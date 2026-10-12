import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Privacy & Permissions: live Full Disk Access status, App Management, administrator
/// prompts, notifications and Spruce's privacy promise.
struct SettingsPrivacyTab: View {
    @Bindable var store: SettingsStore
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .privacy
    @State private var notifications: SettingsNotificationStatus = .notDetermined

    var body: some View {
        SettingsPage(tab: .privacy) {
            fullDiskAccessSection
            appManagementSection
            administratorSection
            notificationsSection
            privacySection
        }
        .task {
            // Full Disk Access has no change callback: poll while this tab is visible.
            while !Task.isCancelled {
                model.refreshPermissions()
                notifications = await SettingsNotificationAccess.status()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    // MARK: Full Disk Access

    private var fullDiskAccessSection: some View {
        let granted = model.hasFullDiskAccess
        return Section {
            HStack(alignment: .top, spacing: Spacing.m) {
                PrismCategoryBadge(symbol: "externaldrive.badge.checkmark", module: .applications, size: 30,
                                   isDimmed: !granted)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Spacing.s) {
                        Text("Full Disk Access").font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                        StatusPill(text: granted ? "Granted" : "Not granted", status: granted ? .clear : .attention)
                    }
                    Text("Lets Spruce look inside folders macOS keeps private: Mail downloads, Safari and Messages caches, other apps' containers and the Trash. Spruce only reads them while scanning; nothing is removed without your review.")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if granted {
                SettingsNote(text: "Spruce can scan every location. You can turn this off at any time in System Settings.",
                             symbol: "checkmark.circle.fill", color: StatusColor.success)
            } else {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SettingsStepRow(number: 1, text: "Click Open System Settings below.", module: .applications)
                    SettingsStepRow(number: 2, text: "Turn on Spruce in the Full Disk Access list. If it isn't there, click + and choose Spruce, or drag it in from Finder.", module: .applications)
                    SettingsStepRow(number: 3, text: "Come back here. The status updates by itself; if macOS offers to quit and reopen Spruce, that's fine.", module: .applications)
                }
                .padding(.vertical, 2)
                HStack(spacing: Spacing.s) {
                    Button("Open System Settings") {
                        model.refreshPermissions()
                        Permissions.openFullDiskAccessSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Show Spruce in Finder") { SettingsFinder.revealSpruce() }
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
                }
                .controlSize(.small)
            }
        } header: {
            Text("Disk Access")
        }
    }

    // MARK: Other permissions

    private var appManagementSection: some View {
        Section {
            HStack(alignment: .top, spacing: Spacing.m) {
                SettingsRowLabel(title: "App Management",
                                 detail: "macOS asks before one app changes or deletes another. Spruce needs this only when you uninstall, reset or update an app; macOS prompts the first time.",
                                 symbol: "square.grid.2x2", tint: ModuleID.applications.palette.accentText)
                Spacer()
                Button("Open Settings") { Permissions.openAppManagementSettings() }
                    .controlSize(.small)
            }
        }
    }

    private var administratorSection: some View {
        Section {
            SettingsRowLabel(title: "Administrator password",
                             detail: "Asked for only by specific system tasks, such as flushing the DNS cache, running maintenance scripts or moving system-owned files to the Trash. Spruce installs no background helper and never stores your password.",
                             symbol: "lock.shield", tint: ModuleID.applications.palette.accentText)
        }
    }

    private var notificationsSection: some View {
        Section {
            HStack(spacing: Spacing.m) {
                SettingsRowLabel(title: "Notifications", detail: notifications.detail,
                                 symbol: "bell", tint: ModuleID.applications.palette.accentText)
                Spacer()
                StatusPill(text: notifications.title, status: notifications.tileStatus)
                Button("Manage…") { selectedTab = .notifications }
                    .controlSize(.small)
            }
        }
    }

    // MARK: Privacy promise

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s + 2) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(ModuleID.applications.palette.accentText)
                    Text("No data leaves your Mac").font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                }
                SettingsPrivacyPoint(symbol: "chart.bar.xaxis", text: "No analytics, telemetry or crash reporting, and no account.")
                SettingsPrivacyPoint(symbol: "network", text: "The only network requests are update checks (app update feeds, the App Store lookup and Homebrew), made when you open Updater or keep update alerts on.")
                SettingsPrivacyPoint(symbol: "internaldrive", text: "Settings, history and the operations log stay in your Library folder. Advanced lets you open or clear them.")
                SettingsPrivacyPoint(symbol: "trash.slash", text: "Every removal goes through one audited path that refuses protected system locations and keeps a log.")
            }
            .padding(.vertical, 2)
        } header: {
            Text("Privacy")
        }
    }
}

private struct SettingsPrivacyPoint: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s + 2) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Ink.tertiary)
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
