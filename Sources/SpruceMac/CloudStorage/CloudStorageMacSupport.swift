import CoreServices
import Darwin
import Foundation
import SpruceCore

// MARK: - Threads without cloud downloads

/// Runs blocking file system work on a dedicated thread whose I/O policy forbids
/// materialising (downloading) online-only files and folders (TN3150). Touching a
/// placeholder there fails with `EDEADLK` instead of starting a download.
enum CloudStorageThreadRunner {
    // <sys/resource.h>: IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES = 3, IOPOL_SCOPE_THREAD = 1,
    // IOPOL_MATERIALIZE_DATALESS_FILES_OFF = 1. Literal values keep this compiling with
    // SDKs that don't export the macro names to Swift.
    private static let iopolTypeMaterialize: Int32 = 3
    private static let iopolScopeThread: Int32 = 1
    private static let iopolMaterializeOff: Int32 = 1

    /// - Parameter allowMaterialization: leave the default policy in place (for calls that
    ///   ask macOS to evict or download, which must not be blocked themselves).
    static func run<T: Sendable>(allowMaterialization: Bool = false, _ body: @escaping @Sendable () -> T) async -> T {
        let type = iopolTypeMaterialize
        let scope = iopolScopeThread
        let off = iopolMaterializeOff
        return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let thread = Thread {
                var previous: Int32 = -1
                if !allowMaterialization {
                    previous = getiopolicy_np(type, scope)
                    _ = setiopolicy_np(type, scope, off)
                }
                let value = body()
                if previous >= 0 {
                    _ = setiopolicy_np(type, scope, previous)
                }
                continuation.resume(returning: value)
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }
}

/// Thread-safe cancellation flag shared with blocking scanner threads.
final class CloudStorageCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

// MARK: - Metadata

/// Reads sync state and last-use dates without reading file contents.
enum CloudStorageMetadata {
    static let ubiquityKeys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemIsDownloadingKey, .ubiquitousItemHasUnresolvedConflictsKey,
    ]

    /// Current sync status of an item as macOS reports it (fresh, uncached values).
    static func status(at path: String, keepingRequest previous: CloudStorageSyncStatus = .unknown) -> CloudStorageSyncStatus {
        var url = URL(fileURLWithPath: path)
        url.removeAllCachedResourceValues()
        var status = CloudStorageSyncStatus(downloadRequested: previous.downloadRequested)
        guard let values = try? url.resourceValues(forKeys: ubiquityKeys) else { return status }
        // Providers that aren't ubiquitous report nothing useful.
        guard values.isUbiquitousItem != false else { return status }
        if let downloading = values.ubiquitousItemDownloadingStatus {
            if downloading == .current {
                status.download = .current
            } else if downloading == .downloaded {
                status.download = .downloaded
            } else if downloading == .notDownloaded {
                status.download = .notDownloaded
            }
        }
        status.isUploaded = values.ubiquitousItemIsUploaded
        status.isUploading = values.ubiquitousItemIsUploading ?? false
        status.isDownloading = values.ubiquitousItemIsDownloading ?? false
        status.hasConflicts = values.ubiquitousItemHasUnresolvedConflicts ?? false
        return status
    }

    /// Spotlight's "last opened" date.
    static func lastUsed(at path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Adds sync status and last-use dates to listed records. iCloud's own download
    /// status wins over the block-count heuristic when the two disagree.
    static func enrich(_ records: [CloudStorageFileRecord], mechanism: CloudStorageMechanism) -> [CloudStorageFileRecord] {
        records.map { record in
            var record = record
            if mechanism != .syncFolder {
                record.status = status(at: record.path, keepingRequest: record.status)
                // iCloud says "not downloaded" but a small stub is still allocated.
                if mechanism == .iCloud, !record.isPackage, !record.isCloudOnly,
                   record.status.download == .notDownloaded, record.allocatedSize * 16 <= record.logicalSize {
                    record.isCloudOnly = true
                }
            }
            if record.lastUsed == nil { record.lastUsed = lastUsed(at: record.path) }
            return record
        }
    }
}

// MARK: - Command-line helpers

/// Detects and runs the optional command-line helpers, as the current user.
enum CloudStorageTools {
    static let brctlPath = "/usr/bin/brctl"
    static let fileProviderCtlPath = "/usr/bin/fileproviderctl"

    static func detect() async -> CloudStorageToolAvailability {
        let fm = FileManager.default
        var tools = CloudStorageToolAvailability(brctl: fm.isExecutableFile(atPath: brctlPath))
        if fm.isExecutableFile(atPath: fileProviderCtlPath) {
            let result = await Shell.run(fileProviderCtlPath, ["help"], timeout: 10)
            let text = result.stdout + "\n" + result.stderr
            tools.fileProviderCtlEvict = CloudStorageToolAvailability.helpListsVerb("evict", in: text)
            tools.fileProviderCtlMaterialize = CloudStorageToolAvailability.helpListsVerb("materialize", in: text)
        }
        return tools
    }

    /// Runs a helper verb on one path. Returns nil on success, otherwise the reason.
    static func run(_ executable: String, verb: String, path: String) async -> String? {
        let result = await Shell.run(executable, [verb, path], timeout: 120)
        if result.status == 0 { return nil }
        let message = (result.stderr.isEmpty ? result.stdout : result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tool = (executable as NSString).lastPathComponent
        return message.isEmpty ? "\(tool) \(verb) failed (exit \(result.status))" : "\(tool): \(message)"
    }
}

// MARK: - Errors

extension Error {
    /// Short, readable description of a Foundation/Cocoa error.
    var cloudStorageMessage: String {
        let ns = self as NSError
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           let reason = underlying.localizedFailureReason ?? (underlying.localizedDescription.isEmpty ? nil : underlying.localizedDescription) {
            return reason
        }
        return ns.localizedFailureReason ?? ns.localizedDescription
    }
}
