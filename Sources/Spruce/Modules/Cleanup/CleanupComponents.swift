import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Section card

enum CleanupCardState: Equatable {
    case ready
    case empty
    case notScanned
    case needsAccess
}

/// One results card per Cleanup section (System Junk is the tall lead card).
///
/// Each card shows what was found and what is selected. A card whose selection is
/// empty offers only Review — never a Clean button that would act on nothing.
struct CleanupSectionCard: View {
    let section: CleanupSection
    let group: ScanGroup?
    let state: CleanupCardState
    var isLead: Bool = false
    var inUseCount: Int = 0
    /// Categories of this section macOS didn't let Spruce scan, with the reason.
    var unavailable: [CleanupUnavailable] = []
    var onReview: () -> Void
    var onClean: () -> Void
    var onToggle: () -> Void
    var onScan: () -> Void
    var onGrantAccess: () -> Void

    var body: some View {
        GlassCard(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                metric
                Text(section.detail)
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                details
                Spacer(minLength: 0)
                actions
            }
            .frame(maxWidth: .infinity, minHeight: isLead ? 300 : 150, alignment: .topLeading)
        }
        .opacity(state == .notScanned ? 0.7 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var details: some View {
        if state == .ready, let group {
            Text(selectionLine(group))
                .font(SpruceFont.caption.monospacedDigit())
                .foregroundStyle(Ink.tertiary)
            if isLead {
                CleanupIncludesList(group: group)
            }
            if inUseCount > 0 {
                Label("\(CountFormat.items(inUseCount)) left alone because their apps are open",
                      systemImage: "lock")
                    .font(SpruceFont.caption)
                    .foregroundStyle(StatusColor.warning)
            }
        }
        if isLead && (state == .ready || state == .empty) && !unavailable.isEmpty {
            CleanupUnavailableList(items: unavailable)
        }
    }

    private func selectionLine(_ group: ScanGroup) -> String {
        if group.selectedCount == 0 {
            return "Nothing selected · \(CountFormat.items(group.totalCount)) to review"
        }
        return "\(ByteFormat.string(group.selectedSize)) selected · \(CountFormat.items(group.totalCount))"
    }

    /// Whether the card checkbox can do something: clear a selection, or restore a
    /// recommended one.
    private var canToggle: Bool {
        guard let group else { return false }
        return group.selectedCount > 0
            || group.allItems.contains { $0.metadata[CleanupMetadataKey.recommended] == "1" && $0.safety != .risky }
    }

    private var cleanTitle: String {
        section == .trashBins ? "Empty" : "Clean"
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: section.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ModuleID.cleanup.palette.accentText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Ink.controlFill))
            Text(section.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Ink.secondary)
            Spacer(minLength: Spacing.s)
            if state == .ready, let group, canToggle {
                SpruceCheckbox(state: group.selectionState, module: .cleanup, label: "Clean \(section.title)",
                               action: onToggle)
                    .help(group.selectedCount > 0 ? "Don't clean \(section.title)" : "Select the recommended items")
            }
        }
    }

    @ViewBuilder
    private var metric: some View {
        switch state {
        case .ready:
            Text(ByteFormat.string(group?.totalSize ?? 0))
                .font(SpruceFont.numeral(isLead ? 46 : 34))
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .empty:
            Label("Nothing to clean", systemImage: "checkmark.circle.fill")
                .font(SpruceFont.headline)
                .foregroundStyle(StatusColor.success)
        case .notScanned:
            Text("Not scanned")
                .font(SpruceFont.headline)
                .foregroundStyle(Ink.secondary)
        case .needsAccess:
            Label("Needs Full Disk Access", systemImage: "lock.fill")
                .font(SpruceFont.headline)
                .foregroundStyle(StatusColor.warning)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Spacing.s) {
            Spacer(minLength: 0)
            switch state {
            case .ready:
                CapsuleButton(title: "Review", symbol: "list.bullet", action: onReview)
                if let group, group.selectedCount > 0 {
                    CapsuleButton(title: "\(cleanTitle) \(ByteFormat.string(group.selectedSize))", prominent: true,
                                  action: onClean)
                        .help(section == .trashBins
                              ? "Empty the selected Trash items for good"
                              : "Clean only the selected items of \(section.title)")
                }
            case .empty:
                EmptyView()
            case .notScanned:
                CapsuleButton(title: "Scan", symbol: "magnifyingglass", action: onScan)
            case .needsAccess:
                CapsuleButton(title: "Grant Access", symbol: "arrow.up.right", prominent: true, action: onGrantAccess)
            }
        }
    }

    private var accessibilityText: String {
        switch state {
        case .ready:
            let size = ByteFormat.string(group?.totalSize ?? 0)
            let selected = ByteFormat.string(group?.selectedSize ?? 0)
            return "\(section.title), \(size) found, \(selected) selected"
        case .empty: return "\(section.title), nothing to clean"
        case .notScanned: return "\(section.title), not scanned"
        case .needsAccess: return "\(section.title), needs Full Disk Access"
        }
    }
}

/// "Includes" list of the largest categories inside a section.
struct CleanupIncludesList: View {
    let group: ScanGroup

    var body: some View {
        let top = group.children.sorted { $0.totalSize > $1.totalSize }.prefix(5)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(top)) { child in
                HStack(spacing: Spacing.s) {
                    Image(systemName: child.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.tertiary)
                        .frame(width: 16)
                    Text(child.title)
                        .font(SpruceFont.callout)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.s)
                    SizeBadge(bytes: child.totalSize)
                }
            }
            if group.children.count > top.count {
                Text("and \(CountFormat.items(group.children.count - top.count, singular: "more category", plural: "more categories"))")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.top, Spacing.xs)
    }
}

/// Categories that couldn't be scanned, each with its reason ("Needs Full Disk Access").
struct CleanupUnavailableList: View {
    let items: [CleanupUnavailable]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: Spacing.s) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(StatusColor.warning)
                        .frame(width: 16)
                    Text(item.category.title)
                        .font(SpruceFont.callout)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.s)
                    Text(item.message)
                        .font(SpruceFont.caption)
                        .foregroundStyle(StatusColor.warning)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, Spacing.xs)
    }
}

// MARK: - Insights

/// Informational findings Cleanup leaves alone (document versions, deleted users,
/// Mail's trash, system launch items, installers) plus the app-bundle note.
struct CleanupInsightsCard: View {
    let insights: [CleanupInsight]

    var body: some View {
        GlassCard(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Also on this Mac", trailing: "Not removed by Cleanup")
                ForEach(insights) { insight in
                    CleanupInsightRow(symbol: insight.symbol, title: insight.title, detail: insight.detail,
                                      size: insight.size, path: insight.path)
                }
                CleanupInsightRow(
                    symbol: "character.bubble",
                    title: "Language files and universal binaries",
                    detail: "Left inside your apps on purpose. Trimming apps saves little, comes back with every update and can break code signatures.",
                    size: nil, path: nil)
            }
        }
    }
}

struct CleanupInsightRow: View {
    let symbol: String
    let title: String
    let detail: String
    let size: Int64?
    let path: String?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(ModuleID.cleanup.palette.accentText)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Ink.controlFill))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SpruceFont.body.weight(.medium))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s)
            if let size, size > 0 {
                SizeBadge(bytes: size)
            }
            if let path {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Ink.controlFill))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal \(title) in Finder")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Full Disk Access banner

/// Shown on the results when some categories couldn't be scanned. Tells a missing
/// Full Disk Access permission apart from a location macOS refused anyway.
struct CleanupAccessBanner: View {
    let unavailable: [CleanupUnavailable]
    var onOpenSettings: () -> Void
    var onCheckAgain: () -> Void

    var body: some View {
        GlassCard(padding: Spacing.m, tint: StatusColor.warning) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(StatusColor.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(needsFullDiskAccess ? "Full Disk Access is off" : "Some places couldn't be read")
                        .font(SpruceFont.headline)
                        .foregroundStyle(Ink.primary)
                    Text(message)
                        .font(SpruceFont.callout)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.s)
                CapsuleButton(title: needsFullDiskAccess ? "Check Again" : "Scan Again", action: onCheckAgain)
                CapsuleButton(title: "Open Settings", symbol: "arrow.up.right", prominent: true, action: onOpenSettings)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var needsFullDiskAccess: Bool {
        unavailable.contains { $0.reason == .fullDiskAccess }
    }

    private var message: String {
        let names = unavailable.map(\.category.title)
        let list: String
        switch names.count {
        case 0: list = "some locations"
        case 1: list = names[0]
        default: list = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
        if needsFullDiskAccess {
            return "Spruce couldn't look at \(list). Turn on Full Disk Access for Spruce in System Settings › Privacy & Security, then scan again."
        }
        return "macOS didn't let Spruce read \(list). Check that Spruce is still on in System Settings › Privacy & Security › Full Disk Access, then scan again."
    }
}

// MARK: - Quit apps sheet

/// Asks to quit apps whose caches or data are selected (they're skipped otherwise).
struct CleanupQuitAppsSheet: View {
    let prompt: CleanupQuitPrompt
    var onQuit: () -> Void
    var onSkip: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(prompt.apps.count == 1 ? "Quit \(prompt.apps[0].name) to finish?" : "Quit these apps to finish?")
                    .font(SpruceFont.title)
                    .foregroundStyle(Ink.primary)
                Text("Their data is selected, and apps can only rebuild it safely while they're closed. Each app asks you to save open work before it quits.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(prompt.apps) { app in
                    HStack(spacing: Spacing.m) {
                        appIcon(app)
                        Text(app.name)
                            .font(SpruceFont.body)
                            .foregroundStyle(Ink.primary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.subtleFill))
            HStack(spacing: Spacing.s) {
                CapsuleButton(title: "Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                CapsuleButton(title: "Skip These Items", action: onSkip)
                CapsuleButton(title: prompt.apps.count == 1 ? "Quit & Clean" : "Quit All & Clean", prominent: true,
                              action: onQuit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
        .background(ModuleID.cleanup.palette.canvasGradient)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func appIcon(_ app: CleanupRunningApp) -> some View {
        if let icon = app.app.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "app")
                .font(.system(size: 20))
                .foregroundStyle(Ink.secondary)
                .frame(width: 28, height: 28)
        }
    }
}

/// Covers the screen while apps are quitting.
struct CleanupWaitingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            GlassCard(padding: Spacing.xl) {
                HStack(spacing: Spacing.m) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for apps to quit…")
                        .font(SpruceFont.body)
                        .foregroundStyle(Ink.primary)
                }
            }
        }
        .transition(.opacity)
    }
}
