import Foundation

// Pure logic behind the menu's Protection card and its weekly Checkup reminder. (The
// suggestion card's snoozes are Mac Health's own, `ActivityAdviceState`.)

// MARK: - Protection card

/// What the menu's Protection card shows: one state word, a status line and at most one
/// action, from real-time protection, Full Disk Access, the last malware scan and the
/// threats it left behind.
public struct MonitorProtectionSummary: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case protected
        /// Real-time protection is switched off.
        case off
        /// Scans can't reach protected folders without Full Disk Access.
        case needsAccess
        /// Threats found by the last scan that are still on the Mac.
        case threats(Int)
    }

    public enum Action: String, Sendable, Equatable {
        /// Open the malware scan.
        case scan
        /// Open the malware results.
        case review
        /// Switch real-time protection on.
        case turnOn
        /// Open System Settings › Full Disk Access.
        case allowAccess
    }

    public var state: State
    public var realtimeEnabled: Bool
    public var lastScan: Date?
    public var now: Date

    /// Threats come first, then real-time protection being off, then missing access.
    public init(realtimeEnabled: Bool, hasFullDiskAccess: Bool, unresolvedThreats: Int, lastScan: Date?,
                now: Date = Date()) {
        if unresolvedThreats > 0 {
            state = .threats(unresolvedThreats)
        } else if !realtimeEnabled {
            state = .off
        } else if !hasFullDiskAccess {
            state = .needsAccess
        } else {
            state = .protected
        }
        self.realtimeEnabled = realtimeEnabled
        self.lastScan = lastScan
        self.now = now
    }

    /// The big value: "Protected", "Off", "Needs Access", "2 Threats".
    public var title: String {
        switch state {
        case .protected: return "Protected"
        case .off: return "Off"
        case .needsAccess: return "Needs Access"
        case .threats(let count): return count == 1 ? "1 Threat" : "\(count) Threats"
        }
    }

    /// "Real-time on · scanned 2 d ago".
    public var detail: String {
        let scanned = lastScan.map { "scanned " + MonitorFormat.ago(now.timeIntervalSince($0)) } ?? "not scanned yet"
        switch state {
        case .protected: return "Real-time on · \(scanned)"
        case .off: return "Real-time protection is off · \(scanned)"
        case .needsAccess: return "Scans skip protected folders · \(scanned)"
        case .threats: return lastScan.map { "Found \(MonitorFormat.ago(now.timeIntervalSince($0)))" } ?? "Found by the last scan"
        }
    }

    public var status: MonitorHealthStatus {
        switch state {
        case .protected: return .good
        case .off, .needsAccess: return .attention
        case .threats: return .critical
        }
    }

    public var action: Action {
        switch state {
        case .protected: return .scan
        case .off: return .turnOn
        case .needsAccess: return .allowAccess
        case .threats: return .review
        }
    }

    public var actionTitle: String {
        switch action {
        case .scan: return "Scan"
        case .review: return "Review"
        case .turnOn: return "Turn On"
        case .allowAccess: return "Allow Access"
        }
    }

    /// SF Symbol for the shield glyph.
    public var symbol: String {
        switch state {
        case .protected: return "checkmark.shield.fill"
        case .off: return "shield.slash"
        case .needsAccess: return "lock.shield"
        case .threats: return "exclamationmark.shield.fill"
        }
    }
}

// MARK: - Weekly Checkup reminder

/// The weekly Checkup reminder card (Settings › Notifications › weekly reminder): shown in
/// the menu when the last Checkup is a week old and Mac Health has no stronger suggestion.
public enum MonitorReminder {
    public static let weeklyCheckupID = "monitor.weeklyCheckup"
    public static let weeklyCheckupDays = 7

    public static func weeklyCheckupDue(daysSinceCheckup: Int?, enabled: Bool) -> Bool {
        guard enabled, let days = daysSinceCheckup else { return false }
        return days >= weeklyCheckupDays
    }

    public static func weeklyCheckupTitle(days: Int) -> String {
        days < 14 ? "Your weekly Checkup is due" : "It's been \(days) days since your last Checkup"
    }
}
