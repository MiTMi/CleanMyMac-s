import Foundation

/// The kinds of installer files Spruce looks for.
public enum ApplicationsInstallerKind: String, Codable, Sendable, CaseIterable {
    case diskImage
    case package
    case appArchive
    case xip

    public var title: String {
        switch self {
        case .diskImage: return "Disk Images"
        case .package: return "Installer Packages"
        case .appArchive: return "App Archives"
        case .xip: return "Apple Archives"
        }
    }

    public var symbol: String {
        switch self {
        case .diskImage: return "externaldrive"
        case .package: return "shippingbox"
        case .appArchive: return "doc.zipper"
        case .xip: return "archivebox"
        }
    }
}

/// How Spruce tied an installer to an installed app.
public enum ApplicationsInstallerMatch: String, Codable, Sendable {
    /// The archive itself contains the app (read from the zip's directory).
    case contents
    /// The file name, without version and platform words, is the app's distinctive name.
    case exactName
    /// Only part of the name matches, or the app's name is a common word — a guess.
    case partialName

    /// Strong enough to pre-select an old installer.
    public var isConfident: Bool { self != .partialName }
}

/// One installer found in Downloads or on the Desktop.
public struct ApplicationsInstallerFile: Sendable, Hashable, Identifiable, Codable {
    public var id: String { path }
    public var path: String
    public var kind: ApplicationsInstallerKind
    public var size: Int64
    public var modified: Date
    /// Name of the installed app this installer is for, if Spruce recognised it.
    public var installedApp: String?
    /// How the installer was matched to `installedApp`.
    public var match: ApplicationsInstallerMatch?
    /// The disk image is currently mounted.
    public var isAttached: Bool
    /// The disk image is encrypted. Installers never are, so it most likely holds personal files.
    public var isEncrypted: Bool
    /// A word in the file name that suggests personal files ("backup", "photos"…).
    public var personalWord: String?
    /// File identity at scan time (re-checked before removal).
    public var inode: UInt64?

    public init(path: String, kind: ApplicationsInstallerKind, size: Int64, modified: Date,
                installedApp: String? = nil, isAttached: Bool = false, inode: UInt64? = nil,
                match: ApplicationsInstallerMatch? = nil, isEncrypted: Bool = false, personalWord: String? = nil) {
        self.path = path
        self.kind = kind
        self.size = size
        self.modified = modified
        self.installedApp = installedApp
        self.match = installedApp == nil ? nil : match
        self.isAttached = isAttached
        self.isEncrypted = isEncrypted
        self.personalWord = personalWord
        self.inode = inode
    }

    /// Safe to pre-select: confidently matched to an installed app, older than 30 days, not
    /// mounted, not encrypted, and nothing in its name suggests personal files.
    public func isSafe(now: Date = Date()) -> Bool {
        guard installedApp != nil, match?.isConfident == true else { return false }
        return !isAttached && !isEncrypted && personalWord == nil && now.timeIntervalSince(modified) > 30 * 86_400
    }

    public func note(now: Date = Date()) -> String {
        if isAttached { return "This disk image is mounted right now. Eject it before removing." }
        if isEncrypted {
            return "This disk image is encrypted. App installers never are, so it probably holds personal files — check before removing."
        }
        if let personalWord {
            return "Its name contains \u{201C}\(personalWord)\u{201D}, so it may hold personal files rather than an app installer. Check before removing."
        }
        if let installedApp {
            guard match?.isConfident == true else {
                return "It might be the installer of \(installedApp), but only part of the name matches. Check before removing."
            }
            let age = now.timeIntervalSince(modified) > 30 * 86_400
                ? "Downloaded more than a month ago."
                : "Downloaded recently — keep it if you still need it."
            return "\(installedApp) is already installed, so this installer is no longer needed. \(age)"
        }
        return "Spruce couldn't match this installer to an installed app. Keep it if you plan to install it."
    }
}

/// Finds old installers (.dmg, .pkg, app .zip archives, .xip) in Downloads and on the Desktop.
public struct ApplicationsInstallerDetector {
    /// An installed app installers are matched against.
    public struct InstalledApp: Sendable, Hashable {
        public var name: String
        /// Apps that come with macOS never have installers in Downloads; they are not matched.
        public var isSystem: Bool

        public init(name: String, isSystem: Bool = false) {
            self.name = name
            self.isSystem = isSystem
        }
    }

    /// Folders and how deep to look (Downloads: two levels below, Desktop: top level).
    public var roots: [(path: String, depth: Int)]
    /// Top-level entries of a zip archive (nil when unreadable).
    public var zipEntries: (String) -> [String]?
    /// True for encrypted disk images.
    public var isEncryptedImage: (String) -> Bool

    public init(home: String = NSHomeDirectory(),
                zipEntries: @escaping (String) -> [String]? = ApplicationsZipIndex.topLevelEntries(atPath:),
                isEncryptedImage: @escaping (String) -> Bool = ApplicationsDiskImage.isEncrypted(atPath:)) {
        roots = [((home as NSString).appendingPathComponent("Downloads"), 2),
                 ((home as NSString).appendingPathComponent("Desktop"), 0)]
        self.zipEntries = zipEntries
        self.isEncryptedImage = isEncryptedImage
    }

    public init(roots: [(path: String, depth: Int)],
                zipEntries: @escaping (String) -> [String]? = ApplicationsZipIndex.topLevelEntries(atPath:),
                isEncryptedImage: @escaping (String) -> Bool = ApplicationsDiskImage.isEncrypted(atPath:)) {
        self.roots = roots
        self.zipEntries = zipEntries
        self.isEncryptedImage = isEncryptedImage
    }

    /// Scans the roots. `installedAppNames` are names of third-party apps (file name without
    /// ".app", `CFBundleName`…); `attachedImages` are paths of mounted disk images.
    public func scan(installedAppNames: [String], attachedImages: Set<String> = []) -> [ApplicationsInstallerFile] {
        scan(installedApps: installedAppNames.map { InstalledApp(name: $0) }, attachedImages: attachedImages)
    }

    /// Scans the roots, matching installers to `installedApps` (system apps are ignored).
    public func scan(installedApps: [InstalledApp], attachedImages: Set<String> = []) -> [ApplicationsInstallerFile] {
        let normalizedApps = Self.matchable(installedApps)
        let attached = Set(attachedImages.map { ($0 as NSString).standardizingPath.lowercased() })
        var results: [ApplicationsInstallerFile] = []
        for root in roots {
            FileWalker.walk(root.path, options: .init(includeHidden: false, descendIntoPackages: false, maxDepth: root.depth + 1)) { entry in
                if entry.depth == 0 { return .continue }
                if entry.isSymlink { return .skipChildren }
                let ext = (entry.name as NSString).pathExtension.lowercased()
                if entry.isDirectory {
                    // Packages and bundles are leaves; ordinary folders are walked to the depth limit.
                    return FileWalker.packageExtensions.contains(ext) || ext == "sparsebundle" ? .skipChildren : .continue
                }
                guard entry.isRegularFile, let kind = classify(path: entry.path, ext: ext) else { return .continue }
                results.append(file(entry: entry, kind: kind, installed: normalizedApps, attached: attached))
                return .continue
            }
        }
        return results.sorted { $0.size > $1.size }
    }

    /// Describes files the user handed to Spruce (dropped, or opened from Finder), wherever
    /// they are. Files that are not installers are left out.
    public func describe(paths: [String], installedApps: [InstalledApp], attachedImages: Set<String> = []) -> [ApplicationsInstallerFile] {
        let normalizedApps = Self.matchable(installedApps)
        let attached = Set(attachedImages.map { ($0 as NSString).standardizingPath.lowercased() })
        return paths.compactMap { path in
            guard let entry = FileWalker.entry(at: path), entry.isRegularFile || entry.isDirectory, !entry.isSymlink else { return nil }
            let ext = (entry.name as NSString).pathExtension.lowercased()
            // Flat packages are files; bundle-style .pkg/.mpkg installers are folders.
            if entry.isDirectory && ext != "pkg" && ext != "mpkg" { return nil }
            guard let kind = entry.isDirectory ? .package : classify(path: entry.path, ext: ext) else { return nil }
            var measured = entry
            if entry.isDirectory { measured.allocatedSize = DiskUsage.measure(path).bytes }
            return file(entry: measured, kind: kind, installed: normalizedApps, attached: attached)
        }
    }

    private func file(entry: FileEntry, kind: ApplicationsInstallerKind, installed: [(name: String, key: String)],
                      attached: Set<String>) -> ApplicationsInstallerFile {
        let matched = matchApp(fileName: entry.name, archiveEntries: kind == .appArchive ? zipEntries(entry.path) : nil,
                               installed: installed)
        return ApplicationsInstallerFile(
            path: entry.path, kind: kind, size: entry.allocatedSize, modified: entry.modified,
            installedApp: matched?.name, isAttached: attached.contains((entry.path as NSString).standardizingPath.lowercased()),
            inode: entry.inode, match: matched?.match,
            isEncrypted: kind == .diskImage && isEncryptedImage(entry.path),
            personalWord: Self.personalWord(fileName: entry.name))
    }

    static func matchable(_ apps: [InstalledApp]) -> [(name: String, key: String)] {
        apps.filter { !$0.isSystem }
            .map { (name: $0.name, key: ApplicationsTokens.normalized($0.name)) }
            .filter { $0.key.count >= 3 }
    }

    /// The installer kind of a file, or nil when it is not an installer. Zip files only count
    /// when they contain an app at their top level.
    public func classify(path: String, ext: String) -> ApplicationsInstallerKind? {
        switch ext {
        case "dmg": return .diskImage
        case "pkg", "mpkg": return .package
        case "xip": return .xip
        case "zip":
            guard let entries = zipEntries(path) else { return nil }
            return entries.contains(where: { $0.lowercased().hasSuffix(".app") }) ? .appArchive : nil
        default: return nil
        }
    }

    /// Words that decorate installer file names without identifying the app.
    static let noiseWords: Set<String> = [
        "mac", "macos", "osx", "os", "darwin", "universal", "arm", "arm64", "aarch64", "x64", "x86", "amd64", "intel",
        "apple", "silicon", "installer", "install", "setup", "latest", "stable", "release", "beta", "dmg", "pkg",
        "signed", "full", "final", "build", "version", "v", "for", "the", "app", "download", "update", "en", "us",
    ]

    /// Words in a file name that point to personal files rather than an app installer
    /// ("Photos 2019.dmg", "Steam Library Backup.dmg"). Such files are never pre-selected.
    public static let personalWords: Set<String> = [
        "backup", "backups", "archive", "archives", "archived", "library", "photos", "photo", "pictures", "images",
        "videos", "video", "movies", "music", "documents", "docs", "personal", "private", "encrypted", "vault",
        "secure", "export", "exported", "copy", "files", "home", "family", "projects", "timemachine", "snapshot",
        "clone", "scans", "taxes", "keys", "passwords", "wallet",
    ]

    /// The first word of `fileName` that suggests personal files, or nil.
    public static func personalWord(fileName: String) -> String? {
        let stem = (fileName as NSString).deletingPathExtension
        let separators = CharacterSet(charactersIn: " -_.()[]+,")
        for raw in stem.components(separatedBy: separators) where !raw.isEmpty {
            var word = raw.lowercased()
            while let last = word.last, last.isNumber { word.removeLast() }
            if personalWords.contains(word) { return word }
        }
        return nil
    }

    /// True when a normalized app name is specific enough to recognise from a file name alone.
    static func isDistinctiveKey(_ key: String) -> Bool {
        key.count >= 3 && !ApplicationsTokens.commonWords.contains(key)
    }

    /// Recognisable name of an installer file ("Firefox 121.0.dmg" → "firefox",
    /// "VSCode-darwin-universal.zip" → "vscode").
    public static func installerKey(fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        let separators = CharacterSet(charactersIn: " -_.()[]+,")
        var words: [String] = []
        for raw in stem.components(separatedBy: separators) where !raw.isEmpty {
            // "rectangle0" → "rectangle"; "121" → "".
            var word = raw.lowercased()
            while let last = word.last, last.isNumber { word.removeLast() }
            if word.isEmpty || noiseWords.contains(word) {
                if !words.isEmpty && raw.first?.isNumber == true { break }   // version numbers end the name
                continue
            }
            words.append(word)
        }
        return ApplicationsTokens.normalized(words.joined())
    }

    /// The installed app an installer belongs to, and how sure the match is.
    ///
    /// * The zip contains `<App>.app` → `.contents`.
    /// * The file name is exactly a distinctive app name → `.exactName`.
    /// * The name is a common word ("Notes"), or only a prefix matches ("Home Videos" vs
    ///   "Home", "zoomusinstaller" vs "zoom.us") → `.partialName` (never pre-selected).
    func matchApp(fileName: String, archiveEntries: [String]?,
                  installed: [(name: String, key: String)]) -> (name: String, match: ApplicationsInstallerMatch)? {
        if let archiveEntries {
            for entry in archiveEntries where entry.lowercased().hasSuffix(".app") {
                let key = ApplicationsTokens.normalized(String(entry.dropLast(4)))
                if let app = installed.first(where: { $0.key == key }) { return (app.name, .contents) }
            }
        }
        let key = Self.installerKey(fileName: fileName)
        guard key.count >= 3 else { return nil }
        if let exact = installed.first(where: { $0.key == key }) {
            return (exact.name, Self.isDistinctiveKey(key) ? .exactName : .partialName)
        }
        // "googlechromebeta" ↔ "Google Chrome", "zoomusinstaller" ↔ "zoom.us": a guess, shown for review.
        let prefixMatches = installed.filter { app in
            Self.isDistinctiveKey(app.key)
                && ((app.key.count >= 4 && key.hasPrefix(app.key)) || (key.count >= 5 && app.key.hasPrefix(key)))
        }
        return prefixMatches.max(by: { $0.key.count < $1.key.count }).map { ($0.name, .partialName) }
    }
}

/// Reads just enough of a disk image to tell whether it is encrypted.
public enum ApplicationsDiskImage {
    /// True for encrypted disk images: the `encrcdsa` header (current format) or the
    /// `cdsaencr` trailer (the original format).
    public static func isEncrypted(atPath path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8) else { return false }
        if head == Data("encrcdsa".utf8) { return true }
        guard let size = try? handle.seekToEnd(), size >= 16 else { return false }
        guard (try? handle.seek(toOffset: size - 8)) != nil, let tail = try? handle.read(upToCount: 8) else { return false }
        return tail == Data("cdsaencr".utf8)
    }
}

/// Reads the names in a zip archive's central directory without extracting anything.
public enum ApplicationsZipIndex {
    /// Largest central directory we are willing to read.
    static let maxCentralDirectory = 16 * 1024 * 1024

    /// Distinct first path components of the archive's entries ("Foo.app", "README.txt"),
    /// ignoring `__MACOSX`. nil when the file is not a readable zip (or is a ZIP64 archive).
    public static func topLevelEntries(atPath path: String) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let fileSize = handle.seekToEndOfFile()
        guard fileSize >= 22 else { return nil }
        let tailLength = min(fileSize, 65_557)
        handle.seek(toFileOffset: fileSize - tailLength)
        let tail = [UInt8](handle.readData(ofLength: Int(tailLength)))
        guard let eocd = findEndOfCentralDirectory(tail) else { return nil }
        let entryCount = Int(le16(tail, eocd + 10))
        let directorySize = Int(le32(tail, eocd + 12))
        let directoryOffset = UInt64(le32(tail, eocd + 16))
        guard directoryOffset != 0xFFFF_FFFF, directorySize > 0, directorySize <= maxCentralDirectory,
              directoryOffset + UInt64(directorySize) <= fileSize else { return nil }
        handle.seek(toFileOffset: directoryOffset)
        let directory = [UInt8](handle.readData(ofLength: directorySize))
        return entryNames(centralDirectory: directory, expected: entryCount)
    }

    /// Parses central-directory file headers and returns distinct top-level names.
    public static func entryNames(centralDirectory bytes: [UInt8], expected: Int) -> [String]? {
        var names: [String] = []
        var seen = Set<String>()
        var offset = 0
        var count = 0
        while offset + 46 <= bytes.count, count < max(expected, 1) * 2 {
            guard le32(bytes, offset) == 0x0201_4B50 else { break }
            let nameLength = Int(le16(bytes, offset + 28))
            let extraLength = Int(le16(bytes, offset + 30))
            let commentLength = Int(le16(bytes, offset + 32))
            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            if let first = name.split(separator: "/", omittingEmptySubsequences: true).first {
                let top = String(first)
                if top != "__MACOSX" && seen.insert(top).inserted { names.append(top) }
            }
            offset = nameStart + nameLength + extraLength + commentLength
            count += 1
        }
        return count == 0 ? nil : names
    }

    static func findEndOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        var index = bytes.count - 22
        while index >= 0 {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4B, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 {
                return index
            }
            index -= 1
        }
        return nil
    }

    static func le16(_ b: [UInt8], _ o: Int) -> UInt16 {
        guard o + 2 <= b.count else { return 0 }
        return UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }

    static func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}
