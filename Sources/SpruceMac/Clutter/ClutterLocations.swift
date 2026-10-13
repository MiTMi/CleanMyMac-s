import Foundation
import SpruceCore

/// A place Clutter can scan.
public struct ClutterLocationOption: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case home, desktop, documents, downloads, volume, folder
    }

    /// Path as stored in settings (`~` form for folders in the home folder).
    public var path: String
    public var title: String
    public var symbol: String
    public var kind: Kind
    /// Free space for volumes ("212 GB free").
    public var detail: String?

    public init(path: String, title: String, symbol: String, kind: Kind, detail: String? = nil) {
        self.path = path
        self.title = title
        self.symbol = symbol
        self.kind = kind
        self.detail = detail
    }

    public var id: String { ClutterLocations.canonical(path) }
    public var absolutePath: String { path.expandingTilde }
}

/// The standard Clutter locations, mounted volumes and helpers for custom folders.
public enum ClutterLocations {
    /// Home, Desktop, Documents and Downloads.
    public static var standard: [ClutterLocationOption] {
        [
            ClutterLocationOption(path: "~", title: "Home", symbol: "house", kind: .home),
            ClutterLocationOption(path: "~/Desktop", title: "Desktop", symbol: "menubar.dock.rectangle", kind: .desktop),
            ClutterLocationOption(path: "~/Documents", title: "Documents", symbol: "doc", kind: .documents),
            ClutterLocationOption(path: "~/Downloads", title: "Downloads", symbol: "arrow.down.circle", kind: .downloads),
        ]
    }

    /// External and secondary volumes mounted under /Volumes (Time Machine and hidden
    /// volumes excluded).
    ///
    /// Blocking: it asks every mounted volume for its free space, which can take a while
    /// (purgeable-space accounting) and hangs on a disk that stopped answering (a sleeping
    /// NAS, a stale SMB mount). Call it off the main thread — views should use
    /// `loadStatus(for:)` and keep the result. The list is also remembered for `option(for:)`.
    public static func volumes() -> [ClutterLocationOption] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsBrowsableKey, .volumeIsRootFileSystemKey,
                                      .volumeIsRemovableKey, .volumeIsInternalKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var options: [ClutterLocationOption] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix("/Volumes/"), !path.contains("/.timemachine"),
                  !path.lowercased().contains("com.apple.timemachine") else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.volumeIsRootFileSystem == true || values?.volumeIsBrowsable == false { continue }
            let name = values?.volumeLocalizedName ?? url.lastPathComponent
            if name.hasPrefix("Backups of ") { continue }
            var detail: String?
            if let free = values?.volumeAvailableCapacityForImportantUsage, free > 0 {
                detail = "\(ByteFormat.string(free)) free"
            } else if let free = values?.volumeAvailableCapacity, free > 0 {
                detail = "\(ByteFormat.string(Int64(free))) free"
            }
            let removable = values?.volumeIsRemovable == true || values?.volumeIsInternal == false
            options.append(ClutterLocationOption(path: path, title: name,
                                                 symbol: removable ? "externaldrive" : "internaldrive",
                                                 kind: .volume, detail: detail))
        }
        let sorted = options.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        knownVolumes.store(sorted)
        return sorted
    }

    /// An option for any folder (standard folders keep their nice names, mounted volumes
    /// their volume names and free space).
    ///
    /// Never touches the file system, so views may call it while rendering: volumes come
    /// from the last `volumes()` / `status(for:)` probe.
    public static func option(for path: String) -> ClutterLocationOption {
        option(for: path, volumes: knownVolumes.volumes)
    }

    /// `option(for:)` against a given volume list.
    static func option(for path: String, volumes: [ClutterLocationOption]) -> ClutterLocationOption {
        let key = canonical(path)
        if let known = standard.first(where: { canonical($0.path) == key }) { return known }
        if let volume = volumes.first(where: { $0.id == key }) { return volume }
        let absolute = ClutterPaths.standardized(path.expandingTilde)
        if absolute == "/" {
            return ClutterLocationOption(path: "/", title: "Macintosh HD", symbol: "internaldrive", kind: .folder)
        }
        let name = (absolute as NSString).lastPathComponent
        // A disk that isn't mounted (or wasn't probed yet) still looks like a disk.
        let isVolumeRoot = (absolute as NSString).deletingLastPathComponent.lowercased() == "/volumes"
        return ClutterLocationOption(path: absolute.abbreviatingHome, title: name,
                                     symbol: isVolumeRoot ? "externaldrive" : "folder",
                                     kind: isVolumeRoot ? .volume : .folder)
    }

    /// Probes mounted volumes and `paths` (blocking — call off the main thread; see
    /// `loadStatus(for:)`).
    public static func status(for paths: [String]) -> ClutterLocationStatus {
        let mounted = ClutterLocations.volumes()
        var options: [String: ClutterLocationOption] = [:]
        var missing = Set<String>()
        for path in paths {
            let key = canonical(path)
            guard options[key] == nil else { continue }
            options[key] = option(for: path, volumes: mounted)
            if !exists(path) { missing.insert(key) }
        }
        return ClutterLocationStatus(volumes: mounted, options: options, missing: missing)
    }

    /// `status(for:)` on a background queue. Probes run one at a time, so a disk that
    /// stops answering delays the next probe instead of stalling the main thread or
    /// tying up more threads.
    public static func loadStatus(for paths: [String]) async -> ClutterLocationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<ClutterLocationStatus, Never>) in
            ClutterLocations.probeQueue.async {
                continuation.resume(returning: ClutterLocations.status(for: paths))
            }
        }
    }

    /// Whether a location still exists (volumes get unmounted, folders get renamed).
    /// Blocking on a disk that stopped answering: views should read `ClutterLocationStatus`.
    public static func exists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path.expandingTilde, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Comparable form: absolute, standardized, lowercased.
    public static func canonical(_ path: String) -> String {
        ClutterPaths.standardized(path.expandingTilde).lowercased()
    }

    /// Settings form: `~` for the home folder and anything inside it.
    public static func storedForm(_ path: String) -> String {
        ClutterPaths.standardized(path.expandingTilde).abbreviatingHome
    }

    /// Short description of a set of locations ("Home", "Documents and Photos SSD", "3 locations").
    public static func summary(_ paths: [String]) -> String {
        summary(titles: paths.map { option(for: $0).title })
    }

    /// `summary(_:)` from location titles.
    public static func summary(titles names: [String]) -> String {
        switch names.count {
        case 0: return "No location"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.count) locations"
        }
    }

    /// Serial queue for location probes.
    private static let probeQueue = DispatchQueue(label: "app.spruce.clutter.locations", qos: .userInitiated)

    /// The last mounted-volume list.
    private static let knownVolumes = ClutterKnownVolumes()
}

/// What Clutter knows about its locations right now: mounted volumes, a display option
/// for every probed location and which of them are missing. Built off the main thread by
/// `ClutterLocations.loadStatus(for:)`, so views read it without touching the disk.
public struct ClutterLocationStatus: Equatable, Sendable {
    /// Mounted volumes, sorted by name.
    public var volumes: [ClutterLocationOption]
    /// Display options by canonical path (`ClutterLocations.canonical`).
    public var options: [String: ClutterLocationOption]
    /// Canonical paths that were probed and are missing (or aren't folders).
    public var missing: Set<String>

    public init(volumes: [ClutterLocationOption] = [], options: [String: ClutterLocationOption] = [:],
                missing: Set<String> = []) {
        self.volumes = volumes
        self.options = options
        self.missing = missing
    }

    /// Whether `path` was available when probed. Paths not probed yet count as available
    /// (the scan checks again before walking).
    public func isAvailable(_ path: String) -> Bool {
        !missing.contains(ClutterLocations.canonical(path))
    }

    /// Display option for `path` (no file-system access).
    public func option(for path: String) -> ClutterLocationOption {
        options[ClutterLocations.canonical(path)] ?? ClutterLocations.option(for: path, volumes: volumes)
    }
}

/// Lock-protected mounted-volume list shared by every thread.
private final class ClutterKnownVolumes: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ClutterLocationOption] = []

    var volumes: [ClutterLocationOption] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ volumes: [ClutterLocationOption]) {
        lock.lock()
        storage = volumes
        lock.unlock()
    }
}
