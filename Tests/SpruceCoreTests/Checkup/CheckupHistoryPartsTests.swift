import XCTest
@testable import SpruceCore

final class CheckupHistoryPartsTests: XCTestCase {
    private let runDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func board(_ outcomes: [RunOutcome]) -> CheckupRunBoard {
        var board = CheckupRunBoard(plan: outcomes.map(\.module))
        for outcome in outcomes {
            board.start(outcome.module)
            board.complete(outcome.module, outcome: outcome)
        }
        return board
    }

    // MARK: Applications

    func testApplicationsUpdatesAndRemovedAppFilesAreRecordedApart() {
        let prefix = CheckupHistory.applicationsUpdateIDPrefix
        let outcome = RunOutcome(module: .applications, freedBytes: 2_000_000_000, processedCount: 5,
                                 removedItemIDs: [prefix + "brew:firefox", prefix + "sparkle:com.example.app",
                                                  "/Users/me/Library/Caches/com.gone.app",
                                                  "/Users/me/Library/Application Support/Gone",
                                                  "/Users/me/Library/Preferences/com.gone.app.plist"],
                                 summary: "Updated 2 apps · removed 3 files (2 GB)")
        let entries = CheckupHistory.runEntries(board([outcome]), date: runDate)
        XCTAssertEqual(entries.map(\.kind), [.update, .clean, .checkup])
        XCTAssertTrue(entries.dropLast().allSatisfy { $0.module == .applications && $0.date == runDate })

        let update = entries[0]
        XCTAssertEqual(update.count, 2, "only updated apps count as app updates")
        XCTAssertEqual(update.bytes, 0, "updates free no space")
        XCTAssertEqual(update.summary, "Checkup · Updated 2 apps")

        let files = entries[1]
        XCTAssertEqual(files.bytes, 2_000_000_000, "files of removed apps count as space freed")
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files.summary, "Checkup · Removed 3 files of removed apps · 2 GB")

        XCTAssertEqual(entries[2].bytes, 0)
        XCTAssertEqual(entries[2].count, 5)
    }

    func testApplicationsOnlyFilesOrOnlyUpdates() {
        let filesOnly = RunOutcome(module: .applications, freedBytes: 500, processedCount: 1, removedItemIDs: ["/tmp/x"])
        XCTAssertEqual(CheckupHistory.applicationsParts(filesOnly).map(\.kind), [.clean])

        let updatesOnly = RunOutcome(module: .applications, processedCount: 1,
                                     removedItemIDs: [CheckupHistory.applicationsUpdateIDPrefix + "brew:iterm2"])
        let parts = CheckupHistory.applicationsParts(updatesOnly)
        XCTAssertEqual(parts, [CheckupHistoryPart(kind: .update, count: 1, summary: "Updated 1 app")])
    }

    // MARK: Failure-only outcomes

    func testFailureOnlyOutcomesAreNotRecordedAsActions() {
        let performance = RunOutcome(module: .performance,
                                     failures: [ItemFailure(itemID: "performance.task.reindex", title: "Reindex Spotlight",
                                                            reason: "The administrator password prompt was cancelled.")])
        let applications = RunOutcome(module: .applications,
                                      failures: [ItemFailure(itemID: CheckupHistory.applicationsUpdateIDPrefix + "brew:a",
                                                             title: "A 2.0", reason: "The app is open."),
                                                 ItemFailure(itemID: CheckupHistory.applicationsUpdateIDPrefix + "brew:b",
                                                             title: "B 3.0", reason: "Download failed.")],
                                      summary: "Nothing to do")
        let protection = RunOutcome(module: .protection,
                                    failures: [ItemFailure(itemID: "t", title: "Adware", reason: "Refused")])
        let entries = CheckupHistory.runEntries(board([protection, performance, applications]), date: runDate)

        XCTAssertEqual(entries.map(\.module), [.protection, .performance, .applications, .checkup])
        for entry in entries.dropLast() {
            XCTAssertEqual(entry.kind, .other, "\(entry.module) did nothing, so it is not an action")
            XCTAssertEqual(entry.count, 0)
            XCTAssertEqual(entry.bytes, 0)
        }
        XCTAssertEqual(entries[1].summary,
                       "Checkup · Couldn't complete Reindex Spotlight — The administrator password prompt was cancelled.")
        XCTAssertEqual(entries[2].summary, "Checkup · 2 items couldn't be completed — The app is open.")
        let actionKinds: Set<ActivityEntry.Kind> = [.maintenance, .update, .threatRemoved, .clean]
        XCTAssertFalse(entries.contains { actionKinds.contains($0.kind) })
    }

    func testPartialOutcomeKeepsItsKindAndIgnoresFailures() {
        let outcome = RunOutcome(module: .performance, processedCount: 3,
                                 failures: [ItemFailure(itemID: "x", title: "X", reason: "No")], summary: "Ran 3 tasks")
        let entries = CheckupHistory.runEntries(board([outcome]), date: runDate)
        XCTAssertEqual(entries.map(\.kind), [.maintenance, .checkup])
        XCTAssertEqual(entries[0].count, 3)
    }

    func testOutcomeThatDidNothingAndFailedNothingIsNotRecorded() {
        let entries = CheckupHistory.runEntries(board([RunOutcome(module: .clutter, summary: "Nothing selected")]), date: runDate)
        XCTAssertEqual(entries.map(\.kind), [.checkup])
    }

    // MARK: Parts reported by an area

    func testCustomPartsReplaceTheDefaultSplit() {
        let cleanup = RunOutcome(module: .cleanup, freedBytes: 1_300, processedCount: 4, summary: "Cleaned 4 items")
        let parts: [ModuleID: [CheckupHistoryPart]] = [.cleanup: [
            CheckupHistoryPart(kind: .clean, bytes: 900, count: 3, summary: "Cleaned 3 items"),
            CheckupHistoryPart(kind: .other, bytes: 1_000, count: 1, summary: "Emptied the Trash · 1 item"),
        ]]
        let entries = CheckupHistory.runEntries(board([cleanup]), date: runDate, parts: parts)
        XCTAssertEqual(entries.map(\.kind), [.clean, .other, .checkup])
        XCTAssertEqual(entries[0].bytes, 900)
        XCTAssertEqual(entries[1].bytes, 1_000)
        XCTAssertEqual(entries[1].module, .cleanup)
        XCTAssertEqual(entries[1].summary, "Checkup · Emptied the Trash · 1 item")
    }

    func testCustomPartsThatDidNothingFallBackToTheFailureNote() {
        let cleanup = RunOutcome(module: .cleanup,
                                 failures: [ItemFailure(itemID: "/a", title: "Chrome cache", reason: "Google Chrome is open")],
                                 summary: "Cleaned 0 items · Nothing was removed")
        let parts: [ModuleID: [CheckupHistoryPart]] = [.cleanup: [
            CheckupHistoryPart(kind: .clean, summary: "Cleaned 0 items · Nothing was removed"),
        ]]
        let entries = CheckupHistory.runEntries(board([cleanup]), date: runDate, parts: parts)
        XCTAssertEqual(entries.map(\.kind), [.other, .checkup])
        XCTAssertEqual(entries[0].summary, "Checkup · Couldn't complete Chrome cache — Google Chrome is open")
    }

    func testLastSummaryAddsEveryPartOfTheRun() throws {
        let prefix = CheckupHistory.applicationsUpdateIDPrefix
        let applications = RunOutcome(module: .applications, freedBytes: 700, processedCount: 2,
                                      removedItemIDs: [prefix + "brew:x", "/tmp/leftover"])
        let cleanup = RunOutcome(module: .cleanup, freedBytes: 300, processedCount: 1)
        var history = ActivityHistory()
        for entry in CheckupHistory.runEntries(board([cleanup, applications]), date: runDate) { history.append(entry) }
        let summary = try XCTUnwrap(CheckupHistory.lastSummary(in: history))
        XCTAssertEqual(summary.runFreedBytes, 1_000)
        XCTAssertEqual(summary.runProcessedCount, 3)
    }

    // MARK: Scan requests

    func testScanRequestStartsAFreshScanUnlessResultsAreRecent() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let stale = now.addingTimeInterval(-(CheckupScanRequest.staleAfter + 60))
        let fresh = now.addingTimeInterval(-60)
        XCTAssertEqual(CheckupScanRequest.response(to: .idle, now: now), .startScan)
        XCTAssertEqual(CheckupScanRequest.response(to: .done, now: now), .startScan,
                       "an old completion screen is not the scan that was asked for")
        XCTAssertEqual(CheckupScanRequest.response(to: .busy, now: now), .showCurrent)
        XCTAssertEqual(CheckupScanRequest.response(to: .results(finishedAt: fresh, hasCustomChoices: false), now: now),
                       .showCurrent)
        XCTAssertEqual(CheckupScanRequest.response(to: .results(finishedAt: fresh, hasCustomChoices: true), now: now),
                       .showCurrent)
        XCTAssertEqual(CheckupScanRequest.response(to: .results(finishedAt: stale, hasCustomChoices: false), now: now),
                       .startScan)
        XCTAssertEqual(CheckupScanRequest.response(to: .results(finishedAt: stale, hasCustomChoices: true), now: now),
                       .askToScanAgain, "the user's choices are never thrown away without asking")
        XCTAssertEqual(CheckupScanRequest.response(to: .results(finishedAt: nil, hasCustomChoices: false), now: now),
                       .startScan)
    }
}
