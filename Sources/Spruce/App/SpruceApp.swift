import AppKit
import SpruceCore
import SpruceMac
import SwiftUI
import UserNotifications

@main
struct SpruceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Spruce", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1060, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
        .commands {
            SpruceCommands(model: model)
        }

        Window("Spruce Help", id: "help") {
            HelpView()
                .environment(model)
        }
        .defaultSize(width: 820, height: 600)

        MenuBarExtra(isInserted: Binding(
            get: { model.settings.settings.showMenuBarMonitor },
            set: { model.settings.settings.showMenuBarMonitor = $0 }
        )) {
            MonitorMenuView()
                .environment(model)
        } label: {
            MonitorMenuLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let services = SpruceServices()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched from `swift run` (no bundle) make sure we get a Dock icon and focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.servicesProvider = services
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            Notifier.registerCategories()
            // Keep the weekly Checkup reminder in step with settings on every launch.
            SettingsReminderScheduler.sync(SettingsStore.shared.settings)
        }
        SystemMonitor.shared.start()
    }

    /// Keep running in the menu bar after the main window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Alerts delivered while Spruce was in the background (or the weekly reminder)
        // land in the in-app Notification Center too.
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            for item in delivered { Notifier.mirror(item) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HistoryStore.shared.flush()
    }

    // MARK: Opening files and links

    /// `spruce://` links, and files dropped on the Dock icon or opened with Spruce.
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        let model = AppModel.shared
        for link in urls where !link.isFileURL {
            model.handle(url: link)
        }
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { model.openFiles(files) }
    }

    // MARK: Dock menu

    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(dockItem("Run Checkup", action: #selector(dockRunCheckup)))
        var emptyTitle = "Empty Trash…"
        if let bytes = AppModel.shared.monitor.trash.bytes, bytes > 0 {
            emptyTitle = "Empty Trash (\(ByteFormat.string(bytes)))…"
        }
        menu.addItem(dockItem(emptyTitle, action: #selector(dockEmptyTrash)))
        menu.addItem(dockItem("Free Up Memory…", action: #selector(dockFreeMemory)))
        let modules = NSMenu(title: "Open")
        for module in ModuleID.allCases {
            let item = dockItem(module.title, action: #selector(dockOpenModule(_:)))
            item.representedObject = module.rawValue
            modules.addItem(item)
        }
        let open = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
        open.submenu = modules
        menu.addItem(.separator())
        menu.addItem(open)
        return menu
    }

    @MainActor
    private func dockItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Opens Checkup and starts a scan (a scan never removes anything).
    @MainActor @objc private func dockRunCheckup() {
        AppModel.shared.open(.checkup, tool: "checkup.scan")
        AppModel.shared.showMainWindow()
    }

    /// Opens the Empty Trash tool, which asks before emptying.
    @MainActor @objc private func dockEmptyTrash() {
        AppModel.shared.open(.toolbox, tool: "toolbox.emptyTrash")
        AppModel.shared.showMainWindow()
    }

    /// Opens Free Up RAM, which runs only when you click it.
    @MainActor @objc private func dockFreeMemory() {
        AppModel.shared.open(.toolbox, tool: "toolbox.freeRAM")
        AppModel.shared.showMainWindow()
    }

    @MainActor @objc private func dockOpenModule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let module = ModuleID(rawValue: raw) else { return }
        AppModel.shared.open(module)
        AppModel.shared.showMainWindow()
    }

    // MARK: Notifications

    /// Show alerts even while Spruce is frontmost (with sound only when the alert has one,
    /// which follows Settings › Play sounds).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Notifier.mirror(notification)
        let hasSound = notification.request.content.sound != nil
        completionHandler(hasSound ? [.banner, .list, .sound] : [.banner, .list])
    }

    /// Clicking an alert (or its "Review" button) opens the related module/tool, bringing
    /// the main window back if it was closed.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let notification = response.notification
        Notifier.mirror(notification)
        let info = notification.request.content.userInfo
        let moduleRaw = info["module"] as? String
        let tool = info["tool"] as? String
        let identifier = notification.request.identifier
        Task { @MainActor in
            let model = AppModel.shared
            if let moduleRaw, let module = ModuleID(rawValue: moduleRaw) {
                model.open(module, tool: tool)
            }
            model.showMainWindow()
            model.inbox.markRead(id: identifier)
            var forwarded: [String: String] = [:]
            if let moduleRaw { forwarded["module"] = moduleRaw }
            if let tool { forwarded["tool"] = tool }
            NotificationCenter.default.post(name: Notifier.openRequest, object: nil, userInfo: forwarded)
        }
        completionHandler()
    }
}
