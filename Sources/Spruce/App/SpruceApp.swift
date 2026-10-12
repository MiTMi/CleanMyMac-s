import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

@main
struct SpruceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched from `swift run` (no bundle) make sure we get a Dock icon and focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        SystemMonitor.shared.start()
    }

    /// Keep running in the menu bar after the main window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
