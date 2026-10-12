import Foundation

/// Path rules shared by the walk, smart selection and the Downloads tool.
///
/// All checks are case-insensitive (APFS default) and work on standardized paths.
public struct ClutterPaths: Sendable {
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = Self.standardized(home)
    }

    public var downloads: String { home + "/Downloads" }
    public var desktop: String { home + "/Desktop" }
    public var documents: String { home + "/Documents" }
    public var library: String { home + "/Library" }
    public var trash: String { home + "/.Trash" }

    // MARK: Location tests

    /// Inside `~/Downloads` (any depth).
    public func isInDownloads(_ path: String) -> Bool {
        Self.isInside(path, downloads)
    }

    /// Inside the Trash, a temporary folder or Downloads: places a copy is least
    /// likely to be "the original" the user wants to keep.
    public func isTransient(_ path: String) -> Bool {
        if isInDownloads(path) || Self.isInside(path, trash) { return true }
        if Self.isInside(path, home) { return false }
        let key = Self.key(path)
        if key.contains("/.trashes/") { return true }
        for temp in ["/private/tmp", "/tmp", "/private/var/folders", "/var/folders", "/private/var/tmp"]
        where Self.isInside(path, temp) {
            return true
        }
        return false
    }

    /// Inside iCloud Drive or a File Provider root (Dropbox, Google Drive, OneDrive…).
    public func isCloud(_ path: String) -> Bool {
        Self.isInside(path, library + "/Mobile Documents") || Self.isInside(path, library + "/CloudStorage")
    }

    // MARK: Walk exclusions

    /// Package extensions treated as single items (never descended into).
    public static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "appex", "xpc", "prefpane", "qlgenerator", "mdimporter",
        "saver", "sparsebundle", "fcpbundle", "logicx", "band", "pages", "numbers", "key", "rtfd", "playground",
        "xcarchive", "xcodeproj", "xcworkspace", "utm", "pvm", "vmwarevm", "lrdata", "lrlibrary", "dtBase2",
        "scriv", "sketch", "photoboothlibrary", "aplibrary", "imovielibrary", "theater", "movpkg", "download",
        "docset", "nib", "storyboardc", "momd", "car",
    ].reduce(into: Set<String>()) { $0.insert($1.lowercased()) }

    /// Media libraries managed by their apps; files inside are never touched and the
    /// libraries themselves are not offered for removal.
    public static let managedLibraryExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "aplibrary", "migratedphotolibrary",
        "photoboothlibrary", "imovielibrary",
    ]

    /// Folder names skipped anywhere (developer dependency trees and backup stores).
    public static let skippedFolderNames: Set<String> = [
        "node_modules", "backups.backupdb", "bower_components", "deriveddata", "__pycache__", "venv",
    ]

    /// Top-level folders of a startup or external volume that are system territory.
    public static let systemRootFolders: Set<String> = [
        "system", "library", "applications", "private", "usr", "bin", "sbin", "dev", "cores", "opt", "etc",
        "var", "tmp", "volumes", "network", "home", "net",
    ]

    public static func isPackage(name: String) -> Bool {
        packageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    public static func isManagedLibrary(name: String) -> Bool {
        managedLibraryExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Whether the walk should skip `path` (a directory, or a file for hidden checks)
    /// when scanning below `root`.
    ///
    /// * hidden (dot) items, except the root itself;
    /// * `~/Library` (Cleanup's territory, iCloud Drive and app data) unless the user
    ///   chose a folder inside it;
    /// * Photos/Music/TV libraries and the media folders the Music and TV apps manage;
    /// * dependency and backup folders (`node_modules`, `Backups.backupdb`…);
    /// * system folders at the top of a volume.
    public func isExcluded(_ path: String, name: String, root: String) -> Bool {
        let standardizedRoot = Self.standardized(root)
        if Self.key(path) == Self.key(standardizedRoot) { return false }
        if name.hasPrefix(".") { return true }
        let lowerName = name.lowercased()
        if Self.skippedFolderNames.contains(lowerName) { return true }
        if Self.isManagedLibrary(name: name) { return true }
        if Self.isInside(path, library) || Self.key(path) == Self.key(library) {
            if !(Self.isInside(standardizedRoot, library) || Self.key(standardizedRoot) == Self.key(library)) {
                return true
            }
        }
        for managed in [home + "/Music/Music", home + "/Music/iTunes", home + "/Movies/TV"]
        where Self.key(path) == Self.key(managed) {
            return true
        }
        // Top-level system folders when scanning a volume root ("/" or "/Volumes/X").
        let parent = (path as NSString).deletingLastPathComponent
        if Self.isVolumeRoot(parent) && Self.key(parent) == Self.key(standardizedRoot)
            && Self.systemRootFolders.contains(lowerName) {
            return true
        }
        // Other users' home folders.
        if Self.key(parent) == "/users" && Self.key(path) != Self.key(home) && lowerName != "shared" {
            return true
        }
        return false
    }

    /// "/" or "/Volumes/<name>".
    public static func isVolumeRoot(_ path: String) -> Bool {
        let key = Self.key(path)
        if key == "/" { return true }
        let comps = key.split(separator: "/")
        return comps.count == 2 && comps[0] == "volumes"
    }

    /// The folders actually walked for a chosen location. The startup volume root is
    /// mapped to `/Users` because the system volume and the data volume are separate
    /// devices (the walk never crosses devices).
    public static func walkRoots(for location: String) -> [String] {
        let standardized = Self.standardized(location.expandingTilde)
        if standardized == "/" { return ["/Users"] }
        return [standardized]
    }

    // MARK: Path math

    public static func standardized(_ path: String) -> String {
        var p = (path.expandingTilde as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func key(_ path: String) -> String {
        var p = path.lowercased()
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// True when `path` is strictly inside `folder`.
    public static func isInside(_ path: String, _ folder: String) -> Bool {
        let f = key(folder)
        let p = key(path)
        if f == "/" { return p != "/" }
        return p.hasPrefix(f + "/")
    }

    /// True when `path` is `folder` or inside it.
    public static func isInsideOrEqual(_ path: String, _ folder: String) -> Bool {
        key(path) == key(folder) || isInside(path, folder)
    }

    /// Removes locations nested inside other chosen locations (scanning `~` and
    /// `~/Documents` walks Documents once).
    public static func collapsed(_ locations: [String]) -> [String] {
        let all = locations.map { standardized($0.expandingTilde) }
        var result: [String] = []
        for (i, path) in all.enumerated() {
            let covered = all.enumerated().contains { j, other in
                j != i && (isInside(path, other) || (j < i && key(path) == key(other)))
            }
            if !covered { result.append(path) }
        }
        return result
    }
}
