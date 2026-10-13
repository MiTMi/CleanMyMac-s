import Foundation

// The malware scanner's extra detection data and what the macOS layer keeps of it:
// Apple's XProtect rules (read from macOS, compiled once per version of the file) and
// Spruce's downloaded threat list (feed.json + rules.yara, cached in Application Support).
// Networking lives in the macOS layer; this file decides what a download means, stores it
// and reads it back.

// MARK: - Apple's XProtect rules

/// What the Protection screens show about Apple's XProtect rules.
public struct ProtectionAppleRulesStatus: Sendable, Equatable {
    /// The rule file in use, or the one that couldn't be used.
    public var path: String?
    /// XProtect's version, read from the bundle the rules came from.
    public var version: String?
    /// When macOS last changed the rule file.
    public var modified: Date?
    /// Rules that can report a match.
    public var activeRuleCount: Int
    /// Rules Spruce doesn't use (syntax it doesn't support, or they match ordinary files).
    public var skippedRuleCount: Int
    /// Why the rules aren't used, when they aren't.
    public var unavailableReason: String?
    /// Plain lines about rules that aren't used, for a diagnostics view.
    public var notes: [String]

    public init(path: String? = nil, version: String? = nil, modified: Date? = nil, activeRuleCount: Int = 0,
                skippedRuleCount: Int = 0, unavailableReason: String? = nil, notes: [String] = []) {
        self.path = path
        self.version = version
        self.modified = modified
        self.activeRuleCount = activeRuleCount
        self.skippedRuleCount = skippedRuleCount
        self.unavailableReason = unavailableReason
        self.notes = notes
    }

    public var isAvailable: Bool { unavailableReason == nil && activeRuleCount > 0 }

    /// One line for Settings ("Version 5297 · 182 rules"), or why the rules aren't used.
    public var summary: String {
        guard isAvailable else { return unavailableReason ?? "Not available" }
        var parts: [String] = []
        if let version { parts.append("Version \(version)") }
        parts.append(CountFormat.items(activeRuleCount, singular: "rule"))
        return parts.joined(separator: " · ")
    }

    static let notFound = "macOS's XProtect rules weren't found on this Mac."
    static let unreadable = "Spruce couldn't read macOS's XProtect rules."
    static let tooLarge = "macOS's XProtect rules file is larger than expected, so Spruce doesn't read it."
    static let noUsableRules = "None of the rules in macOS's XProtect file could be used."
}

/// Loads Apple's XProtect rules and keeps them compiled until macOS changes the file.
///
/// Every `load()` looks at the files' size, modification date and inode (cheap); the rules
/// are only read and compiled again when one of those changed. The first location that has
/// usable rules wins (the macOS 15+ copy in /private/var/protected comes first). Safe to call
/// from any thread; compiling holds a lock, so concurrent callers wait for one compile.
public final class ProtectionAppleRulesLoader: @unchecked Sendable {
    /// Rule files, preferred first.
    public let paths: [String]

    private struct FileKey: Equatable {
        var size: Int64
        var modified: Date
        var inode: UInt64
        var device: UInt64
        var isRegularFile: Bool
    }

    private struct Entry {
        var keys: [FileKey?]
        var source: ProtectionRuleSource?
        var status: ProtectionAppleRulesStatus
    }

    private let lock = NSLock()
    private var cache: Entry?
    private var compileCount = 0

    /// `paths` defaults to macOS's two locations (`ProtectionRuleSource.appleXProtectPaths`).
    public init(paths: [String] = ProtectionRuleSource.appleXProtectPaths) {
        self.paths = paths
    }

    /// The rules (nil when none are usable) and their status.
    public func load() -> (source: ProtectionRuleSource?, status: ProtectionAppleRulesStatus) {
        let keys = paths.map(Self.fileKey)
        lock.lock()
        defer { lock.unlock() }
        if let cache, cache.keys == keys { return (cache.source, cache.status) }
        let loaded = Self.compile(paths: paths)
        compileCount += 1
        cache = Entry(keys: keys, source: loaded.source, status: loaded.status)
        return loaded
    }

    /// The status, loading the rules when needed.
    public var status: ProtectionAppleRulesStatus { load().status }

    /// How many times the rules were compiled (tests).
    var compiles: Int {
        lock.lock()
        defer { lock.unlock() }
        return compileCount
    }

    /// The file's identity (symbolic links followed), nil when it doesn't exist.
    private static func fileEntry(_ path: String) -> FileEntry? {
        FileWalker.entry(at: (path as NSString).resolvingSymlinksInPath)
    }

    private static func fileKey(_ path: String) -> FileKey? {
        guard let entry = fileEntry(path) else { return nil }
        return FileKey(size: entry.logicalSize, modified: entry.modified, inode: entry.inode, device: entry.device,
                       isRegularFile: entry.isRegularFile)
    }

    private static func compile(paths: [String]) -> (source: ProtectionRuleSource?, status: ProtectionAppleRulesStatus) {
        var fallback: ProtectionAppleRulesStatus?
        let limit = ProtectionRuleSource.maxAppleRulesBytes
        for path in paths {
            guard let entry = fileEntry(path) else { continue }
            let modified = entry.modified
            let version = bundleVersion(forRuleFile: path)
            func problem(_ reason: String) -> ProtectionAppleRulesStatus {
                ProtectionAppleRulesStatus(path: path, version: version, modified: modified, unavailableReason: reason)
            }
            guard entry.isRegularFile else {
                fallback = fallback ?? problem(ProtectionAppleRulesStatus.unreadable)
                continue
            }
            guard entry.logicalSize <= Int64(limit) else {
                fallback = problem(ProtectionAppleRulesStatus.tooLarge)
                continue
            }
            guard let (data, _) = YaraRuleSet.readPrefix(ofFile: path, maxBytes: limit) else {
                fallback = problem(ProtectionAppleRulesStatus.unreadable)
                continue
            }
            let source = ProtectionRuleSource.appleXProtect(
                YaraRuleSet(data: data, origin: ProtectionRuleSource.appleXProtectName), location: path)
            let status = ProtectionAppleRulesStatus(
                path: path, version: version, modified: modified, activeRuleCount: source.activeRuleCount,
                skippedRuleCount: source.rules.skipped.count + source.disabledRules.count,
                unavailableReason: source.isEmpty ? ProtectionAppleRulesStatus.noUsableRules : nil, notes: source.notes)
            if !source.isEmpty { return (source, status) }
            fallback = status
        }
        return (nil, fallback ?? ProtectionAppleRulesStatus(unavailableReason: ProtectionAppleRulesStatus.notFound))
    }

    /// XProtect's version from the Info.plist of the bundle holding `path`
    /// (…/XProtect.bundle/Contents/Resources/XProtect.yara → …/Contents/Info.plist).
    static func bundleVersion(forRuleFile path: String) -> String? {
        let contents = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        guard let data = FileManager.default.contents(atPath: (contents as NSString).appendingPathComponent("Info.plist")) else {
            return nil
        }
        return ProtectionAppleSecurityParser.bundleVersion(plistData: data)
    }
}

// MARK: - Threat list cache

/// One download as the macOS layer saw it.
public enum ProtectionDownload: Sendable, Equatable {
    /// A complete answer (HTTP 200) with its ETag, when the server sent one.
    case downloaded(Data, etag: String?)
    /// HTTP 304: the cached copy is current.
    case notModified
    /// Network trouble, an error status, a refused redirect or an oversized answer.
    case failed(String)
    /// Not asked (for example when only one of the two files is fetched).
    case skipped
}

/// The threat list as the scanner uses it: the cached feed merged into a catalog, and the
/// cached rules.
public struct ProtectionThreatListSnapshot: Sendable {
    public var feed: ProtectionThreatFeed
    /// The cached rules.yara, nil when there is none.
    public var rules: ProtectionRuleSource?
    public var status: ProtectionThreatFeedStatus
    /// `base` merged with `feed` (built-in families and indicators win).
    public let catalog: ProtectionThreatCatalog

    public init(feed: ProtectionThreatFeed, rules: ProtectionRuleSource?, status: ProtectionThreatFeedStatus,
                base: ProtectionThreatCatalog = .standard) {
        self.feed = feed
        self.rules = rules
        self.status = status
        catalog = base.merging(feed)
    }

    /// Nothing downloaded yet.
    public static let empty = ProtectionThreatListSnapshot(feed: .empty, rules: nil, status: ProtectionThreatFeedStatus())

    /// Rule sources for the scanner (none when the cached rules file has no usable rules).
    public var ruleSources: [ProtectionRuleSource] {
        guard let rules, !rules.isEmpty else { return [] }
        return [rules]
    }

    /// Downloaded indicators in use.
    public var indicatorCount: Int { catalog.threatListIndicatorCount }
}

/// How a threat list check went (Settings › Protection › Check Now, and before scans).
public struct ProtectionThreatFeedCheckResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// A new copy was stored.
        case updated
        /// The server said the cached copy is current (or sent the same files again).
        case upToDate
        /// Nothing could be stored; the cached copy (or the built-in list) stays in use.
        case failed(String)
        /// Checked less than a day ago (only a forced check ignores this).
        case notDue
        /// Settings › Protection › Download threat list is off.
        case turnedOff
    }

    public var outcome: Outcome
    public var status: ProtectionThreatFeedStatus

    public init(outcome: Outcome, status: ProtectionThreatFeedStatus) {
        self.outcome = outcome
        self.status = status
    }

    /// One plain sentence for Settings.
    public var message: String {
        switch outcome {
        case .updated:
            if let version = status.version, version > 0 { return "The threat list was updated to version \(version)." }
            return "The threat list was updated."
        case .upToDate: return "The threat list is up to date."
        case .failed(let message): return message
        case .notDue: return "The threat list was checked less than a day ago."
        case .turnedOff: return "Threat list downloads are turned off."
        }
    }
}

/// The threat list's files in Application Support (feed.json, rules.yara, status.json).
/// Writes are atomic, and a file that can't be read back is ignored, so a bad copy never
/// stops a scan: the built-in catalog is always there.
public struct ProtectionThreatFeedCache: Sendable {
    public let directory: URL

    public init(directory: URL = ProtectionThreatFeedCache.defaultDirectory) {
        self.directory = directory
    }

    /// ~/Library/Application Support/Spruce/ThreatFeed
    public static var defaultDirectory: URL {
        SprucePaths.applicationSupport.appendingPathComponent("ThreatFeed", isDirectory: true)
    }

    public var feedFile: URL { directory.appendingPathComponent("feed.json") }
    public var rulesFile: URL { directory.appendingPathComponent("rules.yara") }
    public var statusFile: URL { directory.appendingPathComponent("status.json") }

    private var statusStore: JSONFileStore<ProtectionThreatFeedStatus> { JSONFileStore(url: statusFile) }

    public func loadStatus() -> ProtectionThreatFeedStatus {
        statusStore.load() ?? ProtectionThreatFeedStatus()
    }

    public func saveStatus(_ status: ProtectionThreatFeedStatus) {
        try? statusStore.save(status)
    }

    /// The cached list, or the empty one for files that are missing or no longer pass the
    /// checks (a newer Spruce may have tightened them).
    public func load(base: ProtectionThreatCatalog = .standard) -> ProtectionThreatListSnapshot {
        let status = loadStatus()
        return ProtectionThreatListSnapshot(feed: cachedFeed(base: base) ?? .empty, rules: cachedRules(), status: status,
                                            base: base)
    }

    /// ETags to send with the next check. Only offered for files that are actually cached:
    /// a 304 answer for a file Spruce no longer has would leave it with nothing.
    public func conditionalETags(for status: ProtectionThreatFeedStatus) -> (feed: String?, rules: String?) {
        let fm = FileManager.default
        return (fm.fileExists(atPath: feedFile.path) ? status.feedETag : nil,
                fm.fileExists(atPath: rulesFile.path) ? status.rulesETag : nil)
    }

    /// Stores what a check downloaded and records the check. Each file is checked on its own:
    /// a bad feed.json doesn't throw away good rules, and the other way round. A feed with a
    /// lower version than the cached one is ignored.
    public func apply(feed feedDownload: ProtectionDownload, rules rulesDownload: ProtectionDownload,
                      base: ProtectionThreatCatalog = .standard,
                      now: Date = Date()) -> (snapshot: ProtectionThreatListSnapshot, result: ProtectionThreatFeedCheckResult) {
        var status = loadStatus()
        var feed = cachedFeed(base: base)
        var rules = cachedRules()
        var problems: [String] = []
        var stored = false

        switch feedDownload {
        case .downloaded(let data, let etag):
            do {
                let parsed = try ProtectionThreatFeed.parse(data, base: base)
                if !ProtectionThreatFeed.shouldReplace(cachedVersion: feed?.version, with: parsed) {
                    problems.append("The downloaded threat list is older than the one Spruce has, so it was ignored.")
                } else if (try? Data(contentsOf: feedFile)) == data {
                    status.feedETag = etag
                } else {
                    try write(data, to: feedFile)
                    status.feedETag = etag
                    feed = parsed
                    stored = true
                }
            } catch let error as ProtectionThreatFeedError {
                problems.append(error.description)
            } catch {
                problems.append("Spruce couldn't save the threat list.")
            }
        case .failed(let message):
            problems.append(message)
        case .notModified, .skipped:
            break
        }

        switch rulesDownload {
        case .downloaded(let data, let etag):
            do {
                let set = try ProtectionThreatFeed.rules(from: data)
                if (try? Data(contentsOf: rulesFile)) == data {
                    status.rulesETag = etag
                } else {
                    try write(data, to: rulesFile)
                    status.rulesETag = etag
                    rules = ProtectionRuleSource.threatList(set, location: rulesFile.path)
                    stored = true
                }
            } catch let error as ProtectionThreatFeedError {
                problems.append(error.description)
            } catch {
                problems.append("Spruce couldn't save the threat list's rules.")
            }
        case .failed(let message):
            // Both downloads usually fail for the same reason; say it once.
            if !problems.contains(message) { problems.append(message) }
        case .notModified, .skipped:
            break
        }

        let current = feed ?? .empty
        if stored {
            status.recordUpdate(feed: current, rules: rules, at: now)
            if feed == nil { status.version = nil }
        }
        let problem = problems.isEmpty ? nil : problems.joined(separator: " ")
        status.recordCheck(at: now, error: problem)
        saveStatus(status)

        let outcome: ProtectionThreatFeedCheckResult.Outcome
        if stored {
            outcome = .updated
        } else if let problem {
            outcome = .failed(problem)
        } else {
            outcome = .upToDate
        }
        let snapshot = ProtectionThreatListSnapshot(feed: current, rules: rules, status: status, base: base)
        return (snapshot, ProtectionThreatFeedCheckResult(outcome: outcome, status: status))
    }

    /// Removes the cached files (the built-in catalog stays).
    public func clear() {
        let fm = FileManager.default
        for file in [feedFile, rulesFile, statusFile] { try? fm.removeItem(at: file) }
    }

    // MARK: Private

    private func cachedFeed(base: ProtectionThreatCatalog) -> ProtectionThreatFeed? {
        guard let data = try? Data(contentsOf: feedFile) else { return nil }
        return try? ProtectionThreatFeed.parse(data, base: base)
    }

    private func cachedRules() -> ProtectionRuleSource? {
        guard let data = try? Data(contentsOf: rulesFile), let set = try? ProtectionThreatFeed.rules(from: data) else {
            return nil
        }
        return ProtectionRuleSource.threatList(set, location: rulesFile.path)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
