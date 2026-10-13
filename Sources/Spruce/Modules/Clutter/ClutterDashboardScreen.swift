import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Results overview: how many files might be worth a look, one tile per tool (largest
/// first) and the selection footer for everything selected across tools.
struct ClutterDashboardScreen: View {
    @Bindable var screen: ClutterScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.m) {
            header
            if let report = screen.report, report.isEmpty {
                EmptyStateView(module: .clutter, title: "Nothing to sort through",
                               message: emptyMessage(report), actionTitle: "New Scan",
                               action: { screen.newScan() })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        notices
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.m),
                                            GridItem(.flexible(), spacing: Spacing.m)],
                                  spacing: Spacing.m) {
                            ForEach(orderedTools) { tool in
                                ClutterToolTile(screen: screen, tool: tool)
                            }
                        }
                    }
                    .padding(.bottom, Spacing.s)
                }
                .scrollIndicators(.automatic)
                ClutterToolFooter(screen: screen, tool: nil)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var header: some View {
        let ink = PrismInk(contrast)
        return HStack(alignment: .center, spacing: Spacing.m) {
            HeroLens(module: .clutter, size: 52, parallax: false)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(SpruceFont.display(28))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Text(subheadline)
                    .font(SpruceFont.callout.monospacedDigit())
                    .foregroundStyle(ink.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Spacing.m)
            CapsuleButton(title: "New Scan", symbol: "arrow.counterclockwise") {
                screen.confirmNewScan = true
            }
            .help("Discard these results and choose where to look again")
        }
    }

    private var headline: String {
        let count = screen.report?.distinctFileCount ?? 0
        if count == 0 { return "Nothing to sort through" }
        return "\(CountFormat.items(count, singular: "file")) might be worth a look"
    }

    private var subheadline: String {
        guard let report = screen.report else { return "" }
        var parts = ["\(ByteFormat.string(report.distinctBytes)) in total"]
        if report.scannedTools.contains(.largeOld) || report.scannedTools.contains(.duplicates)
            || report.scannedTools.contains(.similarImages) {
            parts.append("looked in \(screen.locationSummary(report.locations))")
        }
        parts.append("scanned \(report.date.formatted(date: .omitted, time: .shortened))")
        return parts.joined(separator: " · ") + ". Review each group, or pick quick suggestions."
    }

    private func emptyMessage(_ report: ClutterScanReport) -> String {
        if report.filesExamined > 0 {
            return "Spruce looked at \(CountFormat.items(report.filesExamined, singular: "file")) in \(screen.locationSummary(report.locations)) and found no large, old, duplicate or similar files."
        }
        return "No large, old, duplicate or similar files turned up here."
    }

    /// Tools with the most to free first; tools not scanned yet go last.
    private var orderedTools: [ClutterTool] {
        let summaries = Dictionary(uniqueKeysWithValues: ClutterTool.allCases.map { ($0, screen.summary(for: $0)) })
        return ClutterTool.allCases.sorted { a, b in
            let scannedA = screen.wasScanned(a), scannedB = screen.wasScanned(b)
            if scannedA != scannedB { return scannedA }
            let bytesA = summaries[a]?.reclaimableBytes ?? 0, bytesB = summaries[b]?.reclaimableBytes ?? 0
            if bytesA != bytesB { return bytesA > bytesB }
            return (ClutterTool.allCases.firstIndex(of: a) ?? 0) < (ClutterTool.allCases.firstIndex(of: b) ?? 0)
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let report = screen.report {
            if report.wasStopped {
                ClutterNotice(symbol: "exclamationmark.triangle.fill", tint: StatusColor.warning,
                              text: "The scan stopped early, so some files may be missing from these results.")
            }
            if report.skippedPlaceholders > 0 {
                ClutterNotice(symbol: "icloud", tint: StatusColor.info,
                              text: "\(CountFormat.items(report.skippedPlaceholders, singular: "file")) stored only in the cloud \(report.skippedPlaceholders == 1 ? "was" : "were") skipped. \(report.skippedPlaceholders == 1 ? "It takes" : "They take") no space on this Mac.")
            }
        }
    }
}

/// One-line informational banner.
struct ClutterNotice: View {
    var symbol: String
    var tint: Color
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 10)
        .prismSurface(radius: Radius.row, tint: tint)
    }
}

/// A dashboard tile: tool badge, headline ("412 duplicates found"), the other metric,
/// thumbnails of what was found, the selection in that tool and Review.
struct ClutterToolTile: View {
    @Bindable var screen: ClutterScreenModel
    var tool: ClutterTool

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let scanned = screen.wasScanned(tool)
        let summary = screen.summary(for: tool)
        GlassCard(padding: Spacing.l, isHighlighted: hovering) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .center, spacing: Spacing.m) {
                    PrismCategoryBadge(symbol: tool.symbol, module: .clutter, size: 34, isDimmed: scanned && summary.isEmpty)
                    Text(tool.title.uppercased())
                        .font(SpruceFont.overline)
                        .tracking(0.8)
                        .foregroundStyle(ink.tertiary)
                    Spacer(minLength: Spacing.s)
                    if scanned && !summary.isEmpty {
                        selectionChip
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(scanned ? summary.headline : "Not scanned yet")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(scanned ? summary.detail : tool.summary)
                        .font(SpruceFont.callout.monospacedDigit())
                        .foregroundStyle(ink.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: Spacing.s) {
                    thumbnails
                    Spacer(minLength: Spacing.s)
                    if !scanned {
                        CapsuleButton(title: "Scan", symbol: "magnifyingglass", prominent: true) { screen.open(tool) }
                    } else if !summary.isEmpty {
                        CapsuleButton(title: "Review", symbol: "arrow.right", prominent: true) { screen.open(tool) }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            if !scanned || !summary.isEmpty { screen.open(tool) }
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var selectionChip: some View {
        let count = screen.selectedPaths(in: tool).count
        let bytes = screen.selectedBytes(in: tool)
        return Group {
            if count > 0 {
                PrismChip(text: "\(ByteFormat.string(bytes)) selected", color: ModuleID.clutter.palette.accent,
                          symbol: "checkmark")
            } else {
                PrismChip(text: "Nothing selected", color: Color.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var thumbnails: some View {
        let paths = screen.samplePaths(for: tool, limit: 5)
        if paths.isEmpty {
            Color.clear.frame(height: 44)
        } else {
            HStack(spacing: -10) {
                ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                    ClutterThumbnail(path: path, side: 44, symbol: screen.filesByPath[path]?.kind.symbol ?? tool.symbol,
                                     fills: tool == .duplicates || tool == .similarImages)
                        .shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)
                        .zIndex(Double(paths.count - index))
                }
            }
        }
    }
}
