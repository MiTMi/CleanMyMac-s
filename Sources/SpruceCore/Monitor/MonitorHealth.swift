import Foundation

/// Overall state shown in the menu header and as the menu bar status dot.
public enum MonitorHealthStatus: String, Sendable, Codable, Comparable, CaseIterable {
    case good
    case attention
    case critical

    private var rank: Int {
        switch self {
        case .good: return 0
        case .attention: return 1
        case .critical: return 2
        }
    }

    public static func < (lhs: MonitorHealthStatus, rhs: MonitorHealthStatus) -> Bool { lhs.rank < rhs.rank }

    public var label: String {
        switch self {
        case .good: return "Good"
        case .attention: return "Needs attention"
        case .critical: return "Critical"
        }
    }
}

/// One live condition that lowers the health score.
public struct MonitorIssue: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case disk, memory, swap, thermal, cpu, battery, trash
    }

    public var kind: Kind
    public var severity: MonitorHealthStatus
    public var title: String
    public var detail: String
    /// Points deducted from 100.
    public var penalty: Int

    public var id: String { kind.rawValue }

    public init(kind: Kind, severity: MonitorHealthStatus, title: String, detail: String, penalty: Int) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.penalty = penalty
    }

    public var symbol: String {
        switch kind {
        case .disk: return "internaldrive"
        case .memory: return "memorychip"
        case .swap: return "arrow.left.arrow.right"
        case .thermal: return "thermometer.medium"
        case .cpu: return "cpu"
        case .battery: return "battery.25percent"
        case .trash: return "trash"
        }
    }
}

/// Inputs that come from settings and history rather than the snapshot itself.
public struct MonitorHealthContext: Sendable, Equatable {
    /// Warn when the startup disk has less than this percentage available.
    public var lowDiskThresholdPercent: Int
    /// Trash size that counts as "too big"; 0 disables the check.
    public var trashThreshold: Int64
    /// True when the Trash size in the snapshot is a real measurement.
    public var trashKnown: Bool
    /// True when CPU load has been very high for the last minute.
    public var sustainedHighCPU: Bool

    public init(lowDiskThresholdPercent: Int = 10, trashThreshold: Int64 = 2_000_000_000,
                trashKnown: Bool = false, sustainedHighCPU: Bool = false) {
        self.lowDiskThresholdPercent = lowDiskThresholdPercent
        self.trashThreshold = trashThreshold
        self.trashKnown = trashKnown
        self.sustainedHighCPU = sustainedHighCPU
    }
}

/// A live health rating derived from the latest snapshot: 100 minus a penalty for
/// each active issue. It reflects the machine's state *right now* (storage, memory,
/// heat, load, battery), so it moves as conditions change.
public struct MonitorHealth: Sendable, Equatable {
    public var score: Int
    public var status: MonitorHealthStatus
    /// Most severe first.
    public var issues: [MonitorIssue]
    public var isRated: Bool

    public init(score: Int, status: MonitorHealthStatus, issues: [MonitorIssue], isRated: Bool = true) {
        self.score = score
        self.status = status
        self.issues = issues
        self.isRated = isRated
    }

    /// Before the first sample arrives.
    public static let pending = MonitorHealth(score: 100, status: .good, issues: [], isRated: false)

    public var headline: String {
        guard isRated else { return "Checking your Mac…" }
        switch status {
        case .good:
            return "Your Mac is in good shape"
        case .attention:
            return issues.count == 1 ? "1 thing needs attention" : "\(issues.count) things need attention"
        case .critical:
            return issues.first(where: { $0.severity == .critical })?.title ?? "Needs attention now"
        }
    }

    public static func assess(_ snapshot: SystemSnapshot, context: MonitorHealthContext) -> MonitorHealth {
        var issues: [MonitorIssue] = []

        // Storage
        if snapshot.diskTotal > 0 {
            let percent = MonitorDiskMath.freePercent(available: snapshot.diskAvailable, total: snapshot.diskTotal)
            let free = ByteFormat.string(snapshot.diskAvailable)
            if MonitorDiskMath.isCritical(available: snapshot.diskAvailable, total: snapshot.diskTotal) {
                issues.append(MonitorIssue(kind: .disk, severity: .critical, title: "Startup disk is almost full",
                                           detail: "Only \(free) available", penalty: 40))
            } else if percent < Double(context.lowDiskThresholdPercent) {
                issues.append(MonitorIssue(kind: .disk, severity: .attention, title: "Startup disk is getting full",
                                           detail: "\(free) available (\(Int(percent.rounded()))%)", penalty: 20))
            }
        }

        // Memory
        switch snapshot.memoryPressure {
        case .critical:
            issues.append(MonitorIssue(kind: .memory, severity: .critical, title: "Memory pressure is critical",
                                       detail: "Apps may slow down or hang", penalty: 25))
        case .warning:
            issues.append(MonitorIssue(kind: .memory, severity: .attention, title: "Memory pressure is elevated",
                                       detail: "macOS is compressing and swapping memory", penalty: 10))
        case .normal:
            break
        }
        if snapshot.memoryTotal > 0, snapshot.swapUsed > snapshot.memoryTotal / 2 {
            issues.append(MonitorIssue(kind: .swap, severity: .attention, title: "Heavy swap use",
                                       detail: "\(ByteFormat.string(snapshot.swapUsed)) swapped to disk", penalty: 5))
        }

        // Heat
        switch snapshot.thermalState {
        case "critical":
            issues.append(MonitorIssue(kind: .thermal, severity: .critical, title: "Your Mac is overheating",
                                       detail: "macOS is throttling performance heavily", penalty: 30))
        case "serious":
            issues.append(MonitorIssue(kind: .thermal, severity: .attention, title: "Your Mac is running hot",
                                       detail: "Performance is being reduced to cool down", penalty: 15))
        default:
            break
        }

        // Load
        if context.sustainedHighCPU {
            issues.append(MonitorIssue(kind: .cpu, severity: .attention, title: "CPU has been busy for a while",
                                       detail: "Over 90% load for the last minute", penalty: 10))
        }

        // Battery (laptops only — nil on a Mac mini)
        if let health = snapshot.batteryHealth, health < MonitorBatteryMath.serviceThreshold {
            issues.append(MonitorIssue(kind: .battery, severity: .attention, title: "Battery needs service",
                                       detail: "Holds \(MonitorFormat.percent(health)) of its original charge", penalty: 10))
        } else if let level = snapshot.batteryLevel, level <= 0.1, snapshot.isCharging != true {
            issues.append(MonitorIssue(kind: .battery, severity: .attention, title: "Battery is low",
                                       detail: "\(MonitorFormat.percent(level)) left", penalty: 5))
        }

        // Trash
        if context.trashKnown, context.trashThreshold > 0, snapshot.trashSize > context.trashThreshold {
            issues.append(MonitorIssue(kind: .trash, severity: .attention, title: "Trash is taking up space",
                                       detail: "\(ByteFormat.string(snapshot.trashSize)) in the Trash", penalty: 5))
        }

        // Most severe first, then the largest penalty, then the order checked above.
        issues = issues.enumerated().sorted { a, b in
            if a.element.severity != b.element.severity { return a.element.severity > b.element.severity }
            if a.element.penalty != b.element.penalty { return a.element.penalty > b.element.penalty }
            return a.offset < b.offset
        }.map(\.element)
        let score = max(0, min(100, 100 - issues.reduce(0) { $0 + $1.penalty }))
        let status = issues.map(\.severity).max() ?? .good
        return MonitorHealth(score: score, status: status, issues: issues)
    }
}
