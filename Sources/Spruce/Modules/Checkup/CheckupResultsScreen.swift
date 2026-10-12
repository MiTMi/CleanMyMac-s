import Accessibility
import SpruceCore
import SpruceMac
import SwiftUI

/// Results: a 3 × 2 grid of the five area tiles plus a Summary tile, Start Over in the
/// header, a review sheet per tile and the Run orb. Nothing runs until Run is pressed.
@MainActor
struct CheckupResultsScreen: View {
    let session: CheckupSession
    var onScanAgain: () -> Void

    @Environment(AppModel.self) private var model
    @State private var reviewModule: ModuleID?
    @State private var confirmStartOver = false

    var body: some View {
        let tiles = session.tiles
        let summary = session.summary
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ScreenHeader(title: CheckupCopy.resultsTitle(tiles: tiles),
                                 subtitle: CheckupCopy.resultsLine(tiles: tiles),
                                 backTitle: "Start Over", onBack: requestStartOver, module: .checkup)
                    CheckupStaleNotice(finishedAt: session.scanFinishedAt, onScanAgain: onScanAgain)
                    grid(tiles, summary: summary)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.topInset)
                .padding(.bottom, Spacing.m)
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer(summary)
        }
        .prismCanvasIntensity(PrismCanvasMath.Intensity.results)
        .sheet(item: $reviewModule) { module in
            CheckupReviewSheet(module: module, session: session)
        }
        .alert("Start over?", isPresented: $confirmStartOver) {
            Button("Start Over", role: .destructive) { session.startOver() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current results and review choices will be cleared.")
        }
        .onAppear { announceIfFresh(tiles) }
    }

    // MARK: Grid

    private func grid(_ tiles: [CheckupTile], summary: CheckupSelectionSummary) -> some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 200), spacing: Spacing.m, alignment: .top), count: 3)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.m) {
            ForEach(tiles) { tile in
                cell(for: tile)
            }
            CheckupSummaryTile(summary: summary)
        }
    }

    private func cell(for tile: CheckupTile) -> some View {
        let module = tile.module
        let rescanning = session.rescanning.contains(module)
        let shown = rescanning
            ? CheckupTile(module: module, headline: "", detail: "Checking this area again…", status: .info, isSelected: false)
            : tile
        return CheckupTileCell(tile: shown,
                               areaState: session.board.area(module)?.state,
                               isSelected: session.selection.contains(module),
                               isRescanning: rescanning,
                               canReview: session.reviewItemCount(module) > 0,
                               canRecover: session.hasContributor(module),
                               onToggle: { session.toggle(module) },
                               onReview: { reviewModule = module },
                               onRetry: { session.rescan(module) },
                               onInclude: { session.include(module, settings: model.settings) },
                               onOpen: { model.open(module) })
    }

    // MARK: Footer

    private func footer(_ summary: CheckupSelectionSummary) -> some View {
        VStack(spacing: Spacing.s) {
            Text(footerCaption(summary))
                .font(SpruceFont.caption.monospacedDigit())
                .foregroundStyle(Ink.tertiary)
                .contentTransition(.numericText())
            if summary.selectableCount == 0 {
                ActionOrb(title: "Done", module: .checkup, diameter: 84, isDefaultAction: true) {
                    session.startOver()
                }
            } else {
                ActionOrb(title: "Run", subtitle: summary.orbDetail, module: .checkup,
                          isEnabled: !summary.isEmpty && session.rescanning.isEmpty, diameter: 84, isReady: true) {
                    session.run()
                }
            }
        }
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.orbBottom)
    }

    private func footerCaption(_ summary: CheckupSelectionSummary) -> String {
        if !session.rescanning.isEmpty { return "Waiting for the area being checked again…" }
        if summary.selectableCount == 0 { return "Nothing needs attention right now." }
        if summary.isEmpty { return "Tick at least one tile to run it." }
        let areas = CountFormat.items(summary.modules.count, singular: "area")
        return "Runs \(areas), one after another. Only what's selected is touched."
    }

    // MARK: Actions

    private func requestStartOver() {
        if session.hasCustomChoices {
            confirmStartOver = true
        } else {
            session.startOver()
        }
    }

    private func announceIfFresh(_ tiles: [CheckupTile]) {
        guard let finished = session.scanFinishedAt, Date().timeIntervalSince(finished) < 3 else { return }
        let message: String = "Checkup finished. " + CheckupCopy.resultsLine(tiles: tiles)
        AccessibilityNotification.Announcement(message).post()
    }
}

// MARK: - Tile cell

/// A module's result tile plus the recovery action for failed or turned-off areas.
@MainActor
struct CheckupTileCell: View {
    var tile: CheckupTile
    var areaState: CheckupAreaState?
    var isSelected: Bool
    var isRescanning: Bool
    var canReview: Bool
    /// The area has a contributor, so it can be scanned again.
    var canRecover: Bool
    var onToggle: () -> Void
    var onReview: () -> Void
    var onRetry: () -> Void
    var onInclude: () -> Void
    var onOpen: () -> Void

    var body: some View {
        ResultTile(tile: tile, isSelected: isSelected, isScanning: isRescanning,
                   onToggle: onToggle, onReview: canReview ? onReview : nil)
            .overlay(alignment: .bottomTrailing) {
                recovery
                    .padding(Spacing.l)
            }
            .contextMenu {
                Button("Open \(tile.module.title)", action: onOpen)
                if canReview && !isRescanning && tile.status != .unavailable {
                    Button("Review Items…", action: onReview)
                }
            }
    }

    @ViewBuilder
    private var recovery: some View {
        if !isRescanning && canRecover, let areaState {
            switch areaState {
            case .failed:
                CapsuleButton(title: "Try Again", symbol: "arrow.clockwise", action: onRetry)
                    .help("Scan \(tile.module.title) again")
            case .excluded:
                CapsuleButton(title: "Include", symbol: "plus", action: onInclude)
                    .help("Turn \(tile.module.title) back on for Checkup and scan it now")
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Summary tile

/// Sixth tile: what Run will do with the current selection.
@MainActor
struct CheckupSummaryTile: View {
    var summary: CheckupSelectionSummary

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let palette = ModuleID.checkup.palette
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accentText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Ink.controlFill))
                Text("SUMMARY")
                    .font(SpruceFont.overline)
                    .tracking(0.8)
                    .foregroundStyle(ink.secondary)
                Spacer(minLength: Spacing.s)
                Text("\(summary.modules.count) of \(summary.selectableCount) selected")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(ink.tertiary)
            }
            metric(ink)
            Text(detailLine)
                .font(SpruceFont.callout)
                .foregroundStyle(ink.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(summary.modules) { module in
                    PrismCategoryBadge(symbol: module.palette.symbol, module: module, size: 22)
                        .help(module.title)
                }
                if summary.modules.isEmpty {
                    Text("No areas selected")
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 28)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .prismSurface(radius: Radius.card, tint: palette.accent)
        .animation(Motion.standard, value: summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Summary, \(accessibilityText)"))
    }

    @ViewBuilder
    private func metric(_ ink: PrismInk) -> some View {
        if summary.reclaimableBytes > 0 {
            PrismMetricText(text: ByteFormat.string(summary.reclaimableBytes), font: SpruceFont.metricL)
                .frame(height: 40, alignment: .leading)
        } else if summary.actionCount > 0 {
            PrismMetricText(text: CountFormat.items(summary.actionCount, singular: "action"), font: SpruceFont.metricL)
                .frame(height: 40, alignment: .leading)
        } else {
            Text(summary.isEmpty ? "Nothing selected" : "Ready")
                .font(SpruceFont.metricS)
                .foregroundStyle(summary.isEmpty ? ink.tertiary : Ink.primary)
                .frame(height: 40, alignment: .leading)
        }
    }

    private var detailLine: String {
        if summary.isEmpty {
            return summary.selectableCount == 0 ? "Every area is in good shape." : "Tick a tile to include it in Run."
        }
        var parts: [String] = []
        if summary.reclaimableBytes > 0 { parts.append("to free up") }
        if summary.actionCount > 0 {
            parts.append("\(CountFormat.items(summary.actionCount, singular: "action")) across \(CountFormat.items(summary.modules.count, singular: "area"))")
        } else {
            parts.append("in \(CountFormat.items(summary.modules.count, singular: "area"))")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        if summary.isEmpty { return "nothing selected" }
        var parts: [String] = []
        if summary.reclaimableBytes > 0 { parts.append("\(ByteFormat.string(summary.reclaimableBytes)) to free up") }
        if summary.actionCount > 0 { parts.append(CountFormat.items(summary.actionCount, singular: "action")) }
        parts.append("\(CountFormat.items(summary.modules.count, singular: "area")) selected")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Stale notice

/// Shown when the results are older than `CheckupSession.staleAfter`.
@MainActor
struct CheckupStaleNotice: View {
    var finishedAt: Date?
    var onScanAgain: () -> Void

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            Group {
                if let finishedAt, context.date.timeIntervalSince(finishedAt) > CheckupSession.staleAfter {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(StatusColor.warning)
                        Text("These results are \(DurationFormat.short(context.date.timeIntervalSince(finishedAt))) old. Files may have changed since.")
                            .font(SpruceFont.callout)
                            .foregroundStyle(Ink.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Spacing.s)
                        CapsuleButton(title: "Scan Again", symbol: "arrow.clockwise", action: onScanAgain)
                    }
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, 8)
                    .prismSurface(radius: Radius.row, tint: StatusColor.warning)
                }
            }
        }
    }
}
