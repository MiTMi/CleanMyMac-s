import Foundation
import Observation
import SpruceCore
import SpruceMac

/// Drives the standard module journey for any `GroupScanner`:
/// idle → scanning → results (review & select) → running → done.
///
/// CONTRACT: used by module views and `ScanFlowScreen`. Keep public members.
@MainActor
@Observable
final class ScanFlowModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case running
        case done
        case failed(String)
    }

    let module: ModuleID
    let scanner: GroupScanner
    /// What kind of history entry a successful run records.
    var historyKind: ActivityEntry.Kind

    private(set) var phase: Phase = .idle
    private(set) var progress = ScanProgress(message: "")
    var groups: [ScanGroup] = []
    private(set) var outcome: RunOutcome?
    private(set) var lastScanDate: Date?

    private var task: Task<Void, Never>?

    init(module: ModuleID, scanner: GroupScanner, historyKind: ActivityEntry.Kind = .clean) {
        self.module = module
        self.scanner = scanner
        self.historyKind = historyKind
    }

    // MARK: Derived

    var totalSize: Int64 { groups.totalSize }
    var selectedSize: Int64 { groups.selectedSize }
    var selectedItems: [ScanItem] { groups.selectedItems }
    var selectedCount: Int { selectedItems.count }
    var isBusy: Bool { phase == .scanning || phase == .running }

    // MARK: Actions

    func startScan() {
        task?.cancel()
        phase = .scanning
        progress = ScanProgress(fraction: nil, message: "Starting…")
        outcome = nil
        let scanner = self.scanner
        task = Task { [weak self] in
            do {
                let result = try await scanner.scan(progress: { p in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .scanning else { return }
                        self.progress = p
                    }
                })
                guard let self, !Task.isCancelled else { return }
                self.groups = SettingsStore.shared.settings.filteringIgnored(result)
                self.lastScanDate = Date()
                self.phase = .results
                HistoryStore.shared.record(ActivityEntry(module: self.module, kind: .scan, bytes: self.groups.totalSize,
                                                         count: self.groups.allItems.count,
                                                         summary: "Found \(ByteFormat.string(self.groups.totalSize))"))
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = (error as? SpruceError) == .cancelled ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    /// Runs the given items, or the current selection when nil.
    func run(_ items: [ScanItem]? = nil) {
        let targets = items ?? selectedItems
        guard !targets.isEmpty else { return }
        task?.cancel()
        phase = .running
        progress = ScanProgress(fraction: 0, message: "Working…")
        let scanner = self.scanner
        task = Task { [weak self] in
            do {
                let result = try await scanner.perform(targets, progress: { p in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .running else { return }
                        self.progress = p
                    }
                })
                guard let self else { return }
                self.outcome = result
                self.groups.removeItems(withIDs: Set(result.removedItemIDs))
                self.phase = .done
                HistoryStore.shared.record(result, kind: self.historyKind)
            } catch {
                guard let self else { return }
                self.phase = (error as? SpruceError) == .cancelled ? .results : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        switch phase {
        case .scanning: phase = .idle
        case .running: phase = groups.isEmpty ? .idle : .results
        default: break
        }
    }

    /// Back to the idle screen, discarding results.
    func reset() {
        task?.cancel()
        groups = []
        outcome = nil
        phase = .idle
    }

    /// From the done screen back to remaining results (or idle when nothing is left).
    func showRemaining() {
        phase = groups.isEmpty ? .idle : .results
    }

    // MARK: Selection

    func setSelected(_ selected: Bool, itemID: String) {
        groups.setSelected(selected, itemID: itemID)
    }

    func toggle(itemID: String) {
        guard let item = groups.allItems.first(where: { $0.id == itemID }) else { return }
        groups.setSelected(!item.isSelected, itemID: itemID)
    }

    func setGroup(_ groupID: String, selected: Bool) {
        func apply(_ gs: inout [ScanGroup]) -> Bool {
            for i in gs.indices {
                if gs[i].id == groupID {
                    gs[i].setAllSelected(selected)
                    return true
                }
                if apply(&gs[i].children) { return true }
            }
            return false
        }
        _ = apply(&groups)
    }

    func selectAll(_ selected: Bool) {
        for i in groups.indices { groups[i].setAllSelected(selected) }
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
