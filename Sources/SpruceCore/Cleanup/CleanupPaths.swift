import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A rule or exception path pattern after token expansion, split into components.
struct CleanupPattern: Sendable, Hashable {
    /// Absolute pattern (may contain `*`, `?`, `[...]` per component).
    let absolute: String
    let components: [String]
    let lowered: [String]

    init(absolute: String) {
        self.absolute = absolute
        components = CleanupPaths.components(absolute)
        lowered = components.map { $0.lowercased() }
    }

    /// Index of the first component containing a wildcard, if any.
    var firstWildcardIndex: Int? {
        components.firstIndex(where: CleanupPaths.hasWildcard)
    }

    var isLiteral: Bool { firstWildcardIndex == nil }

    /// True when `path` (lowercased components) is at or below this pattern.
    func covers(_ path: [String]) -> Bool {
        guard lowered.count <= path.count else { return false }
        for i in lowered.indices where !CleanupPaths.matchComponent(path[i], lowered[i]) {
            return false
        }
        return true
    }

    /// True when this pattern is deeper than `path` and `path` matches its leading part.
    func extendsBelow(_ path: [String]) -> Bool {
        guard lowered.count > path.count else { return false }
        for i in path.indices where !CleanupPaths.matchComponent(path[i], lowered[i]) {
            return false
        }
        return true
    }
}

/// Path helpers shared by the Cleanup scanner (Foundation + libc only, Linux-testable).
public enum CleanupPaths {

    static func hasWildcard(_ component: String) -> Bool {
        component.contains(where: { $0 == "*" || $0 == "?" || $0 == "[" })
    }

    /// Escapes glob metacharacters so a real path can prefix a pattern (`[*]`, `[?]`, `[[]`).
    static func escapeGlob(_ path: String) -> String {
        var out = ""
        out.reserveCapacity(path.count)
        for ch in path {
            switch ch {
            case "*": out += "[*]"
            case "?": out += "[?]"
            case "[": out += "[[]"
            default: out.append(ch)
            }
        }
        return out
    }

    static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    static func join(_ components: [String]) -> String {
        "/" + components.joined(separator: "/")
    }

    /// Case-insensitive single-component match (APFS is case-insensitive by default).
    /// Both arguments must already be lowercased.
    static func matchComponent(_ name: String, _ pattern: String) -> Bool {
        if !hasWildcard(pattern) { return name == pattern }
        return fnmatch(pattern, name, 0) == 0
    }

    /// Case-insensitive name match against any of several globs.
    public static func matchesAny(_ name: String, _ patterns: [String]) -> Bool {
        let lower = name.lowercased()
        return patterns.contains { matchComponent(lower, $0.lowercased()) }
    }

    /// `realpath(3)`: resolves every symlink (unlike `NSString.resolvingSymlinksInPath`,
    /// which strips `/private`). Returns the input when the path does not exist.
    public static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return (path as NSString).standardizingPath }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Expands a glob without ever traversing a symbolic link or crossing into a
    /// non-directory. The final component may be any file system object (including a
    /// symlink, which callers skip). `denied` is set when a directory that had to be
    /// listed exists but could not be read.
    static func expand(_ pattern: String, includeHidden: Bool) -> (paths: [String], denied: Bool) {
        let comps = components(pattern)
        guard !comps.isEmpty else { return ([], false) }
        var current = ["/"]
        var denied = false
        for (index, component) in comps.enumerated() {
            let isLast = index == comps.count - 1
            var next: [String] = []
            for base in current {
                if hasWildcard(component) {
                    let names: [String]
                    do {
                        names = try FileManager.default.contentsOfDirectory(atPath: base)
                    } catch {
                        if FileWalker.entry(at: base)?.isDirectory == true { denied = true }
                        continue
                    }
                    let loweredPattern = component.lowercased()
                    let allowHidden = includeHidden || component.hasPrefix(".")
                    for name in names.sorted() {
                        if !allowHidden && name.hasPrefix(".") { continue }
                        guard matchComponent(name.lowercased(), loweredPattern) else { continue }
                        let candidate = child(of: base, name)
                        guard let entry = FileWalker.entry(at: candidate) else { continue }
                        if !isLast && (!entry.isDirectory || entry.isSymlink) { continue }
                        next.append(candidate)
                    }
                } else {
                    let candidate = child(of: base, component)
                    guard let entry = FileWalker.entry(at: candidate) else { continue }
                    if !isLast && (!entry.isDirectory || entry.isSymlink) { continue }
                    next.append(candidate)
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return (current, denied)
    }

    static func child(of base: String, _ name: String) -> String {
        base == "/" ? "/" + name : base + "/" + name
    }

    /// Lists a directory, distinguishing "unreadable" from "missing".
    static func list(_ path: String) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: path)
    }

    /// Groups SQLite database families (`x.db`, `x.db-wal`, `x.db-shm`, `x.db-journal`)
    /// so they are always kept or removed together.
    public static func familyKey(_ name: String) -> String {
        for suffix in ["-wal", "-shm", "-journal"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// Parses the first dotted version number in a folder name, e.g.
    /// "iPhone15,2 17.5.1 (21F90)" → [17, 5, 1]. Single numbers are ignored.
    public static func versionKey(_ name: String) -> [Int]? {
        for token in name.split(whereSeparator: { $0 == " " || $0 == "_" }) {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let numbers = parts.compactMap { Int($0) }
            if numbers.count == parts.count { return numbers }
        }
        return nil
    }

    /// Lexicographic numeric comparison; missing trailing parts count as zero.
    public static func versionLess(_ a: [Int], _ b: [Int]) -> Bool {
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// The strict parent directory of a path.
    static func parent(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    /// Path relative to `root` with `~` for the home folder, for subtitles.
    static func display(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

/// Maps cache folders to the app that owns them, and decides whether that app is running.
public enum CleanupOwnership {

    /// Every Firefox channel: they share one `Firefox`/`Mozilla` folder (and its profiles).
    static let firefoxChannels = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "org.mozilla.firefoxbeta",
    ]

    /// Folders that are named after a vendor rather than a bundle identifier, and the
    /// apps that use them (the first is the main one: its name titles the row).
    static let knownFolderOwners: [String: [String]] = [
        "google": ["com.google.Chrome"],
        "firefox": firefoxChannels,
        "mozilla": firefoxChannels,
        "bravesoftware": ["com.brave.Browser"],
        "microsoft edge": ["com.microsoft.edgemac"],
        "vivaldi": ["com.vivaldi.Vivaldi"],
        "opera software": ["com.operasoftware.Opera"],
        "slack": ["com.tinyspeck.slackmacgap"],
        "spotify": ["com.spotify.client"],
        "zoom": ["us.zoom.xos"],
        "discord": ["com.hnc.Discord"],
        "code": ["com.microsoft.VSCode"],
        "cursor": ["com.todesktop.230313mzl4w4u92"],
    ]

    /// Joins the owners of a folder several apps share in an owner hint
    /// (`CleanupMetadataKey.owner`), e.g. Firefox's release, Beta, Developer Edition
    /// and Nightly.
    public static let ownerSeparator: Character = "|"

    /// True for strings shaped like a reverse-DNS bundle identifier.
    public static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let first = parts.first, first.allSatisfy({ $0.isLetter }), first.count <= 12 else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    /// Every app a folder or file name may belong to: the bundle id it is named after, or
    /// the apps of a known vendor folder (main app first).
    public static func owners(forName name: String) -> [String] {
        if looksLikeBundleID(name) { return [name] }
        return knownFolderOwners[name.lowercased()] ?? []
    }

    /// Owner hint for a folder or file name: a bundle id, or a known vendor mapping
    /// (several apps joined with `ownerSeparator`).
    public static func owner(forName name: String) -> String? {
        let all = owners(forName: name)
        return all.isEmpty ? nil : all.joined(separator: String(ownerSeparator))
    }

    /// The bundle ids (or bundle id prefixes) in an owner hint, main app first.
    public static func owners(in owner: String) -> [String] {
        owner.split(separator: ownerSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The main app of an owner hint (the one whose name titles the row).
    public static func primaryOwner(of owner: String) -> String? {
        owners(in: owner).first
    }

    /// Owner hint for a group container id such as `UBF8T346G9.Office` or
    /// `group.com.example.app`.
    public static func owner(forGroupContainer name: String) -> String? {
        var core = name
        if core.hasPrefix("group.") { core = String(core.dropFirst(6)) }
        let parts = core.split(separator: ".")
        if let first = parts.first, first.count == 10, first.allSatisfy({ $0.isUppercase || $0.isNumber }), parts.count > 1 {
            core = parts.dropFirst().joined(separator: ".")
            if core.hasPrefix("group.") { core = String(core.dropFirst(6)) }
        }
        return looksLikeBundleID(core) ? core : nil
    }

    /// Preference domain from a plist file name (ByHost suffixes removed).
    public static func preferenceDomain(fileName: String) -> String {
        var name = fileName
        if let range = name.range(of: ".plist") { name = String(name[..<range.lowerBound]) }
        let parts = name.split(separator: ".")
        if let last = parts.last {
            let hex = last.allSatisfy { $0.isHexDigit || $0 == "-" }
            if parts.count > 2, hex, last.count >= 12 { name = parts.dropLast().joined(separator: ".") }
        }
        return name
    }

    /// Whether `owner` belongs to the running app `bundleID`: equal, or one is a
    /// reverse-DNS prefix of the other (helpers, ShipIt updaters…). An owner hint that
    /// names several apps matches any of them.
    public static func matches(owner: String, bundleID: String) -> Bool {
        owners(in: owner).contains { matchesOne(owner: $0, bundleID: bundleID) }
    }

    private static func matchesOne(owner: String, bundleID: String) -> Bool {
        let o = owner.lowercased()
        let b = bundleID.lowercased()
        guard !o.isEmpty, !b.isEmpty else { return false }
        if o == b { return true }
        // Require at least two components on the shorter side so "com" never matches.
        let shorter = o.count < b.count ? o : b
        guard shorter.split(separator: ".").count >= 2 else { return false }
        return o.hasPrefix(b + ".") || b.hasPrefix(o + ".")
    }

    public static func isRunning(owner: String, running: Set<String>) -> Bool {
        running.contains { matches(owner: owner, bundleID: $0) }
    }

    /// Owners of the given items that are currently running (for the "quit apps" prompt).
    public static func runningOwners(of items: [ScanItem], running: Set<String>) -> Set<String> {
        var result = Set<String>()
        for item in items {
            guard let owner = item.metadata[CleanupMetadataKey.owner] else { continue }
            for bundleID in running where matches(owner: owner, bundleID: bundleID) {
                result.insert(bundleID)
            }
        }
        return result
    }
}
