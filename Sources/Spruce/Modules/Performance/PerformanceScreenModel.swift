import AppKit
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Navigation

/// The Performance module's tools (tool ids `performance.<rawValue>`).
enum PerformanceTool: String, CaseIterable, Identifiable {
    case maintenance
    case loginItems
    case backgroundItems
    case consumers

    var id: String { rawValue }
    var toolID: String { "performance." + rawValue }

    init?(toolID: String) {
        let prefix = "performance."
        guard toolID.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(toolID.dropFirst(prefix.count)))
    }

    var title: String {
        switch self {
        case .maintenance: return "Maintenance"
        case .loginItems: return "Login Items"
        case .backgroundItems: return "Background Items"
        case .consumers: return "Heavy Consumers"
        }
    }

    var symbol: String {
        switch self {
        case .maintenance: return "wrench.and.screwdriver"
        case .loginItems: return "power"
        case .backgroundItems: return "gearshape.2"
        case .consumers: return "flame"
        }
    }
}

enum PerformanceRoute: Equatable {
    case hub
    case tool(PerformanceTool)
}

// MARK: - Maintenance state

enum PerformanceMaintenancePhase: Equatable {
    case loading
    case ready
    case running
    case done
}

enum PerformanceTaskRowState: Equatable {
    case idle
    case queued
    case running
    case finished(PerformanceTaskRunResult)
}

/// Apps that must close before some selected tasks can run.
struct PerformanceQuitPrompt: Identifiable {
    let id = UUID()
    var apps: [PerformanceAppToQuit]
    var tasks: [PerformanceTaskID]
}

enum PerformanceToastAction: Equatable {
    case forceQuit(PerformanceConsumer)
    case openAutomationSettings
    case openLoginItemsSettings
}

struct PerformanceToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var isError: Bool
    var action: PerformanceToastAction?

    var actionTitle: String? {
        switch action {
        case .forceQuit?: return "Force Quit"
        case .openAutomationSettings?: return "Open Settings"
        case .openLoginItemsSettings?: return "Open Settings"
        case nil: return nil
        }
    }
}

// MARK: - Model

/// UI state for the Performance module. One instance per engine, so results survive
/// navigation between modules.
@MainActor
@Observable
final class PerformanceScreenModel {
    private static var instances: [ObjectIdentifier: PerformanceScreenModel] = [:]

    static func shared(for engine: PerformanceEngine) -> PerformanceScreenModel {
        let key = ObjectIdentifier(engine)
        if let existing = instances[key] { return existing }
        let model = PerformanceScreenModel(engine: engine)
        instances[key] = model
        return model
    }

    let engine: PerformanceEngine
    var route: PerformanceRoute = .hub

    // Maintenance
    private(set) var taskStates: [PerformanceTaskState] = []
    var selectedTasks: Set<PerformanceTaskID> = []
    var focusedTaskID: PerformanceTaskID?
    private(set) var maintenancePhase: PerformanceMaintenancePhase = .loading
    private(set) var isAssessing = false
    private(set) var lastAssessed: Date?
    private(set) var runProgress = ScanProgress(message: "")
    private(set) var rowStates: [PerformanceTaskID: PerformanceTaskRowState] = [:]
    private(set) var lastOutcome: RunOutcome?
    private(set) var lastResults: [PerformanceTaskID: PerformanceTaskRunResult] = [:]
    var quitPrompt: PerformanceQuitPrompt?
    private var selectionEdited = false
    private var runTask: Task<Void, Never>?

    // Login & background items
    private(set) var inventory: PerformanceStartupInventory?
    private(set) var isLoadingInventory = false
    private var inventoryReloadPending = false
    private(set) var busyItemIDs: Set<String> = []
    var selectedStartupIDs: Set<String> = []
    var startupSearch = ""
    private(set) var removalCandidates: [PerformanceStartupItem] = []
    var confirmRemoval = false

    // Heavy consumers
    private(set) var consumers: [PerformanceConsumer] = []
    private(set) var memory: PerformanceMemoryReading?
    var consumerSort: PerformanceConsumerSort = .cpu
    private(set) var consumersSampledAt: Date?
    private(set) var quittingIDs: Set<String> = []
    private(set) var forceQuitCandidate: PerformanceConsumer?
    var confirmForceQuit = false

    var toast: PerformanceToast?

    private init(engine: PerformanceEngine) {
        self.engine = engine
    }

    // MARK: Navigation

    func appeared() {
        if lastAssessed == nil && !isAssessing { refreshTasks() }
        if inventory == nil && !isLoadingInventory { refreshInventory() }
    }

    func open(_ tool: PerformanceTool) {
        route = .tool(tool)
        switch tool {
        case .maintenance:
            if lastAssessed == nil || maintenancePhase == .ready { refreshTasks() }
        case .loginItems, .backgroundItems:
            selectedStartupIDs = []
            startupSearch = ""
            let isStale = inventory.map { Date().timeIntervalSince($0.date) > 20 } ?? true
            if isStale { refreshInventory() }
        case .consumers:
            break
        }
    }

    func goHub() {
        route = .hub
        selectedStartupIDs = []
        if maintenancePhase == .done { maintenancePhase = .ready }
    }

    // MARK: Maintenance

    var availableStates: [PerformanceTaskState] { taskStates.filter { $0.assessment.isAvailable } }
    var recommendedStates: [PerformanceTaskState] { availableStates.filter { $0.assessment.isRecommended } }
    var routineDueStates: [PerformanceTaskState] { availableStates.filter { $0.assessment.preselect } }
    var focusedState: PerformanceTaskState? { taskStates.first { $0.id == focusedTaskID } }
    var isRunning: Bool { maintenancePhase == .running }

    func refreshTasks() {
        guard !isAssessing, maintenancePhase != .running else { return }
        isAssessing = true
        if taskStates.isEmpty { maintenancePhase = .loading }
        let engine = self.engine
        Task { [weak self] in
            let states = await engine.assessTasks()
            self?.applyAssessment(states)
        }
    }

    private func applyAssessment(_ states: [PerformanceTaskState]) {
        isAssessing = false
        lastAssessed = Date()
        // Available tasks first (in catalog order), unavailable ones at the end.
        taskStates = states.filter { $0.assessment.isAvailable } + states.filter { !$0.assessment.isAvailable }
        let valid = Set(availableStates.map(\.id))
        if selectionEdited {
            selectedTasks.formIntersection(valid)
        } else {
            selectedTasks = Set(routineDueStates.map(\.id))
        }
        if focusedTaskID == nil || !taskStates.contains(where: { $0.id == focusedTaskID }) {
            focusedTaskID = (recommendedStates.first ?? availableStates.first)?.id
        }
        if maintenancePhase == .loading { maintenancePhase = .ready }
    }

    func toggleTask(_ id: PerformanceTaskID) {
        guard !isRunning, availableStates.contains(where: { $0.id == id }) else { return }
        selectionEdited = true
        if selectedTasks.contains(id) { selectedTasks.remove(id) } else { selectedTasks.insert(id) }
    }

    func selectTasks(_ mode: PerformanceTaskSelection) {
        guard !isRunning else { return }
        selectionEdited = true
        switch mode {
        case .all: selectedTasks = Set(availableStates.map(\.id))
        case .none: selectedTasks = []
        case .recommended: selectedTasks = Set(recommendedStates.map(\.id))
        }
    }

    /// The hub's "Run" button: the routine tasks that are due.
    func runRoutineTasks() {
        let ids = routineDueStates.map(\.id)
        guard !ids.isEmpty else { return }
        selectedTasks = Set(ids)
        selectionEdited = false
        route = .tool(.maintenance)
        run(ids)
    }

    func runSelected() {
        run(Array(selectedTasks))
    }

    private func run(_ ids: [PerformanceTaskID]) {
        let ordered = PerformanceTaskCatalog.ordered(ids)
        guard !ordered.isEmpty, !isRunning else { return }
        let blocking = engine.appsBlocking(ordered)
        if !blocking.isEmpty {
            quitPrompt = PerformanceQuitPrompt(apps: blocking, tasks: ordered)
            return
        }
        startRun(ordered)
    }

    /// Quit sheet: close the apps (normal quit, never forced), then run everything.
    func quitAppsAndRun() {
        guard let prompt = quitPrompt else { return }
        quitPrompt = nil
        maintenancePhase = .running
        rowStates = Dictionary(uniqueKeysWithValues: prompt.tasks.map { ($0, PerformanceTaskRowState.queued) })
        runProgress = ScanProgress(fraction: nil, message: "Closing \(prompt.apps.map(\.name).joined(separator: ", "))…")
        let engine = self.engine
        Task { [weak self] in
            for app in prompt.apps {
                _ = await engine.quitApp(bundleID: app.bundleID)
            }
            // Tasks whose app refused to close report it in their result.
            self?.startRun(prompt.tasks, force: true)
        }
    }

    /// Quit sheet: run only the tasks that don't need the open apps closed.
    func runWithoutBlockedTasks() {
        guard let prompt = quitPrompt else { return }
        quitPrompt = nil
        let blocked = Set(prompt.apps.map(\.bundleID))
        let remaining = prompt.tasks.filter { id in
            !PerformanceTaskCatalog.definition(id).appsToQuit.contains { blocked.contains($0.bundleID) }
        }
        for id in prompt.tasks where !remaining.contains(id) {
            selectedTasks.remove(id)
        }
        selectionEdited = true
        guard !remaining.isEmpty else { return }
        startRun(remaining)
    }

    func cancelQuitPrompt() {
        quitPrompt = nil
    }

    private func startRun(_ ids: [PerformanceTaskID], force: Bool = false) {
        guard force || !isRunning else { return }
        maintenancePhase = .running
        rowStates = Dictionary(uniqueKeysWithValues: ids.map { ($0, PerformanceTaskRowState.queued) })
        runProgress = ScanProgress(fraction: 0, message: "Starting…")
        let engine = self.engine
        // Built outside the task so they capture `self` weakly by value.
        let onProgress: ProgressHandler = { [weak self] progress in
            Task { @MainActor [weak self] in self?.receiveProgress(progress) }
        }
        let onEvent: @Sendable (PerformanceTaskEvent) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in self?.receive(event) }
        }
        runTask = Task { [weak self] in
            let results = await engine.runTasks(ids, progress: onProgress, onEvent: onEvent)
            self?.finishRun(results)
        }
    }

    func stopRun() {
        runTask?.cancel()
        runProgress = ScanProgress(fraction: runProgress.fraction, message: "Stopping after the current task…")
    }

    private func receiveProgress(_ progress: ScanProgress) {
        guard isRunning else { return }
        runProgress = progress
    }

    private func receive(_ event: PerformanceTaskEvent) {
        guard isRunning else { return }
        switch event {
        case .started(let id):
            rowStates[id] = .running
        case .finished(let result):
            rowStates[result.id] = .finished(result)
        }
    }

    private func finishRun(_ results: [PerformanceTaskRunResult]) {
        runTask = nil
        for result in results {
            rowStates[result.id] = .finished(result)
            lastResults[result.id] = result
        }
        let cancelledAtPrompt = !results.isEmpty
            && results.allSatisfy { $0.status == .skipped && $0.detail == PerformanceEngine.cancelledDetail }
        if results.isEmpty || cancelledAtPrompt {
            rowStates = [:]
            maintenancePhase = .ready
            if cancelledAtPrompt {
                toast = PerformanceToast(message: "Nothing was run: the administrator prompt was cancelled.", isError: false)
            }
            return
        }
        let outcome = PerformanceRunSummary.outcome(results)
        lastOutcome = outcome
        if outcome.processedCount > 0 {
            HistoryStore.shared.record(outcome, kind: .maintenance)
        }
        maintenancePhase = .done
        // Done tasks are no longer due: re-assess and re-apply the default selection.
        selectionEdited = false
        refreshTasks()
    }

    func acknowledgeDone() {
        maintenancePhase = .ready
    }

    func rowState(for id: PerformanceTaskID) -> PerformanceTaskRowState {
        rowStates[id] ?? .idle
    }

    // MARK: Login & background items

    func refreshInventory() {
        guard !isLoadingInventory else {
            inventoryReloadPending = true
            return
        }
        isLoadingInventory = true
        let engine = self.engine
        Task { [weak self] in
            let inventory = await engine.startupInventory()
            self?.applyInventory(inventory)
        }
    }

    private func applyInventory(_ inventory: PerformanceStartupInventory) {
        self.inventory = inventory
        isLoadingInventory = false
        selectedStartupIDs.formIntersection(Set(inventory.items.filter(\.canRemove).map(\.id)))
        if inventoryReloadPending {
            inventoryReloadPending = false
            refreshInventory()
        }
    }

    func items(for tool: PerformanceTool) -> [PerformanceStartupItem] {
        guard let inventory else { return [] }
        let base = tool == .loginItems ? inventory.loginItems : inventory.backgroundItems
        let query = startupSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        return base.filter { item in
            [item.name, item.vendorName, item.label ?? "", item.executablePath ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func groups(for tool: PerformanceTool) -> [PerformanceVendorGroup] {
        PerformanceStartupGrouping.groups(items(for: tool))
    }

    func count(for tool: PerformanceTool) -> Int {
        guard let inventory else { return 0 }
        return tool == .loginItems ? inventory.loginItems.count : inventory.backgroundItems.count
    }

    func selectedItems(for tool: PerformanceTool) -> [PerformanceStartupItem] {
        items(for: tool).filter { selectedStartupIDs.contains($0.id) }
    }

    func toggleSelection(_ item: PerformanceStartupItem) {
        guard item.canRemove else { return }
        if selectedStartupIDs.contains(item.id) { selectedStartupIDs.remove(item.id) } else { selectedStartupIDs.insert(item.id) }
    }

    func setGroupSelection(_ group: PerformanceVendorGroup, selected: Bool) {
        let ids = group.items.filter(\.canRemove).map(\.id)
        if selected { selectedStartupIDs.formUnion(ids) } else { selectedStartupIDs.subtract(ids) }
    }

    func setEnabled(_ item: PerformanceStartupItem, _ enabled: Bool) {
        act(on: [item], removing: false, enable: enabled)
    }

    func setSelectedEnabled(_ enabled: Bool, tool: PerformanceTool) {
        let targets = selectedItems(for: tool).filter { $0.canToggle && $0.isEnabled != enabled }
        guard !targets.isEmpty else { return }
        act(on: targets, removing: false, enable: enabled)
    }

    func requestRemoval(_ items: [PerformanceStartupItem]) {
        removalCandidates = items.filter(\.canRemove)
        confirmRemoval = !removalCandidates.isEmpty
    }

    func confirmRemove() {
        let targets = removalCandidates
        removalCandidates = []
        guard !targets.isEmpty else { return }
        act(on: targets, removing: true, enable: false)
    }

    func cancelRemoval() {
        removalCandidates = []
    }

    private func act(on items: [PerformanceStartupItem], removing: Bool, enable: Bool) {
        let ids = Set(items.map(\.id))
        guard busyItemIDs.isDisjoint(with: ids) else { return }
        busyItemIDs.formUnion(ids)
        let engine = self.engine
        Task { [weak self] in
            let outcome: RunOutcome
            if removing {
                outcome = await engine.remove(items)
            } else {
                outcome = await engine.setEnabled(items, enabled: enable)
            }
            self?.finishAction(outcome, ids: ids, removing: removing)
        }
    }

    private func finishAction(_ outcome: RunOutcome, ids: Set<String>, removing: Bool) {
        busyItemIDs.subtract(ids)
        if removing && outcome.processedCount > 0 {
            HistoryStore.shared.record(outcome, kind: .startupItems)
        }
        if removing { selectedStartupIDs.subtract(outcome.removedItemIDs) }
        if let first = outcome.failures.first {
            let needsAutomation = first.reason.contains("Automation")
            let message = outcome.failures.count == 1
                ? "\(first.title): \(first.reason)"
                : "\(outcome.summary). \(outcome.failures.count) items couldn't be changed — \(first.title): \(first.reason)"
            toast = PerformanceToast(message: message, isError: true, action: needsAutomation ? .openAutomationSettings : nil)
        } else {
            toast = PerformanceToast(message: outcome.summary, isError: false)
        }
        refreshInventory()
    }

    // MARK: Heavy consumers

    func refreshConsumers() async {
        let snapshot = await engine.sampleConsumers(sort: consumerSort, limit: 30)
        consumers = snapshot.consumers
        memory = snapshot.memory
        consumersSampledAt = snapshot.date
    }

    func quit(_ consumer: PerformanceConsumer, force: Bool) {
        guard !quittingIDs.contains(consumer.id) else { return }
        quittingIDs.insert(consumer.id)
        let engine = self.engine
        Task { [weak self] in
            let ok = await engine.quit(consumer, force: force)
            guard let self else { return }
            self.quittingIDs.remove(consumer.id)
            if ok {
                self.toast = PerformanceToast(message: force ? "\(consumer.name) was force quit." : "\(consumer.name) quit.", isError: false)
            } else if force {
                self.toast = PerformanceToast(message: "\(consumer.name) couldn't be stopped.", isError: true)
            } else {
                self.toast = PerformanceToast(message: "\(consumer.name) hasn't quit. It may be waiting for you to save your work.",
                                              isError: true, action: consumer.isApp ? .forceQuit(consumer) : nil)
            }
            await self.refreshConsumers()
        }
    }

    func requestForceQuit(_ consumer: PerformanceConsumer) {
        forceQuitCandidate = consumer
        confirmForceQuit = true
    }

    func confirmForceQuitNow() {
        guard let candidate = forceQuitCandidate else { return }
        forceQuitCandidate = nil
        quit(candidate, force: true)
    }

    // MARK: Toast

    func performToastAction() {
        guard let action = toast?.action else { return }
        toast = nil
        switch action {
        case .forceQuit(let consumer):
            requestForceQuit(consumer)
        case .openAutomationSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        case .openLoginItemsSettings:
            Permissions.openLoginItemsSettings()
        }
    }
}

enum PerformanceTaskSelection {
    case all
    case none
    case recommended
}
