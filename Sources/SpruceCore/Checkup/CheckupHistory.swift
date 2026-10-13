import Foundation

// MARK: - History

/// What the last Checkup scan and run left in the activity history.
public struct CheckupLastSummary: Equatable, Sendable {
    public var scanDate: Date?
    /// Reclaimable bytes the last scan found.
    public var scanFoundBytes: Int64
    /// Recommended actions the last scan found.
    public var scanActionCount: Int
    public var runDate: Date?
    /// Bytes freed by the last run (sum of the per-module entries it recorded).
    public var runFreedBytes: Int64
    public var runProcessedCount: Int

    public init(scanDate: Date? = nil, scanFoundBytes: Int64 = 0, scanActionCount: Int = 0,
                runDate: Date? = nil, runFreedBytes: Int64 = 0, runProcessedCount: Int = 0) {
        self.scanDate = scanDate
        self.scanFoundBytes = scanFoundBytes
        self.scanActionCount = scanActionCount
        self.runDate = runDate
        self.runFreedBytes = runFreedBytes
        self.runProcessedCount = runProcessedCount
    }
}

/// Part of what one area did in a Checkup run, recorded as its own history entry under
/// the kind the Activity statistics count it as.
public struct CheckupHistoryPart: Equatable, Sendable {
    public var kind: ActivityEntry.Kind
    public var bytes: Int64
    public var count: Int
    public var summary: String

    public init(kind: ActivityEntry.Kind, bytes: Int64 = 0, count: Int = 0, summary: String) {
        self.kind = kind
        self.bytes = bytes
        self.count = count
        self.summary = summary
    }

    /// True when the part freed or handled something (worth an entry under its kind).
    public var didAnything: Bool { bytes > 0 || count > 0 }
}

/// How Checkup records itself in `ActivityHistory`.
///
/// * A scan adds one `.scan` entry for `.checkup` (bytes found, action count).
/// * A run adds, per module that did something, one entry per part of what it did,
///   attributed to that module with the kind the module itself records (so per-module
///   statistics stay correct): Applications updates are `.update` and its files of
///   removed apps `.clean`; Cleanup's Trash emptying is `.other` when the run passes
///   Cleanup's own split. An area that only failed is noted as `.other` (never counted as
///   an action). Plus a `.checkup` marker entry (`.other` in older histories) for
///   `.checkup` with **zero bytes** (so totals are never counted twice). All entries of
///   one run share the same date.
public enum CheckupHistory {
    /// Entries of one run are matched to their marker within this window (dates are
    /// stored as whole-second ISO-8601 strings).
    public static let runMatchWindow: TimeInterval = 1

    public static func activityKind(for module: ModuleID) -> ActivityEntry.Kind {
        switch module {
        case .protection: return .threatRemoved
        case .performance: return .maintenance
        case .applications: return .update
        case .cloudStorage: return .cloudFreed
        case .cleanup, .clutter: return .clean
        default: return .other
        }
    }

    public static func scanEntry(tiles: [CheckupTile], date: Date = Date()) -> ActivityEntry {
        let available = tiles.filter { $0.status != .unavailable }
        let bytes = available.reduce(Int64(0)) { $0 + max(0, $1.reclaimableBytes) }
        let actions = available.reduce(0) { $0 + max(0, $1.actionCount) }
        return ActivityEntry(date: date, module: .checkup, kind: .scan, bytes: bytes, count: actions,
                             summary: "Checkup: " + CheckupCopy.resultsLine(tiles: tiles))
    }

    /// Prefix of the ids of Applications update items (`"applications.update:" + update id`;
    /// the Applications engine finds the update to install by the same id). Every other
    /// Applications item in a Checkup review is a file of a removed app (id = its path).
    public static let applicationsUpdateIDPrefix = "applications.update:"

    /// The history entries of a run: the parts of every completed area, then the marker.
    ///
    /// `parts` replaces the default split for an area that reports its own (e.g. Cleanup's
    /// `CleanupHistory.records`, which records Trash emptying as `.other`). Parts that did
    /// nothing are dropped; an area that did nothing but failed gets one `.other` entry.
    public static func runEntries(_ board: CheckupRunBoard, date: Date = Date(),
                                  parts custom: [ModuleID: [CheckupHistoryPart]] = [:]) -> [ActivityEntry] {
        var entries: [ActivityEntry] = []
        for outcome in board.outcomes {
            let parts = (custom[outcome.module] ?? defaultParts(for: outcome)).filter(\.didAnything)
            for part in parts {
                entries.append(ActivityEntry(date: date, module: outcome.module, kind: part.kind,
                                             bytes: max(0, part.bytes), count: max(0, part.count),
                                             summary: "Checkup · \(part.summary)"))
            }
            if parts.isEmpty && !outcome.failures.isEmpty {
                // Nothing was done: keep the note, but never count it as an action or a cleanup.
                entries.append(ActivityEntry(date: date, module: outcome.module, kind: .other, bytes: 0, count: 0,
                                             summary: "Checkup · " + CheckupCopy.failureOnlySummary(outcome)))
            }
        }
        entries.append(ActivityEntry(date: date, module: .checkup, kind: .checkup, bytes: 0,
                                     count: board.processedCount, summary: "Checkup run · " + CheckupCopy.runSummary(board)))
        return entries
    }

    /// How an area's outcome is recorded when it reports no parts of its own: one part
    /// under `activityKind(for:)`, except Applications (see `applicationsParts`).
    public static func defaultParts(for outcome: RunOutcome) -> [CheckupHistoryPart] {
        if outcome.module == .applications { return applicationsParts(outcome) }
        let summary = outcome.summary.isEmpty ? CheckupCopy.outcomeDetail(outcome) : outcome.summary
        return [CheckupHistoryPart(kind: activityKind(for: outcome.module), bytes: max(0, outcome.freedBytes),
                                   count: max(0, outcome.processedCount), summary: summary)]
    }

    /// An Applications run installs updates and can also move files of removed apps to the
    /// Trash. Updates are recorded as `.update` (count = apps updated, no bytes) and the
    /// files as `.clean` (their bytes and file count) — the way the Applications module
    /// records its Updater and Leftovers runs.
    public static func applicationsParts(_ outcome: RunOutcome) -> [CheckupHistoryPart] {
        let updated = Set(outcome.removedItemIDs.filter { $0.hasPrefix(applicationsUpdateIDPrefix) }).count
        let files = max(0, outcome.processedCount - updated)
        let bytes = max(0, outcome.freedBytes)
        var parts: [CheckupHistoryPart] = []
        if updated > 0 {
            parts.append(CheckupHistoryPart(kind: .update, count: updated,
                                            summary: "Updated \(CountFormat.items(updated, singular: "app"))"))
        }
        if files > 0 || bytes > 0 {
            var summary = "Removed \(CountFormat.items(files, singular: "file")) of removed apps"
            if bytes > 0 { summary += " · \(ByteFormat.string(bytes))" }
            parts.append(CheckupHistoryPart(kind: .clean, bytes: bytes, count: files, summary: summary))
        }
        return parts
    }

    /// Summary of the most recent Checkup scan and run, or nil when there was none.
    public static func lastSummary(in history: ActivityHistory) -> CheckupLastSummary? {
        let scan = history.entries.last { $0.module == .checkup && $0.kind == .scan }
        let marker = history.entries.last { $0.module == .checkup && ($0.kind == .checkup || $0.kind == .other) }
        guard scan != nil || marker != nil else { return nil }
        var summary = CheckupLastSummary()
        if let scan {
            summary.scanDate = scan.date
            summary.scanFoundBytes = scan.bytes
            summary.scanActionCount = scan.count
        }
        if let marker {
            summary.runDate = marker.date
            summary.runProcessedCount = marker.count
            let contributors = Set(ModuleID.checkupContributors)
            summary.runFreedBytes = history.entries
                .filter { contributors.contains($0.module) && abs($0.date.timeIntervalSince(marker.date)) < runMatchWindow }
                .reduce(0) { $0 + max(0, $1.bytes) }
        }
        return summary
    }
}

// MARK: - Copy

/// User-facing strings for Checkup (original copy; numbers first, plain words).
public enum CheckupCopy {
    /// Results headline.
    public static func resultsTitle(tiles: [CheckupTile]) -> String {
        if tiles.contains(where: CheckupBoard.isSelectable) { return "Here's the rundown." }
        if tiles.contains(where: { $0.status == .clear }) { return "Spotless." }
        return "Nothing could be checked."
    }

    /// One line under the results headline: "Cleanup 4.2 GB · Applications 3 updates · 2 areas all good".
    public static func resultsLine(tiles: [CheckupTile]) -> String {
        var parts: [String] = []
        for tile in tiles where CheckupBoard.isSelectable(tile) {
            parts.append("\(tile.module.title) \(tile.headline)")
        }
        let clear = tiles.filter { $0.status == .clear }.count
        if clear > 0 {
            parts.append(parts.isEmpty && clear == tiles.count ? "Everything looks good"
                         : "\(CountFormat.items(clear, singular: "area")) all good")
        }
        let skipped = tiles.filter { $0.status == .unavailable }.count
        if skipped > 0 {
            parts.append("\(CountFormat.items(skipped, singular: "area")) skipped")
        }
        return parts.isEmpty ? "No results" : parts.joined(separator: " · ")
    }

    /// Result shown on a finished scan step ("4.2 GB", "All good").
    public static func stepResult(_ tile: CheckupTile) -> String {
        switch tile.status {
        case .clear: return "All good"
        case .unavailable: return "Skipped"
        default: return tile.headline
        }
    }

    /// One line describing what a module's run did.
    public static func outcomeDetail(_ outcome: RunOutcome) -> String {
        var parts: [String] = []
        if outcome.freedBytes > 0 { parts.append("Freed \(ByteFormat.string(outcome.freedBytes))") }
        if outcome.processedCount > 0 { parts.append("\(CountFormat.items(outcome.processedCount)) handled") }
        if !outcome.failures.isEmpty {
            parts.append("\(CountFormat.grouped(outcome.failures.count)) couldn't be completed")
        }
        return parts.isEmpty ? "Nothing needed doing" : parts.joined(separator: " · ")
    }

    /// History summary for an area that did nothing but fail.
    public static func failureOnlySummary(_ outcome: RunOutcome) -> String {
        let failures = outcome.failures
        guard let first = failures.first else { return "Nothing needed doing" }
        if failures.count == 1 {
            return "Couldn't complete \(first.title) — \(first.reason)"
        }
        return "\(CountFormat.items(failures.count)) couldn't be completed — \(first.reason)"
    }

    /// Detail line for a run step on the completion screen.
    public static func stepDetail(_ step: CheckupRunStep) -> String {
        switch step.state {
        case .waiting: return "Waiting"
        case .running: return "Working…"
        case .done(let outcome): return outcome.summary.isEmpty ? outcomeDetail(outcome) : outcome.summary
        case .failed(let reason): return reason
        case .skipped: return "Not run — you stopped Checkup"
        }
    }

    /// Short summary of a whole run.
    public static func runSummary(_ board: CheckupRunBoard) -> String {
        var parts: [String] = []
        if board.freedBytes > 0 { parts.append("Freed \(ByteFormat.string(board.freedBytes))") }
        if board.processedCount > 0 { parts.append("\(CountFormat.items(board.processedCount)) handled") }
        let failedAreas = board.steps.filter { if case .failed = $0.state { return true } else { return false } }.count
        if failedAreas > 0 { parts.append("\(CountFormat.items(failedAreas, singular: "area")) couldn't finish") }
        let skipped = board.skippedModules.count
        if skipped > 0 { parts.append("\(CountFormat.items(skipped, singular: "area")) not run") }
        return parts.isEmpty ? "Nothing needed doing" : parts.joined(separator: " · ")
    }

    /// Completion headline: "Done. You freed 6.2 GB." / "All done.".
    public static func doneHeadline(_ board: CheckupRunBoard) -> String {
        if board.freedBytes > 0 { return "Done. You freed \(ByteFormat.string(board.freedBytes))." }
        if board.failures.isEmpty && board.skippedModules.isEmpty { return "All done." }
        return "Finished, with a few exceptions."
    }

    /// Idle-screen line about the last Checkup.
    public static func lastCheckupLine(_ summary: CheckupLastSummary?, now: Date = Date()) -> String {
        guard let summary else { return "No checkup yet — your first scan takes a minute or two." }
        if let runDate = summary.runDate, summary.scanDate.map({ runDate >= $0 }) ?? true {
            let when = DurationFormat.relative(runDate, now: now)
            if summary.runFreedBytes > 0 {
                return "Last checkup \(when) · freed \(ByteFormat.string(summary.runFreedBytes))"
            }
            if summary.runProcessedCount > 0 {
                return "Last checkup \(when) · \(CountFormat.items(summary.runProcessedCount)) handled"
            }
            return "Last checkup \(when)"
        }
        if let scanDate = summary.scanDate {
            let when = DurationFormat.relative(scanDate, now: now)
            if summary.scanFoundBytes > 0 {
                return "Last scan \(when) · found \(ByteFormat.string(summary.scanFoundBytes))"
            }
            return "Last scan \(when)"
        }
        return "No checkup yet"
    }
}

// MARK: - Progress throttle

/// Lets at most one progress event per key through every `interval` seconds.
/// Contributors may report thousands of events per second; the UI needs ~12.
public final class CheckupProgressThrottle: @unchecked Sendable {
    public let interval: TimeInterval
    private let clock: @Sendable () -> TimeInterval
    private let lock = NSLock()
    private var last: [String: TimeInterval] = [:]

    public init(interval: TimeInterval = 0.08,
                clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.interval = interval
        self.clock = clock
    }

    /// True when an event for `key` may be delivered now. `force` always passes
    /// (e.g. a final 100 % event) and restarts the interval.
    public func shouldEmit(key: String, force: Bool = false) -> Bool {
        let now = clock()
        lock.lock()
        defer { lock.unlock() }
        if !force, let previous = last[key], now - previous < interval { return false }
        last[key] = now
        return true
    }

    public func reset() {
        lock.lock()
        last.removeAll()
        lock.unlock()
    }
}
