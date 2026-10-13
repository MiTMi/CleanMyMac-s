import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Options

/// Where a scan may go.
///
/// A scan never follows symbolic links and never enters another file system unless its
/// device is listed in `allowedDevices`. Scanning the startup disk from "/" allows the
/// System and Data volumes of the same volume group (so the firmlinks from `/Users`,
/// `/Applications`, `/Library`… into the Data volume are crossed) while
/// `/System/Volumes` is excluded, so the Data volume is never walked twice.
public struct SpaceMapBoundary: Sendable, Equatable {
    /// Devices a scan may enter besides the root's own (empty = root device only).
    public var allowedDevices: Set<UInt64>
    /// Absolute paths whose subtree is skipped entirely (the root itself is never skipped).
    public var excludedPaths: Set<String>

    public init(allowedDevices: Set<UInt64> = [], excludedPaths: Set<String> = []) {
        self.allowedDevices = allowedDevices
        self.excludedPaths = excludedPaths
    }

    public func allows(device: UInt64, rootDevice: UInt64) -> Bool {
        device == rootDevice || allowedDevices.contains(device)
    }

    /// Skipped when the startup disk is scanned from "/": the mount point of the Data
    /// volume and the other APFS volumes (reached through firmlinks instead), mounted
    /// disks, and virtual or automounted file systems.
    public static let startupExclusions: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/.vol", "/net", "/home", "/Network",
    ]
}

/// Keeps the tree small: the largest files of a folder become nodes, the long tail of
/// small files is folded into one `smallFiles` node per folder, and (when
/// `collapseBelowBytes` is set) small sub-folders with many items keep only their totals.
///
/// A map of a whole startup disk otherwise holds a node for nearly every folder and file
/// (millions of them, gigabytes of memory). Collapsed folders (`SpaceMapNode.isCollapsed`)
/// are measured exactly but their contents are dropped as soon as they are finished; the
/// app loads them again with a quick rescan when the user opens one.
public struct SpaceMapFoldPolicy: Sendable, Equatable {
    /// Files of one folder kept as individual nodes.
    public var maxFilesPerFolder: Int
    /// Files at least this big are always kept, whatever their rank.
    public var alwaysKeepBytes: Int64
    /// Sub-folders whose whole subtree is smaller than this are collapsed (0 = never). The
    /// scan root is never collapsed.
    public var collapseBelowBytes: Int64
    /// Only folders holding at least this many files and folders are collapsed; smaller
    /// ones cost less memory than loading them again would save.
    public var collapseMinItems: Int

    public init(maxFilesPerFolder: Int = 60, alwaysKeepBytes: Int64 = 10_000_000,
                collapseBelowBytes: Int64 = 0, collapseMinItems: Int = 40) {
        self.maxFilesPerFolder = max(1, maxFilesPerFolder)
        self.alwaysKeepBytes = alwaysKeepBytes
        self.collapseBelowBytes = max(0, collapseBelowBytes)
        self.collapseMinItems = max(1, collapseMinItems)
    }

    /// Whether a finished folder (not the scan root) keeps only its totals.
    public func shouldCollapse(_ node: SpaceMapNode) -> Bool {
        collapseBelowBytes > 0 && node.isFolder && !node.children.isEmpty
            && node.size < collapseBelowBytes && node.itemCount >= collapseMinItems
    }

    /// Collapses the sub-folders of `root` that a scan with this policy would have
    /// collapsed (`root` itself is kept). For a folder loaded in full that turned out to
    /// have grown past the threshold since the scan. Returns how many were collapsed.
    @discardableResult
    public func collapseDescendants(of root: SpaceMapNode) -> Int {
        guard collapseBelowBytes > 0 else { return 0 }
        var collapsed = 0
        var stack = root.children.filter(\.isFolder)
        while let node = stack.popLast() {
            if shouldCollapse(node) {
                _ = node.collapse()
                collapsed += 1
            } else {
                stack.append(contentsOf: node.children.filter(\.isFolder))
            }
        }
        return collapsed
    }

    /// Collapse threshold for a location on a volume with `volumeUsed` bytes in use:
    /// 0.01 % of it, between 4 MB and 256 MB (16 MB when the usage is unknown). Folders
    /// that small never show up on a map of the whole volume, and loading one takes
    /// milliseconds.
    public static func collapseThreshold(volumeUsed: Int64?) -> Int64 {
        guard let used = volumeUsed, used > 0 else { return 16_000_000 }
        return min(256_000_000, max(4_000_000, used / 10_000))
    }
}

public struct SpaceMapScanOptions: Sendable, Equatable {
    public var boundary: SpaceMapBoundary
    public var fold: SpaceMapFoldPolicy
    /// Directory readers working in parallel.
    public var workers: Int
    public var includeHidden: Bool
    /// Expected total (e.g. the volume's used space) for a progress fraction.
    public var expectedBytes: Int64?
    /// Display name of the root node (defaults to the last path component).
    public var rootName: String?

    public init(boundary: SpaceMapBoundary = SpaceMapBoundary(), fold: SpaceMapFoldPolicy = SpaceMapFoldPolicy(),
                workers: Int = 6, includeHidden: Bool = true, expectedBytes: Int64? = nil, rootName: String? = nil) {
        self.boundary = boundary
        self.fold = fold
        self.workers = max(1, workers)
        self.includeHidden = includeHidden
        self.expectedBytes = expectedBytes
        self.rootName = rootName
    }

    /// Options for measuring `node` of an existing map again: the same boundary and
    /// folding, the node's name, and its last size as the expected total. `inFull` (opening
    /// a collapsed folder) turns collapsing off: the folder was below the threshold, so its
    /// whole subtree is small (if it grew since, apply `fold.collapseDescendants(of:)` to
    /// the result). Read `node` on the actor that owns the tree.
    public func rescanning(_ node: SpaceMapNode, inFull: Bool = false) -> SpaceMapScanOptions {
        var copy = self
        copy.rootName = node.name
        copy.expectedBytes = node.size > 0 ? node.size : nil
        if inFull { copy.fold.collapseBelowBytes = 0 }
        return copy
    }
}

/// Live counters of a running scan.
public struct SpaceMapScanStats: Sendable, Equatable {
    public var files = 0
    public var folders = 0
    public var bytes: Int64 = 0
    /// Folders that could not be listed (permissions / privacy protection).
    public var unreadableFolders = 0
    /// Folder read most recently.
    public var currentPath: String?
    /// 0...1 when the expected total is known.
    public var fraction: Double?
    public var elapsed: TimeInterval = 0

    public init() {}

    public var items: Int { files + folders }
}

public typealias SpaceMapStatsHandler = @Sendable (SpaceMapScanStats) -> Void

/// The finished tree and the final counters.
public struct SpaceMapScanOutput: Sendable {
    public let root: SpaceMapNode
    public let stats: SpaceMapScanStats

    public init(root: SpaceMapNode, stats: SpaceMapScanStats) {
        self.root = root
        self.stats = stats
    }
}

// MARK: - Workers

/// Runs one blocking directory-reader loop. The app supplies an executor that also sets
/// thread I/O policies (e.g. "never materialise cloud files").
public protocol SpaceMapWorkerExecutor: Sendable {
    func run(_ work: @escaping @Sendable () -> Void) async
}

/// Runs each worker on its own thread, so blocking file system calls never occupy the
/// Swift concurrency pool. `prepare` runs first on that thread and returns the closure
/// that undoes it.
public struct SpaceMapThreadExecutor: SpaceMapWorkerExecutor {
    public var prepare: (@Sendable () -> (@Sendable () -> Void))?

    public init(prepare: (@Sendable () -> (@Sendable () -> Void))? = nil) {
        self.prepare = prepare
    }

    public func run(_ work: @escaping @Sendable () -> Void) async {
        let prepare = self.prepare
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let thread = Thread {
                let restore = prepare?()
                work()
                restore?()
                continuation.resume()
            }
            #if canImport(Darwin)
            thread.qualityOfService = .userInitiated
            #endif
            thread.start()
        }
    }
}

/// Remembers hard-linked files so each is counted once, across all workers.
public final class SpaceMapHardLinkRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<FileIdentity>()

    public init() {}

    /// True the first time an identity is seen.
    public func claim(device: UInt64, inode: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seen.insert(FileIdentity(device: device, inode: inode)).inserted
    }
}

// MARK: - Scanner

/// Builds a `SpaceMapNode` tree of allocated sizes for a folder or volume.
///
/// Several workers read directories in parallel from a shared stack; each folder is
/// finalised (post-order: own allocation + children, sorted largest first) as soon as
/// its last sub-folder is done, so the root completes last. Symlinks are never
/// followed, hard links are counted once, other file systems are not entered (see
/// `SpaceMapBoundary`), and cloud-only (dataless) files count as zero local bytes.
public enum SpaceMapScanner {

    public static func scan(
        path: String,
        options: SpaceMapScanOptions = SpaceMapScanOptions(),
        hardLinks: SpaceMapHardLinkRegistry = SpaceMapHardLinkRegistry(),
        executor: any SpaceMapWorkerExecutor = SpaceMapThreadExecutor(),
        progress: SpaceMapStatsHandler? = nil
    ) async throws -> SpaceMapScanOutput {
        let job = try SpaceMapScanJob(path: path, options: options, hardLinks: hardLinks, progress: progress)
        if job.needsWalk {
            let workers = options.workers
            await withTaskCancellationHandler {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<workers {
                        group.addTask {
                            await executor.run { job.workerLoop() }
                        }
                    }
                }
            } onCancel: {
                job.cancel()
            }
        }
        if job.wasCancelled || Task.isCancelled { throw SpruceError.cancelled }
        return job.output()
    }

    /// Absolute path without trailing or doubled slashes ("/" stays "/").
    public static func standardize(_ path: String) -> String {
        var parts: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) where component != "." {
            parts.append(component)
        }
        return "/" + parts.joined(separator: "/")
    }
}

/// One scan in progress. All shared state is guarded by `condition`.
final class SpaceMapScanJob: @unchecked Sendable {
    private let options: SpaceMapScanOptions
    private let hardLinks: SpaceMapHardLinkRegistry
    private let progress: SpaceMapStatsHandler?
    private let rootDevice: UInt64
    private let started = Date()
    private let condition = NSCondition()

    let root: SpaceMapNode
    let needsWalk: Bool

    private var stack: [(node: SpaceMapNode, path: String)] = []
    private var finished = false
    private var cancelled = false
    private var stats = SpaceMapScanStats()
    private var lastReport = Date.distantPast

    init(path: String, options: SpaceMapScanOptions, hardLinks: SpaceMapHardLinkRegistry,
         progress: SpaceMapStatsHandler?) throws {
        self.options = options
        self.hardLinks = hardLinks
        self.progress = progress
        var standardized = SpaceMapScanner.standardize(path)
        var st = stat()
        guard lstat(standardized, &st) == 0 else { throw SpruceError.notFound(path) }
        var info = SpaceMapPOSIX.info(st)
        if info.isSymlink {
            // The root may be a link to a folder; everything below it is never followed.
            standardized = SpaceMapScanner.standardize((standardized as NSString).resolvingSymlinksInPath)
            guard lstat(standardized, &st) == 0 else { throw SpruceError.notFound(path) }
            info = SpaceMapPOSIX.info(st)
        }
        rootDevice = info.device
        let lastComponent = (standardized as NSString).lastPathComponent
        let name = options.rootName ?? (standardized == "/" ? "/" : lastComponent)
        var initial = SpaceMapScanStats()
        let rootNode: SpaceMapNode
        if info.isDirectory {
            rootNode = SpaceMapNode(scannedName: name,
                                    kind: SpaceMapCatalog.isPackage(name: lastComponent) ? .package : .directory,
                                    size: info.allocated, fileCount: 0, modifiedStamp: info.modified,
                                    inode: info.inode, basePath: standardized)
            initial.folders = 1
            initial.bytes = info.allocated
        } else {
            rootNode = SpaceMapNode(scannedName: name, kind: info.isSymlink ? .symlink : .file, size: info.allocated,
                                    fileCount: 1, modifiedStamp: info.modified, inode: info.inode,
                                    cloudOnlyBytes: info.isDataless ? info.logical : 0, basePath: standardized)
            initial.files = 1
            initial.bytes = info.allocated
        }
        root = rootNode
        needsWalk = info.isDirectory
        finished = !info.isDirectory
        stack = info.isDirectory ? [(rootNode, standardized)] : []
        stats = initial
    }

    var wasCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    func output() -> SpaceMapScanOutput {
        condition.lock()
        var final = stats
        condition.unlock()
        final.elapsed = Date().timeIntervalSince(started)
        final.fraction = 1
        final.currentPath = nil
        return SpaceMapScanOutput(root: root, stats: final)
    }

    /// One worker: pop a folder, read it outside the lock, publish its sub-folders.
    func workerLoop() {
        while true {
            condition.lock()
            while stack.isEmpty && !finished && !cancelled {
                condition.wait()
            }
            if finished || cancelled {
                condition.unlock()
                return
            }
            let job = stack.removeLast()
            condition.unlock()

            let listing = read(job.node, path: job.path)

            condition.lock()
            stats.folders += listing.subdirectories.count
            stats.files += listing.files
            stats.bytes += listing.bytes
            if job.node.isUnreadable { stats.unreadableFolders += 1 }
            stats.currentPath = job.path
            // Contents of collapsed folders, released after the lock is given up.
            var dropped: [[SpaceMapNode]] = []
            if listing.subdirectories.isEmpty {
                complete(job.node, dropped: &dropped)
            } else {
                job.node.scanPending = listing.subdirectories.count
                stack.append(contentsOf: listing.subdirectories.reversed())
                condition.broadcast()
            }
            let report = takeReportIfDue()
            condition.unlock()
            dropped.removeAll()
            if let report { progress?(report) }
        }
    }

    /// Lock held. Finalises a folder whose sub-folders are all done, then its ancestors;
    /// small folders with many items are collapsed as soon as they are final.
    private func complete(_ node: SpaceMapNode, dropped: inout [[SpaceMapNode]]) {
        var current: SpaceMapNode? = node
        while let folder = current {
            folder.finalizeAggregates()
            if folder === root {
                finished = true
                condition.broadcast()
                return
            }
            if options.fold.shouldCollapse(folder) {
                dropped.append(folder.collapse())
            }
            guard let parent = folder.parent else { return }
            parent.scanPending -= 1
            if parent.scanPending > 0 { return }
            current = parent
        }
    }

    /// Lock held. A stats snapshot at most every 120 ms.
    private func takeReportIfDue() -> SpaceMapScanStats? {
        guard progress != nil else { return nil }
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 0.12 else { return nil }
        lastReport = now
        var snapshot = stats
        snapshot.elapsed = now.timeIntervalSince(started)
        if let expected = options.expectedBytes, expected > 0 {
            snapshot.fraction = min(0.99, Double(snapshot.bytes) / Double(expected))
        }
        return snapshot
    }

    private struct Listing {
        var subdirectories: [(node: SpaceMapNode, path: String)] = []
        var files = 0
        var bytes: Int64 = 0
    }

    /// Reads one folder: creates nodes for its sub-folders (attached, not yet sized) and
    /// for its files (folded per policy). Only this worker touches `node` meanwhile.
    private func read(_ node: SpaceMapNode, path: String) -> Listing {
        var listing = Listing()
        guard let directory = opendir(path) else {
            let code = errno
            if code == EACCES || code == EPERM { node.isUnreadable = true }
            return listing
        }
        defer { closedir(directory) }
        let prefix = path == "/" ? "/" : path + "/"
        var leaves: [SpaceMapLeaf] = []
        while let entry = readdir(directory) {
            if wasCancelledUnlocked { break }
            let name = SpaceMapPOSIX.name(of: entry)
            if name == "." || name == ".." || name.isEmpty { continue }
            if !options.includeHidden && name.hasPrefix(".") { continue }
            let childPath = prefix + name
            var st = stat()
            guard lstat(childPath, &st) == 0 else { continue }
            let info = SpaceMapPOSIX.info(st)
            if info.isDirectory {
                guard options.boundary.allows(device: info.device, rootDevice: rootDevice),
                      !options.boundary.excludedPaths.contains(childPath) else { continue }
                let child = SpaceMapNode(scannedName: name, kind: SpaceMapCatalog.isPackage(name: name) ? .package : .directory,
                                         size: info.allocated, fileCount: 0, modifiedStamp: info.modified, inode: info.inode)
                child.parent = node
                node.children.append(child)
                listing.subdirectories.append((child, childPath))
                listing.bytes += info.allocated
            } else {
                var bytes = info.allocated
                if info.isRegular && info.linkCount > 1
                    && !hardLinks.claim(device: info.device, inode: info.inode) {
                    bytes = 0
                }
                leaves.append(SpaceMapLeaf(name: name, bytes: bytes, modified: info.modified, inode: info.inode,
                                           isSymlink: info.isSymlink, cloudBytes: info.isDataless ? info.logical : 0))
                listing.files += 1
                listing.bytes += bytes
            }
        }
        SpaceMapFolding.attach(leaves, to: node, policy: options.fold)
        return listing
    }

    /// A racy read is fine here: it only shortens a directory read after Stop.
    private var wasCancelledUnlocked: Bool { cancelled }
}

// MARK: - Folding

/// A file found while reading a folder, before it becomes a node.
struct SpaceMapLeaf {
    var name: String
    var bytes: Int64
    var modified: Double
    var inode: UInt64
    var isSymlink: Bool
    var cloudBytes: Int64
}

enum SpaceMapFolding {
    /// Adds file nodes to `node`: the largest `maxFilesPerFolder` (plus any file of at
    /// least `alwaysKeepBytes`) individually, the rest as one `smallFiles` node.
    static func attach(_ leaves: [SpaceMapLeaf], to node: SpaceMapNode, policy: SpaceMapFoldPolicy) {
        guard !leaves.isEmpty else { return }
        var kept: ArraySlice<SpaceMapLeaf>
        var folded: ArraySlice<SpaceMapLeaf> = []
        if leaves.count <= policy.maxFilesPerFolder {
            kept = leaves[...]
        } else {
            let sorted = leaves.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
            var cut = policy.maxFilesPerFolder
            while cut < sorted.count && sorted[cut].bytes >= policy.alwaysKeepBytes { cut += 1 }
            // Folding a single file would only hide it.
            if sorted.count - cut == 1 { cut += 1 }
            kept = sorted[..<cut]
            folded = sorted[cut...]
        }
        node.children.reserveCapacity(node.children.count + kept.count + (folded.isEmpty ? 0 : 1))
        for leaf in kept {
            let child = SpaceMapNode(scannedName: leaf.name, kind: leaf.isSymlink ? .symlink : .file, size: leaf.bytes,
                                     fileCount: 1, modifiedStamp: leaf.modified, inode: leaf.inode,
                                     cloudOnlyBytes: leaf.cloudBytes)
            child.parent = node
            node.children.append(child)
        }
        guard !folded.isEmpty else { return }
        var bytes: Int64 = 0
        var cloud: Int64 = 0
        var newest: Double = 0
        for leaf in folded {
            bytes += leaf.bytes
            cloud += leaf.cloudBytes
            if leaf.modified > newest { newest = leaf.modified }
        }
        let group = SpaceMapNode(scannedName: "\(CountFormat.grouped(folded.count)) smaller files", kind: .smallFiles,
                                 size: bytes, fileCount: folded.count, modifiedStamp: newest, inode: 0,
                                 cloudOnlyBytes: cloud)
        group.parent = node
        node.children.append(group)
    }
}

// MARK: - POSIX helpers

struct SpaceMapStatInfo {
    var isDirectory: Bool
    var isRegular: Bool
    var isSymlink: Bool
    var allocated: Int64
    var logical: Int64
    var modified: Double
    var inode: UInt64
    var device: UInt64
    var linkCount: Int
    /// Cloud-only placeholder (SF_DATALESS): occupies no local blocks.
    var isDataless: Bool
}

enum SpaceMapPOSIX {
    static func info(_ st: stat) -> SpaceMapStatInfo {
        let mode = UInt32(st.st_mode) & UInt32(S_IFMT)
        #if canImport(Darwin)
        let modified = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        let dataless = (UInt32(st.st_flags) & 0x4000_0000) != 0
        #else
        let modified = Double(st.st_mtim.tv_sec) + Double(st.st_mtim.tv_nsec) / 1e9
        let dataless = false
        #endif
        return SpaceMapStatInfo(
            isDirectory: mode == UInt32(S_IFDIR),
            isRegular: mode == UInt32(S_IFREG),
            isSymlink: mode == UInt32(S_IFLNK),
            allocated: Int64(st.st_blocks) * 512,
            logical: Int64(st.st_size),
            modified: modified,
            inode: UInt64(st.st_ino),
            device: UInt64(truncatingIfNeeded: Int64(st.st_dev)),
            linkCount: Int(st.st_nlink),
            isDataless: dataless
        )
    }

    static func name(of entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: &entry.pointee.d_name) { pointer -> String in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                String(cString: $0)
            }
        }
    }

    /// Device of a path (same encoding as `FileEntry.device`), or nil when it doesn't exist.
    static func device(of path: String) -> UInt64? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return UInt64(truncatingIfNeeded: Int64(st.st_dev))
    }
}
