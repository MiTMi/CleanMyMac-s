import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Ignore List: paths, bundle identifiers and engine item ids that never appear in scan
/// results (`SpruceSettings.ignoredPaths` / `ignoredBundleIDs` / `ignoredItemIDs`).
struct SettingsIgnoreListTab: View {
    @Bindable var store: SettingsStore
    @Environment(AppModel.self) private var model
    @State private var pendingReset: SettingsIgnoreScope?
    @State private var showingAppPicker = false

    var body: some View {
        SettingsPage(tab: .ignoreList) {
            SettingsIgnoredPathsSection(store: store, onClear: { pendingReset = .paths })
            SettingsIgnoredAppsSection(store: store, onChoose: { showingAppPicker = true },
                                       onClear: { pendingReset = .apps })
            SettingsIgnoredItemsSection(store: store, onClear: { pendingReset = .items })
            resetSection
        }
        .alert(pendingReset?.confirmTitle ?? "", isPresented: resetBinding, presenting: pendingReset) { scope in
            Button(scope.confirmButton, role: .destructive) { clear(scope) }
            Button("Cancel", role: .cancel) {}
        } message: { scope in
            Text(scope.confirmMessage)
        }
        .sheet(isPresented: $showingAppPicker) {
            SettingsAppPickerSheet(
                alreadyIgnored: Set(store.settings.ignoredBundleIDs.map { $0.lowercased() }),
                knownApps: model.applications.lastApps,
                onAdd: { apps in
                    for app in apps { store.ignore(bundleID: app.bundleID) }
                    showingAppPicker = false
                },
                onCancel: { showingAppPicker = false }
            )
        }
    }

    private var resetSection: some View {
        Section {
            HStack {
                SettingsRowLabel(title: "Reset all ignore lists",
                                 detail: "Everything you ignored shows up in scan results again.",
                                 symbol: "arrow.counterclockwise")
                Spacer()
                Button("Reset All…", role: .destructive) { pendingReset = .all }
                    .disabled(isEverythingEmpty)
            }
        } footer: {
            Text("Ignored items never appear in scan results, and Spruce never removes them. Changes apply to the next scan.")
        }
    }

    private var isEverythingEmpty: Bool {
        store.settings.ignoredPaths.isEmpty && store.settings.ignoredBundleIDs.isEmpty && store.settings.ignoredItemIDs.isEmpty
    }

    private var resetBinding: Binding<Bool> {
        Binding(get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } })
    }

    private func clear(_ scope: SettingsIgnoreScope) {
        switch scope {
        case .paths: store.settings.ignoredPaths = []
        case .apps: store.settings.ignoredBundleIDs = []
        case .items: store.settings.ignoredItemIDs = []
        case .all:
            var settings = store.settings
            settings.ignoredPaths = []
            settings.ignoredBundleIDs = []
            settings.ignoredItemIDs = []
            store.settings = settings
        }
        pendingReset = nil
    }
}

/// Which list a reset clears.
enum SettingsIgnoreScope: String, Identifiable {
    case paths, apps, items, all

    var id: String { rawValue }

    var confirmTitle: String {
        switch self {
        case .paths: return "Clear ignored files and folders?"
        case .apps: return "Clear ignored apps?"
        case .items: return "Clear ignored items?"
        case .all: return "Reset all ignore lists?"
        }
    }

    var confirmMessage: String {
        switch self {
        case .paths: return "These files and folders will appear in scan results again."
        case .apps: return "These apps will be offered for updates, uninstalling and leftover removal again."
        case .items: return "These items will appear in scan results again."
        case .all: return "Every ignored file, folder, app and item will appear in scan results again."
        }
    }

    var confirmButton: String { self == .all ? "Reset All" : "Clear List" }
}

// MARK: - Paths

private struct SettingsIgnoredPathsSection: View {
    @Bindable var store: SettingsStore
    var onClear: () -> Void
    @State private var dropTargeted = false

    var body: some View {
        Section {
            if store.settings.ignoredPaths.isEmpty {
                Text("No files or folders ignored yet. Choose “Ignore” on a scan result, or add them here.")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
            }
            ForEach(store.settings.ignoredPaths, id: \.self) { path in
                SettingsIgnoredPathRow(path: path) {
                    store.settings.ignoredPaths.removeAll { $0 == path }
                }
            }
            dropZone
            HStack(spacing: Spacing.s) {
                Button {
                    choosePaths()
                } label: {
                    Label("Add…", systemImage: "plus")
                }
                Spacer()
                if !store.settings.ignoredPaths.isEmpty {
                    Button("Clear List…", action: onClear)
                }
            }
            .controlSize(.small)
        } header: {
            SettingsSectionHeader(title: "Files & Folders", trailing: countText(store.settings.ignoredPaths.count))
        }
    }

    private var dropZone: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(dropTargeted ? ModuleID.clutter.palette.accentText : Ink.tertiary)
            Text("Drop files or folders here to ignore them")
                .font(SpruceFont.caption)
                .foregroundStyle(dropTargeted ? Ink.primary : Ink.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(dropTargeted ? ModuleID.clutter.palette.accent : Ink.hairline,
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            for url in files { store.ignore(path: url.standardizedFileURL.path) }
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .animation(Motion.quick, value: dropTargeted)
    }

    private func choosePaths() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Ignore"
        panel.message = "Choose files or folders that Spruce should never show in scan results."
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.ignore(path: url.standardizedFileURL.path) }
    }
}

private struct SettingsIgnoredPathRow: View {
    var path: String
    var onRemove: () -> Void

    var body: some View {
        let absolute = path.expandingTilde
        let exists = SettingsFinder.exists(path)
        HStack(spacing: Spacing.m) {
            ItemIcon(url: exists ? URL(fileURLWithPath: absolute) : nil, symbol: "questionmark.folder", size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.s) {
                    Text((absolute as NSString).lastPathComponent.isEmpty ? absolute : (absolute as NSString).lastPathComponent)
                        .font(SpruceFont.body)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    if !exists {
                        PrismChip(text: "Missing", color: StatusColor.warning)
                    }
                }
                Text(path)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(absolute)
            }
            Spacer()
            PrismIconButton(symbol: "magnifyingglass", help: "Show in Finder") { SettingsFinder.reveal(path) }
                .disabled(!exists)
            PrismIconButton(symbol: "minus", help: "Stop ignoring", action: onRemove)
        }
        .contextMenu {
            Button("Show in Finder") { SettingsFinder.reveal(path) }.disabled(!exists)
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(absolute, forType: .string)
            }
            Divider()
            Button("Stop Ignoring", action: onRemove)
        }
    }
}

// MARK: - Apps

private struct SettingsIgnoredAppsSection: View {
    @Bindable var store: SettingsStore
    var onChoose: () -> Void
    var onClear: () -> Void

    @State private var typedID = ""
    @State private var resolved: [String: (name: String, path: String)] = [:]

    private var typedIsValid: Bool { SettingsAppCatalog.isValidBundleID(typedID) }

    var body: some View {
        Section {
            if store.settings.ignoredBundleIDs.isEmpty {
                Text("No apps ignored. Ignored apps aren't offered for updates, uninstalling or leftover removal.")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
            }
            ForEach(store.settings.ignoredBundleIDs, id: \.self) { bundleID in
                appRow(bundleID)
            }
            HStack(spacing: Spacing.s) {
                Button {
                    onChoose()
                } label: {
                    Label("Choose Apps…", systemImage: "plus")
                }
                TextField("or type a bundle ID, e.g. com.example.app", text: $typedID)
                    .textFieldStyle(.roundedBorder)
                    .font(SpruceFont.mono)
                    .onSubmit(addTyped)
                Button("Add", action: addTyped)
                    .disabled(!typedIsValid)
                if !store.settings.ignoredBundleIDs.isEmpty {
                    Button("Clear List…", action: onClear)
                }
            }
            .controlSize(.small)
        } header: {
            SettingsSectionHeader(title: "Apps", trailing: countText(store.settings.ignoredBundleIDs.count))
        }
        .task(id: store.settings.ignoredBundleIDs) {
            var map: [String: (name: String, path: String)] = [:]
            for id in store.settings.ignoredBundleIDs {
                if let hit = await SettingsAppCatalog.resolve(id) { map[id] = hit }
            }
            resolved = map
        }
    }

    private func appRow(_ bundleID: String) -> some View {
        let hit = resolved[bundleID]
        return HStack(spacing: Spacing.m) {
            ItemIcon(url: hit.map { URL(fileURLWithPath: $0.path) }, symbol: "app.dashed", size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.s) {
                    Text(hit?.name ?? bundleID)
                        .font(SpruceFont.body)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    if hit == nil {
                        PrismChip(text: "Not installed", color: StatusColor.info)
                    }
                }
                Text(bundleID)
                    .font(SpruceFont.mono)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer()
            if let hit {
                PrismIconButton(symbol: "magnifyingglass", help: "Show in Finder") { SettingsFinder.reveal(hit.path) }
            }
            PrismIconButton(symbol: "minus", help: "Stop ignoring") {
                store.settings.ignoredBundleIDs.removeAll { $0 == bundleID }
            }
        }
    }

    private func addTyped() {
        let id = typedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SettingsAppCatalog.isValidBundleID(id) else { return }
        if !store.settings.ignoredBundleIDs.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
            store.ignore(bundleID: id)
        }
        typedID = ""
    }
}

// MARK: - Item ids

private struct SettingsIgnoredItemsSection: View {
    @Bindable var store: SettingsStore
    var onClear: () -> Void

    var body: some View {
        Section {
            if store.settings.ignoredItemIDs.isEmpty {
                Text("Single results you ignore, such as one app update or a login item, appear here.")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
            }
            ForEach(store.settings.ignoredItemIDs, id: \.self) { itemID in
                HStack(spacing: Spacing.m) {
                    Image(systemName: "tag")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ModuleID.clutter.palette.accentText)
                        .frame(width: 24)
                    Text(itemID)
                        .font(SpruceFont.mono)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(itemID)
                    Spacer()
                    PrismIconButton(symbol: "minus", help: "Stop ignoring") {
                        store.settings.ignoredItemIDs.removeAll { $0 == itemID }
                    }
                }
            }
            if !store.settings.ignoredItemIDs.isEmpty {
                HStack {
                    Spacer()
                    Button("Clear List…", action: onClear).controlSize(.small)
                }
            }
        } header: {
            SettingsSectionHeader(title: "Specific Items", trailing: countText(store.settings.ignoredItemIDs.count))
        }
    }
}

private func countText(_ count: Int) -> String? {
    count == 0 ? nil : (count == 1 ? "1 item" : "\(count) items")
}

// MARK: - App picker

/// Sheet listing installed and running apps; the chosen ones are added to the ignore list.
struct SettingsAppPickerSheet: View {
    var alreadyIgnored: Set<String>
    var knownApps: [ApplicationsAppInfo]
    var onAdd: ([SettingsAppEntry]) -> Void
    var onCancel: () -> Void

    @State private var apps: [SettingsAppEntry] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var runningOnly = false
    @State private var chosen: Set<String> = []

    private var visibleApps: [SettingsAppEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return apps.filter { app in
            (!runningOnly || app.isRunning)
                && (needle.isEmpty || app.name.localizedCaseInsensitiveContains(needle)
                    || app.bundleID.localizedCaseInsensitiveContains(needle))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Ignore Apps").font(SpruceFont.title).foregroundStyle(Ink.primary)
                Text("Chosen apps won't be offered for updates, uninstalling or leftover removal.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
            }
            HStack(spacing: Spacing.s) {
                PrismSearchField(text: $query, prompt: "Search apps", width: 240)
                Spacer()
                Picker("Show", selection: $runningOnly) {
                    Text("All").tag(false)
                    Text("Running").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            list
            HStack(spacing: Spacing.s) {
                Text(chosen.isEmpty ? "\(apps.count) apps" : "\(chosen.count) selected")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.tertiary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(PrismCapsuleButtonStyle(role: .secondary, large: true))
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count > 1 ? "Ignore \(chosen.count) Apps" : "Ignore App") {
                    onAdd(apps.filter { chosen.contains($0.id) })
                }
                .buttonStyle(PrismCapsuleButtonStyle(role: .primary, large: true))
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 500, height: 540)
        .background { SettingsBackdrop(module: .applications) }
        .preferredColorScheme(.dark)
        .task {
            apps = await SettingsAppCatalog.load(known: knownApps)
            isLoading = false
        }
    }

    @ViewBuilder
    private var list: some View {
        if isLoading {
            VStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Finding apps…").font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .prismSurface(radius: Radius.container)
        } else if visibleApps.isEmpty {
            Text(query.isEmpty ? "No apps found." : "No apps match “\(query)”.")
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .prismSurface(radius: Radius.container)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleApps) { app in
                        pickerRow(app)
                        Divider().opacity(0.4).padding(.leading, 52)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .prismSurface(radius: Radius.container)
        }
    }

    private func pickerRow(_ app: SettingsAppEntry) -> some View {
        let ignored = alreadyIgnored.contains(app.id)
        let isChosen = chosen.contains(app.id)
        return Button {
            toggle(app)
        } label: {
            HStack(spacing: Spacing.m) {
                SpruceCheckbox(isOn: ignored || isChosen, module: .applications) { toggle(app) }
                    .disabled(ignored)
                ItemIcon(url: app.path.map { URL(fileURLWithPath: $0) }, symbol: "app", size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(SpruceFont.body).foregroundStyle(Ink.primary).lineLimit(1)
                    Text(app.bundleID).font(SpruceFont.caption).foregroundStyle(Ink.tertiary).lineLimit(1)
                }
                Spacer()
                if ignored {
                    PrismChip(text: "Ignored", color: StatusColor.info)
                } else if app.isRunning {
                    PrismChip(text: "Running", color: StatusColor.success)
                } else if app.isSystem {
                    PrismChip(text: "macOS", color: Ink.secondary)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(ignored)
        .opacity(ignored ? 0.55 : 1)
    }

    private func toggle(_ app: SettingsAppEntry) {
        guard !alreadyIgnored.contains(app.id) else { return }
        if chosen.contains(app.id) { chosen.remove(app.id) } else { chosen.insert(app.id) }
    }
}
