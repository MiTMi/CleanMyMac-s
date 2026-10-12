import AppKit
import Darwin
import Foundation
import SpruceCore

/// Reads per-process CPU time and memory footprint with libproc
/// (`proc_listallpids` + `proc_pid_rusage`) — no `ps`/`top` subprocesses.
///
/// Only processes owned by the current user can be read without root; system
/// daemons are skipped, which is fine for "which of *my* apps is busy".
final class MonitorProcessProbe {
    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    private struct Identity {
        var startTime: UInt64
        var name: String
        var groupPID: Int32
    }

    /// Folds helper processes into the app responsible for them (resolved at run
    /// time; the symbol is private, so its absence just disables grouping).
    private let responsible: ResponsibleFunction?
    private let timebaseNumer: Double
    private let timebaseDenom: Double
    private var identities: [Int32: Identity] = [:]

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        timebaseNumer = Double(max(timebase.numer, 1))
        timebaseDenom = Double(max(timebase.denom, 1))
        if let handle = UnsafeMutableRawPointer(bitPattern: -2),          // RTLD_DEFAULT
           let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") {
            responsible = unsafeBitCast(symbol, to: ResponsibleFunction.self)
        } else {
            responsible = nil
        }
    }

    /// One reading per readable process.
    func read() -> [MonitorProcessReading] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let filled = pids.withUnsafeMutableBufferPointer { buffer -> Int32 in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        }
        guard filled > 0 else { return [] }

        var readings: [MonitorProcessReading] = []
        readings.reserveCapacity(Int(filled))
        var seen = Set<Int32>()
        for pid in pids.prefix(min(Int(filled), pids.count)) where pid > 0 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
                }
            }
            guard result == 0 else { continue }
            seen.insert(pid)
            let identity = resolve(pid: pid, startTime: info.ri_proc_start_abstime)
            let ticks = info.ri_user_time &+ info.ri_system_time
            let nanos = Double(ticks) * timebaseNumer / timebaseDenom
            readings.append(MonitorProcessReading(
                pid: pid,
                name: identity.name,
                startTime: info.ri_proc_start_abstime,
                cpuTimeNanos: nanos.isFinite && nanos > 0 ? UInt64(min(nanos, Double(UInt64.max / 2))) : 0,
                footprint: Int64(clamping: info.ri_phys_footprint),
                groupPID: identity.groupPID
            ))
        }
        // Forget processes that exited.
        if identities.count > seen.count + 64 {
            identities = identities.filter { seen.contains($0.key) }
        }
        return readings
    }

    private func resolve(pid: Int32, startTime: UInt64) -> Identity {
        if let cached = identities[pid], cached.startTime == startTime { return cached }
        var group = pid
        if let responsible {
            let owner = responsible(pid)
            if owner > 0 { group = owner }
        }
        let identity = Identity(startTime: startTime, name: Self.displayName(for: pid), groupPID: group)
        identities[pid] = identity
        return identity
    }

    /// The app's localized name when it is an app, else the process name.
    static func displayName(for pid: Int32) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName, !name.isEmpty {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            let name = monitorString(from: buffer)
            if !name.isEmpty { return name }
        }
        var path = [CChar](repeating: 0, count: 4096)   // PROC_PIDPATHINFO_MAXSIZE
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let name = (monitorString(from: path) as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "Process \(pid)"
    }
}
