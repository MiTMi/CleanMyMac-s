import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Health gauge on the left, recommendation cards on the right.
struct ActivityHealthPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let report = ActivityHealth.assess(ActivityHealthSource.input(model))
        GlassCard(padding: Spacing.xl) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                ActivityHealthGauge(report: report)
                    .frame(width: 210)
                ActivityRecommendationList(report: report)
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

    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var showsAll = false

    private let collapsedCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(report.headline)
                    .font(SpruceFont.title)
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(statusLine)
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).tertiary)
            }
            if report.recommendations.isEmpty {
                calmState
            } else {
                let visible = showsAll ? report.recommendations : Array(report.recommendations.prefix(collapsedCount))
                VStack(spacing: Spacing.s) {
                    ForEach(visible) { rec in
                        ActivityRecommendationCard(recommendation: rec) {
                            ActivityHealthSource.perform(rec.action, model: model)
                        }
                    }
                }
                if report.recommendations.count > collapsedCount {
                    PrismTextButton(title: showsAll ? "Show fewer" : "Show all \(report.recommendations.count)",
                                    symbol: showsAll ? "chevron.up" : "chevron.down", module: .activity) {
                        withAnimation(Motion.standard) { showsAll.toggle() }
                    }
                }
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

    private var calmState: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(StatusColor.success)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Nothing needs your attention.")
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                Text("Storage, memory, temperature, threats and upkeep all look fine. Suggestions appear here when something changes.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .prismSurface(radius: Radius.row, tint: StatusColor.success)
    }
}

/// One suggestion: status-tinted icon, title, reason and one action.
struct ActivityRecommendationCard: View {
    var recommendation: ActivityRecommendation
    var onAction: () -> Void

    @State private var hovering = false
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
            Spacer(minLength: Spacing.s)
            if recommendation.isActionable {
                CapsuleButton(title: recommendation.actionTitle, prominent: recommendation.severity == .critical,
                              action: onAction)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .prismSurface(radius: Radius.row, highlighted: hovering)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .combine)
    }
}
