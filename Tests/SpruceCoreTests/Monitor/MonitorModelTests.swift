import Foundation
import XCTest
@testable import SpruceCore

final class MonitorProcessTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testCPUPercentFromCumulativeTime() throws {
        var tracker = MonitorProcessTracker()
        let first = tracker.update([
            MonitorProcessReading(pid: 10, name: "Editor", startTime: 1, cpuTimeNanos: 1_000_000_000, footprint: 500),
            MonitorProcessReading(pid: 20, name: "Player", startTime: 2, cpuTimeNanos: 0, footprint: 900),
        ], at: t0)
        XCTAssertEqual(first.map(\.cpuPercent), [0, 0], "first sample has no baseline")

        let second = tracker.update([
            MonitorProcessReading(pid: 10, name: "Editor", startTime: 1, cpuTimeNanos: 4_000_000_000, footprint: 600),
            MonitorProcessReading(pid: 20, name: "Player", startTime: 2, cpuTimeNanos: 200_000_000, footprint: 900),
        ], at: t0.addingTimeInterval(2))
        let editor = try XCTUnwrap(second.first { $0.pid == 10 })
        XCTAssertEqual(editor.cpuPercent, 150, accuracy: 1e-9, "3 s of CPU in 2 s = 150 % of one core")
        XCTAssertEqual(editor.memory, 600)
        let player = try XCTUnwrap(second.first { $0.pid == 20 })
        XCTAssertEqual(player.cpuPercent, 10, accuracy: 1e-9)
    }

    func testReusedPIDStartsFresh() throws {
        var tracker = MonitorProcessTracker()
        _ = tracker.update([MonitorProcessReading(pid: 7, name: "Old", startTime: 100, cpuTimeNanos: 9_000_000_000, footprint: 1)], at: t0)
        let next = tracker.update([MonitorProcessReading(pid: 7, name: "New", startTime: 200, cpuTimeNanos: 50_000_000_000, footprint: 1)],
                                  at: t0.addingTimeInterval(2))
        XCTAssertEqual(try XCTUnwrap(next.first).cpuPercent, 0)
        XCTAssertEqual(try XCTUnwrap(next.first).name, "New")
    }

    func testHelpersFoldIntoTheirApp() throws {
        var tracker = MonitorProcessTracker()
        let readings = [
            MonitorProcessReading(pid: 100, name: "Browser", startTime: 1, cpuTimeNanos: 0, footprint: 300),
            MonitorProcessReading(pid: 101, name: "Browser Helper", startTime: 1, cpuTimeNanos: 0, footprint: 200, groupPID: 100),
            MonitorProcessReading(pid: 102, name: "Browser Helper (GPU)", startTime: 1, cpuTimeNanos: 0, footprint: 100, groupPID: 100),
            MonitorProcessReading(pid: 300, name: "Orphan Helper", startTime: 1, cpuTimeNanos: 0, footprint: 50, groupPID: 299),
        ]
        _ = tracker.update(readings, at: t0)
        var later = readings
        later[1].cpuTimeNanos = 1_000_000_000
        later[2].cpuTimeNanos = 500_000_000
        let usage = tracker.update(later, at: t0.addingTimeInterval(1))
        XCTAssertEqual(usage.count, 2)
        let browser = try XCTUnwrap(usage.first { $0.pid == 100 })
        XCTAssertEqual(browser.name, "Browser")
        XCTAssertEqual(browser.processCount, 3)
        XCTAssertEqual(browser.memory, 600)
        XCTAssertEqual(browser.cpuPercent, 150, accuracy: 1e-9)
        let orphan = try XCTUnwrap(usage.first { $0.pid == 299 })
        XCTAssertEqual(orphan.name, "Orphan Helper", "group leader not visible: use the member's name")
    }

    func testRanking() {
        let usages = [
            MonitorProcessUsage(pid: 1, name: "B", cpuPercent: 30, memory: 100),
            MonitorProcessUsage(pid: 2, name: "A", cpuPercent: 30, memory: 900),
            MonitorProcessUsage(pid: 3, name: "C", cpuPercent: 0.05, memory: 500),
            MonitorProcessUsage(pid: 4, name: "D", cpuPercent: 80, memory: 0),
        ]
        XCTAssertEqual(MonitorProcessRanking.top(usages, by: .cpu, limit: 3).map(\.name), ["D", "A", "B"])
        XCTAssertEqual(MonitorProcessRanking.top(usages, by: .memory, limit: 2).map(\.name), ["A", "C"])
        XCTAssertEqual(MonitorProcessRanking.top(usages, by: .memory, limit: 0), [])
    }
}

final class MonitorModelTests: XCTestCase {
    func testPowerStatusText() {
        XCTAssertEqual(MonitorPowerInfo(kind: .internalBattery, name: "Battery", level: 0.5, isCharging: true,
                                        minutesToFull: 72).statusText, "Charging · 1:12 to full")
        XCTAssertEqual(MonitorPowerInfo(kind: .internalBattery, name: "Battery", level: 0.6, onExternalPower: false,
                                        minutesToEmpty: 220).statusText, "On battery · 3:40 left")
        XCTAssertEqual(MonitorPowerInfo(kind: .internalBattery, name: "Battery", level: 0.6, onExternalPower: false,
                                        minutesToEmpty: -1).statusText, "On battery · calculating…")
        XCTAssertEqual(MonitorPowerInfo(kind: .internalBattery, name: "Battery", level: 1, isCharged: true).statusText, "Charged")
        XCTAssertEqual(MonitorPowerInfo(kind: .ups, name: "Back-UPS", level: 0.9).statusText, "On mains power")
        XCTAssertEqual(MonitorPowerInfo(kind: .ups, name: "Back-UPS", level: 0.9, onExternalPower: false,
                                        minutesToEmpty: 25).statusText, "On UPS battery · 0:25 left")
        XCTAssertEqual(MonitorPowerInfo(kind: .ups, name: "UPS").title, "UPS")
        XCTAssertTrue(MonitorPowerInfo(kind: .internalBattery, name: "B", health: 0.79).needsService)
        XCTAssertFalse(MonitorPowerInfo(kind: .internalBattery, name: "B", health: 0.8).needsService)
    }

    func testDeviceSymbolsAndOrdering() {
        XCTAssertEqual(MonitorDevice.symbol(for: "Magic Keyboard with Touch ID"), "keyboard")
        XCTAssertEqual(MonitorDevice.symbol(for: "Magic Mouse"), "computermouse")
        XCTAssertEqual(MonitorDevice.symbol(for: "Magic Trackpad"), "hand.point.up.left")
        XCTAssertEqual(MonitorDevice.symbol(for: "Michael's AirPods Pro"), "airpods")
        XCTAssertEqual(MonitorDevice.symbol(for: "Thing"), "dot.radiowaves.left.and.right")

        let devices = [
            MonitorDevice(id: "k", name: "Magic Keyboard", batteryPercent: 64),
            MonitorDevice(id: "m", name: "Magic Mouse", batteryPercent: 12),
            MonitorDevice(id: "t", name: "Magic Trackpad", batteryPercent: 5),
            MonitorDevice(id: "k", name: "Magic Keyboard", batteryPercent: 64),
            MonitorDevice(id: "a", name: "AirPods", batteryPercent: 140),
        ]
        let arranged = MonitorDevice.arranged(devices)
        XCTAssertEqual(arranged.map(\.id), ["t", "m", "a", "k"])
        XCTAssertEqual(arranged[2].batteryPercent, 100, "clamped")
        XCTAssertTrue(arranged[0].isLowBattery)
        XCTAssertFalse(MonitorDevice(id: "x", name: "X", batteryPercent: nil).isLowBattery)
    }

    func testTrashStatusBytes() {
        XCTAssertNil(MonitorTrashStatus.measuring.bytes)
        XCTAssertNil(MonitorTrashStatus.needsAccess.bytes)
        XCTAssertEqual(MonitorTrashStatus.measured(42).bytes, 42)
    }

    func testFormatting() {
        XCTAssertEqual(MonitorFormat.rate(0), "0 B/s")
        XCTAssertEqual(MonitorFormat.rate(512), "512 B/s")
        XCTAssertEqual(MonitorFormat.rate(84_300), "84 KB/s")
        XCTAssertEqual(MonitorFormat.rate(1_234_567), "1.2 MB/s")
        XCTAssertEqual(MonitorFormat.rate(999_700), "1 MB/s")
        XCTAssertEqual(MonitorFormat.rate(-5), "0 B/s")
        XCTAssertEqual(MonitorFormat.percent(0.423), "42%")
        XCTAssertEqual(MonitorFormat.percent(1.7), "100%")
        XCTAssertEqual(MonitorFormat.cpuPercent(0.44), "0.4%")
        XCTAssertEqual(MonitorFormat.cpuPercent(3), "3%")
        XCTAssertEqual(MonitorFormat.cpuPercent(140.4), "140%")
        XCTAssertEqual(MonitorFormat.uptime(45), "45 s")
        XCTAssertEqual(MonitorFormat.uptime(12 * 60 + 5), "12 min")
        XCTAssertEqual(MonitorFormat.uptime(3 * 3600 + 12 * 60), "3 h 12 min")
        XCTAssertEqual(MonitorFormat.uptime(2 * 3600), "2 h")
        XCTAssertEqual(MonitorFormat.uptime(6 * 86_400 + 4 * 3600 + 59), "6 d 4 h")
        XCTAssertEqual(MonitorFormat.hoursMinutes(185), "3:05")
        XCTAssertEqual(MonitorFormat.pressure(.warning), "Elevated")
        XCTAssertEqual(MonitorFormat.thermal("serious"), "Hot")
        XCTAssertEqual(MonitorFormat.thermal("nominal"), "Cool")
    }
}

final class MonitorHealthTests: XCTestCase {
    private func healthySnapshot() -> SystemSnapshot {
        var s = SystemSnapshot()
        s.diskTotal = 500_000_000_000
        s.diskAvailable = 200_000_000_000
        s.memoryTotal = 16_000_000_000
        s.memoryUsed = 8_000_000_000
        s.memoryPressure = .normal
        s.thermalState = "nominal"
        return s
    }

    func testHealthyMacScoresFull() {
        let health = MonitorHealth.assess(healthySnapshot(), context: MonitorHealthContext())
        XCTAssertEqual(health.score, 100)
        XCTAssertEqual(health.status, .good)
        XCTAssertTrue(health.issues.isEmpty)
        XCTAssertEqual(health.headline, "Your Mac is in good shape")
        XCTAssertFalse(MonitorHealth.pending.isRated)
        XCTAssertEqual(MonitorHealth.pending.headline, "Checking your Mac…")
    }

    func testLowDiskNeedsAttentionAndCriticalDiskIsCritical() {
        var s = healthySnapshot()
        s.diskAvailable = 30_000_000_000            // 6 % of 500 GB
        var health = MonitorHealth.assess(s, context: MonitorHealthContext(lowDiskThresholdPercent: 10))
        XCTAssertEqual(health.status, .attention)
        XCTAssertEqual(health.issues.map(\.kind), [.disk])
        XCTAssertEqual(health.score, 80)
        XCTAssertEqual(health.headline, "1 thing needs attention")

        s.diskAvailable = 4_000_000_000
        health = MonitorHealth.assess(s, context: MonitorHealthContext(lowDiskThresholdPercent: 10))
        XCTAssertEqual(health.status, .critical)
        XCTAssertEqual(health.headline, "Startup disk is almost full")
    }

    func testIssuesAreOrderedBySeverityThenPenalty() {
        var s = healthySnapshot()
        s.memoryPressure = .critical
        s.swapUsed = 9_000_000_000
        s.thermalState = "serious"
        s.trashSize = 5_000_000_000
        s.batteryHealth = 0.7
        let health = MonitorHealth.assess(s, context: MonitorHealthContext(trashThreshold: 2_000_000_000, trashKnown: true,
                                                                           sustainedHighCPU: true))
        XCTAssertEqual(health.issues.map(\.kind), [.memory, .thermal, .cpu, .battery, .swap, .trash])
        XCTAssertEqual(health.status, .critical)
        XCTAssertEqual(health.score, 100 - 25 - 15 - 10 - 10 - 5 - 5)
    }

    func testUnknownTrashAndDisabledThresholdAreIgnored() {
        var s = healthySnapshot()
        s.trashSize = 50_000_000_000
        XCTAssertTrue(MonitorHealth.assess(s, context: MonitorHealthContext(trashKnown: false)).issues.isEmpty)
        XCTAssertTrue(MonitorHealth.assess(s, context: MonitorHealthContext(trashThreshold: 0, trashKnown: true)).issues.isEmpty)
    }

    func testLowBatteryOnlyWhenNotCharging() {
        var s = healthySnapshot()
        s.batteryLevel = 0.08
        s.isCharging = false
        XCTAssertEqual(MonitorHealth.assess(s, context: MonitorHealthContext()).issues.map(\.kind), [.battery])
        s.isCharging = true
        XCTAssertTrue(MonitorHealth.assess(s, context: MonitorHealthContext()).issues.isEmpty)
    }
}
