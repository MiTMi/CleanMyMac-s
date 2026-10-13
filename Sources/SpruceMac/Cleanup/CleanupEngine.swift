import AppKit
import Darwin
import Foundation
import SpruceCore

/// System junk, caches, logs, mail attachments and trash bins.
///
/// CONTRACT (used by AppModel and Checkup — keep these signatures):
/// * `public init()`
/// * `CheckupContributor` conformance (`checkupScan`, `checkupRun`)
/// * `GroupScanner` conformance (`scan`, `perform`) for the module's main review list
///
/// Scanning runs the catalog rules concurrently off the main actor (`CleanupScanner`
/// in SpruceCore does the file system work). Removal always goes through
/// `FileRemover.dispose`: junk inside regenerable zones is deleted, everything else is
/// moved to the Trash, root-owned system caches and logs are retried with one
/// administrator prompt. Run history is recorded by the app (the Cleanup screen's flow,
/// Checkup), not here; `clean(_:progress:)` reports how a run splits for it
/// (`CleanupRunBreakdown`: emptying a Trash bin isn't counted as freed space again).
public final class CleanupEngine: CheckupContributor, GroupScanner, @unchecked Sendable {
    public let module: ModuleID = .cleanup

    private let lock = NSLock()
    private var reviewStorage: [ScanGroup] = []
    private var requestedSections: Set<CleanupSection>?
    private var moduleReport: CleanupScanReport?
    private var checkupReport: CleanupScanReport?
    private var checkupRunReport: CleanupRunReport?
    private var liveTracker: CleanupScanTracker?

    /// Rules scanned at the same time (I/O bound).
    private let concurrency = 4

    public init() {}

    // MARK: State

    public var checkupReview: [ScanGroup] {
        get { locked { reviewStorage } }
        set { locked { reviewStorage = newValue } }
    }

    /// The last report produced by `scan(progress:)` (insights, unavailable categories…).
    public var lastModuleReport: CleanupScanReport? {
        locked { moduleReport }
    }

    /// The last report produced by `checkupScan`.
    public var lastCheckupReport: CleanupScanReport? {
        locked { checkupReport }
    }

    /// The last `checkupRun`, with the split the activity history should record
    /// (`CleanupHistory.entries(for:date:summaryPrefix:)`).
    public var lastCheckupRun: CleanupRunReport? {
        locked { checkupRunReport }
    }

    /// Per-section progress of the running (or last) module scan, in display order.
    /// Empty until the scan has worked out which rules to run.
    public var scanSectionProgress: [CleanupSectionProgress] {
        locked { liveTracker }?.sections ?? []
    }

    /// Limits the next `scan(progress:)` to some sections (e.g. the Trash Bins tool).
    public func requestNextScan(sections: Set<CleanupSection>) {
        locked {
            requestedSections = sections.isEmpty ? nil : sections
            liveTracker = nil
        }
    }

    private func takeRequestedSections() -> Set<CleanupSection> {
        locked {
            let sections = requestedSections ?? Set(CleanupSection.allCases)
            requestedSections = nil
            return sections
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: GroupScanner

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        let sections = takeRequestedSections()
        let report = try await scan(sections: sections, purpose: .module, progress: progress)
        locked { moduleReport = report }
        return report.groups
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        try await clean(items, progress: progress).outcome
    }

    // MARK: CheckupContributor

    public func checkupScan(progress: @escaping ProgressHandler) async throws -> CheckupTile {
        let report = try await scan(sections: Set(CleanupSection.allCases), purpose: .checkup, progress: progress)
        locked {
            checkupReport = report
            reviewStorage = report.groups
        }
        let selected = report.groups.selectedSize
        let found = report.groups.totalSize
        let count = report.groups.selectedItems.count
        let limited = report.isLimitedByFullDiskAccess
        if found == 0 {
            return CheckupTile(module: module, headline: "All clean",
                               detail: limited ? "Grant Full Disk Access to also check Mail and the Trash."
                                               : "No caches, logs or Trash to clear.",
                               status: .clear, reclaimableBytes: 0, actionCount: 0)
        }
        if selected == 0 {
            return CheckupTile(module: module, headline: ByteFormat.string(found),
                               detail: "found — review to choose what to clean", status: .info,
                               isSelected: false, reclaimableBytes: 0, actionCount: 0)
        }
        var detail = "of caches, logs and Trash to clean"
        if limited { detail += " · partial without Full Disk Access" }
        return CheckupTile(module: module, headline: ByteFormat.string(selected), detail: detail, status: .attention,
                           reclaimableBytes: selected, actionCount: count)
    }

    public func checkupRun(progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let items = checkupReview.selectedItems
        guard !items.isEmpty else { return RunOutcome(module: module, summary: "Nothing selected to clean") }
        let report = try await clean(items, progress: progress)
        locked {
            reviewStorage.removeItems(withIDs: Set(report.outcome.removedItemIDs))
            checkupRunReport = report
        }
        return report.outcome
    }

    // MARK: Scanning

    /// Scans the given sections. Rules run concurrently; progress reports the running
    /// total of bytes found.
    public func scan(sections: Set<CleanupSection>, purpose: CleanupScanPurpose,
                     progress: @escaping ProgressHandler) async throws -> CleanupScanReport {
        if purpose == .module { locked { liveTracker = nil } }
        progress(ScanProgress(fraction: nil, message: "Getting ready…"))
        let settings = await MainActor.run { SettingsStore.shared.settings }
        let context = await CleanupSystemProbe.makeContext(purpose: purpose)
        try Self.checkCancellation()
        let scanner = CleanupScanner(context: context, settings: settings, isCancelled: { Task.isCancelled })
        let rules = scanner.rules(for: sections)
        let tracker = CleanupScanTracker(rules: rules, sections: sections, handler: progress)
        if purpose == .module { locked { liveTracker = tracker } }
        let width = concurrency

        let results = try await withThrowingTaskGroup(of: CleanupRuleResult.self,
                                                      returning: [CleanupRuleResult].self) { group in
            var collected: [CleanupRuleResult] = []
            var queue = rules[...]
            for _ in 0..<width {
                guard let rule = queue.popFirst() else { break }
                tracker.started(rule)
                group.addTask {
                    scanner.scan(rule: rule, onProgress: { tracker.visiting($0, title: rule.category.title) })
                }
            }
            while let result = try await group.next() {
                collected.append(result)
                tracker.finished(result)
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let rule = queue.popFirst() {
                    tracker.started(rule)
                    group.addTask {
                        scanner.scan(rule: rule, onProgress: { tracker.visiting($0, title: rule.category.title) })
                    }
                }
            }
            return collected
        }
        try Self.checkCancellation()
        let report = scanner.assemble(results, sections: sections)
        progress(ScanProgress(fraction: 1, message: "Scan complete", bytesFound: report.groups.totalSize))
        return report
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw SpruceError.cancelled }
    }

    // MARK: Cleaning

    private struct Batch {
        var items: [ScanItem]
        var options: PathGuard.Options
        var escalate: Bool
        /// Deletes Trash-bin contents (recorded apart from the rest of the run).
        var emptiesTrash = false
    }

    /// Removes the selected rows. Rows whose owning app is running are skipped;
    /// folder rows are expanded into their current, still-eligible children.
    ///
    /// The report's outcome is what `perform` returns; its breakdown separates emptying
    /// the Trash bins from the rest of the run for the activity history.
    public func clean(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> CleanupRunReport {
        guard !items.isEmpty else {
            return CleanupRunReport(outcome: RunOutcome(module: module, summary: "Nothing selected"),
                                    breakdown: CleanupRunBreakdown())
        }
        progress(ScanProgress(fraction: nil, message: "Checking what's safe to remove…"))
        let settings = await MainActor.run { SettingsStore.shared.settings }
        let context = await CleanupSystemProbe.makeContext(purpose: .module, includeMailAccounts: false)
        let scanner = CleanupScanner(context: context, settings: settings)

        var failures: [ItemFailure] = []
        var removedRows: [String] = []
        var plan: [(row: ScanItem, targets: [ScanItem])] = []
        for item in items {
            if Task.isCancelled { throw SpruceError.cancelled }
            if let reason = scanner.blockingReason(for: item) {
                failures.append(ItemFailure(itemID: item.id, title: item.title, reason: reason))
                continue
            }
            let expansion = scanner.expand(item)
            if let failure = expansion.failure {
                failures.append(ItemFailure(itemID: item.id, title: item.title, reason: failure))
                continue
            }
            if expansion.targets.isEmpty {
                removedRows.append(item.id)   // already gone or nothing left to clean
                continue
            }
            plan.append((item, expansion.targets))
        }

        // Regenerable folders declared by the catalog become permanent-removal zones for
        // this run only, after re-validating that each belongs to its rule.
        var zones = Set<String>()
        var rowOfTarget: [String: ScanItem] = [:]
        var allTargets: [ScanItem] = []
        for entry in plan {
            for target in entry.targets where rowOfTarget[target.id] == nil {
                rowOfTarget[target.id] = entry.row
                allTargets.append(target)
                if let zone = target.metadata[CleanupMetadataKey.zone],
                   let ruleID = target.metadata[CleanupMetadataKey.ruleID],
                   let rule = CleanupCatalog.rule(id: ruleID),
                   CleanupCatalog.isDeclaredZone(zone, rule: rule, context: scanner.context) {
                    zones.insert(zone)
                }
            }
        }
        let remover = FileRemover(guardian: PathGuard(extraPermanentZones: Array(zones)))

        func isTrashBin(_ item: ScanItem) -> Bool { item.metadata[CleanupMetadataKey.category] == CleanupCategory.trashBins.rawValue }
        func isLaunchItem(_ item: ScanItem) -> Bool { item.metadata[CleanupMetadataKey.launchItem] == "1" }
        func needsAdmin(_ item: ScanItem) -> Bool { item.metadata[CleanupMetadataKey.needsAdmin] == "1" }
        let launchItems = allTargets.filter(isLaunchItem)
        let trashBins = allTargets.filter { isTrashBin($0) && !isLaunchItem($0) }
        let adminItems = allTargets.filter { needsAdmin($0) && !isTrashBin($0) && !isLaunchItem($0) }
        let userItems = allTargets.filter { !needsAdmin($0) && !isTrashBin($0) && !isLaunchItem($0) }
        let batches = [
            Batch(items: userItems.filter { $0.deletion == .remove }, options: [], escalate: false),
            Batch(items: userItems.filter { $0.deletion == .trash }, options: [], escalate: false),
            Batch(items: launchItems, options: [.allowLaunchItems], escalate: false),
            // Root-owned system caches and logs: one administrator prompt at most.
            Batch(items: adminItems, options: [], escalate: true),
            // Emptying the Trash: trashed apps are whole bundles, and root-owned items
            // left by installers need the administrator.
            Batch(items: trashBins, options: [.allowAppBundles], escalate: true, emptiesTrash: true),
        ]

        // Unload broken launch agents before their plists move to the Trash.
        let uid = getuid()
        for item in launchItems {
            guard let path = item.url?.path else { continue }
            _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", path], timeout: 10)
        }

        let totalBytes = max(allTargets.reduce(Int64(0)) { $0 + max($1.size, 1) }, 1)
        var processedBytes: Int64 = 0
        /// Deleted outright (including what was emptied from the Trash bins).
        var freed: Int64 = 0
        var emptiedBytes: Int64 = 0
        var trashedBytes: Int64 = 0
        var trashedCount = 0
        var trashRunIDs: [UUID] = []
        var removedTargets = Set<String>()
        var targetFailures: [ItemFailure] = []
        for batch in batches where !batch.items.isEmpty {
            if Task.isCancelled { break }
            let batchBytes = batch.items.reduce(Int64(0)) { $0 + max($1.size, 1) }
            let baseFraction = Double(processedBytes) / Double(totalBytes)
            let share = Double(batchBytes) / Double(totalBytes)
            let freedBefore = freed + trashedBytes
            let outcome = await remover.dispose(batch.items, module: module, options: batch.options, settings: settings,
                                                escalate: batch.escalate, progress: { p in
                progress(ScanProgress(fraction: baseFraction + (p.fraction ?? 0) * share, message: p.message,
                                      current: p.current, bytesFound: freedBefore + p.bytesFound))
            })
            processedBytes += batchBytes
            removedTargets.formUnion(outcome.removedItemIDs)
            targetFailures += outcome.failures
            // FileRemover counts what it moved to the Trash (also as administrator) as
            // freed; keep that part apart, with its ledger runs for Put Back.
            let deleted = max(0, outcome.freedBytes - outcome.trashedBytes)
            freed += deleted
            if batch.emptiesTrash { emptiedBytes += deleted }
            trashedBytes += outcome.trashedBytes
            trashedCount += outcome.trashedCount
            trashRunIDs += outcome.trashRunIDs
        }
        let cancelled = Task.isCancelled

        var failuresByRow: [String: [ItemFailure]] = [:]
        for failure in targetFailures {
            let rowID = rowOfTarget[failure.itemID]?.id ?? failure.itemID
            failuresByRow[rowID, default: []].append(failure)
        }
        for entry in plan {
            if entry.targets.allSatisfy({ removedTargets.contains($0.id) }) {
                removedRows.append(entry.row.id)
            } else if let rowFailures = failuresByRow[entry.row.id], let first = rowFailures.first {
                let reason = rowFailures.count == 1
                    ? first.reason
                    : "\(CountFormat.items(rowFailures.count)) couldn't be removed — \(first.reason)"
                failures.append(ItemFailure(itemID: entry.row.id, title: entry.row.title, reason: reason))
            } else if cancelled {
                failures.append(ItemFailure(itemID: entry.row.id, title: entry.row.title, reason: "Stopped before this item"))
            }
        }

        let trashBinRows = Set(items.filter(isTrashBin).map(\.id))
        let emptiedRows = removedRows.filter { trashBinRows.contains($0) }.count
        let breakdown = CleanupRunBreakdown(
            cleanedCount: removedRows.count - emptiedRows, deletedBytes: freed - emptiedBytes,
            trashedCount: trashedCount, trashedBytes: trashedBytes,
            emptiedCount: emptiedRows, emptiedBytes: emptiedBytes
        )
        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: freed + trashedBytes))
        let outcome = RunOutcome(
            module: module,
            freedBytes: freed + trashedBytes,
            processedCount: removedRows.count,
            removedItemIDs: removedRows,
            failures: failures,
            summary: CleanupHistory.runSummary(breakdown),
            trashedBytes: trashedBytes,
            trashedCount: trashedCount,
            trashRunIDs: trashRunIDs
        )
        return CleanupRunReport(outcome: outcome, breakdown: breakdown)
    }
}

/// Aggregates progress from concurrently scanned rules (throttled to ~10 updates/s)
/// and keeps the per-section tally the scanning checklist reads.
private final class CleanupScanTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: ProgressHandler
    private var tally: CleanupScanTally
    private var lastEmit = Date.distantPast

    init(rules: [CleanupRule], sections: Set<CleanupSection>, handler: @escaping ProgressHandler) {
        tally = CleanupScanTally(rules: rules, sections: sections)
        self.handler = handler
    }

    var sections: [CleanupSectionProgress] {
        lock.lock()
        defer { lock.unlock() }
        return tally.sections
    }

    func started(_ rule: CleanupRule) {
        lock.lock()
        tally.start(rule)
        lock.unlock()
    }

    func visiting(_ path: String, title: String) {
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= 0.1 else {
            lock.unlock()
            return
        }
        lastEmit = now
        let update = ScanProgress(fraction: tally.fraction, message: "Looking through \(title)…",
                                  current: path.abbreviatingHome, bytesFound: tally.bytesFound)
        lock.unlock()
        handler(update)
    }

    func finished(_ result: CleanupRuleResult) {
        lock.lock()
        tally.finish(result)
        lastEmit = Date()
        let update = ScanProgress(fraction: tally.fraction, message: "Checked \(result.category.title)",
                                  bytesFound: tally.bytesFound)
        lock.unlock()
        handler(update)
    }
}
