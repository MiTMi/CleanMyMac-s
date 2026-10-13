import Foundation
import XCTest
@testable import SpruceCore

final class MonitorAlertEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func snapshot(diskFreePercent: Double = 50, pressure: SystemSnapshot.MemoryPressure = .normal,
                          trash: Int64 = 0) -> SystemSnapshot {
        var s = SystemSnapshot()
        s.diskTotal = 1_000_000_000_000
        s.diskAvailable = Int64(diskFreePercent / 100 * 1_000_000_000_000)
        s.memoryTotal = 16_000_000_000
        s.memoryPressure = pressure
        s.swapUsed = 2_000_000_000
        s.trashSize = trash
        return s
    }

    private func sample(_ offset: TimeInterval, _ snap: SystemSnapshot, trashKnown: Bool = true,
                        processes: [MonitorProcessUsage] = []) -> MonitorAlertSample {
        MonitorAlertSample(date: t0.addingTimeInterval(offset), snapshot: snap, trashKnown: trashKnown, processes: processes)
    }

    func testLowDiskNeedsTwoSamplesThenRepeatsDaily() {
        var engine = MonitorAlertEngine()
        let settings = MonitorAlertSettings(lowDiskPercent: 10)
        XCTAssertTrue(engine.evaluate(sample(0, snapshot(diskFreePercent: 5)), settings: settings).isEmpty, "first dip")
        let fired = engine.evaluate(sample(2, snapshot(diskFreePercent: 5)), settings: settings)
        XCTAssertEqual(fired.map(\.kind), [.lowDisk])
        XCTAssertEqual(fired.first?.id, "spruce.monitor.lowDisk")
        XCTAssertTrue(fired.first?.body.contains("5%") == true)
        XCTAssertTrue(engine.evaluate(sample(3600, snapshot(diskFreePercent: 5)), settings: settings).isEmpty, "cooldown")
        XCTAssertEqual(engine.evaluate(sample(24 * 3600 + 2, snapshot(diskFreePercent: 5)), settings: settings).map(\.kind),
                       [.lowDisk], "daily reminder while still low")
    }

    func testLowDiskRespectsToggleAndBrokenStreak() {
        var engine = MonitorAlertEngine()
        let off = MonitorAlertSettings(lowDisk: false)
        XCTAssertTrue(engine.evaluate(sample(0, snapshot(diskFreePercent: 1)), settings: off).isEmpty)
        XCTAssertTrue(engine.evaluate(sample(2, snapshot(diskFreePercent: 1)), settings: off).isEmpty)
        let on = MonitorAlertSettings(lowDiskPercent: 10)
        XCTAssertTrue(engine.evaluate(sample(4, snapshot(diskFreePercent: 5)), settings: on).isEmpty)
        XCTAssertTrue(engine.evaluate(sample(6, snapshot(diskFreePercent: 40)), settings: on).isEmpty)
        XCTAssertTrue(engine.evaluate(sample(8, snapshot(diskFreePercent: 5)), settings: on).isEmpty, "streak restarted")
    }

    func testMemoryPressureMustBeSustainedAndRearmsAtNormal() {
        var engine = MonitorAlertEngine()
        let settings = MonitorAlertSettings()
        XCTAssertTrue(engine.evaluate(sample(0, snapshot(pressure: .critical)), settings: settings).isEmpty)
        XCTAssertTrue(engine.evaluate(sample(30, snapshot(pressure: .critical)), settings: settings).isEmpty)
        let fired = engine.evaluate(sample(60, snapshot(pressure: .critical)), settings: settings)
        XCTAssertEqual(fired.map(\.kind), [.memoryPressure])
        XCTAssertTrue(fired.first?.body.contains("2 GB") == true, "mentions swap")
        // Still critical hours later: disarmed until pressure returns to normal.
        XCTAssertTrue(engine.evaluate(sample(3 * 3600, snapshot(pressure: .critical)), settings: settings).isEmpty)
        _ = engine.evaluate(sample(3 * 3600 + 2, snapshot(pressure: .normal)), settings: settings)
        XCTAssertTrue(engine.evaluate(sample(3 * 3600 + 4, snapshot(pressure: .critical)), settings: settings).isEmpty)
        XCTAssertEqual(engine.evaluate(sample(3 * 3600 + 64, snapshot(pressure: .critical)), settings: settings).map(\.kind),
                       [.memoryPressure])
    }

    func testWarningPressureInterruptsTheSustainWindow() {
        var engine = MonitorAlertEngine()
        let settings = MonitorAlertSettings()
        _ = engine.evaluate(sample(0, snapshot(pressure: .critical)), settings: settings)
        _ = engine.evaluate(sample(40, snapshot(pressure: .warning)), settings: settings)
        XCTAssertTrue(engine.evaluate(sample(70, snapshot(pressure: .critical)), settings: settings).isEmpty)
    }

    func testTrashAlertsWeeklyOrWhenSizeDoubles() {
        var engine = MonitorAlertEngine()
        let settings = MonitorAlertSettings(trashThreshold: 2_000_000_000)
        XCTAssertTrue(engine.evaluate(sample(0, snapshot(trash: 3_000_000_000), trashKnown: false), settings: settings).isEmpty,
                      "unknown size never alerts")
        XCTAssertEqual(engine.evaluate(sample(1, snapshot(trash: 3_000_000_000)), settings: settings).map(\.kind), [.trashSize])
        XCTAssertTrue(engine.evaluate(sample(60, snapshot(trash: 5_000_000_000)), settings: settings).isEmpty)
        XCTAssertEqual(engine.evaluate(sample(120, snapshot(trash: 6_000_000_000)), settings: settings).map(\.kind),
                       [.trashSize], "doubled")
        XCTAssertTrue(engine.evaluate(sample(3600, snapshot(trash: 7_000_000_000)), settings: settings).isEmpty)
        XCTAssertEqual(engine.evaluate(sample(7 * 86_400 + 200, snapshot(trash: 7_000_000_000)), settings: settings).map(\.kind),
                       [.trashSize], "a week later")
        XCTAssertTrue(engine.evaluate(sample(30 * 86_400, snapshot(trash: 7_000_000_000)),
                                      settings: MonitorAlertSettings(trashSize: false)).isEmpty)
    }

    func testHighCPUAppNeedsTwoMinutesAndHasPerAppCooldown() {
        var engine = MonitorAlertEngine()
        let settings = MonitorAlertSettings()
        let hot = [MonitorProcessUsage(pid: 1, name: "Renderer", cpuPercent: 160, memory: 1),
                   MonitorProcessUsage(pid: 2, name: "Calm", cpuPercent: 5, memory: 1)]
        XCTAssertTrue(engine.evaluate(sample(0, snapshot(), processes: hot), settings: settings).isEmpty)
        XCTAssertTrue(engine.evaluate(sample(100, snapshot(), processes: hot), settings: settings).isEmpty)
        let fired = engine.evaluate(sample(120, snapshot(), processes: hot), settings: settings)
        XCTAssertEqual(fired.map(\.subject), ["Renderer"])
        XCTAssertEqual(fired.first?.id, "spruce.monitor.highCPUApp.Renderer")
        XCTAssertTrue(fired.first?.title.contains("Renderer") == true)
        XCTAssertTrue(fired.first?.body.contains("160%") == true)

        // Cools down, heats up again: re-armed but still inside the 6 h cooldown.
        _ = engine.evaluate(sample(130, snapshot(), processes: []), settings: settings)
        XCTAssertTrue(engine.evaluate(sample(140, snapshot(), processes: hot), settings: settings).isEmpty)
        XCTAssertTrue(engine.evaluate(sample(400, snapshot(), processes: hot), settings: settings).isEmpty)
        // After the cooldown (and a fresh 2-minute window) it fires again.
        _ = engine.evaluate(sample(7 * 3600, snapshot(), processes: []), settings: settings)
        _ = engine.evaluate(sample(7 * 3600 + 2, snapshot(), processes: hot), settings: settings)
        XCTAssertEqual(engine.evaluate(sample(7 * 3600 + 130, snapshot(), processes: hot), settings: settings).map(\.subject),
                       ["Renderer"])
    }

    func testHighCPUToggleOffClearsTracking() {
        var engine = MonitorAlertEngine()
        let hot = [MonitorProcessUsage(pid: 1, name: "Renderer", cpuPercent: 99, memory: 1)]
        _ = engine.evaluate(sample(0, snapshot(), processes: hot), settings: MonitorAlertSettings())
        XCTAssertTrue(engine.evaluate(sample(200, snapshot(), processes: hot),
                                      settings: MonitorAlertSettings(highCPUApp: false)).isEmpty)
        XCTAssertTrue(engine.state.highCPUSince.isEmpty)
        XCTAssertTrue(engine.evaluate(sample(202, snapshot(), processes: hot), settings: MonitorAlertSettings()).isEmpty,
                      "window restarts after re-enabling")
    }

    func testStatePersistsThroughCodable() throws {
        var engine = MonitorAlertEngine()
        let settings = MonitorAlertSettings(lowDiskPercent: 10)
        _ = engine.evaluate(sample(0, snapshot(diskFreePercent: 5)), settings: settings)
        _ = engine.evaluate(sample(2, snapshot(diskFreePercent: 5)), settings: settings)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(MonitorAlertState.self, from: encoder.encode(engine.state))
        var relaunched = MonitorAlertEngine(state: restored)
        XCTAssertTrue(relaunched.evaluate(sample(10, snapshot(diskFreePercent: 5)), settings: settings).isEmpty,
                      "cooldown survives a relaunch")
    }

    func testSettingsMapping() {
        var s = SpruceSettings()
        s.notifyLowDisk = false
        s.lowDiskThresholdPercent = 15
        s.notifyHighMemory = false
        s.notifyTrashSize = true
        s.trashSizeThreshold = 5_000_000_000
        let mapped = MonitorAlertSettings(settings: s, highCPUApp: false)
        XCTAssertFalse(mapped.lowDisk)
        XCTAssertEqual(mapped.lowDiskPercent, 15)
        XCTAssertFalse(mapped.memoryPressure)
        XCTAssertTrue(mapped.trashSize)
        XCTAssertEqual(mapped.trashThreshold, 5_000_000_000)
        XCTAssertFalse(mapped.highCPUApp)
    }
}
