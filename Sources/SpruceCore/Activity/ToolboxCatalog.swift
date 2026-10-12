import Foundation

// MARK: - Catalog

/// Sections of the Toolbox's "All Tools" list.
public enum ToolboxGroup: String, CaseIterable, Sendable, Codable {
    case cleanup
    case protection
    case performance
    case applications
    case clutter
    case storage
    case utilities

    public var title: String {
        switch self {
        case .cleanup: return "Cleanup"
        case .protection: return "Protection"
        case .performance: return "Performance"
        case .applications: return "Applications"
        case .clutter: return "Clutter"
        case .storage: return "Storage & Cloud"
        case .utilities: return "Utilities"
        }
    }

    /// Module whose colours tint the section.
    public var module: ModuleID {
        switch self {
        case .cleanup: return .cleanup
        case .protection: return .protection
        case .performance: return .performance
        case .applications: return .applications
        case .clutter: return .clutter
        case .storage: return .spaceMap
        case .utilities: return .toolbox
        }
    }
}

/// One tool in the Toolbox. `id` is the app-wide tool identifier passed to
/// `AppModel.open(module, tool: id)`; Toolbox-only tools have ids starting with "toolbox.".
public struct ToolboxTool: Identifiable, Hashable, Sendable {
    public var id: String
    /// Module that hosts the tool's screen.
    public var module: ModuleID
    public var group: ToolboxGroup
    public var title: String
    public var caption: String
    public var symbol: String
    /// Search synonyms (lowercase).
    public var keywords: [String]
    /// Module palette used for the tile's badge.
    public var tint: ModuleID
    /// True when the tool does its job right away (a quick action) rather than scanning.
    public var isQuickAction: Bool
    /// True when the tool reads protected folders and works best with Full Disk Access.
    public var prefersFullDiskAccess: Bool

    public init(id: String, module: ModuleID, group: ToolboxGroup, title: String, caption: String, symbol: String,
                keywords: [String], tint: ModuleID? = nil, isQuickAction: Bool = false, prefersFullDiskAccess: Bool = false) {
        self.id = id
        self.module = module
        self.group = group
        self.title = title
        self.caption = caption
        self.symbol = symbol
        self.keywords = keywords
        self.tint = tint ?? module
        self.isQuickAction = isQuickAction
        self.prefersFullDiskAccess = prefersFullDiskAccess
    }

    /// True for tools whose screen lives inside the Toolbox itself.
    public var isToolboxOnly: Bool { module == .toolbox }
}

public enum ToolboxCatalog {
    /// Every tool, in display order.
    public static let all: [ToolboxTool] = [
        // Cleanup
        ToolboxTool(id: "cleanup.systemJunk", module: .cleanup, group: .cleanup, title: "System Junk",
                    caption: "Caches, logs and leftovers macOS can rebuild", symbol: "bubbles.and.sparkles",
                    keywords: ["cache", "caches", "logs", "junk", "temporary files", "clean"], prefersFullDiskAccess: true),
        ToolboxTool(id: "cleanup.mailAttachments", module: .cleanup, group: .cleanup, title: "Mail Attachments",
                    caption: "Local copies of attachments you can download again", symbol: "paperclip",
                    keywords: ["mail", "email", "attachments", "downloads"], prefersFullDiskAccess: true),
        ToolboxTool(id: "cleanup.trash", module: .cleanup, group: .cleanup, title: "Trash Bins",
                    caption: "Every Trash: startup disk, external drives and Mail", symbol: "trash",
                    keywords: ["trash", "bin", "bins", "empty", "external drives"], prefersFullDiskAccess: true),
        // Protection
        ToolboxTool(id: "protection.malware", module: .protection, group: .protection, title: "Malware Scan",
                    caption: "Find and remove adware, spyware and other threats", symbol: "exclamationmark.shield",
                    keywords: ["virus", "malware", "adware", "spyware", "threats", "antivirus", "security"]),
        ToolboxTool(id: "protection.privacy", module: .protection, group: .protection, title: "Privacy",
                    caption: "Clear browser history, cookies and recent items", symbol: "hand.raised",
                    keywords: ["history", "cookies", "browser", "safari", "chrome", "firefox", "recent items", "traces"],
                    prefersFullDiskAccess: true),
        ToolboxTool(id: "protection.permissions", module: .protection, group: .protection, title: "App Permissions",
                    caption: "See which apps can use the camera, microphone and files", symbol: "lock.shield",
                    keywords: ["camera", "microphone", "access", "permissions", "screen recording", "accessibility"],
                    prefersFullDiskAccess: true),
        // Performance
        ToolboxTool(id: "performance.maintenance", module: .performance, group: .performance, title: "Maintenance",
                    caption: "Run macOS upkeep tasks in one go", symbol: "wrench.adjustable",
                    keywords: ["spotlight", "reindex", "scripts", "purgeable", "tasks", "speed up", "repair"]),
        ToolboxTool(id: "performance.loginItems", module: .performance, group: .performance, title: "Login Items",
                    caption: "Choose which apps open when you log in", symbol: "power",
                    keywords: ["startup", "login", "launch at login", "boot", "autostart"]),
        ToolboxTool(id: "performance.backgroundItems", module: .performance, group: .performance, title: "Background Items",
                    caption: "Agents and daemons running behind the scenes", symbol: "gearshape.2",
                    keywords: ["launch agents", "daemons", "background", "helpers", "services"]),
        ToolboxTool(id: "performance.consumers", module: .performance, group: .performance, title: "Heavy Consumers",
                    caption: "Apps using the most CPU and memory right now", symbol: "gauge.with.dots.needle.67percent",
                    keywords: ["cpu", "memory", "slow", "processes", "activity", "hog", "quit"]),
        ToolboxTool(id: "toolbox.freeRAM", module: .toolbox, group: .performance, title: "Free Up RAM",
                    caption: "Release inactive memory in one step", symbol: "memorychip",
                    keywords: ["ram", "memory", "purge", "free memory"], tint: .performance, isQuickAction: true),
        ToolboxTool(id: "toolbox.flushDNS", module: .toolbox, group: .performance, title: "Flush DNS Cache",
                    caption: "Fix stale name lookups after network changes", symbol: "network",
                    keywords: ["dns", "network", "internet", "websites", "domain", "cache"], tint: .performance,
                    isQuickAction: true),
        // Applications
        ToolboxTool(id: "applications.uninstaller", module: .applications, group: .applications, title: "Uninstaller",
                    caption: "Remove apps with all their support files", symbol: "trash.square",
                    keywords: ["remove app", "delete app", "uninstall", "leftovers", "reset app"]),
        ToolboxTool(id: "applications.updater", module: .applications, group: .applications, title: "App Updates",
                    caption: "Update apps from one list", symbol: "arrow.down.circle",
                    keywords: ["update", "upgrade", "updater", "new version", "homebrew"]),
        ToolboxTool(id: "applications.leftovers", module: .applications, group: .applications, title: "Leftovers",
                    caption: "Files left behind by apps you already deleted", symbol: "shippingbox",
                    keywords: ["orphans", "remnants", "leftover", "support files", "deleted apps"]),
        ToolboxTool(id: "applications.installers", module: .applications, group: .applications, title: "Installers",
                    caption: "Old .dmg and .pkg installers you no longer need", symbol: "archivebox",
                    keywords: ["dmg", "pkg", "installer", "setup", "disk image"]),
        ToolboxTool(id: "applications.extensions", module: .applications, group: .applications, title: "Extensions",
                    caption: "Safari, Quick Look and other plug-ins", symbol: "puzzlepiece.extension",
                    keywords: ["plugins", "add-ons", "safari extensions", "quick look", "widgets", "preference panes"]),
        // Clutter
        ToolboxTool(id: "clutter.largeOld", module: .clutter, group: .clutter, title: "Large & Old Files",
                    caption: "Big or forgotten files, sorted by size and age", symbol: "doc.richtext",
                    keywords: ["big files", "large", "old", "size", "forgotten", "space"]),
        ToolboxTool(id: "clutter.duplicates", module: .clutter, group: .clutter, title: "Duplicates",
                    caption: "Identical copies, with smart keep-one selection", symbol: "doc.on.doc",
                    keywords: ["duplicate", "copies", "identical", "same files", "dupes"]),
        ToolboxTool(id: "clutter.similarImages", module: .clutter, group: .clutter, title: "Similar Photos",
                    caption: "Near-identical shots, bursts and screenshots", symbol: "photo.on.rectangle",
                    keywords: ["photos", "images", "pictures", "similar", "burst", "screenshots"]),
        ToolboxTool(id: "clutter.downloads", module: .clutter, group: .clutter, title: "Downloads",
                    caption: "Old installers, archives and documents in Downloads", symbol: "arrow.down.to.line",
                    keywords: ["downloads", "archives", "zip", "old downloads"]),
        // Storage & Cloud
        ToolboxTool(id: "spaceMap", module: .spaceMap, group: .storage, title: "Space Map",
                    caption: "See what takes space, folder by folder", symbol: "circle.hexagongrid.fill",
                    keywords: ["disk usage", "storage", "treemap", "space", "folders", "what is taking space"]),
        ToolboxTool(id: "cloudStorage", module: .cloudStorage, group: .storage, title: "Cloud Storage",
                    caption: "Free local copies of files kept in the cloud", symbol: "icloud",
                    keywords: ["icloud", "dropbox", "google drive", "onedrive", "cloud", "offload"]),
        // Utilities
        ToolboxTool(id: "toolbox.emptyTrash", module: .toolbox, group: .utilities, title: "Empty Trash",
                    caption: "See what's in your Trash, then erase it", symbol: "trash.slash",
                    keywords: ["trash", "bin", "empty", "erase"], tint: .cleanup, isQuickAction: true,
                    prefersFullDiskAccess: true),
        ToolboxTool(id: "toolbox.shredder", module: .toolbox, group: .utilities, title: "Shredder",
                    caption: "Overwrite files before deleting them for good", symbol: "scissors",
                    keywords: ["shred", "secure delete", "erase", "wipe", "destroy", "permanently delete"]),
        ToolboxTool(id: "toolbox.screenCleaning", module: .toolbox, group: .utilities, title: "Screen Cleaning",
                    caption: "Black out the display and lock input while you wipe it", symbol: "sparkles.tv",
                    keywords: ["wipe", "clean screen", "lock keyboard", "display", "smudges", "dust"], isQuickAction: true),
    ]

    /// Tools shown as favourites until the user changes them.
    public static let defaultFavorites: [String] = [
        "applications.uninstaller", "spaceMap", "clutter.duplicates", "performance.loginItems",
    ]

    private static let byID: [String: ToolboxTool] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func tool(id: String) -> ToolboxTool? { byID[id] }

    /// Tools grouped into sections, in display order (empty sections dropped).
    public static func grouped(_ tools: [ToolboxTool] = all) -> [(group: ToolboxGroup, tools: [ToolboxTool])] {
        ToolboxGroup.allCases.compactMap { group -> (group: ToolboxGroup, tools: [ToolboxTool])? in
            let members = tools.filter { $0.group == group }
            guard !members.isEmpty else { return nil }
            return (group: group, tools: members)
        }
    }

    // MARK: Search

    /// Tools matching `query`, best match first; favourites win ties, then catalog order.
    /// An empty query returns every tool in catalog order.
    public static func search(_ query: String, favorites: [String] = []) -> [ToolboxTool] {
        let q = normalize(query)
        guard !q.isEmpty else { return all }
        let favoriteSet = Set(favorites)
        return all.enumerated()
            .map { (offset: $0.offset, tool: $0.element, score: score($0.element, normalizedQuery: q)) }
            .filter { $0.score > 0 }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                let fa = favoriteSet.contains(a.tool.id), fb = favoriteSet.contains(b.tool.id)
                if fa != fb { return fa }
                return a.offset < b.offset
            }
            .map(\.tool)
    }

    /// Relevance of `tool` for `query` (0 = no match). Exact title > title prefix >
    /// title word prefix > keyword > section > description. Every word of a multi-word
    /// query must match somewhere.
    public static func score(_ tool: ToolboxTool, query: String) -> Int {
        score(tool, normalizedQuery: normalize(query))
    }

    static func score(_ tool: ToolboxTool, normalizedQuery q: String) -> Int {
        guard !q.isEmpty else { return 0 }
        let whole = tokenScore(q, tool)
        let tokens = q.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard tokens.count > 1 else { return whole }
        let per = tokens.map { tokenScore($0, tool) }
        let combined = per.contains(0) ? 0 : (per.min() ?? 0)
        return max(whole, combined)
    }

    private static func tokenScore(_ token: String, _ tool: ToolboxTool) -> Int {
        let title = normalize(tool.title)
        if title == token { return 1000 }
        if title.hasPrefix(token) { return 800 }
        if words(title).contains(where: { $0.hasPrefix(token) }) { return 600 }
        for keyword in tool.keywords.map(normalize) {
            if keyword == token { return 450 }
            if keyword.hasPrefix(token) { return 400 }
            if words(keyword).contains(where: { $0.hasPrefix(token) }) { return 350 }
        }
        let group = normalize(tool.group.title)
        if group.hasPrefix(token) || words(group).contains(where: { $0.hasPrefix(token) }) { return 250 }
        let caption = normalize(tool.caption)
        if words(caption).contains(where: { $0.hasPrefix(token) }) { return 200 }
        if token.count >= 3 && caption.contains(token) { return 150 }
        return 0
    }

    /// Lowercased, accent-free, single-spaced.
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return folded.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
    }

    private static func words(_ s: String) -> [Substring] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }
}

// MARK: - Favourites

/// Favourite tools, stored as an ordered list of tool ids (UserDefaults "toolbox.favorites").
public enum ToolboxFavorites {
    public static let defaultsKey = "toolbox.favorites"
    /// Most favourites shown.
    public static let limit = 12

    /// The favourites to show for a stored value: the defaults when nothing was ever
    /// stored, otherwise the stored ids that still exist (unknown ids skipped, no repeats).
    /// A default the user removed is never added back.
    public static func resolve(_ stored: [String]?) -> [String] {
        guard let stored else { return ToolboxCatalog.defaultFavorites }
        var seen = Set<String>()
        var result: [String] = []
        for id in stored where ToolboxCatalog.tool(id: id) != nil && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
            if result.count == limit { break }
        }
        return result
    }

    /// Adds the tool at the end, or removes it when already a favourite.
    public static func toggled(_ id: String, in favorites: [String]) -> [String] {
        if favorites.contains(id) { return favorites.filter { $0 != id } }
        guard ToolboxCatalog.tool(id: id) != nil else { return favorites }
        var next = favorites
        next.append(id)
        if next.count > limit { next.removeFirst(next.count - limit) }
        return next
    }

    /// Moves a favourite one place earlier (-1) or later (+1).
    public static func moved(_ id: String, by offset: Int, in favorites: [String]) -> [String] {
        guard let index = favorites.firstIndex(of: id) else { return favorites }
        let target = index + offset
        guard favorites.indices.contains(target) else { return favorites }
        var next = favorites
        next.swapAt(index, target)
        return next
    }
}
