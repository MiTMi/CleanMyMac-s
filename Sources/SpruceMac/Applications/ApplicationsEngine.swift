import AppKit
import Foundation
import SpruceCore

/// Uninstaller, leftovers, installers, updater and extensions.
///
/// CONTRACT (used by AppModel and Checkup — keep these signatures):
/// * `public init()`
/// * `CheckupContributor` conformance (`checkupScan`, `checkupRun`)
/// * `GroupScanner` conformance (`scan`, `perform`) for the module's main review list
///
/// `scan` returns the files Spruce can tidy without touching installed apps: files of
/// removed apps (review only) and old installers. The Uninstaller works per app
/// (`components(for:mode:)` → `uninstall(_:)`); the Updater uses `checkUpdates`.
public final class ApplicationsEngine: CheckupContributor, GroupScanner, @unchecked Sendable {
    public let module: ModuleID = .applications

    /// Files of apps that are no longer installed (its own scan → review → remove journey).
    public private(set) lazy var leftovers = ApplicationsLeftoversScanner(engine: self)
    /// Old installers in Downloads and on the Desktop.
    public private(set) lazy var installers = ApplicationsInstallersScanner(engine: self)

    struct State {
        var apps: [ApplicationsAppInfo] = []
        var appsLoadedAt: Date?
        /// Bundle sizes by "path|version|build".
        var sizes: [String: Int64] = [:]
        var updates: [ApplicationsUpdate] = []
        var updatesCheckedAt: Date?
        var checkupReview: [ScanGroup] = []
    }

    private let state = ApplicationsLocked(State())

    /// Offers to remove what an app left behind when it is dragged to the Trash.
    public let trashWatcher = ApplicationsTrashWatcher()
    /// The daily background update check behind Settings › Notifications › App updates.
    public let updateWatch = ApplicationsUpdateWatch()
    private let backgroundStarted = ApplicationsLocked(false)

    public init() {
        // The app creates one engine at launch; start the background watchers then (not in
        // `swift run` builds or tests, which have no app bundle to post notifications from).
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") {
            DispatchQueue.main.async { [weak self] in self?.startBackgroundWork() }
        }
    }

    /// Starts the Trash watcher and the daily update check (idempotent).
    public func startBackgroundWork() {
        let first = backgroundStarted.update { (started: inout Bool) -> Bool in
            defer { started = true }
            return !started
        }
        guard first else { return }
        trashWatcher.start(engine: self)
        updateWatch.start(engine: self)
    }

    // MARK: - Catalog

    /// Apps found by the last `loadApps`.
    public var lastApps: [ApplicationsAppInfo] { state.current.apps }
    public var appsLoadedAt: Date? { state.current.appsLoadedAt }

    /// Finds installed apps and reads their metadata. Sizes are measured with `DiskUsage`
    /// (cached per app version) unless `measureSizes` is false.
    @discardableResult
    public func loadApps(measureSizes: Bool = true, progress: ProgressHandler? = nil) async -> [ApplicationsAppInfo] {
        progress?(ScanProgress(fraction: nil, message: "Finding applications…"))
        let running = await MainActor.run { () -> (paths: Set<String>, ids: Set<String>) in
            var paths = Set<String>()
            var ids = Set<String>()
            for app in NSWorkspace.shared.runningApplications {
                if let path = app.bundleURL?.path { paths.insert((path as NSString).standardizingPath) }
                if let id = app.bundleIdentifier { ids.insert(id.lowercased()) }
            }
            return (paths, ids)
        }
        let cachedSizes = state.current.sizes
        let result: (apps: [ApplicationsAppInfo], sizes: [String: Int64]) = await ApplicationsMac.background {
            let reader = ApplicationsCatalogReader()
            let context = ApplicationsCatalogReader.Context(
                runningPaths: running.paths, runningBundleIDs: running.ids,
                caskTokens: ApplicationsCatalogReader.caskTokensFromCaskroom(),
                ownBundlePath: (Bundle.main.bundlePath as NSString).standardizingPath,
                ownBundleID: Bundle.main.bundleIdentifier)
            let bundles = reader.bundlePaths()
            let measured = ApplicationsLocked(cachedSizes)
            let finished = ApplicationsLocked(0)
            let apps: [ApplicationsAppInfo] = ApplicationsMac.concurrentMap(bundles.count) { index in
                let bundle = bundles[index]
                var measure: ((String, String, String) -> Int64)?
                if measureSizes {
                    measure = { path, version, build in
                        let key = "\(path)|\(version)|\(build)"
                        if let cached = measured.current[key] { return cached }
                        let bytes = DiskUsage.measure(path).bytes
                        measured.update { $0[key] = bytes }
                        return bytes
                    }
                }
                let app = reader.readApp(path: bundle.path, isSystem: bundle.isSystem, context: context, measure: measure)
                let count = finished.update { (value: inout Int) -> Int in
                    value += 1
                    return value
                }
                progress?(ScanProgress(fraction: Double(count) / Double(max(bundles.count, 1)),
                                       message: measureSizes ? "Measuring applications…" : "Reading applications…",
                                       current: app?.name ?? (bundle.path as NSString).lastPathComponent))
                return app
            }
            return (apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, measured.current)
        }
        state.update {
            $0.apps = result.apps
            $0.appsLoadedAt = Date()
            $0.sizes = result.sizes
        }
        return result.apps
    }

    /// Re-reads one app from disk (after an update or a reset).
    public func refreshApp(_ app: ApplicationsAppInfo) async -> ApplicationsAppInfo? {
        let running = await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { instance in
                instance.bundleURL.map { ($0.path as NSString).standardizingPath } == (app.path as NSString).standardizingPath
            }
        }
        let refreshed: ApplicationsAppInfo? = await ApplicationsMac.background {
            let context = ApplicationsCatalogReader.Context(
                runningPaths: running ? [app.path] : [], runningBundleIDs: [],
                caskTokens: app.caskToken.map { [(app.path as NSString).lastPathComponent.lowercased(): $0] } ?? [:],
                ownBundlePath: (Bundle.main.bundlePath as NSString).standardizingPath, ownBundleID: Bundle.main.bundleIdentifier)
            return ApplicationsCatalogReader().readApp(path: app.path, isSystem: app.isSystem, context: context) { path, _, _ in
                DiskUsage.measure(path).bytes
            }
        }
        state.update { s in
            if let refreshed, let index = s.apps.firstIndex(where: { $0.path == app.path }) {
                s.apps[index] = refreshed
            } else if refreshed == nil {
                s.apps.removeAll { $0.path == app.path }
            }
        }
        return refreshed
    }

    /// Reads any app bundle (e.g. one dropped from Downloads), with its size. Apps inside
    /// /System (or symlinked there) are marked as part of macOS.
    public func readApp(at path: String) async -> ApplicationsAppInfo? {
        let standardized = (path as NSString).standardizingPath
        let running = await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { instance in
                instance.bundleURL.map { ($0.path as NSString).standardizingPath } == standardized
            }
        }
        return await ApplicationsMac.background {
            let resolved = (standardized as NSString).resolvingSymlinksInPath
            let context = ApplicationsCatalogReader.Context(
                runningPaths: running ? [standardized] : [], runningBundleIDs: [],
                caskTokens: ApplicationsCatalogReader.caskTokensFromCaskroom(),
                ownBundlePath: (Bundle.main.bundlePath as NSString).standardizingPath, ownBundleID: Bundle.main.bundleIdentifier)
            return ApplicationsCatalogReader().readApp(path: standardized, isSystem: resolved.hasPrefix("/System/"),
                                                       context: context) { path, _, _ in DiskUsage.measure(path).bytes }
        }
    }

    /// Whether each app is open right now (by bundle path).
    public func runningApps(among apps: [ApplicationsAppInfo]) async -> [ApplicationsAppInfo] {
        let paths = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL.map { ($0.path as NSString).standardizingPath } })
        }
        return apps.filter { paths.contains(($0.path as NSString).standardizingPath) }
    }

    // MARK: - Uninstaller

    /// The app's checklist: the app, its Dock icon and its files, with the default selection
    /// for `mode`.
    public func components(for app: ApplicationsAppInfo, mode: ApplicationsUninstallMode) async -> [ScanGroup] {
        guard app.canUninstall else { return [] }
        let others = state.current.apps.filter { $0.path != app.path }.map(\.identity)
        let settings = await ApplicationsMac.settings()
        let groups: [ScanGroup] = await ApplicationsMac.background {
            let candidates = ApplicationsLeftoverMatcher().candidates(for: app.identity, others: others)
            let inDock = ApplicationsUninstaller.isInDock(appPath: app.path)
            return ApplicationsComponents.groups(app: app, candidates: candidates, inDock: inDock, mode: mode)
        }
        // The ignore list applies to individual files; the app itself always stays listed.
        return groups.compactMap { group in
            var g = group
            g.items = g.items.filter { item in
                if item.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.application.rawValue { return true }
                guard let url = item.url else { return true }
                return !settings.isIgnored(path: url.path) && !settings.ignoredItemIDs.contains(item.id)
            }
            return g.items.isEmpty ? nil : g
        }
    }

    /// The items a complete uninstall of each app removes by default.
    public func defaultUninstallItems(for apps: [ApplicationsAppInfo]) async -> [ScanItem] {
        var items: [ScanItem] = []
        for app in apps where app.canUninstall {
            items += await components(for: app, mode: .uninstall).selectedItems
        }
        return items
    }

    /// Removes checklist items (uninstall or reset), quitting the apps first. Everything goes
    /// to the Trash through `FileRemover`.
    public func uninstall(_ items: [ScanItem], progress: ProgressHandler? = nil) async -> RunOutcome {
        // Spruce removes these apps itself: no "Finish removing?" offer afterwards.
        let appBundleIDs = items.filter { $0.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.application.rawValue }
            .compactMap { $0.metadata[ApplicationsMeta.bundleID] }
        ApplicationsTrashWatcher.noteSpruceRemoval(bundleIDs: appBundleIDs)
        let outcome = await ApplicationsUninstaller.remove(items, progress: progress)
        ApplicationsTrashWatcher.endSpruceRemoval(bundleIDs: appBundleIDs)
        let removedApps = Set(items.filter {
            $0.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.application.rawValue
                && outcome.removedItemIDs.contains($0.id)
        }.compactMap { $0.metadata[ApplicationsMeta.appPath] })
        if !removedApps.isEmpty {
            state.update { $0.apps.removeAll { removedApps.contains($0.path) } }
        }
        return outcome
    }

    /// Asks the apps to quit; returns the ones still open.
    public func quit(_ apps: [ApplicationsAppInfo]) async -> [ApplicationsAppInfo] {
        let open = await ApplicationsUninstaller.quit(apps.map { ($0.path, $0.bundleID) })
        return apps.filter { open.contains($0.path) }
    }

    // MARK: - Leftovers & installers

    /// Groups of files left by removed apps (nothing pre-selected).
    public func scanLeftovers(progress: ProgressHandler? = nil) async -> [ScanGroup] {
        progress?(ScanProgress(fraction: nil, message: "Indexing installed apps…"))
        var apps = state.current.apps
        if apps.isEmpty { apps = await loadApps(measureSizes: false) }
        let extra = await extraInstalledBundleIDs()
        let settings = await ApplicationsMac.settings()
        progress?(ScanProgress(fraction: nil, message: "Looking for files of removed apps…"))
        let removed = await removedAppsForLeftovers(installed: apps, extraBundleIDs: extra, settings: settings)
        let installedApps = apps.filter { !ApplicationsTrashedAppRules.isInTrash($0.path) }
        let groups: [ScanGroup] = await ApplicationsMac.background {
            let index = ApplicationsInstalledIndex(identities: installedApps.map(\.identity), extraBundleIDs: extra)
            let orphans = ApplicationsOrphanDetector().detect(index: index)
            let orphanGroups = ApplicationsOrphanPlan.groups(orphans)
            // Apps the user moved to the Trash: their files are found by the full matcher
            // (names, team, app groups, helpers), not only by bundle-id-shaped names.
            let matcher = ApplicationsLeftoverMatcher()
            let others = installedApps.map(\.identity)
            let removedGroups = ApplicationsRemovedAppPlan.groups(removed.map { entry in
                (app: entry.app, candidates: matcher.candidates(for: entry.app.identity, others: others), inTrash: entry.inTrash)
            })
            let covered = Set(removedGroups.allItems.compactMap { $0.url?.path })
            return removedGroups + ApplicationsRemovedAppPlan.excluding(covered, from: orphanGroups)
        }
        let filtered = settings.filteringIgnored(groups)
        progress?(ScanProgress(fraction: 1, message: "Done", bytesFound: filtered.totalSize))
        return filtered
    }

    /// Installers in Downloads and on the Desktop.
    public func scanInstallers(progress: ProgressHandler? = nil) async -> [ScanGroup] {
        progress?(ScanProgress(fraction: nil, message: "Looking for old installers…"))
        var apps = state.current.apps
        if apps.isEmpty { apps = await loadApps(measureSizes: false) }
        let attached = await attachedDiskImages()
        let settings = await ApplicationsMac.settings()
        // Apps that come with macOS never have installers in Downloads: "Photos 2019.dmg" is
        // someone's photo archive, not an installer of Photos.
        let installed = Self.installerMatchNames(apps)
        let groups: [ScanGroup] = await ApplicationsMac.background {
            let files = ApplicationsInstallerDetector().scan(installedApps: installed, attachedImages: attached)
            return ApplicationsInstallerPlan.groups(files)
        }
        let filtered = settings.filteringIgnored(groups)
        progress?(ScanProgress(fraction: 1, message: "Done", bytesFound: filtered.totalSize))
        return filtered
    }

    /// Review groups for installer files handed over from Finder or dropped, wherever they
    /// are. Nothing is ticked.
    public func installerGroups(for paths: [String]) async -> [ScanGroup] {
        var apps = state.current.apps
        if apps.isEmpty { apps = await loadApps(measureSizes: false) }
        let attached = await attachedDiskImages()
        let installed = Self.installerMatchNames(apps)
        return await ApplicationsMac.background {
            let files = ApplicationsInstallerDetector(roots: []).describe(paths: paths, installedApps: installed,
                                                                          attachedImages: attached)
            return ApplicationsInstallerPlan.groups(files, preselect: false)
        }
    }

    /// Names installers are matched against, with the system flag (macOS's own apps are skipped).
    static func installerMatchNames(_ apps: [ApplicationsAppInfo]) -> [ApplicationsInstallerDetector.InstalledApp] {
        apps.flatMap { app in
            ([app.name] + app.names).map { ApplicationsInstallerDetector.InstalledApp(name: $0, isSystem: app.isSystem) }
        }
    }

    /// Apps whose leftovers the Leftovers tool lists by name: apps in the Trash now, and apps
    /// moved there earlier (remembered by the Trash watcher). Apps installed elsewhere, still
    /// running, removed by Spruce's Uninstaller, Apple's and ignored apps are left out.
    func removedAppsForLeftovers(installed: [ApplicationsAppInfo], extraBundleIDs: [String],
                                 settings: SpruceSettings) async -> [(app: ApplicationsRemovedApp, inTrash: Bool)] {
        let installedIDs = Set(installed.filter { !ApplicationsTrashedAppRules.isInTrash($0.path) }.map { $0.bundleID.lowercased() }
            + extraBundleIDs.map { $0.lowercased() })
        let running = await MainActor.run { () -> (ids: Set<String>, paths: Set<String>) in
            var ids = Set<String>()
            var paths = Set<String>()
            for app in NSWorkspace.shared.runningApplications {
                if let id = app.bundleIdentifier { ids.insert(id.lowercased()) }
                if let path = app.bundleURL?.path { paths.insert((path as NSString).standardizingPath) }
            }
            return (ids, paths)
        }
        // An app Spruce removed earlier and that is installed again is the user's to trash now.
        let catalogIDs = Set(installed.filter {
            !ApplicationsTrashedAppRules.isInTrash($0.path) && FileManager.default.fileExists(atPath: $0.path)
        }.map { $0.bundleID.lowercased() })
        ApplicationsTrashWatcher.forgetSpruceRemovals(installedBundleIDs: catalogIDs)
        let trashed = await ApplicationsMac.background { ApplicationsTrashWatcher.appsInTrash() }
        var result: [String: (app: ApplicationsRemovedApp, inTrash: Bool)] = [:]
        func eligible(_ bundleID: String, path: String?) -> Bool {
            let lower = bundleID.lowercased()
            let runningNow = running.ids.contains(lower) || path.map { running.paths.contains(($0 as NSString).standardizingPath) } == true
            return ApplicationsTrashedAppRules.skipReason(
                bundleID: bundleID, ownBundleID: Bundle.main.bundleIdentifier, ignoredBundleIDs: settings.ignoredBundleIDs,
                removedBySpruce: ApplicationsTrashWatcher.isSpruceRemoval(bundleID),
                installedElsewhere: installedIDs.contains(lower), isRunning: runningNow) == nil
        }
        for entry in trashed where eligible(entry.app.bundleID, path: entry.app.path) {
            let removed = ApplicationsRemovedApp(bundleID: entry.app.bundleID, name: entry.app.name, trashedPath: entry.app.path,
                                                 removedAt: entry.addedToTrash ?? Date(), identity: entry.app.identity)
            result[removed.id] = (removed, true)
        }
        ApplicationsRemovedAppStore.shared.update { $0.log.prune(installedBundleIDs: installedIDs) }
        for app in ApplicationsRemovedAppStore.shared.contents.log.apps where result[app.id] == nil {
            guard eligible(app.bundleID, path: nil) else { continue }
            result[app.id] = (app, FileWalker.entry(at: app.trashedPath) != nil)
        }
        return Array(result.values)
    }

    /// Removes leftover or installer files (to the Trash). Launch agents and daemons are
    /// unloaded first; files of apps moved to the Trash that live in `/Library` are moved with
    /// one administrator prompt.
    public func removeFiles(_ items: [ScanItem], progress: ProgressHandler? = nil) async -> RunOutcome {
        let settings = await ApplicationsMac.settings()
        await ApplicationsUninstaller.unloadLaunchJobs(in: items, progress: progress)
        let needsAdmin = items.contains {
            $0.metadata[ApplicationsMeta.removedApp] != nil && $0.metadata[ApplicationsMeta.systemDomain] == "1"
        }
        var outcome = await FileRemover.shared.dispose(items, module: .applications, options: [.allowLaunchItems],
                                                       settings: settings, escalate: needsAdmin, progress: progress)
        let finished = Set(items.filter { outcome.removedItemIDs.contains($0.id) }.compactMap { $0.metadata[ApplicationsMeta.removedApp] })
        if !finished.isEmpty {
            // Leftovers that are gone no longer need an offer.
            for bundleID in finished { ApplicationsTrashWatcher.withdraw(bundleID: bundleID) }
        }
        outcome.summary = outcome.removedItemIDs.isEmpty
            ? "Nothing was removed"
            : "Moved \(CountFormat.items(outcome.removedItemIDs.count)) to the Trash · \(ByteFormat.string(outcome.freedBytes))"
        return outcome
    }

    /// Bundle ids of apps outside the scanned folders (Spotlight), running apps and loaded
    /// launchd jobs — so their files are never reported as leftovers.
    func extraInstalledBundleIDs() async -> [String] {
        let running = await MainActor.run { NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) }
        let found = await Shell.run("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"], timeout: 30)
        // Apps in the Trash are not installed: their files are exactly what Leftovers is for.
        let paths = found.stdout.split(separator: "\n").map(String.init)
            .filter { !ApplicationsTrashedAppRules.isInTrash($0) }.prefix(6000)
        let spotlightIDs: [String] = await ApplicationsMac.background {
            ApplicationsMac.concurrentMap(paths.count) { index -> String? in
                let path = paths[paths.startIndex + index]
                let plist = ApplicationsPlist.dictionary(atPath: (path as NSString).appendingPathComponent("Contents/Info.plist"))
                return plist?["CFBundleIdentifier"] as? String
            }
        }
        let launchd = await Shell.run("/bin/launchctl", ["list"], timeout: 15)
        let labels = launchd.stdout.split(separator: "\n").dropFirst().compactMap { line -> String? in
            let columns = line.split(separator: "\t")
            return columns.count >= 3 ? String(columns[2]) : nil
        }
        return running + spotlightIDs + labels
    }

    /// Paths of disk images that are mounted right now.
    func attachedDiskImages() async -> Set<String> {
        let result = await Shell.run("/usr/bin/hdiutil", ["info", "-plist"], timeout: 20)
        guard result.status == 0, let plist = ApplicationsPlist.dictionary(from: Data(result.stdout.utf8)),
              let images = plist["images"] as? [[String: Any]] else { return [] }
        return Set(images.compactMap { $0["image-path"] as? String })
    }

    // MARK: - Updater

    /// Updates found by the last check (not filtered by the ignore list).
    public var lastUpdates: [ApplicationsUpdate] { state.current.updates }
    public var updatesCheckedAt: Date? { state.current.updatesCheckedAt }
    public var hasHomebrew: Bool { ApplicationsMac.brewPath != nil }

    /// Checks Sparkle feeds, the App Store and Homebrew. Returns every update found;
    /// callers filter with `ApplicationsUpdateIgnore.filtered`.
    public func checkUpdates(progress: ProgressHandler? = nil) async -> [ApplicationsUpdate] {
        var apps = state.current.apps
        if apps.isEmpty { apps = await loadApps(measureSizes: false, progress: nil) }
        progress?(ScanProgress(fraction: 0, message: "Checking for updates…"))
        let updates = await ApplicationsUpdateChecker.check(apps: apps, progress: progress)
        state.update {
            $0.updates = updates
            $0.updatesCheckedAt = Date()
        }
        return updates
    }

    /// Installs a Homebrew update (`brew upgrade --cask`) and confirms the new version on disk.
    public func applyHomebrewUpdate(_ update: ApplicationsUpdate) async -> (ok: Bool, message: String) {
        guard update.source == .homebrew, let token = update.caskToken else {
            return (false, "This update is installed by the App Store or the app itself.")
        }
        let result = await ApplicationsUpdateChecker.upgradeCask(token)
        guard result.ok else { return result }
        if let installed = ApplicationsUpdateChecker.installedVersion(appPath: update.appPath),
           ApplicationsVersion.compare(installed.version, update.availableVersion) == .orderedAscending {
            return (false, "Homebrew finished, but \(update.name) still reports version \(installed.version).")
        }
        state.update { $0.updates.removeAll { $0.id == update.id } }
        if let app = state.current.apps.first(where: { $0.path == update.appPath }) {
            _ = await refreshApp(app)
        }
        return result
    }

    /// How `update` gets installed: Homebrew, in place by Spruce (verified Sparkle archive),
    /// or handed off to the App Store / the app.
    public func installMethod(for update: ApplicationsUpdate) -> ApplicationsUpdateInstallMethod {
        let app = state.current.apps.first { $0.path == update.appPath }
        return ApplicationsSparkleInstallPlan.method(for: update, app: app)
    }

    /// Why Spruce leaves a Sparkle update to the app itself (nil when Spruce can install it).
    public func handOffReason(for update: ApplicationsUpdate) -> String? {
        guard update.source == .sparkle else { return nil }
        let app = state.current.apps.first { $0.path == update.appPath }
        return ApplicationsSparkleInstallPlan.blocker(update: update, app: app)
    }

    /// Downloads, verifies and installs a Sparkle update in place (the app must be closed).
    /// The old version goes to the Trash. Reopens the app when `relaunch` is true.
    public func applySparkleUpdate(_ update: ApplicationsUpdate, relaunch: Bool = false,
                                   progress: ProgressHandler? = nil) async -> (ok: Bool, message: String) {
        guard let app = state.current.apps.first(where: { $0.path == update.appPath }) else {
            return (false, "The app wasn't found. Reload the list and try again.")
        }
        let result = await ApplicationsSparkleInstaller.install(update, app: app, progress: progress)
        ApplicationsTrashWatcher.endSpruceRemoval(bundleIDs: [app.bundleID])
        guard result.ok else { return (false, result.message) }
        state.update { $0.updates.removeAll { $0.id == update.id } }
        _ = await refreshApp(app)
        if relaunch {
            await MainActor.run { ApplicationsSparkleInstaller.relaunch(path: app.path) }
        }
        return (true, result.message)
    }

    /// Hand-off actions for updates Spruce does not install itself.
    public enum UpdateAction: Sendable {
        /// Open the App Store page (App Store updates).
        case appStore
        /// Open the app so its own updater installs the update (Sparkle).
        case openApp
        /// Open the download link or the vendor's page.
        case download
        case releaseNotes
    }

    @MainActor
    public func open(_ update: ApplicationsUpdate, action: UpdateAction) {
        switch action {
        case .appStore:
            if let url = update.storeURL ?? URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
        case .openApp:
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: update.appPath), configuration: configuration,
                                               completionHandler: nil)
        case .download:
            if let url = update.downloadURL { NSWorkspace.shared.open(url) }
        case .releaseNotes:
            if let url = update.releaseNotesURL { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - Extensions

    public func loadExtensions() async -> [ApplicationsExtensionInfo] {
        await ApplicationsExtensionManager.load()
    }

    /// Turns an app extension on or off. Returns the state macOS reports afterwards.
    public func setExtension(_ ext: ApplicationsExtensionInfo, enabled: Bool) async -> Bool? {
        await ApplicationsExtensionManager.setEnabled(ext, enabled: enabled)
    }

    /// Moves plug-in files to the Trash.
    public func removeExtensions(_ extensions: [ApplicationsExtensionInfo], progress: ProgressHandler? = nil) async -> RunOutcome {
        await ApplicationsExtensionManager.remove(extensions, progress: progress)
    }

    // MARK: - Finder helpers

    @MainActor
    public func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @MainActor
    public func launch(_ app: ApplicationsAppInfo) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    // MARK: - GroupScanner (files of removed apps + old installers)

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        let leftovers = await scanLeftovers(progress: progress)
        let installers = await scanInstallers(progress: progress)
        var groups: [ScanGroup] = []
        if !leftovers.isEmpty {
            groups.append(ScanGroup(id: ApplicationsOrphanPlan.rootGroupID, title: "Files from Removed Apps",
                                    detail: "Support files of apps that are no longer installed.", symbol: "questionmark.folder",
                                    safety: .review, children: leftovers))
        }
        if !installers.isEmpty {
            groups.append(ScanGroup(id: ApplicationsInstallerPlan.rootGroupID, title: "Old Installers",
                                    detail: "Disk images, packages and archives of apps.", symbol: "shippingbox",
                                    safety: .review, children: installers))
        }
        return groups
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        await removeFiles(items, progress: progress)
    }

    // MARK: - CheckupContributor

    public var checkupReview: [ScanGroup] {
        get { state.current.checkupReview }
        set { state.update { $0.checkupReview = newValue } }
    }

    public func checkupScan(progress: @escaping ProgressHandler) async throws -> CheckupTile {
        progress(ScanProgress(fraction: 0.05, message: "Reading your applications…"))
        let apps = await loadApps(measureSizes: false)
        try Task.checkCancellation()
        progress(ScanProgress(fraction: 0.3, message: "Looking for files of removed apps…"))
        let orphanGroups = await scanLeftovers(progress: nil)
        try Task.checkCancellation()
        let settings = await ApplicationsMac.settings()
        var updates: [ApplicationsUpdate] = []
        // Update checks use the network; they follow Settings › Notifications › updates.
        let checkUpdatesNow = settings.notifyUpdates
        if checkUpdatesNow {
            progress(ScanProgress(fraction: 0.5, message: "Checking for updates…"))
            let found = await ApplicationsUpdateChecker.check(apps: apps, progress: { p in
                progress(ScanProgress(fraction: 0.5 + 0.45 * (p.fraction ?? 0), message: p.message, current: p.current))
            })
            state.update {
                $0.updates = found
                $0.updatesCheckedAt = Date()
            }
            updates = ApplicationsUpdateIgnore.filtered(found, ignoredItemIDs: settings.ignoredItemIDs,
                                                        ignoredBundleIDs: settings.ignoredBundleIDs)
            // Seen on the Checkup tile; announced only when Checkup ran while Spruce was in the background.
            let isActive = await MainActor.run { NSApp?.isActive ?? true }
            updateWatch.record(updates, announce: !isActive)
        }
        let review = settings.filteringIgnored(ApplicationsCheckupPlan.review(updates: updates, orphanGroups: orphanGroups,
                                                                              apps: apps))
        checkupReview = review
        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: orphanGroups.totalSize))
        return ApplicationsCheckupPlan.tile(updates: updates, updatesChecked: checkUpdatesNow, orphanGroups: orphanGroups,
                                            apps: apps)
    }

    public func checkupRun(progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let selected = checkupReview.selectedItems
        let updateItems = selected.filter { $0.metadata[ApplicationsMeta.kind] == "update" }
        let fileItems = selected.filter { $0.metadata[ApplicationsMeta.kind] != "update" && $0.deletion != .custom }
        var outcomes: [RunOutcome] = []

        if !updateItems.isEmpty {
            var removed: [String] = []
            var failures: [ItemFailure] = []
            let knownApps = state.current.apps
            let updateApps = updateItems.compactMap { item in
                knownApps.first { $0.path == item.metadata[ApplicationsMeta.appPath] }
            }
            let openApps = await runningApps(among: updateApps)
            let openPaths = Set(openApps.map(\.path))
            let knownUpdates = state.current.updates
            for (index, item) in updateItems.enumerated() {
                try Task.checkCancellation()
                progress(ScanProgress(fraction: Double(index) / Double(max(updateItems.count + (fileItems.isEmpty ? 0 : 1), 1)),
                                      message: "Updating \(item.title)…"))
                if let path = item.metadata[ApplicationsMeta.appPath], openPaths.contains(path) {
                    failures.append(ItemFailure(itemID: item.id, title: item.title,
                                                reason: "The app is open. Quit it, then update from Applications › Updater."))
                    continue
                }
                let result: (ok: Bool, message: String)
                if item.metadata[ApplicationsMeta.updateMethod] == ApplicationsUpdateInstallMethod.sparkle.rawValue {
                    guard let update = knownUpdates.first(where: { "applications.update:" + $0.id == item.id }) else {
                        failures.append(ItemFailure(itemID: item.id, title: item.title,
                                                    reason: "The update is no longer offered. Check again in Applications › Updater."))
                        continue
                    }
                    result = await applySparkleUpdate(update)
                } else {
                    guard let token = item.metadata[ApplicationsMeta.caskToken] else { continue }
                    result = await ApplicationsUpdateChecker.upgradeCask(token)
                }
                if result.ok {
                    removed.append(item.id)
                } else {
                    failures.append(ItemFailure(itemID: item.id, title: item.title, reason: result.message))
                }
            }
            outcomes.append(RunOutcome(module: .applications, processedCount: removed.count, removedItemIDs: removed,
                                       failures: failures))
        }
        if !fileItems.isEmpty {
            let fileOutcome = await removeFiles(fileItems, progress: progress)
            outcomes.append(fileOutcome)
        }

        var outcome = RunOutcome.merged(outcomes, module: .applications)
        let updatedCount = outcomes.first.map { updateItems.isEmpty ? 0 : $0.removedItemIDs.count } ?? 0
        let fileCount = outcome.removedItemIDs.count - updatedCount
        var parts: [String] = []
        if updatedCount > 0 { parts.append("Updated \(CountFormat.items(updatedCount, singular: "app"))") }
        if fileCount > 0 { parts.append("removed \(CountFormat.items(fileCount, singular: "file")) (\(ByteFormat.string(outcome.freedBytes)))") }
        outcome.summary = parts.isEmpty ? "Nothing to do" : parts.joined(separator: " · ")
        if let first = outcome.summary.first { outcome.summary = String(first).uppercased() + outcome.summary.dropFirst() }
        let removedIDs = Set(outcome.removedItemIDs)
        state.update { $0.checkupReview.removeItems(withIDs: removedIDs) }
        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: outcome.freedBytes))
        return outcome
    }
}

// MARK: - Scanners for the Leftovers and Installers tools

/// Files of removed apps, as a `GroupScanner` for the standard review journey.
public final class ApplicationsLeftoversScanner: GroupScanner, @unchecked Sendable {
    private unowned let engine: ApplicationsEngine

    init(engine: ApplicationsEngine) { self.engine = engine }

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        await engine.scanLeftovers(progress: progress)
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        await engine.removeFiles(items, progress: progress)
    }
}

/// Old installers, as a `GroupScanner` for the standard review journey.
public final class ApplicationsInstallersScanner: GroupScanner, @unchecked Sendable {
    private unowned let engine: ApplicationsEngine

    init(engine: ApplicationsEngine) { self.engine = engine }

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        await engine.scanInstallers(progress: progress)
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        await engine.removeFiles(items, progress: progress)
    }
}
