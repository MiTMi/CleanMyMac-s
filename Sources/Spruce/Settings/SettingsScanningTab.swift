import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Scanning: Checkup composition, Cleanup category exclusions, Clutter thresholds and
/// the folders Clutter scans.
struct SettingsScanningTab: View {
    @Bindable var store: SettingsStore

    var body: some View {
        SettingsPage(tab: .scanning) {
            SettingsCheckupModulesSection(store: store)
            SettingsCleanupCategoriesSection(store: store)
            SettingsThresholdsSection(store: store)
            SettingsClutterLocationsSection(store: store)
        }
    }
}

// MARK: - Checkup

private struct SettingsCheckupModulesSection: View {
    @Bindable var store: SettingsStore

    private var includedCount: Int {
        ModuleID.checkupContributors.filter { store.settings.checkupModules.contains($0) }.count
    }

    var body: some View {
        Section {
            ForEach(ModuleID.checkupContributors) { module in
                Toggle(isOn: binding(for: module)) {
                    HStack(alignment: .center, spacing: Spacing.m) {
                        PrismCategoryBadge(symbol: module.symbol, module: module, size: 26,
                                           isDimmed: !store.settings.checkupModules.contains(module))
                        SettingsRowLabel(title: module.title, detail: module.tagline)
                    }
                }
                .toggleStyle(.switch)
            }
            if includedCount == 0 {
                SettingsNote(text: "Checkup has nothing to scan. Include at least one module.")
            }
        } header: {
            SettingsSectionHeader(title: "Checkup",
                                  trailing: "\(includedCount) of \(ModuleID.checkupContributors.count) included")
        } footer: {
            Text("Excluded modules still appear in Checkup, dimmed, and you can always scan them from their own screen.")
        }
    }

    private func binding(for module: ModuleID) -> Binding<Bool> {
        Binding(
            get: { store.settings.checkupModules.contains(module) },
            set: { include in
                var set = Set(store.settings.checkupModules)
                if include { set.insert(module) } else { set.remove(module) }
                store.settings.checkupModules = ModuleID.checkupContributors.filter { set.contains($0) }
            }
        )
    }
}

// MARK: - Cleanup categories

private struct SettingsCleanupCategoriesSection: View {
    @Bindable var store: SettingsStore

    private var categories: [CategoryDescriptor] { CleanupCatalog.categories }

    private var includedCount: Int {
        let excluded = Set(store.settings.excludedCleanupCategories)
        return categories.filter { !excluded.contains($0.id) }.count
    }

    var body: some View {
        Section {
            ForEach(categories) { category in
                Toggle(isOn: binding(for: category.id)) {
                    SettingsRowLabel(title: category.title,
                                     detail: category.detail.isEmpty ? nil : category.detail,
                                     symbol: category.symbol,
                                     tint: ModuleID.cleanup.palette.accentText)
                }
                .toggleStyle(.switch)
            }
            if !store.settings.excludedCleanupCategories.isEmpty {
                HStack {
                    Spacer()
                    Button("Include All Categories") {
                        store.settings.excludedCleanupCategories = []
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            SettingsSectionHeader(title: "Cleanup Categories",
                                  trailing: "\(includedCount) of \(categories.count) included")
        } footer: {
            Text("Turned-off categories are skipped by Cleanup and by Checkup.")
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !store.settings.excludedCleanupCategories.contains(id) },
            set: { include in
                var excluded = store.settings.excludedCleanupCategories
                if include {
                    excluded.removeAll { $0 == id }
                } else if !excluded.contains(id) {
                    excluded.append(id)
                }
                store.settings.excludedCleanupCategories = excluded
            }
        )
    }
}

// MARK: - Thresholds

private struct SettingsThresholdsSection: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Section {
            Picker(selection: $store.settings.largeFileThreshold) {
                ForEach(SettingsChoices.including(store.settings.largeFileThreshold, in: SettingsChoices.largeFileSizes),
                        id: \.self) { size in
                    Text(ByteFormat.string(size)).tag(size)
                }
            } label: {
                SettingsRowLabel(title: "Large file size",
                                 detail: "Large & Old Files lists files at least this big.",
                                 symbol: "doc.zipper")
            }
            Picker(selection: $store.settings.oldFileDays) {
                ForEach(SettingsChoices.including(store.settings.oldFileDays, in: SettingsChoices.ageDays), id: \.self) { days in
                    Text(SettingsChoices.dayLabel(days)).tag(days)
                }
            } label: {
                SettingsRowLabel(title: "Old after",
                                 detail: "Files you haven't opened for this long count as old.",
                                 symbol: "clock.arrow.circlepath")
            }
            Picker(selection: $store.settings.unusedAppDays) {
                ForEach(SettingsChoices.including(store.settings.unusedAppDays, in: SettingsChoices.ageDays), id: \.self) { days in
                    Text(SettingsChoices.dayLabel(days)).tag(days)
                }
            } label: {
                SettingsRowLabel(title: "Unused apps after",
                                 detail: "Applications flags apps you haven't opened for this long.",
                                 symbol: "app.dashed")
            }
        } header: {
            Text("Clutter & Applications")
        }
    }
}

// MARK: - Clutter locations

private struct SettingsClutterLocationsSection: View {
    @Bindable var store: SettingsStore
    @State private var volumes: [ClutterLocationOption] = []

    private var locations: [String] { store.settings.clutterLocations }

    /// Standard folders and mounted disks not covered yet.
    private var quickAddOptions: [ClutterLocationOption] {
        (ClutterLocations.standard + volumes).filter { option in
            SettingsClutterLocations.merged(locations, adding: [option.path]) != locations
        }
    }

    var body: some View {
        Section {
            if locations.isEmpty {
                HStack {
                    SettingsNote(text: "Clutter has no location to scan.")
                    Button("Use Home Folder") {
                        store.settings.clutterLocations = ["~"]
                    }
                    .controlSize(.small)
                }
            }
            ForEach(locations, id: \.self) { path in
                SettingsLocationRow(path: path) {
                    store.settings.clutterLocations = SettingsClutterLocations.removing(path, from: locations)
                }
            }
            HStack(spacing: Spacing.s) {
                Button {
                    chooseFolders()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                }
                if !quickAddOptions.isEmpty {
                    Menu("Add Location") {
                        ForEach(quickAddOptions) { option in
                            Button {
                                store.settings.clutterLocations = SettingsClutterLocations.merged(locations, adding: [option.path])
                            } label: {
                                Label(option.detail.map { "\(option.title) — \($0)" } ?? option.title,
                                      systemImage: option.symbol)
                            }
                        }
                    }
                    .fixedSize()
                }
                Spacer()
            }
            .controlSize(.small)
            .onAppear { volumes = ClutterLocations.volumes() }
        } header: {
            SettingsSectionHeader(title: "Clutter Locations",
                                  trailing: locations.isEmpty ? nil : ClutterLocations.summary(locations))
        } footer: {
            Text("Clutter looks for large, old, duplicate and similar files here. Folders inside a chosen location are included automatically.")
        }
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose folders or disks for Clutter to scan."
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map(\.path)
        store.settings.clutterLocations = SettingsClutterLocations.merged(locations, adding: paths)
        volumes = ClutterLocations.volumes()
    }
}

private struct SettingsLocationRow: View {
    var path: String
    var onRemove: () -> Void

    var body: some View {
        let option = ClutterLocations.option(for: path)
        let exists = ClutterLocations.exists(path)
        HStack(spacing: Spacing.m) {
            Image(systemName: option.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ModuleID.clutter.palette.accentText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.s) {
                    Text(option.title).font(SpruceFont.body).foregroundStyle(Ink.primary)
                    if !exists {
                        PrismChip(text: "Not available", color: StatusColor.warning, symbol: "exclamationmark")
                    } else if let detail = option.detail {
                        Text(detail).font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
                    }
                }
                Text(path)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            PrismIconButton(symbol: "magnifyingglass", help: "Show in Finder") {
                SettingsFinder.reveal(path)
            }
            .disabled(!exists)
            PrismIconButton(symbol: "minus", help: "Remove location", action: onRemove)
        }
        .accessibilityElement(children: .contain)
    }
}
