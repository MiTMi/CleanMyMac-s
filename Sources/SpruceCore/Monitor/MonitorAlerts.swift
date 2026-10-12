import Foundation

/// The background alerts the monitor can raise.
public enum MonitorAlertKind: String, Sendable, Codable, CaseIterable {
    case lowDisk
    case memoryPressure
    case trashSize
    case highCPUApp

    /// Minimum time between two notifications of this kind (per subject).
    public var cooldown: TimeInterval {
        switch self {
        case .lowDisk: return 24 * 3600
        case .memoryPressure: return 2 * 3600
        case .trashSize: return 7 * 24 * 3600
        case .highCPUApp: return 6 * 3600
        }
    }
}

/// User switches and thresholds for the alert rules.
public struct MonitorAlertSettings: Sendable, Equatable {
    public var lowDisk: Bool
    public var lowDiskPercent: Int
    public var memoryPressure: Bool
    public var trashSize: Bool
    public var trashThreshold: Int64
    public var highCPUApp: Bool
    /// Percent of one core an app must exceed…
    public var highCPUPercent: Double
    /// …for this long.
    public var highCPUDuration: TimeInterval
    /// Critical memory pressure must last this long.
    public var memoryDuration: TimeInterval
    /// Consecutive low-disk samples required (de-bounces brief dips).
    public var lowDiskSamples: Int

    public init(lowDisk: Bool = true, lowDiskPercent: Int = 10, memoryPressure: Bool = true, trashSize: Bool = true,
                trashThreshold: Int64 = 2_000_000_000, highCPUApp: Bool = true, highCPUPercent: Double = 80,
                highCPUDuration: TimeInterval = 120, memoryDuration: TimeInterval = 60, lowDiskSamples: Int = 2) {
        self.lowDisk = lowDisk
        self.lowDiskPercent = lowDiskPercent
        self.memoryPressure = memoryPressure
        self.trashSize = trashSize
        self.trashThreshold = trashThreshold
        self.highCPUApp = highCPUApp
        self.highCPUPercent = highCPUPercent
        self.highCPUDuration = highCPUDuration
        self.memoryDuration = memoryDuration
        self.lowDiskSamples = lowDiskSamples
    }

    /// Maps the persisted settings (the high-CPU switch lives outside `SpruceSettings`).
    public init(settings: SpruceSettings, highCPUApp: Bool) {
        self.init(lowDisk: settings.notifyLowDisk,
                  lowDiskPercent: settings.lowDiskThresholdPercent,
                  memoryPressure: settings.notifyHighMemory,
                  trashSize: settings.notifyTrashSize,
                  trashThreshold: settings.trashSizeThreshold,
                  highCPUApp: highCPUApp)
    }
}

/// Everything one evaluation needs.
public struct MonitorAlertSample: Sendable {
    public var date: Date
    public var snapshot: SystemSnapshot
    /// True when `snapshot.trashSize` is a real measurement (needs Full Disk Access).
    public var trashKnown: Bool
    /// Current per-app CPU use (our own process excluded by the caller).
    public var processes: [MonitorProcessUsage]

    public init(date: Date, snapshot: SystemSnapshot, trashKnown: Bool, processes: [MonitorProcessUsage]) {
        self.date = date
        self.snapshot = snapshot
        self.trashKnown = trashKnown
        self.processes = processes
    }
}

/// A notification to post.
public struct MonitorAlert: Sendable, Equatable, Identifiable {
    public var kind: MonitorAlertKind
    /// The app name for per-app alerts.
    public var subject: String?
    public var title: String
    public var body: String

    public init(kind: MonitorAlertKind, subject: String? = nil, title: String, body: String) {
        self.kind = kind
        self.subject = subject
        self.title = title
        self.body = body
    }

    /// Stable notification identifier: a re-post replaces the previous banner.
    public var id: String { MonitorAlertEngine.key(kind, subject) }
}

/// Persisted rule state: cooldowns survive relaunches so nobody is re-alerted on
/// every login.
public struct MonitorAlertState: Codable, Sendable, Equatable {
    /// Last notification time per alert key (`kind[.subject]`).
    public var lastFired: [String: Date] = [:]
    /// Keys that already fired and wait for the condition to clear.
    public var disarmed: Set<String> = []
    /// Trash size at the last Trash alert (a doubling re-alerts early).
    public var lastTrashAlertSize: Int64 = 0
    /// Consecutive samples below the low-disk threshold.
    public var lowDiskStreak: Int = 0
    /// When memory pressure turned critical.
    public var criticalPressureSince: Date?
    /// When each app first exceeded the CPU threshold.
    public var highCPUSince: [String: Date] = [:]

    public init() {}
}

/// Evaluates the alert rules against each sample, with per-type cooldowns,
/// sustain windows and re-arming once a condition clears.
public struct MonitorAlertEngine: Sendable {
    public private(set) var state: MonitorAlertState

    public init(state: MonitorAlertState = MonitorAlertState()) {
        self.state = state
    }

    public static func key(_ kind: MonitorAlertKind, _ subject: String? = nil) -> String {
        "spruce.monitor.\(kind.rawValue)" + (subject.map { ".\($0)" } ?? "")
    }

    /// Returns the alerts to post now and updates the rule state.
    public mutating func evaluate(_ sample: MonitorAlertSample, settings: MonitorAlertSettings) -> [MonitorAlert] {
        var alerts: [MonitorAlert] = []
        if let alert = evaluateLowDisk(sample, settings) { alerts.append(alert) }
        if let alert = evaluateMemory(sample, settings) { alerts.append(alert) }
        if let alert = evaluateTrash(sample, settings) { alerts.append(alert) }
        alerts += evaluateHighCPU(sample, settings)
        prune(now: sample.date)
        return alerts
    }

    // MARK: Rules

    private mutating func evaluateLowDisk(_ sample: MonitorAlertSample, _ settings: MonitorAlertSettings) -> MonitorAlert? {
        let key = Self.key(.lowDisk)
        let snap = sample.snapshot
        guard settings.lowDisk, settings.lowDiskPercent > 0, snap.diskTotal > 0 else {
            state.lowDiskStreak = 0
            return nil
        }
        let percent = MonitorDiskMath.freePercent(available: snap.diskAvailable, total: snap.diskTotal)
        let threshold = Double(settings.lowDiskPercent)
        guard percent < threshold else {
            state.lowDiskStreak = 0
            return nil
        }
        state.lowDiskStreak += 1
        // A daily reminder while space stays low (the cooldown is the only limiter).
        guard state.lowDiskStreak >= max(1, settings.lowDiskSamples), canFire(key, .lowDisk, at: sample.date) else { return nil }
        markFired(key, at: sample.date, disarm: false)
        let free = ByteFormat.string(snap.diskAvailable)
        return MonitorAlert(kind: .lowDisk, title: "Your startup disk is almost full",
                            body: "Only \(free) (\(Int(percent.rounded()))%) is available. Open Spruce to clear junk, large files and the Trash.")
    }

    private mutating func evaluateMemory(_ sample: MonitorAlertSample, _ settings: MonitorAlertSettings) -> MonitorAlert? {
        let key = Self.key(.memoryPressure)
        let snap = sample.snapshot
        guard settings.memoryPressure else {
            state.criticalPressureSince = nil
            return nil
        }
        guard snap.memoryPressure == .critical else {
            state.criticalPressureSince = nil
            if snap.memoryPressure == .normal { state.disarmed.remove(key) }
            return nil
        }
        let since = state.criticalPressureSince ?? sample.date
        state.criticalPressureSince = since
        guard sample.date.timeIntervalSince(since) >= settings.memoryDuration, canFire(key, .memoryPressure, at: sample.date) else {
            return nil
        }
        markFired(key, at: sample.date)
        var body = "Your Mac has been short of memory for over a minute"
        if snap.swapUsed > 0 { body += " and is swapping \(ByteFormat.string(snap.swapUsed)) to disk" }
        body += ". Quit apps you don't need, or use Free Up in the Spruce menu."
        return MonitorAlert(kind: .memoryPressure, title: "Memory pressure is critical", body: body)
    }

    private mutating func evaluateTrash(_ sample: MonitorAlertSample, _ settings: MonitorAlertSettings) -> MonitorAlert? {
        let key = Self.key(.trashSize)
        let size = sample.snapshot.trashSize
        guard settings.trashSize, settings.trashThreshold > 0, sample.trashKnown, size > settings.trashThreshold else {
            return nil
        }
        let cooledDown = state.lastFired[key].map { sample.date.timeIntervalSince($0) >= MonitorAlertKind.trashSize.cooldown } ?? true
        let doubled = state.lastTrashAlertSize > 0 && size >= state.lastTrashAlertSize * 2
        guard cooledDown || doubled else { return nil }
        state.lastFired[key] = sample.date
        state.lastTrashAlertSize = size
        return MonitorAlert(kind: .trashSize, title: "Your Trash is getting big",
                            body: "The Trash holds \(ByteFormat.string(size)). Empty it from the Spruce menu to get that space back.")
    }

    private mutating func evaluateHighCPU(_ sample: MonitorAlertSample, _ settings: MonitorAlertSettings) -> [MonitorAlert] {
        guard settings.highCPUApp else {
            state.highCPUSince = [:]
            return []
        }
        var alerts: [MonitorAlert] = []
        var stillHot: [String: Date] = [:]
        // Merge entries that share a name (e.g. two instances) and keep the busiest.
        var busiest: [String: MonitorProcessUsage] = [:]
        for process in sample.processes where process.cpuPercent >= settings.highCPUPercent {
            if let existing = busiest[process.name], existing.cpuPercent >= process.cpuPercent { continue }
            busiest[process.name] = process
        }
        for name in busiest.keys.sorted() {
            guard let process = busiest[name] else { continue }
            let since = state.highCPUSince[name] ?? sample.date
            stillHot[name] = since
            let key = Self.key(.highCPUApp, name)
            guard sample.date.timeIntervalSince(since) >= settings.highCPUDuration,
                  canFire(key, .highCPUApp, at: sample.date) else { continue }
            markFired(key, at: sample.date)
            let minutes = max(1, Int((sample.date.timeIntervalSince(since) / 60).rounded(.down)))
            alerts.append(MonitorAlert(
                kind: .highCPUApp, subject: name,
                title: "\u{201C}\(name)\u{201D} is using a lot of CPU",
                body: "It has used about \(MonitorFormat.cpuPercent(process.cpuPercent)) CPU for \(minutes == 1 ? "over a minute" : "\(minutes) minutes"). Quit it if you don't need it right now."
            ))
        }
        // Apps that cooled down (or quit) re-arm.
        for name in state.highCPUSince.keys where stillHot[name] == nil {
            state.disarmed.remove(Self.key(.highCPUApp, name))
        }
        state.highCPUSince = stillHot
        return alerts
    }

    // MARK: Helpers

    private func canFire(_ key: String, _ kind: MonitorAlertKind, at date: Date) -> Bool {
        if state.disarmed.contains(key) { return false }
        if let last = state.lastFired[key], date.timeIntervalSince(last) < kind.cooldown { return false }
        return true
    }

    /// Records a notification. `disarm` keeps the alert quiet until its condition
    /// clears, even after the cooldown.
    private mutating func markFired(_ key: String, at date: Date, disarm: Bool = true) {
        state.lastFired[key] = date
        if disarm { state.disarmed.insert(key) }
    }

    /// Drops per-app bookkeeping once its cooldown is long past, so the state
    /// file stays small.
    private mutating func prune(now: Date) {
        let horizon = MonitorAlertKind.trashSize.cooldown * 2
        state.lastFired = state.lastFired.filter { now.timeIntervalSince($0.value) < horizon }
        let prefix = Self.key(.highCPUApp) + "."
        let hot = state.highCPUSince
        state.disarmed = state.disarmed.filter { key in
            guard key.hasPrefix(prefix) else { return true }
            return hot[String(key.dropFirst(prefix.count))] != nil
        }
    }
}
