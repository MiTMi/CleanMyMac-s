import AppKit
import Foundation
import SpruceCore

/// Removes apps and their files (always to the Trash, always through `FileRemover`).
enum ApplicationsUninstaller {

    // MARK: Running apps

    /// Running instances of the app at `path` (or with its bundle id).
    @MainActor
    static func runningInstances(path: String, bundleID: String) -> [NSRunningApplication] {
        let standardized = (path as NSString).standardizingPath
        return NSWorkspace.shared.runningApplications.filter { running in
            if let url = running.bundleURL, (url.path as NSString).standardizingPath == standardized { return true }
            return false
        }
    }

    /// Asks running apps to quit (like ⌘Q, so they can save) and waits up to `timeout` seconds.
    /// Returns the paths of apps that are still open.
    @MainActor
    static func quit(_ apps: [(path: String, bundleID: String)], timeout: TimeInterval = 10) async -> Set<String> {
        var instances: [(path: String, app: NSRunningApplication)] = []
        for app in apps {
            for instance in runningInstances(path: app.path, bundleID: app.bundleID) {
                instances.append((app.path, instance))
            }
        }
        guard !instances.isEmpty else { return [] }
        for entry in instances { _ = entry.app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if instances.allSatisfy({ $0.app.isTerminated }) { return [] }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return Set(instances.filter { !$0.app.isTerminated }.map(\.path))
    }

    // MARK: Dock

    /// True when the Dock has a tile for the app.
    static func isInDock(appPath: String) -> Bool {
        guard let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else {
            return false
        }
        return tiles.contains { tileMatches($0, appPath: appPath) }
    }

    static func tileMatches(_ tile: [String: Any], appPath: String) -> Bool {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let urlString = file["_CFURLString"] as? String else { return false }
        let path: String
        if let url = URL(string: urlString), url.isFileURL {
            path = url.path
        } else {
            path = urlString
        }
        return (path as NSString).standardizingPath.lowercased() == (appPath as NSString).standardizingPath.lowercased()
    }

    /// Removes the apps' Dock tiles. Only tiles pointing exactly at a removed app are touched.
    @discardableResult
    static func removeFromDock(appPaths: [String]) async -> Bool {
        guard !appPaths.isEmpty,
              let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else {
            return false
        }
        let kept = tiles.filter { tile in !appPaths.contains { tileMatches(tile, appPath: $0) } }
        guard kept.count != tiles.count else { return false }
        CFPreferencesSetAppValue("persistent-apps" as CFString, kept as NSArray as CFArray, "com.apple.dock" as CFString)
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        _ = await Shell.run("/usr/bin/killall", ["Dock"])
        return true
    }

    // MARK: Removal

    /// Removes the given checklist items (from one or more apps).
    ///
    /// 1. Apps whose bundle or data is selected are asked to quit; if one stays open its
    ///    items are skipped.
    /// 2. User launch agents are unloaded (`launchctl bootout`) before they are trashed.
    /// 3. Files go to the Trash through `FileRemover` (app bundles and launch items allowed).
    /// 4. Dock tiles of removed apps are removed; cached preferences are flushed.
    static func remove(_ items: [ScanItem], progress: ProgressHandler?) async -> RunOutcome {
        let settings = await ApplicationsMac.settings()
        let byApp = Dictionary(grouping: items) { $0.metadata[ApplicationsMeta.appPath] ?? "" }

        var failures: [ItemFailure] = []
        var removable: [ScanItem] = []
        var appsToQuit: [(path: String, bundleID: String)] = []
        for (appPath, appItems) in byApp where !appPath.isEmpty {
            appsToQuit.append((appPath, appItems.first?.metadata[ApplicationsMeta.bundleID] ?? ""))
        }
        progress?(ScanProgress(fraction: 0, message: "Quitting apps…"))
        let stillOpen = await quit(appsToQuit)
        for (appPath, appItems) in byApp {
            if stillOpen.contains(appPath) {
                let name = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
                for item in appItems {
                    failures.append(ItemFailure(itemID: item.id, title: item.title, reason: "\(name) is still open. Quit it and try again."))
                }
            } else {
                removable.append(contentsOf: appItems)
            }
        }

        // Unload the user's launch agents first so nothing respawns from the Trash.
        let home = NSHomeDirectory()
        for item in removable {
            guard let path = item.url?.path, path.hasSuffix(".plist"),
                  path.hasPrefix(home + "/Library/LaunchAgents/") else { continue }
            _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(ApplicationsMac.uid)", path], timeout: 15)
        }

        let files = removable.filter { $0.deletion != .custom }
        var outcome = await FileRemover.shared.dispose(files, module: .applications, options: [.allowAppBundles, .allowLaunchItems],
                                                       settings: settings, escalate: false, progress: progress)
        outcome.failures = failures + outcome.failures

        // Dock tiles: only for apps whose bundle really left.
        let removedIDs = Set(outcome.removedItemIDs)
        let removedApps = removable.filter {
            $0.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.application.rawValue && removedIDs.contains($0.id)
        }.compactMap { $0.metadata[ApplicationsMeta.appPath] }
        let dockItems = removable.filter { $0.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.dockIcon.rawValue }
        let dockApps = dockItems.compactMap { $0.metadata[ApplicationsMeta.appPath] }.filter { removedApps.contains($0) }
        if !dockApps.isEmpty {
            progress?(ScanProgress(fraction: nil, message: "Removing Dock icons…", bytesFound: outcome.freedBytes))
            if await removeFromDock(appPaths: dockApps) {
                for item in dockItems where dockApps.contains(item.metadata[ApplicationsMeta.appPath] ?? "") {
                    outcome.removedItemIDs.append(item.id)
                }
            }
        }

        // Preferences are cached by cfprefsd; restart the user's instance so a reset app
        // really starts fresh (it is relaunched on demand).
        let removedPrefs = removable.contains {
            $0.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.preferences.rawValue && removedIDs.contains($0.id)
        }
        if removedPrefs {
            _ = await Shell.run("/usr/bin/killall", ["-u", NSUserName(), "cfprefsd"], timeout: 10)
        }

        outcome.summary = summary(items: removable, outcome: outcome)
        return outcome
    }

    static func summary(items: [ScanItem], outcome: RunOutcome) -> String {
        let removedIDs = Set(outcome.removedItemIDs)
        let apps = items.filter {
            $0.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.application.rawValue && removedIDs.contains($0.id)
        }
        let size = ByteFormat.string(outcome.freedBytes)
        if apps.count == 1, let name = apps.first?.title {
            return "Uninstalled \((name as NSString).deletingPathExtension) · \(size)"
        }
        if apps.count > 1 { return "Uninstalled \(CountFormat.items(apps.count, singular: "app")) · \(size)" }
        if outcome.removedItemIDs.isEmpty { return "Nothing was removed" }
        let appNames = Set(items.compactMap { $0.metadata[ApplicationsMeta.appPath] }).map {
            (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        if appNames.count == 1, let name = appNames.first {
            return "Reset \(name) · \(size)"
        }
        return "Removed \(CountFormat.items(outcome.removedItemIDs.count)) · \(size)"
    }
}
