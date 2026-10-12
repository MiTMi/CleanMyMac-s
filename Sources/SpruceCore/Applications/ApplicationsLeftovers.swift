import Foundation

// MARK: - Component kinds

/// What a file belonging to an app is, for grouping in the app detail checklist.
public enum ApplicationsComponentKind: String, Codable, Sendable, CaseIterable {
    case application
    case applicationSupport
    case caches
    case preferences
    case containers
    case logs
    case savedState
    case webData
    case launchItems
    case plugins
    case other
    case dockIcon

    public var title: String {
        switch self {
        case .application: return "Application"
        case .applicationSupport: return "Application Support"
        case .caches: return "Caches"
        case .preferences: return "Preferences"
        case .containers: return "Containers"
        case .logs: return "Logs & Crash Reports"
        case .savedState: return "Saved State"
        case .webData: return "Web Data & Cookies"
        case .launchItems: return "Launch Agents & Helpers"
        case .plugins: return "Plug-ins & Extensions"
        case .other: return "Other Files"
        case .dockIcon: return "Dock Icon"
        }
    }

    public var symbol: String {
        switch self {
        case .application: return "app.dashed"
        case .applicationSupport: return "folder.badge.gearshape"
        case .caches: return "internaldrive"
        case .preferences: return "slider.horizontal.3"
        case .containers: return "shippingbox"
        case .logs: return "doc.text.magnifyingglass"
        case .savedState: return "rectangle.on.rectangle"
        case .webData: return "network"
        case .launchItems: return "power"
        case .plugins: return "puzzlepiece.extension"
        case .other: return "doc"
        case .dockIcon: return "dock.rectangle"
        }
    }

    public var detail: String {
        switch self {
        case .application: return "The app itself."
        case .applicationSupport: return "Settings, databases and downloaded content the app keeps for itself."
        case .caches: return "Temporary data the app can rebuild."
        case .preferences: return "The app's settings files."
        case .containers: return "Sandbox folders where the app keeps its data, sometimes including documents."
        case .logs: return "Diagnostic logs and crash reports."
        case .savedState: return "Window positions restored when the app reopens."
        case .webData: return "Web caches, local storage and cookies the app's web views use."
        case .launchItems: return "Agents and helpers that start automatically."
        case .plugins: return "Plug-ins the app installed into macOS."
        case .other: return "Other files named after the app."
        case .dockIcon: return "The app's tile in the Dock."
        }
    }

    /// Data a Reset removes: everything the app regenerates on first launch, never the app,
    /// its helpers or its plug-ins.
    public var isResetData: Bool {
        switch self {
        case .applicationSupport, .caches, .preferences, .containers, .logs, .savedState, .webData, .other:
            return true
        case .application, .launchItems, .plugins, .dockIcon:
            return false
        }
    }
}

/// How sure the matcher is that a file belongs to the app.
public enum ApplicationsMatchConfidence: Int, Codable, Sendable, Comparable {
    /// Named after the app's name, but the name is fuzzy; shown, never pre-selected.
    case likely = 50
    /// Exact app name in a standard folder, or inside the vendor's folder.
    case strong = 80
    /// Named after the bundle id (dot boundary), an app group, or a launch job running app code.
    case owned = 100

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Search roots

/// A Library folder searched one level deep for an app's files.
public struct ApplicationsSearchRoot: Sendable, Hashable {
    public enum Mode: String, Sendable, Hashable {
        /// Entry equals the bundle id, or starts with `bundleID.`.
        case bundleID
        /// Like `.bundleID`, and also `TEAMID.bundleID` / `group.bundleID` forms.
        case bundleIDBoundary
        /// Entry equals one of the app's distinctive names.
        case name
        /// Look inside the vendor's folder (`Google/Chrome`).
        case vendorFolders
        /// `<Executable>-<date>.ips` crash reports.
        case crashReports
        /// launchd plists whose program lives inside the app bundle.
        case launchJobs
        /// Group containers named after an app-group entitlement.
        case appGroups
    }

    public var path: String
    public var kind: ApplicationsComponentKind
    public var modes: Set<Mode>
    /// `/Library/...` (shared by all users; usually needs administrator rights).
    public var isSystemDomain: Bool

    public init(_ path: String, _ kind: ApplicationsComponentKind, _ modes: Set<Mode>, system: Bool = false) {
        self.path = path
        self.kind = kind
        self.modes = modes
        self.isSystemDomain = system
    }
}

/// The folders searched for an installed app's files, and for files of removed apps.
public enum ApplicationsLeftoverCatalog {

    /// Roots for the Uninstaller (an installed app's files).
    public static func roots(home: String = NSHomeDirectory()) -> [ApplicationsSearchRoot] {
        let lib = (home as NSString).appendingPathComponent("Library")
        func u(_ sub: String) -> String { (lib as NSString).appendingPathComponent(sub) }
        func s(_ sub: String) -> String { ("/Library" as NSString).appendingPathComponent(sub) }
        return [
            ApplicationsSearchRoot(u("Application Support"), .applicationSupport, [.bundleID, .name, .vendorFolders]),
            ApplicationsSearchRoot(u("Caches"), .caches, [.bundleID, .name, .vendorFolders]),
            ApplicationsSearchRoot(u("Preferences"), .preferences, [.bundleIDBoundary, .name]),
            ApplicationsSearchRoot(u("Preferences/ByHost"), .preferences, [.bundleIDBoundary]),
            ApplicationsSearchRoot(u("Containers"), .containers, [.bundleIDBoundary]),
            ApplicationsSearchRoot(u("Group Containers"), .containers, [.bundleIDBoundary, .appGroups]),
            ApplicationsSearchRoot(u("Application Scripts"), .containers, [.bundleIDBoundary]),
            ApplicationsSearchRoot(u("Saved Application State"), .savedState, [.bundleID]),
            ApplicationsSearchRoot(u("HTTPStorages"), .webData, [.bundleID]),
            ApplicationsSearchRoot(u("WebKit"), .webData, [.bundleID]),
            ApplicationsSearchRoot(u("Cookies"), .webData, [.bundleID]),
            ApplicationsSearchRoot(u("Logs"), .logs, [.bundleID, .name, .vendorFolders]),
            ApplicationsSearchRoot(u("Logs/DiagnosticReports"), .logs, [.crashReports]),
            ApplicationsSearchRoot(u("Application Support/CrashReporter"), .logs, [.crashReports]),
            ApplicationsSearchRoot(u("LaunchAgents"), .launchItems, [.bundleIDBoundary, .launchJobs]),
            ApplicationsSearchRoot(u("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"),
                                   .other, [.bundleID]),
            ApplicationsSearchRoot(u("Internet Plug-Ins"), .plugins, [.bundleID, .name]),
            ApplicationsSearchRoot(u("PreferencePanes"), .plugins, [.name]),
            ApplicationsSearchRoot(u("QuickLook"), .plugins, [.name]),
            ApplicationsSearchRoot(u("Spotlight"), .plugins, [.name]),
            ApplicationsSearchRoot(u("Screen Savers"), .plugins, [.name]),
            ApplicationsSearchRoot(u("Services"), .plugins, [.name]),

            ApplicationsSearchRoot(s("Application Support"), .applicationSupport, [.bundleID, .name, .vendorFolders], system: true),
            ApplicationsSearchRoot(s("Caches"), .caches, [.bundleID, .name], system: true),
            ApplicationsSearchRoot(s("Preferences"), .preferences, [.bundleIDBoundary], system: true),
            ApplicationsSearchRoot(s("Logs"), .logs, [.bundleID, .name], system: true),
            ApplicationsSearchRoot(s("Logs/DiagnosticReports"), .logs, [.crashReports], system: true),
            ApplicationsSearchRoot(s("LaunchAgents"), .launchItems, [.bundleIDBoundary, .launchJobs], system: true),
            ApplicationsSearchRoot(s("LaunchDaemons"), .launchItems, [.bundleIDBoundary, .launchJobs], system: true),
            ApplicationsSearchRoot(s("PrivilegedHelperTools"), .launchItems, [.bundleIDBoundary], system: true),
            ApplicationsSearchRoot(s("Internet Plug-Ins"), .plugins, [.bundleID, .name], system: true),
            ApplicationsSearchRoot(s("PreferencePanes"), .plugins, [.name], system: true),
            ApplicationsSearchRoot(s("QuickLook"), .plugins, [.name], system: true),
            ApplicationsSearchRoot(s("Spotlight"), .plugins, [.name], system: true),
            ApplicationsSearchRoot(s("Screen Savers"), .plugins, [.name], system: true),
        ]
    }

    /// Roots for the Leftovers scan (files of apps that are no longer installed). User domain
    /// only: everything found here can be moved to the Trash without administrator rights.
    public static func orphanRoots(home: String = NSHomeDirectory()) -> [ApplicationsSearchRoot] {
        let lib = (home as NSString).appendingPathComponent("Library")
        func u(_ sub: String) -> String { (lib as NSString).appendingPathComponent(sub) }
        return [
            ApplicationsSearchRoot(u("Application Support"), .applicationSupport, [.bundleID]),
            ApplicationsSearchRoot(u("Caches"), .caches, [.bundleID]),
            ApplicationsSearchRoot(u("Preferences"), .preferences, [.bundleIDBoundary]),
            ApplicationsSearchRoot(u("Preferences/ByHost"), .preferences, [.bundleIDBoundary]),
            ApplicationsSearchRoot(u("Containers"), .containers, [.bundleIDBoundary]),
            ApplicationsSearchRoot(u("Group Containers"), .containers, [.bundleIDBoundary]),
            ApplicationsSearchRoot(u("Application Scripts"), .containers, [.bundleIDBoundary]),
            ApplicationsSearchRoot(u("Saved Application State"), .savedState, [.bundleID]),
            ApplicationsSearchRoot(u("HTTPStorages"), .webData, [.bundleID]),
            ApplicationsSearchRoot(u("WebKit"), .webData, [.bundleID]),
            ApplicationsSearchRoot(u("Cookies"), .webData, [.bundleID]),
            ApplicationsSearchRoot(u("Logs"), .logs, [.bundleID]),
            ApplicationsSearchRoot(u("LaunchAgents"), .launchItems, [.launchJobs]),
        ]
    }

    /// Bundle-id prefixes shared by many apps (runtimes, frameworks, updaters). Apps with
    /// such ids only match files named *exactly* after their id.
    public static let genericBundleIDPrefixes: [String] = [
        "com.github.electron", "com.electron.", "org.chromium.", "org.python.", "com.oracle.java", "net.java.",
        "org.openjdk.", "org.sparkle-project.", "com.google.keystone", "com.google.googleupdater",
        "com.microsoft.autoupdate", "com.apple.",
    ]

    public static func isGenericBundleID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return genericBundleIDPrefixes.contains { lower == $0 || lower.hasPrefix($0) }
    }
}

// MARK: - Candidates

/// A file or folder that probably belongs to an app.
public struct ApplicationsLeftoverCandidate: Sendable, Hashable, Identifiable, Codable {
    public var id: String { path }
    public var path: String
    public var kind: ApplicationsComponentKind
    public var confidence: ApplicationsMatchConfidence
    /// Why it matched ("Named after com.foo.app").
    public var reason: String
    /// Other installed apps that also match this file.
    public var sharedWith: [String]
    public var isSystemDomain: Bool
    /// The current user cannot move it (owned by root or in a read-only folder).
    public var needsAdmin: Bool

    public init(path: String, kind: ApplicationsComponentKind, confidence: ApplicationsMatchConfidence, reason: String,
                sharedWith: [String] = [], isSystemDomain: Bool = false, needsAdmin: Bool = false) {
        self.path = path
        self.kind = kind
        self.confidence = confidence
        self.reason = reason
        self.sharedWith = sharedWith
        self.isSystemDomain = isSystemDomain
        self.needsAdmin = needsAdmin
    }

    /// Pre-selected for a complete uninstall: strong proof, not shared, removable.
    public var isPreselected: Bool { confidence >= .strong && sharedWith.isEmpty && !needsAdmin }

    /// Pre-selected for a Reset: app data in the user's Library with strong proof.
    public var isResetPreselected: Bool { kind.isResetData && !isSystemDomain && isPreselected }

    public var safety: SafetyLevel { isPreselected ? .safe : .review }

    /// Explanation shown in the checklist.
    public var note: String {
        var parts = [reason + "."]
        if !sharedWith.isEmpty {
            parts.append("Also used by \(sharedWith.joined(separator: ", ")), so it is not selected.")
        }
        if needsAdmin {
            parts.append("Owned by the system; macOS may refuse to move it to the Trash without administrator rights.")
        }
        if kind == .containers {
            parts.append("Sandboxed apps can keep documents here — look inside before removing.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Matcher

/// Finds an installed app's files in the Library folders.
///
/// Conservative by design: files are matched by bundle id at dot boundaries, app-group
/// entitlements, launch jobs that run code from inside the bundle, or the app's exact
/// (distinctive) name. Files that also match another installed app are flagged as shared
/// and never pre-selected; files that match another app *more specifically* are dropped.
public struct ApplicationsLeftoverMatcher {
    public var roots: [ApplicationsSearchRoot]
    /// Names of the entries of a directory (empty when unreadable).
    public var listDirectory: (String) -> [String]
    public var isDirectory: (String) -> Bool
    /// True when the current user can move the item (its parent folder is writable).
    public var isRemovable: (String) -> Bool
    public var readLaunchJob: (String) -> ApplicationsLaunchJob?

    public init(roots: [ApplicationsSearchRoot] = ApplicationsLeftoverCatalog.roots(),
                listDirectory: @escaping (String) -> [String] = ApplicationsLeftoverMatcher.defaultList,
                isDirectory: @escaping (String) -> Bool = ApplicationsLeftoverMatcher.defaultIsDirectory,
                isRemovable: @escaping (String) -> Bool = ApplicationsLeftoverMatcher.defaultIsRemovable,
                readLaunchJob: @escaping (String) -> ApplicationsLaunchJob? = ApplicationsLaunchJob.read(atPath:)) {
        self.roots = roots
        self.listDirectory = listDirectory
        self.isDirectory = isDirectory
        self.isRemovable = isRemovable
        self.readLaunchJob = readLaunchJob
    }

    public static func defaultList(_ path: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
    }

    public static func defaultIsDirectory(_ path: String) -> Bool {
        guard let entry = FileWalker.entry(at: path) else { return false }
        return entry.isDirectory
    }

    public static func defaultIsRemovable(_ path: String) -> Bool {
        FileManager.default.isWritableFile(atPath: (path as NSString).deletingLastPathComponent)
    }

    /// A match of one entry against one app.
    struct Match {
        var confidence: ApplicationsMatchConfidence
        var reason: String
        /// Length of the matched id or name (more specific = longer).
        var strength: Int
        var isBundleIDMatch: Bool
    }

    /// Files belonging to `app`, sorted by kind then path. `others` are the other installed
    /// apps, used for the shared-ownership guard.
    public func candidates(for app: ApplicationsAppIdentity, others: [ApplicationsAppIdentity] = []) -> [ApplicationsLeftoverCandidate] {
        guard !app.bundleID.isEmpty else { return [] }
        let context = Context(app)
        let otherContexts = others.filter { $0.bundlePath != app.bundlePath }.map(Context.init)
        let bundlePaths = ([app.bundlePath] + others.map(\.bundlePath)).map { ($0 as NSString).standardizingPath.lowercased() }

        var found: [String: ApplicationsLeftoverCandidate] = [:]
        var order: [String] = []

        func consider(path: String, name: String, root: ApplicationsSearchRoot, insideVendor vendorFolder: String?) {
            let lowerPath = (path as NSString).standardizingPath.lowercased()
            // Never an app bundle, anything inside one, or a folder that contains one.
            if bundlePaths.contains(where: { lowerPath == $0 || lowerPath.hasPrefix($0 + "/") || $0.hasPrefix(lowerPath + "/") }) {
                return
            }
            if name.lowercased().hasPrefix("com.apple.") && !app.bundleID.lowercased().hasPrefix("com.apple.") { return }
            guard let own = match(name: name, path: path, root: root, context: context, vendorFolder: vendorFolder) else { return }

            var shared: [String] = []
            for other in otherContexts {
                guard let theirs = match(name: name, path: path, root: root, context: other, vendorFolder: vendorFolder) else { continue }
                if theirs.isBundleIDMatch && (!own.isBundleIDMatch || theirs.strength > own.strength) {
                    // It belongs to a more specific app (com.foo.app.pro vs com.foo.app).
                    return
                }
                let label = other.identity.names.first ?? other.identity.bundleID
                if !shared.contains(label) { shared.append(label) }
            }
            guard found[path] == nil else { return }
            found[path] = ApplicationsLeftoverCandidate(
                path: path, kind: root.kind, confidence: own.confidence, reason: own.reason, sharedWith: shared,
                isSystemDomain: root.isSystemDomain, needsAdmin: !isRemovable(path))
            order.append(path)
        }

        for root in roots {
            let entries = listDirectory(root.path)
            for name in entries where !name.hasPrefix(".") {
                let path = (root.path as NSString).appendingPathComponent(name)
                consider(path: path, name: name, root: root, insideVendor: nil)
            }
            if root.modes.contains(.vendorFolders) {
                for vendorFolder in vendorFolders(in: entries, context: context) {
                    let folderPath = (root.path as NSString).appendingPathComponent(vendorFolder)
                    guard isDirectory(folderPath) else { continue }
                    for child in listDirectory(folderPath) where !child.hasPrefix(".") {
                        consider(path: (folderPath as NSString).appendingPathComponent(child), name: child,
                                 root: root, insideVendor: vendorFolder)
                    }
                }
            }
        }
        return collapse(order.compactMap { found[$0] })
    }

    // MARK: Matching

    /// Precomputed match data for one app.
    struct Context {
        var identity: ApplicationsAppIdentity
        var bundleIDs: [String]
        var isGeneric: Bool
        var nameForms: Set<String>
        var appGroups: Set<String>
        var crashPrefix: String?

        init(_ identity: ApplicationsAppIdentity) {
            self.identity = identity
            bundleIDs = identity.allBundleIDs
            isGeneric = ApplicationsLeftoverCatalog.isGenericBundleID(identity.bundleID)
            nameForms = Set(ApplicationsTokens.nameForms(for: identity))
            appGroups = Set(identity.appGroups.map { $0.lowercased() })
            let exe = identity.executableName ?? identity.names.first
            if let exe, ApplicationsTokens.isDistinctiveName(exe) {
                crashPrefix = exe.lowercased()
            }
        }
    }

    func vendorFolders(in entries: [String], context: Context) -> [String] {
        guard let token = context.identity.vendorToken, token.count >= 3,
              !ApplicationsTokens.commonWords.contains(token) else { return [] }
        let normalizedToken = ApplicationsTokens.normalized(token)
        return entries.filter { ApplicationsTokens.normalized($0) == normalizedToken }
    }

    func match(name: String, path: String, root: ApplicationsSearchRoot, context: Context, vendorFolder: String?) -> Match? {
        let lowerName = name.lowercased()
        let stripped = ApplicationsTokens.strippingDataSuffix(name)
        let forms = Array(Set([name, stripped]))

        if let vendorFolder {
            // Inside Vendor/: the app's names (with the vendor prefix removed) or the id's last part.
            let stem = ApplicationsTokens.nameStem(name).lowercased()
            let childForms = Set(ApplicationsTokens.vendorChildForms(for: context.identity, vendorFolder: vendorFolder))
            if childForms.contains(stem) {
                return Match(confidence: .strong, reason: "In \(vendorFolder)'s folder, named after the app",
                             strength: stem.count, isBundleIDMatch: false)
            }
            for id in context.bundleIDs where forms.contains(where: { ApplicationsTokens.bundleMatch($0, bundleID: id, allowEmbedded: false) != .none }) {
                return Match(confidence: .owned, reason: "Named after \(id)", strength: id.count, isBundleIDMatch: true)
            }
            return nil
        }

        let bundleModes: Set<ApplicationsSearchRoot.Mode> = [.bundleID, .bundleIDBoundary, .launchJobs]
        if !root.modes.isDisjoint(with: bundleModes) {
            let allowEmbedded = root.modes.contains(.bundleIDBoundary) && !context.isGeneric
            var best: (id: String, kind: ApplicationsTokens.BundleMatch)?
            for id in context.bundleIDs {
                for form in forms {
                    let m = ApplicationsTokens.bundleMatch(form, bundleID: id, allowEmbedded: allowEmbedded)
                    if m == .none { continue }
                    if context.isGeneric && m != .exact { continue }
                    if best == nil || id.count > best!.id.count { best = (id, m) }
                }
            }
            if let best {
                return Match(confidence: .owned, reason: "Named after \(best.id)", strength: best.id.count, isBundleIDMatch: true)
            }
        }

        if root.modes.contains(.appGroups) {
            let lower = stripped.lowercased()
            if context.appGroups.contains(lower) {
                return Match(confidence: .owned, reason: "The app's shared group container", strength: lower.count, isBundleIDMatch: true)
            }
        }

        if root.modes.contains(.launchJobs), lowerName.hasSuffix(".plist"), let job = readLaunchJob(path),
           job.isOwned(byBundleAt: context.identity.bundlePath, bundleID: context.identity.bundleID) {
            return Match(confidence: .owned, reason: "Starts a program from inside the app", strength: context.identity.bundleID.count,
                         isBundleIDMatch: true)
        }

        if root.modes.contains(.name) {
            let stem = ApplicationsTokens.nameStem(name).lowercased()
            if context.nameForms.contains(stem) {
                return Match(confidence: .strong, reason: "Named after the app", strength: stem.count, isBundleIDMatch: false)
            }
        }

        if root.modes.contains(.crashReports), let prefix = context.crashPrefix {
            let reportExtensions = ["ips", "crash", "diag", "spin", "hang", "plist", "panic"]
            let ext = (lowerName as NSString).pathExtension
            if reportExtensions.contains(ext),
               lowerName.hasPrefix(prefix + "-") || lowerName.hasPrefix(prefix + "_") || lowerName.hasPrefix(prefix + ".") {
                return Match(confidence: .strong, reason: "A crash or diagnostic report of the app", strength: prefix.count,
                             isBundleIDMatch: false)
            }
        }
        return nil
    }

    /// Drops candidates inside another candidate's folder; keeps catalog order.
    func collapse(_ candidates: [ApplicationsLeftoverCandidate]) -> [ApplicationsLeftoverCandidate] {
        let paths = candidates.map { ($0.path as NSString).standardizingPath.lowercased() }
        return candidates.enumerated().filter { index, _ in
            let p = paths[index]
            return !paths.enumerated().contains { other, q in other != index && p.hasPrefix(q + "/") }
        }.map(\.element)
    }
}
