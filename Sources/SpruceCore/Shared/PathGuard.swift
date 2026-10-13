import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The last line of defence before anything is deleted, moved or modified.
///
/// Every removal in the app — whether a cache file, a leftover, a duplicate, or a
/// root-owned log — must pass `PathGuard.check` immediately before it happens.
/// The guard is deliberately conservative and independent of any rule catalog:
/// even if a scanner has a bug, the guard refuses to touch system trees, volume
/// roots, the home folder's top-level directories, keychains, iCloud Drive, etc.
///
/// It also enforces that *permanent* removal is only possible inside known
/// regenerable "junk zones" (caches, logs, temp, trash, build products). Anything
/// else can only be moved to the Trash, where the user can put it back.
public struct PathGuard: Sendable {

    public enum Verdict: Equatable, Sendable {
        case allowed
        case denied(String)

        public var isAllowed: Bool { self == .allowed }
        public var reason: String? {
            if case .denied(let r) = self { return r }
            return nil
        }
    }

    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Allow removing an entire `.app` bundle (Uninstaller only).
        public static let allowAppBundles = Options(rawValue: 1 << 0)
        /// Allow removing items inside a `.app` bundle (never used by default).
        public static let allowInsideAppBundles = Options(rawValue: 1 << 1)
        /// Allow items inside launch agent/daemon folders (login item management).
        public static let allowLaunchItems = Options(rawValue: 1 << 2)
    }

    public let home: String
    /// Additional directories in which permanent removal is acceptable.
    public let extraPermanentZones: [String]
    /// The current user's per-user folder in `/private/var/folders` (the parent of
    /// `$TMPDIR`), e.g. `/private/var/folders/ab/xyz…`, when known. Only its `T` and `C`
    /// folders may be acted on as administrator.
    public let userVarFolder: String?
    /// The current user's id (external Trash folders are `/Volumes/<disk>/.Trashes/<uid>`).
    public let uid: UInt32

    /// - Parameters:
    ///   - userTemporaryDirectory: the user's `$TMPDIR` (defaults to the process's own).
    ///   - uid: the user id (defaults to the process's own).
    public init(home: String = NSHomeDirectory(), extraPermanentZones: [String] = [],
                userTemporaryDirectory: String? = nil, uid: UInt32? = nil) {
        self.home = (home as NSString).standardizingPath
        self.extraPermanentZones = extraPermanentZones.map { ($0.expandingTilde as NSString).standardizingPath }
        self.userVarFolder = Self.varFolder(ofTemporaryDirectory: userTemporaryDirectory ?? NSTemporaryDirectory())
        self.uid = uid ?? UInt32(getuid())
    }

    /// `/private/var/folders/<a>/<b>` for a `$TMPDIR` of the form `…/var/folders/<a>/<b>/T`.
    static func varFolder(ofTemporaryDirectory tmp: String) -> String? {
        // Comparison keys are lowercased, so the lowercased spelling is all we need.
        let comps = key((tmp as NSString).standardizingPath).split(separator: "/").map(String.init)
        guard comps.count >= 6, comps[0] == "private", comps[1] == "var", comps[2] == "folders",
              comps[5] == "t" else { return nil }
        return "/private/var/folders/\(comps[3])/\(comps[4])"
    }

    // MARK: Public API

    /// Checks whether `path` may be disposed of with `method`.
    public func check(_ path: String, method: DeletionMethod = .trash, options: Options = []) -> Verdict {
        // 1. Shape checks.
        guard !path.isEmpty else { return .denied("Empty path") }
        guard path.hasPrefix("/") else { return .denied("Relative paths are not allowed") }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return .denied("Path contains control characters")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        if components.contains(where: { $0 == ".." || $0 == "." }) {
            return .denied("Path contains '.' or '..' components")
        }

        let standardized = (path as NSString).standardizingPath

        // 2. Check the path as given, and again with its *parent* resolved through
        //    symlinks (defeats /var -> /private/var games and symlinked ancestors).
        //    The final component itself is not resolved: removing a symlink only
        //    removes the link.
        let parent = (standardized as NSString).deletingLastPathComponent
        let resolvedParent = (parent as NSString).resolvingSymlinksInPath
        let resolved = (resolvedParent as NSString).appendingPathComponent((standardized as NSString).lastPathComponent)

        for candidate in Set([standardized, resolved]) {
            let verdict = checkStandardized(candidate, method: method, options: options)
            if !verdict.isAllowed { return verdict }
        }
        return .allowed
    }

    public func check(_ url: URL, method: DeletionMethod = .trash, options: Options = []) -> Verdict {
        check(url.path, method: method, options: options)
    }

    /// True when `path` lies inside a zone where permanent deletion is acceptable.
    public func isInPermanentZone(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let resolvedParent = ((standardized as NSString).deletingLastPathComponent as NSString).resolvingSymlinksInPath
        let resolved = (resolvedParent as NSString).appendingPathComponent((standardized as NSString).lastPathComponent)
        let keys = [Self.key(standardized), Self.key(resolved)]
        return keys.allSatisfy(inPermanentZone)
    }

    /// Checks whether `path` may be disposed of *as administrator* (`PrivilegedRunner`).
    ///
    /// On top of `check`, root may only act inside a short list of places where
    /// third-party software and regenerable data live (the home folder, `/Applications`,
    /// vendor folders in `/Library`, `/Users/Shared`, `/opt`, system logs and temporary
    /// files, the user's own temporary folders and external Trash). Everything else —
    /// system state in `/private/var`, other users' data, unlisted `/Library` folders —
    /// is refused even when the ordinary rules would allow moving it to the Trash.
    public func checkPrivileged(_ path: String, method: DeletionMethod = .trash, options: Options = []) -> Verdict {
        let verdict = check(path, method: method, options: options)
        guard verdict.isAllowed else { return verdict }
        let standardized = (path as NSString).standardizingPath
        let resolvedParent = ((standardized as NSString).deletingLastPathComponent as NSString).resolvingSymlinksInPath
        let resolved = (resolvedParent as NSString).appendingPathComponent((standardized as NSString).lastPathComponent)
        for candidate in Set([Self.key(standardized), Self.key(resolved)]) where !inPrivilegedZone(candidate) {
            return .denied("\(path.abbreviatingHome) needs administrator rights, which Spruce only uses for apps, their support files, caches, logs and temporary files")
        }
        return .allowed
    }

    /// True when `path` can be checked with `checkPrivileged` successfully as far as
    /// location is concerned (used by the UI to explain refusals up front).
    public func isInPrivilegedZone(_ path: String) -> Bool {
        inPrivilegedZone(Self.key((path as NSString).standardizingPath))
    }

    // MARK: Rules

    /// Exact paths that may never be removed themselves (their *contents* may be,
    /// subject to the other rules).
    private var protectedRoots: Set<String> {
        let h = home
        let roots = [
            "/", "/Applications", "/Applications/Utilities", "/Library", "/Library/Application Support",
            "/Library/Caches", "/Library/Logs", "/Library/Preferences", "/Library/LaunchAgents",
            "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Extensions",
            "/Library/Frameworks", "/Library/Fonts", "/Library/Internet Plug-Ins", "/Library/PreferencePanes",
            "/Library/Developer", "/Library/Updates",
            "/Users", "/Users/Shared", "/Users/Guest", "/Volumes", "/Network", "/cores",
            "/opt", "/opt/homebrew", "/opt/local", "/usr/local",
            "/private", "/private/tmp", "/private/var", "/private/var/tmp", "/private/var/folders",
            "/private/var/log", "/private/var/vm", "/tmp", "/var", "/etc",
            h,
            h + "/Applications", h + "/Desktop", h + "/Documents", h + "/Downloads", h + "/Movies",
            h + "/Music", h + "/Pictures", h + "/Public", h + "/Sites", h + "/.Trash",
            h + "/Library", h + "/Library/Caches", h + "/Library/Logs", h + "/Library/Application Support",
            h + "/Library/Preferences", h + "/Library/Containers", h + "/Library/Group Containers",
            h + "/Library/LaunchAgents", h + "/Library/Mail", h + "/Library/Developer",
            h + "/Library/Developer/Xcode", h + "/Library/Saved Application State", h + "/Library/HTTPStorages",
            h + "/Library/WebKit", h + "/Library/Cookies", h + "/Library/CloudStorage", h + "/Library/Fonts",
            h + "/Library/Safari", h + "/Library/Messages",
            h + "/.config", h + "/.local", h + "/.ssh", h + "/.gnupg",
        ]
        return Set(roots.map(Self.key))
    }

    /// Whole trees that may never be touched at all.
    private var protectedTrees: [String] {
        let h = home
        return [
            "/System", "/bin", "/sbin", "/usr", "/dev", "/etc", "/private/etc",
            "/private/var/db", "/var/db", "/private/var/audit", "/var/audit",
            "/private/var/root", "/var/root", "/private/var/protected", "/private/var/vm",
            "/Library/Apple", "/Library/Keychains", "/Library/Security", "/Library/SystemMigration",
            "/Library/Application Support/Apple", "/Library/Application Support/com.apple.TCC",
            "/Library/Filesystems", "/Library/StagedExtensions", "/Library/SystemExtensions",
            "/Library/Updates", "/Library/Managed Preferences", "/Library/DirectoryServices",
            "/Library/Preferences/SystemConfiguration", "/Library/Preferences/OpenDirectory",
            "/Library/Preferences/Logging",
            "/Applications/Safari.app", "/Applications/Utilities/Terminal.app",
            h + "/Library/Keychains",
            h + "/Library/Mobile Documents",          // iCloud Drive
            h + "/Library/Application Support/com.apple.TCC",
            h + "/Library/Application Support/MobileSync/Backup/.MobileSyncBackupLock",
            h + "/Library/Messages/Attachments",
            h + "/Library/Accounts",
            h + "/Library/Cookies/Cookies.binarycookies",
            h + "/Library/Group Containers/group.com.apple.notes",
            h + "/Library/Containers/com.apple.Notes",
            h + "/Library/Biome", h + "/Library/IdentityServices",
            h + "/Library/Caches/com.apple.FontRegistry",
            h + "/Library/Caches/com.apple.Spotlight", h + "/Library/Caches/CloudKit",
            h + "/Library/Caches/com.apple.LaunchServices",
            h + "/Library/Caches/com.apple.iconservices.store",
            h + "/Library/Caches/Metadata",
            h + "/Library/Logs/Spruce",               // our own operation log
            h + "/.ssh", h + "/.gnupg", h + "/.password-store",
        ]
    }

    /// Path components that mark data we never touch (password managers, wallets, VPNs).
    private static let protectedComponents: [String] = [
        "keychain", "1password", "bitwarden", "lastpass", "keepass", "dashlane", "enpass",
        "wallet", "electrum", "exodus", "ledger live", "metamask",
    ]

    /// Directories in which permanent removal (no Trash) is acceptable.
    private var permanentZones: [String] {
        let h = home
        let zones = [
            h + "/Library/Caches", h + "/Library/Logs", h + "/.Trash",
            h + "/Library/Developer/Xcode/DerivedData", h + "/Library/Developer/Xcode/iOS DeviceSupport",
            h + "/Library/Developer/Xcode/watchOS DeviceSupport", h + "/Library/Developer/Xcode/tvOS DeviceSupport",
            h + "/Library/Developer/Xcode/visionOS DeviceSupport", h + "/Library/Developer/Xcode/macOS DeviceSupport",
            h + "/Library/Developer/Xcode/Products",
            h + "/Library/Developer/Xcode/UserData/Previews", h + "/Library/Developer/CoreSimulator/Caches",
            h + "/Library/Developer/XCTestDevices",
            h + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            h + "/Library/Mail Downloads",
            h + "/Library/Application Support/CrashReporter",
            h + "/Library/iTunes/iPhone Software Updates", h + "/Library/iTunes/iPad Software Updates",
            h + "/Library/Saved Application State",
            h + "/.npm/_cacache", h + "/.npm/_logs", h + "/.yarn/cache", h + "/.pnpm-store",
            h + "/.cache", h + "/.gradle/caches", h + "/.gradle/wrapper/dists", h + "/.m2/repository",
            h + "/.cocoapods/repos", h + "/.cargo/registry/cache", h + "/.bun/install/cache",
            h + "/go/pkg/mod/cache", h + "/.android/cache", h + "/.dartServer", h + "/.pub-cache",
            h + "/.nuget/packages", h + "/.composer/cache", h + "/.expo",
            "/Library/Caches", "/Library/Logs", "/private/var/log", "/private/tmp", "/private/var/tmp",
            // Per-user temporary and cache folders in /private/var/folders: see `varFolderArea`.
        ] + extraPermanentZones
        return zones.map(Self.key)
    }

    private func inPermanentZone(_ k: String) -> Bool {
        if case .contents = Self.varFolderArea(k) { return true }
        // The user's Trash on other disks is Trash too.
        if isInsideExternalTrash(k) { return true }
        return permanentZones.contains { Self.isStrictlyInside(k, $0) }
    }

    /// `/Volumes/<disk>/.Trashes/<uid>/…` for the current user.
    private func isInsideExternalTrash(_ k: String) -> Bool {
        let comps = k.split(separator: "/").map(String.init)
        return comps.count > 4 && comps[0] == "volumes" && comps[2] == ".trashes" && comps[3] == String(uid)
    }

    /// Where root may act at all (see `checkPrivileged`). Lowercased keys.
    private var privilegedZones: [String] {
        let zones = [
            home, "/Applications", "/Users/Shared", "/opt",
            "/Library/Application Support", "/Library/Caches", "/Library/Logs", "/Library/Preferences",
            "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
            "/Library/Internet Plug-Ins", "/Library/PreferencePanes", "/Library/QuickLook", "/Library/Spotlight",
            "/Library/Screen Savers", "/Library/Input Methods", "/Library/Services", "/Library/Audio/Plug-Ins",
            "/Library/Developer",
            "/private/var/log", "/private/tmp", "/private/var/tmp",
        ]
        return zones.map(Self.key)
    }

    private func inPrivilegedZone(_ k: String) -> Bool {
        if privilegedZones.contains(where: { Self.isStrictlyInside(k, $0) }) { return true }
        // The current user's own temporary and cache folders.
        if let folder = userVarFolder {
            let base = Self.key(folder)
            if Self.isStrictlyInside(k, base + "/t") || Self.isStrictlyInside(k, base + "/c") { return true }
        }
        // The current user's Trash on other disks.
        return isInsideExternalTrash(k)
    }

    /// Classifies a key inside `/private/var/folders`. The per-user `T` (temporary) and
    /// `C` (cache) folders of any account hold regenerable data; everything else there —
    /// the folders themselves, `0` (per-user system state), `-Caches-`, daemon folders —
    /// is managed by macOS.
    enum VarFolderArea: Equatable {
        case outside
        case contents
        case system
    }

    static func varFolderArea(_ k: String) -> VarFolderArea {
        let comps = k.split(separator: "/").map(String.init)
        guard comps.count >= 3, comps[0] == "private", comps[1] == "var", comps[2] == "folders" else { return .outside }
        if comps.count >= 7, comps[5] == "t" || comps[5] == "c" { return .contents }
        return .system
    }

    /// True for system state in `/private/var` (anything but logs, temporary files and
    /// per-user temporary/cache folders).
    private static func isVarSystemState(_ k: String) -> Bool {
        guard isStrictlyInside(k, "/private/var") else { return false }
        switch varFolderArea(k) {
        case .contents: return false
        case .system: return true
        case .outside: break
        }
        return !(isStrictlyInside(k, "/private/var/log") || isStrictlyInside(k, "/private/var/tmp"))
    }

    /// True when `k` is inside the user's Trash (home or an external disk's `.Trashes/<uid>`).
    private func isInsideTrash(_ k: String) -> Bool {
        Self.isStrictlyInside(k, Self.key(home + "/.Trash")) || isInsideExternalTrash(k)
    }

    private func checkStandardized(_ path: String, method: DeletionMethod, options: Options) -> Verdict {
        let k = Self.key(path)

        if protectedRoots.contains(k) {
            return .denied("\(path.abbreviatingHome) is a protected location")
        }
        for tree in protectedTrees where Self.isInsideOrEqual(k, Self.key(tree)) {
            return .denied("\(path.abbreviatingHome) is inside a protected area (\(tree.abbreviatingHome))")
        }
        // System state in /private/var (network, scheduled jobs, daemon data, other
        // accounts' per-user folders…). Logs, temporary files and per-user temporary and
        // cache folders stay reachable.
        if Self.isVarSystemState(k) {
            return .denied("\(path.abbreviatingHome) is system data managed by macOS")
        }
        // Apple's own system-wide preferences (network, firewall, login window…).
        if Self.isStrictlyInside(k, "/library/preferences") {
            let name = k.split(separator: "/").map(String.init)[2]
            if name.hasPrefix("com.apple.") || name.hasPrefix(".globalpreferences") {
                return .denied("\(path.abbreviatingHome) is a macOS system setting")
            }
        }

        // Volume roots and the top level of every external volume.
        let comps = k.split(separator: "/").map(String.init)
        if comps.first == "volumes", comps.count <= 2 {
            return .denied("Volume roots cannot be removed")
        }
        // Other users' home folders.
        if comps.first == "users", comps.count >= 2, !Self.isInsideOrEqual(k, Self.key(home)),
           comps[1] != "shared" {
            return .denied("Other users' files are off limits")
        }

        // Sensitive data stores, anywhere — except items the user already put in the
        // Trash (emptying the Trash must be able to finish).
        if !(method == .remove && isInsideTrash(k)) {
            for c in comps {
                for marker in Self.protectedComponents where c.contains(marker) {
                    return .denied("Looks like credential or wallet data (\(marker))")
                }
            }
        }

        // App bundles.
        if let appIndex = comps.indices.first(where: { isAppBundleComponent(comps, $0, originalPath: path) }) {
            let isBundleItself = appIndex == comps.count - 1
            if isBundleItself {
                if !options.contains(.allowAppBundles) {
                    return .denied("Applications can only be removed by the Uninstaller")
                }
            } else if !options.contains(.allowInsideAppBundles) {
                return .denied("Modifying the inside of an application bundle would break its signature")
            }
        }
        // Photos libraries are databases; never pick files out of them.
        if let libIndex = comps.firstIndex(where: { $0.hasSuffix(".photoslibrary") }), libIndex < comps.count - 1 {
            return .denied("Files inside a Photos library are managed by Photos")
        }

        // Launch agents/daemons only through login-item management, never Apple's.
        let isLaunchItem = k.contains("/launchagents/") || k.contains("/launchdaemons/")
        if isLaunchItem {
            if !options.contains(.allowLaunchItems) {
                return .denied("Launch items are managed in Performance › Login Items")
            }
            if (k as NSString).lastPathComponent.hasPrefix("com.apple.") {
                return .denied("Apple launch items are never modified")
            }
        }

        // Permanent removal only inside regenerable zones.
        if method == .remove {
            if !inPermanentZone(k) {
                return .denied("\(path.abbreviatingHome) can only be moved to the Trash, not deleted permanently")
            }
        }
        return .allowed
    }

    /// A ".app" component is treated as an application bundle when it really looks like
    /// one: it has a Contents folder (on disk or as the next component) or it lives in an
    /// Applications folder. This avoids misclassifying cache folders such as
    /// `~/Library/Caches/com.vendor.app`.
    private func isAppBundleComponent(_ comps: [String], _ index: Int, originalPath: String) -> Bool {
        guard comps[index].hasSuffix(".app") else { return false }
        if index + 1 < comps.count, comps[index + 1] == "contents" { return true }
        let parent = "/" + comps[..<index].joined(separator: "/")
        let applicationFolders = ["/applications", "/applications/utilities", "/system/applications",
                                  "/system/applications/utilities", Self.key(home + "/Applications")]
        if applicationFolders.contains(parent) { return true }
        // Check the real file system using the original (case-preserving) path.
        let originalComps = originalPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard index < originalComps.count else { return false }
        let bundlePath = "/" + originalComps[...index].joined(separator: "/")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: bundlePath + "/Contents", isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: Path math

    /// Case-insensitive comparison key (APFS is case-insensitive by default),
    /// with /var, /tmp and /etc mapped onto their /private targets.
    public static func key(_ path: String) -> String {
        var p = path.lowercased()
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        for alias in ["/var", "/tmp", "/etc"] where p == alias || p.hasPrefix(alias + "/") {
            p = "/private" + p
            break
        }
        return p
    }

    public static func isInsideOrEqual(_ path: String, _ root: String) -> Bool {
        path == root || isStrictlyInside(path, root)
    }

    public static func isStrictlyInside(_ path: String, _ root: String) -> Bool {
        if root == "/" { return path != "/" }
        return path.hasPrefix(root + "/")
    }
}
