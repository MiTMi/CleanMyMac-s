import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - What screens publish to the menu bar

/// Actions the focused screen offers to the Scan and Edit menus. A screen publishes
/// them with `.focusedSceneValue(\.spruceFlow, …)` (`ScanFlowModel.menuActions` builds
/// them for a standard flow); a nil member disables its menu item.
struct SpruceFlowActions {
    var scanAgain: (() -> Void)?
    var stop: (() -> Void)?
    /// Opens the screen's own confirmation — never removes anything directly.
    var reviewAndRun: (() -> Void)?
    var selectAll: (() -> Void)?
    var deselectAll: (() -> Void)?
    var selectRecommended: (() -> Void)?

    init(scanAgain: (() -> Void)? = nil, stop: (() -> Void)? = nil, reviewAndRun: (() -> Void)? = nil,
         selectAll: (() -> Void)? = nil, deselectAll: (() -> Void)? = nil, selectRecommended: (() -> Void)? = nil) {
        self.scanAgain = scanAgain
        self.stop = stop
        self.reviewAndRun = reviewAndRun
        self.selectAll = selectAll
        self.deselectAll = deselectAll
        self.selectRecommended = selectRecommended
    }
}

/// The focused review row(s), for File › Quick Look / Reveal in Finder / Copy Path / Ignore.
/// Published by review lists with `.focusedSceneValue(\.spruceRows, …)`.
struct SpruceRowActions {
    var urls: [URL]
    var quickLook: (() -> Void)?
    var ignore: (() -> Void)?

    init(urls: [URL], quickLook: (() -> Void)? = nil, ignore: (() -> Void)? = nil) {
        self.urls = urls
        self.quickLook = quickLook
        self.ignore = ignore
    }
}

struct SpruceFlowActionsKey: FocusedValueKey {
    typealias Value = SpruceFlowActions
}

struct SpruceRowActionsKey: FocusedValueKey {
    typealias Value = SpruceRowActions
}

extension FocusedValues {
    var spruceFlow: SpruceFlowActions? {
        get { self[SpruceFlowActionsKey.self] }
        set { self[SpruceFlowActionsKey.self] = newValue }
    }

    var spruceRows: SpruceRowActions? {
        get { self[SpruceRowActionsKey.self] }
        set { self[SpruceRowActionsKey.self] = newValue }
    }
}

extension ScanFlowModel {
    /// Menu actions for a standard scan flow, for `ScanFlowScreen` to publish.
    /// `reviewAndRun` is left to the screen, which owns the confirmation.
    var menuActions: SpruceFlowActions {
        let canScan = !isBusy
        let hasResults = phase == .results && !groups.isEmpty
        return SpruceFlowActions(
            scanAgain: canScan ? { [weak self] in self?.startScan() } : nil,
            stop: isBusy ? { [weak self] in self?.cancel() } : nil,
            selectAll: hasResults ? { [weak self] in self?.selectAll(true) } : nil,
            deselectAll: hasResults ? { [weak self] in self?.selectAll(false) } : nil,
            selectRecommended: hasResults ? { [weak self] in self?.selectRecommended() } : nil
        )
    }
}

// MARK: - Menus

/// The app's main-menu commands.
struct SpruceCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            FileMenuItems(model: model)
        }
        CommandGroup(after: .pasteboard) {
            EditSelectionItems()
        }
        CommandGroup(after: .sidebar) {
            ViewMenuItems(model: model)
        }
        CommandMenu("Scan") {
            ScanMenuItems()
        }
        CommandMenu("Go") {
            GoMenuItems(model: model)
        }
        CommandGroup(replacing: .help) {
            HelpMenuItems(model: model)
        }
    }
}

private struct FileMenuItems: View {
    let model: AppModel
    @FocusedValue(\.spruceRows) private var rows
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Keep the opener for AppKit callbacks (the main menu exists for the app's lifetime).
        let _ = model.registerWindowOpener(openWindow)
        Button("Quick Look") { rows?.quickLook?() }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(rows?.quickLook == nil)
        Button("Reveal in Finder") {
            if let urls = rows?.urls, !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(rows?.urls.isEmpty ?? true)
        Button("Copy Path") {
            guard let urls = rows?.urls, !urls.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(rows?.urls.isEmpty ?? true)
        Button("Ignore") { rows?.ignore?() }
            .disabled(rows?.ignore == nil)
    }
}

private struct EditSelectionItems: View {
    @FocusedValue(\.spruceFlow) private var flow

    var body: some View {
        Divider()
        Button("Select All Items") { flow?.selectAll?() }
            .disabled(flow?.selectAll == nil)
        Button("Deselect All") { flow?.deselectAll?() }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(flow?.deselectAll == nil)
        Button("Select Recommended") { flow?.selectRecommended?() }
            .disabled(flow?.selectRecommended == nil)
    }
}

private struct ViewMenuItems: View {
    let model: AppModel

    var body: some View {
        Button("Notification Center") {
            model.showMainWindow()
            model.showsInbox = true
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        Button("Mac Health") {
            model.open(.activity)
            model.showMainWindow()
        }
        Divider()
    }
}

private struct ScanMenuItems: View {
    @FocusedValue(\.spruceFlow) private var flow

    var body: some View {
        Button("Scan Again") { flow?.scanAgain?() }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(flow?.scanAgain == nil)
        Button("Stop") { flow?.stop?() }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(flow?.stop == nil)
        Divider()
        Button("Run Selected…") { flow?.reviewAndRun?() }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(flow?.reviewAndRun == nil)
    }
}

private struct GoMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = model.registerWindowOpener(openWindow)
        ForEach(Array(ModuleID.allCases.enumerated()), id: \.element) { index, module in
            if index < 9 {
                Button(module.title) { go(module) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            } else if module == .activity {
                Button(module.title) { go(module) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            } else {
                Button(module.title) { go(module) }
            }
        }
    }

    private func go(_ module: ModuleID) {
        model.open(module)
        model.showMainWindow()
    }
}

private struct HelpMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Spruce Help") { show(.gettingStarted) }
            .keyboardShortcut("?", modifiers: .command)
        Button("Keyboard Shortcuts") { show(.shortcuts) }
            .keyboardShortcut("/", modifiers: .command)
        Button("Permissions Guide") { show(.permissions) }
        Divider()
        Button("Safety & the Trash") { show(.safety) }
    }

    private func show(_ page: HelpPage) {
        model.helpPage = page
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "help")
    }
}
