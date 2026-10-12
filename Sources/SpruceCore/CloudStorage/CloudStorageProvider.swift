import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Provider kinds

/// The cloud services Spruce recognises from their local folders.
///
/// Spruce never signs in to any account: it only looks at the folders the providers'
/// own Mac apps keep on disk, and only ever frees *local copies* of files.
public enum CloudStorageProviderKind: String, Codable, Sendable, CaseIterable, Hashable {
    case iCloudDrive
    case googleDrive
    case oneDrive
    case dropbox
    case box
    case pCloud
    case nextcloud
    /// Any other app that uses Apple's File Provider (`~/Library/CloudStorage/<Name>-…`).
    case otherFileProvider

    /// User-facing service name.
    public var title: String {
        switch self {
        case .iCloudDrive: return "iCloud Drive"
        case .googleDrive: return "Google Drive"
        case .oneDrive: return "OneDrive"
        case .dropbox: return "Dropbox"
        case .box: return "Box"
        case .pCloud: return "pCloud"
        case .nextcloud: return "Nextcloud"
        case .otherFileProvider: return "Cloud Folder"
        }
    }

    /// Generic SF Symbol for the service (never a brand mark).
    public var symbol: String {
        switch self {
        case .iCloudDrive: return "icloud.fill"
        case .googleDrive: return "externaldrive.fill.badge.icloud"
        case .oneDrive: return "cloud.fill"
        case .dropbox: return "shippingbox.fill"
        case .box: return "archivebox.fill"
        case .pCloud: return "cloud.circle.fill"
        case .nextcloud: return "server.rack"
        case .otherFileProvider: return "externaldrive.connected.to.line.below.fill"
        }
    }

    /// What the provider's own Finder command for freeing a download is usually called.
    public var finderCommandHint: String {
        switch self {
        case .iCloudDrive: return "Remove Download"
        case .oneDrive: return "Free Up Space"
        case .dropbox: return "Make online-only"
        case .googleDrive, .box, .pCloud, .nextcloud, .otherFileProvider: return "Remove Download"
        }
    }
}

/// How a provider keeps files on this Mac, which decides what "Free Up Locally" can do.
public enum CloudStorageMechanism: String, Codable, Sendable, Hashable {
    /// iCloud Drive (CloudDocs). Downloads can be removed with `evictUbiquitousItem`
    /// or `brctl evict`.
    case iCloud
    /// An app built on Apple's File Provider (`~/Library/CloudStorage`). Files can be
    /// online-only placeholders; downloads can be removed when the provider allows it.
    case fileProvider
    /// A legacy full-sync folder (`~/Dropbox`, `~/Google Drive`…). The app keeps every
    /// file on the Mac, so there are no local copies to free from here.
    case syncFolder

    public var canFreeUpLocally: Bool { self != .syncFolder }

    /// One-line description for provider cards.
    public var explanation: String {
        switch self {
        case .iCloud:
            return "Files you don't use can live only in iCloud and download again when opened."
        case .fileProvider:
            return "Managed by the provider's app through macOS. Online-only files take no space here."
        case .syncFolder:
            return "An older sync folder: the app keeps every file on this Mac. Switch it to online-only files in the app to save space."
        }
    }
}

/// Which part of a provider's folder a file lives in. Some parts deserve extra care.
public enum CloudStorageArea: String, Codable, Sendable, Hashable {
    /// The ordinary drive contents.
    case drive
    /// iCloud's synced Desktop & Documents folders ("essential" user files).
    case desktopAndDocuments
    /// The user-visible `Documents` folder of an app's own iCloud container.
    case appFolder
}

// MARK: - Provider

/// One cloud folder found on this Mac.
public struct CloudStorageProvider: Identifiable, Hashable, Sendable, Codable {
    public var kind: CloudStorageProviderKind
    public var mechanism: CloudStorageMechanism
    /// The provider's root folder (absolute, standardized).
    public var rootPath: String
    /// Account or organisation shown next to the name ("me@example.com", "Personal").
    public var account: String?
    /// Name used for unknown File Provider apps (derived from the folder name).
    public var customName: String?
    /// Extra folders scanned for this provider, e.g. the `Documents` folders of apps'
    /// iCloud containers that Finder shows inside iCloud Drive.
    public var additionalRoots: [String]

    public var id: String { rootPath }

    public init(kind: CloudStorageProviderKind, mechanism: CloudStorageMechanism, rootPath: String,
                account: String? = nil, customName: String? = nil, additionalRoots: [String] = []) {
        self.kind = kind
        self.mechanism = mechanism
        self.rootPath = (rootPath as NSString).standardizingPath
        self.account = account
        self.customName = customName
        self.additionalRoots = additionalRoots.map { ($0 as NSString).standardizingPath }
    }

    /// "Google Drive", "Dropbox", or the custom app name.
    public var name: String {
        if kind == .otherFileProvider, let customName, !customName.isEmpty { return customName }
        return kind.title
    }

    /// "Google Drive · me@example.com" style title.
    public var displayName: String {
        guard let account, !account.isEmpty else { return name }
        return "\(name) · \(account)"
    }

    /// Short location line: "~/Library/CloudStorage/Dropbox".
    public var locationLine: String { rootPath.abbreviatingHome }

    /// Every folder the scanner walks, with the area it belongs to.
    public var scanRoots: [(path: String, area: CloudStorageArea)] {
        [(rootPath, CloudStorageArea.drive)] + additionalRoots.map { ($0, CloudStorageArea.appFolder) }
    }

    /// True when `path` lies strictly inside one of this provider's scanned folders.
    public func contains(_ path: String) -> Bool {
        let key = CloudStoragePath.key(path)
        return ([rootPath] + additionalRoots).contains { root in
            CloudStoragePath.isStrictlyInside(key, CloudStoragePath.key(root))
        }
    }
}

// MARK: - Discovery

/// Finds cloud folders under a home directory. Pure file system reads (no symlinks are
/// followed), so it is unit-testable with a temporary "home".
public enum CloudStorageDiscovery {

    /// `~/Library/Mobile Documents` — iCloud's local store.
    public static func mobileDocumentsPath(home: String) -> String {
        (home as NSString).appendingPathComponent("Library/Mobile Documents")
    }

    /// `~/Library/Mobile Documents/com~apple~CloudDocs` — iCloud Drive itself.
    public static func iCloudDrivePath(home: String) -> String {
        (mobileDocumentsPath(home: home) as NSString).appendingPathComponent("com~apple~CloudDocs")
    }

    /// `~/Library/CloudStorage` — File Provider roots.
    public static func cloudStoragePath(home: String) -> String {
        (home as NSString).appendingPathComponent("Library/CloudStorage")
    }

    /// Legacy full-sync folders in the home folder, with the marker that proves the
    /// folder belongs to the app (nil = the folder name alone is enough).
    static let legacyFolders: [(name: String, kind: CloudStorageProviderKind, marker: [String]?)] = [
        ("Dropbox", .dropbox, [".dropbox", ".dropbox.cache"]),
        ("Google Drive", .googleDrive, nil),
        ("OneDrive", .oneDrive, nil),
        ("Box Sync", .box, nil),
    ]

    /// Classifies one child of `~/Library/CloudStorage` by its folder name.
    /// Returns nil for names that are not provider roots (hidden entries).
    public static func classify(folderName name: String) -> (kind: CloudStorageProviderKind, account: String?, customName: String?)? {
        guard !name.isEmpty, !name.hasPrefix(".") else { return nil }
        let (prefix, suffix) = split(name)
        let lowerPrefix = prefix.lowercased()
        switch lowerPrefix {
        case "googledrive", "google drive":
            return (.googleDrive, suffix, nil)
        case "onedrive":
            return (.oneDrive, suffix, nil)
        case "dropbox":
            return (.dropbox, suffix, nil)
        case "box":
            // Box's File Provider folder is "Box-Box"; the repeated name is not an account.
            return (.box, suffix?.lowercased() == "box" ? nil : suffix, nil)
        case "pcloud", "pclouddrive", "pcloud drive":
            return (.pCloud, suffix, nil)
        case "nextcloud":
            return (.nextcloud, suffix, nil)
        default:
            return (.otherFileProvider, suffix, prefix)
        }
    }

    /// Splits "GoogleDrive-me@x.com" → ("GoogleDrive", "me@x.com"), "Dropbox (Team)" →
    /// ("Dropbox", "Team"), "Dropbox" → ("Dropbox", nil).
    static func split(_ name: String) -> (String, String?) {
        if let open = name.firstIndex(of: "("), name.hasSuffix(")"), open > name.startIndex {
            let prefix = name[..<open].trimmingCharacters(in: .whitespaces)
            let inner = name[name.index(after: open)..<name.index(before: name.endIndex)]
                .trimmingCharacters(in: .whitespaces)
            return (prefix, inner.isEmpty ? nil : inner)
        }
        if let dash = name.firstIndex(of: "-"), dash > name.startIndex {
            let prefix = String(name[..<dash])
            let rest = String(name[name.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
            return (prefix, rest.isEmpty ? nil : rest)
        }
        return (name, nil)
    }

    /// Every cloud folder found under `home`, iCloud Drive first, then File Provider
    /// roots alphabetically, then legacy sync folders.
    public static func discover(home: String = NSHomeDirectory()) -> [CloudStorageProvider] {
        let home = (home as NSString).standardizingPath
        var providers: [CloudStorageProvider] = []

        let iCloud = iCloudDrivePath(home: home)
        if CloudStoragePath.isRealDirectory(iCloud) {
            providers.append(CloudStorageProvider(kind: .iCloudDrive, mechanism: .iCloud, rootPath: iCloud,
                                                  additionalRoots: iCloudAppFolders(home: home)))
        }

        let storage = cloudStoragePath(home: home)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: storage)) ?? []).sorted {
            $0.lowercased() < $1.lowercased()
        }
        for name in names {
            let path = (storage as NSString).appendingPathComponent(name)
            guard CloudStoragePath.isRealDirectory(path), let info = classify(folderName: name) else { continue }
            providers.append(CloudStorageProvider(kind: info.kind, mechanism: .fileProvider, rootPath: path,
                                                  account: info.account, customName: info.customName))
        }

        for legacy in legacyFolders {
            let path = (home as NSString).appendingPathComponent(legacy.name)
            guard CloudStoragePath.isRealDirectory(path) else { continue }
            if let markers = legacy.marker {
                let hasMarker = markers.contains { FileWalker.entry(at: (path as NSString).appendingPathComponent($0)) != nil }
                guard hasMarker else { continue }
            }
            // Skip when a File Provider root of the same service already exists and the
            // legacy folder is empty (left behind after the app migrated).
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: path))?.filter { !$0.hasPrefix(".") } ?? []
            if entries.isEmpty && providers.contains(where: { $0.kind == legacy.kind }) { continue }
            providers.append(CloudStorageProvider(kind: legacy.kind, mechanism: .syncFolder, rootPath: path))
        }
        return providers
    }

    /// The `Documents` folders of apps' iCloud containers (Pages, TextEdit, …), which
    /// Finder shows as app folders inside iCloud Drive. App-private container data
    /// outside `Documents` is never included.
    public static func iCloudAppFolders(home: String) -> [String] {
        let base = mobileDocumentsPath(home: home)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []).sorted()
        var folders: [String] = []
        for name in names where !name.hasPrefix(".") && name != "com~apple~CloudDocs" {
            let documents = ((base as NSString).appendingPathComponent(name) as NSString).appendingPathComponent("Documents")
            if CloudStoragePath.isRealDirectory(documents) { folders.append(documents) }
        }
        return folders
    }

    /// Friendly name of an app container folder: "iCloud~com~apple~Pages/Documents" → "Pages".
    public static func appFolderName(_ documentsPath: String) -> String {
        let container = ((documentsPath as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let last = container.split(separator: "~").last.map(String.init) ?? container
        return last.isEmpty ? container : last
    }
}

// MARK: - Paths

/// Path helpers shared by discovery, the scanner and the Mac engine.
public enum CloudStoragePath {
    /// Case-insensitive comparison key (APFS is case-insensitive by default).
    public static func key(_ path: String) -> String {
        var p = (path as NSString).standardizingPath.lowercased()
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    public static func isStrictlyInside(_ pathKey: String, _ rootKey: String) -> Bool {
        if rootKey == "/" { return pathKey != "/" }
        return pathKey.hasPrefix(rootKey + "/")
    }

    /// A directory that is not a symlink (checked with `lstat`).
    public static func isRealDirectory(_ path: String) -> Bool {
        guard let entry = FileWalker.entry(at: path) else { return false }
        return entry.isDirectory && !entry.isSymlink
    }

    /// Package extensions treated as single documents (never split or partly freed).
    public static let packageExtensions: Set<String> = [
        "pages", "numbers", "key", "rtfd", "logicx", "band", "fcpbundle", "fcpxbundle", "imovielibrary",
        "photoslibrary", "musiclibrary", "tvlibrary", "aplibrary", "photolibrary", "app", "bundle",
        "framework", "plugin", "sparsebundle", "xcarchive", "playground", "scriptd", "graffle", "sketch",
        "lpdf", "nib", "xcodeproj", "xcworkspace", "dtbase2", "dtsparse", "scrivx", "scriv", "oo3",
        "mindnode", "ulysses", "textbundle", "epub", "dmgpart", "lrlibrary", "lrdata", "cptx",
    ]

    public static func isPackage(name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && packageExtensions.contains(ext)
    }

    /// Provider-internal folders that never count as the user's files.
    public static let excludedNames: Set<String> = [
        ".dropbox.cache", ".shortcut-targets-by-id", ".Trash", ".Trashes", ".tmp.drivedownload",
        ".tmp.driveupload", ".fseventsd", ".Spotlight-V100", ".DocumentRevisions-V100", ".TemporaryItems",
        ".Encrypted", ".file-revisions-by-id",
    ]

    /// Tiny Finder bookkeeping files that never belong in a file list.
    public static func isBookkeeping(name: String) -> Bool {
        name == ".DS_Store" || name == "Icon\r" || name == ".localized" || name == ".dropbox"
            || name.hasPrefix("._")
    }
}
