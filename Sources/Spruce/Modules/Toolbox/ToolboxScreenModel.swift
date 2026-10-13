import AppKit
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

/// Tools whose screens live inside the Toolbox.
enum ToolboxLocalTool: String, CaseIterable, Sendable {
    case shredder
    case screenCleaning
    case emptyTrash
    case freeRAM
    case flushDNS

    /// "toolbox.shredder" → `.shredder`; nil for any other module's tool id.
    init?(toolID: String) {
        let prefix = "toolbox."
        guard toolID.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(toolID.dropFirst(prefix.count)))
    }

    var toolID: String { "toolbox." + rawValue }

    var title: String { ToolboxCatalog.tool(id: toolID)?.title ?? rawValue }
}

enum ToolboxRoute: Equatable {
    case hub
    case tool(ToolboxLocalTool)
}

/// State of the Toolbox: navigation, search, favourites and the Toolbox-only tools.
/// One instance lives for the app's lifetime so tool state survives navigation.
@MainActor
@Observable
final class ToolboxScreenModel {
    static let shared = ToolboxScreenModel()

    var route: ToolboxRoute = .hub
    var query = ""
    private(set) var favorites: [String]

    let shredder = ToolboxShredderModel()
    let trash = ToolboxTrashModel()
    let memory = ToolboxTaskModel(task: .freeRAM)
    let dns = ToolboxTaskModel(task: .flushDNS)

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = ToolboxFavorites.resolve(defaults.stringArray(forKey: ToolboxFavorites.defaultsKey))
    }

    // MARK: Navigation

    /// Opens a tool: Toolbox-only tools open here, every other tool in its module.
    func open(_ tool: ToolboxTool, model: AppModel) {
        if let local = ToolboxLocalTool(toolID: tool.id) {
            open(local)
        } else {
            model.open(tool.module, tool: tool.id)
        }
    }

    func open(_ tool: ToolboxLocalTool) {
        route = .tool(tool)
        switch tool {
        case .emptyTrash:
            trash.refreshIfIdle()
        case .freeRAM:
            memory.resetIfDone()
        case .flushDNS:
            dns.resetIfDone()
        case .shredder, .screenCleaning:
            break
        }
    }

    func showHub() {
        route = .hub
    }

    /// Files handed over from Finder ("Shred with Spruce", the Dock icon, Open With): opens
    /// the Shredder and lists them unchecked. Nothing is shredded without the Shredder's own
    /// confirmation.
    func stageForShredding(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        open(.shredder)
        shredder.add(urls, checked: false)
    }

    // MARK: Search

    var results: [ToolboxTool] { ToolboxCatalog.search(query, favorites: favorites) }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Favourites

    var favoriteTools: [ToolboxTool] { favorites.compactMap(ToolboxCatalog.tool(id:)) }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        setFavorites(ToolboxFavorites.toggled(id, in: favorites))
    }

    func moveFavorite(_ id: String, by offset: Int) {
        setFavorites(ToolboxFavorites.moved(id, by: offset, in: favorites))
    }

    func resetFavorites() {
        setFavorites(ToolboxCatalog.defaultFavorites)
    }

    private func setFavorites(_ ids: [String]) {
        favorites = ids
        defaults.set(ids, forKey: ToolboxFavorites.defaultsKey)
    }
}

// MARK: - Free Up RAM / Flush DNS

/// Runs one Performance maintenance task (one administrator prompt) and keeps its result.
@MainActor
@Observable
final class ToolboxTaskModel {
    enum Phase: Equatable {
        case idle
        case running
        case done(PerformanceTaskRunResult)
    }

    let task: PerformanceTaskID
    private(set) var phase: Phase = .idle
    private(set) var progress = ScanProgress(message: "")
    /// Memory in use before / after a Free Up RAM run.
    private(set) var memoryBefore: Int64?
    private(set) var memoryAfter: Int64?

    init(task: PerformanceTaskID) {
        self.task = task
    }

    var isRunning: Bool { phase == .running }

    func run(engine: PerformanceEngine, monitor: SystemMonitor) {
        guard phase != .running else { return }
        phase = .running
        progress = ScanProgress(fraction: nil, message: "Waiting for administrator approval…")
        memoryBefore = monitor.hasSample ? monitor.memory.used : nil
        memoryAfter = nil
        let task = self.task
        let report: ProgressHandler = { p in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .running else { return }
                self.progress = p
            }
        }
        Task { [weak self] in
            let results = await engine.runTasks([task], progress: report)
            guard let self else { return }
            let result = results.first(where: { $0.id == task })
                ?? PerformanceTaskRunResult(id: task, status: .failed, detail: "The task didn't run.")
            if result.status == .done {
                var outcome = PerformanceRunSummary.outcome(results)
                outcome.summary = result.detail.isEmpty ? outcome.summary : result.detail
                HistoryStore.shared.record(outcome, kind: .maintenance)
            }
            monitor.refresh()
            if task == .freeRAM, result.status == .done {
                // Give the monitor a moment to take a fresh reading.
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.memoryAfter = monitor.hasSample ? monitor.memory.used : nil
            }
            self.phase = .done(result)
        }
    }

    func reset() {
        guard phase != .running else { return }
        phase = .idle
    }

    func resetIfDone() {
        if case .done = phase { phase = .idle }
    }
}

// MARK: - Empty Trash

@MainActor
@Observable
final class ToolboxTrashModel {
    enum Phase: Equatable {
        case measuring
        case ready
        case emptying
        case done(RunOutcome)
    }

    private(set) var phase: Phase = .measuring
    private(set) var summary = ToolboxTrashSummary()
    var confirming = false
    @ObservationIgnored private var measureTask: Task<Void, Never>?

    func refreshIfIdle() {
        switch phase {
        case .emptying:
            return
        case .measuring:
            if measureTask == nil { refresh() }
        case .ready, .done:
            refresh()
        }
    }

    func refresh() {
        measureTask?.cancel()
        phase = .measuring
        measureTask = Task { [weak self] in
            let measured = await ToolboxTrash.measure()
            guard let self, !Task.isCancelled else { return }
            self.summary = measured
            self.phase = .ready
            self.measureTask = nil
        }
    }

    func empty(monitor: SystemMonitor) {
        guard phase == .ready, summary.itemCount > 0 else { return }
        measureTask?.cancel()
        measureTask = nil
        phase = .emptying
        Task { [weak self] in
            let outcome = await monitor.emptyTrash()
            let measured = await ToolboxTrash.measure()
            guard let self else { return }
            self.summary = measured
            self.phase = .done(outcome)
        }
    }

    func acknowledge() {
        phase = .ready
    }
}

// MARK: - Shredder

@MainActor
@Observable
final class ToolboxShredderModel {
    enum Phase: Equatable {
        case choosing
        case inspecting
        case review
        case shredding
        case done(RunOutcome)
    }

    private(set) var phase: Phase = .choosing
    private(set) var plans: [ToolboxShredPlan] = []
    /// Ids of the plans the Shred button acts on. Items picked in the Shredder (drop,
    /// Choose…) start checked; files handed over from Finder start unchecked.
    private(set) var checked: Set<String> = []
    private(set) var progress = ScanProgress(message: "")
    var confirming = false

    private let engine = ToolboxShredder()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Items that arrived while the list was being checked or shredded; they're added once
    /// the Shredder is free.
    @ObservationIgnored private var waiting: [(urls: [URL], checked: Bool)] = []

    /// Checked items that can be shredded: what the Shred button acts on.
    var shreddable: [ToolboxShredPlan] { plans.filter { $0.canShred && checked.contains($0.id) } }
    var shreddableBytes: Int64 { shreddable.reduce(Int64(0)) { $0 + $1.allocatedBytes } }
    /// Items that could be checked.
    var checkable: [ToolboxShredPlan] { plans.filter(\.canShred) }
    /// Items that can't be shredded (each shows why).
    var blockedCount: Int { plans.count - checkable.count }
    var allChecked: Bool { !checkable.isEmpty && checkable.allSatisfy { checked.contains($0.id) } }

    func isChecked(_ plan: ToolboxShredPlan) -> Bool { checked.contains(plan.id) }

    func toggle(_ plan: ToolboxShredPlan) {
        guard phase == .review, plan.canShred else { return }
        if checked.contains(plan.id) {
            checked.remove(plan.id)
        } else {
            checked.insert(plan.id)
        }
    }

    func setAllChecked(_ on: Bool) {
        guard phase == .review else { return }
        checked = on ? Set(checkable.map(\.id)) : []
    }

    /// Shows the open panel and adds what the user picks (checked).
    func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose Items to Shred"
        panel.message = "Choose files or folders to overwrite and delete for good."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    /// Adds dropped or chosen items (checked) or files from Finder (`checked: false`) and
    /// (re)checks the whole list. Never shreds anything by itself.
    func add(_ urls: [URL], checked checkAdded: Bool = true) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        switch phase {
        case .inspecting, .shredding:
            waiting.append((urls: fileURLs, checked: checkAdded))
            return
        case .done:
            // New items replace the finished run's result screen.
            task = nil
        case .choosing, .review:
            break
        }
        let all = plans.map { URL(fileURLWithPath: $0.root) } + fileURLs
        let previous = checked
        phase = .inspecting
        progress = ScanProgress(fraction: nil, message: "Checking the items…")
        let engine = self.engine
        let settings = SettingsStore.shared.settings
        task = Task { [weak self] in
            let inspected = await engine.plan(all, settings: settings)
            guard let self, !Task.isCancelled else { return }
            self.plans = inspected
            self.checked = ToolboxShredPlan.selection(for: inspected, previous: previous,
                                                      added: fileURLs.map(\.path), checkAdded: checkAdded)
            self.phase = inspected.isEmpty ? .choosing : .review
            self.addWaiting()
        }
    }

    func remove(_ plan: ToolboxShredPlan) {
        guard phase == .review || phase == .choosing else { return }
        plans.removeAll { $0.id == plan.id }
        checked.remove(plan.id)
        if plans.isEmpty { phase = .choosing }
    }

    func shred() {
        let targets = shreddable
        guard !targets.isEmpty, phase == .review else { return }
        phase = .shredding
        progress = ScanProgress(fraction: 0, message: "Overwriting…")
        let engine = self.engine
        let settings = SettingsStore.shared.settings
        let report: ProgressHandler = { p in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .shredding else { return }
                self.progress = p
            }
        }
        task = Task { [weak self] in
            let outcome = await engine.shred(targets, settings: settings, progress: report)
            if outcome.processedCount > 0 {
                HistoryStore.shared.record(outcome, kind: .clean)
            }
            guard let self else { return }
            let removed = Set(outcome.removedItemIDs)
            self.plans.removeAll { removed.contains($0.id) }
            self.checked.subtract(removed)
            self.phase = .done(outcome)
        }
    }

    func stop() {
        task?.cancel()
    }

    func finish() {
        task = nil
        phase = plans.isEmpty ? .choosing : .review
        addWaiting()
    }

    func clear() {
        guard phase != .shredding else { return }
        task?.cancel()
        plans = []
        checked = []
        waiting = []
        phase = .choosing
    }

    /// Adds the next batch that arrived while the Shredder was busy.
    private func addWaiting() {
        guard !waiting.isEmpty, phase == .choosing || phase == .review else { return }
        let next = waiting.removeFirst()
        add(next.urls, checked: next.checked)
    }
}
