import Foundation

// Browser and system privacy traces: where each browser keeps history, cookies, caches…
// Paths follow the browsers' documented on-disk layouts (Chromium profile folders,
// Firefox profiles, Safari's ~/Library/Safari and container). Saved passwords are never
// offered, and Safari's open tabs / tab groups (SafariTabs.db, CloudTabs.db) are left alone.

public enum ProtectionBrowserID: String, CaseIterable, Codable, Sendable {
    case safari, chrome, firefox, edge, brave, opera, vivaldi, arc
}

public enum ProtectionBrowserEngine: String, Codable, Sendable {
    case webkit, chromium, gecko
}

/// A supported browser and where it keeps its data.
public struct ProtectionBrowser: Sendable, Hashable, Identifiable {
    public let id: ProtectionBrowserID
    public let name: String
    public let bundleIDs: [String]
    public let engine: ProtectionBrowserEngine
    /// Logical data root ("~/Library/Application Support/Google/Chrome").
    public let dataRoot: String
    /// Logical cache root under ~/Library/Caches (per-profile sub-folders for Chromium/Firefox).
    public let cacheRoot: String?
    /// Safari's data is protected by macOS privacy controls.
    public let requiresFullDiskAccess: Bool

    public init(id: ProtectionBrowserID, name: String, bundleIDs: [String], engine: ProtectionBrowserEngine,
                dataRoot: String, cacheRoot: String?, requiresFullDiskAccess: Bool = false) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.engine = engine
        self.dataRoot = dataRoot
        self.cacheRoot = cacheRoot
        self.requiresFullDiskAccess = requiresFullDiskAccess
    }
}

/// One kind of trace.
public enum ProtectionTraceKind: String, CaseIterable, Codable, Sendable {
    case history
    case downloads
    case cookies
    case autofill
    case topSites
    case sessions
    case siteData
    case cache
    case recentItems
    case quickLookThumbnails
    case downloadLog

    public var title: String {
        switch self {
        case .history: return "Browsing history"
        case .downloads: return "Downloads history"
        case .cookies: return "Cookies"
        case .autofill: return "Autofill & form data"
        case .topSites: return "Top sites & site icons"
        case .sessions: return "Last session & closed tabs"
        case .siteData: return "Website data"
        case .cache: return "Cached files"
        case .recentItems: return "Recent items lists"
        case .quickLookThumbnails: return "Quick Look thumbnails"
        case .downloadLog: return "Download log"
        }
    }

    public var symbol: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .downloads: return "arrow.down.circle"
        case .cookies: return "circle.grid.3x3.fill"
        case .autofill: return "character.cursor.ibeam"
        case .topSites: return "star.square.on.square"
        case .sessions: return "rectangle.stack"
        case .siteData: return "externaldrive.badge.icloud"
        case .cache: return "internaldrive"
        case .recentItems: return "list.bullet.rectangle"
        case .quickLookThumbnails: return "photo.on.rectangle"
        case .downloadLog: return "tray.and.arrow.down"
        }
    }

    /// Selected by default only when clearing it breaks nothing.
    public var defaultSafety: SafetyLevel {
        switch self {
        case .history, .downloads, .cache, .recentItems, .quickLookThumbnails: return .safe
        case .cookies, .autofill, .topSites, .sessions, .siteData, .downloadLog: return .review
        }
    }

    /// What clearing it means, in plain words.
    public func detail(engine: ProtectionBrowserEngine?) -> String {
        switch self {
        case .history:
            switch engine {
            case .chromium?: return "Pages you visited, the downloads list and searches typed in the address bar. Downloaded files stay."
            case .gecko?: return "Pages you visited and the downloads list. Firefox keeps bookmarks in the same file and restores them from its latest automatic backup."
            default: return "Pages you visited. Bookmarks are kept."
            }
        case .downloads: return "The list of files you downloaded. The files themselves stay where they are."
        case .cookies: return "Logins and site preferences. You'll be signed out of websites."
        case .autofill:
            return engine == .chromium
                ? "Saved form entries, addresses and cards, and custom search engines. Saved passwords are kept."
                : "Saved form entries and search bar history. Saved passwords are kept."
        case .topSites: return "Frequently visited sites and their icons."
        case .sessions: return "Tabs the browser reopens after quitting, and recently closed tabs."
        case .siteData: return "Data websites store on your Mac (local storage, databases, offline data). Sites may sign you out."
        case .cache: return "Temporary copies of web pages and images. The browser downloads them again as needed."
        case .recentItems: return "Recent apps, documents and servers macOS lists in menus. The files themselves stay."
        case .quickLookThumbnails: return "Preview images macOS keeps of files you've looked at, even after the files are gone."
        case .downloadLog: return "macOS's record of every file downloaded from the internet. Files stay; their warnings still work."
        }
    }
}

/// A file or folder belonging to a trace.
public struct ProtectionTraceFile: Sendable, Hashable, Codable {
    public var path: String
    public var size: Int64
    public var deletion: DeletionMethod

    public init(path: String, size: Int64, deletion: DeletionMethod) {
        self.path = path
        self.size = size
        self.deletion = deletion
    }
}

/// One cleanable trace of one source (a browser or macOS).
public struct ProtectionTrace: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var sourceID: String
    public var kind: ProtectionTraceKind
    public var title: String
    public var detail: String
    public var safety: SafetyLevel
    public var files: [ProtectionTraceFile]
    /// Custom action instead of file disposal (e.g. "quicklook-reset").
    public var customAction: String?
    /// Size reported when the trace has no files of its own (custom actions).
    public var measuredSize: Int64

    public init(id: String, sourceID: String, kind: ProtectionTraceKind, title: String, detail: String,
                safety: SafetyLevel, files: [ProtectionTraceFile], customAction: String? = nil, measuredSize: Int64 = 0) {
        self.id = id
        self.sourceID = sourceID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.safety = safety
        self.files = files
        self.customAction = customAction
        self.measuredSize = measuredSize
    }

    public var size: Int64 { files.isEmpty ? measuredSize : files.reduce(0) { $0 + $1.size } }

    public static let quickLookResetAction = "quicklook-reset"
}

/// A browser (or macOS) with its traces.
public struct ProtectionTraceSource: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var browser: ProtectionBrowser?
    /// Profile names found (Chromium/Firefox).
    public var profiles: [String]
    public var traces: [ProtectionTrace]
    /// True when macOS blocked reading the data (Safari without Full Disk Access).
    public var isUnreadable: Bool

    public init(id: String, title: String, browser: ProtectionBrowser?, profiles: [String], traces: [ProtectionTrace],
                isUnreadable: Bool) {
        self.id = id
        self.title = title
        self.browser = browser
        self.profiles = profiles
        self.traces = traces
        self.isUnreadable = isUnreadable
    }

    public var totalSize: Int64 { traces.reduce(0) { $0 + $1.size } }
    public static let systemID = "system"
}

// MARK: - Catalog

public enum ProtectionPrivacyCatalog {
    public static let browsers: [ProtectionBrowser] = [
        ProtectionBrowser(id: .safari, name: "Safari", bundleIDs: ["com.apple.Safari"], engine: .webkit,
                          dataRoot: "~/Library/Safari", cacheRoot: "~/Library/Caches/com.apple.Safari",
                          requiresFullDiskAccess: true),
        ProtectionBrowser(id: .chrome, name: "Google Chrome", bundleIDs: ["com.google.Chrome"], engine: .chromium,
                          dataRoot: "~/Library/Application Support/Google/Chrome", cacheRoot: "~/Library/Caches/Google/Chrome"),
        ProtectionBrowser(id: .firefox, name: "Firefox", bundleIDs: ["org.mozilla.firefox"], engine: .gecko,
                          dataRoot: "~/Library/Application Support/Firefox", cacheRoot: "~/Library/Caches/Firefox"),
        ProtectionBrowser(id: .edge, name: "Microsoft Edge", bundleIDs: ["com.microsoft.edgemac"], engine: .chromium,
                          dataRoot: "~/Library/Application Support/Microsoft Edge", cacheRoot: "~/Library/Caches/Microsoft Edge"),
        ProtectionBrowser(id: .brave, name: "Brave", bundleIDs: ["com.brave.Browser"], engine: .chromium,
                          dataRoot: "~/Library/Application Support/BraveSoftware/Brave-Browser",
                          cacheRoot: "~/Library/Caches/BraveSoftware/Brave-Browser"),
        ProtectionBrowser(id: .opera, name: "Opera", bundleIDs: ["com.operasoftware.Opera"], engine: .chromium,
                          dataRoot: "~/Library/Application Support/com.operasoftware.Opera",
                          cacheRoot: "~/Library/Caches/com.operasoftware.Opera"),
        ProtectionBrowser(id: .vivaldi, name: "Vivaldi", bundleIDs: ["com.vivaldi.Vivaldi"], engine: .chromium,
                          dataRoot: "~/Library/Application Support/Vivaldi", cacheRoot: "~/Library/Caches/Vivaldi"),
        ProtectionBrowser(id: .arc, name: "Arc", bundleIDs: ["company.thebrowser.Browser"], engine: .chromium,
                          dataRoot: "~/Library/Application Support/Arc/User Data", cacheRoot: "~/Library/Caches/Arc/User Data"),
    ]

    public static func browser(_ id: ProtectionBrowserID) -> ProtectionBrowser? { browsers.first { $0.id == id } }

    /// Profile-relative files per trace (Chromium).
    public static let chromiumFiles: [ProtectionTraceKind: [String]] = [
        .history: ["History", "History-journal", "Visited Links", "Shortcuts", "Shortcuts-journal",
                   "Network Action Predictor", "Network Action Predictor-journal"],
        .cookies: ["Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal",
                   "Extension Cookies", "Extension Cookies-journal"],
        .autofill: ["Web Data", "Web Data-journal"],
        .topSites: ["Top Sites", "Top Sites-journal", "Favicons", "Favicons-journal"],
        .sessions: ["Sessions", "Current Session", "Current Tabs", "Last Session", "Last Tabs"],
        // Shared stores that also hold extension data (Local Storage, File System) are left alone;
        // per-origin IndexedDB folders are added by the scanner, skipping extension origins.
        .siteData: ["Session Storage", "databases", "Service Worker/CacheStorage", "Service Worker/ScriptCache"],
        .cache: ["GPUCache", "Code Cache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache"],
    ]

    /// Profile-relative files per trace (Firefox).
    public static let firefoxFiles: [ProtectionTraceKind: [String]] = [
        .history: ["places.sqlite", "places.sqlite-wal", "places.sqlite-shm"],
        .cookies: ["cookies.sqlite", "cookies.sqlite-wal", "cookies.sqlite-shm"],
        .autofill: ["formhistory.sqlite", "formhistory.sqlite-wal", "formhistory.sqlite-shm"],
        .topSites: ["favicons.sqlite", "favicons.sqlite-wal", "favicons.sqlite-shm"],
        .sessions: ["sessionstore.jsonlz4", "sessionstore-backups"],
        // Per-origin folders in storage/default are added by the scanner, skipping extensions.
        .siteData: ["storage/temporary"],
    ]

    /// Logical paths per trace (Safari).
    public static let safariFiles: [ProtectionTraceKind: [String]] = [
        .history: ["~/Library/Safari/History.db", "~/Library/Safari/History.db-wal", "~/Library/Safari/History.db-shm",
                   "~/Library/Safari/History.db-lock", "~/Library/Safari/History.plist"],
        .downloads: ["~/Library/Safari/Downloads.plist"],
        .cookies: ["~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"],
        .autofill: ["~/Library/Safari/Form Values"],
        .topSites: ["~/Library/Safari/TopSites.plist", "~/Library/Safari/Favicon Cache", "~/Library/Safari/Touch Icons Cache",
                    "~/Library/Safari/Template Icons"],
        .sessions: ["~/Library/Safari/LastSession.plist", "~/Library/Safari/RecentlyClosedTabs.plist"],
        .siteData: ["~/Library/Safari/LocalStorage", "~/Library/Safari/Databases",
                    "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData"],
        .cache: ["~/Library/Caches/com.apple.Safari",
                 "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari"],
    ]

    /// Recent-items list name prefixes (Finder sidebar favourites are never touched).
    public static let recentListPrefixes: [String] = [
        "com.apple.LSSharedFileList.RecentApplications.",
        "com.apple.LSSharedFileList.RecentDocuments.",
        "com.apple.LSSharedFileList.RecentServers.",
        "com.apple.LSSharedFileList.RecentHosts.",
    ]
    public static let sharedFileListFolder = "~/Library/Application Support/com.apple.sharedfilelist"
    public static let applicationRecentDocumentsFolder = "com.apple.LSSharedFileList.ApplicationRecentDocuments"
    public static let quarantineEventsFile = "~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"

    /// Chromium profile folders under `root` (folders with a Preferences file; the root
    /// itself for browsers that keep a single profile at the top, like Opera).
    public static func chromiumProfiles(root: String) -> [String] {
        let fm = FileManager.default
        var profiles: [String] = []
        if fm.fileExists(atPath: root + "/Preferences") || fm.fileExists(atPath: root + "/History") {
            profiles.append(root)
        }
        for child in DiskUsage.children(of: root, includeHidden: false) {
            let name = (child as NSString).lastPathComponent
            guard name != "System Profile", fm.fileExists(atPath: child + "/Preferences") else { continue }
            profiles.append(child)
        }
        return profiles
    }

    /// Display names from Chromium's "Local State" (profile.info_cache).
    public static func chromiumProfileNames(root: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: root + "/Local State"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [:] }
        var names: [String: String] = [:]
        for (dir, value) in cache {
            if let info = value as? [String: Any], let name = info["name"] as? String { names[dir] = name }
        }
        return names
    }

    /// Firefox profile folders.
    public static func firefoxProfiles(root: String) -> [String] {
        DiskUsage.children(of: root + "/Profiles", includeHidden: false).filter {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue
        }
    }
}

// MARK: - Scanner

/// Finds privacy traces on disk. Foundation-only; running-browser checks happen in the engine.
public struct ProtectionPrivacyScanner: Sendable {
    public var space: ProtectionPathSpace
    public var guardian: PathGuard
    /// The Quick Look thumbnail cache folder (from the per-user Darwin cache dir), if known.
    public var quickLookCachePath: String?

    public init(space: ProtectionPathSpace, guardian: PathGuard? = nil, quickLookCachePath: String? = nil) {
        self.space = space
        self.guardian = guardian ?? PathGuard(home: space.home)
        self.quickLookCachePath = quickLookCachePath
    }

    /// Scans every installed browser plus macOS traces.
    public func scan(browsers: [ProtectionBrowser] = ProtectionPrivacyCatalog.browsers,
                     includeSystem: Bool = true, progress: ProgressHandler? = nil) -> [ProtectionTraceSource] {
        var sources: [ProtectionTraceSource] = []
        let total = Double(browsers.count + (includeSystem ? 1 : 0))
        for (index, browser) in browsers.enumerated() {
            progress?(ScanProgress(fraction: Double(index) / max(total, 1), message: "Looking at \(browser.name)…",
                                   current: browser.dataRoot))
            if let source = scan(browser: browser) { sources.append(source) }
        }
        if includeSystem {
            progress?(ScanProgress(fraction: Double(browsers.count) / max(total, 1), message: "Looking at macOS recent items…"))
            let system = scanSystem()
            if !system.traces.isEmpty { sources.append(system) }
        }
        progress?(ScanProgress(fraction: 1, message: "Done"))
        return sources
    }

    /// One browser's traces, or nil when it has no data on this Mac.
    public func scan(browser: ProtectionBrowser) -> ProtectionTraceSource? {
        let root = space.real(browser.dataRoot)
        guard FileWalker.entry(at: root) != nil else { return nil }
        switch browser.engine {
        case .webkit: return scanSafari(browser, root: root)
        case .chromium: return scanChromium(browser, root: root)
        case .gecko: return scanFirefox(browser, root: root)
        }
    }

    private func scanSafari(_ browser: ProtectionBrowser, root: String) -> ProtectionTraceSource? {
        if (try? FileManager.default.contentsOfDirectory(atPath: root)) == nil {
            return ProtectionTraceSource(id: browser.id.rawValue, title: browser.name, browser: browser, profiles: [],
                                         traces: [], isUnreadable: true)
        }
        var paths = ProtectionPrivacyCatalog.safariFiles.mapValues { $0.map(space.real) }
        // Safari profiles (Safari 17+) keep their own history.
        for profile in DiskUsage.children(of: root + "/Profiles", includeHidden: false) {
            for suffix in ["History.db", "History.db-wal", "History.db-shm", "History.db-lock"] {
                paths[.history, default: []].append(profile + "/" + suffix)
            }
        }
        let traces = ProtectionTraceKind.allCases.compactMap { kind -> ProtectionTrace? in
            guard let list = paths[kind] else { return nil }
            return makeTrace(sourceID: browser.id.rawValue, kind: kind, engine: .webkit, paths: list)
        }
        return ProtectionTraceSource(id: browser.id.rawValue, title: browser.name, browser: browser, profiles: [],
                                     traces: traces, isUnreadable: false)
    }

    private func scanChromium(_ browser: ProtectionBrowser, root: String) -> ProtectionTraceSource? {
        let profiles = ProtectionPrivacyCatalog.chromiumProfiles(root: root)
        guard !profiles.isEmpty else { return nil }
        let names = ProtectionPrivacyCatalog.chromiumProfileNames(root: root)
        var byKind: [ProtectionTraceKind: [String]] = [:]
        for profile in profiles {
            for (kind, files) in ProtectionPrivacyCatalog.chromiumFiles {
                byKind[kind, default: []].append(contentsOf: files.map { profile + "/" + $0 })
            }
            // Website databases, one folder per origin; extension storage (wallets, password
            // managers…) is never touched.
            for origin in DiskUsage.children(of: profile + "/IndexedDB")
                where !(origin as NSString).lastPathComponent.hasPrefix("chrome-extension_") {
                byKind[.siteData, default: []].append(origin)
            }
            if let cacheRoot = browser.cacheRoot {
                let cache = space.real(cacheRoot)
                let dirName = profile == root ? "" : "/" + (profile as NSString).lastPathComponent
                byKind[.cache, default: []].append(cache + dirName)
            }
        }
        let traces = ProtectionTraceKind.allCases.compactMap { kind -> ProtectionTrace? in
            guard let list = byKind[kind] else { return nil }
            return makeTrace(sourceID: browser.id.rawValue, kind: kind, engine: .chromium, paths: list)
        }
        let profileNames = profiles.map { profile -> String in
            let dir = (profile as NSString).lastPathComponent
            return names[dir] ?? (profile == root ? browser.name : dir)
        }
        return ProtectionTraceSource(id: browser.id.rawValue, title: browser.name, browser: browser,
                                     profiles: profileNames, traces: traces, isUnreadable: false)
    }

    private func scanFirefox(_ browser: ProtectionBrowser, root: String) -> ProtectionTraceSource? {
        let profiles = ProtectionPrivacyCatalog.firefoxProfiles(root: root)
        guard !profiles.isEmpty else { return nil }
        var byKind: [ProtectionTraceKind: [String]] = [:]
        for profile in profiles {
            for (kind, files) in ProtectionPrivacyCatalog.firefoxFiles {
                byKind[kind, default: []].append(contentsOf: files.map { profile + "/" + $0 })
            }
            for origin in DiskUsage.children(of: profile + "/storage/default")
                where !(origin as NSString).lastPathComponent.hasPrefix("moz-extension") {
                byKind[.siteData, default: []].append(origin)
            }
            if let cacheRoot = browser.cacheRoot {
                byKind[.cache, default: []].append(space.real(cacheRoot) + "/Profiles/" + (profile as NSString).lastPathComponent)
            }
        }
        let traces = ProtectionTraceKind.allCases.compactMap { kind -> ProtectionTrace? in
            guard let list = byKind[kind] else { return nil }
            var trace = makeTrace(sourceID: browser.id.rawValue, kind: kind, engine: .gecko, paths: list)
            // Firefox history shares its file with bookmarks: never pre-selected.
            if kind == .history { trace?.safety = .review }
            return trace
        }
        let names = profiles.map { profile -> String in
            let dir = (profile as NSString).lastPathComponent
            // "abcd1234.default-release" → "default-release"
            if let dot = dir.firstIndex(of: ".") { return String(dir[dir.index(after: dot)...]) }
            return dir
        }
        return ProtectionTraceSource(id: browser.id.rawValue, title: browser.name, browser: browser,
                                     profiles: names, traces: traces, isUnreadable: false)
    }

    /// macOS traces: recent items lists, Quick Look thumbnails, download log.
    public func scanSystem() -> ProtectionTraceSource {
        var traces: [ProtectionTrace] = []
        let folder = space.real(ProtectionPrivacyCatalog.sharedFileListFolder)
        var recent: [String] = []
        for child in DiskUsage.children(of: folder) {
            let name = (child as NSString).lastPathComponent
            if ProtectionPrivacyCatalog.recentListPrefixes.contains(where: { name.hasPrefix($0) }), name.contains(".sfl") {
                recent.append(child)
            }
        }
        for child in DiskUsage.children(of: folder + "/" + ProtectionPrivacyCatalog.applicationRecentDocumentsFolder) {
            if (child as NSString).lastPathComponent.contains(".sfl") { recent.append(child) }
        }
        if let trace = makeTrace(sourceID: ProtectionTraceSource.systemID, kind: .recentItems, engine: nil, paths: recent) {
            traces.append(trace)
        }
        if let quickLook = quickLookCachePath, FileWalker.entry(at: quickLook) != nil {
            let size = DiskUsage.measure(quickLook).bytes
            traces.append(ProtectionTrace(id: traceID(ProtectionTraceSource.systemID, .quickLookThumbnails),
                                          sourceID: ProtectionTraceSource.systemID, kind: .quickLookThumbnails,
                                          title: ProtectionTraceKind.quickLookThumbnails.title,
                                          detail: ProtectionTraceKind.quickLookThumbnails.detail(engine: nil),
                                          safety: .safe, files: [], customAction: ProtectionTrace.quickLookResetAction,
                                          measuredSize: size))
        }
        let log = space.real(ProtectionPrivacyCatalog.quarantineEventsFile)
        if let trace = makeTrace(sourceID: ProtectionTraceSource.systemID, kind: .downloadLog, engine: nil,
                                 paths: [log, log + "-journal", log + "-wal", log + "-shm"]) {
            traces.append(trace)
        }
        return ProtectionTraceSource(id: ProtectionTraceSource.systemID, title: "macOS", browser: nil, profiles: [],
                                     traces: traces, isUnreadable: false)
    }

    // MARK: Helpers

    public func traceID(_ sourceID: String, _ kind: ProtectionTraceKind) -> String {
        "privacy.\(sourceID).\(kind.rawValue)"
    }

    /// Builds a trace from the existing paths in `paths`; nil when none exist.
    func makeTrace(sourceID: String, kind: ProtectionTraceKind, engine: ProtectionBrowserEngine?, paths: [String]) -> ProtectionTrace? {
        var files: [ProtectionTraceFile] = []
        var seen = Set<String>()
        for path in paths {
            let standardized = (path as NSString).standardizingPath
            guard seen.insert(standardized).inserted, FileWalker.entry(at: standardized) != nil else { continue }
            let size = DiskUsage.measure(standardized).bytes
            let method: DeletionMethod = (kind == .cache && guardian.isInPermanentZone(standardized)) ? .remove : .trash
            guard guardian.check(standardized, method: method).isAllowed else { continue }
            files.append(ProtectionTraceFile(path: standardized, size: size, deletion: method))
        }
        guard !files.isEmpty else { return nil }
        return ProtectionTrace(id: traceID(sourceID, kind), sourceID: sourceID, kind: kind, title: kind.title,
                               detail: kind.detail(engine: engine), safety: kind.defaultSafety, files: files)
    }
}

// MARK: - Scan item mapping

public extension ProtectionTrace {
    /// The reviewable item for this trace (disposed by the engine, file by file).
    var scanItem: ScanItem {
        let fileList = files.map { "\($0.deletion.rawValue)\t\($0.path)" }.joined(separator: "\n")
        var metadata: [String: String] = [
            ProtectionMetaKey.tool: ProtectionMetaKey.privacyTool,
            ProtectionPrivacyMetaKey.source: sourceID,
            ProtectionPrivacyMetaKey.kind: kind.rawValue,
            ProtectionPrivacyMetaKey.files: fileList,
        ]
        if let customAction { metadata[ProtectionPrivacyMetaKey.action] = customAction }
        return ScanItem(id: id, title: title, subtitle: detail, url: nil, size: size,
                        itemCount: max(files.count, 1), safety: safety, deletion: .custom,
                        symbol: kind.symbol, note: detail, metadata: metadata)
    }
}

public enum ProtectionPrivacyMetaKey {
    public static let source = "privacy.source"
    public static let kind = "privacy.kind"
    public static let files = "privacy.files"
    public static let action = "privacy.action"
}

/// What cleaning one selected privacy item involves, decoded from its metadata.
public struct ProtectionPrivacyPlan: Sendable, Equatable {
    public var itemID: String
    public var title: String
    public var sourceID: String
    public var kind: ProtectionTraceKind
    public var files: [ProtectionTraceFile]
    public var customAction: String?

    public init?(item: ScanItem) {
        guard item.metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.privacyTool,
              let source = item.metadata[ProtectionPrivacyMetaKey.source],
              let kind = item.metadata[ProtectionPrivacyMetaKey.kind].flatMap(ProtectionTraceKind.init(rawValue:)) else { return nil }
        itemID = item.id
        title = item.title
        sourceID = source
        self.kind = kind
        customAction = item.metadata[ProtectionPrivacyMetaKey.action]
        files = (item.metadata[ProtectionPrivacyMetaKey.files] ?? "").split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, let method = DeletionMethod(rawValue: parts[0]) else { return nil }
            return ProtectionTraceFile(path: parts[1], size: 0, deletion: method)
        }
    }
}
