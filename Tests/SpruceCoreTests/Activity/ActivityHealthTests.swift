import XCTest
@testable import SpruceCore

final class ActivityHealthTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86_400) }

    private func healthySnapshot() -> SystemSnapshot {
        var s = SystemSnapshot()
        s.diskTotal = 1_000_000_000_000
        s.diskAvailable = 500_000_000_000
        s.memoryTotal = 16_000_000_000
        s.memoryUsed = 8_000_000_000
        s.memoryPressure = .normal
        s.thermalState = "nominal"
        return s
    }

    private func freshHistory() -> ActivityHistory {
        ActivityHistory(entries: [
            ActivityEntry(date: day(-2), module: .checkup, kind: .scan, bytes: 1_000, count: 3, summary: "Checkup"),
            ActivityEntry(date: day(-2), module: .cleanup, kind: .clean, bytes: 5_000_000, count: 40, summary: "Cleaned"),
        ])
    }

    func testHealthyMacIsExcellent() {
        let report = ActivityHealth.assess(ActivityHealthInput(snapshot: healthySnapshot(), history: freshHistory(), now: now))
        XCTAssertEqual(report.score, 100)
        XCTAssertEqual(report.level, .excellent)
        XCTAssertTrue(report.recommendations.isEmpty)
        XCTAssertTrue(report.isRated)
        XCTAssertEqual(report.daysSinceCheckup, 2)
        XCTAssertEqual(report.daysSinceCleanup, 2)
    }

    func testLevelBands() {
        XCTAssertEqual(ActivityHealthLevel.level(for: 100), .excellent)
        XCTAssertEqual(ActivityHealthLevel.level(for: 90), .excellent)
        XCTAssertEqual(ActivityHealthLevel.level(for: 89), .good)
        XCTAssertEqual(ActivityHealthLevel.level(for: 75), .good)
        XCTAssertEqual(ActivityHealthLevel.level(for: 74), .fair)
        XCTAssertEqual(ActivityHealthLevel.level(for: 60), .fair)
        XCTAssertEqual(ActivityHealthLevel.level(for: 59), .requiresAttention)
        XCTAssertEqual(ActivityHealthLevel.level(for: 40), .requiresAttention)
        XCTAssertEqual(ActivityHealthLevel.level(for: 39), .critical)
        XCTAssertEqual(ActivityHealthLevel.level(for: 0), .critical)
        for level in ActivityHealthLevel.allCases {
            XCTAssertEqual(ActivityHealthLevel.level(for: level.floor), level)
            XCTAssertEqual(ActivityHealthLevel.level(for: level.ceiling), level)
        }
    }

    func testMissingFullDiskAccessCapsAtFair() {
        let report = ActivityHealth.assess(ActivityHealthInput(snapshot: healthySnapshot(), history: freshHistory(),
                                                               hasFullDiskAccess: false, now: now))
        XCTAssertLessThanOrEqual(report.score, 74)
        XCTAssertEqual(report.level, .fair)
        let rec = report.recommendations.first { $0.id == "fda.missing" }
        XCTAssertEqual(rec?.action, .grantFullDiskAccess)
    }

    func testUnresolvedThreatIsCritical() {
        var history = freshHistory()
        history.append(ActivityEntry(date: day(-1), module: .protection, kind: .malwareScan, count: 2, summary: "2 threats"))
        let report = ActivityHealth.assess(ActivityHealthInput(snapshot: healthySnapshot(), history: history, now: now))
        XCTAssertEqual(report.unresolvedThreats, 2)
        XCTAssertEqual(report.level, .critical)
        XCTAssertEqual(report.recommendations.first?.id, "threat.active")
        XCTAssertEqual(report.recommendations.first?.targetModule, .protection)
        XCTAssertEqual(report.recommendations.first?.toolID, "protection.malware")
        XCTAssertEqual(report.headline, "2 threats need removal")
    }

    func testRemovedThreatsClearTheCap() {
        var history = freshHistory()
        history.append(ActivityEntry(date: day(-1), module: .protection, kind: .malwareScan, count: 2, summary: ""))
        history.append(ActivityEntry(date: day(-0.5), module: .protection, kind: .threatRemoved, count: 2, summary: ""))
        XCTAssertEqual(ActivityHealth.unresolvedThreats(in: history), 0)
        // A newer clean scan resets the count, too.
        var other = freshHistory()
        other.append(ActivityEntry(date: day(-3), module: .protection, kind: .malwareScan, count: 4, summary: ""))
        other.append(ActivityEntry(date: day(-1), module: .protection, kind: .malwareScan, count: 0, summary: ""))
        XCTAssertEqual(ActivityHealth.unresolvedThreats(in: other), 0)
        // Removals before the scan don't count.
        var older = freshHistory()
        older.append(ActivityEntry(date: day(-3), module: .protection, kind: .threatRemoved, count: 5, summary: ""))
        older.append(ActivityEntry(date: day(-1), module: .protection, kind: .malwareScan, count: 1, summary: ""))
        XCTAssertEqual(ActivityHealth.unresolvedThreats(in: older), 1)
    }

    func testCheckupRecencyCaps() {
        let never = ActivityHealth.assess(ActivityHealthInput(snapshot: healthySnapshot(), history: ActivityHistory(), now: now))
        XCTAssertLessThanOrEqual(never.score, 74)
        XCTAssertTrue(never.recommendations.contains { $0.id == "scan.never" && $0.action == .open(.checkup, tool: "checkup.scan") })
        XCTAssertNil(never.daysSinceCheckup)

        let stale = ActivityHealthInput(snapshot: healthySnapshot(), history: ActivityHistory(entries: [
            ActivityEntry(date: day(-20), module: .checkup, kind: .checkup, summary: "run"),
            ActivityEntry(date: day(-20), module: .cleanup, kind: .clean, bytes: 1, count: 1, summary: ""),
        ]), now: now)
        let staleReport = ActivityHealth.assess(stale)
        XCTAssertEqual(staleReport.level, .good)
        XCTAssertTrue(staleReport.recommendations.contains { $0.id == "scan.stale" })

        let overdue = ActivityHealthInput(snapshot: healthySnapshot(), history: ActivityHistory(entries: [
            ActivityEntry(date: day(-45), module: .checkup, kind: .scan, summary: "scan"),
        ]), now: now)
        let overdueReport = ActivityHealth.assess(overdue)
        XCTAssertLessThanOrEqual(overdueReport.score, 74)
        XCTAssertTrue(overdueReport.recommendations.contains { $0.id == "scan.overdue" })
    }

    func testCleanupSuggestionOnlyWhenCheckupIsCurrent() {
        let history = ActivityHistory(entries: [
            ActivityEntry(date: day(-3), module: .checkup, kind: .scan, summary: "scan"),
        ])
        let report = ActivityHealth.assess(ActivityHealthInput(snapshot: healthySnapshot(), history: history, now: now))
        XCTAssertTrue(report.recommendations.contains { $0.id == "cleanup.stale" })
        XCTAssertEqual(report.score, 95)
        let never = ActivityHealth.assess(ActivityHealthInput(snapshot: healthySnapshot(), history: ActivityHistory(), now: now))
        XCTAssertFalse(never.recommendations.contains { $0.id == "cleanup.stale" })
    }

    func testSnapshotDerivedSystemIssues() {
        var snap = healthySnapshot()
        snap.diskAvailable = 2_000_000_000          // under the 3 GB floor → critical
        snap.memoryPressure = .warning
        snap.thermalState = "serious"
        snap.swapUsed = 9_000_000_000
        let issues = ActivityHealth.systemIssues(from: snap)
        XCTAssertEqual(issues.map(\.kind), ["disk", "memory", "swap", "thermal"])
        XCTAssertTrue(issues[0].isCritical)
        let report = ActivityHealth.assess(ActivityHealthInput(snapshot: snap, history: freshHistory(), now: now))
        XCTAssertEqual(report.systemScore, 100 - 40 - 10 - 5 - 15)
        XCTAssertEqual(report.score, 30)
        XCTAssertEqual(report.level, .critical)
        XCTAssertEqual(report.recommendations.first?.id, "system.disk")
        XCTAssertEqual(report.recommendations.first?.action, .open(.cleanup, tool: "cleanup.systemJunk"))
    }

    func testLowDiskThresholdAndBattery() {
        var snap = healthySnapshot()
        snap.diskAvailable = 80_000_000_000        // 8 % of 1 TB
        snap.batteryHealth = 0.7
        let issues = ActivityHealth.systemIssues(from: snap, lowDiskThresholdPercent: 10)
        XCTAssertEqual(issues.map(\.kind), ["disk", "battery"])
        XCTAssertFalse(issues[0].isCritical)
        XCTAssertEqual(issues[0].penalty, 20)
        XCTAssertTrue(ActivityHealth.systemIssues(from: snap, lowDiskThresholdPercent: 5).allSatisfy { $0.kind != "disk" })
        // Desktop Macs have no battery: nothing is reported for it.
        snap.batteryHealth = nil
        XCTAssertFalse(ActivityHealth.systemIssues(from: snap).contains { $0.kind == "battery" })
    }

    func testLiveIssuesOverrideSnapshot() {
        var snap = healthySnapshot()
        snap.diskAvailable = 1_000_000_000
        let live = [ActivitySystemIssue(kind: "memory", isCritical: false, title: "Memory pressure is elevated",
                                        detail: "", penalty: 10),
                    ActivitySystemIssue(kind: "trash", isCritical: false, title: "Trash is taking up space",
                                        detail: "3 GB", penalty: 5)]
        let report = ActivityHealth.assess(ActivityHealthInput(snapshot: snap, liveIssues: live, history: freshHistory(), now: now))
        XCTAssertEqual(report.systemScore, 85)
        XCTAssertEqual(report.score, 85)
        XCTAssertEqual(report.recommendations.map(\.id), ["system.memory", "system.trash"])
        XCTAssertEqual(report.recommendations[0].action, .open(.toolbox, tool: "toolbox.freeRAM"))
        XCTAssertEqual(report.recommendations[1].action, .open(.toolbox, tool: "toolbox.emptyTrash"))
    }

    func testNotRatedWithoutSystemData() {
        let report = ActivityHealth.assess(ActivityHealthInput(history: freshHistory(), now: now))
        XCTAssertFalse(report.isRated)
        XCTAssertEqual(report.score, 100)
    }

    func testOrderingPutsCriticalFirst() {
        var history = ActivityHistory()
        history.append(ActivityEntry(date: day(-1), module: .protection, kind: .malwareScan, count: 1, summary: ""))
        let report = ActivityHealth.assess(ActivityHealthInput(snapshot: healthySnapshot(), history: history,
                                                               hasFullDiskAccess: false, realtimeProtectionEnabled: false,
                                                               now: now))
        let severities = report.recommendations.map(\.severity)
        XCTAssertEqual(severities, severities.sorted(by: >))
        XCTAssertEqual(report.recommendations.first?.id, "threat.active")
        XCTAssertTrue(report.recommendations.contains { $0.id == "protection.off" })
        XCTAssertEqual(report.level, .critical)
        XCTAssertGreaterThanOrEqual(report.score, 0)
    }
}
