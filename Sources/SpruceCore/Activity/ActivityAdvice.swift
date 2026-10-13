import Foundation

// MARK: - Hiding suggestions

/// Why one suggestion is hidden: snoozed until a date, or "Don't suggest this again".
public struct ActivityAdviceHold: Codable, Equatable, Sendable {
    /// End of a snooze; nil means "Don't suggest this again" (until hidden suggestions are reset).
    public var until: Date?
    /// Severity of the card when it was hidden. A more urgent version of it shows again.
    public var severity: ActivitySeverity
    /// When it was hidden.
    public var date: Date

    public init(until: Date?, severity: ActivitySeverity, date: Date) {
        self.until = until
        self.severity = severity
        self.date = date
    }

    /// True for "Don't suggest this again".
    public var isPermanent: Bool { until == nil }

    /// True while the hold still applies.
    public func isActive(at now: Date) -> Bool {
        guard let until else { return true }
        return now < until
    }
}

/// The user's choices about health suggestions (stored in `advisor.json`): which cards are
/// snoozed or turned off, and whether suggestions are shown at all.
///
/// Rules: unresolved threats can never be hidden. Critical conditions can be snoozed but not
/// turned off for good, and while suggestions are off they still show. A hidden suggestion
/// comes back as soon as it becomes more urgent than when it was hidden. Hiding a card never
/// changes the Mac Health score — the condition still counts, the card just stops nagging.
public struct ActivityAdviceState: Codable, Equatable, Sendable {
    /// Holds keyed by `ActivityRecommendation.adviceKey`.
    public var holds: [String: ActivityAdviceHold]
    /// "Show suggestions" (mirrors the vendor's assistant-recommendations switch). When off,
    /// only critical problems are listed.
    public var showSuggestions: Bool

    public init(holds: [String: ActivityAdviceHold] = [:], showSuggestions: Bool = true) {
        self.holds = holds
        self.showSuggestions = showSuggestions
    }

    private enum CodingKeys: String, CodingKey { case holds, showSuggestions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holds = (try? c.decodeIfPresent([String: ActivityAdviceHold].self, forKey: .holds)) ?? [:]
        showSuggestions = (try? c.decodeIfPresent(Bool.self, forKey: .showSuggestions)) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(holds, forKey: .holds)
        try c.encode(showSuggestions, forKey: .showSuggestions)
    }

    // MARK: Queries

    /// The hold that currently applies to `recommendation`, if any (ignores expired snoozes,
    /// cards that became more urgent and cards that can't be hidden).
    public func hold(for recommendation: ActivityRecommendation, now: Date) -> ActivityAdviceHold? {
        guard recommendation.canSnooze || recommendation.canDismiss,
              let hold = holds[recommendation.adviceKey], hold.isActive(at: now),
              recommendation.severity <= hold.severity else { return nil }
        // A permanent hold on a card that can't be turned off (forged or outdated file) is ignored.
        if hold.isPermanent && !recommendation.canDismiss { return nil }
        return hold
    }

    /// True when the card should not be listed: snoozed, turned off, or muted because
    /// suggestions are off. Threats are always listed.
    public func hides(_ recommendation: ActivityRecommendation, now: Date) -> Bool {
        if recommendation.isPinned { return false }
        if !showSuggestions && recommendation.severity < .critical { return true }
        return hold(for: recommendation, now: now) != nil
    }

    /// Holds that still apply (expired snoozes left out).
    public func activeHolds(now: Date) -> [String: ActivityAdviceHold] {
        holds.filter { $0.value.isActive(at: now) }
    }

    /// Copy without expired snoozes.
    public func pruned(now: Date) -> ActivityAdviceState {
        var copy = self
        copy.holds = activeHolds(now: now)
        return copy
    }

    // MARK: Changes

    /// "Snooze": hides the card for `recommendation.snoozeDays`. No effect on threats.
    public mutating func snooze(_ recommendation: ActivityRecommendation, now: Date) {
        guard recommendation.canSnooze, let days = recommendation.snoozeDays else { return }
        holds[recommendation.adviceKey] = ActivityAdviceHold(
            until: now.addingTimeInterval(TimeInterval(days) * 86_400),
            severity: recommendation.severity, date: now)
        holds = activeHolds(now: now)
    }

    /// "Don't suggest this again". No effect on threats or critical conditions.
    public mutating func dismiss(_ recommendation: ActivityRecommendation, now: Date) {
        guard recommendation.canDismiss else { return }
        holds[recommendation.adviceKey] = ActivityAdviceHold(until: nil, severity: recommendation.severity, date: now)
        holds = activeHolds(now: now)
    }

    /// Shows one hidden card again.
    public mutating func restore(_ recommendation: ActivityRecommendation) {
        holds[recommendation.adviceKey] = nil
    }

    /// "Reset hidden suggestions".
    public mutating func restoreAll() {
        holds = [:]
    }
}

// MARK: - Per-card rules

public extension ActivityRecommendation {
    /// Key a hold is stored under. The Checkup reminders share one key, so turning off
    /// "It's been 2 weeks since your last Checkup" also covers the next reminder unless it
    /// is more urgent.
    var adviceKey: String {
        if id.hasPrefix("scan.") { return "scan" }
        return id
    }

    /// Unresolved threats are always listed.
    var isPinned: Bool { id.hasPrefix("threat.") }

    /// "Snooze" is offered for everything except threats.
    var canSnooze: Bool { !isPinned && snoozeDays != nil }

    /// "Don't suggest this again" is offered for everything except threats and critical conditions.
    var canDismiss: Bool { !isPinned && severity < .critical }

    /// How long "Snooze" hides the card: a day for live conditions that change quickly,
    /// longer for upkeep reminders. Nil when the card can't be snoozed.
    var snoozeDays: Int? {
        if isPinned { return nil }
        switch id {
        case "system.disk", "system.memory", "system.swap", "system.thermal", "system.cpu": return 1
        case "system.battery": return 30
        case "fda.missing": return 3
        default: return 7
        }
    }

    /// Menu title for the snooze command ("Snooze for a Day", "Snooze for a Week"…).
    var snoozeTitle: String {
        switch snoozeDays {
        case 1?: return "Snooze for a Day"
        case 7?: return "Snooze for a Week"
        case let days?: return "Snooze for \(days) Days"
        case nil: return "Snooze"
        }
    }

    /// "a day", "a week", "3 days".
    static func spokenSnooze(_ days: Int) -> String {
        switch days {
        case 1: return "a day"
        case 7: return "a week"
        default: return "\(days) days"
        }
    }

    /// "Why am I seeing this?": what triggered the card, what it does to the score, and how
    /// hiding it works. One string per paragraph.
    var explanation: [String] {
        var paragraphs: [String] = []
        var trigger = triggerExplanation
        if penalty > 0 {
            trigger += " It takes \(penalty) \(penalty == 1 ? "point" : "points") off your Mac Health score"
            trigger += capExplanation.map { "; \($0)" } ?? "."
        } else if let cap = capExplanation {
            trigger += " " + String(cap.prefix(1)).uppercased() + String(cap.dropFirst())
        }
        paragraphs.append(trigger)
        if isPinned {
            paragraphs.append("Threats can't be snoozed or hidden. The card goes away once the threats are removed or a new malware scan comes back clean.")
        } else if canSnooze || canDismiss {
            var hiding: [String] = []
            if let days = snoozeDays {
                hiding.append("Snoozing hides it for \(Self.spokenSnooze(days)).")
            }
            if canDismiss {
                hiding.append("\"Don't Suggest This Again\" hides it until you show hidden suggestions again.")
            } else {
                hiding.append("Critical problems can be snoozed but not turned off.")
            }
            hiding.append("Either way it returns if it becomes more urgent, and it still counts toward the score while hidden.")
            paragraphs.append(hiding.joined(separator: " "))
        }
        return paragraphs
    }

    private var triggerExplanation: String {
        switch id {
        case "threat.active":
            return "Your last malware scan found threats that haven't been removed since."
        case "fda.missing":
            return "macOS hasn't given Spruce Full Disk Access, so Mail, Safari, Messages and other protected folders are skipped by every scan."
        case "scan.never":
            return "No Checkup has been run on this Mac yet, so junk, threats, updates and clutter haven't been rated."
        case "scan.overdue":
            return "Your last Checkup was \(ActivityHealth.checkupOverdueDays) or more days ago."
        case "scan.stale":
            return "Your last Checkup was \(ActivityHealth.checkupStaleDays) or more days ago."
        case "cleanup.stale":
            return "Nothing has been cleaned in the last \(ActivityHealth.cleanupStaleDays) days, and caches, logs and leftovers grow back over time."
        case "protection.off":
            return "Real-time protection is turned off in Settings, so new login items and downloads aren't checked as they appear."
        default:
            if isSystem {
                return "The menu bar monitor measures this live. The suggestion goes away by itself as soon as the condition clears."
            }
            return detail
        }
    }

    /// The band limit this factor imposes, lowercase (it follows a semicolon), if any.
    private var capExplanation: String? {
        switch id {
        case "threat.active": return "while threats remain, Mac Health stays Critical."
        case "fda.missing": return "until access is allowed, the score can't go above Fair."
        case "scan.never", "scan.overdue": return "until you run a Checkup, the score can't go above Fair."
        case "scan.stale": return "until you run a Checkup, the score can't go above Good."
        default: return nil
        }
    }
}
