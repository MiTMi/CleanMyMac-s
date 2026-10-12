import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Protection: real-time protection and the malware scan depth (`SpruceSettings.scanDepth`).
struct SettingsProtectionTab: View {
    @Bindable var store: SettingsStore
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .protection

    @State private var monitorActive = false
    @State private var noticedCount = 0

    private var depth: ProtectionScanDepth { ProtectionScanDepth(setting: store.settings.scanDepth) }

    var body: some View {
        SettingsPage(tab: .protection) {
            realtimeSection
            depthSection
            accessSection
        }
        .task(id: store.settings.realtimeProtection) {
            // The engine follows the setting asynchronously; read its state once it settled.
            try? await Task.sleep(for: .milliseconds(400))
            monitorActive = model.protection.isRealtimeProtectionActive
            noticedCount = model.protection.realtimeEvents.count
        }
    }

    // MARK: Sections

    private var realtimeSection: some View {
        Section {
            SettingsToggleRow(title: "Real-time protection",
                              detail: "Watches the folders malware uses to start with your Mac and alerts you as soon as a new startup item appears. It never removes anything on its own.",
                              symbol: "shield.lefthalf.filled", tint: ModuleID.protection.palette.accentText,
                              isOn: $store.settings.realtimeProtection)
            HStack(spacing: Spacing.s) {
                if store.settings.realtimeProtection {
                    StatusPill(text: monitorActive ? "Watching" : "Starting…", status: monitorActive ? .clear : .info)
                    if noticedCount > 0 {
                        Text(noticedCount == 1 ? "1 new startup item noticed since launch"
                             : "\(noticedCount) new startup items noticed since launch")
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                } else {
                    StatusPill(text: "Off", status: .attention)
                    Text("New startup items won't be checked until you scan.")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                }
                Spacer()
            }
            SettingsToggleRow(title: "Alert me about threats",
                              detail: "Shows a notification when real-time protection spots something suspicious.",
                              symbol: "bell.badge", isOn: $store.settings.notifyThreats)
                .disabled(!store.settings.realtimeProtection)
        } header: {
            Text("Real-Time Protection")
        } footer: {
            HStack(spacing: 4) {
                Text("More alerts live in")
                Button("Notifications") { selectedTab = .notifications }
                    .buttonStyle(.link)
                Text(".")
            }
        }
    }

    private var depthSection: some View {
        Section {
            ForEach(ProtectionScanDepth.allCases) { option in
                SettingsDepthOption(depth: option, isSelected: depth == option) {
                    store.settings.scanDepth = option.rawValue
                }
            }
        } header: {
            Text("Malware Scan Depth")
        } footer: {
            Text("Applies to scans from Protection › Malware Removal. Checkup always runs a quick threat scan so it stays fast.")
        }
    }

    @ViewBuilder
    private var accessSection: some View {
        if !model.hasFullDiskAccess {
            Section {
                HStack(spacing: Spacing.m) {
                    SettingsNote(text: "Without Full Disk Access, some locations, such as Mail downloads and other apps' containers, can't be checked.",
                                 symbol: "lock.fill")
                    Button("Open System Settings") { Permissions.openFullDiskAccessSettings() }
                        .controlSize(.small)
                }
            } header: {
                Text("Coverage")
            }
        }
    }
}

/// One selectable scan depth with its coverage, speed and purpose.
private struct SettingsDepthOption: View {
    var depth: ProtectionScanDepth
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        let accent = ModuleID.protection.palette.accent
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.m) {
                ZStack {
                    Circle().strokeBorder(isSelected ? accent : Color.white.opacity(0.42), lineWidth: 1.5)
                    if isSelected {
                        Circle().fill(accent).padding(4)
                    }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Spacing.s) {
                        Text(depth.title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                        if depth == .balanced {
                            PrismChip(text: "Recommended", color: StatusColor.success)
                        }
                        Spacer()
                        Label(depth.speed, systemImage: "clock")
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                    Text(depth.coverage)
                        .font(SpruceFont.callout)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(depth.purpose)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.10) : (hovering ? Ink.subtleFill : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
