import AppKit
import Darwin
import Foundation
import SQLite3
import SpruceCore

/// Gathers the machine facts the Cleanup scanner needs: running apps and tools,
/// per-user Darwin folders, mounted drives, Mail accounts, permissions.
enum CleanupSystemProbe {

    static func makeContext(purpose: CleanupScanPurpose, includeMailAccounts: Bool = true) async -> CleanupContext {
        let running = await runningBundleIDs()
        let quittable = await quittableBundleIDs()
        let processes = await runningProcessNames()
        let fullDiskAccess = Permissions.hasFullDiskAccess
        let home = NSHomeDirectory()
        let mail = includeMailAccounts && fullDiskAccess ? CleanupMailAccounts.load(home: home) : [:]
        let tempDir = darwinDirectory(_CS_DARWIN_USER_TEMP_DIR) ?? CleanupPaths.realPath(NSTemporaryDirectory())
        var cacheDir = darwinDirectory(_CS_DARWIN_USER_CACHE_DIR)
        if cacheDir == nil, tempDir.hasSuffix("/T") {
            cacheDir = String(tempDir.dropLast()) + "C"
        }
        return CleanupContext(
            home: home,
            systemRoot: "",
            uid: UInt32(getuid()),
            userTempDir: tempDir,
            userCacheDir: cacheDir,
            startupVolumeName: startupVolumeName(),
            externalVolumes: externalVolumes(),
            runningBundleIDs: running,
            quittableBundleIDs: quittable,
            runningProcessNames: processes,
            hasFullDiskAccess: fullDiskAccess,
            ownBundleID: Bundle.main.bundleIdentifier,
            mailAccounts: mail,
            appName: { CleanupAppNames.shared.name(for: $0) },
            now: Date(),
            purpose: purpose
        )
    }

    /// Bundle identifiers of running apps (read on the main actor, where NSWorkspace
    /// keeps the list current).
    static func runningBundleIDs() async -> Set<String> {
        await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
    }

    /// Bundle identifiers of `CleanupRunningApps.quittable()`.
    static func quittableBundleIDs() async -> Set<String> {
        await MainActor.run { Set(CleanupRunningApps.quittable().compactMap(\.bundleIdentifier)) }
    }

    /// Executable names of all processes (Xcode build tools and simulators have no
    /// bundle identifier in the running-apps list).
    static func runningProcessNames() async -> Set<String> {
        let result = await Shell.run("/bin/ps", ["-axco", "comm="], timeout: 5)
        guard result.status == 0 else { return [] }
        return Set(result.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// `confstr(_CS_DARWIN_USER_TEMP_DIR / _CS_DARWIN_USER_CACHE_DIR)`, symlinks resolved.
    static func darwinDirectory(_ name: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = confstr(name, &buffer, buffer.count)
        guard length > 0, length <= buffer.count else { return nil }
        let path = buffer.withUnsafeBufferPointer { pointer -> String in
            guard let base = pointer.baseAddress else { return "" }
            return String(cString: base)
        }
        guard !path.isEmpty else { return nil }
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed.removeLast() }
        return CleanupPaths.realPath(trimmed)
    }

    static func startupVolumeName() -> String {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName ?? "Macintosh HD"
    }

    /// Writable, local volumes mounted under /Volumes (USB disks, external SSDs).
    static func externalVolumes() -> [CleanupVolume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                                options: [.skipHiddenVolumes]) else { return [] }
        return urls.compactMap { url -> CleanupVolume? in
            let path = url.standardizedFileURL.path
            guard path.hasPrefix("/Volumes/"), let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            if values.volumeIsRootFileSystem == true || values.volumeIsReadOnly == true || values.volumeIsLocal == false {
                return nil
            }
            return CleanupVolume(path: path, name: values.volumeName ?? url.lastPathComponent)
        }
    }
}

/// Resolves bundle identifiers to app names (cached; LaunchServices lookups are slow).
final class CleanupAppNames: @unchecked Sendable {
    static let shared = CleanupAppNames()

    private let lock = NSLock()
    private var names: [String: String] = [:]
    private var misses: Set<String> = []

    func name(for bundleID: String) -> String? {
        lock.lock()
        if let cached = names[bundleID] {
            lock.unlock()
            return cached
        }
        if misses.contains(bundleID) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        var resolved: String?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            resolved = name.isEmpty ? nil : name
        }

        lock.lock()
        if let resolved { names[bundleID] = resolved } else { misses.insert(bundleID) }
        lock.unlock()
        return resolved
    }
}

/// Reads Internet Accounts (`~/Library/Accounts/Accounts4.sqlite`, Full Disk Access) to
/// learn which Mail folders belong to server accounts (IMAP, iCloud, Exchange), whose
/// attachments Mail can download again, and which are POP or local.
enum CleanupMailAccounts {

    static func load(home: String) -> [String: CleanupMailAccount] {
        let path = home + "/Library/Accounts/Accounts4.sqlite"
        guard FileManager.default.isReadableFile(atPath: path) else { return [:] }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        // immutable=1: read without taking locks or touching the live database's WAL.
        let uri = "file:\(encoded)?immutable=1"
        var handle: OpaquePointer?
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let db = handle else {
            sqlite3_close(handle)
            return [:]
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT a.ZIDENTIFIER, t.ZIDENTIFIER, a.ZACCOUNTDESCRIPTION, a.ZUSERNAME \
            FROM ZACCOUNT a LEFT JOIN ZACCOUNTTYPE t ON a.ZACCOUNTTYPE = t.Z_PK
            """
        var statementHandle: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statementHandle, nil) == SQLITE_OK, let statement = statementHandle else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var accounts: [String: CleanupMailAccount] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let identifier = text(statement, 0) else { continue }
            let type = text(statement, 1) ?? ""
            let name = text(statement, 2) ?? text(statement, 3) ?? "Mail account"
            accounts[identifier] = CleanupMailAccount(name: name, kind: kind(forAccountType: type))
        }
        return accounts
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        let value = String(cString: pointer)
        return value.isEmpty ? nil : value
    }

    static func kind(forAccountType type: String) -> CleanupMailAccount.Kind {
        let t = type.lowercased()
        if t.contains("pop") { return .pop }
        let server = ["imap", "exchange", "google", "yahoo", "aol", "icloud", "mobileme", "appleaccount", "outlook", "hotmail"]
        if server.contains(where: { t.contains($0) }) { return .server }
        if t.contains("onmymac") || t.contains("local") { return .local }
        return .unknown
    }
}

/// The open apps Cleanup can ask to quit before cleaning their caches.
public enum CleanupRunningApps {
    /// Running apps a quit sheet can show and quit: regular apps, and menu bar apps that
    /// aren't part of macOS (launchd restarts Apple's own agents right after they quit).
    /// Never background-only processes, and never Spruce itself.
    @MainActor
    public static func quittable() -> [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard !app.isTerminated, app.processIdentifier != ownPID, let id = app.bundleIdentifier else { return false }
            switch app.activationPolicy {
            case .regular: return true
            case .accessory: return !id.lowercased().hasPrefix("com.apple.")
            default: return false
            }
        }
    }
}
