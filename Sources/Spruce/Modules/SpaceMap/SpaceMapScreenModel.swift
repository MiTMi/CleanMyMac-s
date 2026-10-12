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
    /// Short-lived message shown over the map (e.g. a rescan that failed).
    var toast: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var protectionCache: [ObjectIdentifier: SpaceMapProtection] = [:]
    @ObservationIgnored private var mapCache: [String: SpaceMapBubbleMap] = [:]
    @ObservationIgnored private var mapCacheOrder: [String] = []

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

    func refreshTargets() {
        var list = engine.availableTargets()
        if let custom = customTarget {
            if engine.exists(custom) {
                if !list.contains(where: { $0.path == custom.path }) { list.append(engine.refreshed(custom)) }
            } else {
                customTarget = nil
            }
        }
        targets = list
        if selectedTarget == nil {
            selectedTargetID = list.first?.id
        }
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
        let target = engine.target(forFolder: url)
        if target.kind == .folder { customTarget = target }
        refreshTargets()
        selectedTargetID = targets.first(where: { $0.path == target.path })?.id ?? target.id
    }

    // MARK: Scan

    var canStartScan: Bool { selectedTarget != nil && phase != .scanning }

    func startScan() {
        guard let target = selectedTarget else { return }
        scan(target)
    }

    func scan(_ target: SpaceMapTarget) {
        task?.cancel()
        phase = .scanning
        stats = SpaceMapScanStats()
        scanningTarget = target
        let engine = self.engine
        task = Task { [weak self] in
            do {
                let result = try await engine.scan(target, progress: { stats in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .scanning else { return }
                        self.stats = stats
                    }
                })
                guard let self, !Task.isCancelled else { return }
                self.apply(result, recordHistory: true)
            } catch {
                // A cancelled task was stopped or replaced by a newer scan; that code owns the phase.
                guard let self, !Task.isCancelled else { return }
                if (error as? SpruceError) == .cancelled {
                    if self.phase == .scanning { self.phase = self.result == nil ? .idle : .results }
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
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
        engine.discardResult()
        result = nil
        focus = nil
        history.reset()
        clearSelection()
        resetCaches()
        outcome = nil
        phase = .idle
        refreshTargets()
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
    }

    // MARK: Selection

    var selectedBytes: Int64 { selection.reduce(0) { $0 + $1.size } }
    var selectedFiles: Int { selection.reduce(0) { $0 + max(1, $1.fileCount) } }

    func protection(of node: SpaceMapNode) -> SpaceMapProtection {
        if let cached = protectionCache[node.id] { return cached }
        let reason = SpaceMapCatalog.protectionReason(for: node, guardian: FileRemover.shared.guardian,
                                                      settings: SettingsStore.shared.settings)
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
        task = Task { [weak self] in
            let outcome = await engine.remove(targets, settings: settings, progress: { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.phase == .removing else { return }
                    self.removalProgress = progress
                }
            })
            guard let self else { return }
            self.finishRemoval(outcome, of: targets)
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

    /// Measures one folder again (the whole location gets a full scan with progress).
    func rescan(_ node: SpaceMapNode, quietly: Bool = false) {
        guard let result, node.isFolder, node.isReal, !rescanning.contains(node.id) else { return }
        if node === result.root {
            rescanAll()
            return
        }
        rescanning.insert(node.id)
        let engine = self.engine
        let options = result.options
        let focusPath = focus?.path
        Task { [weak self] in
            do {
                let fresh = try await engine.rescan(node, options: options)
                guard let self else { return }
                self.rescanning.remove(node.id)
                guard let root = self.result?.root, node.isAttached(to: root) else { return }
                if let fresh {
                    node.replaceContents(with: fresh)
                } else {
                    node.detach()
                }
                self.afterTreeEdit(previousFocusPath: focusPath, fallback: fresh == nil ? nil : node)
            } catch {
                guard let self else { return }
                self.rescanning.remove(node.id)
                if !quietly, (error as? SpruceError) != .cancelled {
                    self.toast = "Couldn't rescan \(node.name): \(error.localizedDescription)"
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

    private func resetCaches() {
        mapCache = [:]
        mapCacheOrder = []
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
