import Foundation

// MARK: - Levels

/// The five health bands shown on the Activity gauge.
public enum ActivityHealthLevel: String, CaseIterable, Sendable, Codable, Comparable {
    case excellent
    case good
    case fair
    case requiresAttention
    case critical

    /// 0 = best.
    public var rank: Int {
        switch self {
        case .excellent: return 0
        case .good: return 1
        case .fair: return 2
        case .requiresAttention: return 3
        case .critical: return 4
        }
    }

    public static func < (lhs: ActivityHealthLevel, rhs: ActivityHealthLevel) -> Bool { lhs.rank < rhs.rank }

    /// User-facing band name.
    public var title: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .requiresAttention: return "Needs Attention"
        case .critical: return "Critical"
        }
    }

    /// One line under the band name.
    public var blurb: String {
        switch self {
        case .excellent: return "Everything checks out."
        case .good: return "In good shape, with a few small wins available."
        case .fair: return "Worth a look soon."
        case .requiresAttention: return "Some issues are affecting your Mac."
        case .critical: return "Act now — start with the first suggestion."
        }
    }

    /// Lowest score in the band.
    public var floor: Int {
        switch self {
        case .excellent: return 90
        case .good: return 75
        case .fair: return 60
        case .requiresAttention: return 40
        case .critical: return 0
        }
    }

    /// Highest score in the band.
    public var ceiling: Int {
        switch self {
        case .excellent: return 100
        case .good: return 89
        case .fair: return 74
        case .requiresAttention: return 59
        case .critical: return 39
        }
    }

    /// Band for a 0–100 score.
    public static func level(for score: Int) -> ActivityHealthLevel {
        switch score {
        case 90...: return .excellent
        case 75..<90: return .good
        case 60..<75: return .fair
        case 40..<60: return .requiresAttention
        default: return .critical
        }
    }
}

/// How urgent one recommendation is.
public enum ActivitySeverity: String, Sendable, Codable, Comparable, CaseIterable {
    case info
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    public static func < (lhs: ActivitySeverity, rhs: ActivitySeverity) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - Recommendations

/// What a recommendation card's button does.
public enum ActivityRecommendationAction: Equatable, Sendable {
    /// Navigate to a module and (optionally) one of its tools (`AppModel.open(_:tool:)`).
    case open(ModuleID, tool: String?)
    /// Open System Settings › Privacy & Security › Full Disk Access.
    case grantFullDiskAccess
    /// Informational only.
    case none
}

/// One card under the health gauge: a factor that lowers the score and how to fix it.
public struct ActivityRecommendation: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var severity: ActivitySeverity
    public var symbol: String
    public var actionTitle: String
    public var action: ActivityRecommendationAction
    /// Points this factor takes off the score.
    public var penalty: Int
    /// True for live system conditions (disk, memory, heat…); false for upkeep factors.
    public var isSystem: Bool

    public init(id: String, title: String, detail: String, severity: ActivitySeverity, symbol: String,
                actionTitle: String, action: ActivityRecommendationAction, penalty: Int, isSystem: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.action = action
        self.penalty = penalty
        self.isSystem = isSystem
    }

    /// True when the card has a button.
    public var isActionable: Bool {
        if case .none = action { return false }
        return !actionTitle.isEmpty
    }

    /// Module the action opens, if any.
    public var targetModule: ModuleID? {
        if case .open(let module, _) = action { return module }
        return nil
    }

    /// Tool id the action opens, if any.
    public var toolID: String? {
        if case .open(_, let tool) = action { return tool }
        return nil
    }
}

/// A live condition reported by the system monitor (mirrors `MonitorIssue`, kept
/// independent so Activity's logic stays self-contained). `kind` uses the monitor's
/// raw values: disk, memory, swap, thermal, cpu, battery, trash.
public struct ActivitySystemIssue: Equatable, Sendable {
    public var kind: String
    public var isCritical: Bool
    public var title: String
    public var detail: String
    public var penalty: Int

    public init(kind: String, isCritical: Bool, title: String, detail: String, penalty: Int) {
        self.kind = kind
        self.isCritical = isCritical
        self.title = title
        self.detail = detail
        self.penalty = penalty
    }
}

// MARK: - Input & report

/// Everything the health score is computed from.
public struct ActivityHealthInput: Sendable, Equatable {
    /// Latest monitor reading; nil until the monitor has produced its first sample.
    public var snapshot: SystemSnapshot?
    /// Live issues as assessed by the system monitor. When present they are used as the
    /// system part of the score (so the app and the menu bar agree); otherwise the
    /// system factors are derived from `snapshot`.
    public var liveIssues: [ActivitySystemIssue]?
    public var history: ActivityHistory
    public var hasFullDiskAccess: Bool
    public var realtimeProtectionEnabled: Bool
    /// Warn when the startup disk has less than this percentage available.
    public var lowDiskThresholdPercent: Int
    public var now: Date

    public init(snapshot: SystemSnapshot? = nil, liveIssues: [ActivitySystemIssue]? = nil,
                history: ActivityHistory = ActivityHistory(), hasFullDiskAccess: Bool = true,
                realtimeProtectionEnabled: Bool = true, lowDiskThresholdPercent: Int = 10, now: Date = Date()) {
        self.snapshot = snapshot
        self.liveIssues = liveIssues
        self.history = history
        self.hasFullDiskAccess = hasFullDiskAccess
        self.realtimeProtectionEnabled = realtimeProtectionEnabled
        self.lowDiskThresholdPercent = lowDiskThresholdPercent
        self.now = now
    }
}

/// The computed health score.
public struct ActivityHealthReport: Equatable, Sendable {
    /// 0–100.
    public var score: Int
    public var level: ActivityHealthLevel
    /// Most urgent first.
    public var recommendations: [ActivityRecommendation]
    /// False until live system data is available (the score then reflects upkeep only).
    public var isRated: Bool
    /// 100 minus the live system penalties (matches the menu bar when fed live issues).
    public var systemScore: Int
    /// 100 minus the upkeep penalties (threats, permissions, scan recency), with caps.
    public var careScore: Int
    /// Days since the last Checkup, nil when there was none.
    public var daysSinceCheckup: Int?
    /// Days since anything was last cleaned, nil when nothing was.
    public var daysSinceCleanup: Int?
    /// Threats found by the last malware scan that were not removed afterwards.
    public var unresolvedThreats: Int

    public init(score: Int, level: ActivityHealthLevel, recommendations: [ActivityRecommendation], isRated: Bool,
                systemScore: Int, careScore: Int, daysSinceCheckup: Int?, daysSinceCleanup: Int?, unresolvedThreats: Int) {
        self.score = score
        self.level = level
        self.recommendations = recommendations
        self.isRated = isRated
        self.systemScore = systemScore
        self.careScore = careScore
        self.daysSinceCheckup = daysSinceCheckup
        self.daysSinceCleanup = daysSinceCleanup
        self.unresolvedThreats = unresolvedThreats
    }

    /// Headline next to the gauge.
    public var headline: String {
        if recommendations.isEmpty { return "Your Mac is in great shape" }
        if let first = recommendations.first, first.severity == .critical { return first.title }
        let count = recommendations.count
        return count == 1 ? "1 suggestion for your Mac" : "\(count) suggestions for your Mac"
    }
}

// MARK: - Scoring

/// Health score: 100 minus a penalty per factor, then capped by the upkeep rules
/// (unresolved threats → Critical; no Full Disk Access → at most Fair; no Checkup for
/// 14 days → at most Good, 30 days or never → at most Fair). Bands: ≥ 90 Excellent,
/// 75–89 Good, 60–74 Fair, 40–59 Needs Attention, < 40 Critical.
public enum ActivityHealth {
    /// No Checkup for this many days caps the band at Good.
    public static let checkupStaleDays = 14
    /// No Checkup for this many days (or never) caps the band at Fair.
    public static let checkupOverdueDays = 30
    /// Nothing cleaned for this many days adds a small suggestion.
    public static let cleanupStaleDays = 30

    public static func assess(_ input: ActivityHealthInput) -> ActivityHealthReport {
        var recommendations: [ActivityRecommendation] = []
        var cap = 100

        // 1. Live system factors.
        let issues: [ActivitySystemIssue]
        if let live = input.liveIssues {
            issues = live
        } else if let snapshot = input.snapshot {
            issues = systemIssues(from: snapshot, lowDiskThresholdPercent: input.lowDiskThresholdPercent)
        } else {
            issues = []
        }
        let systemRecs = issues.map(recommendation(for:))
        recommendations += systemRecs
        let systemPenalty = systemRecs.reduce(0) { $0 + $1.penalty }

        // 2. Upkeep factors.
        var careRecs: [ActivityRecommendation] = []
        var careCap = 100

        let threats = unresolvedThreats(in: input.history)
        if threats > 0 {
            careRecs.append(ActivityRecommendation(
                id: "threat.active",
                title: threats == 1 ? "1 threat needs removal" : "\(threats) threats need removal",
                detail: "The last malware scan found \(threats == 1 ? "a threat" : "threats") that are still on your Mac.",
                severity: .critical, symbol: "exclamationmark.shield.fill", actionTitle: "Review Threats",
                action: .open(.protection, tool: "protection.malware"), penalty: 35))
            careCap = min(careCap, ActivityHealthLevel.critical.ceiling)
        }

        if !input.hasFullDiskAccess {
            careRecs.append(ActivityRecommendation(
                id: "fda.missing", title: "Allow Full Disk Access for complete scans",
                detail: "Without it, Mail, Safari, Messages and other protected folders can't be checked.",
                severity: .warning, symbol: "lock.open.fill", actionTitle: "Allow Access",
                action: .grantFullDiskAccess, penalty: 10))
            careCap = min(careCap, ActivityHealthLevel.fair.ceiling)
        }

        let checkupDays = lastCheckup(in: input.history).map { days(from: $0, to: input.now) }
        switch checkupDays {
        case nil:
            careRecs.append(ActivityRecommendation(
                id: "scan.never", title: "Run your first Checkup",
                detail: "One scan rates junk, threats, speed, updates and clutter, so the score has something to go on.",
                severity: .warning, symbol: "sparkles", actionTitle: "Run Checkup",
                action: .open(.checkup, tool: "checkup.scan"), penalty: 15))
            careCap = min(careCap, ActivityHealthLevel.fair.ceiling)
        case let d? where d >= checkupOverdueDays:
            careRecs.append(ActivityRecommendation(
                id: "scan.overdue", title: "It's been \(spokenDays(d)) since your last Checkup",
                detail: "Junk, updates and threats pile up quietly. A fresh scan takes a minute or two.",
                severity: .warning, symbol: "sparkles", actionTitle: "Run Checkup",
                action: .open(.checkup, tool: "checkup.scan"), penalty: 15))
            careCap = min(careCap, ActivityHealthLevel.fair.ceiling)
        case let d? where d >= checkupStaleDays:
            careRecs.append(ActivityRecommendation(
                id: "scan.stale", title: "It's been \(spokenDays(d)) since your last Checkup",
                detail: "A quick scan keeps the score current.",
                severity: .info, symbol: "sparkles", actionTitle: "Run Checkup",
                action: .open(.checkup, tool: "checkup.scan"), penalty: 8))
            careCap = min(careCap, ActivityHealthLevel.good.ceiling)
        default:
            break
        }

        let cleanupDays = input.history.lastDate(of: .clean).map { days(from: $0, to: input.now) }
        let checkupCurrent = checkupDays.map { $0 < checkupStaleDays } ?? false
        if checkupCurrent, cleanupDays.map({ $0 >= cleanupStaleDays }) ?? true {
            careRecs.append(ActivityRecommendation(
                id: "cleanup.stale",
                title: cleanupDays == nil ? "Nothing has been cleaned yet" : "Last cleanup was \(spokenDays(cleanupDays!)) ago",
                detail: "Caches, logs and leftovers grow back. Clearing them is safe and regains space.",
                severity: .info, symbol: "bubbles.and.sparkles", actionTitle: "Clean Up",
                action: .open(.cleanup, tool: "cleanup.systemJunk"), penalty: 5))
        }

        if !input.realtimeProtectionEnabled {
            careRecs.append(ActivityRecommendation(
                id: "protection.off", title: "Real-time protection is off",
                detail: "New login items and downloads aren't being watched for threats.",
                severity: .info, symbol: "shield.slash", actionTitle: "Review",
                action: .open(.protection, tool: nil), penalty: 5))
        }

        recommendations += careRecs
        let carePenalty = careRecs.reduce(0) { $0 + $1.penalty }
        cap = min(cap, careCap)

        // 3. Combine.
        let raw = 100 - systemPenalty - carePenalty
        let score = clamp(min(raw, cap))
        let systemScore = clamp(100 - systemPenalty)
        let careScore = clamp(min(100 - carePenalty, careCap))

        let ordered = recommendations.enumerated().sorted { a, b in
            if a.element.severity != b.element.severity { return a.element.severity > b.element.severity }
            if a.element.penalty != b.element.penalty { return a.element.penalty > b.element.penalty }
            return a.offset < b.offset
        }.map(\.element)

        return ActivityHealthReport(
            score: score,
            level: .level(for: score),
            recommendations: ordered,
            isRated: input.liveIssues != nil || input.snapshot != nil,
            systemScore: systemScore,
            careScore: careScore,
            daysSinceCheckup: checkupDays,
            daysSinceCleanup: cleanupDays,
            unresolvedThreats: threats
        )
    }

    // MARK: System factors

    /// System factors derived straight from a snapshot (same thresholds as the menu bar
    /// monitor): disk space, memory pressure, swap, heat and battery condition.
    public static func systemIssues(from snapshot: SystemSnapshot, lowDiskThresholdPercent: Int = 10) -> [ActivitySystemIssue] {
        var issues: [ActivitySystemIssue] = []

        if snapshot.diskTotal > 0 {
            let available = max(0, snapshot.diskAvailable)
            let percent = Double(available) / Double(snapshot.diskTotal) * 100
            let criticalFloor = max(Int64(3_000_000_000), snapshot.diskTotal / 50)
            let free = ByteFormat.string(available)
            if available < criticalFloor {
                issues.append(ActivitySystemIssue(kind: "disk", isCritical: true, title: "Startup disk is almost full",
                                                  detail: "Only \(free) available", penalty: 40))
            } else if percent < Double(lowDiskThresholdPercent) {
                issues.append(ActivitySystemIssue(kind: "disk", isCritical: false, title: "Startup disk is getting full",
                                                  detail: "\(free) available (\(Int(percent.rounded()))%)", penalty: 20))
            }
        }

        switch snapshot.memoryPressure {
        case .critical:
            issues.append(ActivitySystemIssue(kind: "memory", isCritical: true, title: "Memory pressure is critical",
                                              detail: "Apps may slow down or hang", penalty: 25))
        case .warning:
            issues.append(ActivitySystemIssue(kind: "memory", isCritical: false, title: "Memory pressure is elevated",
                                              detail: "macOS is compressing and swapping memory", penalty: 10))
        case .normal:
            break
        }
        if snapshot.memoryTotal > 0, snapshot.swapUsed > snapshot.memoryTotal / 2 {
            issues.append(ActivitySystemIssue(kind: "swap", isCritical: false, title: "Heavy swap use",
                                              detail: "\(ByteFormat.string(snapshot.swapUsed)) swapped to disk", penalty: 5))
        }

        switch snapshot.thermalState {
        case "critical":
            issues.append(ActivitySystemIssue(kind: "thermal", isCritical: true, title: "Your Mac is overheating",
                                              detail: "macOS is throttling performance heavily", penalty: 30))
        case "serious":
            issues.append(ActivitySystemIssue(kind: "thermal", isCritical: false, title: "Your Mac is running hot",
                                              detail: "Performance is being reduced to cool down", penalty: 15))
        default:
            break
        }

        if let health = snapshot.batteryHealth, health < 0.8 {
            issues.append(ActivitySystemIssue(kind: "battery", isCritical: false, title: "Battery needs service",
                                              detail: "Holds \(Int((health * 100).rounded()))% of its original charge", penalty: 10))
        }
        return issues
    }

    /// Card for a live system issue, with the most useful place to fix it.
    public static func recommendation(for issue: ActivitySystemIssue) -> ActivityRecommendation {
        let severity: ActivitySeverity = issue.isCritical ? .critical : .warning
        let symbol: String
        let actionTitle: String
        let action: ActivityRecommendationAction
        switch issue.kind {
        case "disk":
            symbol = "internaldrive"
            actionTitle = "Free Up Space"
            action = .open(.cleanup, tool: "cleanup.systemJunk")
        case "memory":
            symbol = "memorychip"
            actionTitle = "Free Up RAM"
            action = .open(.toolbox, tool: "toolbox.freeRAM")
        case "swap":
            symbol = "arrow.left.arrow.right"
            actionTitle = "See Heavy Apps"
            action = .open(.performance, tool: "performance.consumers")
        case "thermal":
            symbol = "thermometer.medium"
            actionTitle = "See Heavy Apps"
            action = .open(.performance, tool: "performance.consumers")
        case "cpu":
            symbol = "cpu"
            actionTitle = "See Heavy Apps"
            action = .open(.performance, tool: "performance.consumers")
        case "trash":
            symbol = "trash"
            actionTitle = "Empty Trash"
            action = .open(.toolbox, tool: "toolbox.emptyTrash")
        case "battery":
            symbol = "battery.25percent"
            actionTitle = ""
            action = .none
        default:
            symbol = "exclamationmark.triangle"
            actionTitle = ""
            action = .none
        }
        return ActivityRecommendation(id: "system.\(issue.kind)", title: issue.title, detail: issue.detail,
                                      severity: severity, symbol: symbol, actionTitle: actionTitle, action: action,
                                      penalty: max(0, issue.penalty), isSystem: true)
    }

    // MARK: History helpers

    /// Threats found by the most recent malware scan minus the threats removed since then.
    public static func unresolvedThreats(in history: ActivityHistory) -> Int {
        guard let scan = history.entries.last(where: { $0.kind == .malwareScan }) else { return 0 }
        let found = max(0, scan.count)
        guard found > 0 else { return 0 }
        let removed = history.entries
            .filter { $0.kind == .threatRemoved && $0.date >= scan.date }
            .reduce(0) { $0 + max(0, $1.count) }
        return max(0, found - removed)
    }

    /// Date of the most recent Checkup scan or run.
    public static func lastCheckup(in history: ActivityHistory) -> Date? {
        history.entries
            .filter { $0.module == .checkup && ($0.kind == .scan || $0.kind == .checkup || $0.kind == .other) }
            .map(\.date)
            .max()
    }

    /// Whole days between two dates (never negative).
    public static func days(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 86_400))
    }

    static func spokenDays(_ days: Int) -> String {
        if days >= 60 { return "\(days / 30) months" }
        if days >= 14 && days % 7 == 0 { return "\(days / 7) weeks" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    private static func clamp(_ value: Int) -> Int { min(100, max(0, value)) }
}
