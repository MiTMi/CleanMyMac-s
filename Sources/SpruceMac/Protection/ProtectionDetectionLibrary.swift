import Foundation
import SpruceCore

/// The detection data the malware scan and real-time protection use on top of the built-in
/// catalog: Apple's XProtect rules (read from macOS and compiled again only when macOS
/// changes the file) and the cached threat list (Settings › Protection › Download threat
/// list). Thread-safe: scans read it from their own queues, the threat list updater swaps in
/// a new copy after a download.
final class ProtectionDetectionLibrary: @unchecked Sendable {
    let appleRules: ProtectionAppleRulesLoader
    let feedCache: ProtectionThreatFeedCache

    private let lock = NSLock()
    private var threatList: ProtectionThreatListSnapshot?
    private var threatListOn = true

    init(appleRules: ProtectionAppleRulesLoader = ProtectionAppleRulesLoader(),
         feedCache: ProtectionThreatFeedCache = ProtectionThreatFeedCache()) {
        self.appleRules = appleRules
        self.feedCache = feedCache
    }

    /// Follows `SpruceSettings.threatFeedEnabled`. Off: nothing is downloaded and scans use
    /// the built-in catalog only (the cached copy stays on disk for when it's switched on).
    var isThreatListEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return threatListOn
        }
        set {
            lock.lock()
            threatListOn = newValue
            lock.unlock()
        }
    }

    /// What a scanner is built with: the catalog (merged with the threat list while it's on)
    /// and the rule files to run (Apple's XProtect rules first, then the threat list's).
    /// The first call compiles Apple's rules, so call it off the main thread.
    func scannerInputs() -> (catalog: ProtectionThreatCatalog, ruleSources: [ProtectionRuleSource]) {
        var sources: [ProtectionRuleSource] = []
        if let apple = appleRules.load().source { sources.append(apple) }
        guard isThreatListEnabled else { return (.standard, sources) }
        let list = currentThreatList()
        return (list.catalog, sources + list.ruleSources)
    }

    /// The cached threat list, read from disk on first use. While the list is off only its
    /// status is read: the cached files aren't parsed or compiled, so turning the list off
    /// always works around a bad copy.
    func currentThreatList() -> ProtectionThreatListSnapshot {
        lock.lock()
        if let threatList {
            lock.unlock()
            return threatList
        }
        let enabled = threatListOn
        lock.unlock()
        guard enabled else {
            return ProtectionThreatListSnapshot(feed: .empty, rules: nil, status: feedCache.loadStatus())
        }
        let loaded = feedCache.load()
        lock.lock()
        defer { lock.unlock() }
        if let threatList { return threatList }
        threatList = loaded
        return loaded
    }

    /// Uses a freshly stored copy from now on (scans already running keep theirs).
    func replaceThreatList(_ snapshot: ProtectionThreatListSnapshot) {
        lock.lock()
        threatList = snapshot
        lock.unlock()
    }
}
