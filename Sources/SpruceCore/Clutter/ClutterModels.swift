import Foundation

// MARK: - Tools

/// The four Clutter tools. `toolID` values are the navigation identifiers from the
/// architecture contract (`clutter.largeOld`, …).
public enum ClutterTool: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case largeOld
    case duplicates
    case similarImages
    case downloads

    public var id: String { rawValue }

    public var toolID: String { "clutter.\(rawValue)" }

    public init?(toolID: String) {
        guard toolID.hasPrefix("clutter.") else { return nil }
        self.init(rawValue: String(toolID.dropFirst("clutter.".count)))
    }

    public var title: String {
        switch self {
        case .largeOld: return "Large & Old Files"
        case .duplicates: return "Duplicates"
        case .similarImages: return "Similar Images"
        case .downloads: return "Downloads"
        }
    }

    public var symbol: String {
        switch self {
        case .largeOld: return "archivebox"
        case .duplicates: return "doc.on.doc"
        case .similarImages: return "photo.on.rectangle.angled"
        case .downloads: return "arrow.down.circle"
        }
    }

    /// One-line description for idle screens and tool headers.
    public var summary: String {
        switch self {
        case .largeOld: return "Big files and files you haven't opened in months."
        case .duplicates: return "Identical copies of the same file, compared by content."
        case .similarImages: return "Photos and pictures that look almost the same."
        case .downloads: return "Installers, archives and other one-time downloads."
        }
    }
}

// MARK: - Kinds

/// What a file is, for grouping Large & Old Files and choosing icons.
public enum ClutterKind: String, CaseIterable, Codable, Sendable, Hashable {
    case movies
    case music
    case pictures
    case documents
    case archives
    case installers
    case virtualMachines
    case folders
    case other

    public var title: String {
        switch self {
        case .movies: return "Movies"
        case .music: return "Music & Audio"
        case .pictures: return "Pictures"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .installers: return "Installers & Disk Images"
        case .virtualMachines: return "Virtual Machines"
        case .folders: return "Folders & Bundles"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .movies: return "film"
        case .music: return "music.note"
        case .pictures: return "photo"
        case .documents: return "doc.text"
        case .archives: return "doc.zipper"
        case .installers: return "externaldrive"
        case .virtualMachines: return "desktopcomputer"
        case .folders: return "folder"
        case .other: return "doc"
        }
    }
}

// MARK: - Files

/// One file (or package treated as a single item) found by the Clutter walk.
public struct ClutterFile: Sendable, Hashable, Identifiable, Codable {
    public var path: String
    /// Bytes allocated on disk (what removing it frees). For packages, the whole tree.
    public var size: Int64
    /// Logical length in bytes (st_size). Used to bucket duplicate candidates.
    public var logicalSize: Int64
    public var modified: Date
    public var accessed: Date
    /// Creation (birth) date when the platform layer knows it.
    public var created: Date?
    /// Spotlight's `kMDItemLastUsedDate` (set when the file is opened via Launch Services).
    public var lastOpened: Date?
    /// When the file arrived in its folder (`kMDItemDateAdded`), if known.
    public var dateAdded: Date?
    public var inode: UInt64
    public var device: UInt64
    public var linkCount: Int
    /// A directory treated as one item (bundle/package such as `.sparsebundle`).
    public var isPackage: Bool
    /// A plain folder listed as one item (only in Downloads).
    public var isFolder: Bool
    /// Lives in a cloud-synced location (iCloud Drive, File Provider roots).
    public var isCloud: Bool
    /// A cloud placeholder whose data is not on this Mac (never read, frees nothing).
    public var isPlaceholder: Bool
    public var kind: ClutterKind

    public init(
        path: String,
        size: Int64,
        logicalSize: Int64? = nil,
        modified: Date,
        accessed: Date? = nil,
        created: Date? = nil,
        lastOpened: Date? = nil,
        dateAdded: Date? = nil,
        inode: UInt64 = 0,
        device: UInt64 = 0,
        linkCount: Int = 1,
        isPackage: Bool = false,
        isFolder: Bool = false,
        isCloud: Bool = false,
        isPlaceholder: Bool = false,
        kind: ClutterKind? = nil
    ) {
        self.path = path
        self.size = size
        self.logicalSize = logicalSize ?? size
        self.modified = modified
        self.accessed = accessed ?? modified
        self.created = created
        self.lastOpened = lastOpened
        self.dateAdded = dateAdded
        self.inode = inode
        self.device = device
        self.linkCount = linkCount
        self.isPackage = isPackage
        self.isFolder = isFolder
        self.isCloud = isCloud
        self.isPlaceholder = isPlaceholder
        self.kind = kind ?? ClutterKindClassifier.kind(forPath: path, isDirectory: isPackage || isFolder,
                                                        isPackage: isPackage)
    }

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
    public var parentPath: String { (path as NSString).deletingLastPathComponent }
    public var pathExtension: String { (path as NSString).pathExtension.lowercased() }
    public var identity: FileIdentity { FileIdentity(device: device, inode: inode) }

    /// When the file was last used: Spotlight's last-opened date, else the access time.
    public var lastUsed: Date { lastOpened ?? accessed }

    /// The most recent sign of activity (opened or changed). "Old" files are old by this.
    public var effectiveLastUse: Date { max(lastUsed, modified) }

    /// Creation date, falling back to modification (used to find the original copy).
    public var originDate: Date { min(created ?? modified, modified) }
}

// MARK: - Kind classification

/// Extension-based kind classification (identical on macOS and Linux).
public enum ClutterKindClassifier {
    public static let movieExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "3g2", "mts", "m2ts",
        "vob", "ogv", "divx", "f4v", "braw", "r3d", "mxf", "dv", "insv", "lrv",
    ]
    public static let musicExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "aifc", "flac", "alac", "ogg", "oga", "opus", "wma", "m4b",
        "m4p", "caf", "mid", "midi", "ape", "dsf", "dff", "amr",
    ]
    public static let pictureExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "gif", "heic", "heif", "hif", "tif", "tiff", "bmp", "webp", "avif", "jxl",
        "raw", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "dng", "orf", "rw2", "raf", "srw", "pef",
        "x3f", "3fr", "erf", "kdc", "mrw", "psd", "psb", "svg", "ico", "icns", "exr", "hdr", "tga", "jp2",
    ]
    /// Formats ImageIO decodes that make sense to compare as photos.
    public static let similarImageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "heic", "heif", "hif", "tif", "tiff", "bmp", "webp", "avif",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "raf", "srw", "pef",
    ]
    public static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "docm", "xls", "xlsx", "xlsm", "ppt", "pptx", "pages", "numbers", "key", "rtf",
        "rtfd", "txt", "md", "markdown", "csv", "tsv", "odt", "ods", "odp", "epub", "mobi", "azw", "azw3",
        "djvu", "xps", "ibooks", "indd", "ai", "eps", "sketch", "fig", "afdesign", "afphoto", "afpub",
    ]
    public static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lz", "lzma", "zst", "z",
        "cab", "sit", "sitx", "cpio", "lha", "lzh", "arj", "war", "jar",
    ]
    public static let installerExtensions: Set<String> = [
        "dmg", "pkg", "mpkg", "iso", "xip", "ipsw", "msi", "exe", "appimage", "deb", "rpm", "apk", "img",
        "sparseimage", "sparsebundle", "toast", "cdr", "dmgpart",
    ]
    public static let virtualMachineExtensions: Set<String> = [
        "vmdk", "vdi", "qcow2", "qcow", "hdd", "hds", "vhd", "vhdx", "utm", "pvm", "vmwarevm", "ova", "ovf",
        "vmem", "vmsn", "nvram",
    ]

    public static func kind(forPath path: String, isDirectory: Bool, isPackage: Bool) -> ClutterKind {
        let ext = (path as NSString).pathExtension.lowercased()
        if isDirectory && !isPackage { return .folders }
        if movieExtensions.contains(ext) { return .movies }
        if musicExtensions.contains(ext) { return .music }
        if pictureExtensions.contains(ext) { return .pictures }
        if virtualMachineExtensions.contains(ext) { return .virtualMachines }
        if installerExtensions.contains(ext) { return .installers }
        if archiveExtensions.contains(ext) { return .archives }
        if documentExtensions.contains(ext) { return .documents }
        if isDirectory { return .folders }
        return .other
    }

    public static func isSimilarImageCandidate(_ path: String) -> Bool {
        similarImageExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}

// MARK: - Settings snapshot

/// The Clutter-relevant settings, captured once per scan.
public struct ClutterScanSettings: Sendable, Equatable {
    /// Minimum size for "large" files (`SpruceSettings.largeFileThreshold`).
    public var largeFileThreshold: Int64
    /// Files not used for this many days are "old" (`SpruceSettings.oldFileDays`).
    public var oldFileDays: Int
    /// Old files smaller than this are not worth listing.
    public var oldMinimumSize: Int64
    /// Duplicate candidates outside Downloads must be at least this big (inside
    /// Downloads every non-empty file counts).
    public var duplicateMinimumSize: Int64
    /// Images smaller than this (bytes) are skipped by Similar Images (icons, UI assets).
    public var similarImageMinimumSize: Int64
    /// Installers in Downloads older than this many days are "old installers".
    public var oldInstallerDays: Int
    /// Incomplete downloads untouched for this many hours are "stale".
    public var staleIncompleteHours: Int

    public init(
        largeFileThreshold: Int64 = 50_000_000,
        oldFileDays: Int = 180,
        oldMinimumSize: Int64 = 10_000_000,
        duplicateMinimumSize: Int64 = 100_000,
        similarImageMinimumSize: Int64 = 50_000,
        oldInstallerDays: Int = 30,
        staleIncompleteHours: Int = 24
    ) {
        self.largeFileThreshold = max(1, largeFileThreshold)
        self.oldFileDays = max(1, oldFileDays)
        self.oldMinimumSize = max(1, min(oldMinimumSize, max(1, largeFileThreshold)))
        self.duplicateMinimumSize = max(1, duplicateMinimumSize)
        self.similarImageMinimumSize = max(1, similarImageMinimumSize)
        self.oldInstallerDays = max(1, oldInstallerDays)
        self.staleIncompleteHours = max(1, staleIncompleteHours)
    }

    public init(_ settings: SpruceSettings) {
        self.init(largeFileThreshold: settings.largeFileThreshold, oldFileDays: settings.oldFileDays)
    }

    /// Smallest file the walk needs to keep for Large & Old Files and Duplicates.
    public var walkMinimumSize: Int64 {
        min(largeFileThreshold, oldMinimumSize, duplicateMinimumSize, similarImageMinimumSize)
    }
}
