import Foundation

/// One raw per-process reading from `proc_pid_rusage`.
public struct MonitorProcessReading: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    /// Process start time (Mach absolute). Distinguishes a reused pid from the
    /// process that had it before.
    public var startTime: UInt64
    /// Cumulative user + system CPU time, in nanoseconds.
    public var cpuTimeNanos: UInt64
    /// Physical footprint in bytes (Activity Monitor's "Memory" column).
    public var footprint: Int64
    /// The process this one is attributed to (the "responsible" app for helpers);
    /// equal to `pid` for standalone processes.
    public var groupPID: Int32

    public init(pid: Int32, name: String, startTime: UInt64, cpuTimeNanos: UInt64, footprint: Int64, groupPID: Int32? = nil) {
        self.pid = pid
        self.name = name
        self.startTime = startTime
        self.cpuTimeNanos = cpuTimeNanos
        self.footprint = footprint
        self.groupPID = groupPID ?? pid
    }
}

/// CPU and memory use of one app (its helpers folded in) between two samples.
public struct MonitorProcessUsage: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    /// Percent of one core (can exceed 100 on multi-core work, like Activity Monitor).
    public var cpuPercent: Double
    public var memory: Int64
    /// Number of processes folded into this entry.
    public var processCount: Int

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double, memory: Int64, processCount: Int = 1) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memory = memory
        self.processCount = processCount
    }
}

/// Turns successive cumulative CPU-time readings into per-app CPU percentages.
public struct MonitorProcessTracker: Sendable {
    private struct Previous: Sendable {
        var startTime: UInt64
        var cpuTimeNanos: UInt64
    }

    private var previous: [Int32: Previous] = [:]
    private var lastDate: Date?

    public init() {}

    /// Consumes a full set of readings taken at `date` and returns per-app usage
    /// (helpers folded into their group). The first call reports 0 % CPU for all.
    public mutating func update(_ readings: [MonitorProcessReading], at date: Date) -> [MonitorProcessUsage] {
        let interval = lastDate.map { date.timeIntervalSince($0) } ?? 0
        var next: [Int32: Previous] = [:]
        next.reserveCapacity(readings.count)

        struct Group {
            var name: String?
            var fallbackName: String
            var cpu: Double = 0
            var memory: Int64 = 0
            var count = 0
        }
        var groups: [Int32: Group] = [:]
        var order: [Int32] = []

        for reading in readings {
            var percent = 0.0
            if interval > 0, let before = previous[reading.pid], before.startTime == reading.startTime,
               reading.cpuTimeNanos >= before.cpuTimeNanos {
                percent = Double(reading.cpuTimeNanos - before.cpuTimeNanos) / (interval * 1_000_000_000) * 100
            }
            next[reading.pid] = Previous(startTime: reading.startTime, cpuTimeNanos: reading.cpuTimeNanos)

            let key = reading.groupPID > 0 ? reading.groupPID : reading.pid
            if groups[key] == nil {
                groups[key] = Group(fallbackName: reading.name)
                order.append(key)
            }
            groups[key]!.cpu += max(0, percent)
            groups[key]!.memory += max(0, reading.footprint)
            groups[key]!.count += 1
            if reading.pid == key { groups[key]!.name = reading.name }
        }

        previous = next
        lastDate = date
        return order.compactMap { key in
            guard let group = groups[key] else { return nil }
            return MonitorProcessUsage(pid: key, name: group.name ?? group.fallbackName,
                                       cpuPercent: group.cpu, memory: group.memory, processCount: group.count)
        }
    }

    /// Forgets all history (e.g. after a long sleep).
    public mutating func reset() {
        previous = [:]
        lastDate = nil
    }
}

public enum MonitorProcessRanking {
    public enum Metric: Sendable { case cpu, memory }

    /// The top `limit` apps by the given metric. CPU ranking skips idle apps
    /// (below 0.1 %); ties break by name for a stable order.
    public static func top(_ usages: [MonitorProcessUsage], by metric: Metric, limit: Int) -> [MonitorProcessUsage] {
        let candidates: [MonitorProcessUsage]
        switch metric {
        case .cpu:
            candidates = usages.filter { $0.cpuPercent >= 0.1 }
                .sorted { ($0.cpuPercent, $1.name) > ($1.cpuPercent, $0.name) }
        case .memory:
            candidates = usages.filter { $0.memory > 0 }
                .sorted { ($0.memory, $1.name) > ($1.memory, $0.name) }
        }
        return Array(candidates.prefix(max(0, limit)))
    }
}
