import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Activity module. CONTRACT: keep the type name `ActivityView` and `init()`.
///
/// One scrolling dashboard: health gauge with recommendations, the monthly summary
/// (stat tiles + six-month chart), and the recent-activity timeline. The header opens
/// the operations log and clears the history.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedMonth: Date?
    @State private var showsLog = false
    @State private var confirmsClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ActivityHeader(canClear: !model.history.history.entries.isEmpty,
                               onShowLog: { showsLog = true },
                               onClear: { confirmsClear = true })
                ActivityHealthPanel()
                ActivityStatsSection(selectedMonth: $selectedMonth)
                ActivityTimelineSection()
            }
            .frame(maxWidth: Spacing.readableWidth)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.topInset + Spacing.l)
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .onAppear {
            model.refreshPermissions()
            model.monitor.refresh()
            // Activity has no sub-tools; drop a stale request aimed at it.
            if let tool = model.pendingTool, tool.hasPrefix("activity") { model.pendingTool = nil }
        }
        .sheet(isPresented: $showsLog) {
            ActivityOperationsLogSheet { showsLog = false }
        }
        .confirmationDialog("Clear all activity history?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                model.history.clear()
                selectedMonth = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Statistics, the monthly chart and the timeline start over. The operations log of removed files is kept.")
        }
    }
}

// MARK: - Header

struct ActivityHeader: View {
    var canClear: Bool
    var onShowLog: () -> Void
    var onClear: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            HeroLens(module: .activity, size: 84, parallax: false)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Activity")
                    .font(SpruceFont.display(34))
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(ModuleID.activity.tagline)
                    .font(SpruceFont.body)
                    .foregroundStyle(PrismInk(contrast).secondary)
            }
            Spacer(minLength: Spacing.m)
            CapsuleButton(title: "Operations Log", symbol: "list.bullet.rectangle", action: onShowLog)
                .help("Every file Spruce moved to the Trash or deleted")
            CapsuleButton(title: "Clear History", symbol: "trash", destructive: true, action: onClear)
                .disabled(!canClear)
        }
    }
}

// MARK: - Shared helpers

/// The Mac Health report Activity shows, and what its cards do.
@MainActor
enum ActivityHealthSource {
    /// `AppModel.healthReport` — the one Mac Health score, shared with the sidebar pill and
    /// the menu bar — with the user's snoozed and turned-off suggestions applied. Hiding a
    /// card never changes the score.
    static func report(_ model: AppModel, advice: ActivityAdviceStore, now: Date = Date()) -> ActivityHealthReport {
        model.healthReport.applying(advice.state, now: now)
    }

    /// Runs a recommendation's action.
    static func perform(_ action: ActivityRecommendationAction, model: AppModel) {
        switch action {
        case .open(let module, let tool):
            model.open(module, tool: tool)
        case .grantFullDiskAccess:
            Permissions.openFullDiskAccessSettings()
        case .none:
            break
        }
    }
}

/// Colours used across the Activity screen.
enum ActivityStyle {
    static func color(_ level: ActivityHealthLevel) -> Color {
        switch level {
        case .excellent: return StatusColor.success
        case .good: return Color(hex: 0x8FD694)
        case .fair: return StatusColor.warning
        case .requiresAttention: return Color(hex: 0xFB923C)
        case .critical: return StatusColor.danger
        }
    }

    static func color(_ severity: ActivitySeverity) -> Color {
        switch severity {
        case .info: return StatusColor.info
        case .warning: return StatusColor.warning
        case .critical: return StatusColor.danger
        }
    }

    static func color(_ delta: ActivityDelta, higherIsBetter: Bool = true) -> Color {
        switch delta {
        case .up: return higherIsBetter ? StatusColor.success : StatusColor.warning
        case .down: return higherIsBetter ? Ink.secondary : StatusColor.success
        case .new: return StatusColor.info
        case .same, .none: return Ink.secondary
        }
    }
}
