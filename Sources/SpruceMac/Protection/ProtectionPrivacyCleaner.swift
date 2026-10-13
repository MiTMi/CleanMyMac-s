import AppKit
import Darwin
import Foundation
import SpruceCore

/// Summary of the last privacy scan (what the review list alone can't show).
public struct ProtectionPrivacyReport: Sendable, Equatable {
    public var date: Date
    /// Browsers with data on this Mac (titles).
    public var browsersFound: [String]
    /// Sources macOS didn't let Spruce read (Safari without Full Disk Access).
    public var unreadableSources: [String]
    /// Ids of the browsers that were open during the scan.
    public var runningSourceIDs: Set<String>

    public init(date: Date = Date(), browsersFound: [String], unreadableSources: [String], runningSourceIDs: Set<String>) {
        self.date = date
        self.browsersFound = browsersFound
        self.unreadableSources = unreadableSources
        self.runningSourceIDs = runningSourceIDs
    }

    public var needsFullDiskAccess: Bool { !unreadableSources.isEmpty }
}

/// Finds and clears browser and macOS privacy traces.
///
/// Browsers must be quit first (their databases would be rewritten or corrupted); open
/// browsers' items are skipped and reported. Safari's data needs Full Disk Access. Files
/// go through `FileRemover`: permanently only where `PathGuard` allows it (caches),
/// otherwise to the Trash.
public final class ProtectionPrivacyCleaner: GroupScanner, @unchecked Sendable {
    private let state = ProtectionLocked<ProtectionPrivacyReport?>(nil)

    public init() {}

    public var lastReport: ProtectionPrivacyReport? { state.current }

    // MARK: Browsers

    /// Display name of a privacy source ("Google Chrome", "macOS").
    public static func name(ofSource sourceID: String) -> String {
        if sourceID == ProtectionTraceSource.systemID { return "macOS" }
        return ProtectionBrowserID(rawValue: sourceID).flatMap { ProtectionPrivacyCatalog.browser($0)?.name } ?? sourceID
    }

    /// Running instances of the browser behind `sourceID` (empty for macOS traces).
    public static func runningApplications(sourceID: String) -> [NSRunningApplication] {
        guard let id = ProtectionBrowserID(rawValue: sourceID), let browser = ProtectionPrivacyCatalog.browser(id) else { return [] }
        return browser.bundleIDs
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { !$0.isTerminated }
    }

    /// True when a Firefox profile is open in some Firefox (release, Beta, Developer
    /// Edition, Nightly…): its `.parentlock` holds an `fcntl` lock, or its `lock` symlink
    /// names a process that is still alive.
    public static func isGeckoProfileInUse(_ profile: String) -> Bool {
        let parentLock = profile + "/.parentlock"
        let fd = open(parentLock, O_RDONLY | O_NONBLOCK)
        if fd >= 0 {
            defer { close(fd) }
            var probe: flock = .init()
            probe.l_type = Int16(F_WRLCK)
            probe.l_whence = Int16(SEEK_SET)
            probe.l_start = 0
            probe.l_len = 0
            if fcntl(fd, F_GETLK, &probe) == 0, probe.l_type != Int16(F_UNLCK) {
                return true
            }
        }
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: profile + "/lock"),
           let pid = ProtectionPrivacyCatalog.geckoLockOwnerPID(symlinkTarget: target),
           kill(pid, 0) == 0 || errno == EPERM {
            return true
        }
        return false
    }

    /// Ids of the supported browsers that are open right now.
    public static func runningSourceIDs() -> Set<String> {
        Set(ProtectionPrivacyCatalog.browsers.map(\.id.rawValue).filter { !runningApplications(sourceID: $0).isEmpty })
    }

    /// Asks the browsers behind `sourceIDs` to quit (they may ask to save first) and waits up
    /// to `timeout` seconds. Returns the ids of browsers that are still open.
    @MainActor
    public static func quit(sourceIDs: Set<String>, timeout: TimeInterval = 10) async -> Set<String> {
        let apps = sourceIDs.flatMap { runningApplications(sourceID: $0) }
        for app in apps { app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, apps.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return Set(sourceIDs.filter { !runningApplications(sourceID: $0).isEmpty })
    }

    // MARK: GroupScanner

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        let running = Self.runningSourceIDs()
        let scanner = ProtectionPrivacyScanner(space: ProtectionPathSpace(home: NSHomeDirectory()),
                                               quickLookCachePath: ProtectionMac.quickLookCachePath())
        let sources = try await ProtectionMac.runBlocking { (flag: ProtectionCancelFlag) throws -> [ProtectionTraceSource] in
            let found = scanner.scan(progress: progress)
            if flag.isCancelled { throw SpruceError.cancelled }
            return found
        }
        let groups = sources.compactMap { $0.scanGroup(isRunning: running.contains($0.id)) }
        state.current = ProtectionPrivacyReport(
            browsersFound: sources.filter { $0.browser != nil }.map(\.title),
            unreadableSources: sources.filter(\.isUnreadable).map(\.title),
            runningSourceIDs: running.filter { id in sources.contains { $0.id == id } }
        )
        return groups
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let settings = await ProtectionMac.settings()
        let guardian = FileRemover.shared.guardian
        let hasFullDiskAccess = Permissions.hasFullDiskAccess
        var failures: [ItemFailure] = []
        var removed: [String] = []
        var freed: Int64 = 0
        var trashedBytes: Int64 = 0
        var trashedCount = 0
        var trashRunIDs: [UUID] = []

        var disposeItems: [ScanItem] = []
        var filesByPlan: [(plan: ProtectionPrivacyPlan, ids: [String])] = []
        var customPlans: [(plan: ProtectionPrivacyPlan, size: Int64)] = []
        var seen = Set<String>()
        // Plans of which some files were skipped (they stay in the list as not done).
        var partialPlans = Set<String>()

        for item in items {
            guard let plan = ProtectionPrivacyPlan(item: item) else { continue }
            let source = Self.name(ofSource: plan.sourceID)
            let title = "\(source) · \(plan.title)"
            if !Self.runningApplications(sourceID: plan.sourceID).isEmpty {
                failures.append(ItemFailure(itemID: plan.itemID, title: title,
                                            reason: "\(source) is open. Quit it, then clean again."))
                continue
            }
            if plan.sourceID == ProtectionBrowserID.safari.rawValue && !hasFullDiskAccess {
                failures.append(ItemFailure(itemID: plan.itemID, title: title,
                                            reason: "Safari's data needs Full Disk Access. Grant it in System Settings, then try again."))
                continue
            }
            if plan.customAction != nil {
                customPlans.append((plan, item.size))
                continue
            }
            // Firefox channels share one Profiles folder: a profile some Firefox still has
            // open (Developer Edition, Nightly…) is never touched, even if the release
            // browser is closed.
            var files = plan.files
            if plan.sourceID == ProtectionBrowserID.firefox.rawValue,
               let firefox = ProtectionPrivacyCatalog.browser(.firefox) {
                let space = ProtectionPathSpace(home: NSHomeDirectory())
                let dataRoot = space.real(firefox.dataRoot)
                let cacheRoot = firefox.cacheRoot.map { space.real($0) }
                var inUse: [String: Bool] = [:]
                files = files.filter { file in
                    guard let profile = ProtectionPrivacyCatalog.geckoProfileFolder(of: file.path, dataRoot: dataRoot,
                                                                                    cacheRoot: cacheRoot) else { return true }
                    if inUse[profile] == nil { inUse[profile] = Self.isGeckoProfileInUse(profile) }
                    return inUse[profile] != true
                }
                if files.count < plan.files.count {
                    failures.append(ItemFailure(itemID: plan.itemID, title: title,
                                                reason: "A Firefox profile is in use (Firefox, Developer Edition or Nightly is open). Quit it, then clean again."))
                    guard !files.isEmpty else { continue }
                    partialPlans.insert(plan.itemID)
                }
            }
            var ids: [String] = []
            for file in files {
                let url = URL(fileURLWithPath: file.path)
                // Permanent removal only where PathGuard allows it; everything else is recoverable.
                let method: DeletionMethod = file.deletion == .remove && guardian.check(url, method: .remove).isAllowed
                    ? .remove : .trash
                var disposable = ScanItem.file(url, size: DiskUsage.measure(file.path).bytes, safety: .safe,
                                               deletion: method, title: title)
                if let entry = FileWalker.entry(at: file.path) {
                    disposable.metadata[ProtectionMetaKey.inode] = String(entry.inode)
                }
                ids.append(disposable.id)
                if seen.insert(disposable.id).inserted { disposeItems.append(disposable) }
            }
            filesByPlan.append((plan, ids))
        }

        if !disposeItems.isEmpty {
            let outcome = await FileRemover.shared.dispose(disposeItems, module: .protection, settings: settings, progress: { p in
                progress(ScanProgress(fraction: 0.9 * (p.fraction ?? 0), message: p.message, current: p.current,
                                      bytesFound: p.bytesFound))
            })
            freed += outcome.freedBytes
            trashedBytes += outcome.trashedBytes
            trashedCount += outcome.trashedCount
            trashRunIDs += outcome.trashRunIDs
            let done = Set(outcome.removedItemIDs)
            var reasons: [String: String] = [:]
            for failure in outcome.failures where reasons[failure.itemID] == nil {
                reasons[failure.itemID] = failure.reason
            }
            var clearedRecentItems = false
            for (plan, ids) in filesByPlan {
                let missing = ids.filter { !done.contains($0) }
                if missing.isEmpty {
                    if plan.kind == .recentItems { clearedRecentItems = true }
                    // Partly cleaned (a profile was in use): already reported, stays in the list.
                    if !partialPlans.contains(plan.itemID) { removed.append(plan.itemID) }
                } else {
                    let reason = missing.compactMap { reasons[$0] }.first ?? "Some files couldn't be removed."
                    failures.append(ItemFailure(itemID: plan.itemID,
                                                title: "\(Self.name(ofSource: plan.sourceID)) · \(plan.title)",
                                                reason: reason))
                }
            }
            if clearedRecentItems {
                // The recent-items daemon keeps its lists in memory; restart it so it doesn't
                // write the old entries back (launchd starts it again on demand).
                _ = await Shell.run("/usr/bin/killall", ["sharedfilelistd"], timeout: 10)
            }
        }

        for (plan, size) in customPlans {
            progress(ScanProgress(fraction: 0.95, message: "Resetting Quick Look thumbnails…", bytesFound: freed))
            guard plan.customAction == ProtectionTrace.quickLookResetAction else {
                failures.append(ItemFailure(itemID: plan.itemID, title: plan.title, reason: "Unsupported action."))
                continue
            }
            let result = await Shell.run("/usr/bin/qlmanage", ["-r", "cache"], timeout: 30)
            if result.status == 0 {
                removed.append(plan.itemID)
                freed += size
                OperationLog.shared.record(module: .protection, action: "qlmanage-reset", result: "ok", bytes: size,
                                           detail: "Quick Look thumbnail cache")
            } else {
                failures.append(ItemFailure(itemID: plan.itemID, title: plan.title,
                                            reason: ProtectionMac.message(from: result, fallback: "Quick Look couldn't reset its cache.")))
            }
        }

        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: freed))
        let summary = removed.isEmpty
            ? "No privacy items were cleared"
            : "Cleared \(CountFormat.items(removed.count, singular: "privacy item")) · \(ByteFormat.string(freed))"
        return RunOutcome(module: .protection, freedBytes: freed, processedCount: removed.count, removedItemIDs: removed,
                          failures: failures, summary: summary,
                          trashedBytes: trashedBytes, trashedCount: trashedCount, trashRunIDs: trashRunIDs)
    }
}
