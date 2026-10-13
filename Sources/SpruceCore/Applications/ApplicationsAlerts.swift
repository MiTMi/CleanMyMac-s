import Foundation

// MARK: - Update alerts

/// What the background update check remembers between runs.
public struct ApplicationsUpdateAlertState: Codable, Sendable, Equatable {
    /// `ApplicationsUpdate.skipVersionKey` of every update already announced (or seen in the app).
    public var notified: [String]
    /// When the last background check ran.
    public var lastCheck: Date?

    public init(notified: [String] = [], lastCheck: Date? = nil) {
        self.notified = notified
        self.lastCheck = lastCheck
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notified = (try? c.decodeIfPresent([String].self, forKey: .notified)) ?? nil ?? []
        lastCheck = (try? c.decodeIfPresent(Date.self, forKey: .lastCheck)) ?? nil
    }

    private enum CodingKeys: String, CodingKey { case notified, lastCheck }
}

/// Decides when the background update check runs and what its notification says.
public enum ApplicationsUpdateAlertPlan {
    /// Time between background checks.
    public static let checkInterval: TimeInterval = 24 * 3600

    /// True when no check ran yet, or the last one is older than `interval`.
    public static func isDue(lastCheck: Date?, now: Date = Date(), interval: TimeInterval = checkInterval) -> Bool {
        guard let lastCheck else { return true }
        // A clock set backwards must not stop checks forever.
        return now.timeIntervalSince(lastCheck) >= interval || lastCheck > now.addingTimeInterval(3600)
    }

    /// The key that identifies one version of one app's update.
    public static func key(_ update: ApplicationsUpdate) -> String { update.skipVersionKey }

    /// Updates (one per app, ignore list applied by the caller) not announced before.
    public static func newUpdates(_ updates: [ApplicationsUpdate], notified: [String]) -> [ApplicationsUpdate] {
        let known = Set(notified)
        var seen = Set<String>()
        return updates.filter { !known.contains(key($0)) && seen.insert(key($0)).inserted }
    }

    /// The remembered keys after a check: only versions still on offer are kept, so a list
    /// that shrinks after installs never re-announces old versions, and a newer version of
    /// the same app is announced again.
    public static func remembered(after updates: [ApplicationsUpdate], previously notified: [String]) -> [String] {
        let current = Set(updates.map(key))
        var result = notified.filter { current.contains($0) }
        for k in updates.map(key) where !result.contains(k) { result.append(k) }
        return result
    }

    /// "3 app updates available" / "Rectangle 0.80, VLC 3.0.21 and Safari Technology Preview".
    public static func message(newUpdates: [ApplicationsUpdate], totalAvailable: Int) -> (title: String, body: String) {
        let total = max(totalAvailable, newUpdates.count)
        let title: String
        if newUpdates.count == 1, total == 1, let only = newUpdates.first {
            title = "Update available for \(only.name)"
        } else {
            title = total == 1 ? "1 app update available" : "\(total) app updates available"
        }
        let names = newUpdates.sorted { lhs, rhs in
            if lhs.isCritical != rhs.isCritical { return lhs.isCritical }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }.map { "\($0.name) \($0.availableVersion)" }
        var body: String
        switch names.count {
        case 0: body = ""
        case 1: body = names[0]
        case 2: body = "\(names[0]) and \(names[1])"
        case 3: body = "\(names[0]), \(names[1]) and \(names[2])"
        default: body = "\(names[0]), \(names[1]), \(names[2]) and \(names.count - 3) more"
        }
        if newUpdates.contains(where: \.isCritical) { body += " — includes an important update" }
        let review = total == 1 ? "Review it in Spruce." : "Review them in Spruce."
        body += body.isEmpty ? review : ". " + review
        return (title, body)
    }
}

// MARK: - Apps moved to the Trash

/// An app the user moved to the Trash, remembered so its leftover files can be offered for
/// removal — also after the Trash is emptied.
public struct ApplicationsRemovedApp: Codable, Sendable, Hashable, Identifiable {
    public var id: String { bundleID.lowercased() }
    public var bundleID: String
    public var name: String
    /// Where the bundle is (or was) in the Trash.
    public var trashedPath: String
    public var removedAt: Date
    /// What identifies the app's files (names, team, app groups, helpers).
    public var identity: ApplicationsAppIdentity

    public init(bundleID: String, name: String, trashedPath: String, removedAt: Date = Date(), identity: ApplicationsAppIdentity) {
        self.bundleID = bundleID
        self.name = name
        self.trashedPath = trashedPath
        self.removedAt = removedAt
        self.identity = identity
    }
}

/// The list of recently removed apps (persisted by the Mac engine).
public struct ApplicationsRemovedAppLog: Codable, Sendable, Equatable {
    /// How long a removed app is remembered.
    public static let maxAge: TimeInterval = 30 * 86_400
    public static let maxApps = 50

    public var apps: [ApplicationsRemovedApp]

    public init(apps: [ApplicationsRemovedApp] = []) { self.apps = apps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = (try? c.decodeIfPresent([ApplicationsRemovedApp].self, forKey: .apps)) ?? nil ?? []
    }

    private enum CodingKeys: String, CodingKey { case apps }

    /// Adds or replaces the app (one entry per bundle id), newest first.
    public mutating func record(_ app: ApplicationsRemovedApp) {
        apps.removeAll { $0.id == app.id }
        apps.insert(app, at: 0)
        if apps.count > Self.maxApps { apps.removeLast(apps.count - Self.maxApps) }
    }

    public mutating func remove(bundleID: String) {
        apps.removeAll { $0.id == bundleID.lowercased() }
    }

    /// Drops entries that are too old or whose app is installed again.
    public mutating func prune(now: Date = Date(), installedBundleIDs: Set<String>) {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        let installed = Set(installedBundleIDs.map { $0.lowercased() })
        apps.removeAll { $0.removedAt < cutoff || installed.contains($0.id) }
    }
}

/// Decides whether an app that appeared in the Trash deserves a "Finish removing?" offer.
public enum ApplicationsTrashedAppRules {
    /// Below this, leftovers are not worth an alert (unless a launch job keeps trying to run).
    public static let minimumBytes: Int64 = 1_000_000

    /// Why no offer is made, or nil when one is.
    public enum Skip: String, Sendable, Equatable {
        case noBundleID, apple, spruce, ignored, removedBySpruce, stillInstalled, running, nothingLeft
    }

    public static func skipReason(bundleID: String, ownBundleID: String?, ignoredBundleIDs: [String],
                                  removedBySpruce: Bool, installedElsewhere: Bool, isRunning: Bool) -> Skip? {
        let lower = bundleID.lowercased()
        if lower.isEmpty { return .noBundleID }
        if lower.hasPrefix("com.apple.") { return .apple }
        if let own = ownBundleID?.lowercased(), !own.isEmpty, lower == own || lower.hasPrefix(own + ".") { return .spruce }
        if ignoredBundleIDs.contains(where: { $0.lowercased() == lower }) { return .ignored }
        if removedBySpruce { return .removedBySpruce }
        if installedElsewhere { return .stillInstalled }
        if isRunning { return .running }
        return nil
    }

    /// True when the leftovers are worth offering.
    public static func isWorthOffering(bytes: Int64, count: Int, hasLaunchItem: Bool) -> Bool {
        guard count > 0 else { return false }
        return bytes >= minimumBytes || hasLaunchItem
    }

    /// Notification text for an app's leftovers.
    public static func message(appName: String, count: Int, bytes: Int64) -> (title: String, body: String) {
        let title = "Finish removing \u{201C}\(appName)\u{201D}?"
        let body = "\(appName) left \(CountFormat.items(count)) (\(ByteFormat.string(bytes))) behind. Review them in Spruce and move them to the Trash too."
        return (title, body)
    }

    /// Notification identifier for one app (the same app replaces its earlier alert).
    public static func notificationID(bundleID: String) -> String { "app.spruce.trashed." + bundleID.lowercased() }

    /// True when `path` lies in a Trash folder (the user's, or a volume's `.Trashes`).
    public static func isInTrash(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let lower = (path as NSString).standardizingPath.lowercased()
        let userTrash = ((home as NSString).appendingPathComponent(".Trash") as NSString).standardizingPath.lowercased()
        if lower.hasPrefix(userTrash + "/") { return true }
        let parts = lower.split(separator: "/")
        return parts.count > 3 && parts[0] == "volumes" && parts[2] == ".trashes"
    }

    /// Top-level `.app` bundles that are in `current` but were not in `previous`.
    public static func newBundles(previous: Set<String>, current: [String]) -> [String] {
        current.filter { $0.lowercased().hasSuffix(".app") && !previous.contains($0) }
    }
}

/// Review groups for the leftovers of apps the user moved to the Trash.
public enum ApplicationsRemovedAppPlan {
    public static let groupPrefix = ApplicationsOrphanPlan.rootGroupID + ".removed."

    /// Kinds that can hold the user's own data (documents in a sandbox container, databases
    /// in Application Support): listed, never pre-selected.
    public static let userDataKinds: Set<ApplicationsComponentKind> = [.applicationSupport, .containers, .other]

    /// One group per app, newest removal first. Settings, caches, logs and helpers that clearly
    /// belong to the app (strong match, not shared with an installed app, movable without
    /// administrator rights) are pre-selected — the user already chose to remove the app.
    /// Data folders and everything less certain stay unticked.
    public static func groups(_ apps: [(app: ApplicationsRemovedApp, candidates: [ApplicationsLeftoverCandidate], inTrash: Bool)],
                              now: Date = Date(),
                              measure: (String) -> ApplicationsMeasured = ApplicationsMeasured.measure) -> [ScanGroup] {
        var groups: [ScanGroup] = []
        for entry in apps.sorted(by: { $0.app.removedAt > $1.app.removedAt }) {
            let items: [ScanItem] = entry.candidates.map { candidate in
                let measured = measure(candidate.path)
                var meta: [String: String] = [
                    ApplicationsMeta.kind: candidate.kind.rawValue,
                    ApplicationsMeta.ownerKey: entry.app.bundleID,
                    ApplicationsMeta.removedApp: entry.app.bundleID,
                    ApplicationsMeta.systemDomain: candidate.isSystemDomain ? "1" : "0",
                ]
                if let inode = measured.inode { meta[ApplicationsMeta.inode] = String(inode) }
                let keepsData = userDataKinds.contains(candidate.kind)
                let safety: SafetyLevel = candidate.safety == .safe && !keepsData ? .safe : .review
                let note = keepsData && candidate.safety == .safe
                    ? candidate.note + " It may hold your own data, so it isn't selected."
                    : candidate.note
                return ScanItem.file(URL(fileURLWithPath: candidate.path), size: measured.bytes, itemCount: measured.files,
                                     safety: safety, note: note, metadata: meta)
            }
            guard !items.isEmpty else { continue }
            let when = DurationFormat.relative(entry.app.removedAt, now: now)
            let detail = entry.inTrash
                ? "You moved \(entry.app.name) to the Trash \(when). Its settings, caches and logs are selected; data folders aren't, in case you want to keep something."
                : "You removed \(entry.app.name) \(when). Its settings, caches and logs are selected; data folders aren't, in case you want to keep something."
            groups.append(ScanGroup(id: groupPrefix + entry.app.id, title: entry.app.name, detail: detail, symbol: "trash.square",
                                    safety: items.allSatisfy { $0.safety == .safe } ? .safe : .review,
                                    items: items.sorted { $0.size > $1.size }))
        }
        return groups
    }

    /// Removes items already listed in `covered` (paths) from orphan groups, dropping empty groups.
    public static func excluding(_ covered: Set<String>, from groups: [ScanGroup]) -> [ScanGroup] {
        guard !covered.isEmpty else { return groups }
        let keys = Set(covered.map { ($0 as NSString).standardizingPath.lowercased() })
        return groups.compactMap { group in
            var g = group
            g.items = g.items.filter { item in
                guard let path = item.url?.path else { return true }
                return !keys.contains((path as NSString).standardizingPath.lowercased())
            }
            return g.items.isEmpty && g.children.isEmpty ? nil : g
        }
    }
}
