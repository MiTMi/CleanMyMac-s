import AppKit
import Foundation
import SpruceCore
import UserNotifications

// MARK: - Module preferences

/// Applications preferences that `SpruceSettings` doesn't hold.
public struct ApplicationsPreferences: Codable, Equatable, Sendable {
    /// Offer to remove an app's leftover files when the app is dragged to the Trash.
    public var offerLeftoversOnTrash: Bool = true

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offerLeftoversOnTrash = (try? c.decodeIfPresent(Bool.self, forKey: .offerLeftoversOnTrash)) ?? nil ?? offerLeftoversOnTrash
    }

    private enum CodingKeys: String, CodingKey { case offerLeftoversOnTrash }
}

/// Persists `ApplicationsPreferences` next to the app's other files.
public final class ApplicationsPreferenceStore: @unchecked Sendable {
    public static let shared = ApplicationsPreferenceStore(
        url: SprucePaths.applicationSupport.appendingPathComponent("applications-preferences.json"))

    private let store: JSONFileStore<ApplicationsPreferences>
    private let lock = NSLock()
    private var cached: ApplicationsPreferences?

    public init(url: URL) {
        store = JSONFileStore(url: url)
    }

    public var preferences: ApplicationsPreferences {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let cached { return cached }
            let value = store.load() ?? ApplicationsPreferences()
            cached = value
            return value
        }
        set {
            lock.lock()
            cached = newValue
            try? store.save(newValue)
            lock.unlock()
        }
    }
}

/// Apps the user removed (to find their leftovers later) and apps Spruce removed itself.
final class ApplicationsRemovedAppStore: @unchecked Sendable {
    static let shared = ApplicationsRemovedAppStore(
        url: SprucePaths.applicationSupport.appendingPathComponent("applications-removed-apps.json"))

    struct Contents: Codable, Equatable {
        var log = ApplicationsRemovedAppLog()
        /// Lowercased bundle id → when Spruce's Uninstaller (or an in-place update) trashed it.
        var removedBySpruce: [String: Date] = [:]

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            log = (try? c.decodeIfPresent(ApplicationsRemovedAppLog.self, forKey: .log)) ?? nil ?? ApplicationsRemovedAppLog()
            removedBySpruce = (try? c.decodeIfPresent([String: Date].self, forKey: .removedBySpruce)) ?? nil ?? [:]
        }

        private enum CodingKeys: String, CodingKey { case log, removedBySpruce }
    }

    private let store: JSONFileStore<Contents>
    private let lock = NSLock()
    private var cached: Contents?

    init(url: URL) {
        store = JSONFileStore(url: url, prettyPrinted: false)
    }

    var contents: Contents {
        lock.lock()
        defer { lock.unlock() }
        return loaded()
    }

    func update(_ change: (inout Contents) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var value = loaded()
        let before = value
        change(&value)
        let cutoff = Date().addingTimeInterval(-ApplicationsRemovedAppLog.maxAge)
        value.removedBySpruce = value.removedBySpruce.filter { $0.value >= cutoff }
        guard value != before else { return }
        cached = value
        try? store.save(value)
    }

    private func loaded() -> Contents {
        if let cached { return cached }
        let value = store.load() ?? Contents()
        cached = value
        return value
    }
}

// MARK: - Trash watcher

/// Watches the Trash for apps the user drags there and offers to remove what they left
/// behind ("Finish removing “X”?"). Read-only: it only reads the trashed bundle and looks
/// for its files; removal happens from the Leftovers review, through `FileRemover`.
///
/// Runs only with Full Disk Access (the Trash is protected) and while
/// `ApplicationsPreferences.offerLeftoversOnTrash` is on.
public final class ApplicationsTrashWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.spruce.applications.trash-watch", qos: .utility)
    private weak var engine: ApplicationsEngine?

    // Confined to `queue`.
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var snapshots: [String: Set<String>] = [:]
    private var pendingCheck: DispatchWorkItem?
    private var timer: DispatchSourceTimer?
    private var isStarted = false

    // Main thread.
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    private let stateLock = NSLock()
    private var recordedAt: Date?

    public init() {}

    /// When the last trashed app's leftovers were recorded (the Leftovers tool re-scans
    /// when it is newer than its results).
    public var lastRecordAt: Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recordedAt
    }

    // MARK: Spruce's own removals

    private static let removalLock = NSLock()
    nonisolated(unsafe) private static var spruceRemovals: [String: Date] = [:]

    /// Marks apps Spruce itself is about to trash (Uninstaller, in-place updates) so no
    /// "Finish removing?" offer follows. Also remembered so Leftovers doesn't re-offer files
    /// the user chose to keep in the Uninstaller.
    static func noteSpruceRemoval(bundleIDs: [String], for duration: TimeInterval = 1800) {
        let ids = bundleIDs.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        removalLock.lock()
        let until = Date().addingTimeInterval(duration)
        for id in ids { spruceRemovals[id] = until }
        removalLock.unlock()
        ApplicationsRemovedAppStore.shared.update { contents in
            for id in ids {
                contents.removedBySpruce[id] = Date()
                contents.log.remove(bundleID: id)
            }
        }
    }

    /// Shortens the in-process mark once the removal finished (the Trash event follows within seconds).
    static func endSpruceRemoval(bundleIDs: [String]) {
        removalLock.lock()
        let until = Date().addingTimeInterval(60)
        for id in bundleIDs.map({ $0.lowercased() }) where spruceRemovals[id] != nil { spruceRemovals[id] = until }
        removalLock.unlock()
    }

    /// True while Spruce is removing the app (or just did). With `includeHistory`, also when
    /// Spruce's Uninstaller removed it in the last 30 days (and it wasn't installed again since).
    static func isSpruceRemoval(_ bundleID: String, includeHistory: Bool = true, now: Date = Date()) -> Bool {
        let id = bundleID.lowercased()
        removalLock.lock()
        spruceRemovals = spruceRemovals.filter { $0.value > now }
        let inProcess = spruceRemovals[id] != nil
        removalLock.unlock()
        if inProcess || !includeHistory { return inProcess }
        return ApplicationsRemovedAppStore.shared.contents.removedBySpruce[id] != nil
    }

    /// Forgets Spruce's own removals of apps that are installed again.
    static func forgetSpruceRemovals(installedBundleIDs: Set<String>) {
        ApplicationsRemovedAppStore.shared.update { contents in
            contents.removedBySpruce = contents.removedBySpruce.filter { !installedBundleIDs.contains($0.key) }
        }
    }

    // MARK: Lifecycle

    /// Starts watching (idempotent). Re-checks permissions and the preference every few
    /// minutes, when Spruce becomes active and when disks are mounted.
    public func start(engine: ApplicationsEngine) {
        self.engine = engine
        queue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true
            self.refreshOnQueue()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 600, repeating: 600, leeway: .seconds(60))
            timer.setEventHandler { [weak self] in self?.refreshOnQueue() }
            timer.resume()
            self.timer = timer
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.observers.isEmpty else { return }
            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didWakeNotification] {
                let token = workspace.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.refresh() }
                self.observers.append((workspace, token))
            }
            let token = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                               queue: nil) { [weak self] _ in self?.refresh() }
            self.observers.append((NotificationCenter.default, token))
        }
    }

    /// Re-reads the preference and permissions; arms or disarms the watch.
    public func refresh() {
        queue.async { [weak self] in self?.refreshOnQueue() }
    }

    private var isEnabled: Bool {
        ApplicationsPreferenceStore.shared.preferences.offerLeftoversOnTrash && Permissions.hasFullDiskAccess
    }

    private func refreshOnQueue() {
        guard isStarted else { return }
        guard isEnabled else {
            for source in sources.values { source.cancel() }
            sources = [:]
            snapshots = [:]
            return
        }
        let folders = Set(Self.trashFolders())
        for (folder, source) in sources where !folders.contains(folder) {
            source.cancel()
            sources[folder] = nil
            snapshots[folder] = nil
        }
        for folder in folders where sources[folder] == nil {
            arm(folder)
        }
    }

    private func arm(_ folder: String) {
        let descriptor = open(folder, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .delete, .rename, .revoke], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, let current = self.sources[folder] else { return }
            let events = current.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
                // The folder itself went away (disk ejected, Trash recreated): watch it again later.
                current.cancel()
                self.sources[folder] = nil
                self.snapshots[folder] = nil
                self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.refreshOnQueue() }
                return
            }
            self.scheduleCheck()
        }
        source.setCancelHandler { close(descriptor) }
        snapshots[folder] = Set(Self.appBundleNames(in: folder))
        sources[folder] = source
        source.resume()
    }

    /// Waits for the Trash to settle (Finder moves several items one by one).
    private func scheduleCheck() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkForNewApps() }
        pendingCheck = work
        queue.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func checkForNewApps() {
        var added: [String] = []
        for folder in sources.keys {
            let current = Self.appBundleNames(in: folder)
            let previous = snapshots[folder] ?? []
            for name in ApplicationsTrashedAppRules.newBundles(previous: previous, current: current) {
                added.append((folder as NSString).appendingPathComponent(name))
            }
            snapshots[folder] = Set(current)
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if !added.isEmpty { await self.handle(added) }
            await self.withdrawReinstalled()
        }
    }

    // MARK: Trash folders

    /// The user's Trash and, on other disks, `.Trashes/<uid>` where it exists.
    static func trashFolders() -> [String] {
        var folders = [(NSHomeDirectory() as NSString).appendingPathComponent(".Trash")]
        let uid = String(getuid())
        for volume in (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? [] {
            let trash = "/Volumes/\(volume)/.Trashes/\(uid)"
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: trash, isDirectory: &isDirectory), isDirectory.boolValue {
                folders.append(trash)
            }
        }
        return folders.filter { FileManager.default.isReadableFile(atPath: $0) }
    }

    /// Names of the top-level `.app` bundles in a Trash folder.
    static func appBundleNames(in folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.lowercased().hasSuffix(".app") }
    }

    /// Every app bundle in the Trash right now, read like an installed app.
    static func appsInTrash() -> [(app: ApplicationsAppInfo, addedToTrash: Date?)] {
        var result: [(app: ApplicationsAppInfo, addedToTrash: Date?)] = []
        for folder in trashFolders() {
            for name in appBundleNames(in: folder) {
                let path = (folder as NSString).appendingPathComponent(name)
                guard FileWalker.entry(at: path)?.isSymlink == false, let app = readTrashedApp(path) else { continue }
                let added = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
                result.append((app, added))
            }
        }
        return result
    }

    /// Reads a bundle in the Trash (nil for Spruce itself and unreadable bundles).
    static func readTrashedApp(_ path: String) -> ApplicationsAppInfo? {
        let context = ApplicationsCatalogReader.Context(
            runningPaths: [], runningBundleIDs: [], caskTokens: [:],
            ownBundlePath: (Bundle.main.bundlePath as NSString).standardizingPath, ownBundleID: Bundle.main.bundleIdentifier)
        return ApplicationsCatalogReader().readApp(path: path, isSystem: false, context: context, measure: nil)
    }

    // MARK: Offer

    private func handle(_ paths: [String]) async {
        guard let engine else { return }
        let settings = await ApplicationsMac.settings()
        let running = await MainActor.run { () -> (ids: Set<String>, paths: Set<String>) in
            var ids = Set<String>()
            var paths = Set<String>()
            for app in NSWorkspace.shared.runningApplications {
                if let id = app.bundleIdentifier { ids.insert(id.lowercased()) }
                if let path = app.bundleURL?.path { paths.insert((path as NSString).standardizingPath) }
            }
            return (ids, paths)
        }
        var installed = engine.lastApps
        if installed.isEmpty { installed = await engine.loadApps(measureSizes: false) }

        for path in paths {
            guard let app = await ApplicationsMac.background({ Self.readTrashedApp(path) }) else { continue }
            let elsewhere = await Self.isInstalledOutsideTrash(bundleID: app.bundleID, fileName: (path as NSString).lastPathComponent,
                                                               catalog: installed)
            let isRunning = running.paths.contains((path as NSString).standardizingPath)
            if ApplicationsTrashedAppRules.skipReason(bundleID: app.bundleID, ownBundleID: Bundle.main.bundleIdentifier,
                                                      ignoredBundleIDs: settings.ignoredBundleIDs,
                                                      removedBySpruce: Self.isSpruceRemoval(app.bundleID, includeHistory: false),
                                                      installedElsewhere: elsewhere, isRunning: isRunning) != nil {
                continue
            }
            let others = installed.filter {
                $0.bundleID.caseInsensitiveCompare(app.bundleID) != .orderedSame && !ApplicationsTrashedAppRules.isInTrash($0.path)
            }.map(\.identity)
            let found: (count: Int, bytes: Int64, launchItem: Bool) = await ApplicationsMac.background {
                let candidates = ApplicationsLeftoverMatcher().candidates(for: app.identity, others: others).filter {
                    !settings.isIgnored(path: $0.path)
                }
                let bytes = candidates.reduce(Int64(0)) { $0 + ApplicationsMeasured.measure($1.path).bytes }
                return (candidates.count, bytes, candidates.contains { $0.kind == .launchItems })
            }
            guard ApplicationsTrashedAppRules.isWorthOffering(bytes: found.bytes, count: found.count,
                                                               hasLaunchItem: found.launchItem) else { continue }
            let removed = ApplicationsRemovedApp(bundleID: app.bundleID, name: app.name, trashedPath: path, identity: app.identity)
            ApplicationsRemovedAppStore.shared.update { $0.log.record(removed) }
            stateLock.holding { recordedAt = Date() }
            guard ApplicationsPreferenceStore.shared.preferences.offerLeftoversOnTrash else { continue }
            let message = ApplicationsTrashedAppRules.message(appName: app.name, count: found.count, bytes: found.bytes)
            let id = ApplicationsTrashedAppRules.notificationID(bundleID: app.bundleID)
            await MainActor.run {
                Notifier.post(id: id, title: message.title, body: message.body, module: ModuleID.applications.rawValue,
                              tool: "applications.leftovers")
            }
        }
    }

    /// Withdraws offers for apps that were put back (installed again).
    private func withdrawReinstalled() async {
        guard let engine else { return }
        let recent = ApplicationsRemovedAppStore.shared.contents.log.apps.filter {
            Date().timeIntervalSince($0.removedAt) < 7 * 86_400
        }
        guard !recent.isEmpty else { return }
        for app in recent {
            let fileName = (app.trashedPath as NSString).lastPathComponent
            guard await Self.isInstalledOutsideTrash(bundleID: app.bundleID, fileName: fileName, catalog: engine.lastApps) else {
                continue
            }
            ApplicationsRemovedAppStore.shared.update { $0.log.remove(bundleID: app.bundleID) }
            Self.withdraw(bundleID: app.bundleID)
        }
    }

    static func withdraw(bundleID: String) {
        let id = ApplicationsTrashedAppRules.notificationID(bundleID: bundleID)
        InboxStore.shared.remove(id: id)
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// True when a copy of the app exists outside the Trash (an update replaced it, it was
    /// put back, or another copy is installed).
    static func isInstalledOutsideTrash(bundleID: String, fileName: String, catalog: [ApplicationsAppInfo]) async -> Bool {
        guard !bundleID.isEmpty else { return false }
        let fm = FileManager.default
        let registered = await MainActor.run { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).map(\.path) }
        if registered.contains(where: { !ApplicationsTrashedAppRules.isInTrash($0) && fm.fileExists(atPath: $0) }) { return true }
        if catalog.contains(where: {
            $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame && !ApplicationsTrashedAppRules.isInTrash($0.path)
                && fm.fileExists(atPath: $0.path)
        }) { return true }
        for folder in ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")] {
            let candidate = (folder as NSString).appendingPathComponent(fileName)
            let plist = ApplicationsPlist.dictionary(atPath: (candidate as NSString).appendingPathComponent("Contents/Info.plist"))
            if (plist?["CFBundleIdentifier"] as? String)?.caseInsensitiveCompare(bundleID) == .orderedSame { return true }
        }
        return false
    }
}

// MARK: - Background update check

/// Checks for app updates about once a day while Settings › Notifications › App updates
/// is on, and announces versions not announced before ("3 app updates available").
/// Checks made in Spruce (Updater, overview, Checkup) count too, so nothing is announced
/// twice and the background check only runs when nobody looked for a day.
public final class ApplicationsUpdateWatch: @unchecked Sendable {
    public static let notificationID = "app.spruce.updates"
    public static let activityIdentifier = "app.spruce.applications.updates"

    private weak var engine: ApplicationsEngine?
    private let store: JSONFileStore<ApplicationsUpdateAlertState>
    private let lock = NSLock()
    private var cached: ApplicationsUpdateAlertState?
    private var scheduler: NSBackgroundActivityScheduler?
    private var isChecking = false

    public init(url: URL = SprucePaths.applicationSupport.appendingPathComponent("applications-update-alerts.json")) {
        store = JSONFileStore(url: url)
    }

    /// Schedules the daily check (idempotent).
    public func start(engine: ApplicationsEngine) {
        lock.lock()
        self.engine = engine
        guard scheduler == nil else {
            lock.unlock()
            return
        }
        let activity = NSBackgroundActivityScheduler(identifier: Self.activityIdentifier)
        activity.repeats = true
        // Wakes every few hours; `runIfDue` only goes online when a day has passed.
        activity.interval = 3 * 3600
        activity.tolerance = 3600
        activity.qualityOfService = .utility
        scheduler = activity
        lock.unlock()
        activity.schedule { [weak self] completion in
            guard let self else {
                completion(.finished)
                return
            }
            Task.detached(priority: .utility) {
                await self.runIfDue()
                completion(.finished)
            }
        }
        // The scheduler's first run can be hours away: catch up shortly after launch.
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
            await self?.runIfDue()
        }
    }

    public var lastCheck: Date? {
        lock.lock()
        defer { lock.unlock() }
        return loaded().lastCheck
    }

    /// Checks online when update alerts are on and no check ran for a day.
    func runIfDue(now: Date = Date()) async {
        let settings = await ApplicationsMac.settings()
        guard settings.notifyUpdates, let engine else { return }
        let start: Bool = lock.holding {
            let due = ApplicationsUpdateAlertPlan.isDue(lastCheck: loaded().lastCheck, now: now)
            let begin = due && !isChecking
            if begin { isChecking = true }
            return begin
        }
        guard start else { return }
        defer { lock.holding { isChecking = false } }
        _ = await engine.loadApps(measureSizes: false)
        let found = await engine.checkUpdates()
        let fresh = await ApplicationsMac.settings()
        guard fresh.notifyUpdates else { return }
        let visible = ApplicationsUpdateIgnore.filtered(found, ignoredItemIDs: fresh.ignoredItemIDs,
                                                        ignoredBundleIDs: fresh.ignoredBundleIDs)
        record(visible, announce: true, checkedAt: Date())
    }

    /// Remembers `updates` (ignore list already applied). With `announce`, versions not seen
    /// before are posted as one notification; otherwise they only count as seen.
    public func record(_ updates: [ApplicationsUpdate], announce: Bool, checkedAt: Date? = Date()) {
        lock.lock()
        var state = loaded()
        let new = ApplicationsUpdateAlertPlan.newUpdates(updates, notified: state.notified)
        state.notified = ApplicationsUpdateAlertPlan.remembered(after: updates, previously: state.notified)
        if let checkedAt { state.lastCheck = checkedAt }
        cached = state
        try? store.save(state)
        lock.unlock()
        guard announce, !new.isEmpty else { return }
        let message = ApplicationsUpdateAlertPlan.message(newUpdates: new, totalAvailable: updates.count)
        let post = {
            Notifier.post(id: Self.notificationID, title: message.title, body: message.body,
                          module: ModuleID.applications.rawValue, tool: "applications.updater")
        }
        if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
    }

    /// Call with the lock held.
    private func loaded() -> ApplicationsUpdateAlertState {
        if let cached { return cached }
        let value = store.load() ?? ApplicationsUpdateAlertState()
        cached = value
        return value
    }
}

private extension NSLock {
    /// Runs `body` while holding the lock. Unlike `lock()`/`unlock()` it may be called from
    /// async code (the lock is never held across a suspension point).
    func holding<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
