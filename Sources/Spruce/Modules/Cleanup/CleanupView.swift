import AppKit
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Cleanup module. CONTRACT: keep the type name `CleanupView` and `init()`.
struct CleanupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CleanupRootScreen(engine: model.cleanup)
    }
}

// MARK: - Screen model

/// A running app whose data is selected for cleaning.
struct CleanupRunningApp: Identifiable {
    let app: NSRunningApplication
    var id: pid_t { app.processIdentifier }
    var name: String { app.localizedName ?? app.bundleIdentifier ?? "App" }
    var bundleID: String? { app.bundleIdentifier }
}

/// The "quit these apps first" prompt.
struct CleanupQuitPrompt: Identifiable {
    let id = UUID()
    var apps: [CleanupRunningApp]
}

/// UI state of the Cleanup module. One instance per engine lives for the whole app
/// session (the module view is recreated on every navigation), so scan results,
/// selection and the current screen survive switching modules.
@MainActor
@Observable
final class CleanupScreenModel {
    enum Route: Equatable {
        case overview
        case review(CleanupSection?)
    }

    let engine: CleanupEngine
    let flow: ScanFlowModel
    var route: Route = .overview
    /// The last finished run. The flow keeps only the part of a run it recorded in the
    /// history (see `CleanupFlowScanner`); the Done screen shows the whole run.
    private(set) var lastRun: CleanupFlowRun?
    /// Insights, unavailable categories and scanned sections of the last module scan.
    private(set) var report: CleanupScanReport?
    var quitPrompt: CleanupQuitPrompt?
    var confirmNonSafe = false
    var confirmStartOver = false
    private(set) var isWaitingForApps = false
    /// The section a card's Clean button applies to; nil cleans everything selected.
    private(set) var cleanScope: CleanupSection?
    private var pendingFocus: CleanupSection?
    private var scanningSections: Set<CleanupSection> = Set(CleanupSection.allCases)
    private var scanStartedAt: Date?
    private var appsBeingQuit: [NSRunningApplication] = []

    /// The shared model for `engine` (created on first use).
    static func shared(for engine: CleanupEngine) -> CleanupScreenModel {
        CleanupScreenRegistry.model(for: engine)
    }

    fileprivate init(engine: CleanupEngine) {
        self.engine = engine
        let scanner = CleanupFlowScanner(engine: engine)
        flow = ScanFlowModel(module: .cleanup, scanner: scanner, historyKind: .clean)
        scanner.flow = flow
        scanner.onRunFinished = { [weak self] run in self?.lastRun = run }
    }

    // MARK: Derived

    var phaseKey: String {
        switch flow.phase {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .results: return route == .overview ? "results" : "review"
        case .running: return "running"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    var scanTitle: String {
        if scanningSections.count == 1, let only = scanningSections.first {
            switch only {
            case .systemJunk: return "Looking for system junk…"
            case .mailAttachments: return "Looking through Mail…"
            case .trashBins: return "Looking in the Trash…"
            }
        }
        return "Looking for junk…"
    }

    /// What the Done screen shows: the whole last run.
    var doneOutcome: RunOutcome? {
        guard let outcome = flow.outcome else { return nil }
        if let run = lastRun, run.flowOutcome == outcome { return run.report.outcome }
        return outcome
    }

    var scannedSections: Set<CleanupSection> {
        report?.scannedSections ?? Set(CleanupSection.allCases)
    }

    func group(for section: CleanupSection) -> ScanGroup? {
        flow.groups.first { $0.id == section.rawValue }
    }

    /// Categories macOS didn't let us scan (missing Full Disk Access, or a denial that
    /// Full Disk Access resolves), with the reason.
    var unavailable: [CleanupUnavailable] {
        report?.unavailable ?? []
    }

    var categoriesNeedingAccess: [CleanupCategory] {
        unavailable.map(\.category)
    }

    func unavailableItems(in section: CleanupSection) -> [CleanupUnavailable] {
        unavailable.filter { $0.category.section == section }
    }

    /// Rows of open apps that stay unchecked (their rule doesn't quit the app).
    var inUseCount: Int {
        flow.groups.allItems.filter {
            $0.metadata[CleanupMetadataKey.inUse] == "1" && $0.metadata[CleanupMetadataKey.quitToClean] != "1"
        }.count
    }

    /// Open apps whose selected caches Clean asks to quit first.
    var appsToQuitCount: Int {
        Set(flow.selectedItems.compactMap { item -> String? in
            guard item.metadata[CleanupMetadataKey.quitToClean] == "1" else { return nil }
            return item.metadata[CleanupMetadataKey.bundleID] ?? item.metadata[CleanupMetadataKey.owner]
        }).count
    }

    var selectionNeedsAdmin: Bool {
        flow.selectedItems.contains { $0.metadata[CleanupMetadataKey.needsAdmin] == "1" }
    }

    var selectionMovesToTrash: Int {
        flow.selectedItems.filter { $0.deletion == .trash }.count
    }

    /// Selected items emptied from a Trash (deleted for good).
    var selectionEmptiesTrash: Int {
        flow.selectedItems.filter(Self.isTrashBinItem).count
    }

    /// What the pending Clean acts on: the selection of `cleanScope`, or all of it.
    var pendingSelection: [ScanItem] {
        guard let scope = cleanScope else { return flow.selectedItems }
        return group(for: scope)?.allItems.filter(\.isSelected) ?? []
    }

    nonisolated static func isTrashBinItem(_ item: ScanItem) -> Bool {
        item.metadata[CleanupMetadataKey.category] == CleanupCategory.trashBins.rawValue
    }

    /// The scanning checklist (only when more than one section is scanned).
    var scanSteps: [PrismScanStep] {
        guard scanningSections.count > 1 else { return [] }
        var live: [CleanupSection: CleanupSectionProgress] = [:]
        for progress in engine.scanSectionProgress { live[progress.section] = progress }
        return CleanupSection.allCases.filter { scanningSections.contains($0) }.map { section in
            PrismScanStep(id: section.rawValue, title: section.title, symbol: section.symbol,
                          state: live[section].map(Self.stepState) ?? .waiting)
        }
    }

    nonisolated private static func stepState(_ progress: CleanupSectionProgress) -> PrismScanStep.State {
        switch progress.status {
        case .waiting: return .waiting
        case .running: return .running
        case .found(let bytes): return .done(ByteFormat.string(bytes))
        case .nothingFound: return .done("Nothing found")
        case .unavailable(let reason): return .skipped(reason)
        case .excluded: return .skipped("Excluded in Settings")
        }
    }

    // MARK: Lifecycle

    /// Called when the module view appears: results may have arrived while the user
    /// was in another module (the view is recreated on navigation).
    func appeared() {
        syncWithFlow()
    }

    func phaseChanged(from old: ScanFlowModel.Phase, to new: ScanFlowModel.Phase) {
        if old == .scanning && new == .results, let start = scanStartedAt, Date().timeIntervalSince(start) >= 1.5 {
            SpruceSound.play(.scanComplete)
        }
        syncWithFlow()
    }

    /// Adopts a new scan report (and applies a pending tool focus) once per scan.
    private func syncWithFlow() {
        switch flow.phase {
        case .results:
            guard let latest = engine.lastModuleReport, latest.date != report?.date else { return }
            report = latest
            scanStartedAt = nil
            if let focus = pendingFocus {
                pendingFocus = nil
                route = group(for: focus) == nil ? .overview : .review(focus)
            } else {
                route = .overview
            }
        case .idle:
            route = .overview
        default:
            break
        }
    }

    // MARK: Navigation

    /// Starts a scan of `sections` (all by default); `focus` opens that section's review
    /// when results arrive.
    func startScan(sections: Set<CleanupSection> = Set(CleanupSection.allCases), focus: CleanupSection? = nil) {
        engine.requestNextScan(sections: sections)
        scanningSections = sections
        pendingFocus = focus
        route = .overview
        scanStartedAt = Date()
        SpruceSound.play(.scanStart)
        flow.startScan()
    }

    /// Handles the `cleanup.systemJunk` / `cleanup.mailAttachments` / `cleanup.trash` tools.
    func open(_ section: CleanupSection) {
        switch flow.phase {
        case .results:
            if scannedSections.contains(section) {
                route = .review(section)
            } else {
                startScan(sections: [section], focus: section)
            }
        case .scanning, .running:
            pendingFocus = section
        case .idle, .done, .failed:
            startScan(sections: [section], focus: section)
        }
    }

    func startOver() {
        confirmStartOver = false
        report = nil
        flow.reset()
    }

    // MARK: Selection

    /// Applies the scanner's recommendation ("smart selection") to a section or all.
    func selectRecommended(in section: CleanupSection? = nil) {
        updateItems(in: section) { item in
            item.isSelected = item.metadata[CleanupMetadataKey.recommended] == "1" && item.safety != .risky
        }
    }

    func deselectAll(in section: CleanupSection? = nil) {
        updateItems(in: section) { $0.isSelected = false }
    }

    /// Edit › Select All Items: everything but risky items (they need their own confirmation).
    func selectAllItems(in section: CleanupSection? = nil) {
        updateItems(in: section) { $0.isSelected = $0.safety != .risky }
    }

    /// The section whose review is on screen, if any.
    var reviewedSection: CleanupSection? {
        if case .review(let section) = route { return section }
        return nil
    }

    /// Scan and Edit menu actions (published by `CleanupRootScreen`). Run Selected… is
    /// not offered: the Clean orb runs a safe selection without a confirmation, and the
    /// menu may only open one.
    var menuActions: SpruceFlowActions {
        var actions = SpruceFlowActions()
        actions.context = "cleanup.\(ObjectIdentifier(self).hashValue).\(reviewedSection?.rawValue ?? "all")"
        switch flow.phase {
        case .idle, .done, .failed:
            actions.scanAgain = { [weak self] in self?.startScan() }
        case .scanning, .running:
            actions.stop = { [weak self] in self?.flow.cancel() }
        case .results:
            guard !isWaitingForApps, quitPrompt == nil, !confirmNonSafe else { break }
            actions.scanAgain = { [weak self] in
                guard let self else { return }
                self.startScan(sections: self.scannedSections)
            }
            if !flow.groups.allItems.isEmpty {
                let section = reviewedSection
                actions.selectAll = { [weak self] in self?.selectAllItems(in: section) }
                actions.deselectAll = { [weak self] in self?.deselectAll(in: section) }
                actions.selectRecommended = { [weak self] in self?.selectRecommended(in: section) }
            }
        }
        return actions
    }

    /// Card checkbox: clears a section that has a selection, otherwise restores the
    /// recommended selection (never everything — review items stay unchecked).
    func toggleSection(_ section: CleanupSection) {
        if (group(for: section)?.selectedCount ?? 0) > 0 {
            deselectAll(in: section)
        } else {
            selectRecommended(in: section)
        }
    }

    private func updateItems(in section: CleanupSection?, _ transform: (inout ScanItem) -> Void) {
        func apply(_ group: inout ScanGroup) {
            for i in group.items.indices { transform(&group.items[i]) }
            for j in group.children.indices { apply(&group.children[j]) }
        }
        var groups = flow.groups
        for i in groups.indices where section == nil || groups[i].id == section?.rawValue {
            apply(&groups[i])
        }
        flow.groups = groups
    }

    // MARK: Cleaning

    /// Clean button (the orb, or a card's Clean for one `section`): first asks to quit
    /// apps whose data is selected, then confirms non-safe selections, then runs.
    func requestClean(in section: CleanupSection? = nil) {
        guard !flow.isBusy, !isWaitingForApps else { return }
        cleanScope = section
        let selected = pendingSelection
        guard !selected.isEmpty else {
            cleanScope = nil
            return
        }
        let runningApps = NSWorkspace.shared.runningApplications
        let running = Set(runningApps.compactMap(\.bundleIdentifier))
        let owners = CleanupOwnership.runningOwners(of: selected, running: running)
        let apps = runningApps.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return owners.contains(id) && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        if !apps.isEmpty {
            quitPrompt = CleanupQuitPrompt(apps: apps.map { CleanupRunningApp(app: $0) })
            return
        }
        continueClean()
    }

    private func continueClean() {
        let selection = pendingSelection
        guard !selection.isEmpty else {
            cleanScope = nil
            return
        }
        if selection.contains(where: { $0.safety != .safe }) {
            confirmNonSafe = true
            return
        }
        runNow()
    }

    func runNow() {
        confirmNonSafe = false
        let items = pendingSelection
        cleanScope = nil
        route = .overview
        guard !items.isEmpty else { return }
        flow.run(items)
    }

    /// Dismisses the "items macOS can't rebuild" confirmation without cleaning.
    func cancelConfirmation() {
        confirmNonSafe = false
        cleanScope = nil
    }

    /// Deselects the items of the apps in the prompt and cleans the rest.
    func skipItemsOfRunningApps() {
        guard let prompt = quitPrompt else { return }
        quitPrompt = nil
        let ids = prompt.apps.compactMap(\.bundleID)
        for item in pendingSelection {
            guard let owner = item.metadata[CleanupMetadataKey.owner] else { continue }
            if ids.contains(where: { CleanupOwnership.matches(owner: owner, bundleID: $0) }) {
                flow.setSelected(false, itemID: item.id)
            }
        }
        continueClean()
    }

    /// Politely asks the apps to quit (they may ask to save), waits up to 15 s, then
    /// cleans. Items of apps that are still open are skipped by the engine.
    func quitAppsAndClean() {
        guard let prompt = quitPrompt else { return }
        quitPrompt = nil
        appsBeingQuit = prompt.apps.map(\.app)
        isWaitingForApps = true
        for app in appsBeingQuit { app.terminate() }
        Task { @MainActor [weak self] in
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                guard let model = self else { return }
                if !model.appsBeingQuit.contains(where: { !$0.isTerminated }) { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard let self else { return }
            self.appsBeingQuit = []
            self.isWaitingForApps = false
            self.continueClean()
        }
    }

    func cancelQuitPrompt() {
        quitPrompt = nil
        cleanScope = nil
    }
}

/// Keeps one `CleanupScreenModel` per engine for the app's lifetime.
@MainActor
private enum CleanupScreenRegistry {
    static var models: [ObjectIdentifier: CleanupScreenModel] = [:]

    static func model(for engine: CleanupEngine) -> CleanupScreenModel {
        let key = ObjectIdentifier(engine)
        if let existing = models[key] { return existing }
        let created = CleanupScreenModel(engine: engine)
        models[key] = created
        return created
    }
}

// MARK: - Root screen

/// Hosts the phase screens, the tool-id routing and the shared sheets/dialogs.
struct CleanupRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: CleanupScreenModel

    init(engine: CleanupEngine) {
        _screen = State(initialValue: CleanupScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack {
            CleanupPhaseContent(screen: screen)
                .id(screen.phaseKey)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : Motion.standard, value: screen.phaseKey)
        .onAppear {
            screen.appeared()
            consumePendingTool()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .onChange(of: screen.flow.phase) { oldPhase, newPhase in
            screen.phaseChanged(from: oldPhase, to: newPhase)
        }
        .focusedSceneValue(\.spruceFlow, screen.menuActions)
        .sheet(item: $screen.quitPrompt) { prompt in
            CleanupQuitAppsSheet(prompt: prompt,
                                 onQuit: { screen.quitAppsAndClean() },
                                 onSkip: { screen.skipItemsOfRunningApps() },
                                 onCancel: { screen.cancelQuitPrompt() })
        }
        .confirmationDialog(nonSafeTitle, isPresented: $screen.confirmNonSafe, titleVisibility: .visible) {
            Button("Clean", role: .destructive) { screen.runNow() }
            Button("Cancel", role: .cancel) { screen.cancelConfirmation() }
        } message: {
            Text(nonSafeMessage)
        }
    }

    private var nonSafeItems: [ScanItem] {
        screen.pendingSelection.filter { $0.safety != .safe }
    }

    private var nonSafeTitle: String {
        "Clean \(CountFormat.items(nonSafeItems.count)) that macOS can't rebuild?"
    }

    private var nonSafeMessage: String {
        let trashed = nonSafeItems.filter { $0.deletion == .trash }.count
        var text = "You selected items Spruce doesn't pick on its own, such as backups, archives or edited attachments."
        if trashed == nonSafeItems.count {
            text += " They go to the Trash, so you can still put them back."
        } else if trashed > 0 {
            text += " Some go to the Trash; the rest are deleted right away."
        } else {
            text += " They're deleted right away."
        }
        return text
    }

    private func consumePendingTool() {
        guard let tool = model.pendingTool, let section = CleanupSection(toolID: tool) else { return }
        model.pendingTool = nil
        screen.open(section)
    }
}

/// Switches between the idle, scanning, results/review, running, done and failure screens.
struct CleanupPhaseContent: View {
    @Bindable var screen: CleanupScreenModel

    var body: some View {
        switch screen.flow.phase {
        case .idle:
            CleanupIdleScreen(screen: screen)
        case .scanning:
            ScanningView(module: .cleanup, progress: screen.flow.progress, title: screen.scanTitle,
                         onStop: { screen.flow.cancel() }, steps: screen.scanSteps)
        case .results:
            switch screen.route {
            case .overview:
                CleanupResultsScreen(screen: screen)
            case .review(let section):
                CleanupReviewScreen(screen: screen, section: section)
            }
        case .running:
            ScanningView(module: .cleanup, progress: screen.flow.progress, title: "Cleaning…",
                         onStop: { screen.flow.cancel() })
        case .done:
            if let outcome = screen.doneOutcome {
                DoneView(module: .cleanup, outcome: outcome,
                         doneTitle: screen.flow.groups.isEmpty ? "Done" : "Review Remaining",
                         flow: screen.flow) {
                    screen.flow.showRemaining()
                }
            } else {
                EmptyStateView(module: .cleanup, title: "All done", message: "Nothing else to clean right now.",
                               actionTitle: "Back", action: { screen.flow.showRemaining() })
            }
        case .failed(let message):
            FailureView(module: .cleanup, message: message) { screen.startScan() }
        }
    }
}
