import Foundation

// MARK: - Modules

/// Every top-level destination in the app's sidebar.
///
/// The raw values are stable identifiers used for persistence (settings,
/// activity history) — never rename them.
public enum ModuleID: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case checkup
    case cleanup
    case protection
    case performance
    case applications
    case clutter
    case spaceMap
    case cloudStorage
    case toolbox
    case activity

    public var id: String { rawValue }

    /// User-facing name.
    public var title: String {
        switch self {
        case .checkup: return "Checkup"
        case .cleanup: return "Cleanup"
        case .protection: return "Protection"
        case .performance: return "Performance"
        case .applications: return "Applications"
        case .clutter: return "Clutter"
        case .spaceMap: return "Space Map"
        case .cloudStorage: return "Cloud Storage"
        case .toolbox: return "Toolbox"
        case .activity: return "Activity"
        }
    }

    /// One-line description shown under the module title on its idle screen.
    public var tagline: String {
        switch self {
        case .checkup: return "One scan for junk, threats, speed, updates and clutter."
        case .cleanup: return "Clear caches, logs, leftovers and other system junk."
        case .protection: return "Find malware, clear privacy traces and review permissions."
        case .performance: return "Run maintenance tasks and tame what launches at login."
        case .applications: return "Uninstall completely, update, and remove leftovers."
        case .clutter: return "Find large, old, duplicate and similar files."
        case .spaceMap: return "See what is taking up space, at a glance."
        case .cloudStorage: return "Free local copies of files kept in the cloud."
        case .toolbox: return "Every individual tool, one click away."
        case .activity: return "Your Mac's health score and cleanup history."
        }
    }

    /// SF Symbol used in the sidebar.
    public var symbol: String {
        switch self {
        case .checkup: return "sparkles"
        case .cleanup: return "trash.circle"
        case .protection: return "shield.lefthalf.filled"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .applications: return "square.grid.2x2"
        case .clutter: return "doc.on.doc"
        case .spaceMap: return "circle.hexagongrid"
        case .cloudStorage: return "icloud"
        case .toolbox: return "wrench.and.screwdriver"
        case .activity: return "chart.bar.xaxis"
        }
    }

    /// Sidebar sections, in display order.
    public enum Section: String, CaseIterable, Sendable {
        case overview = "Overview"
        case modules = "Modules"
        case storage = "Storage"
        case more = "More"

        public var modules: [ModuleID] {
            switch self {
            case .overview: return [.checkup]
            case .modules: return [.cleanup, .protection, .performance, .applications, .clutter]
            case .storage: return [.spaceMap, .cloudStorage]
            case .more: return [.toolbox, .activity]
            }
        }
    }

    /// Modules that contribute a tile to Checkup, in tile order.
    public static let checkupContributors: [ModuleID] = [.cleanup, .protection, .performance, .applications, .clutter]
}

// MARK: - Safety

/// How confident we are that removing something is harmless.
///
/// * `safe`   — regenerated automatically by macOS or the owning app. May be pre-selected.
/// * `review` — probably unneeded, but the user should look first. Never pre-selected.
/// * `risky`  — can break an app or lose user data. Never pre-selected; requires an
///              explicit confirmation before removal.
public enum SafetyLevel: String, Codable, Sendable, Comparable, CaseIterable {
    case safe
    case review
    case risky

    private var rank: Int {
        switch self {
        case .safe: return 0
        case .review: return 1
        case .risky: return 2
        }
    }

    public static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool { lhs.rank < rhs.rank }

    public var label: String {
        switch self {
        case .safe: return "Safe to remove"
        case .review: return "Review before removing"
        case .risky: return "Removing may break things"
        }
    }
}

/// How a selected item is disposed of.
public enum DeletionMethod: String, Codable, Sendable {
    /// Move to the user's Trash (recoverable). The default for anything user-visible.
    case trash
    /// Delete immediately. Only for regenerable caches/logs and items inside the Trash.
    case remove
    /// The owning engine performs a custom action (e.g. evict a cloud file, disable a
    /// login item, run a maintenance command).
    case custom
}

// MARK: - Scan results

/// A single actionable thing found by a scan: a file, folder, app, login item, threat…
public struct ScanItem: Identifiable, Hashable, Sendable, Codable {
    /// Stable identifier. For file system items this is the standardized path.
    public var id: String
    public var title: String
    public var subtitle: String?
    /// Location on disk, if the item is a file system object.
    public var url: URL?
    /// Bytes reclaimed if removed (allocated size on disk).
    public var size: Int64
    /// Number of files represented (1 for a plain file, N for a folder).
    public var itemCount: Int
    public var safety: SafetyLevel
    public var isSelected: Bool
    public var deletion: DeletionMethod
    public var lastUsed: Date?
    public var modified: Date?
    /// SF Symbol hint for the row icon (the UI falls back to the file icon for URLs).
    public var symbol: String?
    /// Short explanation shown in the inspector ("Why is this here?").
    public var note: String?
    /// Free-form engine-specific data (bundle id, rule id, command id…).
    public var metadata: [String: String]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        url: URL? = nil,
        size: Int64 = 0,
        itemCount: Int = 1,
        safety: SafetyLevel = .review,
        isSelected: Bool? = nil,
        deletion: DeletionMethod = .trash,
        lastUsed: Date? = nil,
        modified: Date? = nil,
        symbol: String? = nil,
        note: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.size = size
        self.itemCount = itemCount
        self.safety = safety
        // Safe items are pre-selected by default; review items only when the engine
        // explicitly asks (e.g. duplicate "smart selection"); risky items never are.
        let requested = isSelected ?? (safety == .safe)
        self.isSelected = requested && safety != .risky
        self.deletion = deletion
        self.lastUsed = lastUsed
        self.modified = modified
        self.symbol = symbol
        self.note = note
        self.metadata = metadata
    }

    /// Convenience for file system items.
    public static func file(
        _ url: URL,
        size: Int64,
        itemCount: Int = 1,
        safety: SafetyLevel,
        deletion: DeletionMethod = .trash,
        title: String? = nil,
        subtitle: String? = nil,
        note: String? = nil,
        lastUsed: Date? = nil,
        modified: Date? = nil,
        metadata: [String: String] = [:]
    ) -> ScanItem {
        ScanItem(
            id: url.standardizedFileURL.path,
            title: title ?? url.lastPathComponent,
            subtitle: subtitle ?? url.deletingLastPathComponent().path.abbreviatingHome,
            url: url,
            size: size,
            itemCount: itemCount,
            safety: safety,
            deletion: deletion,
            lastUsed: lastUsed,
            modified: modified,
            note: note,
            metadata: metadata
        )
    }
}

/// A named collection of items (and optional sub-groups), e.g. "User Cache Files".
public struct ScanGroup: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var safety: SafetyLevel
    public var items: [ScanItem]
    public var children: [ScanGroup]

    public init(
        id: String,
        title: String,
        detail: String = "",
        symbol: String = "folder",
        safety: SafetyLevel = .review,
        items: [ScanItem] = [],
        children: [ScanGroup] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.safety = safety
        self.items = items
        self.children = children
    }

    /// Every item in this group and all sub-groups.
    public var allItems: [ScanItem] { items + children.flatMap(\.allItems) }

    public var totalSize: Int64 { allItems.reduce(0) { $0 + $1.size } }
    public var selectedSize: Int64 { allItems.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    public var totalCount: Int { allItems.count }
    public var selectedCount: Int { allItems.filter(\.isSelected).count }
    public var isEmpty: Bool { allItems.isEmpty }

    /// Selection state for a tri-state group checkbox.
    public var selectionState: SelectionState {
        let all = allItems
        guard !all.isEmpty else { return .none }
        let selected = all.filter(\.isSelected).count
        if selected == 0 { return .none }
        return selected == all.count ? .all : .some
    }

    /// Selects or deselects every item. Risky items are never bulk-selected.
    public mutating func setAllSelected(_ selected: Bool) {
        for i in items.indices {
            items[i].isSelected = selected && items[i].safety != .risky
        }
        for i in children.indices {
            children[i].setAllSelected(selected)
        }
    }

    /// Sets the selection of one item anywhere in the tree. Returns true if found.
    @discardableResult
    public mutating func setSelected(_ selected: Bool, itemID: String) -> Bool {
        if let i = items.firstIndex(where: { $0.id == itemID }) {
            items[i].isSelected = selected
            return true
        }
        for i in children.indices where children[i].setSelected(selected, itemID: itemID) {
            return true
        }
        return false
    }

    /// Removes the given item ids anywhere in the tree (after they were cleaned).
    public mutating func removeItems(withIDs ids: Set<String>) {
        items.removeAll { ids.contains($0.id) }
        for i in children.indices { children[i].removeItems(withIDs: ids) }
        children.removeAll { $0.isEmpty }
    }
}

public enum SelectionState: Sendable { case none, some, all }

public extension Array where Element == ScanGroup {
    var allItems: [ScanItem] { flatMap(\.allItems) }
    var totalSize: Int64 { reduce(0) { $0 + $1.totalSize } }
    var selectedSize: Int64 { reduce(0) { $0 + $1.selectedSize } }
    var selectedItems: [ScanItem] { allItems.filter(\.isSelected) }

    mutating func setSelected(_ selected: Bool, itemID: String) {
        for i in indices where self[i].setSelected(selected, itemID: itemID) { return }
    }

    mutating func removeItems(withIDs ids: Set<String>) {
        for i in indices { self[i].removeItems(withIDs: ids) }
        removeAll { $0.isEmpty }
    }
}

// MARK: - Progress & outcomes

/// Progress reported by long-running scans and runs.
public struct ScanProgress: Sendable, Equatable {
    /// 0...1, or nil when indeterminate.
    public var fraction: Double?
    /// Short status line ("Scanning caches…").
    public var message: String
    /// Path or item currently being processed (shown truncated in the UI).
    public var current: String?
    /// Running total of reclaimable bytes found so far.
    public var bytesFound: Int64

    public init(fraction: Double? = nil, message: String, current: String? = nil, bytesFound: Int64 = 0) {
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.message = message
        self.current = current
        self.bytesFound = bytesFound
    }
}

public typealias ProgressHandler = @Sendable (ScanProgress) -> Void

/// A failure for one item during a run. Runs never abort on a single failure.
public struct ItemFailure: Codable, Hashable, Sendable {
    public var itemID: String
    public var title: String
    public var reason: String

    public init(itemID: String, title: String, reason: String) {
        self.itemID = itemID
        self.title = title
        self.reason = reason
    }
}

/// The result of performing actions (cleaning, removing, running tasks).
public struct RunOutcome: Codable, Hashable, Sendable {
    public var module: ModuleID
    public var date: Date
    public var freedBytes: Int64
    public var processedCount: Int
    public var removedItemIDs: [String]
    public var failures: [ItemFailure]
    /// Short human summary ("Removed 1,204 files").
    public var summary: String

    public init(
        module: ModuleID,
        date: Date = Date(),
        freedBytes: Int64 = 0,
        processedCount: Int = 0,
        removedItemIDs: [String] = [],
        failures: [ItemFailure] = [],
        summary: String = ""
    ) {
        self.module = module
        self.date = date
        self.freedBytes = freedBytes
        self.processedCount = processedCount
        self.removedItemIDs = removedItemIDs
        self.failures = failures
        self.summary = summary
    }

    public static func merged(_ outcomes: [RunOutcome], module: ModuleID, summary: String = "") -> RunOutcome {
        RunOutcome(
            module: module,
            freedBytes: outcomes.reduce(0) { $0 + $1.freedBytes },
            processedCount: outcomes.reduce(0) { $0 + $1.processedCount },
            removedItemIDs: outcomes.flatMap(\.removedItemIDs),
            failures: outcomes.flatMap(\.failures),
            summary: summary
        )
    }
}

// MARK: - Checkup

/// Overall state of one Checkup tile.
public enum TileStatus: String, Codable, Sendable {
    /// Nothing to do.
    case clear
    /// Recommended actions available.
    case attention
    /// Something important (e.g. a threat) needs action.
    case critical
    /// Informational only.
    case info
    /// Module was excluded in settings or could not run (e.g. missing permission).
    case unavailable
}

/// One tile on the Checkup results screen.
public struct CheckupTile: Identifiable, Sendable, Equatable {
    public var module: ModuleID
    public var id: ModuleID { module }
    /// Big value line, e.g. "4.2 GB" or "No threats".
    public var headline: String
    /// Secondary line, e.g. "of junk to clean".
    public var detail: String
    public var status: TileStatus
    /// Whether the tile's actions are included in "Run" by default.
    public var isSelected: Bool
    /// Bytes this tile will free when run (0 when not applicable).
    public var reclaimableBytes: Int64
    /// Number of recommended actions.
    public var actionCount: Int

    public init(
        module: ModuleID,
        headline: String,
        detail: String,
        status: TileStatus,
        isSelected: Bool? = nil,
        reclaimableBytes: Int64 = 0,
        actionCount: Int = 0
    ) {
        self.module = module
        self.headline = headline
        self.detail = detail
        self.status = status
        self.isSelected = isSelected ?? (status == .attention || status == .critical)
        self.reclaimableBytes = reclaimableBytes
        self.actionCount = actionCount
    }

    public static func unavailable(_ module: ModuleID, reason: String) -> CheckupTile {
        CheckupTile(module: module, headline: "Skipped", detail: reason, status: .unavailable, isSelected: false)
    }
}

/// Implemented by each module engine that contributes a tile to Checkup.
///
/// `checkupScan` performs the module's quick scan and remembers the result;
/// `checkupRun` performs only the default-safe recommended actions from that scan.
public protocol CheckupContributor: AnyObject {
    var module: ModuleID { get }
    /// Reviewable items found by the last `checkupScan`. The Checkup review sheet edits
    /// the selection; `checkupRun` acts only on selected items.
    var checkupReview: [ScanGroup] { get set }
    func checkupScan(progress: @escaping ProgressHandler) async throws -> CheckupTile
    func checkupRun(progress: @escaping ProgressHandler) async throws -> RunOutcome
}

// MARK: - Catalog descriptors

/// Describes a scan category (e.g. a Cleanup group) for settings and help screens.
/// `CleanupCatalog.categories` (SpruceCore/Cleanup) returns these; Settings › Scanning
/// uses them to let the user exclude categories (`SpruceSettings.excludedCleanupCategories`).
public struct CategoryDescriptor: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String

    public init(id: String, title: String, detail: String = "", symbol: String = "folder") {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

// MARK: - Errors

public enum SpruceError: LocalizedError, Sendable, Equatable {
    case blockedPath(String)
    case notFound(String)
    case permissionDenied(String)
    case needsFullDiskAccess
    case cancelled
    case commandFailed(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .blockedPath(let p): return "Protected location, refused to touch: \(p)"
        case .notFound(let p): return "Not found: \(p)"
        case .permissionDenied(let p): return "Permission denied: \(p)"
        case .needsFullDiskAccess: return "Full Disk Access is required for this action."
        case .cancelled: return "Cancelled."
        case .commandFailed(let m): return m
        case .unsupported(let m): return m
        }
    }
}

// MARK: - Helpers

public extension String {
    /// Replaces the user's home directory prefix with "~".
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        if self == home { return "~" }
        if hasPrefix(home + "/") { return "~" + dropFirst(home.count) }
        return self
    }

    /// Expands a leading "~" to the user's home directory.
    var expandingTilde: String {
        if self == "~" { return NSHomeDirectory() }
        if hasPrefix("~/") { return NSHomeDirectory() + dropFirst(1) }
        return self
    }
}
