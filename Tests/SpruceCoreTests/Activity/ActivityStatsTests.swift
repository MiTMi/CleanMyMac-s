import XCTest
@testable import SpruceCore

final class ActivityStatsTests: XCTestCase {
    let calendar = ActivityMonthly.calendar(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testMonthsAreZeroFilledOldestFirst() {
        let months = ActivityMonthly.months(ActivityHistory(), count: 6, now: date(2026, 3, 15), calendar: calendar)
        XCTAssertEqual(months.count, 6)
        XCTAssertEqual(months.first?.start, date(2025, 10, 1, 0))
        XCTAssertEqual(months.last?.start, date(2026, 3, 1, 0))
        XCTAssertTrue(months.allSatisfy(\.isEmpty))
        XCTAssertEqual(months.map { ActivityMonthly.shortName($0.start, calendar: calendar) },
                       ["Oct", "Nov", "Dec", "Jan", "Feb", "Mar"])
        XCTAssertEqual(ActivityMonthly.title(months.last!.start, calendar: calendar), "March 2026")
    }

    func testAggregationPerKind() {
        let history = ActivityHistory(entries: [
            ActivityEntry(date: date(2026, 3, 2), module: .cleanup, kind: .clean, bytes: 1_000, count: 10, summary: ""),
            ActivityEntry(date: date(2026, 3, 3), module: .applications, kind: .uninstall, bytes: 500, count: 30, summary: ""),
            ActivityEntry(date: date(2026, 3, 4), module: .cloudStorage, kind: .cloudFreed, bytes: 700, count: 3, summary: ""),
            ActivityEntry(date: date(2026, 3, 5), module: .protection, kind: .malwareScan, count: 2, summary: ""),
            ActivityEntry(date: date(2026, 3, 5), module: .protection, kind: .threatRemoved, bytes: 20, count: 2, summary: ""),
            ActivityEntry(date: date(2026, 3, 6), module: .cleanup, kind: .scan, bytes: 9_999, count: 120, summary: ""),
            ActivityEntry(date: date(2026, 3, 7), module: .performance, kind: .maintenance, bytes: 8_000_000, count: 2, summary: ""),
            ActivityEntry(date: date(2026, 3, 8), module: .applications, kind: .update, count: 4, summary: ""),
            ActivityEntry(date: date(2026, 3, 9), module: .checkup, kind: .checkup, summary: ""),
            ActivityEntry(date: date(2026, 2, 9), module: .cleanup, kind: .clean, bytes: 4_000, count: 1, summary: ""),
            ActivityEntry(date: date(2025, 1, 9), module: .cleanup, kind: .clean, bytes: 1, count: 1, summary: "too old"),
        ])
        let months = ActivityMonthly.months(history, count: 6, now: date(2026, 3, 20), calendar: calendar)
        let march = months[5]
        XCTAssertEqual(march.bytesFreed, 1_000 + 500 + 20)   // scans and maintenance never count as freed
        XCTAssertEqual(march.cloudFreed, 700)
        XCTAssertEqual(march.threatsFound, 2)
        XCTAssertEqual(march.threatsRemoved, 2)
        XCTAssertEqual(march.malwareScans, 1)
        XCTAssertEqual(march.itemsScanned, 120)
        XCTAssertEqual(march.scans, 1)
        XCTAssertEqual(march.uninstalls, 1)
        XCTAssertEqual(march.appsUpdated, 4)
        XCTAssertEqual(march.tasksRun, 2)
        XCTAssertEqual(march.checkups, 1)
        XCTAssertEqual(march.cleanups, 1)
        XCTAssertEqual(march.entryCount, 9)
        XCTAssertGreaterThan(march.timeSaved, 0)
        XCTAssertEqual(months[4].bytesFreed, 4_000)
        XCTAssertEqual(months.reduce(0) { $0 + $1.entryCount }, 10)
        XCTAssertEqual(ActivityMonthly.allTime(history, calendar: calendar).entryCount, 11)
    }

    func testDeltas() {
        XCTAssertEqual(ActivityDelta.percent(current: 0, previous: 0), .none)
        XCTAssertEqual(ActivityDelta.percent(current: 5, previous: 0), .new)
        XCTAssertEqual(ActivityDelta.percent(current: 118, previous: 100), .up(18))
        XCTAssertEqual(ActivityDelta.percent(current: 96, previous: 100), .down(4))
        XCTAssertEqual(ActivityDelta.percent(current: 100.2, previous: 100), .same)
        XCTAssertEqual(ActivityDelta.absolute(current: 3, previous: 1), .up(2))
        XCTAssertEqual(ActivityDelta.absolute(current: 1, previous: 3), .down(2))
        XCTAssertEqual(ActivityDelta.up(18).label(), "▲ 18%")
        XCTAssertEqual(ActivityDelta.down(2).label(percent: false), "−2")
        XCTAssertNil(ActivityDelta.none.label())
    }

    func testTimeSavedCreditsAndDailyCap() {
        let day = date(2026, 3, 2)
        let entries = [
            ActivityEntry(date: day, module: .checkup, kind: .checkup, summary: ""),
            ActivityEntry(date: day, module: .applications, kind: .uninstall, count: 12, summary: ""),
            ActivityEntry(date: day, module: .cleanup, kind: .clean, count: 400, summary: ""),
            ActivityEntry(date: day, module: .cleanup, kind: .scan, count: 400, summary: ""),
        ]
        let estimate = ActivityTimeSaved.estimate(entries, calendar: calendar)
        XCTAssertEqual(estimate.total, 600 + 180 + 45 + 2)
        XCTAssertFalse(estimate.wasCapped)
        XCTAssertEqual(estimate.lines.first?.kind, .checkup)
        XCTAssertEqual(estimate.lines.count, 3)

        let big = (0..<20).map { _ in ActivityEntry(date: day, module: .protection, kind: .threatRemoved, count: 5, summary: "") }
        let capped = ActivityTimeSaved.estimate(big, calendar: calendar)
        XCTAssertEqual(capped.total, ActivityTimeSaved.dailyCap)
        XCTAssertTrue(capped.wasCapped)

        let cloud = ActivityTimeSaved.credit(for: ActivityEntry(module: .cloudStorage, kind: .cloudFreed, count: 1_000, summary: ""))
        XCTAssertEqual(cloud.seconds, ActivityTimeSaved.Constant.cloudSessionCap)
        XCTAssertEqual(ActivityTimeSaved.formatted(0), "None yet")
        XCTAssertEqual(ActivityTimeSaved.formatted(300), "≈ 5 min")
        XCTAssertEqual(ActivityTimeSaved.formatted(9_600), "≈ 2 h 40 min")
    }

    func testTimelineGroupsByDayNewestFirst() {
        let history = ActivityHistory(entries: [
            ActivityEntry(date: date(2026, 3, 1, 9), module: .cleanup, kind: .clean, summary: "a"),
            ActivityEntry(date: date(2026, 3, 2, 9), module: .cleanup, kind: .clean, summary: "b"),
            ActivityEntry(date: date(2026, 3, 2, 18), module: .cleanup, kind: .scan, summary: "c"),
        ])
        let days = ActivityTimeline.recent(history, limit: 10, calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].entries.map(\.summary), ["c", "b"])
        XCTAssertEqual(days[1].entries.map(\.summary), ["a"])
        XCTAssertEqual(ActivityTimeline.recent(history, limit: 1, calendar: calendar).first?.entries.count, 1)
        let now = date(2026, 3, 2, 20)
        XCTAssertEqual(ActivityTimeline.dayTitle(days[0].day, now: now, calendar: calendar), "Today")
        XCTAssertEqual(ActivityTimeline.dayTitle(days[1].day, now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(ActivityTimeline.dayTitle(date(2026, 2, 23), now: now, calendar: calendar), "Mon, Feb 23")
        XCTAssertEqual(ActivityTimeline.dayTitle(date(2025, 12, 25), now: now, calendar: calendar), "Thu, Dec 25, 2025")
        XCTAssertEqual(ActivityTimeline.timeLabel(date(2026, 3, 2, 7), calendar: calendar), "07:00")
    }

    func testOperationLogParsing() {
        let lines = [
            "2026-03-02T10:00:00Z\tcleanup\ttrash\tok\t2048\t/Users/me/Library/Caches/x",
            "garbage line",
            "2026-03-02T10:01:00Z\ttoolbox\tremove\terror\t0\t/Users/me/.Trash/a\twith tab",
        ]
        let parsed = ActivityLogLine.parseAll(lines)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].module, "toolbox")
        XCTAssertEqual(parsed[0].detail, "/Users/me/.Trash/a\twith tab")
        XCTAssertFalse(parsed[0].isSuccess)
        XCTAssertEqual(parsed[1].detail, "garbage line")
        XCTAssertNil(parsed[1].date)
        XCTAssertEqual(parsed[2].bytes, 2048)
        XCTAssertNotNil(parsed[2].date)
        XCTAssertTrue(parsed[2].isSuccess)
        XCTAssertTrue(parsed[2].matches("caches"))
        XCTAssertFalse(parsed[2].matches("toolbox"))
        XCTAssertTrue(parsed[2].matches("  "))
    }

    func testKindPresentationIsComplete() {
        let kinds: [ActivityEntry.Kind] = [.scan, .clean, .malwareScan, .threatRemoved, .maintenance, .uninstall,
                                           .update, .cloudFreed, .other, .checkup, .startupItems]
        for kind in kinds {
            XCTAssertFalse(kind.activityTitle.isEmpty)
            XCTAssertFalse(kind.activitySymbol.isEmpty)
        }
    }
}
