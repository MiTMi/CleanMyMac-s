import Darwin
import Foundation
import SpruceCore

/// Disk usage maps of the startup disk, the home folder, other mounted volumes or any
/// folder.
///
/// CONTRACT: keep `public init()`. The rest of the API is owned by this module.
///
/// * Scans use `SpaceMapScanner`: parallel directory readers on dedicated threads (a
///   TaskGroup of workers), each with the "never materialise cloud files" I/O policy, so
///   reading an iCloud Drive or File Provider folder never downloads anything.
/// * The startup disk is scanned from "/" across its System and Data volumes; the Data
///   volume's own mount point (`/System/Volumes`) is skipped so firmlinked folders such as
///   `/Users` are counted once. Other volumes and mount points are never entered.
/// * For whole-volume scans the space no readable file accounts for becomes the
///   "System & snapshots" pseudo-node (used − scanned).
/// * Removal goes through `FileRemover.dispose`, always to the Trash, after `PathGuard`
///   and an inode check that the item is still what was scanned.
public final class SpaceMapEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: SpaceMapScanResult?

    public init() {}

    // MARK: State

    /// The most recent finished scan (nil before the first one).
    public var lastResult: SpaceMapScanResult? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    /// Forgets the last scan (e.g. "New Scan").
    public func discardResult() {
        lock.lock()
        storedResult = nil
        lock.unlock()
    }

    // MARK: Targets

    /// The startup disk, the home folder and every other mounted, browsable volume.
    public func availableTargets() -> [SpaceMapTarget] {
        let startupVolume = SpaceMapVolumes.info(for: URL(fileURLWithPath: "/"))
        let home = NSHomeDirectory()
        var targets = [
            SpaceMapTarget(kind: .startup, path: "/", title: startupVolume?.name ?? "Macintosh HD",
                           symbol: "internaldrive", volume: startupVolume),
            SpaceMapTarget(kind: .home, path: home, title: "Home",
                           symbol: "house", volume: SpaceMapVolumes.info(for: URL(fileURLWithPath: home)) ?? startupVolume),
        ]
        targets.append(contentsOf: SpaceMapVolumes.otherVolumes())
        return targets
    }

    /// A target for a folder the user picked (standard locations keep their names).
    public func target(forFolder url: URL) -> SpaceMapTarget {
        let path = SpaceMapScanner.standardize(url.resolvingSymlinksInPath().path)
        if let known = availableTargets().first(where: { $0.path == path }) { return known }
        let name = FileManager.default.displayName(atPath: path)
        return SpaceMapTarget(kind: .folder, path: path, title: name.isEmpty ? (path as NSString).lastPathComponent : name,
                              symbol: "folder", volume: SpaceMapVolumes.info(for: URL(fileURLWithPath: path)))
    }

    /// Fresh capacity figures for a target's volume.
    public func refreshed(_ target: SpaceMapTarget) -> SpaceMapTarget {
        var copy = target
        copy.volume = SpaceMapVolumes.info(for: URL(fileURLWithPath: target.path)) ?? target.volume
        return copy
    }

    /// Whether the location still exists (volumes get unmounted, folders renamed).
    public func exists(_ target: SpaceMapTarget) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: Scanning

    /// Builds the map of `target`. Throws `SpruceError.cancelled` when the task is cancelled.
    public func scan(_ target: SpaceMapTarget,
                     progress: @escaping SpaceMapStatsHandler) async throws -> SpaceMapScanResult {
        let current = refreshed(target)
        guard exists(current) else { throw SpruceError.notFound(current.path) }
        let options = scanOptions(for: current)
        let output = try await SpaceMapScanner.scan(path: current.path, options: options,
                                                    executor: Self.executor, progress: progress)
        var systemNode: SpaceMapNode?
        if current.coversWholeVolume, let volume = current.volume {
            systemNode = SpaceMapAccounting.attachSystemNode(to: output.root, volume: volume)
        }
        let result = SpaceMapScanResult(target: current, root: output.root, stats: output.stats, options: options,
                                        date: Date(), systemNode: systemNode)
        lock.lock()
        storedResult = result
        lock.unlock()
        return result
    }

    /// Rescans one folder of an existing map with the same boundary. Returns the fresh
    /// subtree (pass it to `SpaceMapNode.replaceContents(with:)` on the owning actor), or
    /// nil when the folder no longer exists (then detach the node).
    public func rescan(_ node: SpaceMapNode, options: SpaceMapScanOptions,
                       progress: SpaceMapStatsHandler? = nil) async throws -> SpaceMapNode? {
        guard node.isReal else { return nil }
        let path = node.path
        guard FileWalker.entry(at: path) != nil else { return nil }
        var subtree = options
        subtree.rootName = node.name
        subtree.expectedBytes = node.size > 0 ? node.size : nil
        let output = try await SpaceMapScanner.scan(path: path, options: subtree, executor: Self.executor,
                                                    progress: progress)
        return output.root
    }

    /// Scan settings for a target: boundary, reader count and expected total.
    public func scanOptions(for target: SpaceMapTarget) -> SpaceMapScanOptions {
        let startupDevices = SpaceMapVolumes.startupDevices()
        var boundary = SpaceMapBoundary()
        switch target.kind {
        case .startup:
            boundary = SpaceMapBoundary(allowedDevices: startupDevices, excludedPaths: SpaceMapBoundary.startupExclusions)
        case .home, .volume:
            boundary = SpaceMapBoundary()
        case .folder:
            if let device = FileWalker.entry(at: target.path)?.device, startupDevices.contains(device) {
                boundary = SpaceMapBoundary(allowedDevices: startupDevices,
                                            excludedPaths: SpaceMapBoundary.startupExclusions)
            }
        }
        let workers: Int
        if let volume = target.volume, !volume.isLocal {
            workers = 2
        } else if let volume = target.volume, volume.isRemovable || !volume.isInternal {
            workers = 3
        } else {
            workers = 6
        }
        return SpaceMapScanOptions(boundary: boundary, fold: SpaceMapFoldPolicy(), workers: workers,
                                   includeHidden: true,
                                   expectedBytes: target.coversWholeVolume ? target.volume?.used : nil,
                                   rootName: target.title)
    }

    // MARK: Removal

    /// Moves the given items to the Trash (items inside another given folder are covered
    /// by it). Root-owned items are retried as administrator with one password prompt.
    public func remove(_ nodes: [SpaceMapNode], settings: SpruceSettings,
                       progress: ProgressHandler? = nil) async -> RunOutcome {
        let items = SpaceMapEngine.removalItems(for: nodes)
        guard !items.isEmpty else {
            return RunOutcome(module: .spaceMap, summary: "Nothing was removed")
        }
        return await FileRemover.shared.dispose(items, module: .spaceMap, settings: settings, escalate: true,
                                                progress: progress)
    }

    /// The `ScanItem`s handed to `FileRemover` (ids are standardized paths).
    public static func removalItems(for nodes: [SpaceMapNode]) -> [ScanItem] {
        SpaceMapSelection.topmost(nodes).compactMap { node -> ScanItem? in
            guard node.isReal, let url = node.url else { return nil }
            var metadata: [String: String] = [:]
            if node.inode != 0 { metadata["inode"] = String(node.inode) }
            return ScanItem.file(url, size: node.size, itemCount: max(1, node.fileCount), safety: .review,
                                 deletion: .trash, metadata: metadata)
        }
    }

    // MARK: Workers

    /// Thread workers that never trigger downloads of cloud-only files or folders.
    static let executor = SpaceMapThreadExecutor(prepare: { SpaceMapEngine.disableMaterialization() })

    // <sys/resource.h>: IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES = 3, IOPOL_SCOPE_THREAD = 1,
    // IOPOL_MATERIALIZE_DATALESS_FILES_OFF = 1 (TN3150). Literal values keep this compiling
    // with SDKs that hide the macro names.
    private static let iopolTypeMaterialize: Int32 = 3
    private static let iopolScopeThread: Int32 = 1
    private static let iopolMaterializeOff: Int32 = 1

    /// Sets the calling thread's policy and returns the closure that restores it.
    static func disableMaterialization() -> @Sendable () -> Void {
        let previous = getiopolicy_np(iopolTypeMaterialize, iopolScopeThread)
        _ = setiopolicy_np(iopolTypeMaterialize, iopolScopeThread, iopolMaterializeOff)
        return {
            if previous >= 0 {
                _ = setiopolicy_np(SpaceMapEngine.iopolTypeMaterialize, SpaceMapEngine.iopolScopeThread, previous)
            }
        }
    }
}

// MARK: - Volumes

enum SpaceMapVolumes {
    static let keys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsRemovableKey,
        .volumeIsEjectableKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey, .volumeIsLocalKey,
    ]

    /// Capacity figures of the volume containing `url`.
    static func info(for url: URL) -> SpaceMapVolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let available = Int64(values.volumeAvailableCapacity ?? 0)
        let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
        return SpaceMapVolumeInfo(name: name, capacity: Int64(total), available: available,
                                  availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage,
                                  isInternal: values.volumeIsInternal ?? true,
                                  isRemovable: (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false),
                                  isLocal: values.volumeIsLocal ?? true)
    }

    /// Mounted volumes under /Volumes other than the startup disk (Time Machine and
    /// hidden volumes excluded).
    static func otherVolumes() -> [SpaceMapTarget] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var targets: [SpaceMapTarget] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix("/Volumes/") else { continue }
            let lowered = path.lowercased()
            if lowered.contains(".timemachine") || lowered.contains("com.apple.timemachine") { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.volumeIsRootFileSystem == true || values?.volumeIsBrowsable == false { continue }
            guard let volume = info(for: url) else { continue }
            if volume.name.hasPrefix("Backups of ") { continue }
            let symbol: String
            if !volume.isLocal {
                symbol = "server.rack"
            } else if volume.isRemovable || !volume.isInternal {
                symbol = "externaldrive"
            } else {
                symbol = "internaldrive"
            }
            targets.append(SpaceMapTarget(kind: .volume, path: path, title: volume.name, symbol: symbol, volume: volume))
        }
        return targets.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Devices of the startup volume group: the sealed System volume ("/") and the Data
    /// volume that the firmlinks point into.
    static func startupDevices() -> Set<UInt64> {
        var devices = Set<UInt64>()
        for path in ["/", "/System/Volumes/Data"] {
            if let device = FileWalker.entry(at: path)?.device { devices.insert(device) }
        }
        return devices
    }
}
