import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Notifications: permission status, alert toggles with thresholds, the weekly reminder
/// and the temperature unit used by the monitor.
struct SettingsNotificationsTab: View {
    @Bindable var store: SettingsStore

    @State private var permission: SettingsNotificationStatus = .notDetermined
    @State private var isRequesting = false

    var body: some View {
        SettingsPage(tab: .notifications) {
            permissionSection
            storageSection
            performanceSection
            appsSection
            reminderSection
            unitsSection
        }
        .task { await refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshPermission() }
        }
    }

    // MARK: Permission

    private var permissionSection: some View {
        Section {
            HStack(spacing: Spacing.m) {
                PrismCategoryBadge(symbol: "bell.fill", module: .performance, size: 30,
                                   isDimmed: permission != .allowed)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.s) {
                        Text("Notification permission").font(SpruceFont.body).foregroundStyle(Ink.primary)
                        StatusPill(text: permission.title, status: permission.tileStatus)
                    }
                    Text(permission.detail).font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
                }
                Spacer()
                permissionButton
            }
        } footer: {
            Text("Alerts appear while Spruce is running; the weekly reminder is scheduled with macOS itself. Nothing is sent anywhere.")
        }
    }

    @ViewBuilder
    private var permissionButton: some View {
        switch permission {
        case .notDetermined:
            Button {
                Task {
                    isRequesting = true
                    permission = await SettingsNotificationAccess.request()
                    isRequesting = false
                    SettingsReminderScheduler.sync(store.settings)
                }
            } label: {
                if isRequesting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Allow Notifications…")
                }
            }
            .disabled(isRequesting)
        case .denied, .allowed:
            Button("Open System Settings") { SettingsNotificationAccess.openSystemSettings() }
        case .unavailable:
            EmptyView()
        }
    }

    // MARK: Alerts

    private var storageSection: some View {
        Section {
            SettingsToggleRow(title: "Low disk space",
                              detail: "When free space on the startup disk drops below the level you choose.",
                              symbol: "internaldrive", isOn: $store.settings.notifyLowDisk)
            Picker("Warn below", selection: $store.settings.lowDiskThresholdPercent) {
                ForEach(SettingsChoices.including(store.settings.lowDiskThresholdPercent, in: SettingsChoices.lowDiskPercents),
                        id: \.self) { percent in
                    Text(verbatim: "\(percent)% free").tag(percent)
                }
            }
            .disabled(!store.settings.notifyLowDisk)
            .padding(.leading, 30)
            SettingsToggleRow(title: "Large Trash",
                              detail: "When the Trash grows past the size you choose.",
                              symbol: "trash", isOn: $store.settings.notifyTrashSize)
            Picker("Notify above", selection: $store.settings.trashSizeThreshold) {
                ForEach(SettingsChoices.including(store.settings.trashSizeThreshold, in: SettingsChoices.trashSizes),
                        id: \.self) { size in
                    Text(ByteFormat.string(size)).tag(size)
                }
            }
            .disabled(!store.settings.notifyTrashSize)
            .padding(.leading, 30)
        } header: {
            Text("Storage")
        }
    }

    private var performanceSection: some View {
        Section {
            SettingsToggleRow(title: "High memory pressure",
                              detail: "When macOS runs short of memory for a while, with a shortcut to free some up.",
                              symbol: "memorychip", isOn: $store.settings.notifyHighMemory)
            SettingsToggleRow(title: "App using a lot of CPU",
                              detail: "When one app keeps a processor core busy for minutes.",
                              symbol: "cpu", isOn: $store.settings.notifyHighCPU)
        } header: {
            Text("Performance")
        }
    }

    private var appsSection: some View {
        Section {
            SettingsToggleRow(title: "App updates available",
                              detail: "When apps you use have newer versions. While this is on, Checkup also looks up updates online.",
                              symbol: "arrow.down.app", isOn: $store.settings.notifyUpdates)
            SettingsToggleRow(title: "Threats found",
                              detail: store.settings.realtimeProtection
                                  ? "When real-time protection spots a suspicious startup item."
                                  : "Needs real-time protection (Settings › Protection).",
                              symbol: "exclamationmark.shield", isOn: $store.settings.notifyThreats)
        } header: {
            Text("Apps & Security")
        }
    }

    private var reminderSection: some View {
        Section {
            SettingsToggleRow(title: "Weekly Checkup reminder",
                              detail: "\(SettingsReminderScheduler.scheduleDescription). Clicking the reminder starts a Checkup.",
                              symbol: "calendar.badge.clock", isOn: $store.settings.weeklyCleanupReminder)
            if store.settings.weeklyCleanupReminder && permission == .denied {
                SettingsNote(text: "Notifications are off for Spruce, so the reminder can't appear.")
            }
        } header: {
            Text("Reminders")
        }
    }

    private var unitsSection: some View {
        Section {
            HStack {
                Picker(selection: $store.settings.temperatureUnitCelsius) {
                    Text("Celsius (°C)").tag(true)
                    Text("Fahrenheit (°F)").tag(false)
                } label: {
                    SettingsRowLabel(title: "Temperature", detail: "Used wherever Spruce shows temperatures.",
                                     symbol: "thermometer.medium")
                }
                Button("Match System") {
                    store.settings.temperatureUnitCelsius = SettingsChoices.systemPrefersCelsius
                }
                .controlSize(.small)
                .disabled(store.settings.temperatureUnitCelsius == SettingsChoices.systemPrefersCelsius)
            }
        } header: {
            Text("Units")
        }
    }

    // MARK: Helpers

    private func refreshPermission() async {
        permission = await SettingsNotificationAccess.status()
    }
}
