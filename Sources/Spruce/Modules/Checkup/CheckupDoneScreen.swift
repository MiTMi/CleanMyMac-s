import Accessibility
import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Completion: celebration burst, the freed total counting up, one row per area that
/// ran (with its outcome), anything that couldn't be completed, and the Done orb.
@MainActor
struct CheckupDoneScreen: View {
    let session: CheckupSession

    @State private var shownBytes: Double = 0
    @State private var celebrating = true
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let board = session.runBoard {
            content(board)
        } else {
            EmptyStateView(module: .checkup, title: "All done", message: "Nothing else to do here.",
                           actionTitle: "Back to Checkup", action: { session.startOver() })
        }
    }

    private func content(_ board: CheckupRunBoard) -> some View {
        let succeeded = board.failures.isEmpty && board.skippedModules.isEmpty
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    HeroLens(module: .checkup, size: 110, mood: succeeded ? .clean : .warning, parallax: false)
                        .frame(height: 110 * 1.4)
                    headline(board)
                    Text(CheckupCopy.runSummary(board))
                        .font(SpruceFont.body)
                        .foregroundStyle(PrismInk(contrast).secondary)
                        .multilineTextAlignment(.center)
                    statChips(board)
                    CheckupDoneAreasCard(board: board)
                    if !board.failures.isEmpty {
                        CheckupDoneFailuresCard(failures: board.failures)
                    }
                    links(board)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.contentInset)
                .padding(.top, Spacing.topInset)
                .padding(.bottom, Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            ActionOrb(title: "Done", module: .checkup, diameter: 84, isDone: celebrating && !reduceMotion,
                      isDefaultAction: true) {
                session.startOver()
            }
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.orbBottom)
        }
        .background(alignment: .top) {
            if board.processedCount > 0 || board.freedBytes > 0 {
                PrismBurst(color: Color.white, secondary: ModuleID.checkup.palette.accent2)
                    .frame(width: 440, height: 440)
                    .offset(y: Spacing.topInset + 110 * 0.7 - 220)
                    .allowsHitTesting(false)
            }
        }
        .prismCanvasIntensity(celebrating && !reduceMotion ? PrismCanvasMath.Intensity.celebrate : PrismCanvasMath.Intensity.idle)
        .onAppear { celebrate(board) }
        .task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                withAnimation(Motion.slow) { celebrating = false }
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func headline(_ board: CheckupRunBoard) -> some View {
        if board.freedBytes > 0 {
            VStack(spacing: 0) {
                PrismCountingBytes(value: shownBytes, font: SpruceFont.metricXL, unitFont: .system(size: 20, weight: .medium))
                Text("freed up")
                    .font(SpruceFont.headline)
                    .foregroundStyle(PrismInk(contrast).secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(CheckupCopy.doneHeadline(board)))
            .accessibilityAddTraits(.isHeader)
        } else {
            Text(CheckupCopy.doneHeadline(board))
                .font(SpruceFont.display(30))
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func statChips(_ board: CheckupRunBoard) -> some View {
        let palette = ModuleID.checkup.palette
        if board.freedBytes > 0 || board.processedCount > 0 || !board.failures.isEmpty {
            HStack(spacing: Spacing.s) {
                if board.freedBytes > 0 {
                    PrismStatChip(symbol: "arrow.down.circle.fill", value: ByteFormat.string(board.freedBytes),
                                  label: "Freed", tint: palette.accentText)
                }
                if board.processedCount > 0 {
                    PrismStatChip(symbol: "checkmark.circle.fill", value: CountFormat.grouped(board.processedCount),
                                  label: board.processedCount == 1 ? "Item handled" : "Items handled", tint: StatusColor.success)
                }
                if !board.failures.isEmpty {
                    PrismStatChip(symbol: "exclamationmark.triangle.fill", value: CountFormat.grouped(board.failures.count),
                                  label: "Couldn't complete", tint: StatusColor.warning)
                }
            }
        }
    }

    private func links(_ board: CheckupRunBoard) -> some View {
        HStack(spacing: Spacing.l) {
            PrismTextButton(title: copied ? "Copied" : "Copy Summary", symbol: copied ? "checkmark" : "doc.on.doc",
                            module: .checkup) {
                copySummary(board)
            }
            if FileManager.default.fileExists(atPath: OperationLog.shared.url.path) {
                PrismTextButton(title: "Show Log", symbol: "arrow.up.right", module: .checkup) {
                    NSWorkspace.shared.activateFileViewerSelecting([OperationLog.shared.url])
                }
                .help("Reveal the log of every file operation in Finder")
            }
        }
    }

    // MARK: Actions

    private func copySummary(_ board: CheckupRunBoard) {
        var lines = ["Checkup — \(CheckupCopy.doneHeadline(board))"]
        for step in board.steps {
            lines.append("• \(step.module.title): \(CheckupCopy.stepDetail(step))")
        }
        for failure in board.failures.prefix(20) {
            lines.append("  ⚠︎ \(failure.title): \(failure.reason)")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        withAnimation(Motion.quick) { copied = true }
    }

    private func celebrate(_ board: CheckupRunBoard) {
        let target = Double(max(0, board.freedBytes))
        if reduceMotion {
            shownBytes = target
        } else {
            withAnimation(Motion.countUp) { shownBytes = target }
        }
        if board.failures.isEmpty {
            SpruceSound.play(.cleanComplete)
        } else if board.processedCount > 0 || board.freedBytes > 0 {
            SpruceSound.play(.attention)
        } else {
            SpruceSound.play(.error)
        }
        var announcement = CheckupCopy.doneHeadline(board)
        if !board.failures.isEmpty {
            announcement += " \(CountFormat.items(board.failures.count)) couldn't be completed."
        }
        AccessibilityNotification.Announcement(announcement).post()
    }
}

// MARK: - Areas card

/// One row per area that was part of the run.
@MainActor
struct CheckupDoneAreasCard: View {
    var board: CheckupRunBoard

    var body: some View {
        GlassCard(radius: Radius.container) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "What changed", trailing: CountFormat.items(board.steps.count, singular: "area"))
                ForEach(board.steps) { step in
                    CheckupDoneRow(step: step)
                }
            }
        }
        .frame(maxWidth: 560)
    }
}

@MainActor
struct CheckupDoneRow: View {
    var step: CheckupRunStep

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.m) {
            PrismCategoryBadge(symbol: step.module.palette.symbol, module: step.module, size: 28,
                               isDimmed: step.state == .skipped)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.module.title)
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                Text(CheckupCopy.stepDetail(step))
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s)
            if let value = trailingValue {
                Text(value)
                    .font(SpruceFont.bodyStrong.monospacedDigit())
                    .foregroundStyle(Ink.primary)
            }
            statusIcon
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var trailingValue: String? {
        guard let outcome = step.outcome else { return nil }
        if outcome.freedBytes > 0 { return ByteFormat.string(outcome.freedBytes) }
        if outcome.processedCount > 0 { return CountFormat.grouped(outcome.processedCount) }
        return nil
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch step.state {
        case .done(let outcome):
            Image(systemName: outcome.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(outcome.failures.isEmpty ? StatusColor.success : StatusColor.warning)
                .accessibilityLabel(Text(outcome.failures.isEmpty ? "Done" : "Partly done"))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(StatusColor.warning)
                .accessibilityLabel(Text("Couldn't finish"))
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(Ink.disabled)
                .accessibilityLabel(Text("Not run"))
        case .waiting, .running:
            Image(systemName: "circle.dotted")
                .foregroundStyle(Ink.disabled)
        }
    }
}

// MARK: - Failures card

@MainActor
struct CheckupDoneFailuresCard: View {
    var failures: [ItemFailure]

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        GlassCard(radius: Radius.container, tint: StatusColor.warning) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Couldn't complete", trailing: CountFormat.items(failures.count))
                ForEach(Array(failures.prefix(6).enumerated()), id: \.offset) { _, failure in
                    HStack(alignment: .top, spacing: Spacing.m) {
                        Text(failure.title)
                            .font(SpruceFont.callout)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.s)
                        Text(failure.reason)
                            .font(SpruceFont.caption)
                            .foregroundStyle(ink.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if failures.count > 6 {
                    Text("and \(CountFormat.items(failures.count - 6, singular: "more item", plural: "more items"))")
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                }
            }
        }
        .frame(maxWidth: 560)
    }
}
