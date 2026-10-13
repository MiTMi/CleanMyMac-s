import XCTest
@testable import SpruceCore

final class ActivityAdviceTests: XCTestCase {
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

    /// Checkup 3 days ago, nothing cleaned → only the "nothing cleaned" nudge (−5).
    private func cleanupNudgeHistory() -> ActivityHistory {
        ActivityHistory(entries: [ActivityEntry(date: day(-3), module: .checkup, kind: .scan, summary: "scan")])
    }

    private func assess(history: ActivityHistory, snapshot: SystemSnapshot? = nil, hasFullDiskAccess: Bool = true,
                        realtime: Bool = true, at date: Date? = nil, advice: ActivityAdviceState = ActivityAdviceState()) -> ActivityHealthReport {
        ActivityHealth.assess(ActivityHealthInput(snapshot: snapshot ?? healthySnapshot(), history: history,
                                                  hasFullDiskAccess: hasFullDiskAccess, realtimeProtectionEnabled: realtime,
                                                  now: date ?? now, advice: advice))
    }

    func testDefaultAdviceHidesNothing() {
        let report = assess(history: cleanupNudgeHistory())
        XCTAssertEqual(report.recommendations.map(\.id), ["cleanup.stale"])
        XCTAssertTrue(report.hiddenRecommendations.isEmpty)
        XCTAssertTrue(report.showsSuggestions)
    }

    func testSnoozeHidesTheCardButKeepsTheScore() throws {
        let base = assess(history: cleanupNudgeHistory())
        let card = try XCTUnwrap(base.recommendations.first)
        XCTAssertEqual(card.snoozeDays, 7)
        XCTAssertEqual(card.snoozeTitle, "Snooze for a Week")

        var advice = ActivityAdviceState()
        advice.snooze(card, now: now)
        let snoozed = assess(history: cleanupNudgeHistory(), advice: advice)
        XCTAssertTrue(snoozed.recommendations.isEmpty)
        XCTAssertEqual(snoozed.hiddenRecommendations.map(\.id), ["cleanup.stale"])
        XCTAssertEqual(snoozed.score, base.score)
        XCTAssertEqual(snoozed.score, 95)
        XCTAssertEqual(snoozed.headline, "Nothing new to suggest")
        XCTAssertEqual(snoozed.allRecommendations.map(\.id), ["cleanup.stale"])

        // A week later the snooze is over.
        let later = assess(history: cleanupNudgeHistory(), at: day(7.01), advice: advice)
        XCTAssertEqual(later.recommendations.map(\.id), ["cleanup.stale"])
        XCTAssertTrue(advice.pruned(now: day(7.01)).holds.isEmpty)
        XCTAssertEqual(advice.pruned(now: day(6)).holds.count, 1)
    }

    func testThreatsCanNeverBeHidden() throws {
        var history = cleanupNudgeHistory()
        history.append(ActivityEntry(date: day(-1), module: .protection, kind: .malwareScan, count: 1, summary: ""))
        let report = assess(history: history)
        let threat = try XCTUnwrap(report.recommendations.first { $0.id == "threat.active" })
        XCTAssertTrue(threat.isPinned)
        XCTAssertFalse(threat.canSnooze)
        XCTAssertFalse(threat.canDismiss)
        XCTAssertNil(threat.snoozeDays)

        var advice = ActivityAdviceState()
        advice.snooze(threat, now: now)
        advice.dismiss(threat, now: now)
        XCTAssertTrue(advice.holds.isEmpty)

        // Even a hand-edited file can't hide it, nor can turning suggestions off.
        advice.holds["threat.active"] = ActivityAdviceHold(until: nil, severity: .critical, date: now)
        advice.showSuggestions = false
        let forced = assess(history: history, advice: advice)
        XCTAssertEqual(forced.recommendations.first?.id, "threat.active")
        XCTAssertFalse(forced.hiddenRecommendations.contains { $0.id == "threat.active" })
    }

    func testDismissedCardReturnsWhenMoreUrgent() throws {
        // Checkup 20 days ago → "scan.stale" (info).
        let staleHistory = ActivityHistory(entries: [
            ActivityEntry(date: day(-20), module: .checkup, kind: .checkup, summary: "run"),
            ActivityEntry(date: day(-20), module: .cleanup, kind: .clean, bytes: 1, count: 1, summary: ""),
        ])
        let stale = try XCTUnwrap(assess(history: staleHistory).recommendations.first { $0.id == "scan.stale" })
        XCTAssertEqual(stale.adviceKey, "scan")
        XCTAssertTrue(stale.canDismiss)

        var advice = ActivityAdviceState()
        advice.dismiss(stale, now: now)
        XCTAssertEqual(advice.holds["scan"]?.isPermanent, true)
        let hidden = assess(history: staleHistory, at: day(9), advice: advice)
        XCTAssertFalse(hidden.recommendations.contains { $0.id == "scan.stale" })
        XCTAssertEqual(hidden.level, .good)          // the cap still applies

        // Ten more days without a Checkup: the overdue reminder is a warning → shown again.
        let overdue = assess(history: staleHistory, at: day(11), advice: advice)
        let overdueCard = try XCTUnwrap(overdue.recommendations.first { $0.id == "scan.overdue" })
        XCTAssertEqual(overdueCard.severity, .warning)

        // Turning that off too keeps it hidden, and "show again" brings it back.
        advice.dismiss(overdueCard, now: day(11))
        XCTAssertFalse(assess(history: staleHistory, at: day(40), advice: advice).recommendations.contains { $0.adviceKey == "scan" })
        advice.restore(overdueCard)
        XCTAssertTrue(assess(history: staleHistory, at: day(40), advice: advice).recommendations.contains { $0.id == "scan.overdue" })
    }

    func testCriticalConditionsCanBeSnoozedButNotTurnedOff() throws {
        var snap = healthySnapshot()
        snap.diskAvailable = 2_000_000_000       // under the 3 GB floor → critical
        let history = ActivityHistory(entries: [
            ActivityEntry(date: day(-2), module: .checkup, kind: .scan, summary: "scan"),
            ActivityEntry(date: day(-2), module: .cleanup, kind: .clean, bytes: 1, count: 1, summary: ""),
        ])
        let disk = try XCTUnwrap(assess(history: history, snapshot: snap).recommendations.first)
        XCTAssertEqual(disk.id, "system.disk")
        XCTAssertEqual(disk.severity, .critical)
        XCTAssertFalse(disk.canDismiss)
        XCTAssertTrue(disk.canSnooze)
        XCTAssertEqual(disk.snoozeDays, 1)

        var advice = ActivityAdviceState()
        advice.dismiss(disk, now: now)
        XCTAssertTrue(advice.holds.isEmpty)
        advice.snooze(disk, now: now)
        XCTAssertFalse(assess(history: history, snapshot: snap, at: day(0.5), advice: advice).recommendations.contains { $0.id == "system.disk" })
        XCTAssertTrue(assess(history: history, snapshot: snap, at: day(1.01), advice: advice).recommendations.contains { $0.id == "system.disk" })

        // A permanent hold on a critical card (hand-edited file) is ignored.
        advice.holds["system.disk"] = ActivityAdviceHold(until: nil, severity: .critical, date: now)
        XCTAssertTrue(assess(history: history, snapshot: snap, advice: advice).recommendations.contains { $0.id == "system.disk" })
    }

    func testSnoozedWarningComesBackWhenCritical() throws {
        let history = ActivityHistory(entries: [
            ActivityEntry(date: day(-2), module: .checkup, kind: .scan, summary: "scan"),
            ActivityEntry(date: day(-2), module: .cleanup, kind: .clean, bytes: 1, count: 1, summary: ""),
        ])
        var low = healthySnapshot()
        low.diskAvailable = 80_000_000_000          // 8 % → warning
        let warning = try XCTUnwrap(assess(history: history, snapshot: low).recommendations.first)
        XCTAssertEqual(warning.severity, .warning)
        var advice = ActivityAdviceState()
        advice.dismiss(warning, now: now)
        XCTAssertTrue(assess(history: history, snapshot: low, advice: advice).recommendations.isEmpty)

        var full = low
        full.diskAvailable = 1_000_000_000
        let report = assess(history: history, snapshot: full, advice: advice)
        XCTAssertEqual(report.recommendations.first?.id, "system.disk")
        XCTAssertEqual(report.recommendations.first?.severity, .critical)
    }

    func testSuggestionsOffListsOnlyCriticalProblems() {
        var snap = healthySnapshot()
        snap.thermalState = "critical"
        let advice = ActivityAdviceState(showSuggestions: false)
        let report = assess(history: ActivityHistory(), snapshot: snap, hasFullDiskAccess: false, realtime: false, advice: advice)
        XCTAssertFalse(report.showsSuggestions)
        XCTAssertEqual(report.recommendations.map(\.id), ["system.thermal"])
        XCTAssertEqual(Set(report.hiddenRecommendations.map(\.id)), ["fda.missing", "scan.never", "protection.off"])
        let shown = assess(history: ActivityHistory(), snapshot: snap, hasFullDiskAccess: false, realtime: false)
        XCTAssertEqual(report.score, shown.score)
        XCTAssertEqual(report.allRecommendations.map(\.id), shown.recommendations.map(\.id))
    }

    func testApplyingAdviceToAPlainReportMatchesAssessingWithIt() throws {
        // A report made without advice (like AppModel.healthReport) filtered for display.
        var snap = healthySnapshot()
        snap.memoryPressure = .warning
        let history = cleanupNudgeHistory()
        let plain = assess(history: history, snapshot: snap, hasFullDiskAccess: false, realtime: false)
        XCTAssertEqual(plain.recommendations.map(\.id), ["system.memory", "fda.missing", "cleanup.stale", "protection.off"])

        var advice = ActivityAdviceState()
        advice.snooze(try XCTUnwrap(plain.recommendations.first { $0.id == "system.memory" }), now: now)
        advice.dismiss(try XCTUnwrap(plain.recommendations.first { $0.id == "protection.off" }), now: now)

        let applied = plain.applying(advice, now: now)
        let assessed = assess(history: history, snapshot: snap, hasFullDiskAccess: false, realtime: false, advice: advice)
        XCTAssertEqual(applied, assessed)
        XCTAssertEqual(applied.recommendations.map(\.id), ["fda.missing", "cleanup.stale"])
        XCTAssertEqual(applied.hiddenRecommendations.map(\.id), ["system.memory", "protection.off"])
        XCTAssertEqual(applied.score, plain.score)
        XCTAssertEqual(applied.level, plain.level)

        // Idempotent, and clearing the advice brings every card back.
        XCTAssertEqual(applied.applying(advice, now: now), applied)
        let cleared = applied.applying(ActivityAdviceState(), now: now)
        XCTAssertEqual(Set(cleared.recommendations.map(\.id)), Set(plain.recommendations.map(\.id)))
        XCTAssertTrue(cleared.hiddenRecommendations.isEmpty)

        // The memory snooze lasts a day.
        let tomorrow = plain.applying(advice, now: day(1.01))
        XCTAssertTrue(tomorrow.recommendations.contains { $0.id == "system.memory" })
        XCTAssertEqual(tomorrow.hiddenRecommendations.map(\.id), ["protection.off"])
    }

    func testRestoreAllAndPerCardSnoozeLengths() {
        let fda = ActivityRecommendation(id: "fda.missing", title: "", detail: "", severity: .warning, symbol: "",
                                         actionTitle: "", action: .grantFullDiskAccess, penalty: 10)
        let battery = ActivityRecommendation(id: "system.battery", title: "", detail: "", severity: .warning, symbol: "",
                                             actionTitle: "", action: .none, penalty: 10, isSystem: true)
        XCTAssertEqual(fda.snoozeDays, 3)
        XCTAssertEqual(fda.snoozeTitle, "Snooze for 3 Days")
        XCTAssertEqual(battery.snoozeDays, 30)
        var advice = ActivityAdviceState()
        advice.snooze(fda, now: now)
        advice.dismiss(battery, now: now)
        XCTAssertEqual(advice.holds["fda.missing"]?.until, day(3))
        XCTAssertEqual(advice.activeHolds(now: day(4)).keys.sorted(), ["system.battery"])
        advice.restoreAll()
        XCTAssertTrue(advice.holds.isEmpty)
    }

    func testStateRoundTripsAndToleratesMissingKeys() throws {
        var advice = ActivityAdviceState(showSuggestions: false)
        advice.holds["scan"] = ActivityAdviceHold(until: day(7), severity: .info, date: now)
        advice.holds["protection.off"] = ActivityAdviceHold(until: nil, severity: .info, date: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ActivityAdviceState.self, from: encoder.encode(advice))
        XCTAssertEqual(decoded, advice)

        let empty = try decoder.decode(ActivityAdviceState.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, ActivityAdviceState())
        XCTAssertTrue(empty.showSuggestions)

        // Through the app's store, in a temporary folder.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("advice-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore<ActivityAdviceState>(url: dir.appendingPathComponent("advisor.json"))
        try store.save(advice)
        XCTAssertEqual(store.load(), advice)
    }

    func testExplanationNamesPenaltyCapAndHiding() {
        let fda = ActivityHealth.assess(ActivityHealthInput(snapshot: healthySnapshot(), history: cleanupNudgeHistory(),
                                                            hasFullDiskAccess: false, now: now))
            .recommendations.first { $0.id == "fda.missing" }
        let text = fda?.explanation.joined(separator: " ") ?? ""
        XCTAssertTrue(text.contains("10 points"))
        XCTAssertTrue(text.contains("can't go above Fair"))
        XCTAssertTrue(text.contains("Snoozing hides it for 3 days"))
        XCTAssertTrue(text.contains("Don't Suggest This Again"))

        let threat = ActivityRecommendation(id: "threat.active", title: "", detail: "", severity: .critical, symbol: "",
                                            actionTitle: "Review", action: .open(.protection, tool: "protection.malware"),
                                            penalty: 35)
        XCTAssertTrue(threat.explanation.joined().contains("can't be snoozed"))

        let disk = ActivityHealth.recommendation(for: ActivitySystemIssue(kind: "disk", isCritical: true, title: "Full",
                                                                          detail: "", penalty: 40))
        let diskText = disk.explanation.joined(separator: " ")
        XCTAssertTrue(diskText.contains("measures this live"))
        XCTAssertTrue(diskText.contains("can be snoozed but not turned off"))
        XCTAssertFalse(diskText.contains("Don't Suggest This Again"))
    }
}
