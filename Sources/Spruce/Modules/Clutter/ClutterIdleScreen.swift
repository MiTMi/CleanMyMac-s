import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Intro screen: what Clutter finds, where it looks (Home, Desktop, Documents,
/// Downloads, mounted disks, chosen folders) and the Scan orb.
struct ClutterIdleScreen: View {
    @Bindable var screen: ClutterScreenModel

    var body: some View {
        ModuleIdleView(module: .clutter,
                       title: screen.focusTool?.title,
                       subtitle: screen.focusTool?.summary,
                       features: screen.focusTool == nil ? features : [],
                       actionTitle: "Scan",
                       actionSubtitle: actionSubtitle,
                       isEnabled: screen.canStartScan,
                       notice: notice,
                       accessory: AnyView(ClutterLocationPicker(screen: screen)),
                       action: { screen.startScan() })
    }

    private var features: [IdleFeature] {
        ClutterTool.allCases.map { IdleFeature(symbol: $0.symbol, title: $0.title, detail: $0.summary) }
    }

    private var actionSubtitle: String? {
        if screen.focusTool == .downloads { return "Downloads" }
        let available = screen.availableLocations
        guard !available.isEmpty else { return nil }
        return screen.locationSummary(available)
    }

    private var notice: String? {
        if screen.focusTool != .downloads && screen.availableLocations.isEmpty {
            return screen.locations.isEmpty
                ? "Choose at least one place to look in."
                : "None of the chosen places is available right now. Connect the disk or choose another folder."
        }
        let missing = screen.missingLocations
        guard !missing.isEmpty, screen.focusTool != .downloads else { return nil }
        let names = missing.map { screen.locationOption(for: $0).title }
        let list = names.count == 1 ? "“\(names[0])” isn't" : "\(names.count) chosen places aren't"
        return "\(list) available right now, so the scan skips \(names.count == 1 ? "it" : "them")."
    }
}

/// Chips for the places Clutter scans, plus "Choose Folder…". Names, free space and
/// availability come from the screen's last location probe (never from the disk while
/// rendering).
struct ClutterLocationPicker: View {
    @Bindable var screen: ClutterScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Look in", symbol: "scope")
            if screen.focusTool == .downloads {
                Text("Downloads always looks at the top level of your Downloads folder.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ClutterFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(ClutterLocations.standard) { option in
                        ClutterLocationChip(option: option, isSelected: screen.isLocationSelected(option),
                                            isAvailable: screen.isLocationAvailable(option.path),
                                            onTap: { screen.toggleLocation(option) }, onRemove: nil)
                    }
                    ForEach(screen.volumes) { option in
                        ClutterLocationChip(option: option, isSelected: screen.isLocationSelected(option),
                                            isAvailable: true,
                                            onTap: { screen.toggleLocation(option) }, onRemove: nil)
                    }
                    ForEach(screen.customLocations) { option in
                        ClutterLocationChip(option: option, isSelected: true,
                                            isAvailable: screen.isLocationAvailable(option.path),
                                            onTap: { screen.removeLocation(option.path) },
                                            onRemove: { screen.removeLocation(option.path) })
                    }
                    ClutterChooseFolderChip { screen.chooseFolders() }
                }
            }
            if screen.focusTool != nil {
                PrismTextButton(title: "Scan with every tool instead", symbol: "arrow.right", module: .clutter) {
                    screen.focusTool = nil
                }
                .font(SpruceFont.callout)
            }
        }
        .padding(.top, Spacing.xs)
    }
}

/// One selectable location capsule.
struct ClutterLocationChip: View {
    var option: ClutterLocationOption
    var isSelected: Bool
    var isAvailable: Bool
    var onTap: () -> Void
    var onRemove: (() -> Void)?

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let accent = ModuleID.clutter.palette.accent
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: isSelected ? "checkmark" : option.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? Ink.onBright : ink.secondary)
                Text(option.title)
                    .font(SpruceFont.callout.weight(.medium))
                    .foregroundStyle(isSelected ? Ink.onBright : Ink.primary)
                    .lineLimit(1)
                if let detail = isAvailable ? option.detail : "Not available" {
                    Text(detail)
                        .font(SpruceFont.caption)
                        .foregroundStyle(isSelected ? Ink.onBright.opacity(0.7) : ink.tertiary)
                        .lineLimit(1)
                }
                if onRemove != nil && hovering {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Ink.onBright : ink.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(isSelected ? accent : (hovering ? ink.selectedFill : ink.controlFill)))
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : ink.hairline, lineWidth: 1))
            .opacity(isAvailable ? 1 : 0.6)
            .contentShape(Capsule())
        }
        .buttonStyle(PrismPressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: isSelected)
        .help(helpText)
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? "selected" : "not selected")
    }

    private var helpText: String {
        if onRemove != nil { return "\(option.absolutePath.abbreviatingHome) — click to remove" }
        return option.absolutePath.abbreviatingHome
    }
}

/// "Choose Folder…" capsule that opens a folder picker.
struct ClutterChooseFolderChip: View {
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text("Choose Folder…").font(SpruceFont.callout.weight(.medium))
            }
            .foregroundStyle(hovering ? Ink.primary : ink.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(ink.highlight))
            .contentShape(Capsule())
        }
        .buttonStyle(PrismPressStyle())
        .onHover { hovering = $0 }
        .help("Add a folder or disk to scan")
    }
}
