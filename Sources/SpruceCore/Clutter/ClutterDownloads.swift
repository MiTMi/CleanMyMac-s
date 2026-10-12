import Foundation

/// Kind of item found in `~/Downloads`.
public enum ClutterDownloadCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case installers
    case archives
    case incomplete
    case documents
    case images
    case video
    case audio
    case folders
    case other

    public var title: String {
        switch self {
        case .installers: return "Installers"
        case .archives: return "Archives"
        case .incomplete: return "Unfinished Downloads"
        case .documents: return "Documents"
        case .images: return "Images"
        case .video: return "Video"
        case .audio: return "Audio"
        case .folders: return "Folders"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .installers: return "shippingbox"
        case .archives: return "doc.zipper"
        case .incomplete: return "exclamationmark.arrow.circlepath"
        case .documents: return "doc.text"
        case .images: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .folders: return "folder"
        case .other: return "doc"
        }
    }

    public var detail: String {
        switch self {
        case .installers: return "Disk images and packages are usually needed once, to install an app."
        case .archives: return "Compressed files you may already have opened."
        case .incomplete: return "Downloads that stopped before they finished."
        case .documents: return "PDFs, documents and spreadsheets you downloaded."
        case .images: return "Pictures saved from the web, mail and chats."
        case .video: return "Movies and clips you downloaded."
        case .audio: return "Songs, podcasts and recordings."
        case .folders: return "Folders, often unpacked archives."
        case .other: return "Everything else in your Downloads folder."
        }
    }
}

/// One top-level item of `~/Downloads`.
public struct ClutterDownloadItem: Sendable, Hashable, Identifiable, Codable {
    public var file: ClutterFile
    public var category: ClutterDownloadCategory
    /// Downloading app (from the quarantine record), e.g. "Safari".
    public var sourceApp: String?
    /// Website the file came from (from `kMDItemWhereFroms`), e.g. "github.com".
    public var sourceHost: String?
    /// When it was downloaded (download date, quarantine time or date added).
    public var downloadedAt: Date?
    /// The installer's app is already in an Applications folder.
    public var installerAlreadyUsed: Bool
    /// A folder with the archive's name sits next to it (it was unpacked).
    public var archiveAlreadyExtracted: Bool

    public init(file: ClutterFile, category: ClutterDownloadCategory, sourceApp: String? = nil, sourceHost: String? = nil,
                downloadedAt: Date? = nil, installerAlreadyUsed: Bool = false, archiveAlreadyExtracted: Bool = false) {
        self.file = file
        self.category = category
        self.sourceApp = sourceApp
        self.sourceHost = sourceHost
        self.downloadedAt = downloadedAt
        self.installerAlreadyUsed = installerAlreadyUsed
        self.archiveAlreadyExtracted = archiveAlreadyExtracted
    }

    public var id: String { file.path }

    /// The date used for "downloaded N days ago".
    public var referenceDate: Date { downloadedAt ?? file.dateAdded ?? file.modified }

    /// Grouping label for "By Source".
    public var sourceLabel: String { sourceApp ?? sourceHost ?? "Unknown source" }
}

/// Categorizes `~/Downloads` and decides what may be pre-selected.
public enum ClutterDownloadsAnalyzer {
    public static let incompleteExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "opdownload", "filepart", "aria2", "!ut", "!qb",
        "bc!", "unconfirmed",
    ]

    public static func category(for file: ClutterFile) -> ClutterDownloadCategory {
        let ext = file.pathExtension
        if incompleteExtensions.contains(ext) { return .incomplete }
        if file.isFolder { return .folders }
        switch file.kind {
        case .installers, .virtualMachines: return .installers
        case .archives: return .archives
        case .documents: return .documents
        case .pictures: return .images
        case .movies: return .video
        case .music: return .audio
        case .folders: return .folders
        case .other: return .other
        }
    }

    /// Parses a `com.apple.quarantine` value (`flags;hex-unix-time;agent;uuid`).
    public static func parseQuarantine(_ value: String) -> (agent: String?, date: Date?) {
        let fields = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        var date: Date?
        if fields.count > 1, let seconds = UInt64(fields[1], radix: 16), seconds > 0 {
            date = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        var agent: String?
        if fields.count > 2 {
            let raw = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { agent = displayName(forAgent: raw) }
        }
        return (agent, date)
    }

    /// Friendlier names for well-known downloading agents.
    public static func displayName(forAgent agent: String) -> String {
        switch agent.lowercased() {
        case "sharingd": return "AirDrop"
        case "com.apple.safari", "safari": return "Safari"
        case "com.google.chrome", "google chrome": return "Google Chrome"
        case "org.mozilla.firefox", "firefox": return "Firefox"
        case "com.apple.mail", "mail": return "Mail"
        case "com.apple.messages", "messages": return "Messages"
        default: return agent
        }
    }

    /// The website a file came from, from the `kMDItemWhereFroms` URL list
    /// (`www.` is dropped). Local file URLs are ignored.
    public static func host(fromWhereFroms urls: [String]) -> String? {
        for value in urls {
            guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  var host = url.host?.lowercased(), !host.isEmpty else { continue }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            return host
        }
        return nil
    }

    /// "Firefox 120.0.1.dmg" → "firefox", "Visual Studio Code-arm64.zip" → "visual studio code".
    public static func normalizedInstallerName(_ filename: String) -> String {
        var base = filename.lowercased()
        // Strip all extensions (".tar.gz", ".dmg").
        while true {
            let ext = (base as NSString).pathExtension
            guard !ext.isEmpty, ext.count <= 8, !ext.contains(" ") else { break }
            base = (base as NSString).deletingPathExtension
        }
        let separators = CharacterSet(charactersIn: "-_.+()[] ")
        let noise: Set<String> = [
            "arm64", "x64", "x86", "x86_64", "intel", "universal", "mac", "macos", "osx", "darwin", "apple",
            "silicon", "installer", "setup", "install", "latest", "release", "stable", "beta", "final", "signed",
            "dmg", "pkg", "aarch64", "amd64", "en", "us", "full",
        ]
        let words = base.components(separatedBy: separators).filter { word in
            guard !word.isEmpty, !noise.contains(word) else { return false }
            // Version-like tokens: "120", "1.2.3", "v2", "2024", "b123".
            let digits = word.filter(\.isNumber).count
            if digits == word.count { return false }
            if word.hasPrefix("v") && word.dropFirst().allSatisfy({ $0.isNumber }) { return false }
            if word.count <= 5 && digits >= word.count - 1 { return false }
            return true
        }
        return words.joined(separator: " ")
    }

    /// Whether an installer's name matches one of the installed app names (lowercased,
    /// without ".app").
    public static func installerMatchesInstalledApp(_ filename: String, appNames: Set<String>) -> Bool {
        let name = normalizedInstallerName(filename)
        guard name.count >= 3 else { return false }
        if appNames.contains(name) { return true }
        let squashed = name.replacingOccurrences(of: " ", with: "")
        for app in appNames {
            let appSquashed = app.replacingOccurrences(of: " ", with: "")
            guard appSquashed.count >= 3 else { continue }
            if appSquashed == squashed { return true }
            // "docker desktop" installer for the "docker" app (whole leading words only).
            if app.count >= 4 && name.hasPrefix(app + " ") { return true }
        }
        return false
    }

    /// An unfinished download nobody touched for `staleIncompleteHours`.
    public static func isStaleIncomplete(_ item: ClutterDownloadItem, settings: ClutterScanSettings,
                                         now: Date = Date()) -> Bool {
        guard item.category == .incomplete else { return false }
        let age = now.timeIntervalSince(item.file.modified)
        return age >= TimeInterval(settings.staleIncompleteHours) * 3_600
    }

    /// An installer older than `oldInstallerDays`.
    public static func isOldInstaller(_ item: ClutterDownloadItem, settings: ClutterScanSettings,
                                      now: Date = Date()) -> Bool {
        guard item.category == .installers else { return false }
        return now.timeIntervalSince(item.referenceDate) >= TimeInterval(settings.oldInstallerDays) * 86_400
    }

    /// Builds items for the top-level contents of Downloads.
    ///
    /// - Parameters:
    ///   - metadata: per-path platform metadata (quarantine value, where-froms, download date).
    ///   - installedAppNames: lowercased names of installed apps, without ".app".
    public static func items(from files: [ClutterFile], metadata: [String: ClutterDownloadMetadata] = [:],
                             installedAppNames: Set<String> = []) -> [ClutterDownloadItem] {
        let siblingFolders = Set(files.filter(\.isFolder).map { ($0.path as NSString).lastPathComponent.lowercased() })
        return files.map { file in
            let kind = Self.category(for: file)
            let meta = metadata[file.path]
            let quarantine = meta?.quarantine.map { Self.parseQuarantine($0) }
            let sourceHost = meta.flatMap { Self.host(fromWhereFroms: $0.whereFroms) }
            let downloaded = meta?.downloadedDate ?? quarantine?.date ?? file.dateAdded
            var extracted = false
            if kind == .archives {
                var base = file.name.lowercased()
                while !(base as NSString).pathExtension.isEmpty { base = (base as NSString).deletingPathExtension }
                extracted = siblingFolders.contains(base)
            }
            let used = kind == .installers && Self.installerMatchesInstalledApp(file.name, appNames: installedAppNames)
            return ClutterDownloadItem(file: file, category: kind, sourceApp: quarantine?.agent,
                                       sourceHost: sourceHost, downloadedAt: downloaded,
                                       installerAlreadyUsed: used, archiveAlreadyExtracted: extracted)
        }
        .sorted { $0.file.size != $1.file.size ? $0.file.size > $1.file.size : $0.file.path < $1.file.path }
    }

    /// The source app that downloaded the most bytes (for the tile headline).
    public static func dominantSource(_ items: [ClutterDownloadItem]) -> String? {
        var bytes: [String: Int64] = [:]
        for item in items {
            guard let app = item.sourceApp else { continue }
            bytes[app, default: 0] += item.file.size
        }
        return bytes.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }
}

/// Platform metadata of a downloaded file (read by the Mac layer from extended attributes).
public struct ClutterDownloadMetadata: Sendable, Hashable, Codable {
    public var quarantine: String?
    public var whereFroms: [String]
    public var downloadedDate: Date?

    public init(quarantine: String? = nil, whereFroms: [String] = [], downloadedDate: Date? = nil) {
        self.quarantine = quarantine
        self.whereFroms = whereFroms
        self.downloadedDate = downloadedDate
    }
}
