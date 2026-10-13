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
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Modules") {
                ForEach(Array(ModuleID.allCases.enumerated()), id: \.element) { index, module in
                    if index < 9 {
                        Button(module.title) { model.open(module) }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    } else {
                        Button(module.title) { model.open(module) }
                    }
                }
            }
        }

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched from `swift run` (no bundle) make sure we get a Dock icon and focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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

    /// Show alerts even while Spruce is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking an alert (or its "Review" button) opens the related module/tool.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let moduleRaw = info["module"] as? String
        let tool = info["tool"] as? String
        Task { @MainActor in
            if let moduleRaw, let module = ModuleID(rawValue: moduleRaw) {
                AppModel.shared.open(module, tool: tool)
            }
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain && $0.title == "Spruce" }?.makeKeyAndOrderFront(nil)
            var forwarded: [String: String] = [:]
            if let moduleRaw { forwarded["module"] = moduleRaw }
            if let tool { forwarded["tool"] = tool }
            NotificationCenter.default.post(name: Notifier.openRequest, object: nil, userInfo: forwarded)
        }
        completionHandler()
    }
}
