import AppKit
import Darwin
import Foundation
import SpruceCore

/// Memory readout for the maintenance tasks and the heavy-consumers screen.
public struct PerformanceMemoryReading: Sendable, Equatable {
    public var total: Int64
    /// Truly free pages.
    public var free: Int64
    /// Memory in use the way Activity Monitor counts it (app + wired + compressed).
    public var used: Int64
    public var compressed: Int64
    public var swapUsed: Int64
    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public var pressureLevel: Int

    public var available: Int64 { max(0, total - used) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public var pressureTitle: String {
        switch pressureLevel {
        case 4: return "Critical"
        case 2: return "Elevated"
        default: return "Normal"
        }
    }
}

/// Capacity of the volume holding the home folder.
public struct PerformanceDiskReading: Sendable, Equatable {
    public var total: Int64
    /// Space free right now.
    public var free: Int64
    /// Free plus what macOS can purge on demand (what Finder calls "available").
    public var availableForImportantUsage: Int64

    public var purgeable: Int64 { max(0, availableForImportantUsage - free) }
    public var freeFraction: Double { total > 0 ? Double(availableForImportantUsage) / Double(total) : 0 }
}

public enum PerformanceSystemProbe {
    // MARK: Memory

    public static func memory() -> PerformanceMemoryReading? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Int64(vm_kernel_page_size)
        let active = Int64(stats.active_count) * page
        let inactive = Int64(stats.inactive_count) * page
        let speculative = Int64(stats.speculative_count) * page
        let wired = Int64(stats.wire_count) * page
        let compressed = Int64(stats.compressor_page_count) * page
        let purgeable = Int64(stats.purgeable_count) * page
        let external = Int64(stats.external_page_count) * page
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        let used = max(0, active + inactive + speculative + wired + compressed - purgeable - external)
        return PerformanceMemoryReading(total: total, free: Int64(stats.free_count) * page, used: min(used, total),
                                        compressed: compressed, swapUsed: swapUsed(), pressureLevel: pressureLevel())
    }

    public static func pressureLevel() -> Int {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 1 }
        return Int(level)
    }

    public static func swapUsed() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }

    // MARK: Disk

    public static func disk(path: String = NSHomeDirectory()) -> PerformanceDiskReading? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity else { return nil }
        let free = Int64(values.volumeAvailableCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage ?? free
        return PerformanceDiskReading(total: Int64(total), free: free, availableForImportantUsage: max(important, free))
    }

    // MARK: Apps

    public static func isRunning(bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    // MARK: Files

    public static func fileSize(_ path: String) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    public static func mailIndexSize(_ path: String) -> Int64 {
        PerformanceMailIndex.companionPaths(for: path).reduce(0) { $0 + fileSize($1) }
    }

    // MARK: Conditions

    /// Everything the recommender looks at. Runs a few quick commands; call off the main actor.
    public static func conditions(home: String = NSHomeDirectory()) async -> PerformanceConditions {
        var conditions = PerformanceConditions()
        if let memory = memory() {
            conditions.memoryPressureLevel = memory.pressureLevel
            conditions.swapUsedBytes = memory.swapUsed
        }
        if let disk = disk(path: home) {
            conditions.purgeableBytes = disk.purgeable
            conditions.volumeFreeFraction = disk.freeFraction
        }
        let vpn = await Shell.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 5)
        conditions.vpnConnected = vpn.status == 0 && PerformanceSystemParsers.vpnConnected(scutilNCList: vpn.stdout)
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/mdutil") {
            let spotlight = await Shell.run("/usr/bin/mdutil", ["-s", "/"], timeout: 10)
            conditions.spotlightIndexingEnabled = PerformanceSystemParsers.spotlightIndexingEnabled(
                mdutilStatus: spotlight.stdout + "\n" + spotlight.stderr)
        }
        conditions.mailIndex = await mailIndexState(home: home)
        conditions.homePermissionProblems = homePermissionProblems(home: home)
        let attributes = try? FileManager.default.attributesOfItem(atPath: "/var/log/daily.out")
        conditions.systemScriptsLastRun = attributes?[.modificationDate] as? Date
        return conditions
    }

    /// Finds and measures Mail's Envelope Index (read-only).
    public static func mailIndexState(home: String) async -> PerformanceMailIndexState {
        let mailRoot = (home as NSString).appendingPathComponent("Library/Mail")
        guard FileManager.default.fileExists(atPath: mailRoot) else { return .notFound }
        guard let path = PerformanceMailIndex.locate(home: home) else {
            // ~/Library/Mail is protected: when it can't be listed, Full Disk Access is missing.
            let listable = (try? FileManager.default.contentsOfDirectory(atPath: mailRoot)) != nil
            return listable ? .notFound : .unreadable
        }
        let query = await Shell.run("/usr/bin/sqlite3", ["-readonly", path, "PRAGMA page_count; PRAGMA freelist_count;"],
                                    timeout: 20)
        guard query.status == 0, let counts = PerformanceSystemParsers.sqlitePageCounts(query.stdout) else { return .unreadable }
        return .measured(PerformanceMailIndexInfo(path: path, bytes: mailIndexSize(path), pageCount: counts.pageCount,
                                                  freelistCount: counts.freelistCount))
    }

    public static func homePermissionProblems(home: String) -> [String] {
        let fm = FileManager.default
        return PerformanceHomePermissions.problems(
            home: home,
            uid: getuid(),
            ownerOf: { path in ((try? fm.attributesOfItem(atPath: path))?[.ownerAccountID] as? NSNumber)?.uint32Value },
            isWritable: { fm.isWritableFile(atPath: $0) },
            exists: { fm.fileExists(atPath: $0) })
    }
}
