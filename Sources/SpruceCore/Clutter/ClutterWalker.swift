import Foundation

/// Everything the Clutter walk collected from the chosen locations.
public struct ClutterWalkResult: Sendable {
    /// Regular files and packages big enough to matter for any Clutter tool
    /// (hard links reported once).
    public var files: [ClutterFile] = []
    /// Number of file system entries looked at.
    public var examined: Int = 0
    /// Cloud placeholders skipped without reading them.
    public var skippedPlaceholders: Int = 0
    /// Unreadable folders and entries.
    public var errors: Int = 0
    /// The walk was stopped before it finished.
    public var stopped: Bool = false

    public init() {}
}

/// Walks Clutter locations with the module's exclusions.
///
/// * built on `FileWalker` (lstat, never follows symlinks, never crosses volumes) with
///   `descendIntoPackages: false`: packages are measured and reported as one item;
/// * skips hidden items, `~/Library`, managed media libraries, dependency folders and
///   system folders at volume roots (`ClutterPaths.isExcluded`);
/// * skips cloud placeholders (data not on this Mac) and applications (Applications
///   module territory, and PathGuard refuses to remove them here anyway).
public struct ClutterWalker: Sendable {
    public var paths: ClutterPaths
    public var settings: ClutterScanSettings
    /// Platform check for cloud placeholders. The default treats a file with a length but
    /// no allocated blocks as a placeholder; the Mac layer also checks `SF_DATALESS`.
    public var isPlaceholder: @Sendable (FileEntry) -> Bool

    public init(paths: ClutterPaths = ClutterPaths(), settings: ClutterScanSettings = ClutterScanSettings(),
                isPlaceholder: (@Sendable (FileEntry) -> Bool)? = nil) {
        self.paths = paths
        self.settings = settings
        self.isPlaceholder = isPlaceholder ?? { entry in entry.logicalSize > 0 && entry.allocatedSize == 0 }
    }

    /// Walks every location (nested locations are walked once).
    public func walk(
        locations: [String],
        shouldContinue: () -> Bool = { true },
        progress: (_ examined: Int, _ current: String) -> Void = { _, _ in }
    ) -> ClutterWalkResult {
        var result = ClutterWalkResult()
        var seenLinks = Set<FileIdentity>()
        var seenPaths = Set<String>()
        let roots = ClutterPaths.collapsed(locations).flatMap(ClutterPaths.walkRoots(for:))
        let minimum = settings.walkMinimumSize

        for root in roots {
            if !shouldContinue() {
                result.stopped = true
                break
            }
            let options = FileWalker.Options(includeHidden: false, crossDevices: false, descendIntoPackages: false)
            let stats = FileWalker.walk(root, options: options) { entry in
                result.examined += 1
                if result.examined % 400 == 0 {
                    if !shouldContinue() { return .stop }
                    progress(result.examined, entry.path)
                }
                if entry.isSymlink { return .skipChildren }
                if entry.depth > 0 && paths.isExcluded(entry.path, name: entry.name, root: root) {
                    return .skipChildren
                }
                if entry.isDirectory {
                    guard entry.depth > 0, ClutterPaths.isPackage(name: entry.name) else { return .continue }
                    collectPackage(entry, minimum: minimum, into: &result, seen: &seenPaths)
                    return .skipChildren
                }
                guard entry.isRegularFile else { return .continue }
                if isPlaceholder(entry) {
                    result.skippedPlaceholders += 1
                    return .continue
                }
                guard entry.logicalSize > 0 else { return .continue }
                let inDownloads = paths.isInDownloads(entry.path)
                guard inDownloads || entry.logicalSize >= minimum else { return .continue }
                if entry.linkCount > 1, !seenLinks.insert(FileIdentity(device: entry.device, inode: entry.inode)).inserted {
                    return .continue
                }
                guard seenPaths.insert(entry.path).inserted else { return .continue }
                result.files.append(file(from: entry))
                return .continue
            }
            result.errors += stats.errors
            if stats.stopped {
                result.stopped = true
                break
            }
        }
        return result
    }

    /// Lists the top-level items of `~/Downloads` (files, packages and folders, each as
    /// one item with its full size). Hidden items and placeholders are skipped.
    public func listDownloads(shouldContinue: () -> Bool = { true }) -> [ClutterFile] {
        let folder = paths.downloads
        var items: [ClutterFile] = []
        for child in DiskUsage.children(of: folder, includeHidden: false) {
            if !shouldContinue() { break }
            guard let entry = FileWalker.entry(at: child), !entry.isSymlink else { continue }
            let name = entry.name
            if ClutterPaths.isManagedLibrary(name: name) { continue }
            if (name as NSString).pathExtension.lowercased() == "app" { continue }
            if entry.isDirectory {
                let usage = DiskUsage.measure(child, includeHidden: true)
                let isPackage = ClutterPaths.isPackage(name: name)
                items.append(ClutterFile(
                    path: child, size: usage.bytes, logicalSize: usage.bytes,
                    modified: max(entry.modified, usage.newestModification ?? entry.modified),
                    accessed: max(entry.accessed, usage.newestAccess ?? entry.accessed),
                    inode: entry.inode, device: entry.device, linkCount: entry.linkCount,
                    isPackage: isPackage, isFolder: !isPackage, isCloud: paths.isCloud(child)))
            } else if entry.isRegularFile {
                if isPlaceholder(entry) { continue }
                items.append(file(from: entry))
            }
        }
        return items
    }

    private func collectPackage(_ entry: FileEntry, minimum: Int64, into result: inout ClutterWalkResult,
                                seen: inout Set<String>) {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        // Apps belong to the Applications module; `.download` bundles are in-progress
        // Safari downloads, which only the Downloads tool lists.
        guard ext != "app", ext != "download" else { return }
        let usage = DiskUsage.measure(entry.path, includeHidden: true)
        guard usage.bytes >= minimum, seen.insert(entry.path).inserted else { return }
        result.files.append(ClutterFile(
            path: entry.path, size: usage.bytes, logicalSize: usage.bytes,
            modified: max(entry.modified, usage.newestModification ?? entry.modified),
            accessed: max(entry.accessed, usage.newestAccess ?? entry.accessed),
            inode: entry.inode, device: entry.device, linkCount: entry.linkCount,
            isPackage: true, isCloud: paths.isCloud(entry.path)))
    }

    private func file(from entry: FileEntry) -> ClutterFile {
        ClutterFile(
            path: entry.path, size: entry.allocatedSize, logicalSize: entry.logicalSize,
            modified: entry.modified, accessed: entry.accessed,
            inode: entry.inode, device: entry.device, linkCount: entry.linkCount,
            isCloud: paths.isCloud(entry.path))
    }
}
