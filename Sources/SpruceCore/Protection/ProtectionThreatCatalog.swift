import Foundation

// Curated catalog of publicly documented macOS adware / malware / PUA indicators.
//
// Sources: public research write-ups (Objective-See, SentinelOne, Jamf, Kandji, Red Canary,
// Malwarebytes, Check Point, ESET, Huntress…) as collected in the public index
// `stuartjash/macos-malware-kb` (families/*.md, fetched 2026-10-12), plus the AMOS backdoor
// persistence documented by Moonlock Lab and Gen Digital (SigmaHQ rule). Only specific,
// low-collision indicators are included; generic names are left to the heuristics.
// Hash matches are ignored for Apple-signed files, so a wrong entry can never flag macOS itself.

/// A known threat family.
public struct ProtectionThreatFamily: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let category: ThreatCategory
    public let severity: ThreatSeverity
    /// One-line original description shown in the inspector.
    public let summary: String

    public init(id: String, name: String, category: ThreatCategory, severity: ThreatSeverity, summary: String) {
        self.id = id
        self.name = name
        self.category = category
        self.severity = severity
        self.summary = summary
    }
}

/// One documented indicator of compromise.
public struct ProtectionIndicator: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        /// Logical path glob (`~` = home). `*` and `?` stay within one path component.
        case path
        /// Regular expression over the logical path.
        case pathRegex
        /// Launch job label glob.
        case launchLabel
        /// Bundle identifier glob.
        case bundleID
        /// Bundle (or extension) name glob, e.g. "Advanced Mac Cleaner.app".
        case bundleName
        /// Apple Developer Team ID of a revoked malware signing identity.
        case teamID
        /// SHA-256 of a malicious file (lowercase hex).
        case sha256
    }

    public let kind: Kind
    public let pattern: String
    public let familyID: String
    /// Only match executable files (Mach-O, scripts with a shebang, or files with an x bit).
    public let executableOnly: Bool

    public init(_ kind: Kind, _ pattern: String, family: String, executableOnly: Bool = false) {
        self.kind = kind
        self.pattern = pattern
        self.familyID = family
        self.executableOnly = executableOnly
    }
}

/// A catalog hit.
public struct ProtectionCatalogMatch: Sendable, Hashable {
    public let family: ProtectionThreatFamily
    public let indicator: ProtectionIndicator

    /// Human-readable reason for the inspector.
    public var reason: String {
        if family.id == "fakeflash" {
            return "Uses the name of the retired Flash Player, a common disguise for malware installers"
        }
        switch indicator.kind {
        case .path, .pathRegex: return "Location used by \(family.name)"
        case .launchLabel: return "Startup job name used by \(family.name)"
        case .bundleID: return "App identifier of \(family.name)"
        case .bundleName: return "Known \(family.name) component"
        case .teamID: return "Signed with a revoked developer identity used by \(family.name)"
        case .sha256: return "File is a known \(family.name) sample (SHA-256 match)"
        }
    }

    public var evidence: ThreatEvidence { indicator.kind == .sha256 ? .knownHash : .knownIndicator }
}

/// Case-insensitive glob matching where `*`/`?` never cross a `/`.
public enum ProtectionGlob {
    public static func matches(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased().unicodeScalars)
        let t = Array(text.lowercased().unicodeScalars)
        return match(p, 0, t, 0)
    }

    private static func match(_ p: [Unicode.Scalar], _ pi: Int, _ t: [Unicode.Scalar], _ ti: Int) -> Bool {
        var pi = pi
        var ti = ti
        var starP = -1
        var starT = -1
        while ti < t.count {
            if pi < p.count, p[pi] == "*" {
                starP = pi
                starT = ti
                pi += 1
            } else if pi < p.count, (p[pi] == "?" && t[ti] != "/") || p[pi] == t[ti] {
                pi += 1
                ti += 1
            } else if starP >= 0, t[starT] != "/" {
                // Let the last star absorb one more character (never a slash).
                pi = starP + 1
                starT += 1
                ti = starT
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// True when the pattern contains wildcards.
    public static func isPattern(_ s: String) -> Bool { s.contains("*") || s.contains("?") }
}

/// The curated indicator catalog.
public struct ProtectionThreatCatalog: Sendable {
    public let families: [ProtectionThreatFamily]
    public let indicators: [ProtectionIndicator]

    private let familiesByID: [String: ProtectionThreatFamily]
    private let hashes: [String: String]
    private let teams: [String: String]

    public init(families: [ProtectionThreatFamily], indicators: [ProtectionIndicator]) {
        self.families = families
        self.indicators = indicators
        var byID: [String: ProtectionThreatFamily] = [:]
        for family in families { byID[family.id] = family }
        familiesByID = byID
        var hashes: [String: String] = [:]
        var teams: [String: String] = [:]
        for indicator in indicators {
            switch indicator.kind {
            case .sha256: hashes[indicator.pattern.lowercased()] = indicator.familyID
            case .teamID: teams[indicator.pattern.uppercased()] = indicator.familyID
            default: break
            }
        }
        self.hashes = hashes
        self.teams = teams
    }

    public func family(id: String) -> ProtectionThreatFamily? { familiesByID[id] }

    // MARK: Matching

    /// Matches a logical path ("~/…" or "/…", see `ProtectionPathSpace`).
    public func matchPath(_ logicalPath: String, isExecutable: Bool) -> ProtectionCatalogMatch? {
        for indicator in indicators where indicator.kind == .path || indicator.kind == .pathRegex {
            if indicator.executableOnly && !isExecutable { continue }
            let hit: Bool
            if indicator.kind == .path {
                hit = ProtectionGlob.matches(indicator.pattern, logicalPath)
            } else {
                hit = ProtectionRegexCache.matches(indicator.pattern, logicalPath)
            }
            if hit, let match = makeMatch(indicator) { return match }
        }
        return nil
    }

    /// Matches a path or any of its ancestors (a file inside a known malicious folder).
    public func matchPathOrAncestor(_ logicalPath: String, isExecutable: Bool) -> ProtectionCatalogMatch? {
        var current = logicalPath
        var first = true
        while current.count > 1 {
            if let match = matchPath(current, isExecutable: first ? isExecutable : false) { return match }
            first = false
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty || parent == "~" || parent == "/" { break }
            current = parent
        }
        return nil
    }

    public func matchLabel(_ label: String) -> ProtectionCatalogMatch? {
        firstMatch(.launchLabel) { ProtectionGlob.matches($0, label) }
    }

    public func matchBundleID(_ bundleID: String) -> ProtectionCatalogMatch? {
        firstMatch(.bundleID) { ProtectionGlob.matches($0, bundleID) }
    }

    public func matchBundleName(_ name: String) -> ProtectionCatalogMatch? {
        firstMatch(.bundleName) { ProtectionGlob.matches($0, name) }
    }

    public func matchTeamID(_ teamID: String) -> ProtectionCatalogMatch? {
        guard let familyID = teams[teamID.uppercased()] else { return nil }
        let indicator = ProtectionIndicator(.teamID, teamID.uppercased(), family: familyID)
        return makeMatch(indicator)
    }

    public func matchHash(_ sha256: String) -> ProtectionCatalogMatch? {
        guard let familyID = hashes[sha256.lowercased()] else { return nil }
        return makeMatch(ProtectionIndicator(.sha256, sha256.lowercased(), family: familyID))
    }

    /// Concrete (wildcard-free) path indicators: checked for existence on every scan.
    public var literalPaths: [ProtectionIndicator] {
        indicators.filter { $0.kind == .path && !ProtectionGlob.isPattern($0.pattern) }
    }

    /// Wildcard path indicators whose wildcards are only in the last component
    /// (expandable with one directory listing).
    public var leafPatternPaths: [ProtectionIndicator] {
        indicators.filter { indicator in
            guard indicator.kind == .path, ProtectionGlob.isPattern(indicator.pattern) else { return false }
            let parent = (indicator.pattern as NSString).deletingLastPathComponent
            return !ProtectionGlob.isPattern(parent)
        }
    }

    public var hashCount: Int { hashes.count }

    private func firstMatch(_ kind: ProtectionIndicator.Kind, _ test: (String) -> Bool) -> ProtectionCatalogMatch? {
        for indicator in indicators where indicator.kind == kind && test(indicator.pattern) {
            if let match = makeMatch(indicator) { return match }
        }
        return nil
    }

    private func makeMatch(_ indicator: ProtectionIndicator) -> ProtectionCatalogMatch? {
        guard let family = familiesByID[indicator.familyID] else { return nil }
        return ProtectionCatalogMatch(family: family, indicator: indicator)
    }

    // MARK: Constants

    /// Adobe Inc.'s Developer Team ID. Flash Player reached end of life in 2020, so any
    /// other "Flash Player" installer is a classic adware dropper disguise.
    public static let adobeTeamID = "JQ525L2MZD"

    /// Search/homepage hijack domains documented for adware families.
    public static let hijackDomains: [String] = [
        "trovi.com", "search-quick.com", "chumsearch.com", "safefinder.com", "safefinderformac.com",
        "macsafefinder.com", "safefinder.net", "searchmine.net", "search.conduit.com", "weknow.ac",
        "myshopcouponmac.com", "mycouponsmartmac.com", "shoptimizelymac.com",
    ]

    /// True when `text` mentions a documented hijack domain.
    public static func mentionsHijackDomain(_ text: String) -> String? {
        let lower = text.lowercased()
        return hijackDomains.first { lower.contains($0) }
    }
}

/// Converts real paths into the catalog's logical form ("~/…" for the home folder,
/// "/…" relative to the scanned root), so tests can scan a fake root.
public struct ProtectionPathSpace: Sendable, Hashable {
    public let home: String
    /// Prefix of the scanned system root ("" for the real "/").
    public let root: String

    public init(home: String, root: String = "") {
        self.home = (home as NSString).standardizingPath
        self.root = root.isEmpty ? "" : (root as NSString).standardizingPath
    }

    /// Real path → logical path.
    public func logical(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        if !root.isEmpty, path.hasPrefix(root + "/") { return String(path.dropFirst(root.count)) }
        return path
    }

    /// Logical path → real path.
    public func real(_ logicalPath: String) -> String {
        if logicalPath == "~" { return home }
        if logicalPath.hasPrefix("~/") { return home + logicalPath.dropFirst(1) }
        return root + logicalPath
    }

    /// Real path of a system location ("/Library/LaunchAgents").
    public func system(_ path: String) -> String { root + path }
}

/// Compiled-regex cache (NSRegularExpression is thread-safe once created).
enum ProtectionRegexCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = regex(pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    static func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        cache[pattern] = compiled
        return compiled
    }
}

// MARK: - Standard catalog

public extension ProtectionThreatCatalog {
    static let standard = ProtectionThreatCatalog(families: ProtectionCatalogData.families,
                                                  indicators: ProtectionCatalogData.indicators)
}

enum ProtectionCatalogData {
    static let families: [ProtectionThreatFamily] = [
        // Adware & browser hijackers
        .init(id: "adload", name: "Adload", category: .adware, severity: .high,
              summary: "Adware that hides in randomly numbered folders, proxies your browsing to inject ads and can turn the Mac into a proxy node."),
        .init(id: "pirrit", name: "Pirrit", category: .adware, severity: .high,
              summary: "Adware that installs a system daemon and redirects web traffic through a local ad-injecting proxy."),
        .init(id: "genieo", name: "Genieo", category: .browserHijacker, severity: .high,
              summary: "Long-running browser hijacker that replaces the homepage and search engine and tracks searches."),
        .init(id: "bundlore", name: "Bundlore", category: .adware, severity: .high,
              summary: "Adware bundler usually delivered as a fake player or Flash installer; installs further adware."),
        .init(id: "shlayer", name: "Shlayer", category: .dropper, severity: .high,
              summary: "Malware installer disguised as a media player or Flash update that downloads adware."),
        .init(id: "chromeloader", name: "ChromeLoader", category: .browserHijacker, severity: .high,
              summary: "Force-loads a malicious browser extension at every login to hijack searches."),
        .init(id: "convuster", name: "Convuster", category: .adware, severity: .high,
              summary: "Adware that persists as a launch job and serves ads through the browser."),
        .init(id: "maxofferdeal", name: "MaxOfferDeal", category: .adware, severity: .high,
              summary: "Adware variant that persists through a per-user launch agent and injects shopping offers."),
        .init(id: "mughthesec", name: "Mughthesec", category: .adware, severity: .high,
              summary: "Adware delivered as a fake Flash Player installer; installs further unwanted software."),
        .init(id: "hydromac", name: "HydroMac", category: .adware, severity: .high,
              summary: "Adware that installs a system daemon and phones home for more payloads."),
        .init(id: "searchprotect", name: "SearchProtect (Conduit)", category: .browserHijacker, severity: .high,
              summary: "Search hijacker that loads plug-ins into browsers to redirect searches."),
        .init(id: "vsearch", name: "VSearch / Trovi", category: .browserHijacker, severity: .high,
              summary: "Search hijacker that redirects searches to its own portal."),
        .init(id: "mami", name: "MaMi", category: .browserHijacker, severity: .critical,
              summary: "Hijacks DNS settings and installs a rogue root certificate to intercept web traffic."),
        .init(id: "fakeflash", name: "Fake Flash Player installer", category: .dropper, severity: .high,
              summary: "Flash Player was retired in 2020; installers using its name are a classic disguise for adware droppers."),
        // Potentially unwanted apps
        .init(id: "advancedmaccleaner", name: "Advanced Mac Cleaner", category: .pua, severity: .medium,
              summary: "Scareware-style cleaner often bundled with adware; flagged as unwanted by many vendors."),
        .init(id: "macmechanic", name: "MacMechanic", category: .pua, severity: .medium,
              summary: "System \"optimizer\" commonly bundled with adware installers."),
        .init(id: "mackeeperlegacy", name: "MacKeeper (legacy edition)", category: .pua, severity: .medium,
              summary: "Older edition of a utility suite widely flagged as potentially unwanted."),
        // Stealers
        .init(id: "amos", name: "Atomic Stealer (AMOS)", category: .stealer, severity: .critical,
              summary: "Steals Keychain passwords, browser data and crypto wallets; newer builds add a hidden backdoor."),
        .init(id: "banshee", name: "Banshee Stealer", category: .stealer, severity: .critical,
              summary: "Phishes your login password with a fake dialog and steals browser and wallet data."),
        .init(id: "cuckoo", name: "Cuckoo", category: .stealer, severity: .critical,
              summary: "Spyware and stealer hidden in a hidden folder of your home, restarted at every login."),
        .init(id: "macsync", name: "MacSync", category: .stealer, severity: .critical,
              summary: "Stealer with a backdoor component that keeps a sync worker running in the background."),
        .init(id: "odyssey", name: "Odyssey Stealer", category: .stealer, severity: .critical,
              summary: "AppleScript stealer that collects passwords, cookies and wallet data."),
        .init(id: "poseidon", name: "Poseidon Stealer", category: .stealer, severity: .critical,
              summary: "Stealer distributed through fake browser download sites."),
        .init(id: "realst", name: "Realst", category: .stealer, severity: .critical,
              summary: "Stealer delivered as fake blockchain games."),
        .init(id: "xloader", name: "XLoader", category: .stealer, severity: .critical,
              summary: "Steals credentials and logs keystrokes; hides its copy under a random name."),
        // Ransomware & miners
        .init(id: "evilquest", name: "EvilQuest", category: .ransomware, severity: .critical,
              summary: "Ransomware and spyware that disguises its startup jobs as Apple services."),
        .init(id: "keranger", name: "KeRanger", category: .ransomware, severity: .critical,
              summary: "Ransomware once shipped inside a compromised app download."),
        .init(id: "loudminer", name: "LoudMiner", category: .miner, severity: .high,
              summary: "Cryptominer bundled with pirated software; runs a hidden virtual machine."),
        .init(id: "osaminer", name: "OSAMiner", category: .miner, severity: .high,
              summary: "Cryptominer hidden in compiled AppleScripts disguised as Apple startup items."),
        .init(id: "ppminer", name: "PPMiner", category: .miner, severity: .high,
              summary: "Cryptominer that installs a launcher daemon and a mining helper."),
        // Backdoors, spyware, trojans
        .init(id: "fruitfly", name: "FruitFly", category: .backdoor, severity: .critical,
              summary: "Spying backdoor that hides as a script in your home folder."),
        .init(id: "eleanor", name: "Eleanor", category: .backdoor, severity: .critical,
              summary: "Backdoor that disguises its startup jobs as Dropbox components."),
        .init(id: "coldroot", name: "Coldroot", category: .backdoor, severity: .critical,
              summary: "Remote-access trojan disguised as an Apple audio driver."),
        .init(id: "mokes", name: "Mokes", category: .spyware, severity: .critical,
              summary: "Spyware that records the screen, audio and keystrokes from look-alike folders."),
        .init(id: "calisto", name: "Calisto", category: .backdoor, severity: .critical,
              summary: "Backdoor disguised as a security product installer."),
        .init(id: "proton", name: "Proton", category: .backdoor, severity: .critical,
              summary: "Remote-access trojan once distributed through hijacked app downloads."),
        .init(id: "dazzlespy", name: "DazzleSpy", category: .spyware, severity: .critical,
              summary: "Spyware implant disguised as a software update agent."),
        .init(id: "dok", name: "Dok", category: .trojan, severity: .critical,
              summary: "Intercepts web traffic through a rogue proxy disguised as Safari components."),
        .init(id: "cloudmensis", name: "CloudMensis", category: .spyware, severity: .critical,
              summary: "Spyware that uses cloud storage as its command channel."),
        .init(id: "jokerspy", name: "JokerSpy", category: .backdoor, severity: .critical,
              summary: "Backdoor toolkit dropped in the shared users folder."),
        .init(id: "rustbucket", name: "RustBucket", category: .backdoor, severity: .critical,
              summary: "Backdoor delivered as a fake PDF viewer, persisting as a fake system update."),
        .init(id: "windtail", name: "WindTail", category: .backdoor, severity: .critical,
              summary: "Backdoor disguised as a presentation document."),
        .init(id: "geacon", name: "Geacon", category: .backdoor, severity: .critical,
              summary: "Remote-control implant hidden in look-alike Apple tool bundles."),
        .init(id: "silversparrow", name: "Silver Sparrow", category: .dropper, severity: .high,
              summary: "Downloader that checks in hourly for new payloads."),
        .init(id: "zshlayer", name: "ZShlayer", category: .dropper, severity: .high,
              summary: "Script-based adware dropper delivered in disk images."),
        .init(id: "xcsset", name: "XCSSET", category: .backdoor, severity: .critical,
              summary: "Backdoor that spreads through infected Xcode projects."),
    ]

    static let indicators: [ProtectionIndicator] = paths + labels + bundles + teams + hashes

    private static let paths: [ProtectionIndicator] = [
        // Adload: hidden numeric folders with Services/System components.
        .init(.pathRegex, #"^~/Library/Application Support/\.[0-9]{19,}(/|$)"#, family: "adload"),
        .init(.pathRegex, #"^/Library/Application Support/\.[0-9]{19,}(/|$)"#, family: "adload"),
        .init(.pathRegex, #"^/(private/)?tmp/php[A-Za-z0-9]{6}$"#, family: "adload", executableOnly: true),
        .init(.path, "~/.logg", family: "adload"),
        // Pirrit
        .init(.path, "/Library/LaunchDaemons/com.*.net-preferences.plist", family: "pirrit"),
        .init(.path, "/etc/change_net_settings.sh", family: "pirrit"),
        .init(.path, "/etc/pf_proxy.conf", family: "pirrit"),
        .init(.path, "/private/etc/change_net_settings.sh", family: "pirrit"),
        .init(.path, "/private/etc/pf_proxy.conf", family: "pirrit"),
        .init(.path, "/var/tmp/updText.txt", family: "pirrit"),
        .init(.path, "/private/var/tmp/updText.txt", family: "pirrit"),
        // Genieo
        .init(.path, "/Library/PrivilegedHelperTools/com.genieoinnovation.macextension.client", family: "genieo"),
        .init(.path, "/Applications/Genieo.app", family: "genieo"),
        .init(.path, "~/Library/Application Support/Genieo", family: "genieo"),
        // Bundlore
        .init(.path, "~/Applications/PingTrusteer", family: "bundlore"),
        .init(.pathRegex, #"^/(private/)?tmp/\.[^/]{9,}/(player|install)\.app(/|$)"#, family: "bundlore"),
        // ChromeLoader
        .init(.path, "~/Library/LaunchAgents/com.chrome.extension.plist", family: "chromeloader"),
        .init(.path, "~/Library/LaunchAgents/com.chrome.extensions.plist", family: "chromeloader"),
        .init(.path, "~/Library/LaunchAgents/com.chrome.extensionsPop.plist", family: "chromeloader"),
        .init(.path, "~/Library/LaunchAgents/com.safarii.extension.plist", family: "chromeloader"),
        .init(.path, "~/Library/LaunchAgents/com.extension.pop.plist", family: "chromeloader"),
        // MaxOfferDeal
        .init(.path, "~/Library/Application Support/.gettime", family: "maxofferdeal"),
        // Mughthesec
        .init(.path, "~/Library/Application Support/com.Mughthesec", family: "mughthesec"),
        .init(.path, "~/Library/LaunchAgents/com.Mughthesec.plist", family: "mughthesec"),
        // HydroMac
        .init(.path, "/Library/LaunchDaemons/com.MapperState.system.plist", family: "hydromac"),
        // SearchProtect / Conduit
        .init(.path, "/Library/LaunchAgents/com.conduit.loader.agent.plist", family: "searchprotect"),
        .init(.path, "/Library/Application Support/Conduit", family: "searchprotect"),
        .init(.path, "/Library/InputManagers/CTLoader", family: "searchprotect"),
        .init(.path, "/Library/Application Support/SIMBL/Plugins/CT2285220.bundle", family: "searchprotect"),
        .init(.path, "~/Library/Internet Plug-Ins/ConduitNPAPIPlugin.plugin", family: "searchprotect"),
        // VSearch / Trovi
        .init(.path, "/Library/uyerrack", family: "vsearch"),
        // MaMi
        .init(.path, "/Library/LaunchDaemons/Cyclonica.plist", family: "mami"),
        // MacMechanic
        .init(.path, "~/Library/Caches/com.macmechanic.mmhlpr", family: "macmechanic"),
        // Atomic Stealer (AMOS) backdoor and ClickFix builds
        .init(.path, "~/.helper", family: "amos", executableOnly: true),
        .init(.path, "~/.agent", family: "amos", executableOnly: true),
        .init(.path, "/Library/LaunchDaemons/com.finder.helper.plist", family: "amos"),
        .init(.path, "/Library/LaunchDaemons/com.xdivcmp.plist", family: "amos"),
        .init(.path, "/tmp/lksopo", family: "amos"),
        .init(.path, "/tmp/lksopo.zip", family: "amos"),
        .init(.path, "/private/tmp/lksopo", family: "amos"),
        .init(.path, "/private/tmp/lksopo.zip", family: "amos"),
        // Banshee
        .init(.path, "/tmp/tempAppleScript", family: "banshee"),
        .init(.path, "/private/tmp/tempAppleScript", family: "banshee"),
        // Cuckoo
        .init(.pathRegex, #"^~/\.local-[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}(/|$)"#, family: "cuckoo"),
        // MacSync
        .init(.path, "/tmp/runner", family: "macsync", executableOnly: true),
        .init(.path, "/private/tmp/runner", family: "macsync", executableOnly: true),
        .init(.path, "/tmp/runner.headers", family: "macsync"),
        .init(.path, "/private/tmp/runner.headers", family: "macsync"),
        .init(.path, "/tmp/salmonela.zip", family: "macsync"),
        .init(.path, "/private/tmp/salmonela.zip", family: "macsync"),
        .init(.path, "~/Library/Application Support/UserSyncWorker", family: "macsync"),
        .init(.path, "~/Library/Logs/UserSyncWorker.log", family: "macsync"),
        // Odyssey
        .init(.path, "/tmp/lovemrtrump", family: "odyssey"),
        .init(.path, "/private/tmp/lovemrtrump", family: "odyssey"),
        // XLoader
        .init(.path, "~/73a470tO", family: "xloader"),
        // EvilQuest
        .init(.path, "~/Library/AppQuest", family: "evilquest"),
        .init(.path, "/Library/AppQuest", family: "evilquest"),
        .init(.path, "~/Library/LaunchAgents/com.apple.abtpd.plist", family: "evilquest"),
        .init(.path, "/Library/LaunchDaemons/com.apple.abtpd.plist", family: "evilquest"),
        .init(.path, "~/Library/LaunchAgents/com.apple.questd.plist", family: "evilquest"),
        .init(.path, "/Library/LaunchDaemons/com.apple.questd.plist", family: "evilquest"),
        .init(.path, "~/.aespot", family: "evilquest"),
        .init(.path, "~/.ncspot", family: "evilquest"),
        // KeRanger
        .init(.path, "~/Library/kernel_service", family: "keranger"),
        .init(.path, "~/Library/.kernel_pid", family: "keranger"),
        .init(.path, "~/Library/.kernel_time", family: "keranger"),
        .init(.path, "~/Library/.kernel_complete", family: "keranger"),
        // LoudMiner
        .init(.path, "/Library/LaunchDaemons/buildtools.system-monitor.plist", family: "loudminer"),
        .init(.path, "/Library/LaunchDaemons/buildtools.tools-service.plist", family: "loudminer"),
        .init(.path, "/Library/LaunchDaemons/modulesys.qemuservice.plist", family: "loudminer"),
        .init(.path, "/Library/LaunchDaemons/systools.cpumonitor.plist", family: "loudminer"),
        .init(.path, "/Library/Application Support/.Qemusys", family: "loudminer"),
        .init(.path, "/usr/local/bin/.Tools-Service", family: "loudminer"),
        // OSAMiner
        .init(.path, "~/Library/LaunchAgents/com.apple.4V.plist", family: "osaminer"),
        .init(.path, "~/Library/LaunchAgents/com.apple.UV.plist", family: "osaminer"),
        .init(.path, "~/Library/LaunchAgents/com.apple.00.plist", family: "osaminer"),
        // PPMiner
        .init(.path, "~/Library/Application Support/pplauncher", family: "ppminer"),
        .init(.path, "/Library/LaunchDaemons/com.pplauncher.plist", family: "ppminer"),
        .init(.path, "/tmp/mshelper", family: "ppminer"),
        .init(.path, "/private/tmp/mshelper", family: "ppminer"),
        // FruitFly
        .init(.path, "~/.client", family: "fruitfly"),
        .init(.path, "~/Library/LaunchAgents/com.client.client.plist", family: "fruitfly"),
        // Eleanor
        .init(.path, "~/Library/.dropbox/sync", family: "eleanor"),
        .init(.path, "~/Library/.dropbox/utilities", family: "eleanor"),
        // Coldroot
        .init(.path, "/Library/LaunchDaemons/com.apple.audio.driver.plist", family: "coldroot"),
        .init(.path, "/private/var/tmp/com.apple.audio.driver.app", family: "coldroot"),
        .init(.path, "/var/tmp/com.apple.audio.driver.app", family: "coldroot"),
        // Mokes
        .init(.path, "~/Library/LaunchAgents/storeuserd.plist", family: "mokes"),
        .init(.path, "~/Library/LaunchAgents/quicklookd.plist", family: "mokes"),
        .init(.path, "~/Library/App Store/storeuserd", family: "mokes"),
        .init(.path, "~/Library/com.apple.spotlight/SpotlightHelper", family: "mokes"),
        .init(.path, "~/Library/Dock/com.apple.dock.cache", family: "mokes"),
        .init(.path, "~/Library/Skype/SkypeHelper", family: "mokes"),
        .init(.path, "~/Library/Dropbox/DropboxCache", family: "mokes"),
        .init(.path, "~/Library/Dropbox/quicklookd", family: "mokes"),
        .init(.path, "~/Library/Google/Chrome/nacld", family: "mokes"),
        .init(.path, "~/Library/Firefox/Profiles/profiled", family: "mokes"),
        // Calisto
        .init(.path, "~/.calisto", family: "calisto"),
        // Proton
        .init(.path, "/Library/LaunchAgents/com.Eltima.UpdaterAgent.plist", family: "proton"),
        .init(.path, "/Library/.rand", family: "proton"),
        .init(.path, "/tmp/Updater.app", family: "proton"),
        .init(.path, "/private/tmp/Updater.app", family: "proton"),
        // DazzleSpy
        .init(.path, "~/.local/softwareupdate", family: "dazzlespy"),
        .init(.path, "~/.local/security/keystealDaemon", family: "dazzlespy"),
        .init(.path, "~/.local/security.zip", family: "dazzlespy"),
        .init(.path, "~/Library/LaunchAgents/com.apple.softwareupdate.plist", family: "dazzlespy"),
        // Dok
        .init(.path, "~/Library/LaunchAgents/com.apple.Safari.pac.plist", family: "dok"),
        .init(.path, "~/Library/LaunchAgents/com.apple.Safari.proxy.plist", family: "dok"),
        // CloudMensis
        .init(.path, "/Library/LaunchDaemons/.com.apple.WindowServer.plist", family: "cloudmensis"),
        .init(.path, "/Library/WebServer/share/httpd/manual/WindowServer", family: "cloudmensis"),
        .init(.path, "~/Library/Preferences/com.apple.iTunesInfo29.plist", family: "cloudmensis"),
        // JokerSpy
        .init(.path, "/Users/Shared/xcc", family: "jokerspy"),
        .init(.path, "/Users/Shared/sh.py", family: "jokerspy"),
        .init(.path, "~/Public/Safari/sar.dat", family: "jokerspy"),
        // RustBucket
        .init(.path, "~/Library/LaunchAgents/com.apple.systemupdate.plist", family: "rustbucket"),
        .init(.path, "~/Library/Metadata/System Update", family: "rustbucket"),
        // WindTail
        .init(.path, "~/Library/Final_Presentation.app", family: "windtail"),
        // Geacon
        .init(.path, "~/runoob.log", family: "geacon"),
        // Silver Sparrow
        .init(.path, "~/Library/._insu", family: "silversparrow"),
        .init(.path, "/tmp/agent.sh", family: "silversparrow"),
        .init(.path, "/private/tmp/agent.sh", family: "silversparrow"),
        .init(.path, "~/Library/Application Support/agent_updater", family: "silversparrow"),
        .init(.path, "~/Library/Application Support/verx_updater", family: "silversparrow"),
        .init(.path, "~/Library/LaunchAgents/init_agent.plist", family: "silversparrow"),
        .init(.path, "~/Library/LaunchAgents/init_verx.plist", family: "silversparrow"),
        .init(.path, "~/Library/LaunchAgents/verx.plist", family: "silversparrow"),
    ]

    private static let labels: [ProtectionIndicator] = [
        .init(.launchLabel, "com.genieo.*", family: "genieo"),
        .init(.launchLabel, "com.genieoinnovation.*", family: "genieo"),
        .init(.launchLabel, "com.chrome.extension", family: "chromeloader"),
        .init(.launchLabel, "com.chrome.extensions", family: "chromeloader"),
        .init(.launchLabel, "com.chrome.extensionsPop", family: "chromeloader"),
        .init(.launchLabel, "com.safarii.extension", family: "chromeloader"),
        .init(.launchLabel, "com.extension.pop", family: "chromeloader"),
        .init(.launchLabel, "com.ist.up", family: "convuster"),
        .init(.launchLabel, "com.Mughthesec", family: "mughthesec"),
        .init(.launchLabel, "com.MapperState.system", family: "hydromac"),
        .init(.launchLabel, "com.conduit.loader.agent", family: "searchprotect"),
        .init(.launchLabel, "com.zeobit.MacKeeper*", family: "mackeeperlegacy"),
        .init(.launchLabel, "com.finder.helper", family: "amos"),
        .init(.launchLabel, "com.xdivcmp", family: "amos"),
        .init(.launchLabel, "com.apple.abtpd", family: "evilquest"),
        .init(.launchLabel, "com.apple.questd", family: "evilquest"),
        .init(.launchLabel, "buildtools.system-monitor", family: "loudminer"),
        .init(.launchLabel, "buildtools.tools-service", family: "loudminer"),
        .init(.launchLabel, "modulesys.qemuservice", family: "loudminer"),
        .init(.launchLabel, "systools.cpumonitor", family: "loudminer"),
        .init(.launchLabel, "com.pplauncher", family: "ppminer"),
        .init(.launchLabel, "com.client.client", family: "fruitfly"),
        .init(.launchLabel, "com.getdropbox.dropbox.integritycheck", family: "eleanor"),
        .init(.launchLabel, "com.getdropbox.dropbox.timegrabber", family: "eleanor"),
        .init(.launchLabel, "com.getdropbox.dropbox.usercontent", family: "eleanor"),
        .init(.launchLabel, "com.apple.audio.driver", family: "coldroot"),
        .init(.launchLabel, "com.proton.calisto", family: "calisto"),
        .init(.launchLabel, "com.Eltima.UpdaterAgent", family: "proton"),
    ]

    private static let bundles: [ProtectionIndicator] = [
        .init(.bundleID, "com.genieo.*", family: "genieo"),
        .init(.bundleID, "com.genieoinnovation.*", family: "genieo"),
        .init(.bundleName, "Genieo.app", family: "genieo"),
        .init(.bundleName, "Leperdvil*", family: "genieo"),
        .init(.bundleID, "com.Ethernet.bundle.installer", family: "shlayer"),
        .init(.bundleID, "com.FlashPlayer", family: "mughthesec"),
        .init(.bundleID, "com.techyutils.cleaner", family: "advancedmaccleaner"),
        .init(.bundleName, "Advanced Mac Cleaner.app", family: "advancedmaccleaner"),
        .init(.bundleID, "com.macmechanic.*", family: "macmechanic"),
        .init(.bundleName, "Mac Mechanic.app", family: "macmechanic"),
        .init(.bundleName, "MacMechanic.app", family: "macmechanic"),
        .init(.bundleID, "com.zeobit.MacKeeper*", family: "mackeeperlegacy"),
        .init(.bundleID, "upd.upd", family: "cuckoo"),
        .init(.bundleID, "com.alis.tre", family: "windtail"),
        .init(.bundleID, "com.apple.ScriptEditor.id.1223", family: "geacon"),
        .init(.bundleID, "com.apple.automator.makabaka", family: "geacon"),
        .init(.bundleName, "ManagementMark*", family: "bundlore"),
    ]

    private static let teams: [ProtectionIndicator] = [
        .init(.teamID, "4X5KZ42L4B", family: "shlayer"),
        .init(.teamID, "NC43XU5Z95", family: "shlayer"),
        .init(.teamID, "73KF97486K", family: "shlayer"),
        .init(.teamID, "9G2J3967H9", family: "mughthesec"),
        .init(.teamID, "GNJLS3UYZ4", family: "macsync"),
        .init(.teamID, "C46287MB25", family: "realst"),
        .init(.teamID, "54YDV8NU9C", family: "xloader"),
        .init(.teamID, "Z7276PX673", family: "keranger"),
        .init(.teamID, "5834W6MYX3", family: "silversparrow"),
        .init(.teamID, "MSZ3ZH74RK", family: "silversparrow"),
    ]

    private static let hashes: [ProtectionIndicator] = hashPairs.map { ProtectionIndicator(.sha256, $0.1, family: $0.0) }

    /// (family id, SHA-256) pairs.
    private static let hashPairs: [(String, String)] = [
        ("adload", "6587e61a8a7edb312da5798ffccf4a5ef227d3834389993b4df3ef0b173443dc"),
        ("adload", "956aae546af632ea20123bfe659d57e0d5134e39cdb5489bd6f1ba5d8bbd0472"),
        ("adload", "d94f62ec4b6ffcec35d5e639d02a52ce226629a5eb3e2a7190174ea8d3b40b5b"),
        ("advancedmaccleaner", "e7af2bd1ea722a1fc6f8012a7472c8e6583406166509135b35ef001827fd55b3"),
        ("amos", "15afe14b5db2896d35a0c4f3139db85158da120fa90613c975c88f10bbbcc420"),
        ("amos", "18610847efe2876714e77458503e487396408547abd0663e96f0b741f58d7107"),
        ("banshee", "11aa6eeca2547fcf807129787bec0d576de1a29b56945c5a8fb16ed8bf68f782"),
        ("bundlore", "5bbdf331b270973e9987e0163a319ef8c12bb3421e69018629cdd85bee77ff3d"),
        ("bundlore", "d44e579ca410fbe04a15e7f10c7c4fffbc758ebb589e8bfd93e7a455ef631490"),
        ("bundlore", "f425e6b6ac74b2b3b2c8b20b56641dfa8bcdd325b3bcabe023970855cc7f129e"),
        ("chromeloader", "46bbb3103bdc2263a0b50eb80815705f61885b3e3e132e5e5c5ff822512085ca"),
        ("chromeloader", "53ddfdb4c01ace20322647eead73ddf77e6d9613b73ca90521c2e57063be387b"),
        ("chromeloader", "81ac23cc9dba6bed6e33d172e011ead46254a29483c287f35c670d81bc9785b7"),
        ("chromeloader", "83d6ab417c9a362e6292dd8d85032b623889d9154b9d357fd8576f843fbecae9"),
        ("chromeloader", "e31607b87355b4ae3e5f96c6b48ed783e6b706fb1c2ab6a1ff25a13af615bca7"),
        ("chromeloader", "e734ec9832f8385eb737dd024eb96d53d0d3cb534a72afb4730db8e7e6162fcc"),
        ("convuster", "02a0842beaf5ee9ed4f0f693ba276b73d53717eca821d2506efcdef7711d66da"),
        ("convuster", "77bc8b0e17e1c56fba70d8707de9718cd5c10565454fdb85c862a7f3d7e82983"),
        ("convuster", "8898f499f334a3231695b8a60dfdfb289836da1de7a4e4e334df83a748c11e07"),
        ("convuster", "947ae8f075fd0d1e5be0341b922c0173f0c5cfd771314ebe220207f3ed53466a"),
        ("convuster", "d511e44ee6ae06228170aef1bef567e059596d259e205295b99e85de8c966354"),
        ("convuster", "f9615ce5f1038afd4e19d3e35643c98af1a2ee53d9bf45958c84e5a7c4529e62"),
        ("coldroot", "c20980d3971923a0795662420063528a43dd533d07565eb4639ee8c0ccb77fdf"),
        ("dok", "4131d4737fe8dfe66d407bfd0a0df18a4a77b89347471cc012da8efc93c661a5"),
        ("dok", "7819ae7d72fa045baa77e9c8e063a69df439146b27f9c3bb10aef52dcc77c145"),
        ("evilquest", "06974e23a3bf303f75c754156f36f57b960f0df79a38407dfdef9a1c55bf8bff"),
        ("evilquest", "c5a77de3f55cacc3dc412e2325637ca7a2c36b1f4d75324be8833465fd1383d3"),
        ("evilquest", "d18daea336889f5d7c8bd16a4d6358ddb315766fa21751db7d41f0839081aee2"),
        ("fruitfly", "ce07d208a2d89b4e0134f5282d9df580960d5c81412965a6d1a0786b27e7f044"),
        ("hydromac", "7f7c7e1b181142592b2f8b7c823a969fb79160c9a5920abd718364eae98d1496"),
        ("hydromac", "919d049d5490adaaed70169ddd0537bfa2018a572e93b19801cf245f7fd28408"),
        ("jokerspy", "8ca86f78f0c73a46f31be366538423ea0ec58089f3880e041543d08ce11fa626"),
        ("jokerspy", "aa951c053baf011d08f3a60a10c1d09bbac32f332413db5b38b8737558a08dc1"),
        ("jokerspy", "d895075057e491b34b0f8c0392b44e43ade425d19eaaacea6ef8c5c9bd3487d8"),
        ("keranger", "31b6adb633cff2a0f34cefd2a218097f3a9a8176c9363cc70fe41fe02af810b9"),
        ("keranger", "6061a554f5997a43c91f49f8aaf40c80a3f547fc6187bee57cd5573641fcf153"),
        ("keranger", "d1ac55a4e610380f0ab239fcc1c5f5a42722e8ee1554cba8074bbae4a5f6dbe1"),
        ("keranger", "ddc3dbee2a8ea9d8ed93f0843400653a89350612f2914868485476a847c6484a"),
        ("loudminer", "390e9a6d4a6f6c9a553aaa6543058931d14cfdc2620732bbfac73fd90eaf09ee"),
        ("loudminer", "3dca4365b5ea280b966541d53eaee665e2b915a668dd34a1ae208595bc83dbda"),
        ("loudminer", "5c314b493d6ad5df84450e190b94a9ff67e79ca125a322a65b465ee171b6e638"),
        ("loudminer", "7e36222a3e3898d9473f017c33c803ad70878fa79f391a65d87ae061cb89fba7"),
        ("macsync", "03014c8f49eca127a1ff7308be341d79aee809c51f388b906d6fe9f4bef15595"),
        ("macsync", "a42eece43aad2e2a2f98d41b1b48025c252452318a864d32d0f9156adaabe65b"),
        ("macsync", "cfd338c16249e9bcae69b3c3a334e6deafd5a22a84935a76b390a9d02ed2d032"),
        ("odyssey", "4cfeb6ebf19743f3d0cd157dfb9701132fbe6b0b31859ad85c5bc936af414b70"),
        ("odyssey", "74d7f64fa3185f775a9816003e5c33487dcc68f92e4fd81310144922271f103a"),
        ("odyssey", "a0bdf6f602af5efea0fd96e659ac553e0e23362d2da6aecb13770256a254ef55"),
        ("odyssey", "ef5f28fd1928fc3872c81c0fa0582717654d7a60dfd04babfcc5694251eed7f9"),
        ("osaminer", "35a83f2467d914d113f5430cdbede54ac96a212ed2b893ee9908e6b05c12b6f6"),
        ("osaminer", "97febb1aa15ad7b1c321f056f7164526eb698297e0fea0c23bd127498ba3e9bb"),
        ("osaminer", "df550039acad9e637c7c3ec2a629abf8b3f35faca18e58d447f490cf23f114e8"),
        ("ppminer", "8f1938d082393713539abb9dfa8bfde8e1a09721f622e6e597d4560219ffca0d"),
        ("ppminer", "a00f6fbb2e00d35f938534e1c20ba2e02311536bcf60be2165037d68cba141b2"),
        ("mokes", "664e0a048f61a76145b55d1f1a5714606953d69edccec5228017eb546049dc8c"),
        ("mami", "5586be30d505216bdc912605481f9c8c7bfd52748f66c5e212160f6b31fd8571"),
        ("poseidon", "c1693ee747e31541919f84dfa89e36ca5b74074044b181656d95d7f40af34a05"),
        ("xcsset", "56670f51f94080f1ae45f2a433767f210f290835bf582e1a2e1876f1028832de"),
        ("xcsset", "d338dc9a75a14753f57399815b5d996a1c5e65aa4eb203222d8c85fb3d74b02f"),
        ("xloader", "46adfe4740a126455c1a022e835de74f7e3cf59246ca66aa4e878bf52e11645d"),
        ("xloader", "97d6b194da410db82d9974aec984cff8ac0a6ad59ec72b79d4b2a4672b5aa8aa"),
        ("zshlayer", "269d5f15da3bc3522ca53a3399dbaf4848f86de35d78c636a78336d46c23951c"),
        ("zshlayer", "3e20c0b2979a368c7d38cf305f1f60693375165bb76150ad80dbd34e7e0550ed"),
        ("zshlayer", "93ff20ff59d4e82e9c0e3b08037c48886dc54b8ed37c19894e0a65c1af8612f6"),
        ("zshlayer", "c561d62c786c757a660c47d133b6d23e030a40c4aa08aebe44b8c4a7711da580"),
        ("zshlayer", "e3292268c1d0830e76c3e80b4ea57921b9171027e07f064ef3b867b6d0450191"),
        ("zshlayer", "f6cb7f9593d85f0cd1e81d5b9f520b74d9bf5e829206cefe05b956c0f7638c28"),
    ]
}
