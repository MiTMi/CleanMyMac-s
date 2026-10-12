import AppKit
import Foundation
import SpruceCore

/// The single place where files leave the disk.
///
/// Every engine hands its selected `ScanItem`s to `FileRemover`, which:
/// 1. re-validates each path with `PathGuard` immediately before acting,
/// 2. honours the ignore list one final time,
/// 3. verifies the item still is the same file system object it was at scan time
///    (inode check, when the scanner recorded one in `metadata["inode"]`),
/// 4. moves it to the Trash or removes it, per the item's `DeletionMethod`,
/// 5. records the result in the operation log.
///
/// Root-owned items (which fail with permission errors) can optionally be retried
/// through `PrivilegedRunner` as a single batched administrator prompt.
public final class FileRemover: @unchecked Sendable {
    public static let shared = FileRemover()

    public var guardian: PathGuard
    private let log: OperationLog

    public init(guardian: PathGuard = PathGuard(), log: OperationLog = .shared) {
        self.guardian = guardian
        self.log = log
    }

    /// Disposes of `items`. Items whose `deletion` is `.custom` are ignored here.
    ///
    /// - Parameters:
    ///   - options: extra `PathGuard` permissions (e.g. `.allowAppBundles` for the Uninstaller).
    ///   - settings: used for a final ignore-list check.
    ///   - escalate: retry permission failures as administrator (one password prompt).
    public func dispose(
        _ items: [ScanItem],
        module: ModuleID,
        options: PathGuard.Options = [],
        settings: SpruceSettings? = nil,
        escalate: Bool = false,
        progress: ProgressHandler? = nil
    ) async -> RunOutcome {
        var freed: Int64 = 0
        var removed: [String] = []
        var failures: [ItemFailure] = []
        var needsRoot: [ScanItem] = []
        let candidates = items.filter { $0.deletion != .custom && $0.url != nil }

        for (index, item) in candidates.enumerated() {
            if Task.isCancelled { break }
            guard let url = item.url else { continue }
            progress?(ScanProgress(fraction: Double(index) / Double(max(candidates.count, 1)),
                                   message: "Removing \(item.title)…", current: url.path.abbreviatingHome,
                                   bytesFound: freed))

            if let settings, settings.isIgnored(path: url.path) {
                failures.append(ItemFailure(itemID: item.id, title: item.title, reason: "On the ignore list"))
                continue
            }
            let verdict = guardian.check(url, method: item.deletion, options: options)
            guard verdict.isAllowed else {
                failures.append(ItemFailure(itemID: item.id, title: item.title, reason: verdict.reason ?? "Refused"))
                log.record(module: module, action: item.deletion.rawValue, result: "refused", detail: "\(url.path) — \(verdict.reason ?? "")")
                continue
            }
            guard let current = FileWalker.entry(at: url.path) else {
                // Already gone: count as done, nothing freed.
                removed.append(item.id)
                continue
            }
            if let recorded = item.metadata["inode"], recorded != String(current.inode) {
                failures.append(ItemFailure(itemID: item.id, title: item.title, reason: "Changed since the scan; skipped"))
                continue
            }

            do {
                switch item.deletion {
                case .trash:
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                case .remove:
                    try FileManager.default.removeItem(at: url)
                case .custom:
                    continue
                }
                freed += item.size
                removed.append(item.id)
                log.record(module: module, action: item.deletion.rawValue, result: "ok", bytes: item.size, detail: url.path)
            } catch {
                let ns = error as NSError
                let permission = ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError
                    || (ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES)))
                if permission && escalate && item.deletion == .remove {
                    needsRoot.append(item)
                } else {
                    failures.append(ItemFailure(itemID: item.id, title: item.title, reason: error.localizedDescription))
                    log.record(module: module, action: item.deletion.rawValue, result: "error", detail: "\(url.path) — \(error.localizedDescription)")
                }
            }
        }

        if !needsRoot.isEmpty {
            progress?(ScanProgress(fraction: nil, message: "Waiting for administrator approval…", bytesFound: freed))
            let paths = needsRoot.compactMap { $0.url?.path }
            do {
                try await PrivilegedRunner.shared.removePaths(paths, guardian: guardian)
                for item in needsRoot {
                    guard let path = item.url?.path else { continue }
                    if FileWalker.entry(at: path) == nil {
                        freed += item.size
                        removed.append(item.id)
                        log.record(module: module, action: "remove-admin", result: "ok", bytes: item.size, detail: path)
                    } else {
                        failures.append(ItemFailure(itemID: item.id, title: item.title, reason: "Could not be removed, even as administrator"))
                    }
                }
            } catch {
                for item in needsRoot {
                    failures.append(ItemFailure(itemID: item.id, title: item.title, reason: error.localizedDescription))
                }
            }
        }

        progress?(ScanProgress(fraction: 1, message: "Done", bytesFound: freed))
        return RunOutcome(
            module: module,
            freedBytes: freed,
            processedCount: removed.count,
            removedItemIDs: removed,
            failures: failures,
            summary: removed.isEmpty ? "Nothing was removed" : "Removed \(CountFormat.items(removed.count)) · \(ByteFormat.string(freed))"
        )
    }

    /// Empties the Trash of the startup disk (permanently deletes its contents).
    public func emptyTrash(module: ModuleID = .cleanup) async -> RunOutcome {
        let trash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        let contents = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        let items = contents.map { url -> ScanItem in
            ScanItem.file(url, size: DiskUsage.measure(url.path).bytes, safety: .safe, deletion: .remove)
        }
        return await dispose(items, module: module)
    }
}
