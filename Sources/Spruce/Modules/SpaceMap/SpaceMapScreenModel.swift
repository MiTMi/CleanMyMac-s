import AppKit
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

/// Where the Space Map journey is.
enum SpaceMapPhase: Equatable {
    case idle
    case scanning
    case results
    case removing
    case done
    case failed(String)
}

/// Bubble map or sunburst rings.
enum SpaceMapViewMode: String, CaseIterable, Identifiable {
    case bubbles
    case rings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bubbles: return "Bubbles"
        case .rings: return "Rings"
        }
    }

    var symbol: String {
        switch self {
        case .bubbles: return "circle.hexagongrid"
        case .rings: return "circle.dashed.inset.filled"
        }
    }
}

/// State of the Space Map module: targets, scan, the map's focus and history, selection,
/// removal and rescans. One instance per engine, so a map survives navigation.
@MainActor
@Observable
final class SpaceMapScreenModel {
    private static var instances: [ObjectIdentifier: SpaceMapScreenModel] = [:]

    static func shared(for engine: SpaceMapEngine) -> SpaceMapScreenModel {
        let key = ObjectIdentifier(engine)
        if let existing = instances[key] { return existing }
        let model = SpaceMapScreenModel(engine: engine)
        instances[key] = model
        return model
    }

    let engine: SpaceMapEngine

    private(set) var phase: SpaceMapPhase = .idle
    private(set) var targets: [SpaceMapTarget] = []
    private(set) var customTarget: SpaceMapTarget?
    var selectedTargetID: String?

    private(set) var stats = SpaceMapScanStats()
    private(set) var scanningTarget: SpaceMapTarget?
    private(set) var result: SpaceMapScanResult?
    private(set) var focus: SpaceMapNode?
    /// Bumped whenever the tree changes (removal, rescan) so views re-read it.
    private(set) var revision = 0
    private var history = SpaceMapHistory()

    /// Selected items, topmost only (a selected folder covers everything inside it).
    private(set) var selection: [SpaceMapNode] = []
    private(set) var selectedIDs: Set<ObjectIdentifier> = []
    private(set) var selectionAncestorIDs: Set<ObjectIdentifier> = []

    /// Shared hover between the map and the list.
    var hovered: SpaceMapNode?
    /// The smaller-items bubble or row is hovered.
    var hoveringSmaller = false
    /// Row clicked in the list (ringed in the map).
    var highlighted: SpaceMapNode?
    /// The list shows the folded "smaller items" individually.
    var showsSmallerItems = false
    var viewMode: SpaceMapViewMode = .bubbles

    var removalSheetShown = false
    private(set) var removalProgress = ScanProgress(message: "")
    private(set) var outcome: RunOutcome?
    var previewURL: URL?
    private(set) var rescanning: Set<ObjectIdentifier> = []
    /// Collapsed folders whose contents are being loaded (or wait for it in the background).
    private(set) var expanding: Set<ObjectIdentifier> = []
    /// Short-lived message shown over the map (e.g. a rescan that failed).
    var toast: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var protectionCache: [ObjectIdentifier: SpaceMapProtection] = [:]
    @ObservationIgnored private var mapCache: [String: SpaceMapBubbleMap] = [:]
    @ObservationIgnored private var mapCacheOrder: [String] = []
    @ObservationIgnored private var ringCache: [String: [SpaceMapRingSegment]] = [:]
    @ObservationIgnored private var ringCacheOrder: [String] = []
    /// Background loads not started yet (a folder opened meanwhile is taken out and loaded at once).
    @ObservationIgnored private var queuedExpansions: Set<ObjectIdentifier> = []
    /// Paths of collapsed folders that couldn't be loaded; not retried automatically.
    @ObservationIgnored private var failedExpansions: Set<String> = []
    @ObservationIgnored private var targetsRefreshRunning = false
    @ObservationIgnored private var targetsRefreshQueued = false

    private init(engine: SpaceMapEngine) {
        self.engine = engine
        if let last = engine.lastResult {
            apply(last, recordHistory: false)
        }
    }

    // MARK: Targets

    var selectedTarget: SpaceMapTarget? {
        targets.first { $0.id == selectedTargetID }
    }

    /// Re-reads the locations and their capacities. Volume queries can block (purgeable
    /// space, unresponsive network shares), so they run off the main thread while the
    /// current list stays on screen; calls made meanwhile are coalesced into one more.
    func refreshTargets() {
        guard !targetsRefreshRunning else {
            targetsRefreshQueued = true
            return
        }
        targetsRefreshRunning = true
        let engine = self.engine
        let custom = customTarget
        let model = self
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                engine.availableTargets(keeping: custom)
            }.value
            model.applyTargets(found.targets, checkedCustom: custom, customStillExists: found.custom != nil)
            model.targetsRefreshRunning = false
            if model.targetsRefreshQueued {
                model.targetsRefreshQueued = false
                model.refreshTargets()
            }
        }
    }

    private func applyTargets(_ found: [SpaceMapTarget], checkedCustom: SpaceMapTarget?, customStillExists: Bool) {
        if let checkedCustom, !customStillExists, customTarget?.path == checkedCustom.path {
            customTarget = nil
        }
        var list = found
        // A folder picked while this refresh was running.
        if let current = customTarget, !list.contains(where: { $0.path == current.path }) {
            list.append(current)
        }
        targets = list
        if selectedTarget == nil {
            selectedTargetID = list.first?.id
        }
    }

    /// Lists a location the user picked (a folder stays listed until it disappears) and selects it.
    private func adopt(_ target: SpaceMapTarget) {
        if target.kind == .folder { customTarget = target }
        if !targets.contains(where: { $0.id == target.id }) { targets.append(target) }
        selectedTargetID = target.id
        refreshTargets()
    }

    func select(_ target: SpaceMapTarget) {
        selectedTargetID = target.id
    }

    /// Lets the user pick any folder to map.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder or disk to map."
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let engine = self.engine
        let model = self
        Task {
            let target = await Task.detached(priority: .userInitiated) { engine.target(forFolder: url) }.value
            model.adopt(target)
        }
    }

    /// A folder handed over from Finder ("Map Folder with Spruce", a drop on the Dock icon,
    /// Open With) or dropped on the window: list it, select it and map it. A file maps the
    /// folder it is in; an item that no longer exists is ignored. Nothing is ever removed
    /// from here.
    func mapFolder(_ url: URL) {
        let engine = self.engine
        let model = self
        Task {
            // The file system and volume queries run off the main thread.
            let target: SpaceMapTarget? = await Task.detached(priority: .userInitiated) { () -> SpaceMapTarget? in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
                return engine.target(forFolder: isDirectory.boolValue ? url : url.deletingLastPathComponent())
            }.value
            guard let target else { return }
            model.adopt(target)
            // A removal in progress finishes first; the folder stays selected in the picker.
            guard model.phase != .removing else { return }
            model.scan(target)
        }
    }

    // MARK: Drops

    /// Drops are taken except while items are being moved to the Trash.
    var acceptsDrops: Bool { phase != .removing }

    /// A folder (or disk) dropped on the window or on a location card is mapped; a file
    /// maps the folder it is in. Only the first item counts. Returns false when refused.
    @discardableResult
    func receiveDrop(_ urls: [URL]) -> Bool {
        guard acceptsDrops, let first = urls.first(where: \.isFileURL) else { return false }
        mapFolder(first.standardizedFileURL)
        return true
    }

    // MARK: Scan

    var canStartScan: Bool { selectedTarget != nil && phase != .scanning }

    func startScan() {
        guard let target = selectedTarget else { return }
        scan(target)
    }

    func scan(_ target: SpaceMapTarget) {
        task?.cancel()
        // Never hold two trees at once: a map of a whole disk is large, and the new scan
        // builds a complete one. Stopping the scan leads back to the location picker.
        releaseMap()
        phase = .scanning
        stats = SpaceMapScanStats()
        scanningTarget = target
        let engine = self.engine
        // Screen models live as long as the app (one per engine), so strong captures are fine.
        let model = self
        let progress: SpaceMapStatsHandler = { stats in
            Task { @MainActor in model.receive(stats) }
        }
        task = Task {
            do {
                let result = try await engine.scan(target, progress: progress)
                guard !Task.isCancelled else { return }
                model.apply(result, recordHistory: true)
            } catch {
                // A cancelled task was stopped or replaced by a newer scan; that code owns the phase.
                guard !Task.isCancelled else { return }
                if (error as? SpruceError) == .cancelled {
                    if model.phase == .scanning { model.phase = model.result == nil ? .idle : .results }
                } else {
                    model.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func receive(_ newStats: SpaceMapScanStats) {
        guard phase == .scanning else { return }
        stats = newStats
    }

    func cancelScan() {
        task?.cancel()
        task = nil
        if phase == .scanning { phase = result == nil ? .idle : .results }
    }

    /// Back to the target picker, discarding the map. Nothing is removed.
    func newScan() {
        task?.cancel()
        task = nil
        releaseMap()
        phase = .idle
        refreshTargets()
    }

    /// Lets go of every reference to the current tree (engine, focus, history, selection,
    /// caches) so its memory is returned before anything else is built.
    private func releaseMap() {
        engine.discardResult()
        result = nil
        focus = nil
        history.reset()
        clearSelection()
        resetCaches()
        hovered = nil
        highlighted = nil
        hoveringSmaller = false
        showsSmallerItems = false
        outcome = nil
        expanding = []
        queuedExpansions = []
        failedExpansions = []
    }

    /// Scans the same location again (with progress).
    func rescanAll() {
        guard let target = result?.target else { return }
        selectedTargetID = target.id
        scan(target)
    }

    func retry() {
        if let target = scanningTarget ?? selectedTarget {
            scan(target)
        } else {
            phase = .idle
        }
    }

    private func apply(_ newResult: SpaceMapScanResult, recordHistory: Bool) {
        result = newResult
        focus = newResult.root
        history.reset()
        clearSelection()
        resetCaches()
        showsSmallerItems = false
        hovered = nil
        highlighted = nil
        revision += 1
        phase = .results
        prefetchVisible()
        if recordHistory {
            let root = newResult.root
            HistoryStore.shared.record(ActivityEntry(module: .spaceMap, kind: .scan, bytes: root.size,
                                                     count: root.fileCount,
                                                     summary: "Mapped \(ByteFormat.string(root.size)) on \(newResult.target.title)"))
        }
    }

    /// Opened from elsewhere (Toolbox, a notification): show the map or the picker.
    func openFromTool() {
        switch phase {
        case .done, .failed:
            phase = result == nil ? .idle : .results
        case .idle:
            refreshTargets()
        default:
            break
        }
    }

    // MARK: Navigation

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    var canZoomOut: Bool { focus?.parent != nil }

    func zoom(into node: SpaceMapNode) {
        guard node.canZoom, let focus, node !== focus else { return }
        history.leave(focus)
        setFocus(node)
    }

    func zoomOut() {
        guard let focus, let parent = focus.parent else { return }
        history.leave(focus)
        setFocus(parent)
    }

    func jump(to node: SpaceMapNode) {
        guard let focus, node !== focus, node.isFolder else { return }
        history.leave(focus)
        setFocus(node)
    }

    func goBack() {
        guard let focus, let root = result?.root, let target = history.goBack(from: focus, root: root) else { return }
        setFocus(target)
    }

    func goForward() {
        guard let focus, let root = result?.root, let target = history.goForward(from: focus, root: root) else { return }
        setFocus(target)
    }

    private func setFocus(_ node: SpaceMapNode) {
        focus = node
        showsSmallerItems = false
        highlighted = nil
        hovered = nil
        hoveringSmaller = false
        // A collapsed folder shows "Loading…" until its contents are back (milliseconds).
        if node.isCollapsed { expand([node], now: true) }
        prefetchVisible()
    }

    // MARK: Selection

    var selectedBytes: Int64 { selection.reduce(0) { $0 + $1.size } }
    var selectedFiles: Int { selection.reduce(0) { $0 + max(1, $1.fileCount) } }

    /// Why `node` can't be selected (nil = selectable), cached per tree revision. Besides
    /// PathGuard, the ignore list and cloud folders, items the user can't move themselves
    /// are refused before they are selected when administrator rights won't help: locked
    /// items, and root-owned items outside the places where Spruce acts as administrator
    /// (`PathGuard.isInPrivilegedZone`). The list and the hover card show the reason.
    func protection(of node: SpaceMapNode) -> SpaceMapProtection {
        if let cached = protectionCache[node.id] { return cached }
        let reason = SpaceMapCatalog.protectionReason(for: node, guardian: FileRemover.shared.guardian,
                                                      settings: SettingsStore.shared.settings,
                                                      access: { SpaceMapPermissions.moveAccess(ofPath: $0) })
        let value = SpaceMapProtection(reason: reason)
        protectionCache[node.id] = value
        return value
    }

    func isSelectable(_ node: SpaceMapNode) -> Bool { protection(of: node).reason == nil }

    func isSelected(_ node: SpaceMapNode) -> Bool { selectedIDs.contains(node.id) }

    /// Inside a selected folder.
    func isCovered(_ node: SpaceMapNode) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if selectedIDs.contains(current.id) { return true }
            ancestor = current.parent
        }
        return false
    }

    func selectionState(of node: SpaceMapNode) -> SelectionState {
        if isSelected(node) || isCovered(node) { return .all }
        return selectionAncestorIDs.contains(node.id) ? .some : .none
    }

    func toggle(_ node: SpaceMapNode) {
        if isSelected(node) {
            selection.removeAll { $0 === node }
        } else {
            guard isSelectable(node), !isCovered(node) else { return }
            selection.removeAll { $0.isDescendant(of: node) }
            selection.append(node)
        }
        updateSelectionIndexes()
    }

    func setSelected(_ nodes: [SpaceMapNode], _ selected: Bool) {
        for node in nodes where isSelected(node) != selected {
            if selected && (!isSelectable(node) || isCovered(node)) { continue }
            if selected {
                selection.removeAll { $0.isDescendant(of: node) }
                selection.append(node)
            } else {
                selection.removeAll { $0 === node }
            }
        }
        updateSelectionIndexes()
    }

    func clearSelection() {
        selection = []
        updateSelectionIndexes()
    }

    private func updateSelectionIndexes() {
        selection = SpaceMapSelection.topmost(selection)
        selectedIDs = Set(selection.map(\.id))
        selectionAncestorIDs = SpaceMapSelection.ancestorIDs(of: selection)
    }

    // MARK: Removal

    func requestRemoval() {
        guard !selection.isEmpty else { return }
        removalSheetShown = true
    }

    func confirmRemoval(_ nodes: [SpaceMapNode]) {
        removalSheetShown = false
        let targets = SpaceMapSelection.topmost(nodes)
        guard !targets.isEmpty else { return }
        task?.cancel()
        phase = .removing
        removalProgress = ScanProgress(fraction: 0, message: "Moving to the Trash…")
        let engine = self.engine
        let settings = SettingsStore.shared.settings
        let model = self
        let progress: ProgressHandler = { update in
            Task { @MainActor in
                guard model.phase == .removing else { return }
                model.removalProgress = update
            }
        }
        task = Task {
            let outcome = await engine.remove(targets, settings: settings, progress: progress)
            model.finishRemoval(outcome, of: targets)
        }
    }

    private func finishRemoval(_ outcome: RunOutcome, of nodes: [SpaceMapNode]) {
        let removedIDs = Set(outcome.removedItemIDs)
        var formerParents: [(node: SpaceMapNode, parent: SpaceMapNode?)] = []
        for node in nodes where removedIDs.contains(URL(fileURLWithPath: node.path).standardizedFileURL.path) {
            formerParents.append((node, node.parent))
            node.detach()
        }
        if let focus, let root = result?.root, !focus.isAttached(to: root) {
            let container = formerParents.first { focus === $0.node || focus.isDescendant(of: $0.node) }
            setFocus(container?.parent ?? root)
            history.reset()
        }
        selection.removeAll { node in formerParents.contains { $0.node === node } }
        updateSelectionIndexes()
        resetCaches()
        revision += 1
        self.outcome = outcome
        phase = .done
        HistoryStore.shared.record(outcome, kind: .clean)
        refreshTrashNode()
    }

    /// Items moved to the Trash still use the disk until it is emptied; keep the Trash
    /// bubble honest by measuring it again.
    private func refreshTrashNode() {
        guard let root = result?.root,
              let trash = root.node(atPath: NSHomeDirectory() + "/.Trash"), trash.isFolder else { return }
        rescan(trash, quietly: true)
    }

    /// From the completion screen back to the map.
    func showRemaining() {
        outcome = nil
        phase = result == nil ? .idle : .results
    }

    // MARK: Rescan

    func isRescanning(_ node: SpaceMapNode) -> Bool { rescanning.contains(node.id) }

    /// Being rescanned, or a collapsed folder whose contents are being loaded.
    func isLoading(_ node: SpaceMapNode) -> Bool { rescanning.contains(node.id) || expanding.contains(node.id) }

    /// Measures one folder again (the whole location gets a full scan with progress).
    func rescan(_ node: SpaceMapNode, quietly: Bool = false) {
        guard let result, node.isFolder, node.isReal, !rescanning.contains(node.id),
              !expanding.contains(node.id) else { return }
        if node === result.root {
            rescanAll()
            return
        }
        rescanning.insert(node.id)
        let engine = self.engine
        // Read on the main actor, which owns the tree. Small sub-folders are collapsed as in
        // the scan (the Trash may have just received a folder with thousands of files).
        let path = node.path
        let options = result.options.rescanning(node)
        let focusPath = focus?.path
        let model = self
        Task {
            do {
                let fresh = try await engine.rescan(path: path, options: options)
                model.rescanning.remove(node.id)
                guard let root = model.result?.root, node.isAttached(to: root) else { return }
                if let fresh {
                    node.replaceContents(with: fresh)
                } else {
                    node.detach()
                }
                model.afterTreeEdit(previousFocusPath: focusPath, fallback: fresh == nil ? nil : node)
            } catch {
                model.rescanning.remove(node.id)
                if !quietly, (error as? SpruceError) != .cancelled {
                    model.toast = "Couldn't rescan \(node.name): \(error.localizedDescription)"
                }
            }
        }
    }

    /// Repairs focus, selection and caches after part of the tree was replaced.
    private func afterTreeEdit(previousFocusPath: String?, fallback: SpaceMapNode?) {
        guard let root = result?.root else { return }
        if let focus, !focus.isAttached(to: root) {
            let replacement = previousFocusPath.flatMap { root.node(atPath: $0) }
            setFocus(replacement ?? fallback ?? root)
        }
        if let hovered, !hovered.isAttached(to: root) { self.hovered = nil }
        if let highlighted, !highlighted.isAttached(to: root) { self.highlighted = nil }
        selection.removeAll { !$0.isAttached(to: root) }
        updateSelectionIndexes()
        resetCaches()
        revision += 1
        prefetchVisible()
    }

    // MARK: Collapsed folders

    /// Loads a collapsed folder again after it failed (the list's "Try Again").
    func loadContents(of node: SpaceMapNode) {
        failedExpansions.remove(node.path)
        expand([node], now: true)
    }

    /// The focused folder's visible children that are collapsed get loaded in the
    /// background, so their bubbles and rings show what's inside.
    private func prefetchVisible() {
        guard let focus, !focus.isCollapsed, !focus.children.isEmpty else { return }
        let collapsed = SpaceMapGrouping.group(focus.children).visible.filter(\.isCollapsed)
        if !collapsed.isEmpty { expand(collapsed, now: false) }
    }

    /// Loads the contents of collapsed folders (small folders whose items the scan measured
    /// but didn't keep). `now`: each in its own task (a folder being opened); otherwise one
    /// after another in the background, skipping any that was opened meanwhile.
    private func expand(_ nodes: [SpaceMapNode], now: Bool) {
        guard let result else { return }
        let root = result.root
        var picked: [SpaceMapNode] = []
        var seen = Set<ObjectIdentifier>()
        for node in nodes where node.isCollapsed && node.isReal && seen.insert(node.id).inserted {
            guard !rescanning.contains(node.id), node.isAttached(to: root),
                  !failedExpansions.contains(node.path) else { continue }
            if expanding.contains(node.id) {
                // Already loading, or still waiting in a background batch: take it out of
                // the batch when it's needed now.
                guard now, queuedExpansions.remove(node.id) != nil else { continue }
            } else {
                expanding.insert(node.id)
                if !now { queuedExpansions.insert(node.id) }
            }
            picked.append(node)
        }
        guard !picked.isEmpty else { return }
        let requests = picked.map { node in
            SpaceMapExpansion(node: node, path: node.path, options: result.options.rescanning(node, inFull: true),
                              fold: result.options.fold)
        }
        let engine = self.engine
        let model = self
        if now {
            for request in requests {
                Task {
                    let outcome = await request.run(engine)
                    model.finishExpansions([(request, outcome)], root: root)
                }
            }
        } else {
            Task {
                // Applied in groups, so a long batch doesn't relayout the map for every folder.
                var loaded: [(SpaceMapExpansion, SpaceMapExpansion.Outcome)] = []
                var lastApplied = Date()
                for request in requests {
                    guard model.queuedExpansions.remove(request.node.id) != nil else { continue }
                    guard model.result?.root === root else {
                        model.expanding.remove(request.node.id)
                        continue
                    }
                    let outcome = await request.run(engine)
                    loaded.append((request, outcome))
                    if Date().timeIntervalSince(lastApplied) >= 0.25 {
                        model.finishExpansions(loaded, root: root)
                        loaded = []
                        lastApplied = Date()
                    }
                }
                model.finishExpansions(loaded, root: root)
            }
        }
    }

    private func finishExpansions(_ loaded: [(SpaceMapExpansion, SpaceMapExpansion.Outcome)], root: SpaceMapNode) {
        guard !loaded.isEmpty else { return }
        for (request, _) in loaded { expanding.remove(request.node.id) }
        guard let current = result?.root, current === root else { return }
        let focusPath = focus?.path
        var fallback: SpaceMapNode?
        var changed = false
        for (request, outcome) in loaded {
            let node = request.node
            guard node.isAttached(to: root), node.isCollapsed else { continue }
            switch outcome {
            case .loaded(let fresh):
                node.replaceContents(with: fresh)
                changed = true
            case .gone:
                // If the focus was inside it, show its folder instead.
                if let focus, focus === node || focus.isDescendant(of: node) { fallback = node.parent }
                node.detach()
                changed = true
            case .failed:
                failedExpansions.insert(request.path)
            }
        }
        if changed { afterTreeEdit(previousFocusPath: focusPath, fallback: fallback) }
    }

    // MARK: Finder

    func reveal(_ node: SpaceMapNode) {
        guard let url = node.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func quickLook(_ node: SpaceMapNode) {
        guard let url = node.url else { return }
        previewURL = url
    }

    func copyPath(_ node: SpaceMapNode) {
        guard node.isReal else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    func ignore(_ node: SpaceMapNode) {
        guard node.isReal else { return }
        SettingsStore.shared.ignore(path: node.path)
        selection.removeAll { $0 === node || $0.isDescendant(of: node) }
        updateSelectionIndexes()
        protectionCache = [:]
    }

    // MARK: Layout cache

    /// Bubble map of `node` for a canvas size, cached per tree revision.
    func bubbleMap(for node: SpaceMapNode, width: Double, height: Double) -> SpaceMapBubbleMap {
        let key = "\(UInt(bitPattern: ObjectIdentifier(node)))-\(Int(width))x\(Int(height))-\(revision)"
        if let cached = mapCache[key] { return cached }
        let map = SpaceMapBubbleMapBuilder.build(focus: node, width: width, height: height)
        mapCache[key] = map
        mapCacheOrder.append(key)
        if mapCacheOrder.count > 8 {
            let evicted = mapCacheOrder.removeFirst()
            mapCache[evicted] = nil
        }
        return map
    }

    /// Sunburst of `node` for the given radii, cached per tree revision so hovering never
    /// lays it out again. Collapsed folders among its arcs are loaded in the background so
    /// they get their outer rings.
    func ringSegments(for node: SpaceMapNode, holeRadius: Double, outerRadius: Double,
                      maxDepth: Int) -> [SpaceMapRingSegment] {
        let key = "\(UInt(bitPattern: ObjectIdentifier(node)))-\(Int(holeRadius))-\(Int(outerRadius))-\(maxDepth)-\(revision)"
        if let cached = ringCache[key] { return cached }
        let segments = SpaceMapSunburst.layout(focus: node, maxDepth: maxDepth, holeRadius: holeRadius,
                                               outerRadius: outerRadius, minAngle: 0.008)
        ringCache[key] = segments
        ringCacheOrder.append(key)
        if ringCacheOrder.count > 4 {
            let evicted = ringCacheOrder.removeFirst()
            ringCache[evicted] = nil
        }
        let collapsed = segments.compactMap { segment -> SpaceMapNode? in
            guard segment.depth < maxDepth, let child = segment.node, child.isCollapsed else { return nil }
            return child
        }
        if !collapsed.isEmpty {
            // Called while a view is being drawn: change state afterwards.
            let model = self
            Task { model.expand(collapsed, now: false) }
        }
        return segments
    }

    private func resetCaches() {
        mapCache = [:]
        mapCacheOrder = []
        ringCache = [:]
        ringCacheOrder = []
        protectionCache = [:]
    }

    // MARK: Presentation helpers

    /// Children of the focused folder grouped like the map (top items + smaller items).
    var focusGroups: SpaceMapGrouped {
        _ = revision
        guard let focus else { return SpaceMapGrouped(visible: [], smaller: nil) }
        return SpaceMapGrouping.group(focus.children)
    }

    /// Hover-card and list subtitle for a node.
    func subtitle(for node: SpaceMapNode) -> String {
        switch node.kind {
        case .system:
            return "Used by macOS outside readable files"
        case .smallFiles:
            return "Too small to show one by one"
        default:
            break
        }
        if node.isUnreadable { return "Couldn't be read — needs Full Disk Access" }
        if let known = SpaceMapCatalog.description(forPath: node.path) { return known }
        switch SpaceMapFileType.of(node) {
        case .application: return "Application"
        case .folder, .package:
            return node.itemCount == 0 ? "Empty" : CountFormat.items(node.itemCount)
        case let type:
            return type.label
        }
    }

    /// Explanation of the pseudo-node, with this volume's purgeable estimate.
    var systemNodeDetail: String {
        guard let volume = result?.target.volume else { return "" }
        return SpaceMapAccounting.systemNodeDetail(volume: volume, unreadableFolders: result?.stats.unreadableFolders ?? 0)
    }
}

/// Cached "may this be selected" verdict.
struct SpaceMapProtection {
    var reason: String?
}

/// Loading one collapsed folder: what to scan, read on the main actor beforehand.
struct SpaceMapExpansion: Sendable {
    enum Outcome: Sendable {
        case loaded(SpaceMapNode)
        /// The folder no longer exists.
        case gone
        case failed
    }

    let node: SpaceMapNode
    let path: String
    /// Collapsing off: the folder was small when it was scanned.
    let options: SpaceMapScanOptions
    /// The map's folding, applied afterwards if the folder has grown past its threshold.
    let fold: SpaceMapFoldPolicy

    func run(_ engine: SpaceMapEngine) async -> Outcome {
        do {
            guard let fresh = try await engine.rescan(path: path, options: options) else { return .gone }
            if fold.collapseBelowBytes > 0 && fresh.size >= fold.collapseBelowBytes {
                fold.collapseDescendants(of: fresh)
            }
            return .loaded(fresh)
        } catch {
            return .failed
        }
    }
}
