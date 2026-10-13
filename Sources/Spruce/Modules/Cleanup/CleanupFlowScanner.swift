import Foundation
import SpruceCore
import SpruceMac

/// A finished Cleanup run as the module screen sees it.
struct CleanupFlowRun: Equatable {
    /// The whole run: what the Done screen shows.
    let report: CleanupRunReport
    /// The outcome handed back to `ScanFlowModel`: the first history record (the flow
    /// records it with the kind `CleanupFlowScanner` set), with every removed id and
    /// failure so the flow updates its results correctly.
    let flowOutcome: RunOutcome
}

/// The `GroupScanner` behind Cleanup's `ScanFlowModel`.
///
/// Scans and cleans with `CleanupEngine`, then writes the run to the activity history
/// the way `CleanupHistory` splits it: emptying a Trash bin is recorded as `.other`
/// (like the menu bar's and Toolbox's Empty Trash, because those bytes were counted as
/// freed when they were moved to the Trash), the rest as `.clean`. `ScanFlowModel`
/// records exactly one entry per run, so this class sets the flow's `historyKind` for
/// the first record and records any second one itself.
final class CleanupFlowScanner: GroupScanner, @unchecked Sendable {
    let engine: CleanupEngine
    /// The flow this scanner drives (its `historyKind` is set before it records a run).
    @MainActor weak var flow: ScanFlowModel?
    /// Receives each finished run on the main actor, before the flow shows it.
    @MainActor var onRunFinished: (@MainActor (CleanupFlowRun) -> Void)?

    init(engine: CleanupEngine) {
        self.engine = engine
    }

    func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        try await engine.scan(progress: progress)
    }

    func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let report = try await engine.clean(items, progress: progress)
        let records = CleanupHistory.records(for: report)
        let first = records.first ?? CleanupHistory.Record(outcome: report.outcome, kind: .clean)
        let run = CleanupFlowRun(report: report, flowOutcome: first.outcome)
        await MainActor.run {
            self.flow?.historyKind = first.kind
            for record in records.dropFirst() {
                HistoryStore.shared.record(record.outcome, kind: record.kind)
            }
            self.onRunFinished?(run)
        }
        return run.flowOutcome
    }
}
