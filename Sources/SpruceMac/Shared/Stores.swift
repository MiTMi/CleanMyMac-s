import Foundation
import Observation
import SpruceCore

/// Observable, persisted user settings. Shared by the app, the monitor and all engines.
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()

    public var settings: SpruceSettings {
        didSet { if settings != oldValue { save() } }
    }

    private let store: JSONFileStore<SpruceSettings>

    public init(url: URL = SprucePaths.settingsFile) {
        store = JSONFileStore(url: url)
        settings = store.load() ?? SpruceSettings()
    }

    private func save() {
        try? store.save(settings)
    }

    // Ignore-list conveniences.

    public func ignore(path: String) {
        let tilde = path.abbreviatingHome
        guard !settings.ignoredPaths.contains(tilde) else { return }
        settings.ignoredPaths.append(tilde)
    }

    public func ignore(bundleID: String) {
        guard !settings.ignoredBundleIDs.contains(bundleID) else { return }
        settings.ignoredBundleIDs.append(bundleID)
    }

    public func ignore(itemID: String) {
        guard !settings.ignoredItemIDs.contains(itemID) else { return }
        settings.ignoredItemIDs.append(itemID)
    }
}

/// Observable, persisted activity history (powers the Activity dashboard).
@Observable
public final class HistoryStore {
    public static let shared = HistoryStore()

    public private(set) var history: ActivityHistory

    private let store: JSONFileStore<ActivityHistory>

    public init(url: URL = SprucePaths.historyFile) {
        store = JSONFileStore(url: url)
        history = store.load() ?? ActivityHistory()
    }

    public func record(_ entry: ActivityEntry) {
        history.append(entry)
        try? store.save(history)
    }

    public func record(_ outcome: RunOutcome, kind: ActivityEntry.Kind) {
        history.record(outcome, kind: kind)
        try? store.save(history)
    }

    public func clear() {
        history = ActivityHistory()
        try? store.save(history)
    }
}
