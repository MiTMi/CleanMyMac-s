import AppKit
import Foundation
import SpruceCore

/// Where one item went when Spruce moved it to the Trash.
public struct TrashLedgerEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// One `FileRemover.dispose` call (see `RunOutcome.trashRunIDs`).
    public var runID: UUID
    public var module: ModuleID
    public var date: Date
    public var originalPath: String
    public var trashedPath: String
    public var bytes: Int64
    /// Moved as administrator: it stays root-owned, so Spruce can't put it back.
    public var byAdministrator: Bool

    public init(id: UUID = UUID(), runID: UUID, module: ModuleID, date: Date = Date(), originalPath: String,
                trashedPath: String, bytes: Int64, byAdministrator: Bool = false) {
        self.id = id
        self.runID = runID
        self.module = module
        self.date = date
        self.originalPath = originalPath
        self.trashedPath = trashedPath
        self.bytes = bytes
        self.byAdministrator = byAdministrator
    }
}

/// The result of `TrashLedger.putBack`.
public struct TrashPutBackResult: Sendable, Equatable {
    /// Original paths that were restored.
    public var restored: [String] = []
    public var failures: [ItemFailure] = []

    public var summary: String {
        if restored.isEmpty && failures.isEmpty { return "Nothing to put back" }
        if failures.isEmpty { return "Put back \(CountFormat.items(restored.count))" }
        if restored.isEmpty { return "Couldn't put back \(CountFormat.items(failures.count))" }
        return "Put back \(CountFormat.items(restored.count)); \(CountFormat.items(failures.count)) couldn't be"
    }
}

/// Remembers where `FileRemover` put each trashed item, so a run can be undone
/// ("Put Back") while the items are still in the Trash. Entries older than 60 days,
/// and entries whose item has left the Trash, are pruned.
public final class TrashLedger: @unchecked Sendable {
    public static let shared = TrashLedger(url: SprucePaths.applicationSupport.appendingPathComponent("trash-ledger.json"))
    public static let maxEntries = 5_000
    public static let maxAge: TimeInterval = 60 * 24 * 3600

    private let store: JSONFileStore<[TrashLedgerEntry]>
    private let lock = NSLock()
    private var cache: [TrashLedgerEntry]?

    public init(url: URL) {
        store = JSONFileStore(url: url, prettyPrinted: false)
    }

    /// Adds entries (one save per call; `FileRemover` calls it once per run).
    public func record(_ entries: [TrashLedgerEntry]) {
        guard !entries.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var all = loaded() + entries
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        all.removeAll { $0.date < cutoff }
        if all.count > Self.maxEntries { all.removeFirst(all.count - Self.maxEntries) }
        save(all)
    }

    /// Entries of the given runs whose item is still in the Trash.
    public func entries(runIDs: [UUID]) -> [TrashLedgerEntry] {
        let ids = Set(runIDs)
        guard !ids.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return loaded().filter { ids.contains($0.runID) && FileWalker.entry(at: $0.trashedPath) != nil }
    }

    /// Entries of the given runs that `putBack` can restore.
    public func restorable(runIDs: [UUID]) -> [TrashLedgerEntry] {
        entries(runIDs: runIDs).filter { !$0.byAdministrator && Self.isInTrash($0.trashedPath) }
    }

    /// Moves the items of the given runs back to where they were. An item is restored only
    /// when it is still in the Trash and nothing has taken its original place since.
    public func putBack(runIDs: [UUID], log: OperationLog = .shared) -> TrashPutBackResult {
        var result = TrashPutBackResult()
        let candidates = entries(runIDs: runIDs)
        var done = Set<UUID>()
        let fm = FileManager.default
        for entry in candidates {
            let title = (entry.originalPath as NSString).lastPathComponent
            let itemID = URL(fileURLWithPath: entry.originalPath).standardizedFileURL.path
            if entry.byAdministrator || !Self.isInTrash(entry.trashedPath) {
                result.failures.append(ItemFailure(itemID: itemID, title: title,
                                                   reason: "It was moved as administrator; drag it back from the Trash in Finder."))
                continue
            }
            if FileWalker.entry(at: entry.originalPath) != nil {
                result.failures.append(ItemFailure(itemID: itemID, title: title,
                                                   reason: "Something else is at \(entry.originalPath.abbreviatingHome) now."))
                continue
            }
            let parent = (entry.originalPath as NSString).deletingLastPathComponent
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: parent, isDirectory: &isDir), isDir.boolValue else {
                result.failures.append(ItemFailure(itemID: itemID, title: title,
                                                   reason: "Its original folder \(parent.abbreviatingHome) no longer exists."))
                continue
            }
            do {
                try fm.moveItem(atPath: entry.trashedPath, toPath: entry.originalPath)
                result.restored.append(entry.originalPath)
                done.insert(entry.id)
                log.record(module: entry.module, action: "put-back", result: "ok", bytes: entry.bytes,
                           detail: "\(entry.trashedPath) -> \(entry.originalPath)")
            } catch {
                result.failures.append(ItemFailure(itemID: itemID, title: title, reason: error.localizedDescription))
                log.record(module: entry.module, action: "put-back", result: "error",
                           detail: "\(entry.trashedPath) — \(error.localizedDescription)")
            }
        }
        if !done.isEmpty {
            lock.lock()
            save(loaded().filter { !done.contains($0.id) })
            lock.unlock()
        }
        return result
    }

    /// Opens the Trash in Finder.
    public static func openTrash() {
        let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        NSWorkspace.shared.open(trash)
    }

    /// Only items inside the user's own Trash folders are ever moved back.
    static func isInTrash(_ path: String) -> Bool {
        let key = PathGuard.key((path as NSString).standardizingPath)
        if PathGuard.isStrictlyInside(key, PathGuard.key(NSHomeDirectory() + "/.Trash")) { return true }
        let comps = key.split(separator: "/").map(String.init)
        return comps.count > 4 && comps[0] == "volumes" && comps[2] == ".trashes" && comps[3] == String(getuid())
    }

    // MARK: Private (lock held)

    private func loaded() -> [TrashLedgerEntry] {
        if let cache { return cache }
        let value = store.load() ?? []
        cache = value
        return value
    }

    private func save(_ entries: [TrashLedgerEntry]) {
        cache = entries
        try? store.save(entries)
    }
}
