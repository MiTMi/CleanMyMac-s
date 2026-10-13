import Foundation

// MARK: - Monthly statistics

/// Activity totals for one calendar month.
public struct ActivityMonthStats: Identifiable, Equatable, Sendable {
    /// First instant of the month in the calendar used for aggregation.
    public var start: Date
    public var id: Date { start }
    /// Disk space our app removed or moved out (cleanups, uninstalls, threats, startup items).
    public var bytesFreed: Int64 = 0
    /// Space freed in cloud storage.
    public var cloudFreed: Int64 = 0
    /// Threats reported by malware scans in the month.
    public var threatsFound: Int = 0
    public var threatsRemoved: Int = 0
    public var malwareScans: Int = 0
    /// Items surfaced by scans (files, apps, launch items…).
    public var itemsScanned: Int = 0
    public var scans: Int = 0
    public var checkups: Int = 0
    public var cleanups: Int = 0
    public var uninstalls: Int = 0
    public var appsUpdated: Int = 0
    public var tasksRun: Int = 0
    /// Estimated manual effort saved (see `ActivityTimeSaved`).
    public var timeSaved: TimeInterval = 0
    public var entryCount: Int = 0

    public init(start: Date) { self.start = start }

    /// True when nothing at all was recorded.
    public var isEmpty: Bool { entryCount == 0 }
}

/// Month-over-month change for a stat tile.
public enum ActivityDelta: Equatable, Sendable {
    /// Both months are zero.
    case none
    /// The previous month was zero.
    case new
    case same
    case up(Int)
    case down(Int)

    /// Percentage change from `previous` to `current`.
    public static func percent(current: Double, previous: Double) -> ActivityDelta {
        if current <= 0 && previous <= 0 { return .none }
        if previous <= 0 { return .new }
        let change = (current - previous) / previous * 100
        let rounded = Int(change.rounded())
        if rounded == 0 { return .same }
        return rounded > 0 ? .up(rounded) : .down(-rounded)
    }

    /// Absolute change for counters ("+3", "−2").
    public static func absolute(current: Int, previous: Int) -> ActivityDelta {
        if current == 0 && previous == 0 { return .none }
        if current == previous { return .same }
        return current > previous ? .up(current - previous) : .down(previous - current)
    }

    /// Short chip text: "▲ 18%", "▼ 4%", "New", "Same".
    public func label(percent: Bool = true) -> String? {
        switch self {
        case .none: return nil
        case .new: return "New"
        case .same: return "Same"
        case .up(let v): return percent ? "▲ \(v)%" : "+\(CountFormat.grouped(v))"
        case .down(let v): return percent ? "▼ \(v)%" : "−\(CountFormat.grouped(v))"
        }
    }
}

/// Aggregates `ActivityHistory` into calendar months.
public enum ActivityMonthly {
    /// A Gregorian calendar in the given time zone (the current one by default).
    public static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Start of the month containing `date`.
    public static func monthStart(of date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// The last `count` months ending with the month containing `now`, oldest first.
    /// Months without activity are included (all zeros).
    public static func months(_ history: ActivityHistory, count: Int = 6, now: Date = Date(),
                              calendar: Calendar = ActivityMonthly.calendar()) -> [ActivityMonthStats] {
        guard count > 0 else { return [] }
        let current = monthStart(of: now, calendar: calendar)
        var starts: [Date] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            if let start = calendar.date(byAdding: .month, value: -offset, to: current) {
                starts.append(start)
            }
        }
        var stats = starts.map { ActivityMonthStats(start: $0) }
        var index: [Date: Int] = [:]
        for (i, s) in stats.enumerated() { index[s.start] = i }

        var byMonth: [Int: [ActivityEntry]] = [:]
        for entry in history.entries {
            let key = monthStart(of: entry.date, calendar: calendar)
            guard let i = index[key] else { continue }
            byMonth[i, default: []].append(entry)
        }
        for (i, entries) in byMonth {
            stats[i] = aggregate(entries, start: stats[i].start, calendar: calendar)
        }
        return stats
    }

    /// Totals for one month's entries.
    public static func aggregate(_ entries: [ActivityEntry], start: Date, calendar: Calendar) -> ActivityMonthStats {
        var s = ActivityMonthStats(start: start)
        for e in entries {
            s.entryCount += 1
            let bytes = max(0, e.bytes)
            let count = max(0, e.count)
            switch e.kind {
            case .clean:
                s.bytesFreed += bytes
                s.cleanups += 1
            case .uninstall:
                s.bytesFreed += bytes
                s.uninstalls += 1
            case .threatRemoved:
                s.bytesFreed += bytes
                s.threatsRemoved += count
            case .startupItems:
                s.bytesFreed += bytes
            case .cloudFreed:
                s.cloudFreed += bytes
            case .malwareScan:
                s.malwareScans += 1
                s.threatsFound += count
            case .scan:
                s.scans += 1
                s.itemsScanned += count
            case .checkup:
                s.checkups += 1
            case .maintenance:
                // Maintenance bytes are memory or purgeable space, not deleted data.
                s.tasksRun += max(1, count)
            case .update:
                s.appsUpdated += max(1, count)
            case .other:
                if e.module == .checkup { s.checkups += 1 }
            }
        }
        s.timeSaved = ActivityTimeSaved.estimate(entries, calendar: calendar).total
        return s
    }

    /// Totals over every recorded entry.
    public static func allTime(_ history: ActivityHistory, calendar: Calendar = ActivityMonthly.calendar()) -> ActivityMonthStats {
        let start = history.entries.map(\.date).min() ?? Date(timeIntervalSince1970: 0)
        return aggregate(history.entries, start: start, calendar: calendar)
    }

    /// Short month name ("Oct") and full title ("October 2026").
    public static func shortName(_ start: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: start)
        return shortMonthNames[(month - 1 + 12) % 12]
    }

    public static func title(_ start: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: start)
        let year = calendar.component(.year, from: start)
        return "\(monthNames[(month - 1 + 12) % 12]) \(year)"
    }

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                             "September", "October", "November", "December"]
    static let shortMonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

// MARK: - Entry presentation

public extension ActivityEntry.Kind {
    /// Timeline label for the kind.
    var activityTitle: String {
        switch self {
        case .scan: return "Scan"
        case .clean: return "Cleanup"
        case .malwareScan: return "Malware scan"
        case .threatRemoved: return "Threats removed"
        case .maintenance: return "Maintenance"
        case .uninstall: return "Uninstall"
        case .update: return "App updates"
        case .cloudFreed: return "Cloud space freed"
        case .other: return "Activity"
        case .checkup: return "Checkup"
        case .startupItems: return "Startup items"
        }
    }

    /// SF Symbol for the timeline.
    var activitySymbol: String {
        switch self {
        case .scan: return "magnifyingglass"
        case .clean: return "bubbles.and.sparkles"
        case .malwareScan: return "shield.lefthalf.filled"
        case .threatRemoved: return "checkmark.shield"
        case .maintenance: return "wrench.adjustable"
        case .uninstall: return "trash.square"
        case .update: return "arrow.down.circle"
        case .cloudFreed: return "icloud"
        case .other: return "circle.dashed"
        case .checkup: return "sparkles"
        case .startupItems: return "power"
        }
    }
}

/// A day of the recent-activity timeline.
public struct ActivityTimelineDay: Identifiable, Equatable, Sendable {
    public var day: Date
    public var id: Date { day }
    /// Newest first.
    public var entries: [ActivityEntry]

    public init(day: Date, entries: [ActivityEntry]) {
        self.day = day
        self.entries = entries
    }
}

public enum ActivityTimeline {
    /// The newest `limit` entries grouped by calendar day, newest day first.
    public static func recent(_ history: ActivityHistory, limit: Int = 30,
                              calendar: Calendar = ActivityMonthly.calendar()) -> [ActivityTimelineDay] {
        let newest = history.entries.sorted { $0.date > $1.date }.prefix(max(0, limit))
        var days: [ActivityTimelineDay] = []
        for entry in newest {
            let day = calendar.startOfDay(for: entry.date)
            if let last = days.last, last.day == day {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(ActivityTimelineDay(day: day, entries: [entry]))
            }
        }
        return days
    }

    /// "Today", "Yesterday", or "Mon, Oct 5" (plus the year when it differs).
    public static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = ActivityMonthly.calendar()) -> String {
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: day)
        if start == today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), start == yesterday { return "Yesterday" }
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let weekday = weekdays[(calendar.component(.weekday, from: start) - 1 + 7) % 7]
        let month = ActivityMonthly.shortName(start, calendar: calendar)
        let dayNumber = calendar.component(.day, from: start)
        let year = calendar.component(.year, from: start)
        let base = "\(weekday), \(month) \(dayNumber)"
        return year == calendar.component(.year, from: today) ? base : "\(base), \(year)"
    }

    /// "14:05" in the calendar's time zone.
    public static func timeLabel(_ date: Date, calendar: Calendar = ActivityMonthly.calendar()) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        func pad(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        return "\(pad(hour)):\(pad(minute))"
    }
}

// MARK: - Operations log

/// One parsed line of `OperationLog` (tab separated: date, module, action, result, bytes, detail).
public struct ActivityLogLine: Identifiable, Equatable, Sendable {
    public var id: Int
    public var date: Date?
    public var dateText: String
    public var module: String
    public var action: String
    public var result: String
    public var bytes: Int64
    public var detail: String

    public init(id: Int, date: Date?, dateText: String, module: String, action: String, result: String,
                bytes: Int64, detail: String) {
        self.id = id
        self.date = date
        self.dateText = dateText
        self.module = module
        self.action = action
        self.result = result
        self.bytes = bytes
        self.detail = detail
    }

    /// True for successful operations.
    public var isSuccess: Bool { result == "ok" }

    /// Parses one log line; lines that don't have the expected shape are kept as detail text.
    public static func parse(_ line: String, id: Int) -> ActivityLogLine {
        let fields = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6 else {
            return ActivityLogLine(id: id, date: nil, dateText: "", module: "", action: "", result: "",
                                   bytes: 0, detail: line)
        }
        let formatter = ISO8601DateFormatter()
        return ActivityLogLine(id: id, date: formatter.date(from: fields[0]), dateText: fields[0], module: fields[1],
                               action: fields[2], result: fields[3], bytes: Int64(fields[4]) ?? 0, detail: fields[5])
    }

    /// Parses lines as returned by `OperationLog.tail()` (oldest first) and returns newest first.
    public static func parseAll(_ lines: [String]) -> [ActivityLogLine] {
        lines.enumerated().map { parse($0.element, id: $0.offset) }.reversed()
    }

    /// Matches the query against module, action, result and detail (case-insensitive).
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return [module, action, result, detail, dateText].contains { $0.lowercased().contains(q) }
    }
}
