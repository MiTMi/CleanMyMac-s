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
///
/// Pass `module` (a `ModuleID` raw value) and optionally `tool` (a tool id) to give the
/// notification a "Review" button; clicking the notification or the button opens that
/// module/tool (the AppDelegate routes it, brings the main window back if it was
/// closed, and also posts `Notifier.openRequest` with those values).
///
/// Every alert is also kept in the in-app Notification Center (`InboxStore`), and the
/// sound follows Settings › Play sounds.
public enum Notifier {
    public static let reviewCategory = "app.spruce.review"
    public static let reviewAction = "app.spruce.review.open"
    /// Posted on the main thread with userInfo ["module": String, "tool": String?].
    public static let openRequest = Notification.Name("app.spruce.notifier.openRequest")
    /// userInfo key carrying the `InboxItem.Kind` raw value.
    public static let kindKey = "kind"

    public static func post(id: String, title: String, body: String, module: String? = nil, tool: String? = nil,
                            kind: InboxItem.Kind = .alert) {
        InboxStore.shared.add(InboxItem(id: id, kind: kind, title: title, body: body, module: module, tool: tool))
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = playsSounds ? .default : nil
        var info: [String: String] = [kindKey: kind.rawValue]
        if let module {
            info["module"] = module
            if let tool { info["tool"] = tool }
            content.categoryIdentifier = reviewCategory
        }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Keeps a message in the in-app Notification Center only (no banner).
    public static func keep(id: String = UUID().uuidString, kind: InboxItem.Kind, title: String, body: String,
                            module: String? = nil, tool: String? = nil) {
        InboxStore.shared.add(InboxItem(id: id, kind: kind, title: title, body: body, module: module, tool: tool))
    }

    /// Mirrors a delivered system notification (e.g. the scheduled weekly reminder) into
    /// the in-app Notification Center, once.
    public static func mirror(_ notification: UNNotification) {
        let content = notification.request.content
        let info = content.userInfo
        let id = notification.request.identifier
        let kind = (info[kindKey] as? String).flatMap(InboxItem.Kind.init(rawValue:))
            ?? (notification.request.trigger is UNCalendarNotificationTrigger ? .reminder : .alert)
        // Repeating reminders reuse one identifier; keep one entry per delivery.
        let itemID = kind == .reminder ? "\(id).\(Int(notification.date.timeIntervalSince1970))" : id
        InboxStore.shared.addIfMissing(InboxItem(id: itemID, kind: kind, date: notification.date, title: content.title,
                                                 body: content.body, module: info["module"] as? String,
                                                 tool: info["tool"] as? String))
    }

    /// Settings › Play sounds.
    public static var playsSounds: Bool { SettingsStore.shared.settings.playSounds }

    /// Registers the "Review" action. Call once at launch.
    public static func registerCategories() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let review = UNNotificationAction(identifier: reviewAction, title: "Review", options: [.foreground])
        let category = UNNotificationCategory(identifier: reviewCategory, actions: [review], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
