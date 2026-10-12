import Foundation

// Pure metric math for the system monitor. The macOS layer (SpruceMac/Monitor)
// reads raw counters from Mach, sysctl, getifaddrs and IOKit and hands them here,
// so every formula is unit-tested on Linux.

// MARK: - CPU

/// Cumulative scheduler ticks for one logical CPU, as reported by
/// `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`. The kernel counters are 32-bit
/// and wrap, so deltas use wrapping subtraction.
public struct MonitorCPUTicks: Sendable, Equatable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// CPU load between two tick readings. All values are fractions (0...1).
public struct MonitorCPULoad: Sendable, Equatable {
    public var total: Double
    public var user: Double
    public var system: Double
    public var perCore: [Double]

    public init(total: Double, user: Double, system: Double, perCore: [Double]) {
        self.total = total
        self.user = user
        self.system = system
        self.perCore = perCore
    }

    public static let zero = MonitorCPULoad(total: 0, user: 0, system: 0, perCore: [])
}

public enum MonitorCPUMath {
    /// Load between two readings of every core. Returns nil for the first reading
    /// (no previous sample) or when the core count changed.
    public static func load(previous: [MonitorCPUTicks], current: [MonitorCPUTicks]) -> MonitorCPULoad? {
        guard !previous.isEmpty, previous.count == current.count else { return nil }
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        var userAll: UInt64 = 0
        var systemAll: UInt64 = 0
        var busyAll: UInt64 = 0
        var totalAll: UInt64 = 0
        for (old, new) in zip(previous, current) {
            let user = UInt64(new.user &- old.user)
            let system = UInt64(new.system &- old.system)
            let nice = UInt64(new.nice &- old.nice)
            let idle = UInt64(new.idle &- old.idle)
            let busy = user + system + nice
            let total = busy + idle
            perCore.append(total > 0 ? Double(busy) / Double(total) : 0)
            userAll += user + nice
            systemAll += system
            busyAll += busy
            totalAll += total
        }
        guard totalAll > 0 else {
            return MonitorCPULoad(total: 0, user: 0, system: 0, perCore: perCore)
        }
        let t = Double(totalAll)
        return MonitorCPULoad(total: monitorClamp01(Double(busyAll) / t),
                              user: monitorClamp01(Double(userAll) / t),
                              system: monitorClamp01(Double(systemAll) / t),
                              perCore: perCore.map(monitorClamp01))
    }

    /// Marks samples that belong to a "spike": a run of at least `minimumRun`
    /// consecutive values above `threshold` (default: > 80 % for ≥ 10 s at 2 s/sample).
    public static func spikeMask(_ values: [Double], threshold: Double = 0.8, minimumRun: Int = 5) -> [Bool] {
        var mask = [Bool](repeating: false, count: values.count)
        var runStart: Int?
        for index in 0...values.count {
            let above = index < values.count && values[index] > threshold
            if above {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                if index - start >= max(1, minimumRun) {
                    for i in start..<index { mask[i] = true }
                }
                runStart = nil
            }
        }
        return mask
    }

    /// True when each of the last `samples` values is above `threshold`.
    public static func isSustained(_ values: [Double], above threshold: Double, samples: Int) -> Bool {
        guard samples > 0, values.count >= samples else { return false }
        return values.suffix(samples).allSatisfy { $0 > threshold }
    }
}

// MARK: - Memory

/// Page counts from `host_statistics64(HOST_VM_INFO64)`.
public struct MonitorVMCounts: Sendable, Equatable {
    public var free: UInt64
    public var active: UInt64
    public var inactive: UInt64
    public var speculative: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var purgeable: UInt64
    /// File-backed pages (part of "Cached Files").
    public var external: UInt64
    /// Anonymous pages (the basis of "App Memory").
    public var anonymous: UInt64

    public init(free: UInt64 = 0, active: UInt64 = 0, inactive: UInt64 = 0, speculative: UInt64 = 0,
                wired: UInt64 = 0, compressed: UInt64 = 0, purgeable: UInt64 = 0, external: UInt64 = 0,
                anonymous: UInt64 = 0) {
        self.free = free
        self.active = active
        self.inactive = inactive
        self.speculative = speculative
        self.wired = wired
        self.compressed = compressed
        self.purgeable = purgeable
        self.external = external
        self.anonymous = anonymous
    }
}

/// Memory split the way Activity Monitor shows it. Used = App + Wired + Compressed.
public struct MonitorMemoryBreakdown: Sendable, Equatable {
    public var total: Int64
    public var app: Int64
    public var wired: Int64
    public var compressed: Int64
    /// Cached files (file-backed + purgeable pages); reclaimable on demand.
    public var cached: Int64
    public var swapUsed: Int64
    public var swapTotal: Int64

    public init(total: Int64 = 0, app: Int64 = 0, wired: Int64 = 0, compressed: Int64 = 0, cached: Int64 = 0,
                swapUsed: Int64 = 0, swapTotal: Int64 = 0) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
    }

    public var used: Int64 { min(total > 0 ? total : .max, app + wired + compressed) }
    /// Memory not in use by apps or the kernel (includes cached files).
    public var available: Int64 { max(0, total - used) }
    public var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

public enum MonitorMemoryMath {
    /// Computes the Activity Monitor style breakdown from VM page counts.
    ///
    /// App = (anonymous − purgeable) pages; Wired; Compressed (pages occupied by the
    /// compressor); Cached = file-backed + purgeable pages.
    public static func breakdown(counts: MonitorVMCounts, pageSize: UInt64, totalBytes: UInt64,
                                 swapUsed: UInt64 = 0, swapTotal: UInt64 = 0) -> MonitorMemoryBreakdown {
        let page = max(pageSize, 1)
        let appPages: UInt64
        if counts.anonymous > 0 {
            appPages = counts.anonymous > counts.purgeable ? counts.anonymous - counts.purgeable : 0
        } else {
            // Fallback when the kernel does not report anonymous pages.
            let gross = counts.active + counts.inactive + counts.speculative
            let reclaimable = counts.purgeable + counts.external
            appPages = gross > reclaimable ? gross - reclaimable : 0
        }
        let total = Int64(clamping: totalBytes)
        func bytes(_ pages: UInt64) -> Int64 {
            let (product, overflow) = pages.multipliedReportingOverflow(by: page)
            return overflow ? .max : Int64(clamping: product)
        }
        var app = bytes(appPages)
        let wired = bytes(counts.wired)
        let compressed = bytes(counts.compressed)
        // Never report more than physical memory (counters are sampled non-atomically).
        if total > 0, app + wired + compressed > total {
            app = max(0, total - wired - compressed)
        }
        return MonitorMemoryBreakdown(
            total: total,
            app: app,
            wired: wired,
            compressed: compressed,
            cached: bytes(counts.external + counts.purgeable),
            swapUsed: Int64(clamping: swapUsed),
            swapTotal: Int64(clamping: swapTotal)
        )
    }

    /// Maps `kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical).
    public static func pressure(sysctlLevel: Int32) -> SystemSnapshot.MemoryPressure {
        switch sysctlLevel {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}

// MARK: - Network

/// Raw byte counters of one interface.
public struct MonitorInterfaceCounters: Sendable, Equatable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

/// Throughput between two counter readings.
public struct MonitorNetworkRates: Sendable, Equatable {
    public var downBytesPerSecond: Double
    public var upBytesPerSecond: Double
    /// Bytes transferred during the interval (for session totals).
    public var downBytes: UInt64
    public var upBytes: UInt64

    public init(downBytesPerSecond: Double = 0, upBytesPerSecond: Double = 0, downBytes: UInt64 = 0, upBytes: UInt64 = 0) {
        self.downBytesPerSecond = downBytesPerSecond
        self.upBytesPerSecond = upBytesPerSecond
        self.downBytes = downBytes
        self.upBytes = upBytes
    }

    public static let zero = MonitorNetworkRates()
}

public enum MonitorNetworkMath {
    /// `if_data` byte counters (from `getifaddrs`) are 32-bit and wrap at 4 GiB.
    public static let counterModulus: UInt64 = 1 << 32
    /// Deltas implying more than this (≈ 40 Gb/s) are treated as a counter reset.
    public static let maximumPlausibleBytesPerSecond: Double = 5_000_000_000

    /// Delta between two readings of a counter that wraps at `modulus`.
    public static func delta(from old: UInt64, to new: UInt64, modulus: UInt64 = counterModulus) -> UInt64 {
        if new >= old { return new - old }
        guard old < modulus else { return 0 }     // larger counter went backwards: a reset
        return (modulus - old) + new
    }

    /// Interfaces counted towards throughput: physical links only. Loopback is
    /// excluded, and so are tunnels and virtual links whose traffic is already
    /// counted on a physical interface (VPN `utun`, `ipsec`, AWDL, bridges…).
    public static func isCountedInterface(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let excludedPrefixes = ["lo", "utun", "ipsec", "gif", "stf", "awdl", "llw", "anpi", "bridge", "ap", "pktap", "vmenet", "feth"]
        return !excludedPrefixes.contains { name.hasPrefix($0) }
    }

    /// Sums per-interface deltas between two readings. Interfaces present in only
    /// one reading contribute nothing (they just appeared or disappeared).
    public static func rates(previous: [String: MonitorInterfaceCounters],
                             current: [String: MonitorInterfaceCounters],
                             interval: TimeInterval) -> MonitorNetworkRates {
        guard interval > 0 else { return .zero }
        var down: UInt64 = 0
        var up: UInt64 = 0
        let limit = UInt64(maximumPlausibleBytesPerSecond * interval)
        for (name, now) in current {
            guard let before = previous[name] else { continue }
            let rx = delta(from: before.received, to: now.received)
            let tx = delta(from: before.sent, to: now.sent)
            if rx <= limit { down += rx }
            if tx <= limit { up += tx }
        }
        return MonitorNetworkRates(downBytesPerSecond: Double(down) / interval,
                                   upBytesPerSecond: Double(up) / interval,
                                   downBytes: down, upBytes: up)
    }
}

// MARK: - Battery

public enum MonitorBatteryMath {
    /// Full-charge capacity in mAh from `AppleSmartBattery` keys. Apple silicon
    /// reports `MaxCapacity` as a percentage and the real value in
    /// `AppleRawMaxCapacity`; Intel reports mAh in `MaxCapacity`.
    public static func fullChargeCapacity(maxCapacity: Int?, rawMaxCapacity: Int?) -> Int? {
        if let raw = rawMaxCapacity, raw > 0 { return raw }
        if let max = maxCapacity, max > 100 { return max }
        return nil
    }

    /// Battery health = full-charge capacity / design capacity, capped at 100 %.
    public static func health(maxCapacity: Int?, rawMaxCapacity: Int?, designCapacity: Int?) -> Double? {
        if let full = fullChargeCapacity(maxCapacity: maxCapacity, rawMaxCapacity: rawMaxCapacity),
           let design = designCapacity, design > 0 {
            return monitorClamp01(Double(full) / Double(design))
        }
        if let percent = maxCapacity, (1...100).contains(percent) {
            return Double(percent) / 100
        }
        return nil
    }

    /// Battery health below this counts as "service recommended".
    public static let serviceThreshold = 0.8
}

// MARK: - Storage

public enum MonitorDiskMath {
    /// Purgeable space = available for important usage − truly free.
    public static func purgeable(importantAvailable: Int64, available: Int64) -> Int64 {
        max(0, importantAvailable - available)
    }

    /// Available space as a percentage of capacity (0...100).
    public static func freePercent(available: Int64, total: Int64) -> Double {
        guard total > 0 else { return 100 }
        return min(100, max(0, Double(available) / Double(total) * 100))
    }

    /// Critically low: under 2 % or under 3 GB, whichever is larger.
    public static func isCritical(available: Int64, total: Int64) -> Bool {
        guard total > 0 else { return false }
        let floor = max(Int64(3_000_000_000), total / 50)
        return available < floor
    }
}

func monitorClamp01(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(1, max(0, value))
}
