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
/// 5. records the result in the operation log, and where each trashed item went in
///    the `TrashLedger` (so the run can be put back).
///
/// Root-owned items (which fail with permission errors) can optionally be retried
/// through `PrivilegedRunner` as a single batched administrator prompt — only where
/// `PathGuard.checkPrivileged` allows root to act, and never after the run was stopped.
public final class FileRemover: @unchecked Sendable {
    public static let shared = FileRemover()

    public var guardian: PathGuard
    private let log: OperationLog
    private let ledger: TrashLedger

    public init(guardian: PathGuard = PathGuard(), log: OperationLog = .shared) {
        self.guardian = guardian
        self.log = log
        self.ledger = .shared
    }

    /// Reason given for items left alone because the run was stopped.
    public static let stoppedReason = "Stopped before this item"

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
        var trashedBytes: Int64 = 0
        var trashedCount = 0
        var removed: [String] = []
        var failures: [ItemFailure] = []
        var needsRoot: [ScanItem] = []
        var needsRootTrash: [ScanItem] = []
        var ledgerEntries: [TrashLedgerEntry] = []
        let runID = UUID()
        let candidates = items.filter { $0.deletion != .custom && $0.url != nil }
        let reporter = ProgressThrottle(progress)

        for (index, item) in candidates.enumerated() {
            if Task.isCancelled { break }
            guard let url = item.url else { continue }
            reporter.report(ScanProgress(fraction: Double(index) / Double(max(candidates.count, 1)),
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
                    var resulting: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                    trashedBytes += item.size
                    trashedCount += 1
                    if let trashedPath = resulting?.path {
                        ledgerEntries.append(TrashLedgerEntry(runID: runID, module: module, originalPath: url.path,
                                                              trashedPath: trashedPath, bytes: item.size))
                    }
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
                } else if permission && escalate && item.deletion == .trash {
                    needsRootTrash.append(item)
                } else {
                    failures.append(ItemFailure(itemID: item.id, title: item.title, reason: error.localizedDescription))
                    log.record(module: module, action: item.deletion.rawValue, result: "error", detail: "\(url.path) — \(error.localizedDescription)")
                }
            }
        }

        // Stop pressed: never put up an administrator prompt for what was collected so far.
        if Task.isCancelled {
            for item in needsRoot + needsRootTrash {
                failures.append(ItemFailure(itemID: item.id, title: item.title, reason: Self.stoppedReason))
            }
            needsRoot = []
            needsRootTrash = []
        }

        // Root may only act in a few places; explain the rest instead of prompting for them.
        needsRoot = needsRoot.filter { item in
            guard let path = item.url?.path else { return false }
            let verdict = guardian.checkPrivileged(path, method: .remove, options: options)
            if verdict.isAllowed { return true }
            failures.append(ItemFailure(itemID: item.id, title: item.title, reason: Self.permissionReason(verdict)))
            log.record(module: module, action: "remove-admin", result: "refused", detail: "\(path) — \(verdict.reason ?? "")")
            return false
        }
        let trashDevice = FileWalker.entry(at: (NSHomeDirectory() as NSString).appendingPathComponent(".Trash"))?.device
        needsRootTrash = needsRootTrash.filter { item in
            guard let path = item.url?.path else { return false }
            let verdict = guardian.checkPrivileged(path, method: .trash, options: options)
            guard verdict.isAllowed else {
                failures.append(ItemFailure(itemID: item.id, title: item.title, reason: Self.permissionReason(verdict)))
                log.record(module: module, action: "trash-admin", result: "refused", detail: "\(path) — \(verdict.reason ?? "")")
                return false
            }
            if let trashDevice, let device = FileWalker.entry(at: path)?.device, device != trashDevice {
                failures.append(ItemFailure(itemID: item.id, title: item.title,
                                            reason: "It needs administrator rights and is on another disk; move it to the Trash in Finder."))
                return false
            }
            return true
        }

        if !needsRoot.isEmpty {
            reporter.report(ScanProgress(fraction: nil, message: "Waiting for administrator approval…", bytesFound: freed), force: true)
            let paths = needsRoot.compactMap { $0.url?.path }
            do {
                let gone = try await PrivilegedRunner.shared.removePaths(paths, guardian: guardian, options: options)
                for item in needsRoot {
                    guard let path = item.url?.path else { continue }
                    if gone.contains(path) {
                        freed += item.size
                        removed.append(item.id)
                        log.record(module: module, action: "remove-admin", result: "ok", bytes: item.size, detail: path)
                    } else if FileWalker.entry(at: path) == nil {
                        // Went with a folder removed in the same batch.
                        removed.append(item.id)
                    } else {
                        failures.append(ItemFailure(itemID: item.id, title: item.title, reason: "Could not be removed, even as administrator"))
                    }
                }
            } catch {
                for item in needsRoot {
                    failures.append(ItemFailure(itemID: item.id, title: item.title, reason: Self.adminFailureReason(error)))
                }
            }
        }

        if !needsRootTrash.isEmpty {
            reporter.report(ScanProgress(fraction: nil, message: "Waiting for administrator approval…", bytesFound: freed), force: true)
            let paths = needsRootTrash.compactMap { $0.url?.path }
            do {
                let moved = try await PrivilegedRunner.shared.trashPaths(paths, guardian: guardian, options: options)
                for item in needsRootTrash {
                    guard let path = item.url?.path else { continue }
                    if let destination = moved[path] {
                        freed += item.size
                        trashedBytes += item.size
                        trashedCount += 1
                        removed.append(item.id)
                        ledgerEntries.append(TrashLedgerEntry(runID: runID, module: module, originalPath: path,
                                                              trashedPath: destination, bytes: item.size, byAdministrator: true))
                        log.record(module: module, action: "trash-admin", result: "ok", bytes: item.size, detail: "\(path) -> \(destination)")
                    } else if FileWalker.entry(at: path) == nil,
                              moved.keys.contains(where: { PathGuard.isStrictlyInside(PathGuard.key(path), PathGuard.key($0)) }) {
                        // Went to the Trash inside a folder moved in the same batch.
                        removed.append(item.id)
                    } else {
                        failures.append(ItemFailure(itemID: item.id, title: item.title, reason: "Could not be moved to the Trash, even as administrator"))
                    }
                }
            } catch {
                for item in needsRootTrash {
                    failures.append(ItemFailure(itemID: item.id, title: item.title, reason: Self.adminFailureReason(error)))
                }
            }
        }

        ledger.record(ledgerEntries)
        reporter.report(ScanProgress(fraction: 1, message: "Done", bytesFound: freed), force: true)
        return RunOutcome(
            module: module,
            freedBytes: freed,
            processedCount: removed.count,
            removedItemIDs: removed,
            failures: failures,
            summary: Self.summary(count: removed.count, bytes: freed, trashedCount: trashedCount),
            trashedBytes: trashedBytes,
            trashedCount: trashedCount,
            trashRunIDs: ledgerEntries.isEmpty ? [] : [runID]
        )
    }

    /// "Removed 3 items · 1.2 GB", "Moved 3 items to the Trash · 1.2 GB", or both.
    public static func summary(count: Int, bytes: Int64, trashedCount: Int) -> String {
        guard count > 0 else { return "Nothing was removed" }
        let size = ByteFormat.string(bytes)
        if trashedCount >= count { return "Moved \(CountFormat.items(count)) to the Trash · \(size)" }
        if trashedCount == 0 { return "Removed \(CountFormat.items(count)) · \(size)" }
        return "Removed \(CountFormat.items(count)) · \(size) (\(CountFormat.items(trashedCount)) moved to the Trash)"
    }

    private static func permissionReason(_ verdict: PathGuard.Verdict) -> String {
        verdict.reason ?? "It needs administrator rights, which Spruce won't use here."
    }

    private static func adminFailureReason(_ error: Error) -> String {
        if (error as? SpruceError) == .cancelled { return "Administrator approval was cancelled" }
        return error.localizedDescription
    }

    /// Empties the Trash of the startup disk (permanently deletes its contents). Trashed
    /// apps are whole bundles, and root-owned items (left by installers, or moved there
    /// as administrator) need one administrator prompt.
    public func emptyTrash(module: ModuleID = .cleanup) async -> RunOutcome {
        let trash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        let contents = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        let items = contents.map { url -> ScanItem in
            ScanItem.file(url, size: DiskUsage.measure(url.path).bytes, safety: .safe, deletion: .remove)
        }
        return await dispose(items, module: module, options: [.allowAppBundles], escalate: true)
    }
}

/// Forwards at most one progress update per `interval` (forced updates always pass), so
/// removing tens of thousands of small files doesn't flood the main actor.
final class ProgressThrottle {
    private let handler: ProgressHandler?
    private let interval: TimeInterval
    private var last: TimeInterval = -.infinity

    init(_ handler: ProgressHandler?, interval: TimeInterval = 0.08) {
        self.handler = handler
        self.interval = interval
    }

    func report(_ progress: ScanProgress, force: Bool = false) {
        guard let handler else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - last >= interval else { return }
        last = now
        handler(progress)
    }
}
