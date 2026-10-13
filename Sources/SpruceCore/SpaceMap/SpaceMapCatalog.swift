import Foundation

/// Broad type of an item, used for colours, icons and hover-card labels.
public enum SpaceMapFileType: String, Sendable, CaseIterable {
    case folder, application, package, video, audio, image, archive, diskImage, document, code, other
    case smallFiles, system

    /// Classifies a node (folders by kind, files by extension).
    public static func of(_ node: SpaceMapNode) -> SpaceMapFileType {
        switch node.kind {
        case .directory: return .folder
        case .package:
            return node.name.lowercased().hasSuffix(".app") ? .application : .package
        case .smallFiles: return .smallFiles
        case .system: return .system
        case .file, .symlink: return forFileName(node.name)
        }
    }

    public static func forFileName(_ name: String) -> SpaceMapFileType {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .other }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if imageExtensions.contains(ext) { return .image }
        if diskImageExtensions.contains(ext) { return .diskImage }
        if archiveExtensions.contains(ext) { return .archive }
        if documentExtensions.contains(ext) { return .document }
        if codeExtensions.contains(ext) { return .code }
        return .other
    }

    public var label: String {
        switch self {
        case .folder: return "Folder"
        case .application: return "Application"
        case .package: return "Package"
        case .video: return "Video"
        case .audio: return "Audio"
        case .image: return "Image"
        case .archive: return "Archive"
        case .diskImage: return "Disk image"
        case .document: return "Document"
        case .code: return "Code or data"
        case .other: return "File"
        case .smallFiles: return "Small files"
        case .system: return "System"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .application: return "app.dashed"
        case .package: return "shippingbox.fill"
        case .video: return "film"
        case .audio: return "music.note"
        case .image: return "photo"
        case .archive: return "archivebox.fill"
        case .diskImage: return "opticaldiscdrive.fill"
        case .document: return "doc.text.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc.fill"
        case .smallFiles: return "square.grid.3x3.fill"
        case .system: return "gearshape.2.fill"
        }
    }

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg",
                                               "3gp", "mts", "m2ts", "braw", "r3d", "prores"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "alac", "ogg", "opus",
                                               "caf", "m4b", "m4p", "mid", "midi"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp",
                                               "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "raf", "rw2", "psd",
                                               "svg", "ico", "icns", "avif"]
    static let diskImageExtensions: Set<String> = ["dmg", "iso", "img", "vmdk", "vdi", "qcow2", "hdd", "sparseimage",
                                                   "sparsebundle", "toast", "ipsw", "vhd", "vhdx"]
    static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "lz",
                                                 "lzma", "cab", "pkg", "mpkg", "xip", "jar", "apk", "ipa", "deb", "rpm"]
    static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers",
                                                  "key", "txt", "rtf", "rtfd", "md", "csv", "epub", "odt", "ods", "odp"]
    static let codeExtensions: Set<String> = ["swift", "m", "h", "c", "cpp", "hpp", "js", "ts", "py", "rb", "go", "rs",
                                              "java", "kt", "json", "xml", "yml", "yaml", "plist", "sql", "sqlite",
                                              "db", "log", "html", "css", "sh", "o", "a", "dylib", "so"]
}

/// Static knowledge about folders and packages: which are packages, what well-known
/// folders contain, and which items may not be selected for removal.
public enum SpaceMapCatalog {

    /// Folder extensions Finder shows as single items. They are still browsable here.
    public static let packageExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "kext", "systemextension", "xpc", "prefpane",
        "qlgenerator", "mdimporter", "saver", "component", "driver",
        "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "aplibrary", "migratedphotolibrary",
        "fcpbundle", "logicx", "band", "imovielibrary", "theater", "xcarchive", "xcodeproj", "xcworkspace",
        "playground", "pages", "numbers", "key", "rtfd", "sparsebundle", "pkg", "mpkg", "lproj",
        "docarchive", "abbu", "photosmigrator", "noindex", "scptd", "wdgt",
    ]

    public static func isPackage(name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && packageExtensions.contains(ext)
    }

    /// A short description of a well-known folder (our own wording), shown as the list
    /// subtitle. Nil for anything else.
    public static func description(forPath path: String, home: String = NSHomeDirectory()) -> String? {
        let key = normalized(path)
        let homeKey = normalized(home)
        if key.hasSuffix(".photoslibrary") { return "Photos library — manage it in Photos" }
        if key.hasSuffix(".musiclibrary") { return "Music library — manage it in Music" }
        if key == homeKey { return "Your home folder" }
        if key.hasPrefix(homeKey + "/") {
            let relative = String(key.dropFirst(homeKey.count + 1))
            return homeDescriptions[relative]
        }
        return systemDescriptions[key]
    }

    private static let systemDescriptions: [String: String] = [
        "/system": "macOS itself, sealed and read-only",
        "/library": "Settings, fonts and support files shared by all users",
        "/library/developer": "Command-line developer tools and SDKs",
        "/library/application support": "Data apps keep for every user",
        "/library/caches": "Shared caches, rebuilt when needed",
        "/applications": "Apps installed for everyone on this Mac",
        "/users": "Home folders of every account",
        "/users/shared": "Files shared by all accounts",
        "/private": "System temporary files, caches and logs, managed by macOS",
        "/private/var": "Changing system data: caches, logs and databases",
        "/private/var/folders": "Per-user temporary files and caches",
        "/private/var/vm": "Virtual memory swap files",
        "/private/var/log": "System logs",
        "/private/tmp": "Temporary files, cleared on restart",
        "/usr": "Command-line tools that ship with macOS",
        "/usr/local": "Command-line software you installed",
        "/opt": "Optional software such as package managers",
        "/opt/homebrew": "Homebrew and the packages it installed",
        "/cores": "Memory dumps from crashed processes",
        "/bin": "Essential command-line programs",
        "/sbin": "Essential system programs",
    ]

    private static let homeDescriptions: [String: String] = [
        "library": "Settings, caches and data of your apps",
        "library/caches": "App caches, rebuilt automatically",
        "library/application support": "Data your apps keep, from databases to downloads",
        "library/containers": "Private data of sandboxed apps",
        "library/group containers": "Data shared by apps from the same developer",
        "library/developer": "Xcode data: simulators, builds and device support",
        "library/developer/coresimulator": "Simulator devices and runtimes",
        "library/developer/xcode": "Xcode builds, archives and device support",
        "library/mail": "Your mail and attachments",
        "library/messages": "Messages history and attachments",
        "library/mobile documents": "iCloud Drive files stored on this Mac",
        "library/cloudstorage": "Cloud drives such as Dropbox, Google Drive or OneDrive",
        "library/logs": "Diagnostic logs of your apps",
        "library/photos": "Photos data and caches",
        "library/application support/mobilesync": "iPhone and iPad backups",
        ".trash": "Items in the Trash — empty it to get this space back",
        "applications": "Apps installed only for you",
        "desktop": "Files on your desktop",
        "documents": "Your documents",
        "downloads": "Files you downloaded",
        "movies": "Videos and editing projects",
        "music": "Music library and audio projects",
        "pictures": "Photos and images",
        "public": "Files you share with other users",
        "developer": "Your development projects",
    ]

    /// Why a node may not be selected for removal (nil = it may be selected).
    ///
    /// Real items are checked against `PathGuard` (the same rules `FileRemover` applies),
    /// cloud folders are left to Cloud Storage, and ignored paths are honoured. With
    /// `access` (the app passes `SpaceMapPermissions.moveAccess(ofPath:)`), items the user
    /// can't move themselves are refused up front when administrator rights won't help:
    /// locked items anywhere, and root-owned (or otherwise unwritable) items outside the
    /// places where Spruce acts as administrator (`PathGuard.isInPrivilegedZone`).
    public static func protectionReason(for node: SpaceMapNode, guardian: PathGuard,
                                        settings: SpruceSettings? = nil,
                                        access: ((String) -> SpaceMapMoveAccess)? = nil) -> String? {
        switch node.kind {
        case .system:
            return "Managed by macOS; it can't be removed from here"
        case .smallFiles:
            return "A summary of many small files; select their folder instead"
        default:
            break
        }
        if node.parent == nil { return "This is the location you scanned" }
        let path = node.path
        let key = normalized(path)
        let home = normalized(guardian.home)
        for cloudRoot in [home + "/library/mobile documents", home + "/library/cloudstorage"]
            where key == cloudRoot || key.hasPrefix(cloudRoot + "/") {
            return "Cloud files; manage them in Cloud Storage"
        }
        if let settings, settings.isIgnored(path: path) {
            return "On your ignore list"
        }
        let verdict = guardian.check(path, method: .trash)
        if let reason = verdict.reason { return reason }
        if let access {
            switch access(path) {
            case .userCanMove:
                break
            case .locked(let byUser):
                return byUser ? lockedReason : systemLockedReason
            case .needsAdministrator(let rootOwned):
                // Inside the privileged zones FileRemover asks for the password once.
                if !guardian.isInPrivilegedZone(path) {
                    return rootOwned ? rootOwnedReason : noPermissionReason
                }
            }
        }
        return nil
    }

    /// Tooltip for root-owned items outside the places where Spruce uses administrator rights.
    public static let rootOwnedReason = "Owned by the system (root). Spruce only uses administrator rights for apps, their support files, caches, logs and temporary files, so it can't move this"
    /// Tooltip for other items the user can't move, outside those places.
    public static let noPermissionReason = "You don't have permission to move this, and Spruce only uses administrator rights for apps, their support files, caches, logs and temporary files"
    /// Tooltip for items locked in Finder (or inside a locked folder).
    public static let lockedReason = "Locked. Unlock it (or its folder) in Finder's Get Info window first"
    /// Tooltip for items macOS protects (System Integrity Protection, system immutable flag).
    public static let systemLockedReason = "Protected by macOS; not even an administrator can move it"

    /// Lowercased, without trailing slashes, `/var`, `/tmp` and `/etc` mapped to `/private`.
    static func normalized(_ path: String) -> String {
        var p = path.lowercased()
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        for alias in ["/var", "/tmp", "/etc"] where p == alias || p.hasPrefix(alias + "/") {
            p = "/private" + p
            break
        }
        return p
    }
}
