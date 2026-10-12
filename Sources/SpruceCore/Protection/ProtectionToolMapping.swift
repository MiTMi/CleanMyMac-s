import Foundation

// Turns the Protection scanners' results into reviewable `ScanGroup`s (Privacy, App
// Permissions), builds the Checkup tile, diffs launch folders for real-time protection and
// parses XProtect's version output. Foundation-only so all of it is unit-tested on Linux.

// MARK: - Privacy review groups

public enum ProtectionPrivacyGroup {
    /// Group ids are "protection.privacy.<source id>".
    public static let prefix = "protection.privacy."

    public static func groupID(sourceID: String) -> String { prefix + sourceID }

    /// The source id of a privacy review group, or nil for other groups.
    public static func sourceID(groupID: String) -> String? {
        guard groupID.hasPrefix(prefix) else { return nil }
        return String(groupID.dropFirst(prefix.count))
    }
}

public extension ProtectionTraceSource {
    /// SF Symbol for the source's review group.
    var symbol: String {
        guard let browser else { return "desktopcomputer" }
        switch browser.id {
        case .safari: return "safari"
        case .firefox: return "flame"
        default: return "globe"
        }
    }

    /// The review group of this source (one browser or macOS); nil when nothing is cleanable.
    /// Items of a browser that is open are tagged so cleaning can ask to quit it first.
    func scanGroup(isRunning: Bool) -> ScanGroup? {
        guard !traces.isEmpty else { return nil }
        let order = ProtectionTraceKind.allCases
        let items = traces
            .sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
            .map { trace -> ScanItem in
                var item = trace.scanItem
                if isRunning { item.metadata[ProtectionPrivacyMetaKey.running] = "1" }
                return item
            }
        var detail: String
        if browser == nil {
            detail = "Lists and logs macOS keeps of what you opened, previewed and downloaded. The files themselves stay."
        } else if isRunning {
            detail = "\(title) is open. Spruce will ask to quit it before cleaning, so it can't write the data back."
        } else {
            detail = "What \(title) keeps on this Mac about your browsing. Bookmarks and saved passwords are never touched."
        }
        if browser != nil && profiles.count > 1 {
            detail += " Profiles: " + profiles.joined(separator: ", ") + "."
        }
        let safety: SafetyLevel = traces.allSatisfy { $0.safety == .safe } ? .safe : .review
        return ScanGroup(id: ProtectionPrivacyGroup.groupID(sourceID: id), title: title, detail: detail, symbol: symbol,
                         safety: safety, items: items)
    }
}

public extension ScanItem {
    /// True when this privacy item belongs to a browser that was open at scan time.
    var protectionBrowserWasRunning: Bool { metadata[ProtectionPrivacyMetaKey.running] == "1" }
}

// MARK: - App Permissions review groups

/// Metadata keys of App Permissions items.
public enum ProtectionPermissionMetaKey {
    public static let service = "permission.service"
    public static let tccutil = "permission.tccutil"
    public static let client = "permission.client"
    public static let clientType = "permission.clientType"
    public static let database = "permission.database"
    public static let appPath = "permission.appPath"
    public static let missing = "permission.missing"
    public static let settingsURL = "permission.settingsURL"
    public static let auth = "permission.auth"
    public static let indirect = "permission.indirect"
}

/// How the macOS layer resolved a grant's client (bundle id or path) on this Mac.
public struct ProtectionPermissionClient: Sendable, Hashable {
    public var displayName: String
    /// The app bundle or executable, when it exists.
    public var appPath: String?
    /// The client no longer exists (the app was deleted): the grant is a leftover.
    public var isMissing: Bool

    public init(displayName: String, appPath: String?, isMissing: Bool) {
        self.displayName = displayName
        self.appPath = appPath
        self.isMissing = isMissing
    }
}

public enum ProtectionPermissionGroupID {
    public static let prefix = "protection.permissions."
}

public extension ProtectionTCCGrant {
    /// Bundle ids are the only clients `tccutil reset` accepts.
    static func isValidBundleID(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 255, !text.hasPrefix("."), !text.hasPrefix("-") else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x30 && scalar.value <= 0x39) || (scalar.value >= 0x41 && scalar.value <= 0x5A)
                || (scalar.value >= 0x61 && scalar.value <= 0x7A) || scalar == "." || scalar == "-" || scalar == "_"
        }
    }

    /// True when Spruce can reset this grant with `tccutil reset <Service> <bundle id>`.
    func isResettable(service: ProtectionTCCService) -> Bool {
        isBundleClient && service.tccutilName != nil && Self.isValidBundleID(client)
    }

    /// The reviewable item for this grant. Never pre-selected: resetting a permission makes
    /// the app ask again, which only the user can judge.
    func scanItem(service: ProtectionTCCService, client resolved: ProtectionPermissionClient) -> ScanItem {
        let resettable = isResettable(service: service)
        var subtitle: String
        if let indirectObject {
            subtitle = "Can control \(indirectObject)"
        } else if !isBundleClient {
            subtitle = client.abbreviatingHome
        } else {
            subtitle = auth.label
        }
        if resolved.isMissing { subtitle += " · App not found" }
        let note: String
        if resolved.isMissing {
            note = "This app is no longer on your Mac, so the permission is a leftover. Resetting removes it."
        } else if resettable {
            note = service.detail + " Resetting makes the app ask again the next time it needs this."
        } else {
            note = service.detail + " macOS only lets you change this one in System Settings."
        }
        var metadata: [String: String] = [
            ProtectionMetaKey.tool: ProtectionMetaKey.permissionsTool,
            ProtectionPermissionMetaKey.service: service.id,
            ProtectionPermissionMetaKey.client: client,
            ProtectionPermissionMetaKey.clientType: String(clientType),
            ProtectionPermissionMetaKey.database: database.rawValue,
            ProtectionPermissionMetaKey.settingsURL: service.settingsURLString,
            ProtectionPermissionMetaKey.auth: auth.label,
        ]
        if resettable, let name = service.tccutilName { metadata[ProtectionPermissionMetaKey.tccutil] = name }
        if let path = resolved.appPath { metadata[ProtectionPermissionMetaKey.appPath] = path }
        if resolved.isMissing { metadata[ProtectionPermissionMetaKey.missing] = "1" }
        if let indirectObject { metadata[ProtectionPermissionMetaKey.indirect] = indirectObject }
        return ScanItem(id: "permission|" + id, title: resolved.displayName, subtitle: subtitle, url: nil, size: 0,
                        itemCount: 1, safety: .review, isSelected: false, deletion: .custom, modified: lastModified,
                        symbol: service.symbol, note: note, metadata: metadata)
    }
}

public extension ProtectionPermissionGroup {
    /// Review groups, one per permission (catalog order), listing only apps that currently
    /// hold the permission. Services without such apps are left out.
    static func scanGroups(_ grants: [ProtectionTCCGrant],
                           resolve: (ProtectionTCCGrant) -> ProtectionPermissionClient) -> [ScanGroup] {
        groups(from: grants.filter { $0.auth.isGranted }, includeEmpty: false).compactMap { group in
            let items = group.grants.map { grant in
                grant.scanItem(service: group.service, client: resolve(grant))
            }
            .sorted { lhs, rhs in
                let lm = lhs.metadata[ProtectionPermissionMetaKey.missing] == "1"
                let rm = rhs.metadata[ProtectionPermissionMetaKey.missing] == "1"
                if lm != rm { return lm }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            guard !items.isEmpty else { return nil }
            return ScanGroup(id: ProtectionPermissionGroupID.prefix + group.service.id, title: group.service.title,
                             detail: group.service.detail, symbol: group.service.symbol, safety: .review, items: items)
        }
    }
}

/// What resetting one selected permission involves, decoded from `ScanItem.metadata`.
public struct ProtectionPermissionPlan: Sendable, Equatable {
    public var itemID: String
    public var title: String
    public var serviceID: String
    public var tccutilName: String?
    public var client: String
    public var isBundleClient: Bool
    public var settingsURL: String?

    public init?(item: ScanItem) {
        guard item.metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.permissionsTool,
              let service = item.metadata[ProtectionPermissionMetaKey.service],
              let client = item.metadata[ProtectionPermissionMetaKey.client] else { return nil }
        itemID = item.id
        title = item.title
        serviceID = service
        tccutilName = item.metadata[ProtectionPermissionMetaKey.tccutil]
        self.client = client
        isBundleClient = item.metadata[ProtectionPermissionMetaKey.clientType] == "0"
        settingsURL = item.metadata[ProtectionPermissionMetaKey.settingsURL]
    }

    /// Arguments for `/usr/bin/tccutil`: always one service and one bundle id, never the
    /// bare form that would reset every app. Nil when this grant can't be reset from here.
    public var resetArguments: [String]? {
        guard isBundleClient, let name = tccutilName, !name.isEmpty,
              ProtectionTCCGrant.isValidBundleID(name), ProtectionTCCGrant.isValidBundleID(client) else { return nil }
        return ["reset", name, client]
    }
}

public extension ProtectionTCCParser {
    /// True when sqlite3's error output means macOS blocked reading the database
    /// (Spruce lacks Full Disk Access).
    static func isAccessDenied(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("authorization denied") || lower.contains("unable to open")
            || lower.contains("operation not permitted") || lower.contains("permission denied")
    }
}

// MARK: - Checkup

public enum ProtectionCheckupSummary {
    /// The Protection tile: critical when known threats were found (pre-selected for removal),
    /// attention when only suspicious items need a look, clear otherwise.
    public static func tile(for groups: [ScanGroup], unreadableLocations: Int = 0) -> CheckupTile {
        let all = groups.allItems
        let selected = all.filter(\.isSelected)
        if all.isEmpty {
            let detail = unreadableLocations > 0
                ? "Quick scan found nothing. Some locations need Full Disk Access."
                : "Quick scan found nothing to worry about."
            return CheckupTile(module: .protection, headline: "No threats", detail: detail, status: .clear,
                               isSelected: false)
        }
        let headline = CountFormat.items(all.count, singular: "threat")
        if selected.isEmpty {
            return CheckupTile(module: .protection, headline: headline,
                               detail: "Suspicious, not confirmed. Review before removing.", status: .attention,
                               isSelected: false, reclaimableBytes: 0, actionCount: 0)
        }
        let detail = selected.count == all.count
            ? "Selected for removal. They go to the Trash."
            : "\(CountFormat.grouped(selected.count)) selected for removal, \(CountFormat.grouped(all.count - selected.count)) to review."
        return CheckupTile(module: .protection, headline: headline, detail: detail, status: .critical,
                           isSelected: true, reclaimableBytes: 0, actionCount: selected.count)
    }
}

// MARK: - Real-time protection

public enum ProtectionLaunchWatch {
    /// Startup-item file names that appeared since `previous`: third-party property lists
    /// only (Apple's own jobs and hidden files are ignored).
    public static func addedItems(previous: Set<String>, current: Set<String>) -> [String] {
        current.subtracting(previous).filter { name in
            let lower = name.lowercased()
            return lower.hasSuffix(".plist") && !name.hasPrefix(".") && !lower.hasPrefix("com.apple.")
        }
        .sorted()
    }
}

/// A new startup item noticed by real-time protection.
public struct ProtectionRealtimeEvent: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var date: Date
    public var path: String
    public var label: String?
    public var domain: ProtectionLaunchDomain
    public var kind: ProtectionItemKind
    /// Set when the item matched a known threat or scored as suspicious.
    public var finding: ProtectionThreatFinding?

    public init(id: UUID = UUID(), date: Date = Date(), path: String, label: String?, domain: ProtectionLaunchDomain,
                kind: ProtectionItemKind, finding: ProtectionThreatFinding?) {
        self.id = id
        self.date = date
        self.path = path
        self.label = label
        self.domain = domain
        self.kind = kind
        self.finding = finding
    }

    public var isThreat: Bool { finding != nil }
    public var name: String { label ?? (path as NSString).lastPathComponent }
    public var location: String { (path as NSString).deletingLastPathComponent.abbreviatingHome }

    public var notificationTitle: String {
        guard let finding else { return "New startup item" }
        return finding.isKnownThreat ? "Threat added to startup items" : "Suspicious startup item"
    }

    public var notificationBody: String {
        guard let finding else {
            return "\(name) will now run automatically (\(location)). If you didn't just install something, review it in Spruce."
        }
        let what = finding.family.map { "\($0) (\(finding.category.title.lowercased()))" } ?? finding.category.title
        return "\(name) looks like \(what): \(finding.reason). Open Spruce › Protection to remove it."
    }
}

// MARK: - XProtect

public enum ProtectionXProtectParser {
    /// Parses `xprotect version` (macOS 15+): a "Version: 5297" line and, when present,
    /// an "Installed: 2025-01-28 19:57:47 +0000" line.
    public static func parseVersionCommand(_ output: String) -> (version: String?, installed: Date?) {
        var version: String?
        var installed: Date?
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            guard let colon = line.firstIndex(of: ":") else {
                if version == nil, let range = lower.range(of: "version") {
                    version = firstNumber(in: String(lower[range.upperBound...]))
                }
                continue
            }
            let key = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if version == nil, key.contains("version") {
                version = firstNumber(in: value)
            } else if installed == nil, key.contains("install") || key.contains("date") || key.contains("updated") {
                installed = parseDate(value)
            }
        }
        return (version, installed)
    }

    /// First dotted number in `text` ("5297", "2.1.10").
    static func firstNumber(in text: String) -> String? {
        var current = ""
        for ch in text {
            if ch.isNumber || (ch == "." && !current.isEmpty) {
                current.append(ch)
            } else if !current.isEmpty {
                break
            }
        }
        while current.hasSuffix(".") { current.removeLast() }
        return current.isEmpty ? nil : current
    }

    static func parseDate(_ text: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss ZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZ",
                       "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
