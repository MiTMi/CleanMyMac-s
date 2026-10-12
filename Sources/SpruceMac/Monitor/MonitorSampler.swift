import Darwin
import Foundation
import SpruceCore

/// One round of readings. Optional members were not sampled this round (they run
/// on slower cadences) and keep their previous value in `SystemMonitor`.
struct MonitorSample: Sendable {
    var date: Date
    var cpu: MonitorCPULoad?
    var coreCount = 0
    var memory: MonitorMemoryReading?
    var disk: MonitorDiskReading?
    var trash: MonitorTrashStatus?
    var network: MonitorNetworkRates?
    var powerSampled = false
    var power: MonitorPowerInfo?
    var devices: [MonitorDevice]?
    var processes: [MonitorProcessUsage]?
    var loadAverage: [Double] = []
    var uptime: TimeInterval = 0
    var thermalState = "nominal"
    var computerName: String?

    init(date: Date) {
        self.date = date
    }
}

/// Owns all sampling state. Used only on `SystemMonitor`'s private serial queue.
final class MonitorSampler: @unchecked Sendable {
    /// `mach_host_self()` returns a new send right on every call, so cache it.
    private let host: mach_port_t = mach_host_self()
    private let processProbe = MonitorProcessProbe()
    private var tracker = MonitorProcessTracker()
    private var previousTicks: [MonitorCPUTicks] = []
    private var previousInterfaces: [String: MonitorInterfaceCounters] = [:]
    private var previousNetworkDate: Date?
    private var lastDisk = Date.distantPast
    private var lastPower = Date.distantPast
    private var lastDevices = Date.distantPast
    private var lastTrash = Date.distantPast
    private var resolvedComputerName = false

    /// Takes the 2-second readings, plus the slower ones when they are due.
    /// `force` (the menu was opened) refreshes the slow readings immediately.
    func sample(force: Bool) -> MonitorSample {
        let now = Date()
        var sample = MonitorSample(date: now)

        if let ticks = MonitorCPUProbe.ticks(host: host) {
            sample.cpu = MonitorCPUMath.load(previous: previousTicks, current: ticks)
            sample.coreCount = ticks.count
            previousTicks = ticks
        }

        sample.memory = MonitorMemoryProbe.read(host: host)

        let counters = MonitorNetworkProbe.counters()
        if let last = previousNetworkDate {
            sample.network = MonitorNetworkMath.rates(previous: previousInterfaces, current: counters,
                                                      interval: now.timeIntervalSince(last))
        }
        previousInterfaces = counters
        previousNetworkDate = now

        sample.processes = tracker.update(processProbe.read(), at: now)

        if force || now.timeIntervalSince(lastDisk) >= MonitorSampling.diskInterval {
            sample.disk = MonitorDiskProbe.startupVolume()
            lastDisk = now
        }
        if force || now.timeIntervalSince(lastPower) >= MonitorSampling.powerInterval {
            sample.power = MonitorPowerProbe.read()
            sample.powerSampled = true
            lastPower = now
        }
        if force || now.timeIntervalSince(lastDevices) >= MonitorSampling.devicesInterval {
            sample.devices = MonitorPowerProbe.devices()
            lastDevices = now
        }
        let trashAge = now.timeIntervalSince(lastTrash)
        if trashAge >= (force ? MonitorSampling.trashMinimumRefresh : MonitorSampling.trashInterval) {
            sample.trash = measureTrash()
        }

        sample.loadAverage = MonitorSystemProbe.loadAverage()
        sample.uptime = MonitorSystemProbe.uptime(now: now)
        sample.thermalState = MonitorSystemProbe.thermalState()
        if !resolvedComputerName {
            resolvedComputerName = true
            sample.computerName = Host.current().localizedName
        }
        return sample
    }

    /// Measures the Trash now (after emptying it, or on the regular cadence).
    func measureTrash() -> MonitorTrashStatus {
        lastTrash = Date()
        if let bytes = MonitorDiskProbe.trashSize() { return .measured(bytes) }
        return .needsAccess
    }

    /// A one-off memory reading (Free Up compares before and after).
    func readMemory() -> MonitorMemoryBreakdown? {
        MonitorMemoryProbe.read(host: host)?.breakdown
    }
}
