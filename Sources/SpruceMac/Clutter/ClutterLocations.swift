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
        return options.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// An option for any folder (standard folders keep their nice names).
    public static func option(for path: String) -> ClutterLocationOption {
        let key = canonical(path)
        if let known = standard.first(where: { canonical($0.path) == key }) { return known }
        if let volume = volumes().first(where: { canonical($0.path) == key }) { return volume }
        let absolute = path.expandingTilde
        let name = absolute == "/" ? "Macintosh HD" : (absolute as NSString).lastPathComponent
        return ClutterLocationOption(path: absolute.abbreviatingHome, title: name, symbol: "folder", kind: .folder)
    }

    /// Whether a location still exists (volumes get unmounted, folders get renamed).
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
        let names = paths.map { option(for: $0).title }
        switch names.count {
        case 0: return "No location"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.count) locations"
        }
    }
}
