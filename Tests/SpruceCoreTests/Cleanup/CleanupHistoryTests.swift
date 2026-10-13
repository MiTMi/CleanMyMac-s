import Foundation
import XCTest
@testable import SpruceCore

final class CleanupHistoryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(_ breakdown: CleanupRunBreakdown, failures: [ItemFailure] = [],
                        trashRunIDs: [UUID] = []) -> CleanupRunReport {
        let rows = breakdown.cleanedCount + breakdown.emptiedCount
        let outcome = RunOutcome(module: .cleanup, date: date,
                                 freedBytes: breakdown.deletedBytes + breakdown.emptiedBytes + breakdown.trashedBytes,
                                 processedCount: rows,
                                 removedItemIDs: (0..<rows).map { "row\($0)" },
                                 failures: failures,
                                 summary: CleanupHistory.runSummary(breakdown),
                                 trashedBytes: breakdown.trashedBytes,
                                 trashedCount: breakdown.trashedCount,
                                 trashRunIDs: trashRunIDs)
        return CleanupRunReport(outcome: outcome, breakdown: breakdown)
    }

    func testOnlyTheCleanedRecordKeepsWhatWentToTheTrash() throws {
        let runID = UUID()
        let b = CleanupRunBreakdown(cleanedCount: 3, deletedBytes: 1_000, trashedCount: 2, trashedBytes: 700,
                                    emptiedCount: 1, emptiedBytes: 5_000)
        let run = report(b, trashRunIDs: [runID])
        XCTAssertLessThanOrEqual(run.outcome.trashedBytes, run.outcome.freedBytes)
        let records = CleanupHistory.records(for: run)
        XCTAssertEqual(records.map(\.kind), [.clean, .other])
        XCTAssertEqual(records[0].outcome.freedBytes, 1_700)
        XCTAssertEqual(records[0].outcome.trashedBytes, 700)
        XCTAssertEqual(records[0].outcome.trashedCount, 2)
        XCTAssertEqual(records[0].outcome.trashRunIDs, [runID], "the flow's outcome can put the run back")
        XCTAssertEqual(records[1].outcome.trashedBytes, 0)
        XCTAssertEqual(records[1].outcome.trashedCount, 0)
        XCTAssertTrue(records[1].outcome.trashRunIDs.isEmpty)
        // Merging the records again gives back the run's Trash part once.
        let merged = RunOutcome.merged(records.map(\.outcome), module: .cleanup)
        XCTAssertEqual(merged.trashRunIDs, [runID])
        XCTAssertEqual(merged.trashedBytes, 700)
    }

    func testRunSummaryDescribesTheWholeRun() {
        let b = CleanupRunBreakdown(cleanedCount: 3, deletedBytes: 2_000_000, trashedCount: 1, trashedBytes: 500_000,
                                    emptiedCount: 2, emptiedBytes: 3_000_000)
        XCTAssertEqual(CleanupHistory.runSummary(b),
                       "Cleaned 5 items · \(ByteFormat.string(5_000_000)) deleted · 1 item moved to the Trash (\(ByteFormat.string(500_000)))")
        XCTAssertEqual(CleanupHistory.runSummary(CleanupRunBreakdown()), "Cleaned 0 items · Nothing was removed")
        XCTAssertEqual(CleanupHistory.runSummary(CleanupRunBreakdown(cleanedCount: 2)), "Cleaned 2 items · Already clean")
    }

    func testRunWithoutTrashIsOneCleanRecordCountingTrashedBytes() throws {
        let b = CleanupRunBreakdown(cleanedCount: 4, deletedBytes: 1_000, trashedCount: 1, trashedBytes: 300)
        let run = report(b)
        let records = CleanupHistory.records(for: run)
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.kind, .clean)
        XCTAssertEqual(record.outcome.freedBytes, 1_300, "moved-to-Trash bytes count as freed, like every other module")
        XCTAssertEqual(record.outcome.processedCount, 4)
        XCTAssertEqual(record.outcome.summary, run.outcome.summary)
        XCTAssertEqual(record.outcome.removedItemIDs, run.outcome.removedItemIDs)
        XCTAssertEqual(record.outcome.date, date)
    }

    func testEmptyingOnlyTheTrashIsRecordedAsOther() throws {
        let run = report(CleanupRunBreakdown(emptiedCount: 3, emptiedBytes: 9_000_000))
        let records = CleanupHistory.records(for: run)
        XCTAssertEqual(records.map(\.kind), [.other])
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.outcome.freedBytes, 9_000_000)
        XCTAssertEqual(record.outcome.processedCount, 3)
        XCTAssertTrue(record.outcome.summary.hasPrefix("Emptied the Trash"))
        XCTAssertEqual(record.outcome.removedItemIDs, run.outcome.removedItemIDs, "the flow still drops every removed row")
    }

    func testMixedRunSplitsCleanedAndEmptiedParts() throws {
        let failure = ItemFailure(itemID: "x", title: "X", reason: "Locked")
        let b = CleanupRunBreakdown(cleanedCount: 2, deletedBytes: 4_000, trashedCount: 0, trashedBytes: 0,
                                    emptiedCount: 1, emptiedBytes: 6_000)
        let run = report(b, failures: [failure])
        let records = CleanupHistory.records(for: run)
        XCTAssertEqual(records.map(\.kind), [.clean, .other])
        XCTAssertEqual(records[0].outcome.freedBytes, 4_000)
        XCTAssertEqual(records[0].outcome.processedCount, 2)
        XCTAssertEqual(records[0].outcome.summary, "Cleaned 2 items · \(ByteFormat.string(4_000)) deleted")
        XCTAssertEqual(records[0].outcome.failures, [failure])
        XCTAssertEqual(records[1].outcome.freedBytes, 6_000)
        XCTAssertEqual(records[1].outcome.processedCount, 1)
        XCTAssertEqual(records[1].outcome.summary, "Emptied the Trash · 1 item · \(ByteFormat.string(6_000)) deleted")
        XCTAssertTrue(records.allSatisfy { $0.outcome.date == date })

        // Space-freed totals see only the cleaned part; the Trash part is like the menu bar's Empty Trash.
        var history = ActivityHistory()
        for record in records { history.record(record.outcome, kind: record.kind) }
        XCTAssertEqual(history.totalBytes(kind: .clean), 4_000)
        XCTAssertEqual(history.totalBytes(kind: .other), 6_000)
    }

    func testRunThatOnlyFailedStillLeavesOneCleanRecord() throws {
        let failure = ItemFailure(itemID: "a", title: "A", reason: "Locked")
        let run = report(CleanupRunBreakdown(), failures: [failure])
        let records = CleanupHistory.records(for: run)
        XCTAssertEqual(records.map(\.kind), [.clean])
        XCTAssertEqual(records[0].outcome.freedBytes, 0)
        XCTAssertEqual(records[0].outcome.failures, [failure])
    }

    func testEntriesUseOneDateAndPrefix() {
        let run = report(CleanupRunBreakdown(cleanedCount: 1, deletedBytes: 10, emptiedCount: 1, emptiedBytes: 20))
        let when = date.addingTimeInterval(60)
        let entries = CleanupHistory.entries(for: run, date: when, summaryPrefix: "Checkup · ")
        XCTAssertEqual(entries.map(\.kind), [.clean, .other])
        XCTAssertEqual(entries.map(\.bytes), [10, 20])
        XCTAssertEqual(entries.map(\.count), [1, 1])
        XCTAssertTrue(entries.allSatisfy { $0.date == when && $0.module == .cleanup && $0.summary.hasPrefix("Checkup · ") })
    }
}
