import Foundation
import SpruceCore

/// Shredder: overwrites the chosen files with zeros, then removes them for good.
///
/// For each chosen item:
/// 1. re-plan it (`ToolboxShredPlan.make`: PathGuard, no app bundles, no hard links,
///    write access) right before acting;
/// 2. overwrite every regular file with zeros in 1 MB chunks and flush it to the drive;
/// 3. rename the item to a random name (so the original name doesn't linger);
/// 4. move it to the Trash with `FileRemover.dispose` (`.trash`);
/// 5. remove the trashed copy with `FileRemover.dispose` (`.remove`, a Trash zone).
///
/// On SSDs and APFS, overwriting can't guarantee the old blocks are physically erased
/// (wear levelling, copy-on-write clones, local snapshots). The UI says so.
public final class ToolboxShredder: @unchecked Sendable {
    public static let chunkSize = 1 << 20
    /// `SF_DATALESS`: the file's contents live only in the cloud.
    private static let datalessFlag: UInt32 = 0x4000_0000

    private let remover: FileRemover
    private let guardian: PathGuard
    private let log: OperationLog

    public init(remover: FileRemover = .shared, guardian: PathGuard = PathGuard(), log: OperationLog = .shared) {
        self.remover = remover
        self.guardian = guardian
        self.log = log
    }

    // MARK: Planning

    /// Validates and measures the chosen items (off the main thread). Items inside
    /// another chosen folder are dropped, since shredding the folder covers them.
    public func plan(_ urls: [URL], settings: SpruceSettings? = nil) async -> [ToolboxShredPlan] {
        let guardian = self.guardian
        return await Task.detached(priority: .userInitiated) { () -> [ToolboxShredPlan] in
            var seen = Set<String>()
            var plans: [ToolboxShredPlan] = []
            for url in urls {
                var path = url.path
                while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
                guard !path.isEmpty, seen.insert(path.lowercased()).inserted else { continue }
                var plan = ToolboxShredPlan.make(root: path, guardian: guardian)
                if plan.problem == nil, let settings, settings.isIgnored(path: path) {
                    plan.problem = "It's on your ignore list. Remove it from the list in Settings to shred it."
                }
                plans.append(plan)
            }
            let folders = plans.filter(\.isDirectory).map { $0.root.lowercased() }
            return plans.filter { plan in
                let key = plan.root.lowercased()
                return !folders.contains { key != $0 && key.hasPrefix($0 + "/") }
            }
        }.value
    }

    // MARK: Shredding

    /// Shreds the items that can be shredded. Never throws; each failure is reported
    /// per item. Cancelling stops before the next file chunk.
    public func shred(_ plans: [ToolboxShredPlan], settings: SpruceSettings? = nil,
                      progress: @escaping ProgressHandler) async -> RunOutcome {
        let targets = plans.filter(\.canShred)
        let totalBytes = max(1, targets.reduce(Int64(0)) { $0 + $1.logicalBytes })
        var written: Int64 = 0
        var freed: Int64 = 0
        var removed: [String] = []
        var failures: [ItemFailure] = []
        var stillInTrash = 0

        for chosen in targets {
            if Task.isCancelled {
                failures.append(ItemFailure(itemID: chosen.id, title: chosen.name, reason: "Not shredded — you stopped the Shredder"))
                continue
            }
            // Re-check right before acting: the item may have changed since it was chosen.
            let plan = ToolboxShredPlan.make(root: chosen.root, guardian: guardian)
            if let problem = plan.problem {
                failures.append(ItemFailure(itemID: chosen.id, title: chosen.name, reason: problem))
                continue
            }
            if let settings, settings.isIgnored(path: plan.root) {
                failures.append(ItemFailure(itemID: chosen.id, title: chosen.name, reason: "On the ignore list"))
                continue
            }

            // 1. Overwrite.
            var overwriteError: String?
            for file in plan.files {
                do {
                    try overwrite(file, written: &written, total: totalBytes, title: plan.name, progress: progress)
                } catch SpruceError.cancelled {
                    overwriteError = "Stopped while overwriting. Some of its files are already overwritten; it was left in place."
                    break
                } catch {
                    overwriteError = "Couldn't overwrite \u{201C}\((file.path as NSString).lastPathComponent)\u{201D}: \(error.localizedDescription)"
                    break
                }
            }
            if let overwriteError {
                failures.append(ItemFailure(itemID: chosen.id, title: chosen.name, reason: overwriteError))
                log.record(module: .toolbox, action: "shred", result: "error", detail: "\(plan.root) — \(overwriteError)")
                continue
            }
            log.record(module: .toolbox, action: "overwrite", result: "ok", bytes: plan.logicalBytes, detail: plan.root)

            // 2. Rename, trash, then remove the trashed copy.
            progress(ScanProgress(fraction: Double(written) / Double(totalBytes), message: "Removing \(plan.name)…",
                                  current: plan.root.abbreviatingHome, bytesFound: freed))
            switch await dispose(plan) {
            case .removed:
                freed += plan.allocatedBytes
                removed.append(chosen.id)
            case .inTrash:
                stillInTrash += 1
                removed.append(chosen.id)
                failures.append(ItemFailure(itemID: chosen.id, title: chosen.name,
                                            reason: "Overwritten and moved to the Trash. Empty the Trash to finish."))
            case .failed(let reason):
                failures.append(ItemFailure(itemID: chosen.id, title: chosen.name,
                                            reason: "Overwritten, but not removed: \(reason)"))
            }
        }

        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: freed))
        let done = removed.count - stillInTrash
        var summary: String
        if done > 0 {
            summary = "Shredded \(CountFormat.items(done)) · \(ByteFormat.string(freed))"
            if stillInTrash > 0 { summary += " · \(CountFormat.items(stillInTrash)) left in the Trash" }
        } else if stillInTrash > 0 {
            summary = "Overwrote \(CountFormat.items(stillInTrash)); empty the Trash to finish"
        } else {
            summary = "Nothing was shredded"
        }
        return RunOutcome(module: .toolbox, freedBytes: freed, processedCount: removed.count, removedItemIDs: removed,
                          failures: failures, summary: summary)
    }

    // MARK: Steps

    private enum DisposeResult {
        case removed
        case inTrash
        case failed(String)
    }

    private func dispose(_ plan: ToolboxShredPlan) async -> DisposeResult {
        let fm = FileManager.default
        let original = URL(fileURLWithPath: plan.root)
        let parent = original.deletingLastPathComponent()

        // Scrub the name: rename to a random one in the same folder.
        var scrubbed = parent.appendingPathComponent("Shredded-\(UUID().uuidString)")
        while FileWalker.entry(at: scrubbed.path) != nil {
            scrubbed = parent.appendingPathComponent("Shredded-\(UUID().uuidString)")
        }
        do {
            try fm.moveItem(at: original, to: scrubbed)
        } catch {
            // Fall back to trashing under the original name.
            scrubbed = original
        }
        let trashDirectory = try? fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: scrubbed, create: false)

        let toTrash = ScanItem.file(scrubbed, size: plan.allocatedBytes, itemCount: max(1, plan.itemCount),
                                    safety: .review, deletion: .trash, title: plan.name)
        let trashed = await remover.dispose([toTrash], module: .toolbox)
        guard trashed.removedItemIDs.contains(toTrash.id) else {
            return .failed(trashed.failures.first?.reason ?? "It couldn't be moved to the Trash.")
        }

        guard let trashDirectory else { return .inTrash }
        let inTrash = trashDirectory.appendingPathComponent(scrubbed.lastPathComponent)
        guard FileWalker.entry(at: inTrash.path) != nil else { return .inTrash }

        // Permanent removal is allowed in the home Trash; other volumes' Trash folders
        // are added as a zone just for this call.
        let homeTrash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash").standardizedFileURL.path
        let zone = trashDirectory.standardizedFileURL.path
        let finalRemover = zone.lowercased() == homeTrash.lowercased()
            ? remover
            : FileRemover(guardian: PathGuard(extraPermanentZones: [zone]), log: log)
        let item = ScanItem.file(inTrash, size: plan.allocatedBytes, itemCount: max(1, plan.itemCount),
                                 safety: .safe, deletion: .remove, title: plan.name)
        let outcome = await finalRemover.dispose([item], module: .toolbox)
        if outcome.removedItemIDs.contains(item.id) && FileWalker.entry(at: inTrash.path) == nil {
            return .removed
        }
        return .inTrash
    }

    /// Overwrites one regular file with zeros, in place, and flushes it to the drive.
    private func overwrite(_ file: ToolboxShredFile, written: inout Int64, total: Int64, title: String,
                           progress: ProgressHandler) throws {
        var st = stat()
        guard lstat(file.path, &st) == 0 else { throw SpruceError.notFound(file.path.abbreviatingHome) }
        guard UInt32(st.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG), UInt64(st.st_ino) == file.inode else {
            throw SpruceError.commandFailed("it changed since it was chosen")
        }
        if UInt32(st.st_flags) & Self.datalessFlag != 0 {
            throw SpruceError.unsupported("its contents are stored in the cloud, not on this Mac")
        }

        let fd = open(file.path, O_WRONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Self.posixError(errno) }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0,
              UInt32(opened.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG),
              UInt64(opened.st_ino) == file.inode,
              opened.st_nlink == 1 else {
            throw SpruceError.commandFailed("it changed since it was chosen")
        }

        let size = Int64(opened.st_size)
        let zeros = [UInt8](repeating: 0, count: Self.chunkSize)
        var offset: Int64 = 0
        var lastReport: Int64 = 0
        let name = (file.path as NSString).lastPathComponent
        while offset < size {
            if Task.isCancelled { throw SpruceError.cancelled }
            let length = Int(min(Int64(Self.chunkSize), size - offset))
            let count = zeros.withUnsafeBytes { buffer in
                pwrite(fd, buffer.baseAddress, length, off_t(offset))
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw Self.posixError(errno)
            }
            if count == 0 { throw SpruceError.commandFailed("the disk stopped accepting data") }
            offset += Int64(count)
            written += Int64(count)
            if written - lastReport >= 8 * Int64(Self.chunkSize) || offset >= size {
                lastReport = written
                progress(ScanProgress(fraction: Double(written) / Double(total), message: "Overwriting \(title)…",
                                      current: name))
            }
        }
        // Push the zeros past the drive's cache, not just the OS cache.
        if fcntl(fd, F_FULLFSYNC) != 0 {
            _ = fsync(fd)
        }
    }

    private static func posixError(_ code: Int32) -> SpruceError {
        if code == EACCES || code == EPERM { return .permissionDenied("not allowed to write to it") }
        return .commandFailed(String(cString: strerror(code)))
    }
}

// MARK: - Trash inspection

/// One top-level item in the Trash.
public struct ToolboxTrashEntry: Identifiable, Sendable, Equatable {
    public var path: String
    public var id: String { path }
    public var name: String
    public var bytes: Int64
    public var isDirectory: Bool

    public init(path: String, name: String, bytes: Int64, isDirectory: Bool) {
        self.path = path
        self.name = name
        self.bytes = bytes
        self.isDirectory = isDirectory
    }
}

/// What's in the user's Trash right now.
public struct ToolboxTrashSummary: Sendable, Equatable {
    public var bytes: Int64
    /// Top-level items.
    public var itemCount: Int
    /// Files inside them.
    public var fileCount: Int
    /// Largest first.
    public var largest: [ToolboxTrashEntry]
    /// True when the Trash can't be listed without Full Disk Access.
    public var needsAccess: Bool

    public init(bytes: Int64 = 0, itemCount: Int = 0, fileCount: Int = 0, largest: [ToolboxTrashEntry] = [],
                needsAccess: Bool = false) {
        self.bytes = bytes
        self.itemCount = itemCount
        self.fileCount = fileCount
        self.largest = largest
        self.needsAccess = needsAccess
    }

    public var isEmpty: Bool { itemCount == 0 && !needsAccess }
}

public enum ToolboxTrash {
    /// The startup disk's Trash for the current user.
    public static var url: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash") }

    /// Measures the Trash off the main thread.
    public static func measure(limit: Int = 8) async -> ToolboxTrashSummary {
        await Task.detached(priority: .userInitiated) { ToolboxTrash.measureNow(limit: limit) }.value
    }

    static func measureNow(limit: Int) -> ToolboxTrashSummary {
        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        } catch {
            let ns = error as NSError
            let missing = ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError
            return ToolboxTrashSummary(needsAccess: !missing)
        }
        var entries: [ToolboxTrashEntry] = []
        var files = 0
        for item in contents where item.lastPathComponent != ".DS_Store" && item.lastPathComponent != ".localized" {
            let usage = DiskUsage.measure(item.path)
            files += max(1, usage.fileCount)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            entries.append(ToolboxTrashEntry(path: item.path, name: fm.displayName(atPath: item.path),
                                             bytes: usage.bytes, isDirectory: isDir == true))
        }
        let total = entries.reduce(Int64(0)) { $0 + $1.bytes }
        let largest = Array(entries.sorted { $0.bytes > $1.bytes }.prefix(max(0, limit)))
        return ToolboxTrashSummary(bytes: total, itemCount: entries.count, fileCount: files, largest: largest)
    }
}
