import Darwin
import Foundation
import SpruceCore

// Thin, allocation-light readers over Mach, sysctl and getifaddrs. All of them are
// called on the monitor's private serial queue, never on the main thread.

// MARK: - sysctl

enum MonitorSysctl {
    /// Reads a fixed-size sysctl value by name.
    static func read<T>(_ name: String, as initial: T) -> T? {
        var value = initial
        var size = MemoryLayout<T>.size
        let result = withUnsafeMutablePointer(to: &value) { pointer -> Int32 in
            sysctlbyname(name, pointer, &size, nil, 0)
        }
        return result == 0 ? value : nil
    }
}

/// Converts a NUL-terminated C buffer to a String.
func monitorString(from buffer: [CChar]) -> String {
    buffer.withUnsafeBufferPointer { pointer -> String in
        guard let base = pointer.baseAddress else { return "" }
        return String(cString: base)
    }
}

// MARK: - CPU

enum MonitorCPUProbe {
    /// Cumulative ticks per logical CPU (`host_processor_info`).
    static func ticks(host: mach_port_t) -> [MonitorCPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        let stride = Int(CPU_STATE_MAX)
        var ticks: [MonitorCPUTicks] = []
        ticks.reserveCapacity(Int(cpuCount))
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * stride
            guard base + stride <= Int(infoCount) else { break }
            ticks.append(MonitorCPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ))
        }
        return ticks.isEmpty ? nil : ticks
    }
}

// MARK: - Memory

struct MonitorMemoryReading: Sendable {
    var breakdown: MonitorMemoryBreakdown
    var pressure: SystemSnapshot.MemoryPressure
}

enum MonitorMemoryProbe {
    /// `host_statistics64(HOST_VM_INFO64)` × `vm_page_size`, `hw.memsize`,
    /// `vm.swapusage` and `kern.memorystatus_vm_pressure_level`.
    static func read(host: mach_port_t) -> MonitorMemoryReading? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let counts = MonitorVMCounts(
            free: UInt64(stats.free_count),
            active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count),
            speculative: UInt64(stats.speculative_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            purgeable: UInt64(stats.purgeable_count),
            external: UInt64(stats.external_page_count),
            anonymous: UInt64(stats.internal_page_count)
        )
        let total = MonitorSysctl.read("hw.memsize", as: UInt64(0)) ?? ProcessInfo.processInfo.physicalMemory
        let swap = MonitorSysctl.read("vm.swapusage", as: xsw_usage())
        let level = MonitorSysctl.read("kern.memorystatus_vm_pressure_level", as: Int32(1)) ?? 1
        let breakdown = MonitorMemoryMath.breakdown(
            counts: counts,
            pageSize: UInt64(vm_page_size),
            totalBytes: total,
            swapUsed: swap?.xsu_used ?? 0,
            swapTotal: swap?.xsu_total ?? 0
        )
        return MonitorMemoryReading(breakdown: breakdown, pressure: MonitorMemoryMath.pressure(sysctlLevel: level))
    }
}

// MARK: - System

enum MonitorSystemProbe {
    /// Time since boot from `kern.boottime` (includes sleep, like Activity Monitor).
    static func uptime(now: Date = Date()) -> TimeInterval {
        guard let boot = MonitorSysctl.read("kern.boottime", as: timeval()), boot.tv_sec > 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
        return max(0, now.timeIntervalSince(bootDate))
    }

    /// 1, 5 and 15 minute load averages.
    static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        let count = loads.withUnsafeMutableBufferPointer { buffer -> Int32 in
            getloadavg(buffer.baseAddress, 3)
        }
        return count > 0 ? Array(loads.prefix(Int(count))) : []
    }

    static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }
}

// MARK: - Storage

struct MonitorDiskReading: Sendable, Equatable {
    var total: Int64
    /// Available for important usage (free + purgeable), as Finder shows it.
    var available: Int64
    var purgeable: Int64
}

enum MonitorDiskProbe {
    /// Capacity of the startup volume ("/").
    static func startupVolume() -> MonitorDiskReading? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        // A fresh URL each time: resource values are cached per URL instance.
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let free = Int64(values.volumeAvailableCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage.flatMap { $0 > 0 ? $0 : nil } ?? free
        let available = max(important, free)
        return MonitorDiskReading(total: Int64(total), available: available,
                                  purgeable: MonitorDiskMath.purgeable(importantAvailable: available, available: free))
    }

    /// Size of the user's Trash on every mounted volume. Returns nil when
    /// `~/.Trash` cannot be listed (macOS requires Full Disk Access for it).
    static func trashSize() -> Int64? {
        let fileManager = FileManager.default
        let deadline = Date().addingTimeInterval(20)
        let home = NSHomeDirectory() + "/.Trash"
        var total: Int64 = 0
        if fileManager.fileExists(atPath: home) {
            guard (try? fileManager.contentsOfDirectory(atPath: home)) != nil else { return nil }
            total += DiskUsage.measure(home, deadline: deadline).bytes
        }
        let uid = getuid()
        let volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        for volume in volumes where volume.path != "/" {
            let path = volume.appendingPathComponent(".Trashes").appendingPathComponent(String(uid)).path
            guard fileManager.fileExists(atPath: path),
                  (try? fileManager.contentsOfDirectory(atPath: path)) != nil else { continue }
            total += DiskUsage.measure(path, deadline: deadline).bytes
        }
        return total
    }
}

// MARK: - Network

enum MonitorNetworkProbe {
    /// Byte counters of every physical interface (`getifaddrs`, `AF_LINK` entries,
    /// `if_data`), excluding loopback and tunnels.
    static func counters() -> [String: MonitorInterfaceCounters] {
        var result: [String: MonitorInterfaceCounters] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let ifa = entry.pointee
            cursor = ifa.ifa_next
            guard let address = ifa.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data else { continue }
            if (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) != 0 { continue }
            let name = String(cString: ifa.ifa_name)
            guard MonitorNetworkMath.isCountedInterface(name) else { continue }
            let stats = data.load(as: if_data.self)
            result[name] = MonitorInterfaceCounters(received: UInt64(stats.ifi_ibytes), sent: UInt64(stats.ifi_obytes))
        }
        return result
    }
}
