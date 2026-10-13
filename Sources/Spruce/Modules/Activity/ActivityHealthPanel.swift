import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Health gauge on the left, recommendation cards on the right.
///
/// The score is `AppModel.healthReport`, the same one the sidebar pill shows; the user's
/// snoozed and turned-off suggestions only decide which cards are listed.
struct ActivityHealthPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let advice = ActivityAdviceStore.shared
        let report = ActivityHealthSource.report(model, advice: advice)
        GlassCard(padding: Spacing.xl) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                ActivityHealthGauge(report: report)
                    .frame(width: 210)
                ActivityRecommendationList(report: report, advice: advice)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Gauge

struct ActivityHealthGauge: View {
    var report: ActivityHealthReport

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private let lineWidth: CGFloat = 14

    var body: some View {
        let color = ActivityStyle.color(report.level)
        VStack(spacing: Spacing.m) {
            ZStack {
                Circle()
                    .stroke(Ink.controlFill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if report.isRated {
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.02, shown)))
                        .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                                startAngle: .degrees(0), endAngle: .degrees(360 * max(0.02, shown))),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(0.35 * PrismInk(contrast).glowScale), radius: 8)
                } else {
                    Circle()
                        .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
                        .padding(lineWidth / 2)
                }
                VStack(spacing: 0) {
                    Text(report.isRated ? "\(report.score)" : "–")
                        .font(SpruceFont.numeral(54))
                        .foregroundStyle(Ink.primary)
                        .contentTransition(.numericText())
                    Text(report.isRated ? report.level.title : "Measuring…")
                        .font(SpruceFont.headline)
                        .foregroundStyle(report.isRated ? color : PrismInk(contrast).tertiary)
                }
            }
            .frame(width: 170, height: 170)

            Text(report.isRated ? report.level.blurb : "Reading your Mac's vital signs…")
                .font(SpruceFont.callout)
                .foregroundStyle(PrismInk(contrast).secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.xs) {
                PrismChip(text: "System \(report.systemScore)", color: chipColor(report.systemScore), symbol: "cpu")
                    .help("Live condition: storage, memory, heat and load (the same score as the menu bar)")
                PrismChip(text: "Upkeep \(report.careScore)", color: chipColor(report.careScore), symbol: "sparkles")
                    .help("Threats, Full Disk Access and how recently your Mac was checked")
            }
            .opacity(report.isRated ? 1 : 0.5)
        }
        .frame(maxWidth: .infinity)
        .onAppear { animate(to: report.score) }
        .onChange(of: report.score) { _, newValue in animate(to: newValue) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(report.isRated
                            ? "Health: \(report.level.title), \(report.score) out of 100"
                            : "Health: measuring")
    }

    private func chipColor(_ score: Int) -> Color {
        ActivityStyle.color(ActivityHealthLevel.level(for: score))
    }

    private func animate(to score: Int) {
        let target = Double(score) / 100
        if reduceMotion {
            shown = target
        } else {
            withAnimation(Motion.countUp) { shown = target }
        }
    }
}

// MARK: - Recommendations

struct ActivityRecommendationList: View {
    var report: ActivityHealthReport
    @Bindable var advice: ActivityAdviceStore

    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var showsAll = false
    @State private var showsHidden = false

    private let collapsedCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(report.headline)
                        .font(SpruceFont.title)
                        .foregroundStyle(Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(statusLine)
                        .font(SpruceFont.callout)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                }
                Spacer(minLength: Spacing.s)
                optionsMenu
            }
            if !report.showsSuggestions {
                suggestionsOffNote
            }
            if report.recommendations.isEmpty {
                calmState
            } else {
                let visible = showsAll ? report.recommendations : Array(report.recommendations.prefix(collapsedCount))
                VStack(spacing: Spacing.s) {
                    ForEach(visible) { rec in
                        ActivityRecommendationCard(
                            recommendation: rec,
                            onAction: { ActivityHealthSource.perform(rec.action, model: model) },
                            onSnooze: { withAnimation(Motion.standard) { advice.snooze(rec) } },
                            onDismiss: { withAnimation(Motion.standard) { advice.dismiss(rec) } })
                        .transition(.opacity)
                    }
                }
                if report.recommendations.count > collapsedCount {
                    PrismTextButton(title: showsAll ? "Show fewer" : "Show all \(report.recommendations.count)",
                                    symbol: showsAll ? "chevron.up" : "chevron.down", module: .activity) {
                        withAnimation(Motion.standard) { showsAll.toggle() }
                    }
                }
            }
            if !report.hiddenRecommendations.isEmpty {
                hiddenSection
            }
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if let days = report.daysSinceCheckup {
            parts.append(days == 0 ? "Last Checkup today" : "Last Checkup \(days == 1 ? "yesterday" : "\(days) days ago")")
        } else {
            parts.append("No Checkup yet")
        }
        if let days = report.daysSinceCleanup {
            parts.append(days == 0 ? "cleaned today" : "cleaned \(days == 1 ? "yesterday" : "\(days) days ago")")
        }
        return parts.joined(separator: " · ")
    }

    /// "Show Suggestions" and "Show Hidden Suggestions Again" (also offered in Settings).
    private var optionsMenu: some View {
        Menu {
            Toggle("Show Suggestions", isOn: $advice.showSuggestions)
            Divider()
            Button("Show Hidden Suggestions Again") {
                withAnimation(Motion.standard) { advice.restoreAll() }
            }
            .disabled(advice.holdCount() == 0)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
                .foregroundStyle(PrismInk(contrast).secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Suggestion options")
        .accessibilityLabel("Suggestion options")
    }

    private var suggestionsOffNote: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "bell.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PrismInk(contrast).tertiary)
            Text("Suggestions are off. Only critical problems are listed.")
                .font(SpruceFont.caption)
                .foregroundStyle(PrismInk(contrast).secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s)
            PrismTextButton(title: "Turn On", module: .activity) {
                withAnimation(Motion.standard) { advice.showSuggestions = true }
            }
        }
    }

    private var calmState: some View {
        let hidesSome = !report.hiddenRecommendations.isEmpty
        return HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: hidesSome ? "checkmark.circle" : "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(hidesSome ? StatusColor.info : StatusColor.success)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(hidesSome ? "Nothing new needs your attention." : "Nothing needs your attention.")
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                Text(hidesSome
                     ? "The remaining suggestions are hidden. They still count toward the score until they're fixed."
                     : "Storage, memory, temperature, threats and upkeep all look fine. Suggestions appear here when something changes.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .prismSurface(radius: Radius.row, tint: hidesSome ? StatusColor.info : StatusColor.success)
    }

    /// Snoozed, turned-off and muted cards: still part of the score, listed on request.
    private var hiddenSection: some View {
        let hidden = report.hiddenRecommendations
        let now = Date()
        return VStack(alignment: .leading, spacing: Spacing.s) {
            PrismTextButton(title: hidden.count == 1 ? "1 hidden suggestion" : "\(hidden.count) hidden suggestions",
                            symbol: showsHidden ? "chevron.up" : "chevron.down", module: .activity) {
                withAnimation(Motion.standard) { showsHidden.toggle() }
            }
            .accessibilityHint(showsHidden ? "Hides the list" : "Lists suggestions you snoozed or turned off")
            if showsHidden {
                VStack(spacing: Spacing.xs) {
                    ForEach(hidden) { rec in
                        ActivityHiddenRecommendationRow(recommendation: rec, hold: advice.hold(for: rec, now: now)) {
                            withAnimation(Motion.standard) { advice.restore(rec) }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

/// One suggestion: status-tinted icon, title, reason, one action and a ⋯ menu
/// (snooze, don't suggest again, why am I seeing this?).
struct ActivityRecommendationCard: View {
    var recommendation: ActivityRecommendation
    var onAction: () -> Void
    var onSnooze: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var hovering = false
    @State private var explaining = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let tint = ActivityStyle.color(recommendation.severity)
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: recommendation.symbol)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.16)))
                .overlay(Circle().strokeBorder(tint.opacity(0.30), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.title)
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                Text(recommendation.detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.s)
            if recommendation.isActionable {
                CapsuleButton(title: recommendation.actionTitle, prominent: recommendation.severity == .critical,
                              action: onAction)
            }
            cardMenu
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .prismSurface(radius: Radius.row, highlighted: hovering)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var menuItems: some View {
        if recommendation.canSnooze {
            Button(recommendation.snoozeTitle, action: onSnooze)
        }
        if recommendation.canDismiss {
            Button("Don't Suggest This Again", action: onDismiss)
        }
        if recommendation.canSnooze || recommendation.canDismiss {
            Divider()
        }
        Button("Why Am I Seeing This?") { explaining = true }
    }

    private var cardMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? Ink.primary : PrismInk(contrast).tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(recommendation.isPinned ? "Why am I seeing this?" : "Snooze, hide or explain this suggestion")
        .accessibilityLabel("More options for \(recommendation.title)")
        .popover(isPresented: $explaining, arrowEdge: .bottom) {
            ActivityRecommendationExplanation(recommendation: recommendation)
        }
    }
}

/// "Why am I seeing this?": what triggered the card, what it costs the score and how
/// hiding it works.
struct ActivityRecommendationExplanation: View {
    var recommendation: ActivityRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Why am I seeing this?")
                .font(SpruceFont.headline)
            Text(recommendation.title)
                .font(SpruceFont.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(recommendation.explanation.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(index == 0 ? SpruceFont.callout : SpruceFont.caption)
                    .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.l)
        .frame(width: 340, alignment: .leading)
    }
}

/// A hidden suggestion: dimmed, with why it's hidden and (for snoozed or turned-off
/// cards) "Show Again".
struct ActivityHiddenRecommendationRow: View {
    var recommendation: ActivityRecommendation
    /// Nil when the card is hidden only because suggestions are off.
    var hold: ActivityAdviceHold?
    var onRestore: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.m) {
            Image(systemName: recommendation.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink.tertiary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Ink.subtleFill))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(recommendation.title)
                    .font(SpruceFont.body)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                Text(status)
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.s)
            if hold != nil {
                PrismTextButton(title: "Show Again", module: .activity, action: onRestore)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var status: String {
        guard let hold else { return "Hidden while suggestions are off" }
        guard let until = hold.until else { return "Turned off · still counts toward the score" }
        return "Snoozed · back \(until.formatted(.relative(presentation: .named)))"
    }
}
