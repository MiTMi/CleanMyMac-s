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
///
/// Recording is cheap: the history (up to 5,000 entries) is written to disk on a
/// background queue, at most about once a second, in compact JSON. Records made off the
/// main thread are applied on the main thread. Call `flush()` before the app quits.
@Observable
public final class HistoryStore {
    public static let shared = HistoryStore()

    public private(set) var history: ActivityHistory

    private let store: JSONFileStore<ActivityHistory>
    private let saveQueue = DispatchQueue(label: "app.spruce.history.save", qos: .utility)
    private let saveLock = NSLock()
    @ObservationIgnored private var pendingSave: ActivityHistory?
    @ObservationIgnored private var saveScheduled = false
    /// Coalescing window for disk writes.
    private let saveDelay: TimeInterval

    public init(url: URL = SprucePaths.historyFile, saveDelay: TimeInterval = 1) {
        store = JSONFileStore(url: url, prettyPrinted: false)
        self.saveDelay = saveDelay
        history = store.load() ?? ActivityHistory()
    }

    public func record(_ entry: ActivityEntry) {
        record([entry])
    }

    /// Records several entries with one save (e.g. all entries of a Checkup run).
    public func record(_ entries: [ActivityEntry]) {
        guard !entries.isEmpty else { return }
        onMain { [weak self] in
            guard let self else { return }
            for entry in entries { self.history.append(entry) }
            self.scheduleSave()
            for entry in entries where entry.kind == .checkup {
                InboxStore.shared.add(InboxItem(kind: .result, date: entry.date, title: "Checkup finished",
                                                body: entry.summary, module: ModuleID.checkup.rawValue))
            }
        }
    }

    public func record(_ outcome: RunOutcome, kind: ActivityEntry.Kind) {
        onMain { [weak self] in
            guard let self else { return }
            self.history.record(outcome, kind: kind)
            self.scheduleSave()
            if Self.resultKinds.contains(kind), outcome.didAnything {
                InboxStore.shared.add(InboxItem(kind: .result, date: outcome.date, title: "\(outcome.module.title) finished",
                                                body: outcome.summary, module: outcome.module.rawValue))
            }
        }
    }

    public func clear() {
        onMain { [weak self] in
            guard let self else { return }
            self.history = ActivityHistory()
            self.scheduleSave()
        }
    }

    /// Writes any pending change now (call when the app terminates).
    public func flush() {
        saveQueue.sync { writePending() }
    }

    // MARK: Private

    /// Runs that appear in the in-app Notification Center as results.
    private static let resultKinds: Set<ActivityEntry.Kind> = [
        .clean, .uninstall, .threatRemoved, .update, .cloudFreed, .maintenance, .startupItems,
    ]

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func scheduleSave() {
        let snapshot = history
        saveLock.lock()
        pendingSave = snapshot
        let schedule = !saveScheduled
        saveScheduled = true
        saveLock.unlock()
        guard schedule else { return }
        saveQueue.asyncAfter(deadline: .now() + saveDelay) { [weak self] in
            self?.writePending()
        }
    }

    /// Runs on `saveQueue`.
    private func writePending() {
        saveLock.lock()
        let value = pendingSave
        pendingSave = nil
        saveScheduled = false
        saveLock.unlock()
        guard let value else { return }
        try? store.save(value)
    }
}
