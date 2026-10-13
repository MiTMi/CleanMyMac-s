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
/// libproc, getifaddrs, IOKit); results are published on the main thread. Disk capacity
/// is re-read every 10 s, battery every 10 s and accessory batteries every 30 s. Slow
/// readers have their own queues so they never delay a sample: the Trash is walked only
/// when its folders change (`MonitorTrashWatcher`), the startup disk's SMART status is
/// read every 30 min, and external drives every 30 s and on every mount or unmount.
/// `snapshot` may be read from any thread.
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
    /// SMART status (and, when reported, life left and temperature) of the startup disk;
    /// nil until read or when `diskutil` can't tell.
    public private(set) var diskHealth: MonitorDiskHealth?
    /// Mounted external drives, cards and disk images (ejectable), by name.
    public private(set) var volumes: [MonitorVolume] = []
    /// Mount points of drives being ejected right now.
    public private(set) var ejectingVolumes: Set<String> = []
    /// The live (system) part of Mac Health. The menu header and status icon show the
    /// app's combined score (`AppModel.healthReport`), which uses these issues.
    public private(set) var health: MonitorHealth = .pending
    /// Hours since 1970 of the latest sample. It changes once an hour, so views that show
    /// time-based figures (days since the last Checkup or scan) can read it to stay current.
    public private(set) var clockHour = 0
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
    private let volumesQueue = DispatchQueue(label: "app.spruce.monitor.volumes", qos: .utility)
    private let sampler = MonitorSampler()
    private let trashWatcher = MonitorTrashWatcher()
    private let ownPID = getpid()
    /// Accessed only on `queue`.
    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var lastVolumesRead = Date.distantPast
    @ObservationIgnored private var lastDiskHealthRead = Date.distantPast
    @ObservationIgnored private var diskHealthInFlight = false
    /// Mount / unmount observers (kept for the monitor's lifetime).
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    /// Main thread only.
    @ObservationIgnored private var alertCenter = MonitorAlertCenter()
    @ObservationIgnored private var latestProcesses: [MonitorProcessUsage] = []

    public init() {
        Self.migrateHighCPUPreference()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.refreshVolumes()
            })
        }
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
    /// accessories, external drives, the Trash's folders — walked again only if they
    /// changed or the last walk is 10 min old — and disk health if 2 min old).
    public func refresh() {
        queue.async { [weak self] in self?.tick(force: true) }
    }

    /// Re-reads the mounted external drives (on their own queue).
    public func refreshVolumes() {
        volumesQueue.async { [weak self] in
            guard let self else { return }
            let list = MonitorVolumeProbe.externalVolumes()
            DispatchQueue.main.async { self.applyVolumes(list) }
        }
    }

    /// Runs on `queue`.
    private func tick(force: Bool) {
        let sample = sampler.sample(force: force)
        DispatchQueue.main.async { [weak self] in self?.apply(sample) }

        trashWatcher.poll(force: force) { [weak self] status in
            guard let self else { return }
            DispatchQueue.main.async { self.applyTrash(status) }
        }

        let now = sample.date
        if force || now.timeIntervalSince(lastVolumesRead) >= MonitorSampling.volumesInterval {
            lastVolumesRead = now
            refreshVolumes()
        }

        let healthAge = now.timeIntervalSince(lastDiskHealthRead)
        let healthDue = force ? MonitorSampling.diskHealthForcedRefresh : MonitorSampling.diskHealthInterval
        if !diskHealthInFlight, healthAge >= healthDue || healthAge < 0 {
            lastDiskHealthRead = now
            diskHealthInFlight = true
            Task.detached(priority: .utility) { [weak self] in
                let reading = await MonitorDiskHealthProbe.read()
                guard let monitor = self else { return }
                monitor.queue.async { monitor.diskHealthInFlight = false }
                DispatchQueue.main.async { monitor.applyDiskHealth(reading) }
            }
        }
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
        // Same bookkeeping as Performance › Free Up RAM (`PerformanceEngine.runTasks`), so
        // Maintenance and Checkup stop recommending a task that just ran.
        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                  forKey: PerformanceEngine.lastRunPrefix + PerformanceTaskID.freeRAM.rawValue)
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
        let status = await trashWatcher.measureNow()
        applyTrash(status)
        return outcome
    }

    /// Ejects one external drive (off the main thread; a normal eject that macOS refuses
    /// while files on the drive are open). On failure the message names the apps using
    /// it when they can be found.
    @MainActor
    public func eject(_ volume: MonitorVolume) async -> MonitorEjectResult {
        guard !ejectingVolumes.contains(volume.id) else {
            return .failed("\u{201C}\(volume.name)\u{201D} is already being ejected.")
        }
        ejectingVolumes.insert(volume.id)
        let failure = await MonitorEjector.eject(path: volume.path, name: volume.name)
        ejectingVolumes.remove(volume.id)
        if failure == nil { volumes.removeAll { $0.id == volume.id } }
        refreshVolumes()
        if let failure { return .failed(failure) }
        return .ejected
    }

    /// Ejects every listed drive, one after another. Returns the failure messages.
    @MainActor
    public func ejectAll() async -> [String] {
        var failures: [String] = []
        for volume in volumes {
            let result = await eject(volume)
            if case .failed(let message) = result { failures.append(message) }
        }
        return failures
    }

    private func readMemoryNow() async -> MonitorMemoryBreakdown? {
        await withCheckedContinuation { continuation in
            queue.async { [sampler] in continuation.resume(returning: sampler.readMemory()) }
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
        let hour = Int(sample.date.timeIntervalSince1970 / 3600)
        if hour != clockHour { clockHour = hour }
        if let name = sample.computerName, !name.isEmpty, name != computerName { computerName = name }

        setSnapshot(snap)
        if !hasSample { hasSample = true }
        updateHealth(snap)
        runAlerts(snap)
    }

    /// Main thread.
    private func applyTrash(_ status: MonitorTrashStatus) {
        if status != trash { trash = status }
        var snap = currentSnapshot()
        snap.trashSize = status.bytes ?? 0
        setSnapshot(snap)
        updateHealth(snap)
    }

    /// Main thread. A failed read keeps the last known condition.
    private func applyDiskHealth(_ reading: MonitorDiskHealth?) {
        guard let reading, reading != diskHealth else { return }
        diskHealth = reading
        if hasSample { updateHealth(currentSnapshot()) }
    }

    /// Main thread.
    private func applyVolumes(_ list: [MonitorVolume]) {
        if list != volumes { volumes = list }
    }

    private func updateHealth(_ snap: SystemSnapshot) {
        let settings = SettingsStore.shared.settings
        let context = MonitorHealthContext(
            lowDiskThresholdPercent: settings.lowDiskThresholdPercent,
            trashThreshold: settings.notifyTrashSize ? settings.trashSizeThreshold : 0,
            trashKnown: trash.bytes != nil,
            sustainedHighCPU: MonitorCPUMath.isSustained(cpuHistory.elements, above: 0.9, samples: 30),
            diskFailing: diskHealth?.isFailing ?? false
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
