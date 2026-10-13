import XCTest
@testable import SpruceCore

final class CheckupBoardTests: XCTestCase {
    private let all = Set(ModuleID.checkupContributors)

    func testInitialStatesFollowSettingsAndAvailability() {
        let board = CheckupBoard(included: [.cleanup, .protection, .clutter], available: [.cleanup, .protection, .performance])
        XCTAssertEqual(board.areas.map(\.module), ModuleID.checkupContributors)
        XCTAssertEqual(board.area(.cleanup)?.state, .waiting)
        XCTAssertEqual(board.area(.protection)?.state, .waiting)
        XCTAssertEqual(board.area(.performance)?.state, .excluded)
        XCTAssertEqual(board.area(.applications)?.state, .excluded)
        XCTAssertEqual(board.area(.clutter)?.state, .unsupported)
        XCTAssertEqual(board.pendingModules, [.cleanup, .protection])
        XCTAssertEqual(board.participatingModules, [.cleanup, .protection])
        XCTAssertTrue(board.isScanning)
        XCTAssertTrue(board.hasWork)
    }

    func testNothingIncludedMeansNoWork() {
        let board = CheckupBoard(included: [], available: all)
        XCTAssertFalse(board.hasWork)
        XCTAssertFalse(board.isScanning)
        XCTAssertEqual(board.overallFraction(), 1)
        XCTAssertTrue(board.tiles.allSatisfy { $0.status == .unavailable })
        XCTAssertEqual(board.tiles.first?.detail, CheckupBoard.excludedReason)
    }

    func testLifecycleAndLateEventsAreIgnored() {
        var board = CheckupBoard(included: all, available: all)
        let start = Date(timeIntervalSince1970: 1_000)
        board.start(.cleanup, at: start)
        XCTAssertEqual(board.area(.cleanup)?.state, .scanning)
        board.update(.cleanup, progress: ScanProgress(fraction: 0.5, message: "Caches", bytesFound: 2_000))
        XCTAssertEqual(board.bytesFound, 2_000)

        let tile = CheckupTile(module: .cleanup, headline: "3 GB", detail: "to clean", status: .attention,
                               reclaimableBytes: 3_000_000_000, actionCount: 12)
        board.finish(.cleanup, tile: tile, at: start.addingTimeInterval(5))
        XCTAssertEqual(board.area(.cleanup)?.tile, tile)
        XCTAssertEqual(board.bytesFound, 3_000_000_000)

        // A late progress event or a second result must not change a finished area.
        board.update(.cleanup, progress: ScanProgress(fraction: 0.1, message: "late", bytesFound: 1))
        board.fail(.cleanup, reason: "late failure")
        XCTAssertEqual(board.area(.cleanup)?.tile, tile)
        XCTAssertEqual(board.area(.cleanup)?.progress.message, "Caches")
    }

    func testTileModuleIsForcedToTheArea() {
        var board = CheckupBoard(included: all, available: all)
        board.start(.clutter)
        board.finish(.clutter, tile: CheckupTile(module: .cleanup, headline: "x", detail: "y", status: .info))
        XCTAssertEqual(board.tile(for: .clutter)?.module, .clutter)
    }

    func testOverallFractionCombinesReportedAndEstimatedProgress() {
        var board = CheckupBoard(included: [.cleanup, .protection], available: all)
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(board.overallFraction(at: t0), 0)
        board.start(.cleanup, at: t0)
        board.start(.protection, at: t0)
        board.update(.cleanup, progress: ScanProgress(fraction: 0.5, message: ""))
        // Protection reports no fraction: estimated from elapsed time, below 0.9.
        let early = board.overallFraction(at: t0.addingTimeInterval(1))
        let later = board.overallFraction(at: t0.addingTimeInterval(60))
        XCTAssertGreaterThan(early, 0.25)
        XCTAssertGreaterThan(later, early)
        XCTAssertLessThan(later, 0.5 * 0.5 + 0.5 * 0.9 + 0.0001)
        board.finish(.cleanup, tile: CheckupTile(module: .cleanup, headline: "", detail: "", status: .clear))
        board.fail(.protection, reason: "boom")
        XCTAssertEqual(board.overallFraction(at: t0), 1)
        XCTAssertFalse(board.isScanning)
    }

    func testReportedFractionNeverCompletesAnArea() {
        var board = CheckupBoard(included: [.cleanup], available: all)
        board.start(.cleanup)
        board.update(.cleanup, progress: ScanProgress(fraction: 1, message: ""))
        XCTAssertLessThan(board.overallFraction(), 1)
    }

    func testTilesForEveryStateAndDefaultSelection() {
        var board = CheckupBoard(included: [.cleanup, .protection, .performance, .applications], available: all)
        for m in board.pendingModules { board.start(m) }
        board.finish(.cleanup, tile: CheckupTile(module: .cleanup, headline: "4 GB", detail: "", status: .attention,
                                                 reclaimableBytes: 4_000_000_000, actionCount: 3))
        board.finish(.protection, tile: CheckupTile(module: .protection, headline: "No threats", detail: "", status: .clear))
        board.finish(.performance, tile: CheckupTile(module: .performance, headline: "3 tasks", detail: "", status: .info))
        board.fail(.applications, reason: "Network unavailable")

        let tiles = board.tiles
        XCTAssertEqual(tiles.count, 5)
        XCTAssertEqual(tiles[3].status, .unavailable)
        XCTAssertEqual(tiles[3].detail, "Couldn't finish: Network unavailable")
        XCTAssertEqual(tiles[4].status, .unavailable)
        XCTAssertEqual(tiles[4].detail, CheckupBoard.excludedReason)
        // Attention tiles default on; info tiles default off; clear/unavailable are not selectable.
        XCTAssertEqual(board.defaultSelection, [.cleanup])
        XCTAssertEqual(board.selectableModules, [.cleanup, .performance])
    }

    func testRequeueAndReplaceTile() {
        var board = CheckupBoard(included: [.cleanup], available: all)
        XCTAssertEqual(board.area(.clutter)?.state, .excluded)
        board.requeue(.clutter)
        XCTAssertEqual(board.area(.clutter)?.state, .waiting)
        board.start(.clutter)
        let tile = CheckupTile(module: .clutter, headline: "12 duplicates", detail: "", status: .attention)
        board.finish(.clutter, tile: tile)
        var edited = tile
        edited.actionCount = 4
        board.replaceTile(.clutter, with: edited)
        XCTAssertEqual(board.tile(for: .clutter)?.actionCount, 4)
        // Replacing is only allowed for finished areas.
        board.replaceTile(.cleanup, with: edited)
        XCTAssertEqual(board.area(.cleanup)?.state, .waiting)
    }

    func testSelectionSummary() {
        let tiles = [
            CheckupTile(module: .cleanup, headline: "4 GB", detail: "", status: .attention, reclaimableBytes: 4_000_000_000, actionCount: 10),
            CheckupTile(module: .protection, headline: "All good", detail: "", status: .clear, reclaimableBytes: 50, actionCount: 0),
            CheckupTile(module: .performance, headline: "2 tasks", detail: "", status: .attention, actionCount: 2),
            CheckupTile.unavailable(.applications, reason: "Off"),
            CheckupTile(module: .clutter, headline: "1 GB", detail: "", status: .attention, reclaimableBytes: 1_000_000_000, actionCount: 5),
        ]
        let summary = CheckupSelectionSummary(tiles: tiles, selection: [.cleanup, .performance, .protection, .applications])
        XCTAssertEqual(summary.modules, [.cleanup, .performance])
        XCTAssertEqual(summary.reclaimableBytes, 4_000_000_000)
        XCTAssertEqual(summary.actionCount, 12)
        XCTAssertEqual(summary.selectableCount, 3)
        XCTAssertEqual(summary.orbDetail, "4 GB")

        let tasksOnly = CheckupSelectionSummary(tiles: tiles, selection: [.performance])
        XCTAssertEqual(tasksOnly.orbDetail, "2 actions")
        let none = CheckupSelectionSummary(tiles: tiles, selection: [])
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.orbDetail, "Nothing selected")
    }
}

final class CheckupReviewAdjustmentTests: XCTestCase {
    private func review(selected: [Int64], unselected: [Int64]) -> [ScanGroup] {
        var items: [ScanItem] = []
        for (i, size) in selected.enumerated() {
            items.append(ScanItem(id: "s\(i)", title: "s\(i)", size: size, safety: .safe, isSelected: true))
        }
        for (i, size) in unselected.enumerated() {
            items.append(ScanItem(id: "u\(i)", title: "u\(i)", size: size, safety: .review, isSelected: false))
        }
        return [ScanGroup(id: "g", title: "Group", items: items)]
    }

    func testByteHeadlineDetection() {
        XCTAssertTrue(CheckupReviewAdjustment.isByteHeadline("4.2 GB"))
        XCTAssertTrue(CheckupReviewAdjustment.isByteHeadline("512 bytes"))
        XCTAssertTrue(CheckupReviewAdjustment.isByteHeadline("Zero KB"))
        XCTAssertTrue(CheckupReviewAdjustment.isByteHeadline(ByteFormat.string(123_456_789)))
        XCTAssertFalse(CheckupReviewAdjustment.isByteHeadline("3 updates"))
        XCTAssertFalse(CheckupReviewAdjustment.isByteHeadline("No threats"))
        XCTAssertFalse(CheckupReviewAdjustment.isByteHeadline("GB"))
    }

    func testSizeTileFollowsSelection() {
        let tile = CheckupTile(module: .cleanup, headline: "3 GB", detail: "to clean", status: .attention,
                               reclaimableBytes: 3_000_000_000, actionCount: 2)
        let adjusted = CheckupReviewAdjustment.adjusted(tile, review: review(selected: [1_000_000_000], unselected: [2_000_000_000]))
        XCTAssertEqual(adjusted.headline, "1 GB")
        XCTAssertEqual(adjusted.reclaimableBytes, 1_000_000_000)
        XCTAssertEqual(adjusted.actionCount, 1)
        XCTAssertTrue(adjusted.isSelected)
        XCTAssertEqual(adjusted.detail, "to clean")

        let nothing = CheckupReviewAdjustment.adjusted(tile, review: review(selected: [], unselected: [2_000_000_000]))
        XCTAssertEqual(nothing.headline, "2 GB")
        XCTAssertEqual(nothing.reclaimableBytes, 0)
        XCTAssertFalse(nothing.isSelected)
    }

    func testCountTileKeepsHeadlineAndInfoBecomesAttention() {
        let tile = CheckupTile(module: .applications, headline: "3 updates", detail: "", status: .info, actionCount: 3)
        let adjusted = CheckupReviewAdjustment.adjusted(tile, review: review(selected: [10, 20], unselected: [30]))
        XCTAssertEqual(adjusted.headline, "3 updates")
        XCTAssertEqual(adjusted.reclaimableBytes, 0)
        XCTAssertEqual(adjusted.actionCount, 2)
        XCTAssertEqual(adjusted.status, .attention)
        XCTAssertTrue(adjusted.isSelected)
    }

    func testCountTileWithBytesUpdatesReclaimable() {
        let tile = CheckupTile(module: .clutter, headline: "12 duplicates", detail: "", status: .attention,
                               reclaimableBytes: 900, actionCount: 12)
        let adjusted = CheckupReviewAdjustment.adjusted(tile, review: review(selected: [100, 200], unselected: [600]))
        XCTAssertEqual(adjusted.headline, "12 duplicates")
        XCTAssertEqual(adjusted.reclaimableBytes, 300)
    }

    func testClearAndUnavailableTilesAreUntouched() {
        let clear = CheckupTile(module: .protection, headline: "No threats", detail: "", status: .clear)
        XCTAssertEqual(CheckupReviewAdjustment.adjusted(clear, review: review(selected: [1], unselected: [])), clear)
        let off = CheckupTile.unavailable(.clutter, reason: "Off")
        XCTAssertEqual(CheckupReviewAdjustment.adjusted(off, review: review(selected: [1], unselected: [])), off)
    }
}
