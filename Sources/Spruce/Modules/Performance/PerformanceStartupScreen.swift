import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Login items or background items, grouped by vendor, with per-row switches, a row menu
/// and bulk actions for the selection.
struct PerformanceStartupScreen: View {
    @Bindable var screen: PerformanceScreenModel
    var tool: PerformanceTool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: tool.title, subtitle: subtitle, backTitle: "Performance", onBack: { screen.goHub() },
                         module: .performance, trailing: AnyView(trailingControls))
            banners
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
        .padding(.bottom, Spacing.m)
    }

    private var allItems: [PerformanceStartupItem] {
        guard let inventory = screen.inventory else { return [] }
        return tool == .loginItems ? inventory.loginItems : inventory.backgroundItems
    }

    private var subtitle: String {
        if screen.inventory == nil { return "Looking for items…" }
        let items = allItems
        let on = items.filter { $0.isEnabled }.count
        let broken = items.filter(\.isBroken).count
        var text = tool == .loginItems
            ? "\(CountFormat.items(items.count)) · \(on) open at login"
            : "\(CountFormat.items(items.count)) · \(on) switched on"
        if broken > 0 { text += " · \(broken) broken" }
        return text
    }

    private var trailingControls: some View {
        HStack(spacing: Spacing.s) {
            PrismSearchField(text: $screen.startupSearch, prompt: "Search", width: 200)
            if screen.isLoadingInventory {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else {
                PrismIconButton(symbol: "arrow.clockwise", help: "Refresh") { screen.refreshInventory() }
            }
        }
    }

    // MARK: Banners

    @ViewBuilder
    private var banners: some View {
        if tool == .loginItems, let access = screen.inventory?.loginItemsAccess, access != .granted {
            PerformanceBanner(symbol: "lock.fill",
                              text: access == .denied
                                ? "Spruce isn't allowed to read the apps that open at login. Allow Spruce to control System Events in Privacy & Security › Automation, then refresh."
                                : "The apps that open at login couldn't be read: \(failureText(access))",
                              actionTitle: access == .denied ? "Open Settings" : nil) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        let managed = allItems.filter { !$0.kind.isManageable }.count
        if managed > 0 {
            PerformanceBanner(symbol: "info.circle",
                              text: "\(CountFormat.items(managed)) \(managed == 1 ? "was" : "were") registered by \(managed == 1 ? "its app" : "their apps") and can be changed only in System Settings.",
                              actionTitle: "Open Login Items Settings") {
                Permissions.openLoginItemsSettings()
            }
        }
    }

    private func failureText(_ access: PerformanceLoginItemsAccess) -> String {
        if case .failed(let message) = access { return message }
        return ""
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let groups = screen.groups(for: tool)
        if screen.inventory == nil {
            VStack(spacing: Spacing.m) {
                ProgressView()
                Text("Looking for what starts with your Mac…")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
            }
        } else if groups.isEmpty {
            if screen.startupSearch.isEmpty {
                EmptyStateView(module: .performance,
                               title: tool == .loginItems ? "Nothing opens at login" : "No background items",
                               message: tool == .loginItems
                                ? "No apps are set to open when you log in."
                                : "No third-party agents or daemons are installed. Apple's own items are never listed.")
            } else {
                EmptyStateView(module: .performance, title: "No matches", message: "Nothing matches \u{201C}\(screen.startupSearch)\u{201D}.",
                               symbol: "magnifyingglass", mood: .standard)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(groups) { group in
                        PerformanceVendorCard(screen: screen, group: group)
                    }
                }
                .padding(.bottom, Spacing.s)
            }
            .scrollIndicators(.automatic)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        let selected = screen.selectedItems(for: tool)
        if !selected.isEmpty {
            let canTurnOff = selected.contains { $0.canToggle && $0.isEnabled }
            let canTurnOn = selected.contains { $0.canToggle && !$0.isEnabled }
            GlassCard(padding: Spacing.m) {
                HStack(spacing: Spacing.s) {
                    Text("\(CountFormat.items(selected.count)) selected")
                        .font(SpruceFont.bodyStrong)
                        .foregroundStyle(Ink.primary)
                    if selected.contains(where: { $0.kind == .systemDaemon }) {
                        Label("Daemons need your password", systemImage: "lock")
                            .font(SpruceFont.caption)
                            .foregroundStyle(PrismInk(contrast).tertiary)
                    }
                    Spacer()
                    CapsuleButton(title: "Deselect") { screen.selectedStartupIDs = [] }
                    if canTurnOn {
                        CapsuleButton(title: "Turn On", symbol: "play.circle") { screen.setSelectedEnabled(true, tool: tool) }
                    }
                    if canTurnOff {
                        CapsuleButton(title: "Turn Off", symbol: "pause.circle") { screen.setSelectedEnabled(false, tool: tool) }
                    }
                    CapsuleButton(title: "Remove…", symbol: "trash", destructive: true) { screen.requestRemoval(selected) }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Banner

struct PerformanceBanner: View {
    var symbol: String
    var text: String
    var actionTitle: String?
    var action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ModuleID.performance.palette.accentText)
            Text(text)
                .font(SpruceFont.callout)
                .foregroundStyle(PrismInk(contrast).secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s)
            if let actionTitle {
                CapsuleButton(title: actionTitle, action: action)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Ink.subtleFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Ink.hairline))
    }
}

// MARK: - Vendor card

struct PerformanceVendorCard: View {
    @Bindable var screen: PerformanceScreenModel
    var group: PerformanceVendorGroup
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GlassCard(padding: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                header
                Rectangle()
                    .fill(Ink.hairline)
                    .frame(height: 1)
                    .padding(.vertical, Spacing.xs)
                ForEach(group.items) { item in
                    PerformanceStartupRow(screen: screen, item: item)
                }
            }
        }
    }

    private var manageable: [PerformanceStartupItem] { group.items.filter(\.canRemove) }

    private var selectionState: SelectionState {
        let ids = manageable.map(\.id)
        let selected = ids.filter { screen.selectedStartupIDs.contains($0) }.count
        if selected == 0 { return .none }
        return selected == ids.count ? .all : .some
    }

    private var header: some View {
        HStack(spacing: Spacing.m) {
            if manageable.isEmpty {
                Color.clear.frame(width: 16, height: 16)
            } else {
                SpruceCheckbox(state: selectionState, module: .performance, label: group.title) {
                    screen.setGroupSelection(group, selected: selectionState != .all)
                }
            }
            ItemIcon(url: group.appPath.map { URL(fileURLWithPath: $0) }, symbol: "building.2", size: 30, module: .performance)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.title)
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text(CountFormat.items(group.items.count))
                    .font(SpruceFont.caption)
                    .foregroundStyle(PrismInk(contrast).tertiary)
            }
            Spacer(minLength: Spacing.s)
            if group.brokenCount > 0 {
                StatusPill(text: "\(group.brokenCount) broken", status: .critical)
            }
        }
    }
}

// MARK: - Row

struct PerformanceStartupRow: View {
    @Bindable var screen: PerformanceScreenModel
    var item: PerformanceStartupItem

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.m) {
            if item.canRemove {
                SpruceCheckbox(isOn: screen.selectedStartupIDs.contains(item.id), module: .performance, label: item.name) {
                    screen.toggleSelection(item)
                }
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
            ItemIcon(url: iconURL, symbol: item.kind.symbol, size: 24, module: .performance)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s) {
                    Text(item.name)
                        .font(SpruceFont.body.weight(.medium))
                        .foregroundStyle(item.isEnabled || !item.kind.isManageable ? Ink.primary : ink.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    PrismChip(text: item.kind.label, color: ink.tertiary)
                }
                Text(item.statusDetail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(item.isBroken ? StatusColor.danger : ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.s)
            StatusPill(text: item.status.title, status: Self.tileStatus(item.status))
            control
            rowMenu
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hovering ? Ink.subtleFill : Color.clear))
        .onHover { hovering = $0 }
        .help(tooltip)
        .opacity(screen.busyItemIDs.contains(item.id) ? 0.6 : 1)
    }

    private var iconURL: URL? {
        if let appPath = item.appPath { return URL(fileURLWithPath: appPath) }
        if item.kind == .loginItem, let path = item.executablePath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    @ViewBuilder
    private var control: some View {
        if screen.busyItemIDs.contains(item.id) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 38)
        } else if item.canToggle {
            Toggle("", isOn: Binding(get: { item.isEnabled }, set: { screen.setEnabled(item, $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(item.isEnabled ? "Turn off" : "Turn on")
                .accessibilityLabel(Text("\(item.name) on"))
        } else {
            Color.clear.frame(width: 38, height: 1)
        }
    }

    private var rowMenu: some View {
        Menu {
            if let path = revealPath {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            if let label = item.label {
                Button("Copy Label") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(label, forType: .string)
                }
            }
            if !item.kind.isManageable {
                Button("Open Login Items Settings") { Permissions.openLoginItemsSettings() }
            }
            if item.canRemove {
                Divider()
                Button("Remove…", role: .destructive) { screen.requestRemoval([item]) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(PrismInk(contrast).secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("More actions for \(item.name)"))
    }

    private var revealPath: String? {
        for candidate in [item.plistPath, item.executablePath, item.appPath].compactMap({ $0 })
        where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private var tooltip: String {
        var lines: [String] = [item.name]
        if let label = item.label { lines.append("Label: \(label)") }
        if let plist = item.plistPath { lines.append("File: \(plist.abbreviatingHome)") }
        if let program = item.executablePath { lines.append("Runs: \(program.abbreviatingHome)") }
        if item.keepAlive { lines.append("macOS restarts it if it stops") }
        return lines.joined(separator: "\n")
    }

    static func tileStatus(_ status: PerformanceStartupStatus) -> TileStatus {
        switch status {
        case .running: return .clear
        case .enabled: return .info
        case .disabled: return .unavailable
        case .broken: return .critical
        case .managedBySystem: return .unavailable
        }
    }
}
