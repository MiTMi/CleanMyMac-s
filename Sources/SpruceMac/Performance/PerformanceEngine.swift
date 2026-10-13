import AppKit
import Foundation
import SpruceCore

/// Progress of a maintenance run, per task.
public enum PerformanceTaskEvent: Sendable {
    case started(PerformanceTaskID)
    case finished(PerformanceTaskRunResult)
}

/// Maintenance tasks, login & background items, heavy consumers.
///
/// CONTRACT (used by AppModel and Checkup — keep these signatures):
/// * `public init()`
/// * `CheckupContributor` conformance (`checkupScan`, `checkupRun`)
/// * `GroupScanner` conformance (`scan`, `perform`) for the module's main review list
///   (the maintenance tasks).
///
/// Root work goes through `PrivilegedRunner` only, batched into one administrator prompt
/// per run; files leave the disk only through `FileRemover`.
public final class PerformanceEngine: CheckupContributor, GroupScanner, @unchecked Sendable {
    public let module: ModuleID = .performance

    /// Guards `reviewStorage`: Checkup scans and runs write it off the main actor while the
    /// review sheet reads and edits it on the main actor.
    private let reviewLock = NSLock()
    private var reviewStorage: [ScanGroup] = []

    public var checkupReview: [ScanGroup] {
        get { lockedReview { $0 } }
        set { lockedReview { $0 = newValue } }
    }

    private func lockedReview<T>(_ body: (inout [ScanGroup]) -> T) -> T {
        reviewLock.lock()
        defer { reviewLock.unlock() }
        return body(&reviewStorage)
    }

    /// The user's settings, read on the main actor (Settings edits them there at any time).
    func currentSettings() async -> SpruceSettings {
        await MainActor.run { SettingsStore.shared.settings }
    }

    let defaults: UserDefaults
    static let lastRunPrefix = "Spruce.Performance.lastRun."
    static let disabledLoginItemsKey = "Spruce.Performance.disabledLoginItems"
    public static let cancelledDetail = "You cancelled the administrator prompt"

    public init() {
        defaults = .standard
    }

    // MARK: - Tasks

    /// Tasks whose tools exist on this Mac (e.g. no housekeeping scripts on macOS 15+).
    public func availableTasks() -> [PerformanceTaskDefinition] {
        PerformanceTaskCatalog.available { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func lastRun(of id: PerformanceTaskID) -> Date? {
        let value = defaults.double(forKey: Self.lastRunPrefix + id.rawValue)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    public func recordedLastRuns() -> [PerformanceTaskID: Date] {
        var out: [PerformanceTaskID: Date] = [:]
        for id in PerformanceTaskID.allCases {
            if let date = lastRun(of: id) { out[id] = date }
        }
        return out
    }

    func recordRun(_ id: PerformanceTaskID, at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastRunPrefix + id.rawValue)
    }

    /// Measures the Mac and assesses every available task.
    public func assessTasks() async -> [PerformanceTaskState] {
        let conditions = await PerformanceSystemProbe.conditions()
        return PerformanceRecommender.states(for: availableTasks(), recorded: recordedLastRuns(), conditions: conditions)
    }

    /// Apps that are open and must be closed before the given tasks can run.
    public func appsBlocking(_ ids: [PerformanceTaskID]) -> [PerformanceAppToQuit] {
        var seen = Set<String>()
        var out: [PerformanceAppToQuit] = []
        for id in ids {
            for app in PerformanceTaskCatalog.definition(id).appsToQuit
            where PerformanceSystemProbe.isRunning(bundleID: app.bundleID) && seen.insert(app.bundleID).inserted {
                out.append(app)
            }
        }
        return out
    }

    /// Asks an app to quit normally and waits for it. Never force-quits (unsaved work).
    public func quitApp(bundleID: String, timeout: TimeInterval = 10) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return true }
        for app in running { app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !PerformanceSystemProbe.isRunning(bundleID: bundleID) { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return !PerformanceSystemProbe.isRunning(bundleID: bundleID)
    }

    /// Runs tasks in catalog order: steps that run as you first, then every administrator
    /// command in one prompt. Returns one result per task (in run order) and records last-run
    /// dates. Never throws; a cancelled prompt marks the root tasks as skipped.
    public func runTasks(_ ids: [PerformanceTaskID], progress: @escaping ProgressHandler,
                         onEvent: (@Sendable (PerformanceTaskEvent) -> Void)? = nil) async -> [PerformanceTaskRunResult] {
        let ordered = PerformanceTaskCatalog.ordered(ids)
        guard !ordered.isEmpty else { return [] }
        let available = Set(availableTasks().map(\.id))
        var results: [PerformanceTaskID: PerformanceTaskRunResult] = [:]
        var userDetails: [PerformanceTaskID: String] = [:]
        let total = Double(ordered.count)

        func finish(_ result: PerformanceTaskRunResult) {
            results[result.id] = result
            if result.status == .done { recordRun(result.id, at: result.date) }
            onEvent?(.finished(result))
        }

        // 1. Work that runs as the current user.
        for id in ordered {
            let def = PerformanceTaskCatalog.definition(id)
            if Task.isCancelled {
                finish(PerformanceTaskRunResult(id: id, status: .skipped, detail: "Stopped before it ran"))
                continue
            }
            guard available.contains(id) else {
                finish(PerformanceTaskRunResult(id: id, status: .skipped, detail: "Not available on this version of macOS"))
                continue
            }
            guard !def.userSteps.isEmpty else { continue }
            onEvent?(.started(id))
            progress(ScanProgress(fraction: Double(results.count) / total, message: "\(def.title)…", current: def.title))
            let outcome = await runUserSteps(of: def)
            switch outcome.status {
            case .done where !def.privilegedCommands.isEmpty:
                userDetails[id] = outcome.detail
            default:
                finish(PerformanceTaskRunResult(id: id, status: outcome.status, detail: outcome.detail, freedBytes: outcome.freed))
            }
        }

        // 2. All administrator commands, one prompt.
        let adminIDs = ordered.filter { results[$0] == nil && !PerformanceTaskCatalog.definition($0).privilegedCommands.isEmpty }
        if !adminIDs.isEmpty {
            if Task.isCancelled {
                for id in adminIDs { finish(PerformanceTaskRunResult(id: id, status: .skipped, detail: "Stopped before it ran")) }
            } else {
                await runAdminBatch(adminIDs, userDetails: userDetails, completed: results.count, total: total,
                                    progress: progress, onEvent: onEvent, finish: finish)
            }
        }

        progress(ScanProgress(fraction: 1, message: "Done"))
        return ordered.compactMap { results[$0] }
    }

    private func runAdminBatch(_ ids: [PerformanceTaskID], userDetails: [PerformanceTaskID: String], completed: Int,
                               total: Double, progress: @escaping ProgressHandler,
                               onEvent: (@Sendable (PerformanceTaskEvent) -> Void)?,
                               finish: (PerformanceTaskRunResult) -> Void) async {
        let commands = PerformanceTaskCatalog.privilegedBatch(for: ids).compactMap(PrivilegedRunner.PrivilegedCommand.init(rawValue:))
        for id in ids { onEvent?(.started(id)) }
        let titles = ids.map { PerformanceTaskCatalog.definition($0).title }
        progress(ScanProgress(fraction: Double(completed) / total, message: "Waiting for administrator approval…",
                              current: titles.joined(separator: ", ")))
        let memoryBefore = PerformanceSystemProbe.memory()
        let diskBefore = PerformanceSystemProbe.disk()
        do {
            try await PrivilegedRunner.shared.run(commands)
            progress(ScanProgress(fraction: Double(completed + ids.count) / total, message: "Measuring the results…"))
            if ids.contains(.purgeableSpace) || ids.contains(.freeRAM) {
                // macOS reclaims purgeable space and pages with a short delay.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            let memoryAfter = PerformanceSystemProbe.memory()
            let diskAfter = PerformanceSystemProbe.disk()
            let diskFreed = max(0, (diskAfter?.free ?? 0) - (diskBefore?.free ?? 0))
            for id in ids {
                let detail = Self.adminDetail(id, memoryBefore: memoryBefore, memoryAfter: memoryAfter, diskFreed: diskFreed)
                let combined = [userDetails[id], detail].compactMap { $0 }.joined(separator: " ")
                finish(PerformanceTaskRunResult(id: id, status: .done, detail: combined,
                                                freedBytes: id == .purgeableSpace ? diskFreed : 0))
            }
        } catch {
            let cancelled = (error as? SpruceError) == .cancelled
            for id in ids {
                finish(PerformanceTaskRunResult(id: id, status: cancelled ? .skipped : .failed,
                                                detail: cancelled ? Self.cancelledDetail : error.localizedDescription))
            }
        }
    }

    static func adminDetail(_ id: PerformanceTaskID, memoryBefore: PerformanceMemoryReading?,
                            memoryAfter: PerformanceMemoryReading?, diskFreed: Int64) -> String {
        switch id {
        case .freeRAM:
            if let before = memoryBefore, let after = memoryAfter, after.free > before.free {
                return "Free memory went from \(ByteFormat.string(before.free)) to \(ByteFormat.string(after.free))."
            }
            return "The memory cache was emptied."
        case .purgeableSpace:
            if diskFreed >= 50_000_000 { return "Recovered \(ByteFormat.string(diskFreed))." }
            return "macOS kept its purgeable data for now. It frees that space by itself as soon as it's needed."
        case .flushDNS:
            return "The DNS cache was cleared."
        case .maintenanceScripts:
            return "The daily, weekly and monthly scripts finished."
        case .reindexSpotlight:
            return "Spotlight is rebuilding its index in the background. Search results stay incomplete until it's done."
        case .repairHomePermissions:
            return "Permissions in your home folder were reset."
        case .clearFontCaches:
            return "Restart your Mac to finish."
        case .speedUpMail, .rebuildLaunchServices, .resetQuickLook:
            return "Done."
        }
    }

    // MARK: User-context steps

    struct StepOutcome {
        var status: PerformanceTaskRunStatus
        var detail: String
        var freed: Int64 = 0

        static func failed(_ detail: String) -> StepOutcome { StepOutcome(status: .failed, detail: detail) }
        static func skipped(_ detail: String) -> StepOutcome { StepOutcome(status: .skipped, detail: detail) }
    }

    private func runUserSteps(of def: PerformanceTaskDefinition) async -> StepOutcome {
        var details: [String] = []
        var freed: Int64 = 0
        for step in def.userSteps {
            switch step {
            case .user(let executable, let arguments):
                let result = await Shell.run(executable, arguments, timeout: 180)
                guard result.status == 0 else { return .failed(Self.commandFailure(result, executable: executable)) }
            case .builtin(.compactMailIndex):
                let outcome = await compactMailIndex()
                guard outcome.status == .done else { return outcome }
                details.append(outcome.detail)
                freed += outcome.freed
            case .builtin(.unregisterStaleLaunchServices):
                let outcome = await unregisterStaleLaunchServices()
                guard outcome.status == .done else { return outcome }
                details.append(outcome.detail)
            case .privileged:
                continue
            }
        }
        if details.isEmpty {
            switch def.id {
            case .resetQuickLook: details.append("Thumbnails and previews were reset.")
            case .clearFontCaches: details.append("Font caches were cleared.")
            default: details.append("Done.")
            }
        }
        return StepOutcome(status: .done, detail: details.joined(separator: " "), freed: freed)
    }

    static func commandFailure(_ result: Shell.Result, executable: String) -> String {
        commandFailure(status: result.status, stderr: result.stderr, executable: executable)
    }

    static func commandFailure(status: Int32, stderr: String, executable: String) -> String {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let tool = (executable as NSString).lastPathComponent
        if message.isEmpty { return "\(tool) stopped with error \(status)." }
        let firstLine = message.components(separatedBy: "\n").first ?? message
        return "\(tool): \(firstLine)"
    }

    /// `PRAGMA integrity_check` then `VACUUM` on Mail's Envelope Index, with Mail closed.
    private func compactMailIndex() async -> StepOutcome {
        let mail = PerformanceTaskCatalog.mail
        if PerformanceSystemProbe.isRunning(bundleID: mail.bundleID) {
            return .failed("Mail is open. Quit Mail, then run this task again.")
        }
        let home = NSHomeDirectory()
        guard let path = PerformanceMailIndex.locate(home: home) else {
            let mailRoot = (home as NSString).appendingPathComponent("Library/Mail")
            if FileManager.default.fileExists(atPath: mailRoot),
               (try? FileManager.default.contentsOfDirectory(atPath: mailRoot)) == nil {
                return .failed("Spruce needs Full Disk Access to reach Mail's database.")
            }
            return .skipped("Mail has no local mailboxes on this Mac.")
        }
        let before = PerformanceSystemProbe.mailIndexSize(path)
        if let disk = PerformanceSystemProbe.disk(path: home), disk.free < before * 2 + 500_000_000 {
            return .failed("There isn't enough free space to compact Mail's database safely. Free up \(ByteFormat.string(before * 2)) first.")
        }
        let check = await Shell.run("/usr/bin/sqlite3", [path, "PRAGMA integrity_check;"], timeout: 600)
        guard check.status == 0 else {
            let reason = check.stderr.lowercased()
            if reason.contains("authorization") || reason.contains("not permitted") || reason.contains("unable to open") {
                return .failed("Spruce needs Full Disk Access to reach Mail's database.")
            }
            return .failed(Self.commandFailure(check, executable: "/usr/bin/sqlite3"))
        }
        guard PerformanceSystemParsers.integrityOK(check.stdout) else {
            return .failed("Mail's database reported problems, so Spruce left it alone. Mail repairs it the next time it opens.")
        }
        if PerformanceSystemProbe.isRunning(bundleID: mail.bundleID) {
            return .failed("Mail was opened while Spruce was checking its database. Quit Mail and try again.")
        }
        let vacuum = await Shell.run("/usr/bin/sqlite3", [path, "VACUUM;"], timeout: 3600)
        guard vacuum.status == 0 else {
            return .failed("Compacting didn't finish: " + Self.commandFailure(vacuum, executable: "/usr/bin/sqlite3"))
        }
        let after = PerformanceSystemProbe.mailIndexSize(path)
        let freed = max(0, before - after)
        let detail = freed >= 1_000_000 ? "Mail's database is \(ByteFormat.string(freed)) smaller."
            : "Mail's database was already compact."
        return StepOutcome(status: .done, detail: detail, freed: freed)
    }

    /// Unregisters Launch Services records of apps that no longer exist, then garbage-collects.
    /// (`lsregister -kill` was removed by Apple, and the database is per user.)
    private func unregisterStaleLaunchServices() async -> StepOutcome {
        let tool = PerformanceTaskCatalog.lsregisterPath
        // The dump can be hundreds of MB: read it as it arrives and keep only the app paths.
        let collector = PerformanceDumpCollector()
        let dump = await PerformanceStreamingShell.run(tool, ["-dump"], timeout: 300) { chunk in
            collector.reader.consume(chunk)
        }
        collector.reader.finish()
        if Task.isCancelled { return .skipped("Stopped before it finished") }
        guard collector.reader.byteCount > 0 else {
            return .failed("Couldn't read the Launch Services database. "
                           + Self.commandFailure(status: dump.status, stderr: dump.stderr, executable: tool))
        }
        let stale = PerformanceLaunchServices.stalePaths(from: collector.reader.paths,
                                                         fileExists: { FileManager.default.fileExists(atPath: $0) })
        for path in stale {
            if Task.isCancelled { break }
            // `-u` exits non-zero for paths it no longer knows; the dump decides what's left.
            _ = await Shell.run(tool, ["-u", path], timeout: 30)
        }
        let gc = await Shell.run(tool, ["-gc"], timeout: 300)
        if gc.status != 0 && stale.isEmpty {
            return .failed(Self.commandFailure(gc, executable: tool))
        }
        if stale.isEmpty { return StepOutcome(status: .done, detail: "No outdated entries were found; the database was tidied.") }
        return StepOutcome(status: .done,
                           detail: "Removed \(CountFormat.items(stale.count, singular: "entry", plural: "entries")) for apps that are no longer on your Mac.")
    }

    // MARK: - GroupScanner (the maintenance list)

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        progress(ScanProgress(fraction: nil, message: "Checking what your Mac needs…"))
        let states = await assessTasks()
        try Task.checkCancellation()
        let settings = await currentSettings()
        progress(ScanProgress(fraction: 1, message: "Done"))
        return settings.filteringIgnored([PerformanceTaskItems.group(for: states, onlyRecommended: false)])
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let ids = PerformanceTaskItems.taskIDs(in: items)
        guard !ids.isEmpty else { return RunOutcome(module: module, summary: "No maintenance tasks selected") }
        let results = await runTasks(ids, progress: progress)
        if results.allSatisfy({ $0.status == .skipped && $0.detail == Self.cancelledDetail }) {
            throw SpruceError.cancelled
        }
        return PerformanceRunSummary.outcome(results)
    }

    // MARK: - CheckupContributor

    public func checkupScan(progress: @escaping ProgressHandler) async throws -> CheckupTile {
        progress(ScanProgress(fraction: nil, message: "Checking maintenance tasks…"))
        let states = await assessTasks()
        // A stopped scan must not replace the review of the scan that follows it.
        try Task.checkCancellation()
        let group = PerformanceTaskItems.group(for: states, onlyRecommended: true)
        let review = await currentSettings().filteringIgnored(group.isEmpty ? [] : [group])
        try Task.checkCancellation()
        checkupReview = review
        let kept = Set(review.allItems.map(\.id))
        progress(ScanProgress(fraction: 1, message: "Done"))
        return PerformanceTaskItems.checkupTile(for: states.filter { kept.contains($0.id.itemID) })
    }

    public func checkupRun(progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let ids = PerformanceTaskItems.taskIDs(in: checkupReview.selectedItems)
        guard !ids.isEmpty else { return RunOutcome(module: module, summary: "No maintenance tasks selected") }
        // Checkup never interrupts with a quit dialog: tasks whose apps are open report it.
        let results = await runTasks(ids, progress: progress)
        let outcome = PerformanceRunSummary.outcome(results)
        let done = Set(outcome.removedItemIDs)
        lockedReview { $0.removeItems(withIDs: done) }
        return outcome
    }
}
