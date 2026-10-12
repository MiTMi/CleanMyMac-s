import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// App Permissions results: permissions on the left, the apps holding the focused one on
/// the right, with Reset Access and a link to the matching System Settings pane.
struct ProtectionPermissionsResultsScreen: View {
    @Bindable var screen: ProtectionScreenModel
    @Bindable var flow: ScanFlowModel
    @State private var focusedGroupID: String?

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: "App Permissions", subtitle: subtitle, backTitle: "Protection", onBack: { screen.showHub() },
                         module: .protection,
                         trailing: AnyView(PrismTextButton(title: "Scan Again", symbol: "arrow.clockwise",
                                                           module: .protection) { screen.startScan(.permissions) }))
            content
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var report: ProtectionPermissionsReport? { screen.permissionsReport }

    private var subtitle: String {
        guard let report, !report.needsFullDiskAccess else { return "Who can use what on your Mac" }
        var text = "\(CountFormat.items(report.appCount, singular: "app")) hold \(CountFormat.items(report.grantCount, singular: "permission"))"
        if report.leftoverCount > 0 {
            text += " · \(CountFormat.items(report.leftoverCount, singular: "leftover")) from deleted apps"
        }
        return text
    }

    @ViewBuilder
    private var content: some View {
        if report?.needsFullDiskAccess == true {
            VStack(spacing: Spacing.m) {
                EmptyStateView(module: .protection, title: "Full Disk Access needed",
                               message: "macOS keeps the list of app permissions in a protected place. Allow Spruce in System Settings › Privacy & Security › Full Disk Access, then scan again.",
                               symbol: "lock.fill", mood: .limited)
                HStack(spacing: Spacing.m) {
                    CapsuleButton(title: "Open System Settings", symbol: "gearshape", prominent: true, large: true) {
                        Permissions.openFullDiskAccessSettings()
                    }
                    CapsuleButton(title: "Scan Again", symbol: "arrow.clockwise", large: true) {
                        screen.startScan(.permissions)
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
        } else if flow.groups.isEmpty {
            EmptyStateView(module: .protection, title: "No apps hold privacy permissions",
                           message: "No app has been allowed to use your camera, microphone, screen, files or other protected data.",
                           actionTitle: "Scan Again", action: { screen.startScan(.permissions) })
        } else {
            HStack(alignment: .top, spacing: Spacing.m) {
                ProtectionPermissionSidebar(groups: flow.groups, focusedID: focusedGroup?.id) { focusedGroupID = $0 }
                    .frame(width: 270)
                if let group = focusedGroup {
                    ProtectionPermissionDetail(screen: screen, flow: flow, group: group)
                }
            }
            .frame(maxHeight: .infinity)
            ResultsFooter(module: .protection, selectedBytes: 0, selectedCount: flow.selectedCount,
                          actionTitle: "Reset Access", totalCount: flow.groups.allItems.count, showsBytes: false) {
                screen.requestPermissionReset()
            }
        }
    }

    private var focusedGroup: ScanGroup? {
        flow.groups.first { $0.id == focusedGroupID } ?? flow.groups.first
    }
}

/// The permission list (left pane).
struct ProtectionPermissionSidebar: View {
    var groups: [ScanGroup]
    var focusedID: String?
    var onFocus: (String) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        ScrollView {
            VStack(spacing: 2) {
                ForEach(groups) { group in
                    Button {
                        onFocus(group.id)
                    } label: {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: group.symbol)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ModuleID.protection.palette.accentText)
                                .frame(width: 22)
                            Text(group.title)
                                .font(SpruceFont.body)
                                .foregroundStyle(Ink.primary)
                                .lineLimit(1)
                            Spacer(minLength: Spacing.s)
                            if group.selectedCount > 0 {
                                Text("\(group.selectedCount)/")
                                    .font(SpruceFont.captionDigits)
                                    .foregroundStyle(ModuleID.protection.palette.accentText)
                            }
                            Text(CountFormat.grouped(group.totalCount))
                                .font(SpruceFont.captionDigits)
                                .foregroundStyle(ink.tertiary)
                        }
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(group.id == focusedID ? ink.selectedFill : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(group.title), \(CountFormat.items(group.totalCount, singular: "app"))")
                }
            }
            .padding(Spacing.s)
        }
        .prismSurface(radius: Radius.container)
    }
}

/// Apps holding one permission (right pane).
struct ProtectionPermissionDetail: View {
    @Bindable var screen: ProtectionScreenModel
    @Bindable var flow: ScanFlowModel
    var group: ScanGroup
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                PrismCategoryBadge(symbol: group.symbol, module: .protection, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(SpruceFont.headline)
                        .foregroundStyle(Ink.primary)
                    Text(group.detail)
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.s)
                CapsuleButton(title: "Open in System Settings", symbol: "gearshape") {
                    if let first = group.items.first {
                        ProtectionPermissionsReviewer.openSettings(for: first)
                    }
                }
            }
            HStack(spacing: Spacing.s) {
                let resettable = group.items.filter { ProtectionPermissionPlan(item: $0)?.resetArguments != nil }
                let selected = resettable.filter(\.isSelected).count
                SpruceCheckbox(state: selected == 0 ? .none : (selected == resettable.count ? .all : .some),
                               module: .protection, label: "Select all") {
                    let select = selected != resettable.count
                    for item in resettable { flow.setSelected(select, itemID: item.id) }
                }
                .disabled(resettable.isEmpty)
                Text("Select all that can be reset here")
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        ProtectionPermissionRow(item: item,
                                                onToggle: { flow.toggle(itemID: item.id) },
                                                onReset: { screen.reset(item) })
                        if item.id != group.items.last?.id {
                            Divider().overlay(Ink.hairline).padding(.leading, 52)
                        }
                    }
                }
            }
            .prismSurface(radius: Radius.container)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One app holding a permission.
struct ProtectionPermissionRow: View {
    var item: ScanItem
    var onToggle: () -> Void
    var onReset: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var plan: ProtectionPermissionPlan? { ProtectionPermissionPlan(item: item) }
    private var canReset: Bool { plan?.resetArguments != nil }
    private var isLeftover: Bool { item.metadata[ProtectionPermissionMetaKey.missing] == "1" }
    private var appURL: URL? { item.metadata[ProtectionPermissionMetaKey.appPath].map { URL(fileURLWithPath: $0) } }

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.m) {
            if canReset {
                SpruceCheckbox(isOn: item.isSelected, module: .protection, label: item.title, action: onToggle)
            } else {
                Image(systemName: "lock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.tertiary)
                    .frame(width: 18, height: 18)
                    .help("Change this one in System Settings")
            }
            ItemIcon(url: appURL, symbol: item.symbol, size: 26, module: .protection)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(SpruceFont.body)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isLeftover {
                        PrismChip(text: "Leftover", color: StatusColor.warning, symbol: "archivebox")
                    }
                }
                Text(item.subtitle ?? "")
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.s)
            if let date = item.modified {
                Text(DurationFormat.relative(date))
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .help("Last changed")
            }
            if hovering {
                if canReset {
                    CapsuleButton(title: "Reset", symbol: "arrow.counterclockwise", action: onReset)
                        .help("Reset this app's access; it will ask again next time")
                } else {
                    CapsuleButton(title: "Settings", symbol: "gearshape") {
                        ProtectionPermissionsReviewer.openSettings(for: item)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 7)
        .frame(minHeight: 46)
        .background(Rectangle().fill(hovering ? ink.subtleFill : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { if canReset { onToggle() } }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help(item.note ?? "")
        .contextMenu {
            if canReset {
                Button("Reset Access") { onReset() }
            }
            Button("Open in System Settings") { ProtectionPermissionsReviewer.openSettings(for: item) }
            if let url = appURL {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isSelected ? "selected" : "not selected")
    }
}
