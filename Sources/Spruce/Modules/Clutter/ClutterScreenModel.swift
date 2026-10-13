import AppKit
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Navigation & phases

enum ClutterPhase: Equatable {
    case idle
    case scanning
    case results
    case removing
    case done
    case failed(String)
}

enum ClutterRoute: Equatable {
    case dashboard
    case tool(ClutterTool)
}

/// A pending "Move to Trash" confirmation.
struct ClutterRemovalRequest: Identifiable {
    let id = UUID()
    var items: [ScanItem]
    var bytes: Int64
    /// Duplicate sets / similar clusters whose every member is selected.
    var completeSets: Int
    /// The tool the request came from (nil = all tools).
    var tool: ClutterTool?
}

/// Large & Old Files sidebar facet (one at a time, like a Finder sidebar).
enum ClutterLargeOldFacet: Hashable {
    case scope(ClutterLargeOldQuery.Scope)
    case kind(ClutterKind)
    case size(ClutterSizeBucket)
    case age(ClutterAgeBucket)
}

/// Downloads list filter.
enum ClutterDownloadsFacet: Hashable {
    case all
    case category(ClutterDownloadCategory)
    case source(String)
    case selected
}

/// Sort orders for the Downloads list.
enum ClutterDownloadsSort: String, CaseIterable {
    case size = "Size"
    case date = "Date"
    case name = "Name"
}

/// Ways to pick the copies of a duplicate set to remove.
enum ClutterCopySelection: String, CaseIterable, Identifiable {
    case smart
    case allButNewest
    case allButOldest
    case clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "Smart Selection"
        case .allButNewest: return "All but the Newest"
        case .allButOldest: return "All but the Oldest"
        case .clear: return "None"
        }
    }

    var symbol: String {
        switch self {
        case .smart: return "wand.and.stars"
        case .allButNewest: return "clock.arrow.circlepath"
        case .allButOldest: return "clock"
        case .clear: return "circle"
        }
    }
}

/// A short message at the bottom of the module (folders added by a drop or from Finder).
struct ClutterToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var isError = false
}

/// A source of downloads (app or website) with its totals.
struct ClutterDownloadSource: Identifiable, Hashable {
    var label: String
    var count: Int
    var bytes: Int64
    var id: String { label }
}

// MARK: - Screen model

/// State of the Clutter module: locations, scan, results, selection and removal.
/// One instance per engine, so results survive navigation.
@MainActor
@Observable
final class ClutterScreenModel {
    private static var instances: [ObjectIdentifier: ClutterScreenModel] = [:]

    static func shared(for engine: ClutterEngine) -> ClutterScreenModel {
        let key = ObjectIdentifier(engine)
        if let existing = instances[key] { return existing }
        let model = ClutterScreenModel(engine: engine)
        instances[key] = model
        return model
    }

    let engine: ClutterEngine
    let settings = SettingsStore.shared

    private(set) var phase: ClutterPhase = .idle
    var route: ClutterRoute = .dashboard
    private(set) var progress = ScanProgress(message: "")
    private(set) var steps: [PrismScanStep] = []
    private(set) var report: ClutterScanReport?
    private(set) var outcome: RunOutcome?
    /// Selected file paths (shared by every tool, so a file selected in one tool is
    /// selected everywhere it appears).
    var selection: Set<String> = []
    /// A tool requested before results existed; opened right after the scan.
    var focusTool: ClutterTool?
    var removalRequest: ClutterRemovalRequest?
    var confirmNewScan = false
    var previewURL: URL?
    /// Shown at the bottom of the module, then dismissed after a few seconds.
    var toast: ClutterToast?
    /// Mounted volumes, location names and availability, probed off the main thread so
    /// rendering never touches the disk (see `refreshVolumes()`).
    private(set) var locationStatus = ClutterLocationStatus()

    // Tool view state (kept while navigating between tools).
    var largeOldQuery = ClutterLargeOldQuery()
    var focusedDuplicateID: String?
    var duplicatesSearch = ""
    var focusedClusterID: String?
    var similarSearch = ""
    var downloadsFacet: ClutterDownloadsFacet = .all
    var downloadsSort: ClutterDownloadsSort = .size
    var downloadsSearch = ""

    // Indexes rebuilt when the report changes.
    private(set) var filesByPath: [String: ClutterFile] = [:]
    private var duplicateSetByPath: [String: String] = [:]
    private var clusterByPath: [String: String] = [:]
    private var downloadPaths: Set<String> = []

    private var task: Task<Void, Never>?
    private var lastScanTools: Set<ClutterTool> = Set(ClutterTool.allCases)
    @ObservationIgnored private var isProbingLocations = false
    @ObservationIgnored private var needsLocationProbe = false

    init(engine: ClutterEngine) {
        self.engine = engine
        if let existing = engine.lastReport {
            let visible = withoutIgnored(existing)
            setReport(visible)
            selection = visible.defaultSelection(settings: scanSettings)
            lastScanTools = visible.scannedTools
            phase = .results
        }
    }

    var scanSettings: ClutterScanSettings { ClutterScanSettings(settings.settings) }
    var isBusy: Bool { phase == .scanning || phase == .removing }

    // MARK: Locations

    /// Chosen locations (settings form).
    var locations: [String] { settings.settings.clutterLocations }

    /// Chosen locations that were there at the last probe (new ones count until probed;
    /// the engine checks again before walking).
    var availableLocations: [String] { locations.filter { locationStatus.isAvailable($0) } }

    /// Chosen locations that are missing right now (unmounted disks, renamed folders).
    var missingLocations: [String] { locations.filter { !locationStatus.isAvailable($0) } }

    /// Mounted volumes (from the last probe).
    var volumes: [ClutterLocationOption] { locationStatus.volumes }

    /// Whether a location was available at the last probe (no file-system access).
    func isLocationAvailable(_ path: String) -> Bool {
        locationStatus.isAvailable(path)
    }

    /// Display option for a location (no file-system access).
    func locationOption(for path: String) -> ClutterLocationOption {
        locationStatus.option(for: path)
    }

    /// "Home", "Documents and Photos SSD", "3 locations" (no file-system access).
    func locationSummary(_ paths: [String]) -> String {
        ClutterLocations.summary(titles: paths.map { locationOption(for: $0).title })
    }

    /// Whether the scan the orb would start can run.
    var canStartScan: Bool {
        focusTool == .downloads || !availableLocations.isEmpty
    }

    func isLocationSelected(_ option: ClutterLocationOption) -> Bool {
        locations.contains { ClutterLocations.canonical($0) == option.id }
    }

    /// Toggles a location. Home and the folders inside it are exclusive: choosing Home
    /// replaces Desktop/Documents/Downloads, choosing one of those replaces Home.
    func toggleLocation(_ option: ClutterLocationOption) {
        var current = locations
        let key = option.id
        if let index = current.firstIndex(where: { ClutterLocations.canonical($0) == key }) {
            current.remove(at: index)
        } else {
            let home = ClutterLocations.canonical("~")
            if key == home {
                current.removeAll { ClutterPaths.isInside(ClutterLocations.canonical($0), home) }
            } else if ClutterPaths.isInside(key, home) {
                current.removeAll { ClutterLocations.canonical($0) == home }
            }
            current.removeAll { ClutterPaths.isInside(key, ClutterLocations.canonical($0)) }
            current.removeAll { ClutterPaths.isInside(ClutterLocations.canonical($0), key) }
            current.append(ClutterLocations.storedForm(option.path))
        }
        settings.settings.clutterLocations = current
    }

    func removeLocation(_ path: String) {
        let key = ClutterLocations.canonical(path)
        settings.settings.clutterLocations = locations.filter { ClutterLocations.canonical($0) != key }
    }

    /// Custom folders (not one of the standard folders or a mounted volume), including
    /// chosen locations that are currently missing.
    var customLocations: [ClutterLocationOption] {
        let known = Set(ClutterLocations.standard.map(\.id) + volumes.map(\.id))
        return locations.filter { !known.contains(ClutterLocations.canonical($0)) }.map { locationOption(for: $0) }
    }

    /// Re-probes mounted volumes and the chosen and standard locations on a background
    /// queue (on appear, on mount/unmount, when the app becomes active and when the chosen
    /// locations change). One probe runs at a time; requests made meanwhile collapse into
    /// one follow-up probe, so a disk that stops answering never stalls the UI.
    func refreshVolumes() {
        guard !isProbingLocations else {
            needsLocationProbe = true
            return
        }
        isProbingLocations = true
        needsLocationProbe = false
        let paths = locations + ClutterLocations.standard.map(\.path)
        Task { [weak self] in
            let status = await ClutterLocations.loadStatus(for: paths)
            guard let self else { return }
            self.isProbingLocations = false
            if self.locationStatus != status { self.locationStatus = status }
            if self.needsLocationProbe { self.refreshVolumes() }
        }
    }

    /// Lets the user pick folders or disks to scan.
    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose folders or disks for Clutter to scan."
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK else { return }
        addLocations(panel.urls.map(\.path))
    }

    /// Adds folders or disks to the chosen locations. A folder inside a chosen location is
    /// already covered; chosen locations inside a new folder give way to it. Returns the
    /// stored forms of what was added and of what was already covered.
    @discardableResult
    func addLocations(_ paths: [String]) -> (added: [String], covered: [String]) {
        var current = locations
        var added: [String] = []
        var covered: [String] = []
        for path in paths {
            let stored = ClutterLocations.storedForm(path)
            let key = ClutterLocations.canonical(stored)
            if current.contains(where: {
                let existing = ClutterLocations.canonical($0)
                return existing == key || ClutterPaths.isInside(key, existing)
            }) {
                covered.append(stored)
                continue
            }
            current.removeAll { ClutterPaths.isInside(ClutterLocations.canonical($0), key) }
            current.append(stored)
            added.append(stored)
        }
        if current != locations {
            settings.settings.clutterLocations = current
        }
        return (added, covered)
    }

    // MARK: Drops and Finder

    /// Folders dropped on the module or handed over from Finder ("Find Clutter with
    /// Spruce") join the places Clutter scans; files and app bundles are skipped. It never
    /// starts a scan or removes anything, and a running scan keeps its locations (the new
    /// ones count from the next scan). Returns false when nothing could be a folder.
    @discardableResult
    func receiveFolders(_ urls: [URL]) -> Bool {
        let candidates = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !candidates.isEmpty else { return false }
        Task { [weak self] in
            // Reading the items can block on a slow disk: off the main thread.
            let folders = await Task.detached(priority: .userInitiated) {
                ClutterScreenModel.folders(in: candidates)
            }.value
            self?.adoptFolders(folders, offered: candidates.count)
        }
        return true
    }

    /// Paths of the folders and disks among `urls` (packages such as apps excluded).
    nonisolated static func folders(in urls: [URL]) -> [String] {
        urls.compactMap { url -> String? in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
                  values.isDirectory == true, values.isPackage != true else { return nil }
            return url.path
        }
    }

    private func adoptFolders(_ folders: [String], offered: Int) {
        guard !folders.isEmpty else {
            toast = ClutterToast(message: offered == 1
                                    ? "Clutter looks in folders and disks. Drop a folder instead."
                                    : "Clutter looks in folders and disks, and none of those is one.",
                                 isError: true)
            return
        }
        let result = addLocations(folders)
        if !result.added.isEmpty, case .failed = phase { dismissFailure() }
        let title = { (path: String) in "“\(self.locationOption(for: path).title)”" }
        var parts: [String] = []
        if !result.added.isEmpty {
            let what = result.added.count == 1 ? title(result.added[0]) : "\(result.added.count) folders"
            var line = "Added \(what) to the places Clutter looks in."
            if report != nil || isBusy { line += " The next scan includes \(result.added.count == 1 ? "it" : "them")." }
            parts.append(line)
        }
        if !result.covered.isEmpty {
            let what = result.covered.count == 1 ? title(result.covered[0]) : "\(result.covered.count) folders"
            parts.append("\(what) \(result.covered.count == 1 ? "is" : "are") already included.")
        }
        toast = ClutterToast(message: parts.joined(separator: " "), isError: result.added.isEmpty)
    }

    // MARK: Scanning

    /// Scans every tool, or only `focusTool` when the user arrived from a tool shortcut.
    func startScan(tools requested: Set<ClutterTool>? = nil) {
        task?.cancel()
        let tools: Set<ClutterTool> = requested ?? focusTool.map { Set([$0]) } ?? Set(ClutterTool.allCases)
        lastScanTools = tools
        let needsLocations = tools.contains(.largeOld) || tools.contains(.duplicates) || tools.contains(.similarImages)
        if needsLocations && availableLocations.isEmpty {
            phase = .failed("None of the chosen locations is available. Choose a folder or connect the disk, then scan again.")
            return
        }
        phase = .scanning
        outcome = nil
        progress = ScanProgress(fraction: nil, message: "Starting…")
        steps = []
        let engine = self.engine
        let locations = availableLocations
        // Built here (not inside the task) so it captures `self` weakly by value.
        let onProgress: ProgressHandler = { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .scanning else { return }
                self.progress = p
                self.steps = Self.steps(from: engine.stageBoard)
            }
        }
        task = Task { [weak self] in
            do {
                let result = try await engine.scanAll(locations: locations, tools: tools, progress: onProgress)
                guard let self, !Task.isCancelled else { return }
                self.finishScan(result)
            } catch {
                guard let self, !Task.isCancelled else { return }
                if (error as? SpruceError) == .cancelled {
                    self.phase = self.report == nil ? .idle : .results
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func finishScan(_ scanned: ClutterScanReport) {
        let result = withoutIgnored(scanned)
        let previous = report
        let previousSelection = selection
        setReport(result)
        var next = result.defaultSelection(settings: scanSettings)
        if let previous {
            // Adding a tool to earlier results: keep the choices made in tools already reviewed.
            let carried = previous.scannedTools.intersection(result.scannedTools)
            if !carried.isEmpty {
                var reviewed = Set<String>()
                for tool in carried { reviewed.formUnion(previous.paths(in: tool)) }
                next.subtract(reviewed)
                next.formUnion(previousSelection.intersection(Set(filesByPath.keys)))
            }
        }
        selection = next
        phase = .results
        if let tool = focusTool, result.scannedTools.contains(tool) {
            route = .tool(tool)
        } else {
            route = .dashboard
        }
        focusTool = nil
        HistoryStore.shared.record(ActivityEntry(module: .clutter, kind: .scan, bytes: result.distinctBytes,
                                                 count: result.distinctFileCount,
                                                 summary: "Found \(CountFormat.items(result.distinctFileCount, singular: "file")) worth a look"))
    }

    func cancelScan() {
        task?.cancel()
        task = nil
        focusTool = nil
        phase = report == nil ? .idle : .results
    }

    /// Discards the results and returns to the location chooser.
    func newScan() {
        task?.cancel()
        engine.discardReport()
        setReport(nil)
        selection = []
        outcome = nil
        route = .dashboard
        focusTool = nil
        largeOldQuery = ClutterLargeOldQuery()
        downloadsFacet = .all
        duplicatesSearch = ""
        similarSearch = ""
        downloadsSearch = ""
        phase = .idle
    }

    /// Re-runs the last scan (e.g. from the failure screen).
    func retry() {
        startScan(tools: lastScanTools)
    }

    /// Leaves the failure screen: back to the results, or to the location chooser.
    func dismissFailure() {
        phase = report == nil ? .idle : .results
    }

    static func steps(from board: ClutterStageBoard) -> [PrismScanStep] {
        board.snapshot.map { entry in
            let state: PrismScanStep.State
            var label: String?
            switch entry.state {
            case .waiting:
                state = .waiting
            case .running(let fraction):
                state = .running
                if let fraction, fraction > 0 { label = "\(Int((fraction * 100).rounded()))%" }
            case .done(let text):
                state = .done(text)
            case .skipped(let text):
                state = .skipped(text)
            }
            return PrismScanStep(id: entry.stage.rawValue, title: entry.stage.title, symbol: entry.stage.symbol,
                                 state: state, runningLabel: label)
        }
    }

    // MARK: Navigation

    /// Opens a tool, or scans for it first when the current results don't cover it.
    func open(_ tool: ClutterTool) {
        switch phase {
        case .results, .done:
            if let report, report.scannedTools.contains(tool) {
                outcome = nil
                phase = .results
                route = .tool(tool)
            } else {
                focusTool = tool
                startScan(tools: (report?.scannedTools ?? []).union([tool]))
            }
        case .scanning, .removing:
            focusTool = tool
        case .idle, .failed:
            focusTool = tool
            if case .failed = phase { phase = .idle }
        }
    }

    func showDashboard() {
        route = .dashboard
    }

    /// From the done screen back to the remaining results.
    func showRemaining() {
        outcome = nil
        if let report, !report.isEmpty {
            phase = .results
        } else {
            newScan()
        }
    }

    // MARK: Report indexes

    private func setReport(_ newReport: ClutterScanReport?) {
        report = newReport
        filesByPath = newReport?.filesByPath ?? [:]
        var dup: [String: String] = [:]
        var sim: [String: String] = [:]
        for group in newReport?.duplicates ?? [] { for file in group.files { dup[file.path] = group.id } }
        for cluster in newReport?.similar ?? [] { for file in cluster.files { sim[file.path] = cluster.id } }
        duplicateSetByPath = dup
        clusterByPath = sim
        downloadPaths = Set(newReport?.downloads.map(\.file.path) ?? [])
        selection.formIntersection(Set(filesByPath.keys))
        if let id = focusedDuplicateID, !(newReport?.duplicates.contains { $0.id == id } ?? false) { focusedDuplicateID = nil }
        if let id = focusedClusterID, !(newReport?.similar.contains { $0.id == id } ?? false) { focusedClusterID = nil }
        if case .source(let label) = downloadsFacet,
           !(newReport?.downloads.contains { $0.sourceLabel == label } ?? false) {
            downloadsFacet = .all
        }
    }

    /// The report without files that are on the ignore list now.
    private func withoutIgnored(_ input: ClutterScanReport) -> ClutterScanReport {
        let current = settings.settings
        let ignored = Set(input.filesByPath.keys.filter { current.isIgnored(path: $0) || current.ignoredItemIDs.contains($0) })
        guard !ignored.isEmpty else { return input }
        var copy = input
        copy.remove(paths: ignored)
        return copy
    }

    func paths(in tool: ClutterTool) -> [String] {
        report?.paths(in: tool) ?? []
    }

    func summary(for tool: ClutterTool) -> ClutterToolSummary {
        (report ?? ClutterScanReport(scannedTools: [])).summary(for: tool)
    }

    func wasScanned(_ tool: ClutterTool) -> Bool {
        report?.scannedTools.contains(tool) ?? false
    }

    /// A few representative files of a tool (for dashboard thumbnails).
    func samplePaths(for tool: ClutterTool, limit: Int = 5) -> [String] {
        guard let report else { return [] }
        switch tool {
        case .largeOld: return Array(report.largeOld.prefix(limit).map(\.file.path))
        case .duplicates: return Array(report.duplicates.prefix(limit).map { $0.keeperPath })
        case .similarImages: return Array(report.similar.prefix(limit).map(\.bestPath))
        case .downloads: return Array(report.downloads.prefix(limit).map(\.file.path))
        }
    }

    // MARK: Selection

    func isSelected(_ path: String) -> Bool { selection.contains(path) }

    func toggle(_ path: String) {
        if selection.contains(path) {
            selection.remove(path)
        } else {
            selection.insert(path)
        }
    }

    func setSelected(_ paths: [String], _ selected: Bool) {
        if selected {
            selection.formUnion(paths)
        } else {
            selection.subtract(paths)
        }
    }

    func selectionState(of paths: [String]) -> SelectionState {
        guard !paths.isEmpty else { return SelectionState.none }
        let count = paths.reduce(0) { $0 + (selection.contains($1) ? 1 : 0) }
        if count == 0 { return SelectionState.none }
        return count == paths.count ? .all : .some
    }

    /// Selected paths within a tool (or all tools).
    func selectedPaths(in tool: ClutterTool?) -> [String] {
        guard let tool else { return Array(selection) }
        var seen = Set<String>()
        return paths(in: tool).filter { selection.contains($0) && seen.insert($0).inserted }
    }

    func selectedBytes(in tool: ClutterTool?) -> Int64 {
        selectedPaths(in: tool).reduce(0) { $0 + (filesByPath[$1]?.size ?? 0) }
    }

    /// Distinct files a tool lists.
    func fileCount(in tool: ClutterTool) -> Int {
        Set(paths(in: tool)).count
    }

    func totalBytes(in tool: ClutterTool) -> Int64 {
        Set(paths(in: tool)).reduce(0) { $0 + (filesByPath[$1]?.size ?? 0) }
    }

    func deselectAll(in tool: ClutterTool?) {
        if let tool {
            selection.subtract(paths(in: tool))
        } else {
            selection.removeAll()
        }
    }

    // MARK: Large & Old

    var largeOldFacet: ClutterLargeOldFacet {
        if let kind = largeOldQuery.kind { return .kind(kind) }
        if let size = largeOldQuery.sizeBucket { return .size(size) }
        if let age = largeOldQuery.ageBucket { return .age(age) }
        return .scope(largeOldQuery.scope)
    }

    func selectLargeOldFacet(_ facet: ClutterLargeOldFacet) {
        var query = largeOldQuery
        query.scope = .all
        query.kind = nil
        query.sizeBucket = nil
        query.ageBucket = nil
        switch facet {
        case .scope(let scope): query.scope = scope
        case .kind(let kind): query.kind = kind
        case .size(let size): query.sizeBucket = size
        case .age(let age): query.ageBucket = age
        }
        largeOldQuery = query
    }

    /// Changes the sort order, picking the natural direction for it (A→Z, biggest and
    /// longest-unused first).
    func setLargeOldSort(_ sort: ClutterLargeOldQuery.Sort) {
        largeOldQuery.sort = sort
        largeOldQuery.ascending = sort == .name || sort == .kind || sort == .lastOpened
    }

    /// The Large & Old rows the current facet, search and sort produce.
    var visibleLargeOld: [ClutterLargeOldItem] {
        largeOldQuery.apply(report?.largeOld ?? [], selected: selection)
    }

    /// Count and bytes for a facet (ignoring the search field).
    func largeOldStats(_ facet: ClutterLargeOldFacet, now: Date = Date()) -> (count: Int, bytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        for item in report?.largeOld ?? [] {
            let matches: Bool
            switch facet {
            case .scope(.all): matches = true
            case .scope(.large): matches = item.reason.isLarge
            case .scope(.old): matches = item.reason.isOld
            case .scope(.selected): matches = selection.contains(item.id)
            case .kind(let kind): matches = item.file.kind == kind
            case .size(let size): matches = item.sizeBucket == size
            case .age(let age): matches = item.ageBucket(now: now) == age
            }
            if matches {
                count += 1
                bytes += item.file.size
            }
        }
        return (count, bytes)
    }

    // MARK: Duplicates

    /// Duplicate sets matching the search field (any copy's name or folder).
    var visibleDuplicates: [ClutterDuplicateGroup] {
        let groups = report?.duplicates ?? []
        let needle = duplicatesSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return groups }
        return groups.filter { group in group.files.contains { $0.path.lowercased().contains(needle) } }
    }

    /// The set shown in the detail pane.
    var focusedDuplicate: ClutterDuplicateGroup? {
        let groups = visibleDuplicates
        if let id = focusedDuplicateID, let group = groups.first(where: { $0.id == id }) { return group }
        return groups.first
    }

    /// Applies a selection rule to one duplicate set, or to every set.
    func selectCopies(_ mode: ClutterCopySelection, in groupID: String? = nil) {
        guard let report else { return }
        let smart = ClutterSmartSelection()
        for group in report.duplicates where groupID == nil || group.id == groupID {
            let keep: String?
            switch mode {
            case .smart:
                for file in group.files {
                    if smart.shouldSelect(file, keeperPath: group.keeperPath) {
                        selection.insert(file.path)
                    } else {
                        selection.remove(file.path)
                    }
                }
                continue
            case .clear:
                selection.subtract(group.files.map(\.path))
                continue
            case .allButNewest:
                keep = group.files.max { a, b in
                    a.modified != b.modified ? a.modified < b.modified : a.path > b.path
                }?.path
            case .allButOldest:
                keep = group.files.min { a, b in
                    a.originDate != b.originDate ? a.originDate < b.originDate : a.path < b.path
                }?.path
            }
            for file in group.files {
                if file.path == keep { selection.remove(file.path) } else { selection.insert(file.path) }
            }
        }
    }

    /// Keeps `path` and selects every other member of its duplicate set or similar cluster.
    func keepOnly(_ path: String) {
        guard let report else { return }
        if let id = duplicateSetByPath[path], let group = report.duplicates.first(where: { $0.id == id }) {
            for file in group.files { if file.path == path { selection.remove(file.path) } else { selection.insert(file.path) } }
        } else if let id = clusterByPath[path], let cluster = report.similar.first(where: { $0.id == id }) {
            for file in cluster.files { if file.path == path { selection.remove(file.path) } else { selection.insert(file.path) } }
        }
    }

    /// Tri-state checkbox of a duplicate set: unchecked → smart selection, otherwise none.
    func toggleDuplicateGroup(_ group: ClutterDuplicateGroup) {
        if selectionState(of: group.files.map(\.path)) == SelectionState.none {
            selectCopies(.smart, in: group.id)
            if selectionState(of: group.files.map(\.path)) == SelectionState.none {
                // Smart selection keeps every copy (all in the cloud): fall back to all but the keeper.
                selection.formUnion(group.copies.map(\.path))
            }
        } else {
            selection.subtract(group.files.map(\.path))
        }
    }

    // MARK: Similar images

    var visibleClusters: [ClutterSimilarCluster] {
        let clusters = report?.similar ?? []
        let needle = similarSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return clusters }
        return clusters.filter { cluster in cluster.files.contains { $0.path.lowercased().contains(needle) } }
    }

    var focusedCluster: ClutterSimilarCluster? {
        let clusters = visibleClusters
        if let id = focusedClusterID, let cluster = clusters.first(where: { $0.id == id }) { return cluster }
        return clusters.first
    }

    /// Selects every image of a cluster (or all clusters) except the best shot.
    func selectAllButBest(_ clusterID: String? = nil) {
        guard let report else { return }
        for cluster in report.similar where clusterID == nil || cluster.id == clusterID {
            for file in cluster.files {
                if file.path == cluster.bestPath { selection.remove(file.path) } else { selection.insert(file.path) }
            }
        }
    }

    func toggleCluster(_ cluster: ClutterSimilarCluster) {
        if selectionState(of: cluster.files.map(\.path)) == SelectionState.none {
            selectAllButBest(cluster.id)
        } else {
            selection.subtract(cluster.files.map(\.path))
        }
    }

    // MARK: Downloads

    /// Download sources (app, else website) by bytes.
    var downloadSources: [ClutterDownloadSource] {
        var totals: [String: (Int, Int64)] = [:]
        for item in report?.downloads ?? [] {
            let current = totals[item.sourceLabel] ?? (0, 0)
            totals[item.sourceLabel] = (current.0 + 1, current.1 + item.file.size)
        }
        return totals.map { ClutterDownloadSource(label: $0.key, count: $0.value.0, bytes: $0.value.1) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.label < $1.label }
    }

    func downloadStats(_ facet: ClutterDownloadsFacet) -> (count: Int, bytes: Int64) {
        let items = (report?.downloads ?? []).filter { matches($0, facet: facet) }
        return (items.count, items.reduce(0) { $0 + $1.file.size })
    }

    private func matches(_ item: ClutterDownloadItem, facet: ClutterDownloadsFacet) -> Bool {
        switch facet {
        case .all: return true
        case .category(let category): return item.category == category
        case .source(let label): return item.sourceLabel == label
        case .selected: return selection.contains(item.id)
        }
    }

    /// The Downloads rows the current facet, search and sort produce.
    var visibleDownloads: [ClutterDownloadItem] {
        let needle = downloadsSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = (report?.downloads ?? []).filter { item in
            guard matches(item, facet: downloadsFacet) else { return false }
            if needle.isEmpty { return true }
            return item.file.name.lowercased().contains(needle) || item.sourceLabel.lowercased().contains(needle)
                || (item.sourceHost?.lowercased().contains(needle) ?? false)
        }
        return filtered.sorted { a, b in
            switch downloadsSort {
            case .size:
                return a.file.size != b.file.size ? a.file.size > b.file.size : a.file.path < b.file.path
            case .date:
                return a.referenceDate != b.referenceDate ? a.referenceDate < b.referenceDate : a.file.path < b.file.path
            case .name:
                let order = a.file.name.localizedStandardCompare(b.file.name)
                return order == .orderedSame ? a.file.path < b.file.path : order == .orderedAscending
            }
        }
    }

    // MARK: Items

    /// A `ScanItem` for a selected path, tagged with its duplicate set or cluster so the
    /// engine can keep one copy.
    func removalItem(for path: String) -> ScanItem? {
        guard let report, let file = filesByPath[path] else { return nil }
        if let id = duplicateSetByPath[path], let group = report.duplicates.first(where: { $0.id == id }) {
            return ClutterItems.item(file, tool: .duplicates, selected: true, set: id, isKeeper: group.keeperPath == path)
        }
        if let id = clusterByPath[path], let cluster = report.similar.first(where: { $0.id == id }) {
            return ClutterItems.item(file, tool: .similarImages, selected: true, set: id, isKeeper: cluster.bestPath == path)
        }
        return ClutterItems.item(file, tool: downloadPaths.contains(path) ? .downloads : .largeOld, selected: true)
    }

    // MARK: Removal

    func requestRemoval(in tool: ClutterTool?) {
        let paths = selectedPaths(in: tool).sorted()
        let items = paths.compactMap(removalItem(for:))
        guard !items.isEmpty, let report else { return }
        let requested = Set(paths)
        var complete = 0
        for (_, members) in report.setMembers where members.count > 1 && members.allSatisfy({ requested.contains($0) }) {
            complete += 1
        }
        removalRequest = ClutterRemovalRequest(items: items, bytes: items.reduce(0) { $0 + $1.size },
                                               completeSets: complete, tool: tool)
    }

    func confirmRemoval(allowRemovingAllCopies: Bool) {
        guard let request = removalRequest else { return }
        removalRequest = nil
        task?.cancel()
        phase = .removing
        progress = ScanProgress(fraction: 0, message: "Moving to the Trash…")
        let engine = self.engine
        let onProgress: ProgressHandler = { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .removing else { return }
                self.progress = p
            }
        }
        task = Task { [weak self] in
            let result = await engine.remove(request.items, allowRemovingAllCopies: allowRemovingAllCopies,
                                             progress: onProgress)
            guard let self else { return }
            self.outcome = result
            if let updated = engine.lastReport {
                self.setReport(self.withoutIgnored(updated))
            } else {
                self.setReport(self.reportRemoving(result.removedItemIDs))
            }
            self.selection.subtract(result.removedItemIDs)
            self.phase = .done
            if result.processedCount > 0 {
                HistoryStore.shared.record(result, kind: .clean)
            }
        }
    }

    private func reportRemoving(_ ids: [String]) -> ClutterScanReport? {
        guard var copy = report else { return nil }
        copy.remove(paths: Set(ids))
        return copy
    }

    // MARK: Ignore, reveal, preview

    /// Adds a file to the ignore list and hides it from every tool.
    func ignore(_ path: String) {
        settings.ignore(path: path)
        guard var copy = report else { return }
        copy.remove(paths: [path])
        selection.remove(path)
        setReport(copy)
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func quickLook(_ path: String) {
        previewURL = URL(fileURLWithPath: path)
    }

    func open(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}
