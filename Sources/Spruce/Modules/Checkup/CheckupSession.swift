import AppKit
import Foundation
import Observation
import SpruceCore
import SpruceMac

/// Result of one contributor's `checkupScan`, delivered back to the main actor.
enum CheckupScanResult: Sendable {
    case finished(ModuleID, CheckupTile)
    case failed(ModuleID, String)
    case cancelled(ModuleID)
}

/// Result of one contributor's `checkupRun`.
enum CheckupRunResult: Sendable {
    case done(ModuleID, RunOutcome)
    case failed(ModuleID, String)
}

/// The "Quit these apps first?" sheet shown before a run.
struct CheckupQuitPrompt: Identifiable {
    let id = UUID()
    var apps: [CheckupBlockingApp]
}

/// The Checkup journey (idle → scanning → results → running → done).
///
/// A single shared instance keeps scans, results, review edits and runs alive while
/// the user browses other modules (module views are recreated on navigation). Works
/// only through the `CheckupContributor` protocol; which areas take part is decided
/// by `SpruceSettings.checkupModules`. Nothing is ever acted on until `run()`.
@MainActor
@Observable
final class CheckupSession {
    static let shared = CheckupSession()

    enum Phase: Hashable {
        case idle
        case scanning
        case results
        case running
        case done
    }

    /// Results older than this are flagged as possibly stale.
    nonisolated static let staleAfter: TimeInterval = CheckupScanRequest.staleAfter
    /// How long Quit All waits for the apps to quit before running anyway.
    nonisolated static let quitTimeout: TimeInterval = 20

    private(set) var phase: Phase = .idle
    private(set) var board = CheckupBoard(included: [], available: [])
    private(set) var runBoard: CheckupRunBoard?
    /// Tiles included in Run.
    private(set) var selection: Set<ModuleID> = []
    /// Modules whose review selection the user changed.
    private(set) var reviewEdited: Set<ModuleID> = []
    /// True once the user toggled a tile checkbox.
    private(set) var selectionChanged = false
    /// Modules being scanned again from the results screen.
    private(set) var rescanning: Set<ModuleID> = []
    /// Number of reviewable items each contributor holds (cached; reading an engine's
    /// review copies its whole tree).
    private(set) var reviewItemCounts: [ModuleID: Int] = [:]
    private(set) var scanStartedAt: Date?
    private(set) var scanFinishedAt: Date?
    private(set) var liveMessage = ""
    private(set) var liveCurrent: String?
    /// Combined scan progress shown on the ring; never moves backwards.
    private(set) var displayedFraction: Double = 0
    /// The user pressed Stop during a run: the current area finishes, the rest are skipped.
    private(set) var stopRequested = false
    /// A scan was requested (`checkup.scan`) while stale results hold the user's choices:
    /// the results screen asks before scanning again.
    var scanAgainPrompt = false
    /// A review sheet is open on the results screen (a scan request then leaves it alone).
    var isReviewing = false
    /// Open apps that hold up selected items, asked about before Run (`requestRun()`).
    var quitPrompt: CheckupQuitPrompt?
    /// Apps in the quit sheet that were asked to quit and haven't yet.
    private(set) var quittingApps: Set<Int32> = []
    /// Quit All was pressed: waiting (up to `quitTimeout`) for the apps before running.
    private(set) var isWaitingForApps = false

    @ObservationIgnored private var contributors: [ModuleID: CheckupContributor] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var rescanTasks: [ModuleID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var quitWatchTask: Task<Void, Never>?
    @ObservationIgnored private var quitDeadlines: [Int32: Date] = [:]
    private let throttle = CheckupProgressThrottle(interval: 0.08)

    private init() {}

    // MARK: Derived

    var tiles: [CheckupTile] { board.tiles }

    var summary: CheckupSelectionSummary { CheckupSelectionSummary(tiles: board.tiles, selection: selection) }

    var isBusy: Bool { phase == .scanning || phase == .running || !rescanning.isEmpty }

    /// What the screen holds, for `CheckupScanRequest.response(to:)`.
    var scanRequestScreen: CheckupScanRequest.Screen {
        switch phase {
        case .idle: return .idle
        case .scanning, .running: return .busy
        case .done: return .done
        case .results:
            if !rescanning.isEmpty || isWaitingForApps || quitPrompt != nil || isReviewing { return .busy }
            return .results(finishedAt: scanFinishedAt, hasCustomChoices: hasCustomChoices)
        }
    }

    /// True when Start Over would throw away choices the user made.
    var hasCustomChoices: Bool { selectionChanged || !reviewEdited.isEmpty }

    var scanProgress: ScanProgress {
        ScanProgress(fraction: displayedFraction, message: liveMessage, current: liveCurrent, bytesFound: board.bytesFound)
    }

    func reviewItemCount(_ module: ModuleID) -> Int { reviewItemCounts[module] ?? 0 }

    func hasContributor(_ module: ModuleID) -> Bool { contributors[module] != nil }

    /// A copy of a contributor's reviewable groups (for the review sheet).
    func reviewGroups(for module: ModuleID) -> [ScanGroup] {
        contributors[module]?.checkupReview ?? []
    }

    // MARK: Scan

    /// Scans every included area at the same time.
    func startScan(contributors list: [CheckupContributor], included: [ModuleID]) {
        guard phase != .scanning, phase != .running else { return }
        cancelBackgroundWork()
        generation += 1
        let gen = generation

        var map: [ModuleID: CheckupContributor] = [:]
        for contributor in list where map[contributor.module] == nil {
            map[contributor.module] = contributor
        }
        contributors = map
        board = CheckupBoard(included: Set(included), available: Set(map.keys))
        runBoard = nil
        selection = []
        reviewEdited = []
        selectionChanged = false
        rescanning = []
        reviewItemCounts = [:]
        stopRequested = false
        displayedFraction = 0
        liveMessage = "Getting ready…"
        liveCurrent = nil
        scanStartedAt = Date()
        scanFinishedAt = nil
        throttle.reset()
        phase = .scanning
        SpruceSound.play(.scanStart)

        let jobs: [(ModuleID, CheckupContributor)] = board.pendingModules.compactMap { module in
            map[module].map { (module, $0) }
        }
        guard !jobs.isEmpty else {
            finishScan(generation: gen)
            return
        }
        beginActivity(reason: "Checkup scan")
        let now = Date()
        for (module, _) in jobs { board.start(module, at: now) }

        let report = makeScanReporter(generation: gen)
        let throttle = self.throttle
        scanTask = Task {
            await withTaskGroup(of: CheckupScanResult.self) { group in
                for (module, contributor) in jobs {
                    group.addTask {
                        await CheckupSession.performScan(module: module, contributor: contributor,
                                                         throttle: throttle, report: report)
                    }
                }
                for await result in group {
                    self.apply(result, generation: gen)
                }
            }
            self.finishScan(generation: gen)
        }
    }

    /// Stop: cancels every running scan and returns to the idle screen.
    func stopScan() {
        guard phase == .scanning else { return }
        generation += 1
        scanTask?.cancel()
        scanTask = nil
        endActivity()
        board = CheckupBoard(included: [], available: [])
        displayedFraction = 0
        liveMessage = ""
        liveCurrent = nil
        phase = .idle
    }

    /// Refreshes the time-based part of the combined progress (called by a timer on
    /// the scanning screen so the ring moves even when contributors report no fraction).
    func tick() {
        guard phase == .scanning else { return }
        refreshFraction()
    }

    /// Scans one area again from the results screen (after a failure, or when an area
    /// that was turned off is included).
    func rescan(_ module: ModuleID) {
        guard phase == .results, let contributor = contributors[module], !rescanning.contains(module) else { return }
        board.requeue(module)
        board.start(module)
        selection.remove(module)
        reviewEdited.remove(module)
        rescanning.insert(module)
        let gen = generation
        let report = makeScanReporter(generation: gen)
        let throttle = self.throttle
        rescanTasks[module] = Task {
            let result = await CheckupSession.performScan(module: module, contributor: contributor,
                                                          throttle: throttle, report: report)
            self.finishRescan(module, result: result, generation: gen)
        }
    }

    /// Adds an area that was off in Settings back to Checkup and scans it.
    func include(_ module: ModuleID, settings: SettingsStore) {
        var included = Set(settings.settings.checkupModules)
        included.insert(module)
        settings.settings.checkupModules = ModuleID.checkupContributors.filter { included.contains($0) }
        rescan(module)
    }

    private func apply(_ result: CheckupScanResult, generation gen: Int) {
        guard gen == generation else { return }
        switch result {
        case .finished(let module, var tile):
            if let contributor = contributors[module] {
                // Safety net: contributors filter by the ignore list themselves, but
                // nothing on it may ever reach Run.
                let review = contributor.checkupReview
                let filtered = SettingsStore.shared.settings.filteringIgnored(review)
                if Set(filtered.allItems.map(\.id)) != Set(review.allItems.map(\.id)) {
                    contributor.checkupReview = filtered
                    tile = CheckupReviewAdjustment.adjusted(tile, review: filtered)
                }
                reviewItemCounts[module] = filtered.allItems.count
            } else {
                reviewItemCounts[module] = 0
            }
            board.finish(module, tile: tile)
        case .failed(let module, let reason):
            board.fail(module, reason: reason)
            reviewItemCounts[module] = 0
        case .cancelled(let module):
            board.fail(module, reason: "Stopped before it finished")
            reviewItemCounts[module] = 0
        }
        refreshFraction()
    }

    private func finishScan(generation gen: Int) {
        guard gen == generation, phase == .scanning else { return }
        scanTask = nil
        endActivity()
        scanFinishedAt = Date()
        displayedFraction = 1
        selection = board.defaultSelection
        liveMessage = ""
        liveCurrent = nil
        phase = .results
        if board.hasWork {
            HistoryStore.shared.record(CheckupHistory.scanEntry(tiles: board.tiles))
        }
        if let started = scanStartedAt, Date().timeIntervalSince(started) >= 1.5 {
            SpruceSound.play(.scanComplete)
        }
    }

    private func finishRescan(_ module: ModuleID, result: CheckupScanResult, generation gen: Int) {
        rescanTasks[module] = nil
        guard gen == generation else { return }
        rescanning.remove(module)
        apply(result, generation: gen)
        if let tile = board.tile(for: module), CheckupBoard.isSelectable(tile), tile.isSelected {
            selection.insert(module)
        }
    }

    private func receiveScan(_ module: ModuleID, _ progress: ScanProgress, generation gen: Int) {
        guard gen == generation, phase == .scanning || rescanning.contains(module) else { return }
        board.update(module, progress: progress)
        if phase == .scanning {
            if !progress.message.isEmpty { liveMessage = "\(module.title) · \(progress.message)" }
            if let current = progress.current, !current.isEmpty { liveCurrent = current }
            refreshFraction()
        }
    }

    private func refreshFraction() {
        displayedFraction = max(displayedFraction, board.overallFraction(at: Date()))
    }

    private func makeScanReporter(generation gen: Int) -> @Sendable (ModuleID, ScanProgress) -> Void {
        { module, progress in
            Task { @MainActor in
                self.receiveScan(module, progress, generation: gen)
            }
        }
    }

    nonisolated private static func performScan(module: ModuleID, contributor: CheckupContributor,
                                                throttle: CheckupProgressThrottle,
                                                report: @escaping @Sendable (ModuleID, ScanProgress) -> Void) async -> CheckupScanResult {
        let key = "scan." + module.rawValue
        do {
            try Task.checkCancellation()
            let tile = try await contributor.checkupScan(progress: { progress in
                if throttle.shouldEmit(key: key) { report(module, progress) }
            })
            if Task.isCancelled { return .cancelled(module) }
            return .finished(module, tile)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? SpruceError) == .cancelled {
                return .cancelled(module)
            }
            return .failed(module, error.localizedDescription)
        }
    }

    // MARK: Selection & review

    func toggle(_ module: ModuleID) {
        guard phase == .results, let tile = board.tile(for: module), CheckupBoard.isSelectable(tile),
              !rescanning.contains(module) else { return }
        if selection.contains(module) {
            selection.remove(module)
        } else {
            selection.insert(module)
        }
        selectionChanged = true
    }

    /// Writes an edited review back to its contributor and updates the tile.
    func applyReview(_ module: ModuleID, groups: [ScanGroup]) {
        guard let contributor = contributors[module] else { return }
        guard groups != contributor.checkupReview else { return }
        contributor.checkupReview = groups
        reviewItemCounts[module] = groups.allItems.count
        reviewEdited.insert(module)
        guard let tile = board.tile(for: module) else { return }
        let adjusted = CheckupReviewAdjustment.adjusted(tile, review: groups)
        board.replaceTile(module, with: adjusted)
        if CheckupBoard.isSelectable(adjusted) && adjusted.isSelected {
            selection.insert(module)
        } else {
            selection.remove(module)
        }
    }

    // MARK: Quit apps first

    /// The Run button: first asks to quit open apps that hold up selected items (Cleanup
    /// data of a running app, an update of an open app, maintenance that needs Mail
    /// closed), then runs.
    func requestRun() {
        guard phase == .results, rescanning.isEmpty, !isWaitingForApps, quitPrompt == nil else { return }
        let plan = CheckupRunOrder.plan(for: Set(summary.modules))
        guard !plan.isEmpty else { return }
        let apps = CheckupQuitApps.blockingApps(plan: plan, contributors: contributors)
        guard !apps.isEmpty else {
            run()
            return
        }
        quittingApps = []
        quitDeadlines = [:]
        quitPrompt = CheckupQuitPrompt(apps: apps)
        watchBlockingApps()
    }

    /// The sheet's per-app Quit: asks the app to quit normally (it may ask to save first;
    /// never forced). It leaves the sheet once it has quit; when none are left, Run starts.
    func quitBlockingApp(_ app: CheckupBlockingApp) {
        guard quitPrompt != nil else { return }
        if let running = NSRunningApplication(processIdentifier: app.processID), !running.isTerminated {
            running.terminate()
            quittingApps.insert(app.processID)
            quitDeadlines[app.processID] = Date().addingTimeInterval(Self.quitTimeout)
        }
        pruneQuitPrompt()
    }

    /// Quit All & Run: asks every app to quit normally, waits up to `quitTimeout`, then
    /// runs. Items of apps that are still open are skipped by their area and reported.
    func quitAllBlockingAppsAndRun() {
        guard let prompt = quitPrompt, phase == .results else { return }
        clearQuitPrompt()
        let apps = prompt.apps.compactMap { NSRunningApplication(processIdentifier: $0.processID) }
            .filter { !$0.isTerminated }
        guard !apps.isEmpty else {
            run()
            return
        }
        for app in apps { app.terminate() }
        isWaitingForApps = true
        let pids = apps.map(\.processIdentifier)
        let gen = generation
        let timeout = Self.quitTimeout
        quitWatchTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline, !Task.isCancelled {
                let stillOpen = pids.contains { pid in
                    NSRunningApplication(processIdentifier: pid).map { !$0.isTerminated } ?? false
                }
                if !stillOpen { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled, let session = self else { return }
            session.finishWaitingForApps(generation: gen)
        }
    }

    /// The waiting overlay's Run Now: stops waiting for the apps and runs.
    func runWithoutWaitingForApps() {
        guard isWaitingForApps else { return }
        quitWatchTask?.cancel()
        finishWaitingForApps(generation: generation)
    }

    /// Skip These Items: deselects what the open apps hold up and runs the rest.
    func skipBlockedItemsAndRun() {
        guard let prompt = quitPrompt else { return }
        clearQuitPrompt()
        for (module, ids) in CheckupQuitPlan.itemIDs(of: prompt.apps) {
            guard let contributor = contributors[module] else { continue }
            applyReview(module, groups: CheckupQuitPlan.deselecting(ids, in: contributor.checkupReview))
        }
        run()
    }

    /// Closes the quit sheet without running.
    func cancelQuitPrompt() {
        clearQuitPrompt()
    }

    private func clearQuitPrompt() {
        quitPrompt = nil
        quitWatchTask?.cancel()
        quitWatchTask = nil
        quittingApps = []
        quitDeadlines = [:]
    }

    private func finishWaitingForApps(generation gen: Int) {
        guard isWaitingForApps else { return }
        isWaitingForApps = false
        quitWatchTask = nil
        guard gen == generation, phase == .results else { return }
        run()
    }

    /// Keeps the quit sheet current while it is open: apps that quit (from the sheet or
    /// elsewhere) leave it.
    private func watchBlockingApps() {
        quitWatchTask?.cancel()
        quitWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled, let session = self, session.quitPrompt != nil else { return }
                session.pruneQuitPrompt()
            }
        }
    }

    private func pruneQuitPrompt() {
        guard var prompt = quitPrompt else { return }
        prompt.apps.removeAll { app in
            NSRunningApplication(processIdentifier: app.processID).map(\.isTerminated) ?? true
        }
        let open = Set(prompt.apps.map(\.processID))
        let now = Date()
        // An app that is still open after the timeout (it may have asked to save, and the
        // user kept it) gets its Quit button back.
        let quitting = quittingApps.filter { open.contains($0) && (quitDeadlines[$0].map { $0 > now } ?? false) }
        if quitting != quittingApps { quittingApps = quitting }
        quitDeadlines = quitDeadlines.filter { quitting.contains($0.key) }
        if prompt.apps.isEmpty {
            clearQuitPrompt()
            run()
        } else if prompt.apps != quitPrompt?.apps {
            quitPrompt = prompt
        }
    }

    // MARK: Run

    /// Runs the selected areas one after another. The only entry point that acts.
    func run() {
        guard phase == .results, rescanning.isEmpty else { return }
        let plan = CheckupRunOrder.plan(for: Set(summary.modules))
        guard !plan.isEmpty else { return }
        runBoard = CheckupRunBoard(plan: plan)
        stopRequested = false
        throttle.reset()
        phase = .running
        beginActivity(reason: "Checkup run")
        let gen = generation
        let report = makeRunReporter(generation: gen)
        let throttle = self.throttle
        runTask = Task {
            for module in plan {
                if self.stopRequested || gen != self.generation { break }
                guard let contributor = self.contributors[module] else {
                    self.runBoard?.fail(module, reason: CheckupBoard.unsupportedReason)
                    continue
                }
                self.runBoard?.start(module)
                let result = await CheckupSession.performRun(module: module, contributor: contributor,
                                                             throttle: throttle, report: report)
                guard gen == self.generation else { return }
                self.applyRun(result)
            }
            self.finishRun(generation: gen)
        }
    }

    /// Stop during a run: lets the current area finish (never interrupts mid-way)
    /// and skips the rest.
    func requestStop() {
        guard phase == .running else { return }
        stopRequested = true
    }

    private func applyRun(_ result: CheckupRunResult) {
        switch result {
        case .done(let module, let outcome):
            runBoard?.complete(module, outcome: outcome)
            reviewItemCounts[module] = contributors[module]?.checkupReview.allItems.count ?? 0
        case .failed(let module, let reason):
            runBoard?.fail(module, reason: reason)
        }
    }

    private func finishRun(generation gen: Int) {
        guard gen == generation, phase == .running else { return }
        runTask = nil
        runBoard?.skipRemaining()
        endActivity()
        if let board = runBoard {
            HistoryStore.shared.record(CheckupHistory.runEntries(board, date: Date(), parts: historyParts(for: board)))
        }
        phase = .done
    }

    /// Parts an area reports for the history itself. Cleanup splits emptying the Trash
    /// (recorded as `.other`, so space moved to the Trash earlier is not counted twice)
    /// from the rest of its run, which counts moved-to-Trash bytes as freed.
    private func historyParts(for board: CheckupRunBoard) -> [ModuleID: [CheckupHistoryPart]] {
        var parts: [ModuleID: [CheckupHistoryPart]] = [:]
        if let outcome = board.step(.cleanup)?.outcome,
           let report = (contributors[.cleanup] as? CleanupEngine)?.lastCheckupRun,
           report.outcome == outcome {
            parts[.cleanup] = CleanupHistory.records(for: report).map { record in
                CheckupHistoryPart(kind: record.kind, bytes: max(0, record.outcome.freedBytes),
                                   count: max(0, record.outcome.processedCount), summary: record.outcome.summary)
            }
        }
        return parts
    }

    private func receiveRun(_ module: ModuleID, _ progress: ScanProgress, generation gen: Int) {
        guard gen == generation, phase == .running else { return }
        runBoard?.update(module, progress: progress)
    }

    private func makeRunReporter(generation gen: Int) -> @Sendable (ModuleID, ScanProgress) -> Void {
        { module, progress in
            Task { @MainActor in
                self.receiveRun(module, progress, generation: gen)
            }
        }
    }

    nonisolated private static func performRun(module: ModuleID, contributor: CheckupContributor,
                                               throttle: CheckupProgressThrottle,
                                               report: @escaping @Sendable (ModuleID, ScanProgress) -> Void) async -> CheckupRunResult {
        let key = "run." + module.rawValue
        do {
            let outcome = try await contributor.checkupRun(progress: { progress in
                if throttle.shouldEmit(key: key) { report(module, progress) }
            })
            return .done(module, outcome)
        } catch {
            if error is CancellationError || (error as? SpruceError) == .cancelled {
                return .failed(module, "Stopped before it finished")
            }
            return .failed(module, error.localizedDescription)
        }
    }

    // MARK: Reset

    /// Discards results (Start Over) or leaves the completion screen (Done).
    func startOver() {
        guard phase != .running else { return }
        cancelBackgroundWork()
        generation += 1
        endActivity()
        board = CheckupBoard(included: [], available: [])
        runBoard = nil
        selection = []
        reviewEdited = []
        selectionChanged = false
        rescanning = []
        reviewItemCounts = [:]
        stopRequested = false
        displayedFraction = 0
        liveMessage = ""
        liveCurrent = nil
        scanFinishedAt = nil
        phase = .idle
    }

    private func cancelBackgroundWork() {
        scanTask?.cancel()
        scanTask = nil
        for task in rescanTasks.values { task.cancel() }
        rescanTasks = [:]
        clearQuitPrompt()
        isWaitingForApps = false
        scanAgainPrompt = false
    }

    // MARK: Sleep prevention

    private func beginActivity(reason: String) {
        endActivity()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: reason)
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }
}
