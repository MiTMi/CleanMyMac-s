import AppKit
import Foundation
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Navigation

/// The Applications module's tools (tool ids `applications.<rawValue>`).
enum ApplicationsTool: String, CaseIterable, Identifiable {
    case uninstaller
    case updater
    case leftovers
    case installers
    case extensions

    var id: String { rawValue }
    var toolID: String { "applications." + rawValue }

    init?(toolID: String) {
        let prefix = "applications."
        guard toolID.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(toolID.dropFirst(prefix.count)))
    }

    var title: String {
        switch self {
        case .uninstaller: return "Uninstaller"
        case .updater: return "Updater"
        case .leftovers: return "Leftovers"
        case .installers: return "Installers"
        case .extensions: return "Extensions"
        }
    }

    var symbol: String {
        switch self {
        case .uninstaller: return "trash.square"
        case .updater: return "arrow.down.circle"
        case .leftovers: return "questionmark.folder"
        case .installers: return "shippingbox"
        case .extensions: return "puzzlepiece.extension"
        }
    }
}

enum ApplicationsRoute: Equatable {
    case hub
    case tool(ApplicationsTool)
}

/// Loading state of one data source (catalog, updates, extensions).
enum ApplicationsLoadPhase: Equatable {
    case idle
    case loading
    case ready
}

enum ApplicationsOverviewPhase: Equatable {
    case idle
    case scanning
    case ready
}

/// The app opened in the Uninstaller's detail pane, with its component checklist.
struct ApplicationsDetailState {
    var app: ApplicationsAppInfo
    var groups: [ScanGroup] = []
    var isLoading = true
}

/// A pending Uninstall / Reset / Remove awaiting confirmation.
struct ApplicationsUninstallRequest: Identifiable {
    let id = UUID()
    var apps: [ApplicationsAppInfo]
    /// Exact checklist items (detail pane), or nil to use each app's default uninstall set.
    var items: [ScanItem]?
    /// Apps that are open right now (asked to quit first).
    var openApps: [ApplicationsAppInfo] = []

    var removesApps: Bool { items.map(ApplicationsComponents.removesApp) ?? true }
    var isReset: Bool {
        guard let items, !removesApps else { return false }
        return items.allSatisfy { $0.metadata[ApplicationsMeta.resetData] == "1" }
    }
}

/// Uninstall / reset progress shown over the Uninstaller.
enum ApplicationsRunState: Equatable {
    case none
    case running(ScanProgress)
    case done(RunOutcome, removedApps: Bool)
}

struct ApplicationsToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var isError: Bool = false
}

/// Per-row state of the Updater while updates install.
enum ApplicationsUpdateRowStatus: Equatable {
    case queued
    case updating
    case updated
    case failed(String)
}

/// "These apps are open" before Homebrew updates them.
struct ApplicationsUpdateQuitPrompt: Identifiable {
    let id = UUID()
    var updates: [ApplicationsUpdate]
    var openApps: [ApplicationsAppInfo]
}

// MARK: - File review (leftovers, installers)

/// Scan → review → move to Trash journey for files of removed apps or old installers.
/// Unlike `ScanFlowModel` it can be seeded with the overview scan's results.
@MainActor
@Observable
final class ApplicationsFileReview {
    enum Kind {
        case leftovers
        case installers
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case running
        case done
    }

    let kind: Kind
    private let engine: ApplicationsEngine

    private(set) var phase: Phase = .idle
    private(set) var progress = ScanProgress(message: "")
    var groups: [ScanGroup] = []
    private(set) var outcome: RunOutcome?
    private(set) var scannedAt: Date?

    private var task: Task<Void, Never>?

    init(kind: Kind, engine: ApplicationsEngine) {
        self.kind = kind
        self.engine = engine
    }

    var hasResults: Bool { scannedAt != nil }
    var totalSize: Int64 { groups.totalSize }
    var selectedItems: [ScanItem] { groups.selectedItems }
    var isBusy: Bool { phase == .scanning || phase == .running }

    func scan() {
        task?.cancel()
        phase = .scanning
        progress = ScanProgress(fraction: nil, message: "Starting…")
        outcome = nil
        let engine = self.engine
        let kind = self.kind
        let handler: ProgressHandler = { p in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .scanning else { return }
                self.progress = p
            }
        }
        task = Task { [weak self] in
            let result: [ScanGroup]
            switch kind {
            case .leftovers: result = await engine.scanLeftovers(progress: handler)
            case .installers: result = await engine.scanInstallers(progress: handler)
            }
            guard let self, !Task.isCancelled else { return }
            self.groups = result
            self.scannedAt = Date()
            self.phase = .results
        }
    }

    /// Uses results found elsewhere (the overview scan) without scanning again.
    func seed(_ groups: [ScanGroup]) {
        guard !isBusy else { return }
        task?.cancel()
        self.groups = groups
        scannedAt = Date()
        outcome = nil
        phase = .results
    }

    /// Moves the given items (or the selection) to the Trash.
    func run(_ items: [ScanItem]? = nil) {
        let targets = items ?? groups.selectedItems
        guard !targets.isEmpty, !isBusy else { return }
        task?.cancel()
        phase = .running
        progress = ScanProgress(fraction: 0, message: "Moving to the Trash…")
        let engine = self.engine
        let report: ProgressHandler = { p in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .running else { return }
                self.progress = p
            }
        }
        task = Task { [weak self] in
            let result = await engine.removeFiles(targets, progress: report)
            guard let self else { return }
            self.outcome = result
            self.groups.removeItems(withIDs: Set(result.removedItemIDs))
            self.phase = .done
            HistoryStore.shared.record(result, kind: .clean)
        }
    }

    func cancel() {
        guard phase == .scanning else { return }
        task?.cancel()
        task = nil
        phase = scannedAt == nil ? .idle : .results
    }

    /// From the done screen back to the remaining results.
    func showRemaining() {
        phase = .results
    }

    func setGroup(_ groupID: String, selected: Bool) {
        func apply(_ list: inout [ScanGroup]) -> Bool {
            for i in list.indices {
                if list[i].id == groupID {
                    list[i].setAllSelected(selected)
                    return true
                }
                if apply(&list[i].children) { return true }
            }
            return false
        }
        _ = apply(&groups)
    }

    func ignore(_ item: ScanItem) {
        if let url = item.url {
            SettingsStore.shared.ignore(path: url.path)
        } else {
            SettingsStore.shared.ignore(itemID: item.id)
        }
        groups.removeItems(withIDs: [item.id])
    }
}

// MARK: - Screen model

/// State of the Applications module: overview, Uninstaller, Updater, Leftovers,
/// Installers and Extensions. One instance per engine, so results survive navigation.
@MainActor
@Observable
final class ApplicationsScreenModel {
    private static var instances: [ObjectIdentifier: ApplicationsScreenModel] = [:]

    static func shared(for engine: ApplicationsEngine) -> ApplicationsScreenModel {
        let key = ObjectIdentifier(engine)
        if let existing = instances[key] { return existing }
        let model = ApplicationsScreenModel(engine: engine)
        instances[key] = model
        return model
    }

    let engine: ApplicationsEngine
    let leftovers: ApplicationsFileReview
    let installers: ApplicationsFileReview

    var route: ApplicationsRoute = .hub

    // Catalog
    private(set) var apps: [ApplicationsAppInfo] = []
    private(set) var catalogPhase: ApplicationsLoadPhase = .idle
    private(set) var catalogProgress = ScanProgress(message: "")
    private(set) var sizesMeasured = false
    private(set) var isMeasuring = false

    // Overview
    private(set) var overviewPhase: ApplicationsOverviewPhase = .idle
    private(set) var overviewSteps: [PrismScanStep] = []
    private(set) var overviewProgress = ScanProgress(message: "")

    // Uninstaller
    var facet: ApplicationsAppFacet = .all
    var search = ""
    var sort: ApplicationsAppSort = .name
    var sortReversed = false
    var selectedAppIDs: Set<String> = []
    var detail: ApplicationsDetailState?
    var uninstallRequest: ApplicationsUninstallRequest?
    private(set) var runState: ApplicationsRunState = .none
    private(set) var runTitle = "Uninstalling…"

    // Updater
    private(set) var allUpdates: [ApplicationsUpdate] = []
    private(set) var updatesPhase: ApplicationsLoadPhase = .idle
    private(set) var updatesProgress = ScanProgress(message: "")
    private(set) var updatesCheckedAt: Date?
    var selectedUpdateID: String?
    var selectedUpdateIDs: Set<String> = []
    var updateSearch = ""
    var showIgnoredUpdates = false
    private(set) var updateStatus: [String: ApplicationsUpdateRowStatus] = [:]
    private(set) var isInstallingUpdates = false
    var updateQuitPrompt: ApplicationsUpdateQuitPrompt?

    // Extensions
    private(set) var extensions: [ApplicationsExtensionInfo] = []
    private(set) var extensionsPhase: ApplicationsLoadPhase = .idle
    var extensionKind: ApplicationsExtensionKind?
    var extensionSearch = ""
    private(set) var busyExtensionIDs: Set<String> = []
    var extensionRemoval: ApplicationsExtensionInfo?

    var toast: ApplicationsToast?

    private var overviewTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?

    init(engine: ApplicationsEngine) {
        self.engine = engine
        leftovers = ApplicationsFileReview(kind: .leftovers, engine: engine)
        installers = ApplicationsFileReview(kind: .installers, engine: engine)
        // Reuse what an earlier Checkup scan already found.
        let known = engine.lastApps
        if !known.isEmpty {
            apps = known
            catalogPhase = .ready
            sizesMeasured = known.contains { !$0.isSystem && $0.size > 0 }
        }
        if let checked = engine.updatesCheckedAt {
            allUpdates = engine.lastUpdates
            updatesCheckedAt = checked
            updatesPhase = .ready
        }
    }

    var settings: SpruceSettings { SettingsStore.shared.settings }

    // MARK: Navigation

    func goHub() {
        route = .hub
    }

    /// Opens a tool and loads what it needs.
    func open(_ tool: ApplicationsTool) {
        route = .tool(tool)
        switch tool {
        case .uninstaller:
            ensureCatalog()
        case .updater:
            ensureCatalog()
            ensureUpdates()
        case .leftovers:
            if leftovers.phase == .idle { leftovers.scan() }
        case .installers:
            if installers.phase == .idle { installers.scan() }
        case .extensions:
            if extensionsPhase == .idle { loadExtensions() }
        }
    }

    /// Opens the Uninstaller on a facet (e.g. Unused from the overview tile).
    func openUninstaller(facet: ApplicationsAppFacet) {
        self.facet = facet
        detail = nil
        open(.uninstaller)
    }

    // MARK: Catalog

    func ensureCatalog() {
        if catalogPhase == .idle {
            loadCatalog()
        } else if catalogPhase == .ready && !sizesMeasured {
            measureSizes()
        }
    }

    /// Reads every app (fast, without sizes), then measures sizes in the background.
    func loadCatalog() {
        guard catalogPhase != .loading else { return }
        catalogTask?.cancel()
        catalogPhase = .loading
        catalogProgress = ScanProgress(fraction: nil, message: "Finding applications…")
        let engine = self.engine
        let report: ProgressHandler = { p in
            Task { @MainActor [weak self] in
                guard let self, self.catalogPhase == .loading else { return }
                self.catalogProgress = p
            }
        }
        catalogTask = Task { [weak self] in
            let loaded = await engine.loadApps(measureSizes: false, progress: report)
            guard let self, !Task.isCancelled else { return }
            self.apps = loaded
            self.sizesMeasured = false
            self.catalogPhase = .ready
            self.pruneSelection()
            self.measureSizes()
        }
    }

    /// Measures app sizes (cached per version by the engine) without blocking the list.
    func measureSizes() {
        guard !isMeasuring, !sizesMeasured, catalogPhase == .ready else { return }
        isMeasuring = true
        let engine = self.engine
        Task { [weak self] in
            let measured = await engine.loadApps(measureSizes: true)
            guard let self else { return }
            // An app uninstalled while sizes were measured must not come back.
            let fm = FileManager.default
            self.apps = measured.filter { fm.fileExists(atPath: $0.path) }
            self.sizesMeasured = true
            self.isMeasuring = false
            self.pruneSelection()
            if let detail = self.detail, let fresh = self.apps.first(where: { $0.path == detail.app.path }) {
                self.detail?.app = fresh
            }
        }
    }

    /// Drops selections of apps that are gone.
    private func pruneSelection() {
        let paths = Set(apps.map(\.path))
        selectedAppIDs = selectedAppIDs.filter { paths.contains($0) }
    }

    var removableApps: [ApplicationsAppInfo] {
        let ignored = Set(settings.ignoredBundleIDs.map { $0.lowercased() })
        return apps.filter { !$0.isSystem && !ignored.contains($0.bundleID.lowercased()) }
    }

    /// Apps listed in the Uninstaller (ignored bundle ids are hidden; system apps under macOS).
    private var listableApps: [ApplicationsAppInfo] {
        let ignored = Set(settings.ignoredBundleIDs.map { $0.lowercased() })
        return apps.filter { $0.isSystem || !ignored.contains($0.bundleID.lowercased()) }
    }

    var unusedApps: [ApplicationsAppInfo] {
        let days = settings.unusedAppDays
        return removableApps.filter { ApplicationsUnusedRule.isUnused($0, days: days) }
    }

    var intelOnlyApps: [ApplicationsAppInfo] { removableApps.filter(\.isIntelOnly) }

    var totalAppsSize: Int64 { removableApps.reduce(0) { $0 + $1.size } }

    /// Apps for the current facet, search and sort.
    var visibleApps: [ApplicationsAppInfo] {
        let faceted = ApplicationsAppFilter.apps(listableApps, facet: facet, unusedDays: settings.unusedAppDays,
                                                 selected: selectedAppIDs)
        let searched = ApplicationsAppFilter.search(faceted, query: search)
        return ApplicationsAppFilter.sorted(searched, by: sort, ascending: !sortReversed)
    }

    func count(for facet: ApplicationsAppFacet) -> Int {
        ApplicationsAppFilter.apps(listableApps, facet: facet, unusedDays: settings.unusedAppDays,
                                   selected: selectedAppIDs).count
    }

    var vendorFacets: [(name: String, count: Int)] {
        ApplicationsAppFilter.vendors(removableApps)
    }

    /// Source facets that have apps (Other always shows).
    var sourceFacets: [ApplicationsAppFacet] {
        var facets: [ApplicationsAppFacet] = []
        let sources = Set(removableApps.map(\.source))
        if sources.contains(.appStore) { facets.append(.appStore) }
        if sources.contains(.homebrew) { facets.append(.homebrew) }
        if sources.contains(.setapp) { facets.append(.setapp) }
        if sources.contains(.steam) { facets.append(.steam) }
        facets.append(.otherSource)
        return facets
    }

    var selectedApps: [ApplicationsAppInfo] {
        apps.filter { selectedAppIDs.contains($0.id) && $0.canUninstall }
    }

    var selectedAppsSize: Int64 { selectedApps.reduce(0) { $0 + $1.size } }

    func toggleSelection(_ app: ApplicationsAppInfo) {
        guard app.canUninstall else { return }
        if selectedAppIDs.contains(app.id) {
            selectedAppIDs.remove(app.id)
        } else {
            selectedAppIDs.insert(app.id)
        }
    }

    /// Selects or clears every removable app in the current list.
    func setVisibleSelected(_ selected: Bool) {
        let ids = visibleApps.filter(\.canUninstall).map(\.id)
        if selected {
            selectedAppIDs.formUnion(ids)
        } else {
            selectedAppIDs.subtract(ids)
        }
    }

    var visibleSelectionState: SelectionState {
        let removable = visibleApps.filter(\.canUninstall)
        guard !removable.isEmpty else { return .none }
        let count = removable.filter { selectedAppIDs.contains($0.id) }.count
        if count == 0 { return .none }
        return count == removable.count ? .all : .some
    }

    func ignoreApp(_ app: ApplicationsAppInfo) {
        guard !app.bundleID.isEmpty else { return }
        SettingsStore.shared.ignore(bundleID: app.bundleID)
        selectedAppIDs.remove(app.id)
        if detail?.app.path == app.path { detail = nil }
        toast = ApplicationsToast(message: "\(app.name) won't be offered for removal or updates. Manage the ignore list in Settings.")
    }

    // MARK: Detail

    func showDetail(_ app: ApplicationsAppInfo) {
        detail = ApplicationsDetailState(app: app)
        loadComponents(mode: .uninstall)
    }

    func closeDetail() {
        detail = nil
    }

    /// Finds the app's files and applies the default selection for `mode`.
    func loadComponents(mode: ApplicationsUninstallMode) {
        guard let app = detail?.app else { return }
        detail?.isLoading = true
        let engine = self.engine
        Task { [weak self] in
            let groups = await engine.components(for: app, mode: mode)
            guard let self, self.detail?.app.path == app.path else { return }
            self.detail?.groups = groups
            self.detail?.isLoading = false
        }
    }

    /// The Uninstall / Reset selector: re-applies that mode's default selection.
    func applyDetailMode(_ mode: ApplicationsUninstallMode) {
        guard var current = detail else { return }
        ApplicationsComponents.apply(mode: mode, to: &current.groups)
        detail = current
    }

    var detailMode: ApplicationsUninstallMode? {
        guard let detail, !detail.groups.isEmpty else { return nil }
        return ApplicationsComponents.mode(of: detail.groups)
    }

    func toggleDetailItem(_ itemID: String) {
        guard let item = detail?.groups.allItems.first(where: { $0.id == itemID }) else { return }
        detail?.groups.setSelected(!item.isSelected, itemID: itemID)
    }

    func setDetailGroup(_ groupID: String, selected: Bool) {
        guard let index = detail?.groups.firstIndex(where: { $0.id == groupID }) else { return }
        detail?.groups[index].setAllSelected(selected)
    }

    func ignoreDetailItem(_ item: ScanItem) {
        if let url = item.url {
            SettingsStore.shared.ignore(path: url.path)
        } else {
            SettingsStore.shared.ignore(itemID: item.id)
        }
        detail?.groups.removeItems(withIDs: [item.id])
    }

    /// Title of the detail pane's action for the current selection.
    var detailActionTitle: String {
        guard let detail else { return "Uninstall" }
        let items = detail.groups.selectedItems
        if ApplicationsComponents.removesApp(items) { return "Uninstall" }
        if !items.isEmpty && items.allSatisfy({ $0.metadata[ApplicationsMeta.resetData] == "1" }) { return "Reset" }
        return "Remove"
    }

    // MARK: Uninstall / reset

    /// Asks to uninstall apps from the list with their default file selection.
    func requestUninstall(_ apps: [ApplicationsAppInfo]) {
        let removable = apps.filter(\.canUninstall)
        guard !removable.isEmpty else { return }
        presentRequest(ApplicationsUninstallRequest(apps: removable, items: nil))
    }

    /// Asks to act on the detail pane's selection.
    func requestDetailAction() {
        guard let detail, detail.app.canUninstall else { return }
        let items = detail.groups.selectedItems
        guard !items.isEmpty else { return }
        presentRequest(ApplicationsUninstallRequest(apps: [detail.app], items: items))
    }

    private func presentRequest(_ request: ApplicationsUninstallRequest) {
        let engine = self.engine
        let candidates = request.apps
        Task { [weak self] in
            let open = await engine.runningApps(among: candidates)
            guard let self else { return }
            var ready = request
            ready.openApps = open
            self.uninstallRequest = ready
        }
    }

    func cancelUninstall() {
        uninstallRequest = nil
    }

    /// Runs the confirmed request: quits the apps, then moves everything to the Trash.
    func confirmUninstall() {
        guard let request = uninstallRequest else { return }
        uninstallRequest = nil
        runTask?.cancel()
        runTitle = request.removesApps ? "Uninstalling…" : (request.isReset ? "Resetting…" : "Removing files…")
        runState = .running(ScanProgress(fraction: nil, message: request.items == nil ? "Finding the apps' files…" : "Preparing…"))
        let engine = self.engine
        let report: ProgressHandler = { p in
            Task { @MainActor [weak self] in
                guard let self, case .running = self.runState else { return }
                self.runState = .running(p)
            }
        }
        runTask = Task { [weak self] in
            var items = request.items ?? []
            if request.items == nil {
                items = await engine.defaultUninstallItems(for: request.apps)
            }
            let outcome = await engine.uninstall(items, progress: report)
            guard let self else { return }
            let removedIDs = Set(outcome.removedItemIDs)
            let removedAppPaths = Set(items.filter {
                $0.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.application.rawValue && removedIDs.contains($0.id)
            }.compactMap { $0.metadata[ApplicationsMeta.appPath] })
            if !removedAppPaths.isEmpty {
                self.apps.removeAll { removedAppPaths.contains($0.path) }
                self.selectedAppIDs.subtract(removedAppPaths)
                // The leftovers list was built with the old catalog; refresh it in the background.
                if self.leftovers.phase == .results { self.leftovers.scan() }
            }
            HistoryStore.shared.record(outcome, kind: removedAppPaths.isEmpty ? .clean : .uninstall)
            self.runState = .done(outcome, removedApps: !removedAppPaths.isEmpty)
        }
    }

    /// Leaves the done screen: back to the list after an uninstall, back to the refreshed
    /// detail after a reset.
    func finishRun() {
        guard case .done(_, let removedApps) = runState else {
            runState = .none
            return
        }
        runState = .none
        guard let current = detail else { return }
        if removedApps || !FileManager.default.fileExists(atPath: current.app.path) {
            detail = nil
        } else {
            let app = current.app
            let engine = self.engine
            Task { [weak self] in
                let refreshed = await engine.refreshApp(app)
                guard let self, self.detail?.app.path == app.path else { return }
                if let refreshed {
                    self.detail?.app = refreshed
                    if let index = self.apps.firstIndex(where: { $0.path == app.path }) { self.apps[index] = refreshed }
                }
                self.loadComponents(mode: .uninstall)
            }
        }
    }

    // MARK: Mutators (used by the Updater and Extensions extension in another file)

    func setUpdatesPhase(_ phase: ApplicationsLoadPhase) { updatesPhase = phase }
    func setUpdatesProgress(_ progress: ScanProgress) { updatesProgress = progress }

    func replaceUpdates(_ updates: [ApplicationsUpdate], checkedAt: Date) {
        allUpdates = updates
        updatesCheckedAt = checkedAt
        // Statuses of finished installs no longer apply to a fresh list.
        updateStatus = updateStatus.filter { entry in
            if case .updating = entry.value { return true }
            if case .queued = entry.value { return true }
            return false
        }
    }

    func setStatus(_ status: ApplicationsUpdateRowStatus, for updateID: String) { updateStatus[updateID] = status }
    func setInstalling(_ installing: Bool) { isInstallingUpdates = installing }

    func replaceApp(_ app: ApplicationsAppInfo) {
        if let index = apps.firstIndex(where: { $0.path == app.path }) { apps[index] = app }
        if detail?.app.path == app.path { detail?.app = app }
    }

    func setExtensionsPhase(_ phase: ApplicationsLoadPhase) { extensionsPhase = phase }
    func replaceExtensions(_ list: [ApplicationsExtensionInfo]) { extensions = list }

    func setBusy(_ busy: Bool, extensionID: String) {
        if busy { busyExtensionIDs.insert(extensionID) } else { busyExtensionIDs.remove(extensionID) }
    }

    func updateExtension(_ id: String, _ change: (inout ApplicationsExtensionInfo) -> Void) {
        guard let index = extensions.firstIndex(where: { $0.id == id }) else { return }
        change(&extensions[index])
    }

    // MARK: Overview

    /// Scans everything for the overview tiles. The catalog, leftovers, installers and
    /// extensions are quick; sizes and update checks continue in the background.
    func startOverview() {
        overviewTask?.cancel()
        overviewPhase = .scanning
        overviewProgress = ScanProgress(fraction: nil, message: "Finding applications…")
        overviewSteps = [
            PrismScanStep(id: "apps", title: "Applications", symbol: "square.grid.2x2", state: .running),
            PrismScanStep(id: "leftovers", title: "Files from removed apps", symbol: "questionmark.folder"),
            PrismScanStep(id: "installers", title: "Old installers", symbol: "shippingbox"),
            PrismScanStep(id: "extensions", title: "Extensions", symbol: "puzzlepiece.extension"),
        ]
        let engine = self.engine
        catalogPhase = .loading
        let report: ProgressHandler = { p in
            Task { @MainActor [weak self] in
                guard let self, self.overviewPhase == .scanning else { return }
                self.overviewProgress = ScanProgress(fraction: nil, message: "Reading applications…", current: p.current)
            }
        }
        overviewTask = Task { [weak self] in
            let loaded = await engine.loadApps(measureSizes: false, progress: report)
            guard let self, !Task.isCancelled else { return }
            self.apps = loaded
            self.sizesMeasured = false
            self.catalogPhase = .ready
            self.pruneSelection()
            self.setStep("apps", .done(CountFormat.items(self.removableApps.count, singular: "app")))
            for id in ["leftovers", "installers", "extensions"] { self.setStep(id, .running) }
            self.overviewProgress = ScanProgress(fraction: nil, message: "Looking for leftovers and installers…")

            async let leftoverScan = engine.scanLeftovers(progress: nil)
            async let installerScan = engine.scanInstallers(progress: nil)
            async let extensionScan = engine.loadExtensions()
            let leftoverGroups = await leftoverScan
            self.setStep("leftovers", .done(leftoverGroups.isEmpty ? "None" : ByteFormat.string(leftoverGroups.totalSize)))
            let installerGroups = await installerScan
            self.setStep("installers", .done(installerGroups.isEmpty ? "None" : ByteFormat.string(installerGroups.totalSize)))
            let foundExtensions = await extensionScan
            self.setStep("extensions", .done(CountFormat.items(foundExtensions.count)))
            guard !Task.isCancelled else { return }

            self.leftovers.seed(leftoverGroups)
            self.installers.seed(installerGroups)
            self.extensions = foundExtensions
            self.extensionsPhase = .ready
            self.overviewPhase = .ready
            HistoryStore.shared.record(ActivityEntry(
                module: .applications, kind: .scan, bytes: leftoverGroups.totalSize + installerGroups.totalSize,
                count: leftoverGroups.allItems.count + installerGroups.allItems.count,
                summary: "Found \(CountFormat.items(self.removableApps.count, singular: "app")) and \(ByteFormat.string(leftoverGroups.totalSize + installerGroups.totalSize)) to tidy"))
            self.measureSizes()
            // Update checks use the network; they follow Settings › Notifications › updates.
            if self.settings.notifyUpdates && self.updatesPhase != .loading {
                self.checkUpdates()
            }
        }
    }

    func cancelOverview() {
        overviewTask?.cancel()
        overviewTask = nil
        if catalogPhase == .loading { catalogPhase = apps.isEmpty ? .idle : .ready }
        overviewPhase = .idle
    }

    private func setStep(_ id: String, _ state: PrismScanStep.State) {
        guard let index = overviewSteps.firstIndex(where: { $0.id == id }) else { return }
        overviewSteps[index].state = state
    }
}
