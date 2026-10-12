import XCTest
@testable import SpruceCore

final class CheckupRunTests: XCTestCase {
    func testRunOrderPutsProtectionFirstAndUpdatesLast() {
        XCTAssertEqual(CheckupRunOrder.plan(for: Set(ModuleID.checkupContributors)),
                       [.protection, .cleanup, .clutter, .performance, .applications])
        XCTAssertEqual(CheckupRunOrder.plan(for: [.applications, .cleanup]), [.cleanup, .applications])
        XCTAssertEqual(CheckupRunOrder.plan(for: []), [])
    }

    func testRunBoardSequencingAndTotals() {
        var board = CheckupRunBoard(plan: [.protection, .cleanup, .performance], startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(board.next, .protection)
        XCTAssertEqual(board.overallFraction, 0)

        board.start(.protection)
        XCTAssertEqual(board.current?.module, .protection)
        board.update(.protection, progress: ScanProgress(fraction: 0.5, message: "Removing"))
        XCTAssertEqual(board.overallFraction, 0.5 / 3, accuracy: 0.0001)
        board.complete(.protection, outcome: RunOutcome(module: .protection, processedCount: 1, removedItemIDs: ["t"], summary: "Removed 1 threat"))

        board.start(.cleanup)
        // Progress for a step that is not running is ignored.
        board.update(.performance, progress: ScanProgress(fraction: 0.9, message: ""))
        XCTAssertEqual(board.step(.performance)?.progress.fraction, nil)
        board.complete(.cleanup, outcome: RunOutcome(module: .clutter, freedBytes: 2_000, processedCount: 4,
                                                     failures: [ItemFailure(itemID: "a", title: "A", reason: "In use")]))
        XCTAssertEqual(board.step(.cleanup)?.outcome?.module, .cleanup, "outcome module is forced to the step")

        board.start(.performance)
        board.fail(.performance, reason: "Helper declined")
        XCTAssertTrue(board.isFinished)
        XCTAssertNotNil(board.finishedAt)
        XCTAssertEqual(board.overallFraction, 1)
        XCTAssertEqual(board.freedBytes, 2_000)
        XCTAssertEqual(board.processedCount, 5)
        XCTAssertEqual(board.failures.count, 2)
        XCTAssertEqual(board.failures.last?.title, "Performance")
        XCTAssertEqual(board.failures.last?.reason, "Helper declined")

        let merged = board.mergedOutcome
        XCTAssertEqual(merged.module, .checkup)
        XCTAssertEqual(merged.freedBytes, 2_000)
        XCTAssertEqual(merged.removedItemIDs, ["t"])
        XCTAssertEqual(merged.failures.count, 2)
    }

    func testStopSkipsRemainingSteps() {
        var board = CheckupRunBoard(plan: [.cleanup, .clutter, .applications])
        board.start(.cleanup)
        board.skipRemaining()
        XCTAssertFalse(board.isFinished, "the running step still has to finish")
        board.complete(.cleanup, outcome: RunOutcome(module: .cleanup, freedBytes: 10, processedCount: 1))
        XCTAssertTrue(board.isFinished)
        XCTAssertEqual(board.skippedModules, [.clutter, .applications])
        XCTAssertEqual(CheckupCopy.stepDetail(board.step(.clutter)!), "Not run — you stopped Checkup")
        XCTAssertEqual(CheckupCopy.doneHeadline(board), "Done. You freed 10 bytes.")
        XCTAssertTrue(CheckupCopy.runSummary(board).contains("2 areas not run"))
    }

    func testDoneHeadlines() {
        var clean = CheckupRunBoard(plan: [.performance])
        clean.start(.performance)
        clean.complete(.performance, outcome: RunOutcome(module: .performance, processedCount: 2))
        XCTAssertEqual(CheckupCopy.doneHeadline(clean), "All done.")
        XCTAssertEqual(CheckupCopy.runSummary(clean), "2 items handled")

        var failed = CheckupRunBoard(plan: [.applications])
        failed.start(.applications)
        failed.fail(.applications, reason: "Offline")
        XCTAssertEqual(CheckupCopy.doneHeadline(failed), "Finished, with a few exceptions.")
        XCTAssertEqual(CheckupCopy.runSummary(failed), "1 area couldn't finish")
    }
}

final class CheckupHistoryTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("checkup-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testActivityKinds() {
        XCTAssertEqual(CheckupHistory.activityKind(for: .cleanup), .clean)
        XCTAssertEqual(CheckupHistory.activityKind(for: .clutter), .clean)
        XCTAssertEqual(CheckupHistory.activityKind(for: .protection), .threatRemoved)
        XCTAssertEqual(CheckupHistory.activityKind(for: .performance), .maintenance)
        XCTAssertEqual(CheckupHistory.activityKind(for: .applications), .update)
    }

    func testScanEntry() {
        let tiles = [
            CheckupTile(module: .cleanup, headline: "4 GB", detail: "", status: .attention, reclaimableBytes: 4_000_000_000, actionCount: 9),
            CheckupTile(module: .protection, headline: "No threats", detail: "", status: .clear),
            CheckupTile.unavailable(.clutter, reason: "Off"),
        ]
        let entry = CheckupHistory.scanEntry(tiles: tiles)
        XCTAssertEqual(entry.module, .checkup)
        XCTAssertEqual(entry.kind, .scan)
        XCTAssertEqual(entry.bytes, 4_000_000_000)
        XCTAssertEqual(entry.count, 9)
        XCTAssertEqual(entry.summary, "Checkup: Cleanup 4 GB · 1 area all good · 1 area skipped")
    }

    func testRunEntriesAndLastSummarySurviveJSONRoundTrip() throws {
        var board = CheckupRunBoard(plan: [.protection, .cleanup, .clutter])
        board.start(.protection)
        board.complete(.protection, outcome: RunOutcome(module: .protection, summary: "No threats to remove"))
        board.start(.cleanup)
        board.complete(.cleanup, outcome: RunOutcome(module: .cleanup, freedBytes: 3_000_000_000, processedCount: 120, summary: "Cleaned 120 items"))
        board.start(.clutter)
        board.complete(.clutter, outcome: RunOutcome(module: .clutter, freedBytes: 200_000_000, processedCount: 4))

        let runDate = Date(timeIntervalSince1970: 1_700_000_000.75)
        let entries = CheckupHistory.runEntries(board, date: runDate)
        // Protection did nothing, so it is not recorded; the marker carries no bytes.
        XCTAssertEqual(entries.map(\.module), [.cleanup, .clutter, .checkup])
        XCTAssertEqual(entries[0].kind, .clean)
        XCTAssertEqual(entries[0].summary, "Checkup · Cleaned 120 items")
        XCTAssertEqual(entries[1].summary, "Checkup · Freed 200 MB · 4 items handled")
        XCTAssertEqual(entries[2].kind, .other)
        XCTAssertEqual(entries[2].bytes, 0)
        XCTAssertEqual(entries[2].count, 124)

        var history = ActivityHistory()
        history.append(ActivityEntry(date: runDate.addingTimeInterval(-600), module: .checkup, kind: .scan,
                                     bytes: 3_500_000_000, count: 130, summary: "scan"))
        // An unrelated Cleanup entry an hour earlier must not be counted.
        history.append(ActivityEntry(date: runDate.addingTimeInterval(-3_600), module: .cleanup, kind: .clean,
                                     bytes: 999, count: 1, summary: "manual"))
        for entry in entries { history.append(entry) }

        let store = JSONFileStore<ActivityHistory>(url: tempDir.appendingPathComponent("history.json"))
        try store.save(history)
        let reloaded = try XCTUnwrap(store.load())

        for candidate in [history, reloaded] {
            let summary = try XCTUnwrap(CheckupHistory.lastSummary(in: candidate))
            XCTAssertEqual(summary.scanFoundBytes, 3_500_000_000)
            XCTAssertEqual(summary.scanActionCount, 130)
            XCTAssertEqual(summary.runFreedBytes, 3_200_000_000)
            XCTAssertEqual(summary.runProcessedCount, 124)
            XCTAssertNotNil(summary.runDate)
        }
    }

    func testLastSummaryIsNilWithoutCheckupEntries() {
        var history = ActivityHistory()
        history.append(ActivityEntry(module: .cleanup, kind: .clean, bytes: 5, summary: "x"))
        XCTAssertNil(CheckupHistory.lastSummary(in: history))
    }

    func testLastCheckupLine() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        XCTAssertTrue(CheckupCopy.lastCheckupLine(nil, now: now).hasPrefix("No checkup yet"))

        let scanned = CheckupLastSummary(scanDate: now.addingTimeInterval(-86_400 * 6 - 120), scanFoundBytes: 4_100_000_000)
        XCTAssertEqual(CheckupCopy.lastCheckupLine(scanned, now: now), "Last scan 6 days ago · found 4.1 GB")

        var ran = scanned
        ran.runDate = now.addingTimeInterval(-86_400 * 6)
        ran.runFreedBytes = 3_200_000_000
        XCTAssertEqual(CheckupCopy.lastCheckupLine(ran, now: now), "Last checkup 6 days ago · freed 3.2 GB")

        // A newer scan without a run is reported as a scan.
        var rescanned = ran
        rescanned.scanDate = now.addingTimeInterval(-60)
        XCTAssertEqual(CheckupCopy.lastCheckupLine(rescanned, now: now), "Last scan today · found 4.1 GB")
    }

    func testResultsCopy() {
        let tiles = [
            CheckupTile(module: .cleanup, headline: "4 GB", detail: "", status: .attention),
            CheckupTile(module: .applications, headline: "3 updates", detail: "", status: .info),
            CheckupTile(module: .protection, headline: "No threats", detail: "", status: .clear),
        ]
        XCTAssertEqual(CheckupCopy.resultsTitle(tiles: tiles), "Here's the rundown.")
        XCTAssertEqual(CheckupCopy.resultsLine(tiles: tiles), "Cleanup 4 GB · Applications 3 updates · 1 area all good")

        let allClear = [CheckupTile(module: .protection, headline: "No threats", detail: "", status: .clear)]
        XCTAssertEqual(CheckupCopy.resultsTitle(tiles: allClear), "Spotless.")
        XCTAssertEqual(CheckupCopy.resultsLine(tiles: allClear), "Everything looks good")
        XCTAssertEqual(CheckupCopy.stepResult(allClear[0]), "All good")

        let none = [CheckupTile.unavailable(.cleanup, reason: "Off")]
        XCTAssertEqual(CheckupCopy.resultsTitle(tiles: none), "Nothing could be checked.")
    }
}

final class CheckupThrottleTests: XCTestCase {
    final class FakeClock: @unchecked Sendable {
        var now: TimeInterval = 0
    }

    func testThrottlePerKey() {
        let clock = FakeClock()
        let throttle = CheckupProgressThrottle(interval: 0.1, clock: { clock.now })
        XCTAssertTrue(throttle.shouldEmit(key: "a"))
        XCTAssertFalse(throttle.shouldEmit(key: "a"))
        XCTAssertTrue(throttle.shouldEmit(key: "b"), "keys are independent")
        clock.now = 0.05
        XCTAssertFalse(throttle.shouldEmit(key: "a"))
        XCTAssertTrue(throttle.shouldEmit(key: "a", force: true))
        clock.now = 0.1
        XCTAssertFalse(throttle.shouldEmit(key: "a"), "force restarts the interval")
        clock.now = 0.2
        XCTAssertTrue(throttle.shouldEmit(key: "a"))
        throttle.reset()
        XCTAssertTrue(throttle.shouldEmit(key: "a"))
    }
}
