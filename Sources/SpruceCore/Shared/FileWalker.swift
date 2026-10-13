import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Metadata for one file system object, read with `lstat` (symlinks are never followed).
public struct FileEntry: Sendable, Hashable {
    public var path: String
    /// Depth below the walk root (root = 0).
    public var depth: Int
    public var isDirectory: Bool
    public var isSymlink: Bool
    public var isRegularFile: Bool
    /// Logical size in bytes (st_size).
    public var logicalSize: Int64
    /// Bytes actually allocated on disk (st_blocks * 512).
    public var allocatedSize: Int64
    public var modified: Date
    public var accessed: Date
    public var inode: UInt64
    public var device: UInt64
    public var linkCount: Int
    public var ownerUID: UInt32

    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
}

/// What the visitor wants to do next.
public enum WalkDecision: Sendable {
    case `continue`
    /// Do not descend into this directory (only meaningful for directories).
    case skipChildren
    /// Abort the whole walk.
    case stop
}

/// Fast recursive directory traversal built on `opendir(3)`/`lstat(2)`.
///
/// * Never follows symlinks, never crosses into other volumes unless
///   `crossDevices` is set.
/// * Unreadable directories are skipped silently (counted in `WalkStats.errors`).
/// * Works identically on macOS and Linux so scanners are unit-testable.
public enum FileWalker {

    public struct Options: Sendable {
        public var includeHidden: Bool
        public var crossDevices: Bool
        /// Treat bundles/packages (".app", ".photoslibrary"…) as opaque leaves whose
        /// size is still accumulated, but whose children are not reported to the visitor.
        public var descendIntoPackages: Bool
        public var maxDepth: Int?

        public init(includeHidden: Bool = true, crossDevices: Bool = false, descendIntoPackages: Bool = true, maxDepth: Int? = nil) {
            self.includeHidden = includeHidden
            self.crossDevices = crossDevices
            self.descendIntoPackages = descendIntoPackages
            self.maxDepth = maxDepth
        }

        public static let `default` = Options()
    }

    public struct WalkStats: Sendable {
        public var files = 0
        public var directories = 0
        public var errors = 0
        public var stopped = false
    }

    static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "aplibrary", "fcpbundle",
        "logicx", "band", "imovielibrary", "bundle", "framework", "plugin", "kext", "xcarchive",
        "pages", "numbers", "key", "rtfd", "playground", "sparsebundle",
    ]

    /// Walks `root`, calling `visit` for every entry in pre-order (directories are
    /// reported before their contents). The root itself is reported at depth 0.
    @discardableResult
    public static func walk(
        _ root: String,
        options: Options = .default,
        visit: (FileEntry) -> WalkDecision
    ) -> WalkStats {
        var stats = WalkStats()
        guard let rootEntry = entry(at: root) else {
            stats.errors += 1
            return stats
        }
        let rootDevice = rootEntry.device
        // Explicit stack keeps memory flat on deep trees.
        var stack: [FileEntry] = [rootEntry]

        while let current = stack.popLast() {
            if current.isDirectory { stats.directories += 1 } else { stats.files += 1 }
            let decision = visit(current)
            if case .stop = decision {
                stats.stopped = true
                return stats
            }
            guard current.isDirectory, case .continue = decision else { continue }
            if let maxDepth = options.maxDepth, current.depth >= maxDepth { continue }
            if !options.crossDevices && current.device != rootDevice { continue }
            if !options.descendIntoPackages && current.depth > 0,
               packageExtensions.contains((current.name as NSString).pathExtension.lowercased()) {
                continue
            }

            guard let dir = opendir(current.path) else {
                stats.errors += 1
                continue
            }
            var children: [FileEntry] = []
            while let dirent = readdir(dir) {
                let name = withUnsafePointer(to: &dirent.pointee.d_name) { ptr -> String in
                    ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: dirent.pointee.d_name)) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }
                if !options.includeHidden && name.hasPrefix(".") { continue }
                let childPath = current.path == "/" ? "/" + name : current.path + "/" + name
                var st = stat()
                guard lstat(childPath, &st) == 0 else {
                    stats.errors += 1
                    continue
                }
                children.append(makeEntry(path: childPath, depth: current.depth + 1, st: st))
            }
            closedir(dir)
            // Reverse-sorted so popping yields alphabetical order.
            children.sort { $0.path > $1.path }
            stack.append(contentsOf: children)
        }
        return stats
    }

    /// Reads one entry with `lstat`. Returns nil if it does not exist.
    public static func entry(at path: String) -> FileEntry? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return makeEntry(path: path, depth: 0, st: st)
    }

    static func makeEntry(path: String, depth: Int, st: stat) -> FileEntry {
        let mode = UInt32(st.st_mode) & UInt32(S_IFMT)
        #if canImport(Darwin)
        let mtime = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
        let atime = Date(timeIntervalSince1970: TimeInterval(st.st_atimespec.tv_sec) + TimeInterval(st.st_atimespec.tv_nsec) / 1e9)
        #else
        let mtime = Date(timeIntervalSince1970: TimeInterval(st.st_mtim.tv_sec) + TimeInterval(st.st_mtim.tv_nsec) / 1e9)
        let atime = Date(timeIntervalSince1970: TimeInterval(st.st_atim.tv_sec) + TimeInterval(st.st_atim.tv_nsec) / 1e9)
        #endif
        return FileEntry(
            path: path,
            depth: depth,
            isDirectory: mode == UInt32(S_IFDIR),
            isSymlink: mode == UInt32(S_IFLNK),
            isRegularFile: mode == UInt32(S_IFREG),
            logicalSize: Int64(st.st_size),
            allocatedSize: Int64(st.st_blocks) * 512,
            modified: mtime,
            accessed: atime,
            inode: UInt64(st.st_ino),
            device: UInt64(truncatingIfNeeded: Int64(st.st_dev)),
            linkCount: Int(st.st_nlink),
            ownerUID: UInt32(st.st_uid)
        )
    }
}

/// Aggregate size information for a file or folder tree.
public struct DiskUsage: Sendable, Equatable {
    /// Allocated bytes, counting each hard-linked file once.
    public var bytes: Int64
    public var fileCount: Int
    public var newestModification: Date?
    public var newestAccess: Date?
    public var errors: Int

    public static let zero = DiskUsage(bytes: 0, fileCount: 0, newestModification: nil, newestAccess: nil, errors: 0)

    /// Measures a file or directory tree. Symlinks contribute only their own size.
    ///
    /// - Parameter deadline: stop measuring (returning a partial total) after this date.
    public static func measure(_ path: String, includeHidden: Bool = true, deadline: Date? = nil) -> DiskUsage {
        var usage = DiskUsage.zero
        var seenHardLinks = Set<FileIdentity>()
        let stats = FileWalker.walk(path, options: .init(includeHidden: includeHidden)) { entry in
            if let deadline, Date() > deadline { return .stop }
            if entry.isDirectory {
                usage.bytes += entry.allocatedSize
                return .continue
            }
            if entry.linkCount > 1 {
                let identity = FileIdentity(device: entry.device, inode: entry.inode)
                if !seenHardLinks.insert(identity).inserted { return .continue }
            }
            usage.bytes += entry.allocatedSize
            usage.fileCount += 1
            if usage.newestModification.map({ entry.modified > $0 }) ?? true { usage.newestModification = entry.modified }
            if usage.newestAccess.map({ entry.accessed > $0 }) ?? true { usage.newestAccess = entry.accessed }
            return .continue
        }
        usage.errors = stats.errors
        return usage
    }

    /// Lists the immediate children of a directory (hidden entries included unless excluded).
    public static func children(of path: String, includeHidden: Bool = true) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return names
            .filter { includeHidden || !$0.hasPrefix(".") }
            .sorted()
            .map { (path as NSString).appendingPathComponent($0) }
    }
}

public struct FileIdentity: Hashable, Sendable {
    public var device: UInt64
    public var inode: UInt64
    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

/// Expands simple glob patterns (`*`, `?`, `[...]` within a single path component)
/// into existing paths. `~` is expanded. Used by rule catalogs.
public enum PathGlob {
    public static func expand(_ pattern: String) -> [String] {
        let expanded = pattern.expandingTilde
        guard expanded.contains(where: { "*?[".contains($0) }) else {
            return FileManager.default.fileExists(atPath: expanded) || FileWalker.entry(at: expanded) != nil ? [expanded] : []
        }
        let components = expanded.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var current = ["/"]
        for component in components {
            var next: [String] = []
            let isPattern = component.contains(where: { "*?[".contains($0) })
            for base in current {
                if isPattern {
                    for child in DiskUsage.children(of: base) where matches((child as NSString).lastPathComponent, component) {
                        next.append(child)
                    }
                } else {
                    let candidate = (base as NSString).appendingPathComponent(component)
                    if FileWalker.entry(at: candidate) != nil { next.append(candidate) }
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current.sorted()
    }

    /// fnmatch-style match of a single name against a single-component pattern.
    public static func matches(_ name: String, _ pattern: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }
}
