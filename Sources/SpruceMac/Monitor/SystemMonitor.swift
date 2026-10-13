import AppKit
import Foundation
import Observation
import SpruceCore

/// Result of the menu's "Free Up" memory action.
public enum MonitorFreeUpResult: Sendable, Equatable {
    /// Purge ran; bytes of memory that became available (0 when nothing changed).
    case freed(Int64)
    /// The administrator prompt was dismissed.
    case cancelled
    case failed(String)
}

/// Live system metrics for the menu bar monitor, Activity health score and alerts.
///
/// CONTRACT (used by Activity, Checkup and the menu bar — keep these):
/// * `SystemMonitor.shared`
/// * `snapshot: SystemSnapshot` (observable, refreshed while started)
/// * `start()` / `stop()` / `refresh()`
///
/// Sampling runs every 2 s on a private serial queue (Mach host statistics, sysctl,
/// libproc, getifaddrs, IOKit); results are published on the main thread. Disk is
/// re-read every 10 s, battery every 10 s, accessory batteries every 30 s and the
/// Trash every 60 s. `snapshot` may be read from any thread.
@Observable
public final class SystemMonitor: @unchecked Sendable {
    public static let shared = SystemMonitor()

    private static let highCPUAlertKey = "monitor.notifyHighCPU"

    // MARK: Contract

    private let snapshotLock = NSLock()
    @ObservationIgnored private var storedSnapshot = SystemSnapshot()

    /// The latest reading. Thread-safe; observable from SwiftUI.
    public var snapshot: SystemSnapshot {
        access(keyPath: \.snapshot)
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return storedSnapshot
    }

    // MARK: Observable detail (main thread)

    public private(set) var isRunning = false
    /// False until the first sample has been published.
    public private(set) var hasSample = false
    public private(set) var cpuLoad = MonitorCPULoad.zero
    public private(set) var cpuHistory = MonitorRingBuffer<Double>()
    public private(set) var coreCount = 0
    public private(set) var loadAverage: [Double] = []
    public private(set) var memory = MonitorMemoryBreakdown()
    public private(set) var memoryHistory = MonitorRingBuffer<Double>()
    public private(set) var downHistory = MonitorRingBuffer<Double>()
    public private(set) var upHistory = MonitorRingBuffer<Double>()
    /// Bytes received / sent since the monitor started.
    public private(set) var sessionDownloaded: UInt64 = 0
    public private(set) var sessionUploaded: UInt64 = 0
    /// Busiest apps (helpers folded in), refreshed every sample.
    public private(set) var topByCPU: [MonitorProcessUsage] = []
    public private(set) var topByMemory: [MonitorProcessUsage] = []
    /// Internal battery or UPS; nil on a Mac mini without a UPS.
    public private(set) var power: MonitorPowerInfo?
    /// Accessories reporting a battery level, low battery first.
    public private(set) var devices: [MonitorDevice] = []
    public private(set) var trash: MonitorTrashStatus = .measuring
    public private(set) var health: MonitorHealth = .pending
    public private(set) var computerName = "This Mac"
    public private(set) var isFreeingMemory = false
    public private(set) var isEmptyingTrash = false

    /// Alert when one app keeps a core busy (≥ 80 % for 2 min). Backed by
    /// `SpruceSettings.notifyHighCPU` so Settings and the menu share one switch.
    public var notifyHighCPU: Bool {
        get { SettingsStore.shared.settings.notifyHighCPU }
        set { SettingsStore.shared.settings.notifyHighCPU = newValue }
    }

    // MARK: Private

    private let queue = DispatchQueue(label: "app.spruce.monitor", qos: .utility)
    private let sampler = MonitorSampler()
    private let ownPID = getpid()
    /// Accessed only on `queue`.
    @ObservationIgnored private var timer: DispatchSourceTimer?
    /// Main thread only.
    @ObservationIgnored private var alertCenter = MonitorAlertCenter()
    @ObservationIgnored private var latestProcesses: [MonitorProcessUsage] = []

    public init() {
        Self.migrateHighCPUPreference()
    }

    /// One-time migration of the pre-settings preference.
    private static func migrateHighCPUPreference() {
        guard let old = UserDefaults.standard.object(forKey: highCPUAlertKey) as? Bool else { return }
        SettingsStore.shared.settings.notifyHighCPU = old
        UserDefaults.standard.removeObject(forKey: highCPUAlertKey)
    }

    // MARK: Lifecycle

    /// Starts sampling every 2 seconds (idempotent).
    public func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: MonitorSampling.interval, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.tick(force: false) }
            self.timer = timer
            timer.resume()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    /// Stops sampling. The last snapshot stays available.
    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    /// Takes a full reading now, including the slower metrics (disk, battery,
    /// accessories and — if older than 15 s — the Trash).
    public func refresh() {
        queue.async { [weak self] in self?.tick(force: true) }
    }

    private func tick(force: Bool) {
        let sample = sampler.sample(force: force)
        DispatchQueue.main.async { [weak self] in self?.apply(sample) }
    }

    // MARK: Actions

    /// Purges inactive memory (`/usr/sbin/purge`, one administrator prompt) and
    /// reports how much memory became available.
    @MainActor
    public func freeUpMemory() async -> MonitorFreeUpResult {
        guard !isFreeingMemory else { return .cancelled }
        isFreeingMemory = true
        defer { isFreeingMemory = false }
        let before = await readMemoryNow()
        do {
            try await PrivilegedRunner.shared.run([.purgeMemory])
        } catch SpruceError.cancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        let after = await readMemoryNow()
        var freed: Int64 = 0
        if let before, let after { freed = max(0, before.used - after.used) }
        HistoryStore.shared.record(ActivityEntry(
            module: .performance, kind: .maintenance, bytes: freed, count: 1,
            summary: freed > 0 ? "Freed up \(ByteFormat.string(freed)) of memory" : "Freed up memory"
        ))
        refresh()
        return .freed(freed)
    }

    /// Permanently empties the user's Trash through `FileRemover` (the app's only
    /// deletion path), records it in history and re-measures the Trash.
    @MainActor
    public func emptyTrash() async -> RunOutcome {
        isEmptyingTrash = true
        defer { isEmptyingTrash = false }
        let outcome = await FileRemover.shared.emptyTrash(module: .cleanup)
        if outcome.processedCount > 0 || !outcome.failures.isEmpty {
            // Recorded as `.other`: the bytes were already counted as freed when the items
            // were moved to the Trash, so counting them again here would double the total.
            var entry = outcome
            entry.summary = "Emptied the Trash · " + outcome.summary
            HistoryStore.shared.record(entry, kind: .other)
        }
        let status = await measureTrashNow()
        applyTrash(status)
        return outcome
    }

    private func readMemoryNow() async -> MonitorMemoryBreakdown? {
        await withCheckedContinuation { continuation in
            queue.async { [sampler] in continuation.resume(returning: sampler.readMemory()) }
        }
    }

    private func measureTrashNow() async -> MonitorTrashStatus {
        await withCheckedContinuation { continuation in
            queue.async { [sampler] in continuation.resume(returning: sampler.measureTrash()) }
        }
    }

    // MARK: Publishing (main thread)

    private func currentSnapshot() -> SystemSnapshot {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return storedSnapshot
    }

    private func setSnapshot(_ value: SystemSnapshot) {
        withMutation(keyPath: \.snapshot) {
            snapshotLock.lock()
            storedSnapshot = value
            snapshotLock.unlock()
        }
    }

    private func apply(_ sample: MonitorSample) {
        var snap = currentSnapshot()
        snap.date = sample.date

        if let cpu = sample.cpu {
            snap.cpuLoad = cpu.total
            cpuLoad = cpu
            cpuHistory.append(cpu.total)
        }
        if sample.coreCount > 0, sample.coreCount != coreCount { coreCount = sample.coreCount }
        if !sample.loadAverage.isEmpty { loadAverage = sample.loadAverage }

        if let reading = sample.memory {
            let m = reading.breakdown
            snap.memoryTotal = m.total
            snap.memoryUsed = m.used
            snap.swapUsed = m.swapUsed
            snap.memoryPressure = reading.pressure
            if m != memory { memory = m }
            memoryHistory.append(m.usedFraction)
        }

        if let disk = sample.disk {
            snap.diskTotal = disk.total
            snap.diskAvailable = disk.available
            snap.diskPurgeable = disk.purgeable
        }
        if let status = sample.trash {
            if status != trash { trash = status }
            snap.trashSize = status.bytes ?? 0
        }

        if let rates = sample.network {
            snap.networkDownBytesPerSec = rates.downBytesPerSecond
            snap.networkUpBytesPerSec = rates.upBytesPerSecond
            downHistory.append(rates.downBytesPerSecond)
            upHistory.append(rates.upBytesPerSecond)
            sessionDownloaded &+= rates.downBytes
            sessionUploaded &+= rates.upBytes
        }

        if sample.powerSampled {
            if sample.power != power { power = sample.power }
            if let p = sample.power, p.kind == .internalBattery {
                snap.batteryLevel = p.level
                snap.batteryHealth = p.health
                snap.batteryCycles = p.cycleCount
                snap.isCharging = p.isCharging
            } else {
                snap.batteryLevel = nil
                snap.batteryHealth = nil
                snap.batteryCycles = nil
                snap.isCharging = nil
            }
        }
        if let list = sample.devices, list != devices { devices = list }

        if let processes = sample.processes {
            latestProcesses = processes
            let byCPU = MonitorProcessRanking.top(processes, by: .cpu, limit: 5)
            let byMemory = MonitorProcessRanking.top(processes, by: .memory, limit: 5)
            if byCPU != topByCPU { topByCPU = byCPU }
            if byMemory != topByMemory { topByMemory = byMemory }
        }

        snap.uptime = sample.uptime
        snap.thermalState = sample.thermalState
        if let name = sample.computerName, !name.isEmpty, name != computerName { computerName = name }

        setSnapshot(snap)
        if !hasSample { hasSample = true }
        updateHealth(snap)
        runAlerts(snap)
    }

    @MainActor
    private func applyTrash(_ status: MonitorTrashStatus) {
        if status != trash { trash = status }
        var snap = currentSnapshot()
        snap.trashSize = status.bytes ?? 0
        setSnapshot(snap)
        updateHealth(snap)
    }

    private func updateHealth(_ snap: SystemSnapshot) {
        let settings = SettingsStore.shared.settings
        let context = MonitorHealthContext(
            lowDiskThresholdPercent: settings.lowDiskThresholdPercent,
            trashThreshold: settings.notifyTrashSize ? settings.trashSizeThreshold : 0,
            trashKnown: trash.bytes != nil,
            sustainedHighCPU: MonitorCPUMath.isSustained(cpuHistory.elements, above: 0.9, samples: 30)
        )
        let assessed = MonitorHealth.assess(snap, context: context)
        if assessed != health { health = assessed }
    }

    private func runAlerts(_ snap: SystemSnapshot) {
        let settings = SettingsStore.shared.settings
        let sample = MonitorAlertSample(
            date: snap.date,
            snapshot: snap,
            trashKnown: trash.bytes != nil,
            processes: latestProcesses.filter { $0.pid != ownPID }
        )
        alertCenter.process(sample, settings: MonitorAlertSettings(settings: settings, highCPUApp: notifyHighCPU))
    }
}
