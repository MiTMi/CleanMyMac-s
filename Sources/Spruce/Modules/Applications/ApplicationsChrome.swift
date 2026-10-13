import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Tool header

/// Top of every tool: back to the overview, the tool switcher and the title row.
struct ApplicationsToolHeader<Trailing: View>: View {
    @Bindable var screen: ApplicationsScreenModel
    var tool: ApplicationsTool
    var title: String
    var subtitle: String?
    var backTitle: String = "Applications"
    /// Overrides the back action (e.g. detail → list). nil returns to the overview.
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                PrismBackButton(title: backTitle, action: goBack)
                Spacer(minLength: Spacing.s)
                ApplicationsToolTabs(screen: screen, current: tool)
                Spacer(minLength: Spacing.s)
            }
            HStack(alignment: .center, spacing: Spacing.m) {
                PrismCategoryBadge(symbol: tool.symbol, module: .applications, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SpruceFont.title)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(SpruceFont.callout.monospacedDigit())
                            .foregroundStyle(ink.secondary)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.m)
                trailing
            }
        }
    }

    private func goBack() {
        if let onBack {
            onBack()
        } else {
            screen.goHub()
        }
    }
}

/// Glass segmented switcher between the five tools, with live counts.
struct ApplicationsToolTabs: View {
    @Bindable var screen: ApplicationsScreenModel
    var current: ApplicationsTool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ApplicationsTool.allCases) { tool in
                ApplicationsToolTab(tool: tool, isCurrent: tool == current, badge: badge(for: tool)) {
                    if tool != current { screen.open(tool) }
                }
            }
        }
        .padding(3)
        .prismGlassCapsule()
    }

    private func badge(for tool: ApplicationsTool) -> String? {
        switch tool {
        case .uninstaller:
            return nil
        case .updater:
            let count = screen.pendingUpdates.count
            return count > 0 ? String(count) : nil
        case .leftovers:
            let count = screen.leftovers.groups.count
            return count > 0 ? String(count) : nil
        case .installers:
            let count = screen.installers.groups.allItems.count
            return count > 0 ? String(count) : nil
        case .extensions:
            return nil
        }
    }
}

private struct ApplicationsToolTab: View {
    var tool: ApplicationsTool
    var isCurrent: Bool
    var badge: String?
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(tool.title)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Ink.onBright)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(ModuleID.applications.palette.accent2))
                }
            }
            .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
            .foregroundStyle(isCurrent ? Ink.primary : (hovering ? Ink.primary : ink.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isCurrent ? ink.selectedFill : (hovering ? ink.subtleFill : Color.clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(PrismPressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

// MARK: - Facet column

/// Overline title of a facet section ("SOURCES", "VENDORS").
struct ApplicationsFacetHeader: View {
    var title: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(title.uppercased())
            .font(SpruceFont.overline)
            .tracking(0.8)
            .foregroundStyle(PrismInk(contrast).tertiary)
            .padding(.horizontal, Spacing.s)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One selectable row of a facet column.
struct ApplicationsFacetRow: View {
    var title: String
    var symbol: String
    var count: String?
    var isSelected: Bool
    /// Rows that navigate elsewhere show a chevron.
    var showsChevron: Bool = false
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? ModuleID.applications.palette.accentText : ink.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Ink.primary : ink.secondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                if let count {
                    Text(count)
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(ink.tertiary)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ink.tertiary)
                }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(isSelected ? ink.selectedFill : (hovering ? ink.subtleFill : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Small pieces

/// Thin divider used between rows.
struct ApplicationsHairline: View {
    var leading: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(PrismInk(contrast).hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

/// Inline information strip ("Homebrew isn't installed…").
struct ApplicationsBanner: View {
    var symbol: String
    var text: String
    var tint: Color = ModuleID.applications.palette.accentText
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(SpruceFont.callout)
                .foregroundStyle(PrismInk(contrast).secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s)
            if let actionTitle, let action {
                CapsuleButton(title: actionTitle, action: action)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Ink.subtleFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Ink.hairline))
    }
}

/// Centred spinner with a caption, for panes that are still loading.
struct ApplicationsLoadingPane: View {
    var message: String
    var detail: String? = nil
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.m) {
            ProgressView()
                .controlSize(.regular)
            Text(message)
                .font(SpruceFont.callout)
                .foregroundStyle(PrismInk(contrast).secondary)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(PrismInk(contrast).tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Badges describing an app: source, architecture, running, vendor uninstaller.
struct ApplicationsAppBadges: View {
    var app: ApplicationsAppInfo
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if app.isRunning {
                PrismChip(text: "Open", color: StatusColor.success, symbol: "circle.fill")
            }
            if app.isSystem {
                PrismChip(text: "macOS", color: StatusColor.info, symbol: "lock.fill")
            } else if app.source != .other {
                PrismChip(text: app.source.title, color: ModuleID.applications.palette.accent2, symbol: sourceSymbol)
            }
            if app.isIntelOnly {
                PrismChip(text: "Intel", color: StatusColor.warning, symbol: "cpu")
                    .help("Runs through Rosetta on Apple silicon. A native version is usually faster.")
            } else if app.architecture == .legacy32 {
                PrismChip(text: "32-bit", color: StatusColor.danger, symbol: "xmark.octagon")
                    .help("32-bit apps can't open on current macOS.")
            }
            if let label = suspicionLabel {
                PrismChip(text: label, color: StatusColor.warning, symbol: "exclamationmark.shield")
                    .help(ApplicationsSuspicion.reasons(app).joined(separator: " "))
            }
            if !compact && app.prefersVendorUninstaller {
                PrismChip(text: "Own uninstaller", color: StatusColor.warning, symbol: "exclamationmark.shield")
                    .help("This vendor ships its own uninstaller; use it for a complete removal.")
            }
        }
    }

    /// Short label for the Suspicious group's signals.
    private var suspicionLabel: String? {
        guard ApplicationsSuspicion.isSuspicious(app) else { return nil }
        switch app.codeSignature {
        case .broken: return "Broken signature"
        case .unsigned: return "Unsigned"
        case .adHoc: return "No developer ID"
        case .identified, .unknown: return "Not approved"
        }
    }

    private var sourceSymbol: String {
        switch app.source {
        case .appStore: return "bag"
        case .homebrew: return "mug"
        case .setapp: return "square.stack"
        case .steam: return "gamecontroller"
        case .other: return "shippingbox"
        }
    }
}

extension ApplicationsAppInfo {
    /// "Opened 3 months ago" etc.
    var applicationsLastUsedText: String { ApplicationsUnusedRule.lastUsedLabel(self) }
}
