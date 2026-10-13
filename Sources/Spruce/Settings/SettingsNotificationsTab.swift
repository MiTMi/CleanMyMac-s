import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Notifications: permission status, alert toggles with thresholds, the app offers, the
/// Checkup reminder (interval and time of day) and the temperature unit the menu bar
/// monitor uses.
struct SettingsNotificationsTab: View {
    @Bindable var store: SettingsStore
    @Environment(AppModel.self) private var model

    @State private var permission: SettingsNotificationStatus = .notDetermined
    @State private var isRequesting = false
    /// Reminder interval while reminders are on (`SettingsReminderScheduler.storedFrequency`).
    @AppStorage(SettingsReminderScheduler.frequencyKey) private var storedFrequency: SettingsReminderFrequency = .weekly
    /// Reminder time, minutes after midnight (`SettingsReminderScheduler.minuteOfDay`).
    @AppStorage(SettingsReminderScheduler.minuteOfDayKey) private var reminderMinute: Int = SettingsReminderScheduler.defaultMinuteOfDay

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
            Text("Alerts appear while Spruce is running; Checkup reminders are scheduled with macOS itself. Nothing is sent anywhere.")
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
        let applications = ApplicationsScreenModel.shared(for: model.applications)
        let offerBinding = Binding(
            get: { applications.offerLeftoversOnTrash },
            set: { applications.offerLeftoversOnTrash = $0 }
        )
        return Section {
            SettingsToggleRow(title: "App updates available",
                              detail: "While this is on, Spruce looks up newer versions of your apps online once a day (and during Checkup) and tells you about new ones.",
                              symbol: "arrow.down.app", isOn: $store.settings.notifyUpdates)
            SettingsToggleRow(title: "Offer to finish removing apps dragged to the Trash",
                              detail: "When you drag an app to the Trash, Spruce offers to remove the files it leaves behind. You review them first.",
                              symbol: "trash.square", isOn: offerBinding)
            if applications.offerLeftoversOnTrash && !model.hasFullDiskAccess {
                HStack(spacing: Spacing.m) {
                    SettingsNote(text: "Needs Full Disk Access: macOS doesn't let Spruce see the Trash without it.",
                                 symbol: "lock.fill")
                    Button("Open System Settings") { Permissions.openFullDiskAccessSettings() }
                        .controlSize(.small)
                }
            }
            SettingsToggleRow(title: "Threats found",
                              detail: store.settings.realtimeProtection
                                  ? "When real-time protection spots a suspicious startup item."
                                  : "Needs real-time protection (Settings › Protection).",
                              symbol: "exclamationmark.shield", isOn: $store.settings.notifyThreats)
        } header: {
            Text("Apps & Security")
        }
    }

    // MARK: Checkup reminder

    /// The interval in effect: off, or the stored interval while reminders are on.
    private var reminderFrequency: SettingsReminderFrequency {
        store.settings.weeklyCleanupReminder ? SettingsReminderScheduler.usable(storedFrequency) : .off
    }

    private var frequencyBinding: Binding<SettingsReminderFrequency> {
        Binding(
            get: { reminderFrequency },
            set: { choice in
                if choice == .off {
                    store.settings.weeklyCleanupReminder = false
                } else {
                    storedFrequency = choice
                    store.settings.weeklyCleanupReminder = true
                }
                // A new choice starts from the regular schedule.
                SettingsReminderScheduler.snoozedUntil = nil
                SettingsReminderScheduler.sync(store.settings)
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { SettingsReminderScheduler.time(forMinuteOfDay: reminderMinute) },
            set: { date in
                let minute = SettingsReminderScheduler.minute(of: date)
                guard minute != reminderMinute else { return }
                reminderMinute = minute
                SettingsReminderScheduler.sync(store.settings)
            }
        )
    }

    private var reminderSection: some View {
        let frequency = reminderFrequency
        let next = SettingsReminderScheduler.nextReminder(frequency: frequency, minuteOfDay: reminderMinute,
                                                          history: model.history.history)
        return Section {
            Picker(selection: frequencyBinding) {
                ForEach(SettingsReminderFrequency.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                SettingsRowLabel(title: "Checkup reminder",
                                 detail: "A nudge when you haven't run a Checkup for a while. Running one yourself pushes the next reminder back.",
                                 symbol: "calendar.badge.clock")
            }
            DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
                Text("Remind me at")
            }
            .disabled(frequency == .off)
            .padding(.leading, 30)
            if frequency != .off {
                if permission == .denied {
                    SettingsNote(text: "Notifications are off for Spruce, so the reminder can't appear.")
                } else if permission != .unavailable, let next {
                    SettingsNote(text: "Next reminder \(Self.describe(next)). Click it, or its Scan Now button, to start a Checkup.",
                                 symbol: "clock", color: StatusColor.info)
                }
            }
        } header: {
            Text("Reminders")
        }
    }

    // MARK: Units

    private var unitsSection: some View {
        Section {
            HStack {
                Picker(selection: $store.settings.temperatureUnitCelsius) {
                    Text("Celsius (°C)").tag(true)
                    Text("Fahrenheit (°F)").tag(false)
                } label: {
                    SettingsRowLabel(title: "Temperature",
                                     detail: "Used by the menu bar monitor, for example for the startup disk's temperature when the disk reports one.",
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

    /// "tomorrow at 10:00 AM", "on Tuesday, Oct 20 at 10:00 AM".
    private static func describe(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let day = sameYear
            ? date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        return "on \(day) at \(time)"
    }

    // MARK: Helpers

    private func refreshPermission() async {
        permission = await SettingsNotificationAccess.status()
    }
}
