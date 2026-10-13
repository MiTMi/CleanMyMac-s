import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// The menu's upkeep surfaces: the Protection card, the one suggestion card under the
// cards, and the Checkup / Tools quick actions.

// MARK: - Protection

/// Shield state (Protected / Off / Needs Access / N Threats), when the last scan ran, and
/// one action: Scan, Review, Turn On or Allow Access.
@MainActor
struct MonitorProtectionCard: View {
    var summary: MonitorProtectionSummary
    var onAction: (MonitorProtectionSummary.Action) -> Void

    var body: some View {
        let tint = summary.status == .good ? MonitorTheme.protectionTint : MonitorTheme.color(for: summary.status)
        MonitorCard(title: "Protection", symbol: "shield", tint: tint) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Image(systemName: summary.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.title)
                        .font(SpruceFont.metricS)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(summary.detail)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Protection \(summary.title), \(summary.detail)")
                Spacer(minLength: 4)
                CapsuleButton(title: summary.actionTitle, prominent: summary.status == .critical) {
                    onAction(summary.action)
                }
                .help(helpText)
            }
        }
    }

    private var helpText: String {
        switch summary.action {
        case .scan: return "Open the malware scan in Spruce"
        case .review: return "Review the threats in Spruce"
        case .turnOn: return "Switch real-time protection on"
        case .allowAccess: return "Open System Settings › Privacy & Security › Full Disk Access"
        }
    }
}

// MARK: - Suggestion card

/// Picks the menu's one suggestion card.
@MainActor
enum MonitorSuggestion {
    /// The most urgent upkeep suggestion from Mac Health (threats, Full Disk Access, a stale
    /// Checkup…) that the user hasn't snoozed or turned off — the same choices Activity
    /// uses (`ActivityAdviceStore`), so a card hidden in one place is hidden in both. Live
    /// conditions are left out: they are the header's detail lines and their cards have
    /// the actions. Without one, the weekly Checkup reminder, unless Mac Health already
    /// has a Checkup suggestion (shown or hidden), so it never nags twice.
    static func pick(report: ActivityHealthReport, advice: ActivityAdviceState, weeklyReminder: Bool,
                     now: Date = Date()) -> ActivityRecommendation? {
        let shown = report.applying(advice, now: now)
        if let recommendation = shown.recommendations.first(where: { !$0.isSystem }) {
            return recommendation
        }
        let hasCheckupSuggestion = report.allRecommendations.contains { !$0.isSystem && $0.id.hasPrefix("scan.") }
        guard !hasCheckupSuggestion,
              MonitorReminder.weeklyCheckupDue(daysSinceCheckup: report.daysSinceCheckup, enabled: weeklyReminder),
              let days = report.daysSinceCheckup else { return nil }
        let reminder = weeklyCheckup(days: days)
        return advice.hides(reminder, now: now) ? nil : reminder
    }

    /// The weekly reminder, as a Mac Health card (snoozed and turned off like the others;
    /// it takes no points off the score).
    static func weeklyCheckup(days: Int) -> ActivityRecommendation {
        ActivityRecommendation(id: MonitorReminder.weeklyCheckupID, title: MonitorReminder.weeklyCheckupTitle(days: days),
                               detail: "A quick scan finds new junk, updates and threats before they pile up.",
                               severity: .info, symbol: "calendar.badge.clock", actionTitle: "Run Checkup",
                               action: .open(.checkup, tool: "checkup.scan"), penalty: 0)
    }
}

/// Tinted icon, title, reason, one action and a ✕ menu (snooze / don't suggest again;
/// threats can't be hidden).
@MainActor
struct MonitorSuggestionCard: View {
    var suggestion: ActivityRecommendation
    var onAction: () -> Void
    var onSnooze: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        let tint = Self.color(suggestion.severity)
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: suggestion.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(SpruceFont.callout.weight(.semibold))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(suggestion.detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if suggestion.isActionable {
                    CapsuleButton(title: suggestion.actionTitle, prominent: suggestion.severity == .critical,
                                  action: onAction)
                        .padding(.top, 4)
                }
            }
            .accessibilityElement(children: .contain)
            Spacer(minLength: 0)
            if suggestion.canSnooze || suggestion.canDismiss {
                Menu {
                    if suggestion.canSnooze {
                        Button(suggestion.snoozeTitle, action: onSnooze)
                    }
                    if suggestion.canDismiss {
                        Button("Don\u{2019}t Suggest This Again", action: onDismiss)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Ink.tertiary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Hide this suggestion")
                .accessibilityLabel("Hide suggestion")
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .prismSurface(radius: Radius.row)
    }

    static func color(_ severity: ActivitySeverity) -> Color {
        switch severity {
        case .info: return StatusColor.info
        case .warning: return StatusColor.warning
        case .critical: return StatusColor.danger
        }
    }
}

// MARK: - Quick actions

/// Checkup (opens it and starts a scan — a scan never removes anything) and the Toolbox,
/// with when the last Checkup ran.
@MainActor
struct MonitorQuickActions: View {
    var checkupLine: String
    var onCheckup: () -> Void
    var onTools: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            CapsuleButton(title: "Checkup", symbol: "sparkles", action: onCheckup)
                .help("Open Checkup and start a scan")
            CapsuleButton(title: "Tools", symbol: "wrench.and.screwdriver", action: onTools)
                .help("Open the Toolbox")
            Spacer(minLength: 4)
            Text(checkupLine)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }
}
