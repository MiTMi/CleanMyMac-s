import SpruceCore
import SpruceMac
import SwiftUI

/// Checkup landing: hero lens, last-checkup line, the five areas as toggle chips
/// (areas turned off in Settings are dimmed), a Full Disk Access hint and the Scan orb.
@MainActor
struct CheckupIdleScreen: View {
    let session: CheckupSession
    var onScan: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let included = includedModules
        ModuleIdleView(
            module: .checkup,
            title: "Let's give your Mac a once-over.",
            subtitle: "Cleanup, protection, speed, apps and clutter in one scan. Nothing changes until you press Run.",
            actionTitle: "Scan",
            isEnabled: !included.isEmpty,
            notice: notice(included: included),
            noticeActionTitle: showsAccessNotice(included: included) ? "Grant Access" : nil,
            accessory: AnyView(CheckupIdleAccessory(included: included, lastLine: lastLine, onToggle: toggle)),
            action: onScan,
            onNoticeAction: noticeAction(included: included)
        )
    }

    private func showsAccessNotice(included: Set<ModuleID>) -> Bool {
        !included.isEmpty && !model.hasFullDiskAccess
    }

    private func noticeAction(included: Set<ModuleID>) -> (() -> Void)? {
        guard showsAccessNotice(included: included) else { return nil }
        return { Permissions.openFullDiskAccessSettings() }
    }

    private var includedModules: Set<ModuleID> {
        Set(model.settings.settings.checkupModules)
    }

    private var lastLine: String {
        CheckupCopy.lastCheckupLine(CheckupHistory.lastSummary(in: model.history.history))
    }

    private func notice(included: Set<ModuleID>) -> String? {
        if included.isEmpty {
            return "Every area is turned off. Turn at least one back on to scan."
        }
        if showsAccessNotice(included: included) {
            return "To check everywhere, Checkup needs Full Disk Access. Without it, some areas give partial results."
        }
        return nil
    }

    private func toggle(_ module: ModuleID) {
        var set = includedModules
        if set.contains(module) {
            set.remove(module)
        } else {
            set.insert(module)
        }
        model.settings.settings.checkupModules = ModuleID.checkupContributors.filter { set.contains($0) }
    }
}

/// Last-checkup line plus the area chips, shown under the idle subtitle.
@MainActor
struct CheckupIdleAccessory: View {
    var included: Set<ModuleID>
    var lastLine: String
    var onToggle: (ModuleID) -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.tertiary)
                Text(lastLine)
                    .font(SpruceFont.callout.monospacedDigit())
                    .foregroundStyle(ink.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Areas", trailing: "\(included.count) of \(ModuleID.checkupContributors.count)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 220), spacing: Spacing.s, alignment: .leading)],
                          alignment: .leading, spacing: Spacing.s) {
                    ForEach(ModuleID.checkupContributors) { module in
                        CheckupModuleChip(module: module, isIncluded: included.contains(module)) {
                            onToggle(module)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("Click an area to skip or include it.")
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                    SettingsLink {
                        Text("More in Settings")
                            .font(SpruceFont.caption.weight(.semibold))
                            .foregroundStyle(ModuleID.checkup.palette.accentText)
                    }
                    .buttonStyle(.plain)
                    .prismLinkPointer()
                }
            }
        }
    }
}

/// One toggleable area chip on the Checkup landing.
@MainActor
struct CheckupModuleChip: View {
    var module: ModuleID
    var isIncluded: Bool
    var action: () -> Void

    @State private var hovering = false

    private var helpText: String {
        isIncluded ? "\(module.title) is included. Click to skip it." : "\(module.title) is skipped. Click to include it."
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                PrismCategoryBadge(symbol: module.palette.symbol, module: module, size: 20, isDimmed: !isIncluded)
                Text(module.title)
                    .font(SpruceFont.callout.weight(.medium))
                    .foregroundStyle(isIncluded ? Ink.primary : Ink.disabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                Image(systemName: isIncluded ? "checkmark" : "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isIncluded ? module.palette.accentText : Ink.disabled)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .prismSurface(radius: Radius.row, highlighted: hovering)
            .opacity(isIncluded ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismPressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.standard, value: isIncluded)
        .help(helpText)
        .accessibilityLabel(Text(module.title))
        .accessibilityValue(Text(isIncluded ? "Included" : "Skipped"))
        .accessibilityHint(Text("Toggles whether Checkup scans this area"))
    }
}
