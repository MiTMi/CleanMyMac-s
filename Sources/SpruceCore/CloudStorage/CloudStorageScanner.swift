import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Settings for one provider scan.
public struct CloudStorageScanOptions: Sendable {
    /// Downloaded files at or above this size count as "large".
    public var largeFileThreshold: Int64
    /// Smallest file shown in the lists.
    public var listMinimumSize: Int64
    /// Maximum number of downloaded files kept for the list.
    public var localListLimit: Int
    /// Maximum number of online-only files kept for the list.
    public var cloudListLimit: Int
    /// Folder names never walked (provider caches, trash, Google Drive shortcut targets).
    public var excludedNames: Set<String>
    /// Paths on the user's ignore list (checked for every file and folder).
    public var isIgnored: (@Sendable (String) -> Bool)?

    public init(largeFileThreshold: Int64 = 100_000_000, listMinimumSize: Int64 = 1_000_000,
                localListLimit: Int = 300, cloudListLimit: Int = 100,
                excludedNames: Set<String> = CloudStoragePath.excludedNames,
                isIgnored: (@Sendable (String) -> Bool)? = nil) {
        self.largeFileThreshold = largeFileThreshold
        self.listMinimumSize = listMinimumSize
        self.localListLimit = localListLimit
        self.cloudListLimit = cloudListLimit
        self.excludedNames = excludedNames
        self.isIgnored = isIgnored
    }
}

/// Walks a provider's folders and measures local versus cloud-only content.
///
/// * Blocking and single-threaded: the Mac engine runs it on a dedicated thread with
///   cloud materialisation switched off, so nothing is ever downloaded. Online-only
///   folders are counted but not entered.
/// * Never follows symlinks (Google Drive shortcuts), never crosses into other volumes,
///   counts hard-linked files once, and treats packages as single documents.
/// * Online-only files are recognised by `SF_DATALESS` (macOS) or, everywhere, by a
///   real size with no allocated blocks — a heuristic that is only applied inside cloud
///   folders, where sparse files don't otherwise occur.
public enum CloudStorageScanner {

    /// `SF_DATALESS` from `<sys/stat.h>`.
    public static let datalessFlag: UInt32 = 0x4000_0000

    public static func scan(
        _ provider: CloudStorageProvider,
        options: CloudStorageScanOptions = CloudStorageScanOptions(),
        isCancelled: () -> Bool = { false },
        progress: CloudStorageScanTickHandler? = nil
    ) -> CloudStorageProviderReport {
        var walker = Walker(provider: provider, options: options, progress: progress)
        var rootReadable = false
        for (index, root) in provider.scanRoots.enumerated() {
            if isCancelled() { break }
            let readable = walker.walk(root: root.path, area: root.area, isCancelled: isCancelled)
            if index == 0 { rootReadable = readable }
        }
        let cancelled = isCancelled()
        progress?(CloudStorageScanTick(providerID: provider.id, filesSeen: walker.stats.fileCount,
                                       localBytes: walker.stats.localBytes, cloudBytes: walker.stats.cloudBytes,
                                       currentPath: nil, finished: true))
        return CloudStorageProviderReport(
            provider: provider,
            stats: walker.stats,
            largestLocal: walker.local.sorted,
            largestCloudOnly: walker.cloud.sorted,
            scanDate: Date(),
            accessDenied: !rootReadable && walker.stats.fileCount == 0,
            isComplete: !cancelled
        )
    }

    // MARK: - Walker

    private struct Pending {
        var path: String
        var depth: Int
        var area: CloudStorageArea
    }

    struct StatInfo {
        var isDirectory: Bool
        var isRegular: Bool
        var isSymlink: Bool
        var logical: Int64
        var allocated: Int64
        var modified: Date
        var inode: UInt64
        var device: UInt64
        var linkCount: Int
        var flagDataless: Bool

        /// Online-only: the kernel flag, or a real size with nothing allocated.
        var isDataless: Bool { flagDataless || (isRegular && logical > 0 && allocated == 0) }
    }

    private struct Walker {
        let provider: CloudStorageProvider
        let options: CloudStorageScanOptions
        let progress: CloudStorageScanTickHandler?
        var stats = CloudStorageStats()
        var local: CloudStorageTopFiles
        var cloud: CloudStorageTopFiles
        var seenLinks = Set<FileIdentity>()
        var lastTick = 0
        var visited = 0

        init(provider: CloudStorageProvider, options: CloudStorageScanOptions, progress: CloudStorageScanTickHandler?) {
            self.provider = provider
            self.options = options
            self.progress = progress
            local = CloudStorageTopFiles(limit: options.localListLimit, minimumSize: options.listMinimumSize, measure: .local)
            cloud = CloudStorageTopFiles(limit: options.cloudListLimit, minimumSize: options.listMinimumSize, measure: .logical)
        }

        /// Walks one root. Returns false when the root itself could not be listed.
        mutating func walk(root: String, area: CloudStorageArea, isCancelled: () -> Bool) -> Bool {
            guard let rootInfo = CloudStorageScanner.statInfo(root), rootInfo.isDirectory, !rootInfo.isSymlink else {
                return false
            }
            if rootInfo.flagDataless {
                stats.unlistedFolderCount += 1
                return true
            }
            let device = rootInfo.device
            var stack = [Pending(path: root, depth: 0, area: area)]
            var rootListed = false
            while let current = stack.popLast() {
                if isCancelled() { break }
                guard let children = list(current.path) else {
                    if current.depth == 0 { return false }
                    continue
                }
                if current.depth == 0 { rootListed = true }
                for name in children {
                    visited += 1
                    let path = current.path == "/" ? "/" + name : current.path + "/" + name
                    guard let info = CloudStorageScanner.statInfo(path) else { continue }
                    if info.isSymlink { continue }
                    if let isIgnored = options.isIgnored, isIgnored(path) { continue }
                    if info.isDirectory {
                        if options.excludedNames.contains(name) { continue }
                        if info.device != device { continue }
                        if info.flagDataless {
                            stats.unlistedFolderCount += 1
                            continue
                        }
                        let nextArea = childArea(named: name, parent: current)
                        if CloudStoragePath.isPackage(name: name) {
                            addPackage(path: path, info: info, area: nextArea, isCancelled: isCancelled)
                        } else {
                            stats.folderCount += 1
                            stack.append(Pending(path: path, depth: current.depth + 1, area: nextArea))
                        }
                    } else if info.isRegular {
                        addFile(path: path, name: name, info: info, area: current.area)
                    }
                    tick(path)
                }
            }
            return rootListed
        }

        /// iCloud's synced Desktop & Documents live at the top of iCloud Drive.
        private func childArea(named name: String, parent: Pending) -> CloudStorageArea {
            guard parent.depth == 0, parent.area == .drive, provider.kind == .iCloudDrive else { return parent.area }
            return (name == "Desktop" || name == "Documents") ? .desktopAndDocuments : parent.area
        }

        private mutating func addFile(path: String, name: String, info: StatInfo, area: CloudStorageArea) {
            if info.linkCount > 1 {
                guard seenLinks.insert(FileIdentity(device: info.device, inode: info.inode)).inserted else { return }
            }
            let record = CloudStorageFileRecord(
                path: path,
                logicalSize: info.logical,
                allocatedSize: info.isDataless ? 0 : info.allocated,
                isCloudOnly: info.isDataless,
                isPackage: false,
                fileCount: 1,
                modified: info.modified,
                inode: info.inode,
                area: area
            )
            stats.add(record, largeThreshold: options.largeFileThreshold)
            guard !CloudStoragePath.isBookkeeping(name: name) else { return }
            if record.isCloudOnly { cloud.insert(record) } else { local.insert(record) }
        }

        /// Measures a package as one document: local if anything inside is downloaded.
        private mutating func addPackage(path: String, info: StatInfo, area: CloudStorageArea, isCancelled: () -> Bool) {
            var logical: Int64 = 0
            var allocated: Int64 = 0
            var files = 0
            var newest = info.modified
            var stack = [path]
            var unlisted = false
            while let dir = stack.popLast() {
                if isCancelled() { break }
                guard let children = list(dir) else { continue }
                for name in children {
                    let child = dir + "/" + name
                    guard let childInfo = CloudStorageScanner.statInfo(child), !childInfo.isSymlink else { continue }
                    if childInfo.isDirectory {
                        if childInfo.flagDataless {
                            unlisted = true
                        } else if childInfo.device == info.device {
                            stack.append(child)
                        }
                    } else if childInfo.isRegular {
                        if childInfo.linkCount > 1 {
                            guard seenLinks.insert(FileIdentity(device: childInfo.device, inode: childInfo.inode)).inserted else { continue }
                        }
                        files += 1
                        logical += childInfo.logical
                        if !childInfo.isDataless { allocated += childInfo.allocated }
                        if childInfo.modified > newest { newest = childInfo.modified }
                    }
                }
            }
            if files == 0 && unlisted {
                stats.unlistedFolderCount += 1
                return
            }
            let record = CloudStorageFileRecord(
                path: path,
                logicalSize: logical,
                allocatedSize: allocated,
                isCloudOnly: allocated == 0 && logical > 0,
                isPackage: true,
                fileCount: max(files, 1),
                modified: newest,
                inode: info.inode,
                area: area
            )
            stats.add(record, largeThreshold: options.largeFileThreshold)
            if record.isCloudOnly { cloud.insert(record) } else { local.insert(record) }
        }

        /// Lists a directory's entry names (nil when it can't be opened).
        private mutating func list(_ path: String) -> [String]? {
            guard let dir = opendir(path) else {
                let code = errno
                if code == EPERM || code == EACCES {
                    stats.unreadableFolderCount += 1
                } else if code == EDEADLK {
                    // Materialisation is off and the folder is online-only.
                    stats.unlistedFolderCount += 1
                }
                return nil
            }
            defer { closedir(dir) }
            var names: [String] = []
            while let entry = readdir(dir) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer -> String in
                    pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }
                names.append(name)
            }
            return names
        }

        private mutating func tick(_ path: String) {
            guard let progress, visited - lastTick >= 400 else { return }
            lastTick = visited
            progress(CloudStorageScanTick(providerID: provider.id, filesSeen: stats.fileCount,
                                          localBytes: stats.localBytes, cloudBytes: stats.cloudBytes,
                                          currentPath: path, finished: false))
        }
    }

    // MARK: - stat

    /// `lstat` with the fields the scanner needs. Never follows symlinks.
    static func statInfo(_ path: String) -> StatInfo? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let mode = UInt32(st.st_mode) & UInt32(S_IFMT)
        #if canImport(Darwin)
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
        let dataless = (UInt32(st.st_flags) & datalessFlag) != 0
        #else
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtim.tv_sec) + TimeInterval(st.st_mtim.tv_nsec) / 1e9)
        let dataless = false
        #endif
        return StatInfo(
            isDirectory: mode == UInt32(S_IFDIR),
            isRegular: mode == UInt32(S_IFREG),
            isSymlink: mode == UInt32(S_IFLNK),
            logical: Int64(st.st_size),
            allocated: Int64(st.st_blocks) * 512,
            modified: modified,
            inode: UInt64(st.st_ino),
            device: UInt64(truncatingIfNeeded: Int64(st.st_dev)),
            linkCount: Int(st.st_nlink),
            flagDataless: dataless
        )
    }

    /// Re-measures one file or package after an action (free up / download).
    /// Returns nil when the item no longer exists.
    public static func remeasure(_ record: CloudStorageFileRecord) -> CloudStorageFileRecord? {
        guard let info = statInfo(record.path), !info.isSymlink else { return nil }
        var updated = record
        updated.inode = info.inode
        if info.isDirectory && info.flagDataless {
            // The whole package became an online-only placeholder.
            updated.allocatedSize = 0
            updated.isCloudOnly = true
            return updated
        }
        if info.isDirectory {
            var logical: Int64 = 0
            var allocated: Int64 = 0
            var files = 0
            var stack = [record.path]
            while let dir = stack.popLast() {
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
                for name in names {
                    let child = dir + "/" + name
                    guard let childInfo = statInfo(child), !childInfo.isSymlink else { continue }
                    if childInfo.isDirectory {
                        if !childInfo.flagDataless { stack.append(child) }
                    } else if childInfo.isRegular {
                        files += 1
                        logical += childInfo.logical
                        if !childInfo.isDataless { allocated += childInfo.allocated }
                    }
                }
            }
            if files > 0 { updated.logicalSize = logical }
            updated.allocatedSize = allocated
            updated.isCloudOnly = allocated == 0 && updated.logicalSize > 0
            updated.fileCount = max(files, 1)
        } else {
            updated.logicalSize = info.logical
            updated.allocatedSize = info.isDataless ? 0 : info.allocated
            updated.isCloudOnly = info.isDataless
            updated.modified = info.modified
        }
        return updated
    }
}
