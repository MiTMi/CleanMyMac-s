import AppKit
import Foundation
import ServiceManagement
import SpruceCore
import SpruceMac
import UserNotifications

// Helpers shared by the Settings tabs and the onboarding sheet: notification access,
// the login item, the weekly Checkup reminder, Finder helpers, choice lists and the
// app list used by the ignore list.

// MARK: - Notification access

/// Simplified notification authorisation state (Sendable, so it can cross actors).
enum SettingsNotificationStatus: Sendable, Equatable {
    /// Running outside an app bundle (`swift run`): macOS can't deliver notifications.
    case unavailable
    case notDetermined
    case denied
    case allowed

    var title: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .notDetermined: return "Not set up"
        case .denied: return "Off"
        case .allowed: return "Allowed"
        }
    }

    var detail: String {
        switch self {
        case .unavailable: return "Notifications need Spruce to run from its app bundle."
        case .notDetermined: return "Spruce hasn't asked for permission yet."
        case .denied: return "Notifications are turned off for Spruce in System Settings."
        case .allowed: return "Spruce can show alerts and reminders."
        }
    }

    var tileStatus: TileStatus {
        switch self {
        case .allowed: return .clear
        case .notDetermined: return .attention
        case .denied: return .critical
        case .unavailable: return .unavailable
        }
    }
}

enum SettingsNotificationAccess {
    /// Reads the current authorisation status.
    static func status() async -> SettingsNotificationStatus {
        // UNUserNotificationCenter traps when there is no bundle identifier.
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional: return .allowed
        default: return .allowed
        }
    }

    /// Shows the system permission prompt (only the first time) and returns the new status.
    static func request() async -> SettingsNotificationStatus {
        _ = await Permissions.requestNotificationAuthorization()
        return await status()
    }

    /// Opens System Settings › Notifications (Spruce's page when macOS supports it).
    @MainActor
    static func openSystemSettings() {
        var candidates: [String] = []
        if let id = Bundle.main.bundleIdentifier {
            candidates.append("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
        }
        candidates.append("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        candidates.append("x-apple.systempreferences:com.apple.preference.notifications")
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Login item

/// What macOS reports for Spruce's login item.
enum SettingsLaunchState: Equatable {
    case on
    case off
    /// Registered, but the user must allow it in System Settings › Login Items.
    case needsApproval

    var isRequested: Bool { self == .on || self == .needsApproval }
}

enum SettingsLoginItem {
    static var state: SettingsLaunchState {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }

    /// Registers or unregisters the login item and stores what macOS actually did.
    /// Returns an error message when macOS refused the change.
    @MainActor
    @discardableResult
    static func set(_ enabled: Bool, store: SettingsStore) -> String? {
        Permissions.setLaunchAtLogin(enabled)
        let now = state
        if store.settings.launchAtLogin != now.isRequested {
            store.settings.launchAtLogin = now.isRequested
        }
        if enabled && !now.isRequested {
            return "macOS didn't accept the login item. Move Spruce to your Applications folder and try again."
        }
        if !enabled && now.isRequested {
            return "macOS kept the login item. You can remove it in System Settings › General › Login Items."
        }
        return nil
    }

    /// Makes the stored preference match the system (the user may change it in System Settings).
    @MainActor
    static func syncStoredValue(_ store: SettingsStore) -> SettingsLaunchState {
        let now = state
        if store.settings.launchAtLogin != now.isRequested {
            store.settings.launchAtLogin = now.isRequested
        }
        return now
    }
}

// MARK: - Weekly Checkup reminder

/// Schedules the weekly "Time for a Checkup" notification (`SpruceSettings.weeklyCleanupReminder`).
///
/// A repeating calendar trigger (Mondays, 10:00) lives in the notification center, so it
/// fires even when Spruce isn't running. Clicking it opens Checkup and starts a scan.
enum SettingsReminderScheduler {
    static let requestID = "app.spruce.reminder.weeklyCheckup"
    static let weekday = 2 // Monday (Gregorian: 1 = Sunday)
    static let hour = 10

    /// "Every Monday at 10:00 AM" (localised day and time).
    static var scheduleDescription: String {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let time = calendar.date(from: components).map {
            DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)
        } ?? "\(hour):00"
        let symbols = calendar.weekdaySymbols
        let day = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "Monday"
        return "Every \(day) at \(time)"
    }

    /// Adds or removes the pending reminder to match `settings`.
    static func sync(_ settings: SpruceSettings) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        guard settings.weeklyCleanupReminder else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time for a Checkup"
        content.body = "A quick weekly scan keeps junk, threats and outdated apps in check."
        content.sound = settings.playSounds ? UNNotificationSound.default : nil
        content.userInfo = ["module": ModuleID.checkup.rawValue, "tool": "checkup.scan"]
        content.categoryIdentifier = Notifier.reviewCategory

        var when = DateComponents()
        when.weekday = weekday
        when.hour = hour
        when.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
    }
}

// MARK: - Finder

enum SettingsFinder {
    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path.expandingTilde)
    }

    /// Selects the item in a Finder window (or opens its closest existing parent).
    @MainActor
    static func reveal(_ path: String) {
        var url = URL(fileURLWithPath: path.expandingTilde).standardizedFileURL
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" {
            url.deleteLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Selects one of Spruce's own folders in Finder, creating it first when needed.
    @MainActor
    static func revealFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens a file with its default app (Console for logs).
    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Shows Spruce's own app in Finder (handy for dragging it into the Full Disk Access list).
    @MainActor
    static func revealSpruce() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

// MARK: - Choice lists

enum SettingsChoices {
    static let largeFileSizes: [Int64] = [
        10_000_000, 25_000_000, 50_000_000, 100_000_000, 250_000_000, 500_000_000, 1_000_000_000, 5_000_000_000,
    ]
    static let ageDays: [Int] = [30, 60, 90, 180, 365, 730]
    static let lowDiskPercents: [Int] = [5, 10, 15, 20, 25]
    static let trashSizes: [Int64] = [
        500_000_000, 1_000_000_000, 2_000_000_000, 3_000_000_000, 5_000_000_000,
        10_000_000_000, 20_000_000_000, 50_000_000_000,
    ]

    /// `options`, plus `value` when it is a custom value set elsewhere (kept sorted).
    static func including<T: Comparable>(_ value: T, in options: [T]) -> [T] {
        options.contains(value) ? options : (options + [value]).sorted()
    }

    /// "1 month", "6 months", "1 year", "45 days".
    static func dayLabel(_ days: Int) -> String {
        if days > 0 && days % 365 == 0 {
            let years = days / 365
            return years == 1 ? "1 year" : "\(years) years"
        }
        if days > 0 && days % 30 == 0 {
            let months = days / 30
            return months == 1 ? "1 month" : "\(months) months"
        }
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// Whether the system temperature preference (Language & Region) is Celsius.
    static var systemPrefersCelsius: Bool {
        if let unit = UserDefaults.standard.string(forKey: "AppleTemperatureUnit") {
            return unit.lowercased() != "fahrenheit"
        }
        return Locale.current.measurementSystem != .us
    }
}

// MARK: - Apps for the ignore list

/// An app that can be added to the ignore list by bundle identifier.
struct SettingsAppEntry: Identifiable, Hashable, Sendable {
    var bundleID: String
    var name: String
    var path: String?
    var isRunning: Bool
    var isSystem: Bool

    var id: String { bundleID.lowercased() }
}

enum SettingsAppCatalog {
    /// Regular (Dock) apps that are running now.
    @MainActor
    static func runningApps() -> [SettingsAppEntry] {
        NSWorkspace.shared.runningApplications.compactMap { app -> SettingsAppEntry? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return nil }
            let path = app.bundleURL?.path
            return SettingsAppEntry(bundleID: id, name: app.localizedName ?? id, path: path, isRunning: true,
                                    isSystem: path?.hasPrefix("/System/") ?? false)
        }
    }

    /// Installed apps (Applications folders), read off the main thread, merged with apps
    /// the Applications module already found and with running apps.
    @MainActor
    static func load(known: [ApplicationsAppInfo]) async -> [SettingsAppEntry] {
        let running = runningApps()
        let installed = await Task.detached(priority: .userInitiated) { SettingsAppCatalog.scanInstalled() }.value
        var byID: [String: SettingsAppEntry] = [:]
        for app in installed { byID[app.id] = app }
        for app in known where !app.bundleID.isEmpty {
            let entry = SettingsAppEntry(bundleID: app.bundleID, name: app.name, path: app.path,
                                         isRunning: app.isRunning, isSystem: app.isSystem)
            if byID[entry.id] == nil { byID[entry.id] = entry }
        }
        for app in running {
            if var existing = byID[app.id] {
                existing.isRunning = true
                byID[app.id] = existing
            } else {
                byID[app.id] = app
            }
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads bundle identifiers from Info.plist files (no `Bundle` objects, which are cached forever).
    static func scanInstalled() -> [SettingsAppEntry] {
        let fm = FileManager.default
        let roots = [
            "/Applications", "/Applications/Utilities",
            "/System/Applications", "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        var seen = Set<String>()
        var result: [SettingsAppEntry] = []
        for root in roots {
            guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in names where name.lowercased().hasSuffix(".app") {
                let path = (root as NSString).appendingPathComponent(name)
                let plistURL = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
                guard let info = NSDictionary(contentsOf: plistURL),
                      let id = info["CFBundleIdentifier"] as? String, !id.isEmpty else { continue }
                guard seen.insert(id.lowercased()).inserted else { continue }
                var display = fm.displayName(atPath: path)
                if display.lowercased().hasSuffix(".app") { display = String(display.dropLast(4)) }
                result.append(SettingsAppEntry(bundleID: id, name: display, path: path, isRunning: false,
                                               isSystem: root.hasPrefix("/System/")))
            }
        }
        return result
    }

    /// Display name and location for a bundle id (nil when the app isn't installed).
    @MainActor
    static func resolve(_ bundleID: String) -> (name: String, path: String)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        return (name, url.path)
    }

    /// Loose reverse-DNS check for a typed bundle identifier ("com.example.App").
    static func isValidBundleID(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 255, trimmed.contains("."),
              !trimmed.hasPrefix("."), !trimmed.hasSuffix("."), !trimmed.contains("..") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Clutter locations

enum SettingsClutterLocations {
    /// Adds `paths` to `current`, skipping ones already covered by a chosen folder and
    /// dropping chosen folders that the new one covers.
    static func merged(_ current: [String], adding paths: [String]) -> [String] {
        var result = current
        for path in paths {
            let stored = ClutterLocations.storedForm(path)
            let key = ClutterLocations.canonical(stored)
            let covered = result.contains { existing in
                let existingKey = ClutterLocations.canonical(existing)
                return existingKey == key || isInside(key, existingKey)
            }
            if covered { continue }
            result.removeAll { isInside(ClutterLocations.canonical($0), key) }
            result.append(stored)
        }
        return result
    }

    static func removing(_ path: String, from current: [String]) -> [String] {
        let key = ClutterLocations.canonical(path)
        return current.filter { ClutterLocations.canonical($0) != key }
    }

    /// Whether canonical `child` is strictly inside canonical `parent`.
    static func isInside(_ child: String, _ parent: String) -> Bool {
        if parent == "/" { return child != "/" && child.hasPrefix("/") }
        return child.hasPrefix(parent + "/")
    }
}
