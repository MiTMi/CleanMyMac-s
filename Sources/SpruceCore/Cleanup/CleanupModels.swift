import Foundation

// MARK: - Sections & categories

/// The three top-level parts of the Cleanup module.
public enum CleanupSection: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case systemJunk
    case mailAttachments
    case trashBins

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .systemJunk: return "System Junk"
        case .mailAttachments: return "Mail Attachments"
        case .trashBins: return "Trash Bins"
        }
    }

    /// One-line explanation used on cards and in the review header.
    public var detail: String {
        switch self {
        case .systemJunk: return "Caches, logs and leftovers that macOS and your apps rebuild on their own."
        case .mailAttachments: return "Local copies of attachments. Opening the message downloads them again."
        case .trashBins: return "Files you already threw away, still taking up space."
        }
    }

    public var symbol: String {
        switch self {
        case .systemJunk: return "internaldrive"
        case .mailAttachments: return "paperclip"
        case .trashBins: return "trash"
        }
    }

    /// The navigation tool identifier (`AppModel.open(_:tool:)`) for this section.
    public var toolID: String {
        switch self {
        case .systemJunk: return "cleanup.systemJunk"
        case .mailAttachments: return "cleanup.mailAttachments"
        case .trashBins: return "cleanup.trash"
        }
    }

    public init?(toolID: String) {
        guard let match = CleanupSection.allCases.first(where: { $0.toolID == toolID }) else { return nil }
        self = match
    }

    public var categories: [CleanupCategory] {
        CleanupCategory.allCases.filter { $0.section == self }
    }
}

/// A user-visible scan category. The raw value is the stable id stored in
/// `SpruceSettings.excludedCleanupCategories` (never rename).
public enum CleanupCategory: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case userCaches = "systemJunk.userCaches"
    case systemCaches = "systemJunk.systemCaches"
    case userLogs = "systemJunk.userLogs"
    case systemLogs = "systemJunk.systemLogs"
    case tempFiles = "systemJunk.tempFiles"
    case xcodeJunk = "systemJunk.xcodeJunk"
    case devJunk = "systemJunk.devJunk"
    case oldUpdates = "systemJunk.oldUpdates"
    case iosSoftwareUpdates = "systemJunk.iosSoftware"
    case iosBackups = "systemJunk.iosBackups"
    case brokenPreferences = "systemJunk.brokenPreferences"
    case brokenLoginItems = "systemJunk.brokenLoginItems"
    case incompleteDownloads = "systemJunk.brokenDownloads"
    case documentVersions = "systemJunk.documentVersions"
    case deletedUsers = "systemJunk.deletedUsers"
    case mailAttachments = "mailAttachments"
    case trashBins = "trashBins"

    public var id: String { rawValue }

    public var section: CleanupSection {
        switch self {
        case .mailAttachments: return .mailAttachments
        case .trashBins: return .trashBins
        default: return .systemJunk
        }
    }

    public var title: String {
        switch self {
        case .userCaches: return "User Cache Files"
        case .systemCaches: return "System Cache Files"
        case .userLogs: return "User Log Files"
        case .systemLogs: return "System Log Files"
        case .tempFiles: return "Temporary Files"
        case .xcodeJunk: return "Xcode Junk"
        case .devJunk: return "Development Junk"
        case .oldUpdates: return "Old Updates"
        case .iosSoftwareUpdates: return "iOS Software Updates"
        case .iosBackups: return "iOS Device Backups"
        case .brokenPreferences: return "Broken Preferences"
        case .brokenLoginItems: return "Broken Login Items"
        case .incompleteDownloads: return "Incomplete Downloads"
        case .documentVersions: return "Document Versions"
        case .deletedUsers: return "Deleted Users"
        case .mailAttachments: return "Mail Attachments"
        case .trashBins: return "Trash Bins"
        }
    }

    public var detail: String {
        switch self {
        case .userCaches:
            return "Data apps store to load faster. Apps rebuild it as needed; caches of open apps are left alone."
        case .systemCaches:
            return "Caches of macOS services and shared components. Needs your administrator password."
        case .userLogs:
            return "Activity and crash logs written by your apps, older than a week."
        case .systemLogs:
            return "Logs and crash reports of system services, older than a week. Needs your administrator password."
        case .tempFiles:
            return "Your own temporary files that haven't been touched for several days."
        case .xcodeJunk:
            return "Build data, device symbols and caches Xcode recreates. Skipped while Xcode is building."
        case .devJunk:
            return "Download caches of package managers (Homebrew, npm, pip, Cargo, Gradle and more)."
        case .oldUpdates:
            return "Update archives apps downloaded and already installed."
        case .iosSoftwareUpdates:
            return "iPhone and iPad firmware files. They download again whenever a device needs them."
        case .iosBackups:
            return "Backups of your iPhone and iPad. Never selected automatically — review them yourself."
        case .brokenPreferences:
            return "Settings files that are empty or damaged. The app creates a fresh one; they go to the Trash."
        case .brokenLoginItems:
            return "Launch agents that point to programs that no longer exist."
        case .incompleteDownloads:
            return "Downloads that never finished. They go to the Trash."
        case .documentVersions:
            return "Earlier versions of your documents kept by macOS. Shown for information only."
        case .deletedUsers:
            return "Archives of deleted user accounts. Shown for information only."
        case .mailAttachments:
            return "Attachments Mail keeps on this Mac after you open them."
        case .trashBins:
            return "The Trash of your startup disk and of connected drives."
        }
    }

    public var symbol: String {
        switch self {
        case .userCaches: return "internaldrive"
        case .systemCaches: return "gearshape.2"
        case .userLogs: return "doc.text"
        case .systemLogs: return "doc.text.magnifyingglass"
        case .tempFiles: return "clock.arrow.circlepath"
        case .xcodeJunk: return "hammer"
        case .devJunk: return "shippingbox"
        case .oldUpdates: return "arrow.triangle.2.circlepath"
        case .iosSoftwareUpdates: return "arrow.down.circle"
        case .iosBackups: return "iphone"
        case .brokenPreferences: return "slider.horizontal.3"
        case .brokenLoginItems: return "person.crop.circle.badge.xmark"
        case .incompleteDownloads: return "arrow.down.doc"
        case .documentVersions: return "doc.on.doc"
        case .deletedUsers: return "person.badge.minus"
        case .mailAttachments: return "paperclip"
        case .trashBins: return "trash"
        }
    }

    /// Categories that never produce removable items, only `CleanupInsight`s.
    public var isInformational: Bool {
        self == .documentVersions || self == .deletedUsers
    }

    /// Overall safety of the category, used for its result group.
    public var nominalSafety: SafetyLevel {
        switch self {
        case .iosBackups, .documentVersions, .deletedUsers: return .review
        default: return .safe
        }
    }

    public var descriptor: CategoryDescriptor {
        CategoryDescriptor(id: rawValue, title: title, detail: detail, symbol: symbol)
    }
}

// MARK: - Rules

/// One entry of the Cleanup rule catalog ("safety database").
///
/// A rule finds *rows* (`paths`, tilde globs) and says how each row is disposed of.
public struct CleanupRule: Sendable, Hashable, Identifiable {

    /// What a matched path represents.
    public enum Target: String, Sendable, Hashable {
        /// Every match is one row, removed as a whole.
        case each
        /// Every match is a folder whose direct children are removed; the folder stays
        /// (sandboxed apps expect their cache folder to exist). Files are treated as `each`.
        case contents
        /// Every match is a folder; regular files anywhere below it are removed, folders stay.
        case files
        /// Every match is a search root; each file (or bundle) whose name matches
        /// `namePatterns` anywhere below it is one row, removed as a whole.
        case findFiles
    }

    /// Skip (or deselect) rows whose owning app or tool is running.
    public enum Gate: Sendable, Hashable {
        case none
        /// The owner is the path component matched by the pattern's first wildcard.
        case ownerAtWildcard
        /// The owner is the first path component below the row folder (files mode).
        case ownerBelowRow
        /// The owner is the preference domain in the file name.
        case ownerFromFileName
        /// Fixed owners.
        case bundleIDs([String])
        /// Xcode and its build tooling.
        case xcode
        /// A booted iOS Simulator.
        case simulator
    }

    /// Special detection logic beyond glob + age.
    public enum Analyzer: String, Sendable, Hashable {
        case none
        case brokenPreference
        case launchAgent
        case newestKept
        case iosBackup
        case mailDownload
        case derivedData
        case mailStored
        case externalTrash
        // Insight-only analyzers:
        case systemLaunchItems
        case mailTrash
        case documentVersions
        case deletedUsers
        case installerApps

        public var producesInsightsOnly: Bool {
            switch self {
            case .systemLaunchItems, .mailTrash, .documentVersions, .deletedUsers, .installerApps: return true
            default: return false
            }
        }
    }

    /// What happens to a row whose owning app (per `gate`) is open.
    public enum RunningPolicy: String, Sendable, Hashable {
        /// Listed unchecked, and skipped at clean time while the app is open.
        case skip
        /// Selected as usual (CleanMyMac 5 behaviour for app caches): the Clean / Run
        /// step asks to quit the app first, and the row is skipped if it stays open.
        /// While the app is open its content is counted regardless of `minAge`, since
        /// nothing is removed before it quits.
        case quitFirst
        /// The app being open doesn't matter (e.g. log files older than a week, which no
        /// app is still writing).
        case allow
    }

    public enum AgeBasis: String, Sendable, Hashable {
        /// Newest modification date.
        case modification
        /// Newest of modification and access date (temporary files).
        case modificationAndAccess
    }

    public var id: String
    public var category: CleanupCategory
    public var title: String
    /// Tilde globs. Tokens: `~`, `$TMPDIR`, `$DARWIN_CACHE`, `$UID`. Other absolute
    /// paths are system locations.
    public var paths: [String]
    public var target: Target
    public var safety: SafetyLevel
    public var defaultSelected: Bool
    public var deletion: DeletionMethod
    /// Root-owned locations; removal is retried as administrator (one prompt).
    public var needsAdmin: Bool
    /// TCC-protected; skipped (and reported unavailable) without Full Disk Access.
    public var needsFullDiskAccess: Bool
    /// Content modified more recently than this (seconds) is not counted or removed.
    public var minAge: TimeInterval
    public var ageBasis: AgeBasis
    public var gate: Gate
    /// How rows of an open app are treated (see `RunningPolicy`).
    public var whileRunning: RunningPolicy
    /// Name globs a file must match (files/findFiles/each). Empty = any name.
    public var namePatterns: [String]
    /// Child-name globs that are never counted.
    public var excludedNames: [String]
    /// Row-name globs shown unchecked (review) instead of pre-selected.
    public var reviewNames: [String]
    /// The rule's folders are regenerable zones where permanent removal is acceptable
    /// even though `PathGuard` does not list them.
    public var addsPermanentZone: Bool
    /// Include hidden (dot) entries when a wildcard matches.
    public var includeHidden: Bool
    /// Only files owned by the current user (temporary files).
    public var ownFilesOnly: Bool
    /// Depth limit for files/findFiles walks.
    public var maxDepth: Int?
    /// Seconds allowed to measure one row before reporting a partial size.
    public var measureBudget: TimeInterval
    public var analyzer: Analyzer
    /// "Why is this here?" text.
    public var note: String

    public init(
        id: String,
        category: CleanupCategory,
        title: String,
        paths: [String],
        target: Target = .contents,
        safety: SafetyLevel = .safe,
        defaultSelected: Bool? = nil,
        deletion: DeletionMethod = .remove,
        needsAdmin: Bool = false,
        needsFullDiskAccess: Bool = false,
        minAge: TimeInterval = 0,
        ageBasis: AgeBasis = .modification,
        gate: Gate = .none,
        whileRunning: RunningPolicy = .skip,
        namePatterns: [String] = [],
        excludedNames: [String] = [],
        reviewNames: [String] = [],
        addsPermanentZone: Bool = false,
        includeHidden: Bool = false,
        ownFilesOnly: Bool = false,
        maxDepth: Int? = nil,
        measureBudget: TimeInterval = 20,
        analyzer: Analyzer = .none,
        note: String
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.paths = paths
        self.target = target
        self.safety = safety
        self.defaultSelected = (defaultSelected ?? (safety == .safe)) && safety != .risky
        self.deletion = deletion
        self.needsAdmin = needsAdmin
        self.needsFullDiskAccess = needsFullDiskAccess
        self.minAge = minAge
        self.ageBasis = ageBasis
        self.gate = gate
        self.whileRunning = whileRunning
        self.namePatterns = namePatterns
        self.excludedNames = excludedNames
        self.reviewNames = reviewNames
        self.addsPermanentZone = addsPermanentZone
        self.includeHidden = includeHidden
        self.ownFilesOnly = ownFilesOnly
        self.maxDepth = maxDepth
        self.measureBudget = measureBudget
        self.analyzer = analyzer
        self.note = note
    }

    /// Whether Checkup's one-click scan may use this rule (safe, pre-selected,
    /// user-level, no review-only data).
    public var isCheckupEligible: Bool {
        safety == .safe && defaultSelected && !needsAdmin && !analyzer.producesInsightsOnly
            && analyzer != .mailStored && category != .iosBackups && deletion == .remove
    }
}

// MARK: - Scan context

/// Why a scan runs; Checkup only gathers the safe, pre-selected subset.
public enum CleanupScanPurpose: String, Sendable, Codable {
    case module
    case checkup
}

/// A mounted, writable, local volume other than the startup disk.
public struct CleanupVolume: Sendable, Hashable, Codable {
    public var path: String
    public var name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

/// A Mail account, keyed by its folder name under `~/Library/Mail/V*`.
public struct CleanupMailAccount: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// IMAP, iCloud or Exchange: attachments can be downloaded again.
        case server
        /// POP: the local copy may be the only one.
        case pop
        /// "On My Mac" mailboxes.
        case local
        case unknown
    }

    public var name: String
    public var kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    public var isRecoverable: Bool { kind == .server }
}

/// Everything the scanner needs to know about the machine. The Mac engine fills it in;
/// tests point `home`/`systemRoot` at temporary directories.
public struct CleanupContext: Sendable {
    /// The user's home folder (symlinks resolved).
    public var home: String
    /// Prefix applied to absolute system rule paths (`/Library/Caches`…). Empty in the app.
    public var systemRoot: String
    public var uid: UInt32
    /// Per-user temporary folder (`…/T`), symlinks resolved.
    public var userTempDir: String?
    /// Per-user Darwin cache folder (`…/C`), symlinks resolved.
    public var userCacheDir: String?
    public var startupVolumeName: String
    public var externalVolumes: [CleanupVolume]
    public var runningBundleIDs: Set<String>
    /// Executable names of running processes (Xcode tooling detection).
    public var runningProcessNames: Set<String>
    public var hasFullDiskAccess: Bool
    /// Our own bundle identifier; its data is never offered.
    public var ownBundleID: String?
    public var mailAccounts: [String: CleanupMailAccount]
    /// Resolves a bundle identifier to an app's display name.
    public var appName: (@Sendable (String) -> String?)?
    public var now: Date
    public var purpose: CleanupScanPurpose
    public var documentRevisionsPaths: [String]
    public var deletedUsersPath: String

    public init(
        home: String,
        systemRoot: String = "",
        uid: UInt32 = CleanupContext.currentUID,
        userTempDir: String? = nil,
        userCacheDir: String? = nil,
        startupVolumeName: String = "Macintosh HD",
        externalVolumes: [CleanupVolume] = [],
        runningBundleIDs: Set<String> = [],
        runningProcessNames: Set<String> = [],
        hasFullDiskAccess: Bool = true,
        ownBundleID: String? = nil,
        mailAccounts: [String: CleanupMailAccount] = [:],
        appName: (@Sendable (String) -> String?)? = nil,
        now: Date = Date(),
        purpose: CleanupScanPurpose = .module,
        documentRevisionsPaths: [String] = ["/System/Volumes/Data/.DocumentRevisions-V100", "/.DocumentRevisions-V100"],
        deletedUsersPath: String = "/Users/Deleted Users"
    ) {
        self.home = home
        self.systemRoot = systemRoot
        self.uid = uid
        self.userTempDir = userTempDir
        self.userCacheDir = userCacheDir
        self.startupVolumeName = startupVolumeName
        self.externalVolumes = externalVolumes
        self.runningBundleIDs = runningBundleIDs
        self.runningProcessNames = runningProcessNames
        self.hasFullDiskAccess = hasFullDiskAccess
        self.ownBundleID = ownBundleID
        self.mailAccounts = mailAccounts
        self.appName = appName
        self.now = now
        self.purpose = purpose
        self.documentRevisionsPaths = documentRevisionsPaths
        self.deletedUsersPath = deletedUsersPath
    }

    /// The real user id of this process.
    public static var currentUID: UInt32 { UInt32(getuid()) }
}

// MARK: - Results

/// Something worth knowing that Cleanup deliberately does not remove itself
/// (document versions, deleted users, Mail's trash, system launch items…).
public struct CleanupInsight: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var category: CleanupCategory
    public var title: String
    public var detail: String
    /// Bytes involved, when they could be measured.
    public var size: Int64?
    public var path: String?
    public var symbol: String

    public init(id: String, category: CleanupCategory, title: String, detail: String, size: Int64? = nil,
                path: String? = nil, symbol: String? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.size = size
        self.path = path
        self.symbol = symbol ?? category.symbol
    }
}

/// A category that could not be scanned.
public struct CleanupUnavailable: Identifiable, Hashable, Sendable, Codable {
    public enum Reason: String, Sendable, Codable {
        case fullDiskAccess
        case permissionDenied
    }

    public var category: CleanupCategory
    public var reason: Reason
    public var id: String { category.rawValue }

    public init(category: CleanupCategory, reason: Reason) {
        self.category = category
        self.reason = reason
    }

    public var message: String {
        switch reason {
        case .fullDiskAccess: return "Needs Full Disk Access"
        case .permissionDenied: return "macOS denied access"
        }
    }
}

/// Output of scanning one rule.
public struct CleanupRuleResult: Sendable {
    public var ruleID: String
    public var category: CleanupCategory
    public var items: [ScanItem]
    public var insights: [CleanupInsight]
    public var unavailable: CleanupUnavailable?

    public init(ruleID: String, category: CleanupCategory, items: [ScanItem] = [], insights: [CleanupInsight] = [],
                unavailable: CleanupUnavailable? = nil) {
        self.ruleID = ruleID
        self.category = category
        self.items = items
        self.insights = insights
        self.unavailable = unavailable
    }

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// The assembled outcome of a Cleanup scan.
public struct CleanupScanReport: Sendable {
    public var groups: [ScanGroup]
    public var insights: [CleanupInsight]
    public var unavailable: [CleanupUnavailable]
    public var scannedSections: Set<CleanupSection>
    public var purpose: CleanupScanPurpose
    public var date: Date

    public init(groups: [ScanGroup] = [], insights: [CleanupInsight] = [], unavailable: [CleanupUnavailable] = [],
                scannedSections: Set<CleanupSection> = [], purpose: CleanupScanPurpose = .module, date: Date = Date()) {
        self.groups = groups
        self.insights = insights
        self.unavailable = unavailable
        self.scannedSections = scannedSections
        self.purpose = purpose
        self.date = date
    }

    public func group(for section: CleanupSection) -> ScanGroup? {
        groups.first { $0.id == section.rawValue }
    }

    /// True when some categories could not be scanned for lack of Full Disk Access.
    public var isLimitedByFullDiskAccess: Bool {
        unavailable.contains { $0.reason == .fullDiskAccess }
    }
}

/// The concrete deletion targets behind one result row.
public struct CleanupExpansion: Sendable {
    public var targets: [ScanItem]
    /// Set when the row can no longer be processed safely.
    public var failure: String?

    public init(targets: [ScanItem] = [], failure: String? = nil) {
        self.targets = targets
        self.failure = failure
    }
}

/// Keys used in `ScanItem.metadata` by Cleanup.
public enum CleanupMetadataKey {
    public static let ruleID = "ruleID"
    public static let category = "category"
    public static let inode = "inode"
    public static let bundleID = "bundleID"
    /// Owner hint used by the running-app gate (may be a bundle id prefix).
    public static let owner = "owner"
    /// "whole", "contents" or "files".
    public static let mode = "mode"
    /// Permanent-removal zone for this row (regenerable folder).
    public static let zone = "zone"
    public static let needsAdmin = "needsAdmin"
    public static let inUse = "inUse"
    /// "1" on a selected row of an open app whose rule quits the app before cleaning
    /// (`RunningPolicy.quitFirst`).
    public static let quitToClean = "quitToClean"
    public static let launchItem = "launchItem"
    /// Recommended selection ("1"/"0"), used by "Select Recommended".
    public static let recommended = "recommended"
    /// Result sub-group for Mail Attachments and Trash Bins.
    public static let group = "group"
    public static let groupTitle = "groupTitle"
    public static let parentID = "parentID"
    public static let latestBackup = "latestBackup"
    public static let trashBin = "trashBin"
}
