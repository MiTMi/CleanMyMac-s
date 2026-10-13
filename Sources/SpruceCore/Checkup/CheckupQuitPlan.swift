import Foundation

// MARK: - Apps to quit before a run

/// A selected Checkup item that an open app holds up (its data is in use, or the app
/// can't be updated while it runs).
public struct CheckupAppNeed: Hashable, Sendable {
    /// Process of the open app.
    public var processID: Int32
    public var bundleID: String
    public var name: String
    /// Path of the app bundle, when known (for its icon).
    public var appPath: String?
    public var module: ModuleID
    public var itemID: String
    /// Short label for what the item is ("Update", a maintenance task's title); nil for
    /// plain items, which are counted instead.
    public var label: String?

    public init(processID: Int32, bundleID: String, name: String, appPath: String? = nil,
                module: ModuleID, itemID: String, label: String? = nil) {
        self.processID = processID
        self.bundleID = bundleID
        self.name = name
        self.appPath = appPath
        self.module = module
        self.itemID = itemID
        self.label = label
    }
}

/// One row of the "Quit these apps first?" sheet: an open app and the selected items it
/// holds up.
public struct CheckupBlockingApp: Identifiable, Hashable, Sendable {
    public var processID: Int32
    public var bundleID: String
    public var name: String
    public var appPath: String?
    /// Ids of the items it holds up, per area (in the order they were found).
    public var itemIDs: [ModuleID: [String]]
    /// What it holds up, in run order: "Cleanup: 3 items · Applications: Update".
    public var detail: String

    public var id: Int32 { processID }

    public init(processID: Int32, bundleID: String, name: String, appPath: String? = nil,
                itemIDs: [ModuleID: [String]], detail: String) {
        self.processID = processID
        self.bundleID = bundleID
        self.name = name
        self.appPath = appPath
        self.itemIDs = itemIDs
        self.detail = detail
    }

    /// Areas it holds up, in run order.
    public var modules: [ModuleID] { CheckupRunOrder.plan(for: Set(itemIDs.keys)) }
}

/// Builds the "Quit these apps first?" sheet and its "Skip These Items" choice.
public enum CheckupQuitPlan {
    /// One row per open app (by process), Spruce itself left out, sorted by name.
    public static func blockingApps(_ needs: [CheckupAppNeed], ownProcessID: Int32? = nil) -> [CheckupBlockingApp] {
        var order: [Int32] = []
        var byProcess: [Int32: [CheckupAppNeed]] = [:]
        var seen = Set<String>()
        for need in needs where need.processID != ownProcessID {
            let key = "\(need.processID)|\(need.module.rawValue)|\(need.itemID)"
            guard seen.insert(key).inserted else { continue }
            if byProcess[need.processID] == nil { order.append(need.processID) }
            byProcess[need.processID, default: []].append(need)
        }
        let apps = order.compactMap { pid -> CheckupBlockingApp? in
            guard let needs = byProcess[pid], let first = needs.first else { return nil }
            var itemIDs: [ModuleID: [String]] = [:]
            for need in needs { itemIDs[need.module, default: []].append(need.itemID) }
            return CheckupBlockingApp(processID: pid, bundleID: first.bundleID, name: first.name,
                                      appPath: needs.lazy.compactMap(\.appPath).first,
                                      itemIDs: itemIDs, detail: detail(for: needs))
        }
        return apps.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return comparison == .orderedSame ? lhs.processID < rhs.processID : comparison == .orderedAscending
        }
    }

    /// "Cleanup: 3 items · Performance: Speed Up Mail · Applications: Update".
    static func detail(for needs: [CheckupAppNeed]) -> String {
        let modules = CheckupRunOrder.plan(for: Set(needs.map(\.module)))
        let segments = modules.map { module -> String in
            let mine = needs.filter { $0.module == module }
            var labels: [String] = []
            for label in mine.compactMap(\.label) where !labels.contains(label) { labels.append(label) }
            let plain = mine.filter { $0.label == nil }.count
            var parts: [String] = []
            if !labels.isEmpty {
                let shown = labels.prefix(2).joined(separator: ", ")
                parts.append(labels.count > 2 ? "\(shown) +\(labels.count - 2) more" : shown)
            }
            if plain > 0 { parts.append(CountFormat.items(plain)) }
            return "\(module.title): " + parts.joined(separator: ", ")
        }
        return segments.joined(separator: " · ")
    }

    /// The item ids the given apps hold up, per area ("Skip These Items" deselects them).
    public static func itemIDs(of apps: [CheckupBlockingApp]) -> [ModuleID: Set<String>] {
        var result: [ModuleID: Set<String>] = [:]
        for app in apps {
            for (module, ids) in app.itemIDs { result[module, default: []].formUnion(ids) }
        }
        return result
    }

    /// `groups` with the given items deselected (everything else unchanged).
    public static func deselecting(_ ids: Set<String>, in groups: [ScanGroup]) -> [ScanGroup] {
        guard !ids.isEmpty else { return groups }
        var copy = groups
        for id in ids { copy.setSelected(false, itemID: id) }
        return copy
    }
}
