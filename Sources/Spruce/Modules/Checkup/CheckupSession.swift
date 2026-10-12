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
    nonisolated static let staleAfter: TimeInterval = 15 * 60

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

    @ObservationIgnored private var contributors: [ModuleID: CheckupContributor] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var rescanTasks: [ModuleID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activity: NSObjectProtocol?
    private let throttle = CheckupProgressThrottle(interval: 0.08)

    private init() {}

    // MARK: Derived

    var tiles: [CheckupTile] { board.tiles }

    var summary: CheckupSelectionSummary { CheckupSelectionSummary(tiles: board.tiles, selection: selection) }

    var isBusy: Bool { phase == .scanning || phase == .running || !rescanning.isEmpty }

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
            let date = Date()
            for entry in CheckupHistory.runEntries(board, date: date) {
                HistoryStore.shared.record(entry)
            }
        }
        phase = .done
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
