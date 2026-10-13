import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Advanced: operations log, Spruce's data folders, activity history and a full reset.
struct SettingsAdvancedTab: View {
    @Bindable var store: SettingsStore
    @Environment(AppModel.self) private var model

    @State private var recentLines: [SettingsLogLine] = []
    @State private var logSize: Int64 = 0
    @State private var logExists = false
    @State private var confirmClearHistory = false
    @State private var confirmReset = false
    @State private var resetDone = false

    var body: some View {
        SettingsPage(tab: .advanced) {
            logSection
            dataSection
            historySection
            resetSection
        }
        .task { await loadLog() }
        .alert("Clear activity history?", isPresented: $confirmClearHistory) {
            Button("Clear History", role: .destructive) { model.history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Activity loses its record of scans, cleanups and space freed. Files on your Mac and the operations log aren't affected.")
        }
        .alert("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset Settings", role: .destructive) { resetSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every preference returns to its default, including Checkup choices, Cleanup exclusions, Clutter locations, alert thresholds, reminders, automatic scans and all ignore lists. History and logs are kept.")
        }
    }

    // MARK: Operations log

    private var logSection: some View {
        Section {
            HStack(spacing: Spacing.m) {
                SettingsRowLabel(title: "Operations log",
                                 detail: logExists
                                     ? "Every file Spruce moved, removed or changed, with the result. \(ByteFormat.string(logSize))."
                                     : "Nothing recorded yet. Every file Spruce moves or removes will be listed here.",
                                 symbol: "list.bullet.rectangle", tint: ModuleID.toolbox.palette.accentText)
                Spacer()
                Button("Open Log") { SettingsFinder.open(SprucePaths.operationsLog) }
                    .disabled(!logExists)
                Button("Show in Finder") { SettingsFinder.reveal(SprucePaths.operationsLog.path) }
                    .disabled(!logExists)
            }
            .controlSize(.small)
            if !recentLines.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(recentLines) { line in
                        SettingsLogLineRow(line: line)
                    }
                }
                .padding(Spacing.s)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.black.opacity(0.25)))
            }
        } header: {
            SettingsSectionHeader(title: "Logs", trailing: recentLines.isEmpty ? nil : "Latest entries")
        }
    }

    // MARK: Data folders

    private var dataSection: some View {
        Section {
            HStack(spacing: Spacing.m) {
                SettingsRowLabel(title: "App data",
                                 detail: SprucePaths.applicationSupport.path.abbreviatingHome,
                                 symbol: "folder", tint: ModuleID.toolbox.palette.accentText)
                Spacer()
                Button("Show in Finder") { SettingsFinder.revealFolder(SprucePaths.applicationSupport) }
                    .controlSize(.small)
            }
            HStack(spacing: Spacing.m) {
                SettingsRowLabel(title: "Logs folder",
                                 detail: SprucePaths.logs.path.abbreviatingHome,
                                 symbol: "folder.badge.gearshape", tint: ModuleID.toolbox.palette.accentText)
                Spacer()
                Button("Show in Finder") { SettingsFinder.revealFolder(SprucePaths.logs) }
                    .controlSize(.small)
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Settings and history are plain JSON files. Removing Spruce's app data resets it completely.")
        }
    }

    // MARK: History

    private var historySection: some View {
        let count = model.history.history.entries.count
        return Section {
            HStack(spacing: Spacing.m) {
                SettingsRowLabel(title: "Activity history",
                                 detail: count == 0 ? "No activity recorded yet."
                                     : "Activity's charts and totals draw on \(CountFormat.items(count, singular: "recorded event")).",
                                 symbol: "chart.bar.xaxis", tint: ModuleID.toolbox.palette.accentText)
                Spacer()
                Button("Clear History…", role: .destructive) { confirmClearHistory = true }
                    .controlSize(.small)
                    .disabled(count == 0)
            }
        } header: {
            Text("History")
        }
    }

    // MARK: Reset

    private var resetSection: some View {
        Section {
            HStack(spacing: Spacing.m) {
                SettingsRowLabel(title: "Reset all settings",
                                 detail: resetDone ? "Settings were reset to their defaults."
                                     : "Return every preference in this window to its default.",
                                 symbol: "arrow.counterclockwise", tint: StatusColor.danger)
                Spacer()
                Button("Reset Settings…", role: .destructive) { confirmReset = true }
                    .controlSize(.small)
            }
        } header: {
            Text("Reset")
        }
    }

    // MARK: Actions

    private func loadLog() async {
        let url = SprucePaths.operationsLog
        let snapshot = await Task.detached(priority: .utility) { () -> (exists: Bool, size: Int64, lines: [String]) in
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path) else { return (false, 0, []) }
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return (true, size, OperationLog.shared.tail(6))
        }.value
        logExists = snapshot.exists
        logSize = snapshot.size
        recentLines = snapshot.lines.reversed().enumerated().map { SettingsLogLine(index: $0.offset, line: $0.element) }
    }

    private func resetSettings() {
        var fresh = SpruceSettings()
        // Don't replay the welcome guide just because preferences were reset.
        fresh.hasCompletedOnboarding = store.settings.hasCompletedOnboarding
        store.settings = fresh
        if SettingsLoginItem.state.isRequested != fresh.launchAtLogin {
            SettingsLoginItem.set(fresh.launchAtLogin, store: store)
        }
        // Preferences shown in this window but kept outside `SpruceSettings`.
        SettingsReminderScheduler.resetPreferences()
        ProtectionScreenModel.shared(for: model.protection).backgroundSchedule = .defaultValue
        ApplicationsScreenModel.shared(for: model.applications).offerLeftoversOnTrash = ApplicationsPreferences().offerLeftoversOnTrash
        SettingsReminderScheduler.sync(fresh)
        resetDone = true
    }
}

/// One parsed operations-log line (tab separated: date, module, action, result, bytes, detail).
struct SettingsLogLine: Identifiable {
    var id: Int
    var date: Date?
    var module: String
    var action: String
    var result: String
    var bytes: Int64
    var detail: String

    init(index: Int, line: String) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        func field(_ i: Int) -> String { fields.indices.contains(i) ? fields[i] : "" }
        id = index
        date = ISO8601DateFormatter().date(from: field(0))
        module = ModuleID(rawValue: field(1))?.title ?? field(1)
        action = field(2)
        result = field(3)
        bytes = Int64(field(4)) ?? 0
        detail = fields.count > 5 ? fields[5...].joined(separator: " ") : (fields.count == 1 ? line : "")
    }

    var succeeded: Bool {
        let lower = result.lowercased()
        return lower.isEmpty || lower == "ok"
    }
}

private struct SettingsLogLineRow: View {
    var line: SettingsLogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Circle()
                .fill(line.succeeded ? StatusColor.success : StatusColor.warning)
                .frame(width: 6, height: 6)
            if let date = line.date {
                Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(SpruceFont.mono)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize()
            }
            Text([line.module, line.action].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(SpruceFont.caption.weight(.medium))
                .foregroundStyle(Ink.secondary)
                .fixedSize()
            Text(line.detail.abbreviatingHome)
                .font(SpruceFont.mono)
                .foregroundStyle(Ink.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if line.bytes > 0 {
                Text(ByteFormat.string(line.bytes))
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize()
            }
        }
        .help([line.result, line.detail].filter { !$0.isEmpty }.joined(separator: " — "))
    }
}
