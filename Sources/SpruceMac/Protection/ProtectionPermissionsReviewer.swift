import AppKit
import Foundation
import SpruceCore

/// Summary of the last permissions read.
public struct ProtectionPermissionsReport: Sendable, Equatable {
    public var date: Date
    /// TCC databases that could be read.
    public var readDatabases: [ProtectionTCCDatabase]
    /// True when macOS blocked reading the permission databases (no Full Disk Access).
    public var needsFullDiskAccess: Bool
    /// Number of (app, permission) grants listed.
    public var grantCount: Int
    /// Number of distinct apps holding at least one permission.
    public var appCount: Int
    /// Grants whose app is no longer installed.
    public var leftoverCount: Int

    public init(date: Date = Date(), readDatabases: [ProtectionTCCDatabase], needsFullDiskAccess: Bool, grantCount: Int,
                appCount: Int, leftoverCount: Int) {
        self.date = date
        self.readDatabases = readDatabases
        self.needsFullDiskAccess = needsFullDiskAccess
        self.grantCount = grantCount
        self.appCount = appCount
        self.leftoverCount = leftoverCount
    }
}

/// Lists which apps hold macOS privacy permissions and resets selected ones.
///
/// The TCC databases are only ever read (`sqlite3 -readonly`); TCC.db is never written.
/// A reset uses Apple's `tccutil reset <Service> <bundle id>`, so the app asks again the next
/// time it needs access. Granting goes through System Settings (deep links per service).
public final class ProtectionPermissionsReviewer: GroupScanner, @unchecked Sendable {
    private let state = ProtectionLocked<ProtectionPermissionsReport?>(nil)

    public init() {}

    public var lastReport: ProtectionPermissionsReport? { state.current }

    public static var userDatabase: String {
        NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
    }

    public static let systemDatabase = "/Library/Application Support/com.apple.TCC/TCC.db"

    /// Opens System Settings › Privacy & Security at the item's permission.
    public static func openSettings(for item: ScanItem) {
        let link = item.metadata[ProtectionPermissionMetaKey.settingsURL]
            ?? "x-apple.systempreferences:com.apple.preference.security?Privacy"
        openSettings(link: link)
    }

    public static func openSettings(link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: GroupScanner

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        progress(ScanProgress(fraction: 0.1, message: "Reading privacy permissions…"))
        var grants: [ProtectionTCCGrant] = []
        var read: [ProtectionTCCDatabase] = []
        var blocked = false
        let databases: [(String, ProtectionTCCDatabase)] = [(Self.userDatabase, .user), (Self.systemDatabase, .system)]
        for (index, (path, database)) in databases.enumerated() {
            if Task.isCancelled { throw SpruceError.cancelled }
            progress(ScanProgress(fraction: 0.1 + 0.3 * Double(index), message: "Reading privacy permissions…",
                                  current: path.abbreviatingHome))
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let result = await Shell.run("/usr/bin/sqlite3", ["-readonly", "-json", path, ProtectionTCCParser.query],
                                         timeout: 20)
            if result.status == 0 {
                grants += ProtectionTCCParser.parse(json: result.stdout, database: database)
                read.append(database)
            } else if ProtectionTCCParser.isAccessDenied(result.stderr) || database == .user {
                blocked = true
            }
        }
        if Task.isCancelled { throw SpruceError.cancelled }
        progress(ScanProgress(fraction: 0.8, message: "Matching permissions to apps…"))

        var cache: [String: ProtectionPermissionClient] = [:]
        let groups = ProtectionPermissionGroup.scanGroups(grants) { grant in
            let key = "\(grant.clientType)|\(grant.client)"
            if let known = cache[key] { return known }
            let resolved = Self.resolve(grant)
            cache[key] = resolved
            return resolved
        }
        let items = groups.allItems
        let apps = Set(items.compactMap { $0.metadata[ProtectionPermissionMetaKey.client] })
        state.current = ProtectionPermissionsReport(
            readDatabases: read,
            needsFullDiskAccess: read.isEmpty && blocked,
            grantCount: items.count,
            appCount: apps.count,
            leftoverCount: items.filter { $0.metadata[ProtectionPermissionMetaKey.missing] == "1" }.count
        )
        progress(ScanProgress(fraction: 1, message: "Done"))
        return groups
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let plans = items.compactMap(ProtectionPermissionPlan.init(item:))
        var removed: [String] = []
        var failures: [ItemFailure] = []
        for (index, plan) in plans.enumerated() {
            if Task.isCancelled { break }
            progress(ScanProgress(fraction: Double(index) / Double(max(plans.count, 1)),
                                  message: "Resetting \(plan.title)…", current: plan.client))
            guard let arguments = plan.resetArguments else {
                failures.append(ItemFailure(itemID: plan.itemID, title: plan.title,
                                            reason: "macOS only lets you change this permission in System Settings › Privacy & Security."))
                continue
            }
            let result = await Shell.run("/usr/bin/tccutil", arguments, timeout: 20)
            if result.status == 0 {
                removed.append(plan.itemID)
                OperationLog.shared.record(module: .protection, action: "tccutil-reset", result: "ok",
                                           detail: arguments.dropFirst().joined(separator: " "))
            } else {
                OperationLog.shared.record(module: .protection, action: "tccutil-reset", result: "error",
                                           detail: arguments.dropFirst().joined(separator: " "))
                let reason = ProtectionMac.message(from: result, fallback: "macOS refused to reset it.")
                failures.append(ItemFailure(itemID: plan.itemID, title: plan.title,
                                            reason: "\(reason) You can turn it off in System Settings instead."))
            }
        }
        progress(ScanProgress(fraction: 1, message: "Done"))
        let summary = removed.isEmpty
            ? "No permissions were reset"
            : "Reset \(CountFormat.items(removed.count, singular: "permission")). Those apps will ask again when they need access."
        return RunOutcome(module: .protection, processedCount: removed.count, removedItemIDs: removed, failures: failures,
                          summary: summary)
    }

    // MARK: Client resolution

    /// Finds the app behind a grant (bundle id via Launch Services, or an executable path).
    static func resolve(_ grant: ProtectionTCCGrant) -> ProtectionPermissionClient {
        if grant.isBundleClient {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: grant.client) {
                return ProtectionPermissionClient(displayName: displayName(of: url), appPath: url.path, isMissing: false)
            }
            // Apple's own clients are system components, not removable apps.
            return ProtectionPermissionClient(displayName: grant.client, appPath: nil,
                                              isMissing: !grant.client.lowercased().hasPrefix("com.apple."))
        }
        let exists = FileManager.default.fileExists(atPath: grant.client)
        var name = (grant.client as NSString).lastPathComponent
        if let range = grant.client.range(of: ".app/", options: .caseInsensitive) {
            let bundle = String(grant.client[..<range.lowerBound]) + ".app"
            name = displayName(of: URL(fileURLWithPath: bundle))
            return ProtectionPermissionClient(displayName: name, appPath: exists ? bundle : nil, isMissing: !exists)
        }
        return ProtectionPermissionClient(displayName: name, appPath: exists ? grant.client : nil, isMissing: !exists)
    }

    private static func displayName(of url: URL) -> String {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        return name.isEmpty ? url.deletingPathExtension().lastPathComponent : name
    }
}
