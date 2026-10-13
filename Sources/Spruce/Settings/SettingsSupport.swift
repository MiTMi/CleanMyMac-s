import AppKit
import Foundation
import Observation
import ServiceManagement
import SpruceCore
import SpruceMac
import UserNotifications

// Helpers shared by the Settings tabs and the onboarding sheet: notification access,
// the login item, the Checkup reminder, Finder helpers, choice lists and the
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

// MARK: - Checkup reminder

/// How often the Checkup reminder appears (Settings › Notifications › Reminders).
///
/// `SpruceSettings.weeklyCleanupReminder` stays the on/off switch, so older settings files
/// keep working ("on" means `weekly`, the default). The chosen interval and time of day
/// are kept per Mac in user defaults by `SettingsReminderScheduler`.
enum SettingsReminderFrequency: String, CaseIterable, Identifiable, Sendable {
    case off
    case every3Days
    case weekly
    case biweekly
    case monthly

    static let defaultValue: SettingsReminderFrequency = .weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .every3Days: return "Every 3 days"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        }
    }

    /// Days between reminders for the day-based choices (monthly follows the calendar).
    var days: Int? {
        switch self {
        case .off, .monthly: return nil
        case .every3Days: return 3
        case .weekly: return 7
        case .biweekly: return 14
        }
    }

    /// The calendar distance of `times` intervals (nil when off).
    func step(times: Int) -> DateComponents? {
        switch self {
        case .off: return nil
        case .monthly: return DateComponents(month: times)
        case .every3Days, .weekly, .biweekly: return DateComponents(day: (days ?? 7) * times)
        }
    }
}

/// Schedules the "Time for a Checkup" reminders.
///
/// Reminders come every chosen interval after the last Checkup (scan or run), at the
/// chosen time of day, so a Checkup you run yourself pushes the next reminder back. While
/// no Checkup has run, the interval counts from when reminders were first scheduled.
///
/// The next few reminders are scheduled with macOS as one-shot requests, so they appear
/// even when Spruce isn't running. They are rebuilt at launch (the AppDelegate calls
/// `sync`), when the reminder settings change, and whenever a Checkup is recorded in
/// history (`sync` starts following `HistoryStore`). Clicking a reminder or its
/// "Scan Now" button opens Checkup and starts a scan (routed by the AppDelegate like
/// every alert with a module and tool).
enum SettingsReminderScheduler {
    /// The single repeating request older builds scheduled (removed on every sync).
    static let legacyRequestID = "app.spruce.reminder.weeklyCheckup"
    /// Upcoming reminders are the requests "<prefix>1" … "<prefix>N".
    static let requestPrefix = "app.spruce.reminder.checkup."
    /// How many upcoming reminders stay scheduled with macOS.
    static let pendingCount = 4
    /// Notification category with the "Scan Now" action.
    static let categoryID = "app.spruce.reminder.checkupDue"
    static let scanNowAction = "app.spruce.reminder.scanNow"
    /// Identifier reserved for a "Remind Me Tomorrow" action. It is not offered yet: the
    /// notification delegate opens the main window for every action, so it first needs to
    /// call `remindTomorrow()` for this identifier instead.
    static let remindTomorrowAction = "app.spruce.reminder.remindTomorrow"

    /// `UserDefaults` keys (also read by Settings › Notifications through `@AppStorage`).
    static let frequencyKey = "app.spruce.reminder.frequency"
    static let minuteOfDayKey = "app.spruce.reminder.minuteOfDay"
    private static let anchorKey = "app.spruce.reminder.anchor"
    private static let snoozeKey = "app.spruce.reminder.snoozedUntil"

    /// 10:00.
    static let defaultMinuteOfDay = 10 * 60

    // MARK: Preferences

    /// The interval used while reminders are on (never `.off`; off is
    /// `SpruceSettings.weeklyCleanupReminder == false`).
    static var storedFrequency: SettingsReminderFrequency {
        get { usable(UserDefaults.standard.string(forKey: frequencyKey).flatMap(SettingsReminderFrequency.init(rawValue:))) }
        set {
            guard newValue != .off else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: frequencyKey)
        }
    }

    /// Time of day for reminders, in minutes after midnight.
    static var minuteOfDay: Int {
        get { normalized((UserDefaults.standard.object(forKey: minuteOfDayKey) as? Int) ?? defaultMinuteOfDay) }
        set { UserDefaults.standard.set(normalized(newValue), forKey: minuteOfDayKey) }
    }

    /// `stored`, or the default when nothing (or "off") was stored.
    static func usable(_ stored: SettingsReminderFrequency?) -> SettingsReminderFrequency {
        guard let stored, stored != .off else { return .defaultValue }
        return stored
    }

    /// The reminder interval in effect for `settings`.
    static func frequency(for settings: SpruceSettings) -> SettingsReminderFrequency {
        settings.weeklyCleanupReminder ? storedFrequency : .off
    }

    /// Days without a Checkup after which one counts as due (nil when reminders are off).
    /// For other surfaces that nudge about Checkup, such as the menu bar.
    static func dueAfterDays(for settings: SpruceSettings) -> Int? {
        let chosen = frequency(for: settings)
        guard chosen != .off else { return nil }
        return chosen.days ?? 30
    }

    static func normalized(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }

    /// Today's date at `minute` minutes after midnight (for a time picker).
    static func time(forMinuteOfDay minute: Int, calendar: Calendar = .current) -> Date {
        let value = normalized(minute)
        return calendar.date(bySettingHour: value / 60, minute: value % 60, second: 0, of: Date()) ?? Date()
    }

    /// Minutes after midnight of `date`'s time of day.
    static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return normalized((parts.hour ?? 10) * 60 + (parts.minute ?? 0))
    }

    /// Settings › Advanced › Reset: back to weekly at 10:00, no snooze.
    static func resetPreferences() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: frequencyKey)
        defaults.removeObject(forKey: minuteOfDayKey)
        defaults.removeObject(forKey: snoozeKey)
    }

    // MARK: Snooze

    /// A one-off reminder that comes before the regular schedule ("Remind Me Tomorrow").
    static var snoozedUntil: Date? {
        get { (UserDefaults.standard.object(forKey: snoozeKey) as? Double).map { Date(timeIntervalSince1970: $0) } }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: snoozeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: snoozeKey)
            }
        }
    }

    /// "Remind Me Tomorrow": the next reminder comes tomorrow at the chosen time, then the
    /// regular schedule carries on. Call it for `remindTomorrowAction` without opening
    /// any window.
    static func remindTomorrow(now: Date = Date(), calendar: Calendar = .current) {
        let minute = minuteOfDay
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let fire = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: tomorrow) else { return }
        snoozedUntil = fire
        sync(SettingsStore.shared.settings)
    }

    // MARK: Schedule

    /// The most recent Checkup scan or run (the entries Checkup's "Last Checkup" line uses).
    static func lastCheckupDate(in history: ActivityHistory) -> Date? {
        guard let last = CheckupHistory.lastSummary(in: history) else { return nil }
        return [last.scanDate, last.runDate].compactMap { $0 }.max()
    }

    /// Upcoming reminder dates: every `frequency` interval after `base` (the day of the last
    /// Checkup), at `minuteOfDay`, later than `now`. A pending snooze comes first and the
    /// regular reminders continue after it.
    static func upcomingDates(after base: Date, now: Date, frequency: SettingsReminderFrequency, minuteOfDay: Int,
                              snoozedUntil: Date? = nil, count: Int = pendingCount,
                              calendar: Calendar = .current) -> [Date] {
        guard count > 0, frequency != .off else { return [] }
        var dates: [Date] = []
        var earliest = now
        if let snoozedUntil, snoozedUntil > now {
            dates.append(snoozedUntil)
            earliest = snoozedUntil
        }
        let minute = normalized(minuteOfDay)
        let firstDay = calendar.startOfDay(for: base)
        // Skip the intervals that are over (a long gap since the last Checkup). Interval
        // `skip` falls on or before `earliest`'s day; the earlier ones are all in the past.
        let skip: Int
        if let days = frequency.days {
            skip = (calendar.dateComponents([.day], from: firstDay, to: earliest).day ?? 0) / days
        } else {
            skip = calendar.dateComponents([.month], from: firstDay, to: earliest).month ?? 0
        }
        var times = max(1, skip)
        var attempts = 0
        while dates.count < count && attempts < count + 8 {
            attempts += 1
            defer { times += 1 }
            guard let step = frequency.step(times: times),
                  let day = calendar.date(byAdding: step, to: firstDay),
                  let fire = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                  fire > earliest else { continue }
            dates.append(fire)
        }
        return dates
    }

    /// When the next reminder will appear with `frequency` at `minuteOfDay` (nil when off).
    static func nextReminder(frequency: SettingsReminderFrequency, minuteOfDay: Int, history: ActivityHistory,
                             now: Date = Date()) -> Date? {
        guard frequency != .off else { return nil }
        let base = lastCheckupDate(in: history) ?? storedAnchor ?? now
        return upcomingDates(after: base, now: now, frequency: frequency, minuteOfDay: minuteOfDay,
                             snoozedUntil: snoozedUntil, count: 1).first
    }

    /// Body text for a reminder delivered at `fireDate`.
    static func reminderBody(lastCheckup: Date?, fireDate: Date, calendar: Calendar = .current) -> String {
        guard let lastCheckup else {
            return "You haven't run a Checkup yet. One scan looks for junk, threats and outdated apps, and nothing is removed until you review it."
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCheckup),
                                           to: calendar.startOfDay(for: fireDate)).day ?? 0
        let when: String
        switch days {
        case ..<1: when = "earlier today"
        case 1: when = "yesterday"
        default: when = "\(days) days ago"
        }
        return "Your last Checkup was \(when). A quick scan keeps junk, threats and outdated apps in check."
    }

    /// Every request identifier this scheduler may have left pending.
    private static var allRequestIDs: [String] {
        // A few spare slots in case `pendingCount` shrinks between versions.
        [legacyRequestID] + (1...(pendingCount + 4)).map { requestPrefix + String($0) }
    }

    /// Replaces the pending reminders to match `settings`, Checkup history, the chosen
    /// interval and time, and a pending snooze. Cheap and idempotent.
    static func sync(_ settings: SpruceSettings) {
        // UNUserNotificationCenter traps when there is no bundle identifier (`swift run`).
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allRequestIDs)
        Task { @MainActor in SettingsReminderScheduler.prepare() }

        let chosen = frequency(for: settings)
        guard chosen != .off else { return }
        let now = Date()
        var snooze = snoozedUntil
        if let pending = snooze, pending <= now {
            snoozedUntil = nil
            snooze = nil
        }
        let last = lastCheckupDate(in: HistoryStore.shared.history)
        let base = last ?? anchor(now: now)
        let dates = upcomingDates(after: base, now: now, frequency: chosen, minuteOfDay: minuteOfDay,
                                  snoozedUntil: snooze)
        let calendar = Calendar.current
        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Time for a Checkup"
            content.body = reminderBody(lastCheckup: last, fireDate: date, calendar: calendar)
            content.sound = settings.playSounds ? UNNotificationSound.default : nil
            content.userInfo = [
                "module": ModuleID.checkup.rawValue,
                "tool": "checkup.scan",
                Notifier.kindKey: InboxItem.Kind.reminder.rawValue,
            ]
            content.categoryIdentifier = categoryID
            content.threadIdentifier = "app.spruce.reminder"
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            center.add(UNNotificationRequest(identifier: requestPrefix + String(index + 1), content: content,
                                             trigger: trigger))
        }
    }

    // MARK: Anchor

    /// When reminders were first scheduled: the starting point while no Checkup has run.
    private static var storedAnchor: Date? {
        (UserDefaults.standard.object(forKey: anchorKey) as? Double).map { Date(timeIntervalSince1970: $0) }
    }

    private static func anchor(now: Date) -> Date {
        if let storedAnchor { return storedAnchor }
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: anchorKey)
        return now
    }

    // MARK: Category and history

    @MainActor private static var isPrepared = false
    @MainActor private static var followedCheckup: Date?

    /// Once per launch: registers the "Scan Now" category and starts following history.
    @MainActor
    private static func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        registerCategory()
        followedCheckup = observeLastCheckup()
    }

    /// Adds the reminder category next to the ones already registered (the "Review"
    /// category `Notifier.registerCategories()` sets up at launch is kept, and recreated
    /// the same way if it isn't there yet).
    @MainActor
    private static func registerCategory() {
        let categoryID = SettingsReminderScheduler.categoryID
        let scanNowID = SettingsReminderScheduler.scanNowAction
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            let scanNow = UNNotificationAction(identifier: scanNowID, title: "Scan Now", options: [.foreground])
            let due = UNNotificationCategory(identifier: categoryID, actions: [scanNow], intentIdentifiers: [],
                                             options: [])
            var categories = existing.filter { $0.identifier != categoryID }
            if !categories.contains(where: { $0.identifier == Notifier.reviewCategory }) {
                let review = UNNotificationAction(identifier: Notifier.reviewAction, title: "Review", options: [.foreground])
                categories.insert(UNNotificationCategory(identifier: Notifier.reviewCategory, actions: [review],
                                                         intentIdentifiers: [], options: []))
            }
            categories.insert(due)
            UNUserNotificationCenter.current().setNotificationCategories(categories)
        }
    }

    /// Reads the last Checkup date and asks to hear about the next history change.
    @MainActor
    private static func observeLastCheckup() -> Date? {
        withObservationTracking {
            lastCheckupDate(in: HistoryStore.shared.history)
        } onChange: {
            Task { @MainActor in SettingsReminderScheduler.historyDidChange() }
        }
    }

    /// A Checkup was recorded (or history was cleared): reschedule from the new date. A
    /// Checkup you ran also ends a snooze.
    @MainActor
    private static func historyDidChange() {
        let latest = observeLastCheckup()
        guard latest != followedCheckup else { return }
        followedCheckup = latest
        if latest != nil { snoozedUntil = nil }
        sync(SettingsStore.shared.settings)
    }
}

// MARK: - Finder

enum SettingsFinder {
    /// Blocking (a disk that stopped answering can hang it): views use `existsInBackground`.
    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path.expandingTilde)
    }

    /// `exists(_:)` on a background queue, one probe at a time, so a sleeping or stale
    /// disk never stalls the window.
    static func existsInBackground(_ path: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SettingsFinder.probeQueue.async { continuation.resume(returning: SettingsFinder.exists(path)) }
        }
    }

    private static let probeQueue = DispatchQueue(label: "app.spruce.settings.exists", qos: .userInitiated)

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
