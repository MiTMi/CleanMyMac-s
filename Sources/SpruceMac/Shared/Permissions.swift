import AppKit
import Foundation
import ServiceManagement
import SpruceCore
import UserNotifications

/// Full Disk Access, notifications, and launch-at-login helpers.
public enum Permissions {

    // MARK: Full Disk Access

    /// True when the app can read TCC-protected locations.
    ///
    /// There is no API to query Full Disk Access, so we probe files that are only
    /// readable with it (the same approach every cleaner uses).
    public static var hasFullDiskAccess: Bool {
        let home = NSHomeDirectory()
        let probes = [
            home + "/Library/Safari/Bookmarks.plist",
            home + "/Library/Safari/CloudTabs.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Mail",
            home + "/Library/Messages",
        ]
        var sawCandidate = false
        for path in probes {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            sawCandidate = true
            if isDir.boolValue {
                if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil { return true }
            } else if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                return true
            }
        }
        // If none of the probe files exist we cannot tell; assume granted to avoid nagging.
        return !sawCandidate
    }

    /// Opens System Settings › Privacy & Security › Full Disk Access.
    public static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings › General › Login Items & Extensions.
    public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Opens System Settings › Privacy & Security › App Management.
    public static func openAppManagementSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Launch at login

    public static var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Spruce: launch at login change failed: \(error)")
        }
    }

    // MARK: Notifications

    public static func requestNotificationAuthorization() async -> Bool {
        // UNUserNotificationCenter requires a real app bundle.
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

/// Posts local user notifications (low disk, threats, updates…).
public enum Notifier {
    public static func post(id: String, title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
