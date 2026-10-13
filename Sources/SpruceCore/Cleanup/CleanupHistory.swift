import Foundation

/// What one Cleanup run did, split the way the activity history counts it.
///
/// Spruce counts space as freed once: when it deletes something, or when it moves
/// something to the Trash (every module records moved-to-Trash bytes as freed).
/// Emptying a Trash bin deletes what was moved there earlier, so that part of a run is
/// recorded as `.other` and never adds to the "space freed" totals — the same way
/// `SystemMonitor.emptyTrash` records the menu bar's and Toolbox's Empty Trash.
public struct CleanupRunBreakdown: Codable, Hashable, Sendable {
    /// Rows outside the Trash bins that were cleaned (deleted, moved to the Trash or
    /// already gone).
    public var cleanedCount: Int
    /// Bytes deleted outright outside the Trash bins (caches, logs, temporary files…).
    public var deletedBytes: Int64
    /// Files and folders moved to the Trash, and their size.
    public var trashedCount: Int
    public var trashedBytes: Int64
    /// Trash-bin rows emptied (or already gone), and the bytes deleted from the Trash.
    public var emptiedCount: Int
    public var emptiedBytes: Int64

    public init(cleanedCount: Int = 0, deletedBytes: Int64 = 0, trashedCount: Int = 0, trashedBytes: Int64 = 0,
                emptiedCount: Int = 0, emptiedBytes: Int64 = 0) {
        self.cleanedCount = cleanedCount
        self.deletedBytes = deletedBytes
        self.trashedCount = trashedCount
        self.trashedBytes = trashedBytes
        self.emptiedCount = emptiedCount
        self.emptiedBytes = emptiedBytes
    }

    /// True when the run deleted something from a Trash bin.
    public var emptiedTrash: Bool { emptiedCount > 0 || emptiedBytes > 0 }

    /// True when the run did something outside the Trash bins.
    public var cleanedOutsideTrash: Bool { cleanedCount > 0 || deletedBytes > 0 || trashedBytes > 0 }
}

/// The result of one Cleanup run: the outcome the Done screen shows and the split the
/// activity history records. The outcome's `freedBytes` counts everything the run deleted,
/// emptied from a Trash bin or moved to the Trash; `trashedBytes` / `trashedCount` /
/// `trashRunIDs` describe the moved-to-Trash part (for Put Back), as `FileRemover` does.
public struct CleanupRunReport: Hashable, Sendable {
    public var outcome: RunOutcome
    public var breakdown: CleanupRunBreakdown

    public init(outcome: RunOutcome, breakdown: CleanupRunBreakdown) {
        self.outcome = outcome
        self.breakdown = breakdown
    }
}

/// How a Cleanup run is written to the activity history (see `CleanupRunBreakdown`).
public enum CleanupHistory {
    /// One history entry to record: `outcome` (its date, module, bytes, count and
    /// summary) recorded with `kind`.
    public struct Record: Hashable, Sendable {
        public var outcome: RunOutcome
        public var kind: ActivityEntry.Kind

        public init(outcome: RunOutcome, kind: ActivityEntry.Kind) {
            self.outcome = outcome
            self.kind = kind
        }
    }

    /// The history records of a run, never empty:
    /// * the part outside the Trash bins as `.clean` — bytes deleted plus bytes moved
    ///   to the Trash;
    /// * the Trash-emptying part as `.other`, prefixed "Emptied the Trash".
    ///
    /// A run that did neither (only failures, or nothing to do) yields one `.clean`
    /// record with the run's own summary, so it still shows up in the history. Every
    /// record keeps the run's date, removed item ids and failures; only the `.clean`
    /// record keeps what was moved to the Trash (`trashedBytes`, `trashedCount`,
    /// `trashRunIDs`), so the first record can put the run back.
    public static func records(for report: CleanupRunReport) -> [Record] {
        let b = report.breakdown
        let full = report.outcome
        var records: [Record] = []
        if b.cleanedOutsideTrash || !b.emptiedTrash {
            var part = full
            part.freedBytes = max(0, b.deletedBytes) + max(0, b.trashedBytes)
            part.processedCount = max(0, b.cleanedCount)
            if b.emptiedTrash { part.summary = cleanedSummary(b) }
            records.append(Record(outcome: part, kind: .clean))
        }
        if b.emptiedTrash {
            var part = full
            part.freedBytes = max(0, b.emptiedBytes)
            part.processedCount = max(0, b.emptiedCount)
            part.summary = emptiedSummary(b)
            // Emptying deletes for good: nothing of this part is in the Trash.
            part.trashedBytes = 0
            part.trashedCount = 0
            part.trashRunIDs = []
            records.append(Record(outcome: part, kind: .other))
        }
        return records
    }

    /// The records as activity entries, all dated `date` (e.g. one Checkup run), with
    /// `summaryPrefix` in front of each summary.
    public static func entries(for report: CleanupRunReport, date: Date, summaryPrefix: String = "") -> [ActivityEntry] {
        records(for: report).map { record in
            ActivityEntry(date: date, module: record.outcome.module, kind: record.kind,
                          bytes: max(0, record.outcome.freedBytes), count: max(0, record.outcome.processedCount),
                          summary: summaryPrefix + record.outcome.summary)
        }
    }

    // MARK: Summaries

    /// Summary of a whole run, shown on the Done screen:
    /// "Cleaned 12 items · 1.2 GB deleted · 3 items moved to the Trash (40 MB)".
    public static func runSummary(_ b: CleanupRunBreakdown) -> String {
        let rows = max(0, b.cleanedCount) + max(0, b.emptiedCount)
        let deleted = max(0, b.deletedBytes) + max(0, b.emptiedBytes)
        var parts: [String] = []
        if deleted > 0 { parts.append("\(ByteFormat.string(deleted)) deleted") }
        if b.trashedCount > 0 {
            parts.append("\(CountFormat.items(b.trashedCount)) moved to the Trash (\(ByteFormat.string(b.trashedBytes)))")
        }
        if parts.isEmpty { parts.append(rows == 0 ? "Nothing was removed" : "Already clean") }
        return "Cleaned \(CountFormat.items(rows)) · " + parts.joined(separator: " · ")
    }

    /// Summary of the part outside the Trash bins.
    static func cleanedSummary(_ b: CleanupRunBreakdown) -> String {
        var parts: [String] = []
        if b.deletedBytes > 0 { parts.append("\(ByteFormat.string(b.deletedBytes)) deleted") }
        if b.trashedCount > 0 {
            parts.append("\(CountFormat.items(b.trashedCount)) moved to the Trash (\(ByteFormat.string(b.trashedBytes)))")
        }
        if parts.isEmpty { parts.append(b.cleanedCount == 0 ? "Nothing was removed" : "Already clean") }
        return "Cleaned \(CountFormat.items(max(0, b.cleanedCount))) · " + parts.joined(separator: " · ")
    }

    /// Summary of the Trash-emptying part.
    static func emptiedSummary(_ b: CleanupRunBreakdown) -> String {
        var parts = ["Emptied the Trash", CountFormat.items(max(0, b.emptiedCount))]
        if b.emptiedBytes > 0 { parts.append("\(ByteFormat.string(b.emptiedBytes)) deleted") }
        return parts.joined(separator: " · ")
    }
}
