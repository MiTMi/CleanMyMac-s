import Foundation
import XCTest
@testable import SpruceCore

final class MonitorRingBufferTests: XCTestCase {
    func testKeepsMostRecentSamplesInOrder() {
        var buffer = MonitorRingBuffer<Int>(capacity: 3)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.latest)
        buffer.append(1)
        buffer.append(2)
        XCTAssertEqual(buffer.elements, [1, 2])
        XCTAssertEqual(buffer.latest, 2)
        buffer.append(3)
        XCTAssertTrue(buffer.isFull)
        buffer.append(4)
        buffer.append(5)
        XCTAssertEqual(buffer.elements, [3, 4, 5])
        XCTAssertEqual(buffer.latest, 5)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.suffix(2), [4, 5])
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        buffer.append(9)
        XCTAssertEqual(buffer.elements, [9])
    }

    func testDefaultCapacityIsSixtySamples() {
        var buffer = MonitorRingBuffer<Double>()
        XCTAssertEqual(buffer.capacity, 60)
        buffer.append(contentsOf: (0..<100).map(Double.init))
        XCTAssertEqual(buffer.count, 60)
        XCTAssertEqual(buffer.elements.first, 40)
        XCTAssertEqual(buffer.latest, 99)
        XCTAssertEqual(buffer.maximum, 99)
        XCTAssertEqual(buffer.average, (40...99).reduce(0.0) { $0 + Double($1) } / 60, accuracy: 1e-9)
    }

    func testEqualityComparesLogicalContents() {
        var a = MonitorRingBuffer<Int>(capacity: 2)
        var b = MonitorRingBuffer<Int>(capacity: 2)
        a.append(contentsOf: [1, 2, 3])   // wrapped storage [3, 2], start 1
        b.append(contentsOf: [2, 3])      // unwrapped storage [2, 3]
        XCTAssertEqual(a, b)
        b.append(4)
        XCTAssertNotEqual(a, b)
    }
}

final class MonitorCPUMathTests: XCTestCase {
    func testFirstReadingHasNoLoad() {
        let ticks = [MonitorCPUTicks(user: 10, system: 5, idle: 85, nice: 0)]
        XCTAssertNil(MonitorCPUMath.load(previous: [], current: ticks))
        XCTAssertNil(MonitorCPUMath.load(previous: ticks, current: ticks + ticks), "core count changed")
    }

    func testLoadFromTickDeltas() throws {
        let before = [
            MonitorCPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            MonitorCPUTicks(user: 0, system: 0, idle: 1000, nice: 0),
        ]
        let after = [
            MonitorCPUTicks(user: 160, system: 70, idle: 870, nice: 0),   // busy 80 of 100
            MonitorCPUTicks(user: 10, system: 0, idle: 1090, nice: 0),    // busy 10 of 100
        ]
        let load = try XCTUnwrap(MonitorCPUMath.load(previous: before, current: after))
        XCTAssertEqual(load.perCore[0], 0.8, accuracy: 1e-9)
        XCTAssertEqual(load.perCore[1], 0.1, accuracy: 1e-9)
        XCTAssertEqual(load.total, 0.45, accuracy: 1e-9)
        XCTAssertEqual(load.user, 0.35, accuracy: 1e-9)
        XCTAssertEqual(load.system, 0.10, accuracy: 1e-9)
    }

    func testLoadSurvivesThirtyTwoBitWraparound() throws {
        let before = [MonitorCPUTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 29, nice: 0)]
        let after = [MonitorCPUTicks(user: 10, system: 0, idle: 10, nice: 0)]   // +20 user, +40 idle
        let load = try XCTUnwrap(MonitorCPUMath.load(previous: before, current: after))
        XCTAssertEqual(load.total, 20.0 / 60.0, accuracy: 1e-9)
    }

    func testIdleIntervalReportsZero() throws {
        let ticks = [MonitorCPUTicks(user: 5, system: 5, idle: 5, nice: 5)]
        let load = try XCTUnwrap(MonitorCPUMath.load(previous: ticks, current: ticks))
        XCTAssertEqual(load.total, 0)
        XCTAssertEqual(load.perCore, [0])
    }

    func testSpikeMaskNeedsTenSecondsAboveThreshold() {
        let values: [Double] = [0.2, 0.9, 0.9, 0.9, 0.9, 0.9, 0.3, 0.95, 0.95, 0.1]
        let mask = MonitorCPUMath.spikeMask(values)
        XCTAssertEqual(mask, [false, true, true, true, true, true, false, false, false, false])
        XCTAssertEqual(MonitorCPUMath.spikeMask([0.9, 0.9, 0.9, 0.9, 0.9]), [true, true, true, true, true], "run at the end")
        XCTAssertEqual(MonitorCPUMath.spikeMask([]), [])
    }

    func testSustainedLoad() {
        XCTAssertTrue(MonitorCPUMath.isSustained([0.1, 0.95, 0.96, 0.97], above: 0.9, samples: 3))
        XCTAssertFalse(MonitorCPUMath.isSustained([0.95, 0.5, 0.97], above: 0.9, samples: 3))
        XCTAssertFalse(MonitorCPUMath.isSustained([0.95], above: 0.9, samples: 3), "not enough history")
    }
}

final class MonitorMemoryMathTests: XCTestCase {
    func testBreakdownMatchesActivityMonitorFormula() {
        let page: UInt64 = 16_384
        let counts = MonitorVMCounts(free: 10_000, active: 300_000, inactive: 200_000, speculative: 5_000,
                                     wired: 120_000, compressed: 60_000, purgeable: 20_000, external: 150_000,
                                     anonymous: 380_000)
        let total: UInt64 = 16 * 1_073_741_824
        let m = MonitorMemoryMath.breakdown(counts: counts, pageSize: page, totalBytes: total,
                                            swapUsed: 1_000_000_000, swapTotal: 2_000_000_000)
        XCTAssertEqual(m.app, Int64(360_000 * page))
        XCTAssertEqual(m.wired, Int64(120_000 * page))
        XCTAssertEqual(m.compressed, Int64(60_000 * page))
        XCTAssertEqual(m.cached, Int64(170_000 * page))
        XCTAssertEqual(m.used, m.app + m.wired + m.compressed)
        XCTAssertEqual(m.available, Int64(total) - m.used)
        XCTAssertEqual(m.swapUsed, 1_000_000_000)
        XCTAssertEqual(m.usedFraction, Double(m.used) / Double(total), accuracy: 1e-12)
    }

    func testBreakdownNeverExceedsPhysicalMemory() {
        let counts = MonitorVMCounts(wired: 600, compressed: 300, anonymous: 900)
        let m = MonitorMemoryMath.breakdown(counts: counts, pageSize: 1, totalBytes: 1000)
        XCTAssertEqual(m.used, 1000)
        XCTAssertEqual(m.app, 100)
        XCTAssertEqual(m.available, 0)
        XCTAssertEqual(m.usedFraction, 1)
    }

    func testFallbackWithoutAnonymousCount() {
        let counts = MonitorVMCounts(active: 500, inactive: 300, speculative: 20, wired: 100, compressed: 50,
                                     purgeable: 70, external: 250)
        let m = MonitorMemoryMath.breakdown(counts: counts, pageSize: 4096, totalBytes: 8 * 1_073_741_824)
        XCTAssertEqual(m.app, Int64(500 * 4096))
    }

    func testPressureLevels() {
        XCTAssertEqual(MonitorMemoryMath.pressure(sysctlLevel: 1), .normal)
        XCTAssertEqual(MonitorMemoryMath.pressure(sysctlLevel: 2), .warning)
        XCTAssertEqual(MonitorMemoryMath.pressure(sysctlLevel: 4), .critical)
        XCTAssertEqual(MonitorMemoryMath.pressure(sysctlLevel: 0), .normal)
    }
}

final class MonitorNetworkMathTests: XCTestCase {
    func testDeltaHandlesWraparound() {
        XCTAssertEqual(MonitorNetworkMath.delta(from: 100, to: 250), 150)
        XCTAssertEqual(MonitorNetworkMath.delta(from: UInt64(UInt32.max) - 99, to: 50), 150)
        XCTAssertEqual(MonitorNetworkMath.delta(from: 10_000_000_000, to: 5), 0, "64-bit counter reset")
    }

    func testRatesSumCountedInterfaces() {
        let before = ["en0": MonitorInterfaceCounters(received: 1_000, sent: 500),
                      "en1": MonitorInterfaceCounters(received: UInt64(UInt32.max) - 999, sent: 0)]
        let after = ["en0": MonitorInterfaceCounters(received: 5_000, sent: 1_500),
                     "en1": MonitorInterfaceCounters(received: 1_000, sent: 1_000),
                     "en5": MonitorInterfaceCounters(received: 9_999_999, sent: 9_999_999)]   // new: ignored
        let rates = MonitorNetworkMath.rates(previous: before, current: after, interval: 2)
        XCTAssertEqual(rates.downBytes, 4_000 + 2_000)
        XCTAssertEqual(rates.upBytes, 1_000 + 1_000)
        XCTAssertEqual(rates.downBytesPerSecond, 3_000, accuracy: 1e-9)
        XCTAssertEqual(rates.upBytesPerSecond, 1_000, accuracy: 1e-9)
        XCTAssertEqual(MonitorNetworkMath.rates(previous: before, current: after, interval: 0), .zero)
    }

    func testImplausibleJumpIsDropped() {
        let before = ["en0": MonitorInterfaceCounters(received: 0, sent: 0)]
        let after = ["en0": MonitorInterfaceCounters(received: 4_000_000_000, sent: 10)]
        let rates = MonitorNetworkMath.rates(previous: before, current: after, interval: 0.5)
        XCTAssertEqual(rates.downBytes, 0)
        XCTAssertEqual(rates.upBytes, 10)
    }

    func testCountedInterfaces() {
        for name in ["en0", "en1", "en7"] { XCTAssertTrue(MonitorNetworkMath.isCountedInterface(name), name) }
        for name in ["lo0", "utun3", "awdl0", "llw0", "bridge0", "ipsec0", "gif0", "stf0", "anpi1", "ap1", ""] {
            XCTAssertFalse(MonitorNetworkMath.isCountedInterface(name), name)
        }
    }
}

final class MonitorBatteryAndDiskMathTests: XCTestCase {
    func testHealthPrefersRawCapacityOnAppleSilicon() throws {
        // Apple silicon: MaxCapacity is a percentage, AppleRawMaxCapacity is mAh.
        let health = try XCTUnwrap(MonitorBatteryMath.health(maxCapacity: 100, rawMaxCapacity: 4_100, designCapacity: 5_000))
        XCTAssertEqual(health, 0.82, accuracy: 1e-9)
    }

    func testHealthWithIntelMilliampHours() throws {
        let health = try XCTUnwrap(MonitorBatteryMath.health(maxCapacity: 4_500, rawMaxCapacity: nil, designCapacity: 6_000))
        XCTAssertEqual(health, 0.75, accuracy: 1e-9)
    }

    func testHealthIsCappedAndHandlesMissingData() {
        XCTAssertEqual(MonitorBatteryMath.health(maxCapacity: nil, rawMaxCapacity: 5_300, designCapacity: 5_000), 1)
        XCTAssertEqual(MonitorBatteryMath.health(maxCapacity: 87, rawMaxCapacity: nil, designCapacity: nil), 0.87)
        XCTAssertNil(MonitorBatteryMath.health(maxCapacity: nil, rawMaxCapacity: nil, designCapacity: 5_000))
        XCTAssertNil(MonitorBatteryMath.health(maxCapacity: 0, rawMaxCapacity: 0, designCapacity: 0))
    }

    func testPurgeableAndFreePercent() {
        XCTAssertEqual(MonitorDiskMath.purgeable(importantAvailable: 150, available: 100), 50)
        XCTAssertEqual(MonitorDiskMath.purgeable(importantAvailable: 90, available: 100), 0)
        XCTAssertEqual(MonitorDiskMath.freePercent(available: 25, total: 100), 25)
        XCTAssertEqual(MonitorDiskMath.freePercent(available: 25, total: 0), 100)
        XCTAssertTrue(MonitorDiskMath.isCritical(available: 2_000_000_000, total: 500_000_000_000))
        XCTAssertTrue(MonitorDiskMath.isCritical(available: 15_000_000_000, total: 1_000_000_000_000), "under 2 %")
        XCTAssertFalse(MonitorDiskMath.isCritical(available: 40_000_000_000, total: 500_000_000_000))
    }
}
