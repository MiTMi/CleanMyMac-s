import Foundation

/// A transparent "time saved" estimate: for each recorded action, the time doing it by
/// hand would take (finding the folders, running the commands, hunting for leftovers),
/// capped per day so one big cleanup can't claim a week.
///
/// The constants are deliberately conservative and listed in the UI next to the result
/// so the number can be checked.
public enum ActivityTimeSaved {
    /// No day counts for more than this.
    public static let dailyCap: TimeInterval = 3 * 3600

    /// Manual-effort constants, in seconds.
    public enum Constant {
        public static let checkup: TimeInterval = 600
        public static let cleanup: TimeInterval = 45
        /// Extra second per this many items cleaned.
        public static let itemsPerSecond = 200
        public static let malwareScan: TimeInterval = 300
        public static let threatRemoved: TimeInterval = 600
        public static let maintenanceTask: TimeInterval = 120
        public static let uninstall: TimeInterval = 180
        public static let appUpdate: TimeInterval = 60
        public static let startupItem: TimeInterval = 60
        public static let cloudItem: TimeInterval = 5
        public static let cloudSessionCap: TimeInterval = 600
    }

    /// One line of the "How we estimate" breakdown.
    public struct Line: Identifiable, Equatable, Sendable {
        public var kind: ActivityEntry.Kind
        public var id: String { kind.rawValue }
        /// Actions of this kind (runs, threats, apps, tasks…).
        public var count: Int
        public var seconds: TimeInterval
        /// "3 uninstalls × 3 min".
        public var explanation: String

        public init(kind: ActivityEntry.Kind, count: Int, seconds: TimeInterval, explanation: String) {
            self.kind = kind
            self.count = count
            self.seconds = seconds
            self.explanation = explanation
        }
    }

    public struct Estimate: Equatable, Sendable {
        /// Seconds after the daily cap.
        public var total: TimeInterval
        /// Seconds before the daily cap.
        public var uncapped: TimeInterval
        /// Largest contribution first.
        public var lines: [Line]

        public init(total: TimeInterval, uncapped: TimeInterval, lines: [Line]) {
            self.total = total
            self.uncapped = uncapped
            self.lines = lines
        }

        public var wasCapped: Bool { uncapped > total + 0.5 }
    }

    /// Seconds credited to one entry, and how many "actions" it represents.
    public static func credit(for entry: ActivityEntry) -> (seconds: TimeInterval, actions: Int) {
        let count = max(0, entry.count)
        switch entry.kind {
        case .checkup:
            return (Constant.checkup, 1)
        case .other where entry.module == .checkup:
            return (Constant.checkup, 1)
        case .clean:
            return (Constant.cleanup + TimeInterval(count / Constant.itemsPerSecond), 1)
        case .malwareScan:
            return (Constant.malwareScan, 1)
        case .threatRemoved:
            let n = max(1, count)
            return (Constant.threatRemoved * TimeInterval(n), n)
        case .maintenance:
            let n = max(1, count)
            return (Constant.maintenanceTask * TimeInterval(n), n)
        case .uninstall:
            return (Constant.uninstall, 1)
        case .update:
            let n = max(1, count)
            return (Constant.appUpdate * TimeInterval(n), n)
        case .startupItems:
            let n = max(1, count)
            return (Constant.startupItem * TimeInterval(n), n)
        case .cloudFreed:
            let n = max(1, count)
            return (min(Constant.cloudSessionCap, Constant.cloudItem * TimeInterval(n)), n)
        case .scan, .other:
            // A scan alone doesn't save effort until something is acted on.
            return (0, 0)
        }
    }

    /// Estimate for a set of entries (any period).
    public static func estimate(_ entries: [ActivityEntry], calendar: Calendar = ActivityMonthly.calendar()) -> Estimate {
        var perDay: [Date: TimeInterval] = [:]
        var perKind: [ActivityEntry.Kind: (count: Int, seconds: TimeInterval)] = [:]
        var uncapped: TimeInterval = 0
        for entry in entries {
            let credit = credit(for: entry)
            guard credit.seconds > 0 else { continue }
            uncapped += credit.seconds
            perDay[calendar.startOfDay(for: entry.date), default: 0] += credit.seconds
            let kind = entry.kind == .other ? ActivityEntry.Kind.checkup : entry.kind
            let current = perKind[kind] ?? (count: 0, seconds: 0)
            perKind[kind] = (count: current.count + credit.actions, seconds: current.seconds + credit.seconds)
        }
        let total = perDay.values.reduce(0) { $0 + min(dailyCap, $1) }
        let lines = perKind.map { kind, value in
            Line(kind: kind, count: value.count, seconds: value.seconds, explanation: explanation(kind, count: value.count))
        }.sorted { a, b in a.seconds != b.seconds ? a.seconds > b.seconds : a.kind.rawValue < b.kind.rawValue }
        return Estimate(total: total, uncapped: uncapped, lines: lines)
    }

    /// "≈ 2 h 40 min", "≈ 5 min", "None yet".
    public static func formatted(_ seconds: TimeInterval) -> String {
        if seconds < 30 { return "None yet" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "≈ \(max(1, minutes)) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "≈ \(hours) h" : "≈ \(hours) h \(rest) min"
    }

    static func explanation(_ kind: ActivityEntry.Kind, count: Int) -> String {
        func each(_ seconds: TimeInterval) -> String { DurationFormat.short(seconds) }
        switch kind {
        case .checkup, .other:
            return "\(CountFormat.items(count, singular: "Checkup")) × \(each(Constant.checkup))"
        case .clean:
            return "\(CountFormat.items(count, singular: "cleanup")) × \(each(Constant.cleanup)), plus 1 s per \(Constant.itemsPerSecond) items"
        case .malwareScan:
            return "\(CountFormat.items(count, singular: "malware scan")) × \(each(Constant.malwareScan))"
        case .threatRemoved:
            return "\(CountFormat.items(count, singular: "threat")) removed × \(each(Constant.threatRemoved))"
        case .maintenance:
            return "\(CountFormat.items(count, singular: "maintenance task")) × \(each(Constant.maintenanceTask))"
        case .uninstall:
            return "\(CountFormat.items(count, singular: "uninstall")) × \(each(Constant.uninstall))"
        case .update:
            return "\(CountFormat.items(count, singular: "app update")) × \(each(Constant.appUpdate))"
        case .startupItems:
            return "\(CountFormat.items(count, singular: "startup item")) × \(each(Constant.startupItem))"
        case .cloudFreed:
            return "\(CountFormat.items(count, singular: "cloud file")) × \(each(Constant.cloudItem)) (at most \(each(Constant.cloudSessionCap)) per session)"
        case .scan:
            return "Scans"
        }
    }
}
