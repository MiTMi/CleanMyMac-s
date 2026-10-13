import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One concrete deletion target found inside a contents/files row.
struct CleanupChild: Sendable {
    var path: String
    var entry: FileEntry
    var bytes: Int64
    var files: Int
    var newest: Date
}

/// Where a candidate path sits relative to paths claimed by earlier rules.
enum CleanupRelation {
    case none
    /// At or below another rule's territory: that rule owns it.
    case inside
    /// Contains another rule's territory: must not be removed as a whole.
    case contains
}

/// A draft result row before it becomes a `ScanItem`.
struct CleanupRowDraft {
    var path: String
    var entry: FileEntry
    var title: String
    var subtitle: String?
    var size: Int64
    var count: Int
    var modified: Date?
    var lastUsed: Date?
    var safety: SafetyLevel
    var selected: Bool
    var note: String
    var metadata: [String: String] = [:]
}

/// Linux-testable Cleanup scanner: expands catalog rules into measured, grouped results.
///
/// The scanner never follows symbolic links, never touches protected paths
/// (`CleanupCatalog.protectedPaths`/`protectedNames`, the ignore list), never counts
/// content claimed by an earlier rule, keeps SQLite families together, and applies age
/// and running-app gates. It is immutable and safe to share across concurrent tasks.
public struct CleanupScanner: Sendable {
    public let context: CleanupContext
    public let settings: SpruceSettings
    public let rules: [CleanupRule]
    let isCancelled: @Sendable () -> Bool
    let ruleIndex: [String: Int]
    let rulePatterns: [[CleanupPattern]]
    let protectedPatterns: [CleanupPattern]
    let protectedNames: [String]

    static let xcodeTools: [String] = [
        "xcodebuild", "XCBBuildService", "SourceKitService", "swift-frontend", "xctest", "ibtoold",
        "swift-build", "swift-package", "XCTRunner", "IBDesignablesAgentCocoaTouch",
    ]

    public init(
        context: CleanupContext,
        settings: SpruceSettings = SpruceSettings(),
        rules: [CleanupRule] = CleanupCatalog.rules,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) {
        var ctx = context
        ctx.home = CleanupPaths.realPath(context.home)
        if !ctx.systemRoot.isEmpty { ctx.systemRoot = CleanupPaths.realPath(ctx.systemRoot) }
        ctx.userTempDir = ctx.userTempDir.map { CleanupPaths.realPath($0) }
        ctx.userCacheDir = ctx.userCacheDir.map { CleanupPaths.realPath($0) }
        self.context = ctx
        self.settings = settings
        self.rules = rules
        self.isCancelled = isCancelled
        var index: [String: Int] = [:]
        for (i, rule) in rules.enumerated() where index[rule.id] == nil { index[rule.id] = i }
        ruleIndex = index
        rulePatterns = rules.map { rule in
            rule.paths.compactMap { Self.resolveToken($0, context: ctx) }.map(CleanupPattern.init(absolute:))
        }
        var protected = CleanupCatalog.protectedPaths
        if let own = ctx.ownBundleID, !own.isEmpty {
            protected += ["~/Library/Caches/\(own)", "~/Library/Containers/\(own)", "~/Library/Logs/\(own)",
                          "~/Library/Application Support/\(own)", "~/Library/Preferences/\(own).plist",
                          "$TMPDIR/\(own)", "$DARWIN_CACHE/\(own)"]
        }
        protectedPatterns = protected.compactMap { Self.resolveToken($0, context: ctx) }.map(CleanupPattern.init(absolute:))
        protectedNames = CleanupCatalog.protectedNames.map { $0.lowercased() }
    }

    // MARK: Tokens

    /// Expands `~`, `$TMPDIR`, `$DARWIN_CACHE` and `$UID`; prefixes system paths with
    /// `systemRoot`. Returns nil when a token is unavailable.
    public static func resolveToken(_ raw: String, context: CleanupContext) -> String? {
        var path: String
        if raw == "~" {
            path = context.home
        } else if raw.hasPrefix("~/") {
            path = context.home + raw.dropFirst(1)
        } else if raw.hasPrefix("$TMPDIR") {
            guard let tmp = context.userTempDir else { return nil }
            path = tmp + raw.dropFirst("$TMPDIR".count)
        } else if raw.hasPrefix("$DARWIN_CACHE") {
            guard let cache = context.userCacheDir else { return nil }
            path = cache + raw.dropFirst("$DARWIN_CACHE".count)
        } else if raw.hasPrefix("/") {
            path = context.systemRoot + raw
        } else {
            return nil
        }
        if path.contains("$UID") { path = path.replacingOccurrences(of: "$UID", with: String(context.uid)) }
        return path
    }

    // MARK: Rule selection

    /// Rules to run for the given sections, honouring Settings exclusions and the purpose.
    public func rules(for sections: Set<CleanupSection>) -> [CleanupRule] {
        let excluded = Set(settings.excludedCleanupCategories)
        return rules.filter { rule in
            guard sections.contains(rule.category.section) else { return false }
            if excluded.contains(rule.category.rawValue) || excluded.contains(rule.category.section.rawValue) {
                return false
            }
            if context.purpose == .checkup && !rule.isCheckupEligible { return false }
            return true
        }
    }

    public func rule(id: String) -> CleanupRule? {
        ruleIndex[id].map { rules[$0] }
    }

    // MARK: Scanning

    /// Scans sequentially (tests, simple callers). The Mac engine scans rules concurrently
    /// with `scan(rule:)` and then calls `assemble`.
    public func scan(sections: Set<CleanupSection> = Set(CleanupSection.allCases),
                     onProgress: ((String) -> Void)? = nil) -> CleanupScanReport {
        var results: [CleanupRuleResult] = []
        for rule in rules(for: sections) {
            if isCancelled() { break }
            results.append(scan(rule: rule, onProgress: onProgress))
        }
        return assemble(results, sections: sections)
    }

    /// Scans one rule. Pure with respect to other rules, so rules can run in parallel.
    public func scan(rule: CleanupRule, onProgress: ((String) -> Void)? = nil) -> CleanupRuleResult {
        var result = CleanupRuleResult(ruleID: rule.id, category: rule.category)
        if rule.needsFullDiskAccess && !context.hasFullDiskAccess {
            result.unavailable = CleanupUnavailable(category: rule.category, reason: .fullDiskAccess)
            return result
        }
        let index = ruleIndex[rule.id] ?? rules.count
        switch rule.analyzer {
        case .documentVersions:
            result.insights = documentVersionInsights()
            return result
        case .deletedUsers:
            result.insights = deletedUserInsights()
            return result
        case .installerApps:
            result.insights = installerInsights(rule, index: index)
            return result
        case .systemLaunchItems:
            result.insights = systemLaunchItemInsights(rule, index: index)
            return result
        case .mailTrash:
            result.insights = mailTrashInsights()
            return result
        case .externalTrash:
            result.items = externalTrashItems(rule, onProgress: onProgress)
            return result
        case .mailStored:
            let scan = mailStoredItems(rule, onProgress: onProgress)
            result.items = scan.items
            if scan.denied && scan.items.isEmpty {
                result.unavailable = CleanupUnavailable(category: rule.category,
                                                        reason: context.hasFullDiskAccess ? .permissionDenied : .fullDiskAccess)
            }
            return result
        default:
            return scanGeneric(rule, index: index, onProgress: onProgress)
        }
    }

    private func scanGeneric(_ rule: CleanupRule, index: Int, onProgress: ((String) -> Void)?) -> CleanupRuleResult {
        var result = CleanupRuleResult(ruleID: rule.id, category: rule.category)
        var denied = false
        var seen = Set<String>()
        let patterns = index < rulePatterns.count ? rulePatterns[index] : []
        for pattern in patterns {
            if isCancelled() { break }
            let expansion = CleanupPaths.expand(pattern.absolute, includeHidden: rule.includeHidden)
            denied = denied || expansion.denied
            for candidate in expansion.paths {
                if isCancelled() { break }
                guard seen.insert(candidate.lowercased()).inserted else { continue }
                onProgress?(candidate)
                guard let entry = FileWalker.entry(at: candidate), !entry.isSymlink else { continue }
                if isBlocked(candidate) { continue }
                let relation = territoryRelation(candidate, before: index)
                if relation == .inside { continue }
                let owner = ownerHint(path: candidate, rule: rule, pattern: pattern)
                // Nothing of an open app is removed before it quits, so its content counts
                // however recently it was written (see `RunningPolicy.quitFirst`).
                let ignoreAge = rule.whileRunning == .quitFirst && gateBlocker(rule: rule, owner: owner) != nil
                var target = rule.target
                if (target == .contents || target == .files) && !entry.isDirectory { target = .each }
                switch target {
                case .each:
                    if relation == .contains || containsProtected(candidate) { continue }
                    let title = rowTitle(rule: rule, pattern: pattern, path: candidate, entry: entry, owner: owner)
                    if let item = eachRow(rule, path: candidate, entry: entry, owner: owner, title: title,
                                          ignoreAge: ignoreAge) {
                        result.items.append(item)
                    }
                case .contents, .files:
                    let title = rowTitle(rule: rule, pattern: pattern, path: candidate, entry: entry, owner: owner)
                    if let item = folderRow(rule, index: index, path: candidate, entry: entry, owner: owner,
                                            title: title, mode: target, ignoreAge: ignoreAge) {
                        result.items.append(item)
                    }
                case .findFiles:
                    result.items += findFileRows(rule, root: candidate, owner: owner)
                }
            }
        }
        switch rule.analyzer {
        case .newestKept: keepNewest(&result.items)
        case .iosBackup: markLatestBackups(&result.items)
        default: break
        }
        if denied && result.items.isEmpty && (rule.needsFullDiskAccess || rule.category == .trashBins) {
            result.unavailable = CleanupUnavailable(category: rule.category,
                                                    reason: context.hasFullDiskAccess ? .permissionDenied : .fullDiskAccess)
        }
        return result
    }

    // MARK: Rows

    /// A row removed as a whole (file, bundle or folder).
    func eachRow(_ rule: CleanupRule, path: String, entry: FileEntry, owner: String?, title: String,
                 ignoreAge: Bool = false) -> ScanItem? {
        let name = entry.name
        if !rule.namePatterns.isEmpty && !CleanupPaths.matchesAny(name, rule.namePatterns) { return nil }
        if CleanupPaths.matchesAny(name, rule.excludedNames) { return nil }
        if !rule.needsAdmin && !isParentWritable(path) { return nil }

        var draft: CleanupRowDraft
        switch rule.analyzer {
        case .brokenPreference:
            guard let d = brokenPreferenceDraft(rule, path: path, entry: entry) else { return nil }
            draft = d
        case .launchAgent:
            guard let d = launchAgentDraft(rule, path: path, entry: entry) else { return nil }
            draft = d
        case .iosBackup:
            draft = iosBackupDraft(rule, path: path, entry: entry)
        case .mailDownload:
            guard let d = mailDownloadDraft(rule, path: path, entry: entry) else { return nil }
            draft = d
        default:
            let usage = measure(path, entry: entry, budget: rule.measureBudget)
            if !ignoreAge && isRecent(newest: usage.newest, newestAccess: usage.newestAccess, rule: rule) { return nil }
            if usage.bytes <= 0 && rule.category != .trashBins { return nil }
            draft = CleanupRowDraft(
                path: path, entry: entry, title: title,
                subtitle: CleanupPaths.display(CleanupPaths.parent(path), home: context.home),
                size: usage.bytes, count: max(usage.files, 1), modified: usage.newest, lastUsed: nil,
                safety: rule.safety, selected: rule.defaultSelected, note: rule.note
            )
            if rule.analyzer == .derivedData { decorateDerivedData(&draft) }
        }
        draft.metadata[CleanupMetadataKey.mode] = "whole"
        if rule.addsPermanentZone { draft.metadata[CleanupMetadataKey.zone] = CleanupPaths.parent(path) }
        if rule.category == .trashBins {
            draft.metadata[CleanupMetadataKey.group] = "trashBins.startup"
            draft.metadata[CleanupMetadataKey.groupTitle] = "Trash on \(context.startupVolumeName)"
            draft.metadata[CleanupMetadataKey.trashBin] = context.startupVolumeName
            draft.subtitle = "Trash on \(context.startupVolumeName)"
        }
        return finalize(draft, rule: rule, owner: owner)
    }

    /// A folder whose children (contents) or files (files) are removed; the folder stays.
    func folderRow(_ rule: CleanupRule, index: Int, path: String, entry: FileEntry, owner: String?, title: String,
                   mode: CleanupRule.Target, ignoreAge: Bool = false) -> ScanItem? {
        guard entry.isDirectory else { return nil }
        if !rule.needsAdmin && !FileManager.default.isWritableFile(atPath: path) { return nil }
        let children = mode == .files
            ? fileChildren(rule, index: index, folder: path, ignoreAge: ignoreAge)
            : contentsChildren(rule, index: index, folder: path, ignoreAge: ignoreAge)
        guard !children.isEmpty else { return nil }
        let bytes = children.reduce(Int64(0)) { $0 + $1.bytes }
        guard bytes > 0 else { return nil }
        let newest = children.map(\.newest).max()
        var draft = CleanupRowDraft(
            path: path, entry: entry, title: title,
            subtitle: CleanupPaths.display(path, home: context.home),
            size: bytes, count: children.reduce(0) { $0 + max($1.files, 1) }, modified: newest, lastUsed: nil,
            safety: rule.safety, selected: rule.defaultSelected, note: rule.note
        )
        draft.metadata[CleanupMetadataKey.mode] = mode == .files ? "files" : "contents"
        if rule.addsPermanentZone { draft.metadata[CleanupMetadataKey.zone] = path }
        return finalize(draft, rule: rule, owner: owner)
    }

    /// Rows for every matching file or bundle below a search root.
    func findFileRows(_ rule: CleanupRule, root: String, owner: String?) -> [ScanItem] {
        var candidates: [FileEntry] = []
        FileWalker.walk(root, options: .init(includeHidden: false, crossDevices: false, descendIntoPackages: false,
                                             maxDepth: rule.maxDepth)) { e in
            if isCancelled() { return .stop }
            if e.depth == 0 { return .continue }
            if e.isSymlink { return .continue }
            if e.isDirectory && isBlocked(e.path) { return .skipChildren }
            let matches = CleanupPaths.matchesAny(e.name, rule.namePatterns)
            if e.isDirectory {
                if matches {
                    candidates.append(e)
                    return .skipChildren
                }
                return .continue
            }
            if e.isRegularFile && matches { candidates.append(e) }
            return .continue
        }
        return candidates.compactMap { e in
            if isBlocked(e.path) { return nil }
            return eachRow(rule, path: e.path, entry: e, owner: owner, title: e.name)
        }
    }

    /// Applies the running-app gate, review names, owner metadata and builds the item.
    func finalize(_ input: CleanupRowDraft, rule: CleanupRule, owner: String?) -> ScanItem {
        var d = input
        if let owner {
            // `owner` is what the quit-apps prompts and the clean-time gate go by; rows an
            // open app doesn't hold up don't get one.
            if rule.whileRunning != .allow { d.metadata[CleanupMetadataKey.owner] = owner }
            switch rule.gate {
            case .ownerAtWildcard, .ownerFromFileName:
                if let primary = CleanupOwnership.primaryOwner(of: owner), CleanupOwnership.looksLikeBundleID(primary) {
                    d.metadata[CleanupMetadataKey.bundleID] = primary
                }
            default:
                break
            }
        }
        if let blocker = gateBlocker(rule: rule, owner: owner) {
            d.metadata[CleanupMetadataKey.inUse] = "1"
            if rule.whileRunning == .quitFirst {
                // Stays selected; Clean / Run asks to quit the app first.
                d.metadata[CleanupMetadataKey.quitToClean] = "1"
                d.note = "\(blocker). Spruce asks you to quit it before cleaning. " + d.note
            } else {
                d.selected = false
                d.note = "\(blocker) — quit it to clean this. " + d.note
            }
        }
        if !rule.reviewNames.isEmpty {
            let names = [d.entry.name] + (owner.map(CleanupOwnership.owners(in:)) ?? [])
            if names.contains(where: { CleanupPaths.matchesAny($0, rule.reviewNames) }) {
                if d.safety == .safe { d.safety = .review }
                d.selected = false
            }
        }
        var meta = d.metadata
        meta[CleanupMetadataKey.ruleID] = rule.id
        meta[CleanupMetadataKey.category] = rule.category.rawValue
        meta[CleanupMetadataKey.inode] = String(d.entry.inode)
        if rule.needsAdmin { meta[CleanupMetadataKey.needsAdmin] = "1" }
        let selected = d.selected && d.safety != .risky
        meta[CleanupMetadataKey.recommended] = selected ? "1" : "0"
        let url = URL(fileURLWithPath: d.path, isDirectory: d.entry.isDirectory)
        return ScanItem(
            id: url.standardizedFileURL.path,
            title: d.title,
            subtitle: d.subtitle,
            url: url,
            size: d.size,
            itemCount: d.count,
            safety: d.safety,
            isSelected: selected,
            deletion: rule.deletion,
            lastUsed: d.lastUsed,
            modified: d.modified,
            symbol: nil,
            note: d.note,
            metadata: meta
        )
    }

    // MARK: Children

    /// Direct children of a folder that may be removed: not protected, ignored or claimed,
    /// old enough, and kept together with their SQLite family.
    func contentsChildren(_ rule: CleanupRule, index: Int, folder: String, ignoreAge: Bool = false) -> [CleanupChild] {
        guard let names = CleanupPaths.list(folder) else { return [] }
        struct Candidate {
            var name: String
            var child: CleanupChild
            var eligible: Bool
        }
        var candidates: [Candidate] = []
        for name in names.sorted() {
            if isCancelled() { break }
            let path = CleanupPaths.child(of: folder, name)
            guard let entry = FileWalker.entry(at: path) else { continue }
            var eligible = !CleanupPaths.matchesAny(name, rule.excludedNames) && !isBlocked(path)
            if eligible {
                if territoryRelation(path, before: index) != .none || containsProtected(path) { eligible = false }
            }
            var child = CleanupChild(path: path, entry: entry, bytes: 0, files: 0, newest: entry.modified)
            if eligible {
                let usage = measure(path, entry: entry, budget: rule.measureBudget)
                child.bytes = usage.bytes
                child.files = usage.files
                child.newest = usage.newest
                if !ignoreAge && isRecent(newest: usage.newest, newestAccess: usage.newestAccess, rule: rule) {
                    eligible = false
                }
            }
            candidates.append(Candidate(name: name, child: child, eligible: eligible))
        }
        var families: [String: [Candidate]] = [:]
        for candidate in candidates {
            families[CleanupPaths.familyKey(candidate.name), default: []].append(candidate)
        }
        return families.values
            .filter { $0.allSatisfy(\.eligible) }
            .flatMap { $0.map(\.child) }
            .sorted { $0.path < $1.path }
    }

    /// Regular files anywhere below a folder that may be removed (folders stay).
    func fileChildren(_ rule: CleanupRule, index: Int, folder: String, ignoreAge: Bool = false) -> [CleanupChild] {
        struct Candidate {
            var child: CleanupChild
            var eligible: Bool
        }
        var candidates: [Candidate] = []
        let checkIgnored = !settings.ignoredPaths.isEmpty
        FileWalker.walk(folder, options: .init(includeHidden: true, crossDevices: false, descendIntoPackages: true,
                                               maxDepth: rule.maxDepth)) { e in
            if isCancelled() { return .stop }
            if e.depth == 0 { return .continue }
            if e.isDirectory {
                if isBlocked(e.path) || territoryRelation(e.path, before: index) == .inside { return .skipChildren }
                if case .ownerBelowRow = rule.gate, e.depth == 1,
                   let owner = CleanupOwnership.owner(forName: e.name),
                   CleanupOwnership.isRunning(owner: owner, running: context.runningBundleIDs) {
                    return .skipChildren
                }
                return .continue
            }
            guard e.isRegularFile, !e.isSymlink else { return .continue }
            if !rule.namePatterns.isEmpty && !CleanupPaths.matchesAny(e.name, rule.namePatterns) { return .continue }
            if CleanupPaths.matchesAny(e.name, rule.excludedNames) { return .continue }
            if rule.ownFilesOnly && e.ownerUID != context.uid { return .continue }
            if e.depth == 1 && (isProtected(e.path) || territoryRelation(e.path, before: index) != .none) {
                return .continue
            }
            if checkIgnored && settings.isIgnored(path: e.path) { return .continue }
            let eligible = ignoreAge || !isRecent(newest: e.modified, newestAccess: e.accessed, rule: rule)
            candidates.append(Candidate(child: CleanupChild(path: e.path, entry: e, bytes: e.allocatedSize, files: 1,
                                                            newest: e.modified),
                                        eligible: eligible))
            return .continue
        }
        var families: [String: [Candidate]] = [:]
        for candidate in candidates {
            let key = CleanupPaths.parent(candidate.child.path) + "/" + CleanupPaths.familyKey(candidate.child.entry.name)
            families[key, default: []].append(candidate)
        }
        return families.values
            .filter { $0.allSatisfy(\.eligible) }
            .flatMap { $0.map(\.child) }
            .sorted { $0.path < $1.path }
    }

    // MARK: Expansion for removal

    /// The concrete targets to dispose of for one selected row. Whole rows are returned
    /// as-is (FileRemover re-validates them); folder rows are re-listed with the same
    /// filters after checking the folder is still the object that was scanned.
    public func expand(_ item: ScanItem) -> CleanupExpansion {
        let mode = item.metadata[CleanupMetadataKey.mode] ?? "whole"
        guard mode != "whole" else { return CleanupExpansion(targets: [item]) }
        guard let url = item.url else { return CleanupExpansion(failure: "Not a file") }
        guard let ruleID = item.metadata[CleanupMetadataKey.ruleID], let rule = rule(id: ruleID),
              let index = ruleIndex[ruleID] else {
            return CleanupExpansion(failure: "Unknown cleanup rule")
        }
        let path = url.path
        guard let entry = FileWalker.entry(at: path) else { return CleanupExpansion() }
        guard entry.isDirectory, !entry.isSymlink else {
            return CleanupExpansion(failure: "Changed since the scan; skipped")
        }
        if let inode = item.metadata[CleanupMetadataKey.inode], inode != String(entry.inode) {
            return CleanupExpansion(failure: "Changed since the scan; skipped")
        }
        if isBlocked(path) { return CleanupExpansion(failure: "Protected location") }
        // Counted while its app was open (age ignored); the app has quit since, so what
        // it wrote last is no longer in use.
        let ignoreAge = rule.whileRunning == .quitFirst && item.metadata[CleanupMetadataKey.quitToClean] == "1"
            && gateBlocker(rule: rule, owner: item.metadata[CleanupMetadataKey.owner]) == nil
        let children = mode == "files"
            ? fileChildren(rule, index: index, folder: path, ignoreAge: ignoreAge)
            : contentsChildren(rule, index: index, folder: path, ignoreAge: ignoreAge)
        let targets = children.map { child -> ScanItem in
            var meta: [String: String] = [
                CleanupMetadataKey.inode: String(child.entry.inode),
                CleanupMetadataKey.ruleID: rule.id,
                CleanupMetadataKey.category: rule.category.rawValue,
                CleanupMetadataKey.parentID: item.id,
                CleanupMetadataKey.mode: "whole",
            ]
            if let zone = item.metadata[CleanupMetadataKey.zone] { meta[CleanupMetadataKey.zone] = zone }
            if rule.needsAdmin { meta[CleanupMetadataKey.needsAdmin] = "1" }
            let childURL = URL(fileURLWithPath: child.path, isDirectory: child.entry.isDirectory)
            return ScanItem(id: childURL.standardizedFileURL.path, title: child.entry.name,
                            subtitle: CleanupPaths.display(CleanupPaths.parent(child.path), home: context.home),
                            url: childURL, size: child.bytes, itemCount: max(child.files, 1), safety: item.safety,
                            isSelected: true, deletion: rule.deletion, modified: child.newest, metadata: meta)
        }
        return CleanupExpansion(targets: targets)
    }

    /// Why an item must not be removed right now (its app or tool is running, or a
    /// broken launch agent's program is back), or nil.
    public func blockingReason(for item: ScanItem) -> String? {
        if let reason = launchItemBlocker(item) { return reason }
        guard let ruleID = item.metadata[CleanupMetadataKey.ruleID], let rule = rule(id: ruleID) else { return nil }
        return gateBlocker(rule: rule, owner: item.metadata[CleanupMetadataKey.owner])
    }

    // MARK: Gates

    var xcodeIsBusy: Bool {
        if context.runningBundleIDs.contains("com.apple.dt.Xcode") { return true }
        return context.runningProcessNames.contains { process in
            Self.xcodeTools.contains { tool in tool == process || (process.count >= 15 && tool.hasPrefix(process)) }
        }
    }

    var simulatorIsBusy: Bool {
        context.runningBundleIDs.contains("com.apple.iphonesimulator") || context.runningProcessNames.contains("launchd_sim")
    }

    /// A short "X is open" phrase when the gate blocks, otherwise nil.
    func gateBlocker(rule: CleanupRule, owner: String?) -> String? {
        if rule.whileRunning == .allow { return nil }
        switch rule.gate {
        case .none, .ownerBelowRow:
            return nil
        case .xcode:
            return xcodeIsBusy ? "Xcode or its build tools are running" : nil
        case .simulator:
            return simulatorIsBusy ? "A simulator is running" : nil
        case .bundleIDs(let ids):
            guard let running = ids.first(where: { CleanupOwnership.isRunning(owner: $0, running: context.runningBundleIDs) })
            else { return nil }
            return "\(displayName(for: running)) is open"
        case .ownerAtWildcard, .ownerFromFileName:
            // A shared folder (Firefox's channels) is in use when any of its apps is open.
            guard let owner,
                  let running = CleanupOwnership.owners(in: owner).first(where: {
                      CleanupOwnership.isRunning(owner: $0, running: context.runningBundleIDs)
                  })
            else { return nil }
            return "\(displayName(for: running)) is open"
        }
    }

    func displayName(for bundleID: String) -> String {
        if let name = context.appName?(bundleID), !name.isEmpty { return name }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    func ownerHint(path: String, rule: CleanupRule, pattern: CleanupPattern) -> String? {
        switch rule.gate {
        case .ownerAtWildcard:
            guard let w = pattern.firstWildcardIndex else { return nil }
            let comps = CleanupPaths.components(path)
            guard w < comps.count else { return nil }
            if w > 0 && pattern.components[w - 1] == "Group Containers" {
                return CleanupOwnership.owner(forGroupContainer: comps[w])
            }
            return CleanupOwnership.owner(forName: comps[w])
        case .ownerFromFileName:
            let domain = CleanupOwnership.preferenceDomain(fileName: (path as NSString).lastPathComponent)
            return CleanupOwnership.looksLikeBundleID(domain) ? domain : nil
        case .bundleIDs(let ids):
            return ids.first
        case .xcode:
            return "com.apple.dt.Xcode"
        case .simulator:
            return "com.apple.iphonesimulator"
        case .none, .ownerBelowRow:
            return nil
        }
    }

    func rowTitle(rule: CleanupRule, pattern: CleanupPattern, path: String, entry: FileEntry, owner: String?) -> String {
        if pattern.isLiteral {
            return rule.paths.count > 1 ? "\(rule.title) (\(entry.name))" : rule.title
        }
        if case .ownerAtWildcard = rule.gate, let w = pattern.firstWildcardIndex {
            let comps = CleanupPaths.components(path)
            let wildName = w < comps.count ? comps[w] : entry.name
            let app = owner.flatMap(CleanupOwnership.primaryOwner(of:)).flatMap { context.appName?($0) } ?? wildName
            return comps.count - 1 == w ? app : "\(app) · \(entry.name)"
        }
        return entry.name
    }

    // MARK: Protection & territories

    /// Protected by the built-in exception list or the user's ignore list.
    func isBlocked(_ path: String) -> Bool {
        isProtected(path) || settings.isIgnored(path: path)
    }

    func isProtected(_ path: String) -> Bool {
        let lower = CleanupPaths.components(path.lowercased())
        for pattern in protectedPatterns where pattern.covers(lower) { return true }
        for component in lower {
            for name in protectedNames where CleanupPaths.matchComponent(component, name) { return true }
        }
        return false
    }

    /// True when a protected path exists somewhere below `path`.
    func containsProtected(_ path: String) -> Bool {
        let lower = CleanupPaths.components(path.lowercased())
        for pattern in protectedPatterns where pattern.extendsBelow(lower) {
            let rest = pattern.components[lower.count...].joined(separator: "/")
            let probe = CleanupPaths.escapeGlob(path) + "/" + rest
            if !CleanupPaths.expand(probe, includeHidden: true).paths.isEmpty { return true }
        }
        return false
    }

    /// Relation of `path` to the patterns of every rule listed before `index`.
    func territoryRelation(_ path: String, before index: Int) -> CleanupRelation {
        let lower = CleanupPaths.components(path.lowercased())
        var contains = false
        for j in 0..<min(index, rulePatterns.count) {
            for pattern in rulePatterns[j] {
                if pattern.covers(lower) { return .inside }
                if !contains && pattern.extendsBelow(lower) {
                    let rest = pattern.components[lower.count...].joined(separator: "/")
                    let probe = CleanupPaths.escapeGlob(path) + "/" + rest
                    if !CleanupPaths.expand(probe, includeHidden: true).paths.isEmpty { contains = true }
                }
            }
        }
        return contains ? .contains : .none
    }

    // MARK: Measuring

    struct Usage {
        var bytes: Int64
        var files: Int
        var newest: Date
        var newestAccess: Date
    }

    func measure(_ path: String, entry: FileEntry, budget: TimeInterval) -> Usage {
        if entry.isDirectory && !entry.isSymlink {
            let usage = DiskUsage.measure(path, deadline: Date().addingTimeInterval(budget))
            return Usage(bytes: usage.bytes, files: usage.fileCount,
                         newest: max(entry.modified, usage.newestModification ?? entry.modified),
                         newestAccess: max(entry.accessed, usage.newestAccess ?? entry.accessed))
        }
        return Usage(bytes: entry.allocatedSize, files: 1, newest: entry.modified, newestAccess: entry.accessed)
    }

    func isRecent(newest: Date, newestAccess: Date, rule: CleanupRule) -> Bool {
        guard rule.minAge > 0 else { return false }
        let reference = rule.ageBasis == .modification ? newest : max(newest, newestAccess)
        return reference > context.now.addingTimeInterval(-rule.minAge)
    }

    func isParentWritable(_ path: String) -> Bool {
        FileManager.default.isWritableFile(atPath: CleanupPaths.parent(path))
    }

    // MARK: Assembly

    /// Builds the final grouped result from per-rule results (in catalog order),
    /// applying the Checkup filter and the ignore list.
    public func assemble(_ results: [CleanupRuleResult], sections: Set<CleanupSection>) -> CleanupScanReport {
        let ordered = results.sorted { (ruleIndex[$0.ruleID] ?? Int.max) < (ruleIndex[$1.ruleID] ?? Int.max) }
        var seen = Set<String>()
        var byCategory: [CleanupCategory: [ScanItem]] = [:]
        var insights: [CleanupInsight] = []
        var unavailable: [CleanupUnavailable] = []
        for result in ordered {
            insights += result.insights
            if let u = result.unavailable, !unavailable.contains(where: { $0.category == u.category }) {
                unavailable.append(u)
            }
            for item in result.items {
                guard seen.insert(item.id).inserted else { continue }
                if context.purpose == .checkup {
                    if item.safety != .safe { continue }
                    if item.metadata[CleanupMetadataKey.inUse] == "1"
                        && item.metadata[CleanupMetadataKey.quitToClean] != "1" { continue }
                }
                byCategory[result.category, default: []].append(item)
            }
        }
        // A category with results is not "unavailable" even if one of its rules was.
        unavailable.removeAll { u in !(byCategory[u.category] ?? []).isEmpty }

        var groups: [ScanGroup] = []
        if sections.contains(.systemJunk) {
            let children = CleanupCatalog.systemJunkCategories.compactMap { category -> ScanGroup? in
                guard let items = byCategory[category], !items.isEmpty else { return nil }
                return ScanGroup(id: category.rawValue, title: category.title, detail: category.detail,
                                 symbol: category.symbol, safety: category.nominalSafety,
                                 items: items.sorted(by: Self.bySize))
            }
            if !children.isEmpty {
                groups.append(ScanGroup(id: CleanupSection.systemJunk.rawValue, title: CleanupSection.systemJunk.title,
                                        detail: CleanupSection.systemJunk.detail, symbol: CleanupSection.systemJunk.symbol,
                                        safety: .safe, children: children))
            }
        }
        for section in [CleanupSection.mailAttachments, .trashBins] where sections.contains(section) {
            let category: CleanupCategory = section == .mailAttachments ? .mailAttachments : .trashBins
            let children = subgroups(byCategory[category] ?? [], section: section)
            if !children.isEmpty {
                groups.append(ScanGroup(id: section.rawValue, title: section.title, detail: section.detail,
                                        symbol: section.symbol, safety: .safe, children: children))
            }
        }
        return CleanupScanReport(groups: settings.filteringIgnored(groups), insights: insights, unavailable: unavailable,
                                 scannedSections: sections, purpose: context.purpose, date: context.now)
    }

    static func bySize(_ a: ScanItem, _ b: ScanItem) -> Bool {
        a.size != b.size ? a.size > b.size : a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    private func subgroups(_ items: [ScanItem], section: CleanupSection) -> [ScanGroup] {
        var order: [String] = []
        var buckets: [String: [ScanItem]] = [:]
        var titles: [String: String] = [:]
        for item in items {
            let key = item.metadata[CleanupMetadataKey.group] ?? section.rawValue + ".other"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
            titles[key] = item.metadata[CleanupMetadataKey.groupTitle] ?? section.title
        }
        return order.map { key in
            let list = buckets[key] ?? []
            let (detail, symbol) = Self.subgroupStyle(key: key, items: list)
            return ScanGroup(id: key, title: titles[key] ?? section.title, detail: detail, symbol: symbol,
                             safety: list.contains { $0.safety == .safe } ? .safe : .review,
                             items: list.sorted(by: Self.bySize))
        }
    }

    static func subgroupStyle(key: String, items: [ScanItem]) -> (String, String) {
        if key == "mailAttachments.opened" {
            return ("Copies Mail saved when you opened attachments. Opening the message gets them again.", "paperclip")
        }
        if key.hasPrefix("mailAttachments.account.") {
            let recoverable = items.contains { $0.safety != .risky }
            return (recoverable
                ? "Attachments downloaded with messages. Mail downloads them again from the server when you open a message."
                : "Stored only on this Mac. Removing them deletes your only copy, so they're never selected for you.",
                    "envelope")
        }
        if key == "trashBins.startup" {
            return ("Items you moved to the Trash. Emptying it removes them for good.", "trash")
        }
        if key.hasPrefix("trashBins.volume.") {
            return ("Items deleted from this drive, kept in its own Trash.", "externaldrive")
        }
        return ("", "folder")
    }
}
