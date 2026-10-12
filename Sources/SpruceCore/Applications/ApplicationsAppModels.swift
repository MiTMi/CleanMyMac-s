import Foundation

// MARK: - Architecture

/// Which processors an app's main executable runs on natively.
public enum ApplicationsArchitecture: String, Codable, Sendable, CaseIterable {
    /// arm64 only.
    case appleSilicon
    /// arm64 and x86_64 slices.
    case universal
    /// x86_64 only — runs on Apple silicon through Rosetta.
    case intel
    /// Only 32-bit (i386/PowerPC) code — cannot launch on current macOS.
    case legacy32
    case unknown

    public var title: String {
        switch self {
        case .appleSilicon: return "Apple silicon"
        case .universal: return "Universal"
        case .intel: return "Intel"
        case .legacy32: return "32-bit"
        case .unknown: return "Unknown"
        }
    }

    /// Derives the architecture class from the CPU slices found in a Mach-O header.
    public static func from(_ cpus: [ApplicationsMachO.CPU]) -> ApplicationsArchitecture {
        let set = Set(cpus)
        let arm = set.contains(.arm64) || set.contains(.arm64e)
        let intel64 = set.contains(.x86_64)
        if arm && intel64 { return .universal }
        if arm { return .appleSilicon }
        if intel64 { return .intel }
        if set.contains(.i386) || set.contains(.ppc) || set.contains(.ppc64) { return .legacy32 }
        return .unknown
    }
}

// MARK: - Source

/// Where an installed app came from.
public enum ApplicationsAppSource: String, Codable, Sendable, CaseIterable {
    case appStore
    case setapp
    case homebrew
    case steam
    case other

    public var title: String {
        switch self {
        case .appStore: return "App Store"
        case .setapp: return "Setapp"
        case .homebrew: return "Homebrew"
        case .steam: return "Steam"
        case .other: return "Other"
        }
    }
}

// MARK: - Identity (input to the leftover matcher)

/// Everything that identifies an app's files on disk.
public struct ApplicationsAppIdentity: Sendable, Hashable, Codable {
    public var bundleID: String
    /// Path of the `.app` bundle.
    public var bundlePath: String
    /// File name without ".app", `CFBundleName`, `CFBundleDisplayName` (duplicates allowed).
    public var names: [String]
    public var executableName: String?
    public var teamID: String?
    /// Vendor token, e.g. "google" for `com.google.Chrome`, or the signing vendor's name.
    public var vendorToken: String?
    /// `com.apple.security.application-groups` entitlement values.
    public var appGroups: [String]
    /// Bundle ids of helpers, XPC services, login items and app extensions inside the bundle.
    public var embeddedBundleIDs: [String]

    public init(bundleID: String, bundlePath: String, names: [String], executableName: String? = nil,
                teamID: String? = nil, vendorToken: String? = nil, appGroups: [String] = [],
                embeddedBundleIDs: [String] = []) {
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.names = names
        self.executableName = executableName
        self.teamID = teamID
        self.vendorToken = vendorToken
        self.appGroups = appGroups
        self.embeddedBundleIDs = embeddedBundleIDs
    }

    /// All bundle ids this app owns (main + embedded), deduplicated, lowercased.
    public var allBundleIDs: [String] {
        var seen = Set<String>()
        return ([bundleID] + embeddedBundleIDs)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

// MARK: - Installed app

/// One installed application, as shown in the Uninstaller.
public struct ApplicationsAppInfo: Identifiable, Hashable, Sendable, Codable {
    public var id: String { path }
    /// Path of the `.app` bundle.
    public var path: String
    public var name: String
    public var bundleID: String
    /// `CFBundleShortVersionString` (falls back to the build).
    public var version: String
    /// `CFBundleVersion`.
    public var build: String
    public var executableName: String?
    /// Human vendor name ("Google", "Apple", "Other").
    public var vendor: String
    public var teamID: String?
    public var architecture: ApplicationsArchitecture
    public var source: ApplicationsAppSource
    /// Part of macOS (under /System or Apple's cryptex) — shown, never removable.
    public var isSystem: Bool
    /// Allocated bytes of the bundle.
    public var size: Int64
    public var lastUsed: Date?
    public var dateAdded: Date?
    public var isRunning: Bool
    /// `SUFeedURL` from Info.plist, when the app uses Sparkle.
    public var sparkleFeedURL: String?
    /// Homebrew cask token, when installed through Homebrew.
    public var caskToken: String?
    /// Vendors that ship their own uninstaller (security suites, MDM): uninstall from
    /// Spruce is still possible but discouraged.
    public var prefersVendorUninstaller: Bool
    public var appGroups: [String]
    public var embeddedBundleIDs: [String]
    public var names: [String]

    public init(path: String, name: String, bundleID: String, version: String = "", build: String = "",
                executableName: String? = nil, vendor: String = "Other", teamID: String? = nil,
                architecture: ApplicationsArchitecture = .unknown, source: ApplicationsAppSource = .other,
                isSystem: Bool = false, size: Int64 = 0, lastUsed: Date? = nil, dateAdded: Date? = nil,
                isRunning: Bool = false, sparkleFeedURL: String? = nil, caskToken: String? = nil,
                prefersVendorUninstaller: Bool = false, appGroups: [String] = [],
                embeddedBundleIDs: [String] = [], names: [String] = []) {
        self.path = path
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.executableName = executableName
        self.vendor = vendor
        self.teamID = teamID
        self.architecture = architecture
        self.source = source
        self.isSystem = isSystem
        self.size = size
        self.lastUsed = lastUsed
        self.dateAdded = dateAdded
        self.isRunning = isRunning
        self.sparkleFeedURL = sparkleFeedURL
        self.caskToken = caskToken
        self.prefersVendorUninstaller = prefersVendorUninstaller
        self.appGroups = appGroups
        self.embeddedBundleIDs = embeddedBundleIDs
        self.names = names
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var canUninstall: Bool { !isSystem }
    /// Reset (remove data, keep the app) is offered for apps Spruce may uninstall.
    public var canReset: Bool { !isSystem }
    public var isIntelOnly: Bool { architecture == .intel }

    /// "1.2.3" or "1.2.3 (456)" when the build differs.
    public var versionLabel: String {
        if version.isEmpty { return build }
        if build.isEmpty || build == version { return version }
        return "\(version) (\(build))"
    }

    public var identity: ApplicationsAppIdentity {
        ApplicationsAppIdentity(
            bundleID: bundleID,
            bundlePath: path,
            names: ([name] + names),
            executableName: executableName,
            teamID: teamID,
            vendorToken: ApplicationsVendorName.token(bundleID: bundleID),
            appGroups: appGroups,
            embeddedBundleIDs: embeddedBundleIDs
        )
    }
}

// MARK: - Unused rule

/// "Unused" = not opened for `SpruceSettings.unusedAppDays` days.
public enum ApplicationsUnusedRule {
    /// True when the app was last opened more than `days` ago, or was never opened and
    /// was added more than `days` ago. Unknown dates never count as unused.
    public static func isUnused(lastUsed: Date?, dateAdded: Date?, now: Date = Date(), days: Int) -> Bool {
        guard days > 0 else { return false }
        let limit = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        if let lastUsed { return lastUsed < limit }
        if let dateAdded { return dateAdded < limit }
        return false
    }

    public static func isUnused(_ app: ApplicationsAppInfo, now: Date = Date(), days: Int) -> Bool {
        !app.isSystem && !app.isRunning && isUnused(lastUsed: app.lastUsed, dateAdded: app.dateAdded, now: now, days: days)
    }

    /// "Opened 3 months ago", "Never opened", "Last opened: unknown".
    public static func lastUsedLabel(_ app: ApplicationsAppInfo, now: Date = Date()) -> String {
        if app.isRunning { return "Open now" }
        if let lastUsed = app.lastUsed { return "Opened " + DurationFormat.relative(lastUsed, now: now) }
        if app.dateAdded != nil { return "Never opened" }
        return "Last opened: unknown"
    }
}

// MARK: - Vendor names

/// Derives a short, human vendor name for grouping apps.
public enum ApplicationsVendorName {
    /// Pretty names for common vendor tokens.
    static let known: [String: String] = [
        "apple": "Apple", "google": "Google", "microsoft": "Microsoft", "adobe": "Adobe",
        "jetbrains": "JetBrains", "mozilla": "Mozilla", "macpaw": "MacPaw", "setapp": "Setapp",
        "omnigroup": "The Omni Group", "panic": "Panic", "agilebits": "AgileBits", "electron": "Electron",
        "github": "GitHub", "docker": "Docker", "spotify": "Spotify", "zoom": "Zoom", "zoom.us": "Zoom",
        "slack": "Slack", "tinyspeck": "Slack", "figma": "Figma", "brave": "Brave", "operasoftware": "Opera",
        "vivaldi": "Vivaldi", "valvesoftware": "Valve", "readdle": "Readdle", "flexibits": "Flexibits",
        "objective-see": "Objective-See", "obdev": "Objective Development", "rogueamoeba": "Rogue Amoeba",
        "sublimetext": "Sublime HQ", "barebones": "Bare Bones", "parallels": "Parallels", "vmware": "VMware",
        "amazon": "Amazon", "dropbox": "Dropbox", "getdropbox": "Dropbox", "whatsapp": "WhatsApp",
        "telegram": "Telegram", "tdesktop": "Telegram", "facebook": "Meta", "openai": "OpenAI",
        "anthropic": "Anthropic", "notion": "Notion", "linear": "Linear", "raycast": "Raycast",
        "pixelmatorteam": "Pixelmator", "serif": "Serif", "affinity": "Serif", "videolan": "VideoLAN",
        "postmanlabs": "Postman", "tableplus": "TablePlus", "jamf": "Jamf", "crowdstrike": "CrowdStrike",
    ]

    /// Reverse-DNS prefixes that are not vendor names.
    static let genericTLDs: Set<String> = [
        "com", "org", "net", "io", "de", "co", "app", "dev", "me", "uk", "fr", "jp", "cn", "ch", "nl",
        "se", "eu", "us", "ca", "it", "tv", "info", "biz", "cc", "pro", "xyz", "ai", "sh", "so", "is",
        "at", "be", "dk", "fi", "no", "pl", "es", "br", "au", "nz", "in", "kr", "tw", "hk", "sg", "cz",
        "ru", "ua", "by", "il", "ro", "hu", "pt", "gr", "tr", "mx", "ar", "cl", "za", "ie", "lt", "lv",
        "ee", "sk", "si", "hr", "rs", "bg", "md", "ge", "am", "kz", "vn", "th", "my", "id", "ph", "ly",
        "im", "to", "fm", "gg", "ws", "edu", "gov", "mil", "int", "name", "mobi", "tech", "studio", "page",
    ]

    /// Vendor token from a bundle id: the second component of `tld.vendor.product`.
    public static func token(bundleID: String) -> String? {
        let parts = bundleID.lowercased().split(separator: ".").map(String.init)
        guard parts.count >= 3, genericTLDs.contains(parts[0]) else { return nil }
        let candidate = parts[1]
        guard candidate.count >= 2 else { return nil }
        return candidate
    }

    /// Vendor display name from the leaf signing certificate's summary, falling back to the bundle id.
    ///
    /// * "Developer ID Application: Google LLC (EQHXZ8M8AV)" → "Google"
    /// * `com.apple.*` or an Apple-signed system app → "Apple"
    /// * `org.mozilla.firefox` → "Mozilla"
    public static func derive(certificateSummary: String?, bundleID: String) -> String {
        if bundleID.lowercased().hasPrefix("com.apple.") { return "Apple" }
        if let summary = certificateSummary, let name = fromCertificate(summary) {
            return name
        }
        if let token = token(bundleID: bundleID) {
            if let pretty = known[token] { return pretty }
            return token.prefix(1).uppercased() + token.dropFirst()
        }
        return "Other"
    }

    /// Parses "Developer ID Application: Name (TEAMID)" into a cleaned company name.
    public static func fromCertificate(_ summary: String) -> String? {
        let prefixes = ["Developer ID Application: ", "Apple Development: ", "Apple Distribution: ",
                        "3rd Party Mac Developer Application: ", "Mac Developer: "]
        guard let prefix = prefixes.first(where: { summary.hasPrefix($0) }) else { return nil }
        var name = String(summary.dropFirst(prefix.count))
        if let open = name.lastIndex(of: "("), name.hasSuffix(")") {
            name = String(name[..<open])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        let suffixes = [", Inc.", " Inc.", ", Inc", " Inc", ", LLC", " LLC", " L.L.C.", " Ltd.", " Ltd", " Limited",
                        " GmbH", " Corporation", " Corp.", " Corp", " S.A.", " SAS", " SA", " AG", " B.V.", " BV",
                        " Pty", " Co.", " s.r.o.", " Sp. z o.o.", " Oy", " AB", " ApS", " K.K.", " OÜ", " LTD"]
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes where name.count > suffix.count && name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
                changed = true
            }
        }
        if let pretty = known[name.lowercased()] { return pretty }
        return name.isEmpty ? nil : name
    }
}

// MARK: - Uninstaller list facets

/// Filter rows of the Uninstaller's facet column.
public enum ApplicationsAppFacet: Hashable, Sendable {
    case all
    case unused
    case selected
    case appStore
    case homebrew
    case setapp
    case steam
    case otherSource
    case intelOnly
    case system
    case vendor(String)

    public var title: String {
        switch self {
        case .all: return "All Applications"
        case .unused: return "Unused"
        case .selected: return "Selected"
        case .appStore: return "App Store"
        case .homebrew: return "Homebrew"
        case .setapp: return "Setapp"
        case .steam: return "Steam"
        case .otherSource: return "Other"
        case .intelOnly: return "Intel only"
        case .system: return "macOS"
        case .vendor(let name): return name
        }
    }

    public var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .unused: return "moon.zzz"
        case .selected: return "checkmark.circle"
        case .appStore: return "bag"
        case .homebrew: return "mug"
        case .setapp: return "square.stack"
        case .steam: return "gamecontroller"
        case .otherSource: return "shippingbox"
        case .intelOnly: return "cpu"
        case .system: return "apple.logo"
        case .vendor: return "building.2"
        }
    }
}

public enum ApplicationsAppSort: String, CaseIterable, Sendable {
    case name = "Name"
    case size = "Size"
    case lastUsed = "Last Opened"
}

/// Pure filtering and grouping for the Uninstaller list.
public enum ApplicationsAppFilter {
    /// Apps shown for a facet. System apps only appear under `.system` (and `.selected` never holds them).
    public static func apps(_ apps: [ApplicationsAppInfo], facet: ApplicationsAppFacet, unusedDays: Int,
                            selected: Set<String> = [], now: Date = Date()) -> [ApplicationsAppInfo] {
        apps.filter { matches($0, facet: facet, unusedDays: unusedDays, selected: selected, now: now) }
    }

    public static func matches(_ app: ApplicationsAppInfo, facet: ApplicationsAppFacet, unusedDays: Int,
                               selected: Set<String>, now: Date = Date()) -> Bool {
        if facet == .system { return app.isSystem }
        if app.isSystem { return false }
        switch facet {
        case .all: return true
        case .unused: return ApplicationsUnusedRule.isUnused(app, now: now, days: unusedDays)
        case .selected: return selected.contains(app.id)
        case .appStore: return app.source == .appStore
        case .homebrew: return app.source == .homebrew
        case .setapp: return app.source == .setapp
        case .steam: return app.source == .steam
        case .otherSource: return app.source == .other
        case .intelOnly: return app.isIntelOnly
        case .system: return app.isSystem
        case .vendor(let name): return app.vendor == name
        }
    }

    /// Vendors that own at least `minimumApps` removable apps, by count then name.
    /// Apps of other vendors are reachable through "Other" (source) or All.
    public static func vendors(_ apps: [ApplicationsAppInfo], minimumApps: Int = 2) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for app in apps where !app.isSystem && app.vendor != "Other" {
            counts[app.vendor, default: 0] += 1
        }
        return counts.filter { $0.value >= minimumApps }
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Case- and diacritic-insensitive search over name, bundle id and vendor.
    public static func search(_ apps: [ApplicationsAppInfo], query: String) -> [ApplicationsAppInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { app in
            [app.name, app.bundleID, app.vendor].contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    public static func sorted(_ apps: [ApplicationsAppInfo], by sort: ApplicationsAppSort, ascending: Bool = true) -> [ApplicationsAppInfo] {
        let base: [ApplicationsAppInfo]
        switch sort {
        case .name:
            base = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            base = apps.sorted { $0.size != $1.size ? $0.size > $1.size : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed:
            // Least recently used first: never-opened apps lead.
            base = apps.sorted { lhs, rhs in
                let l = lhs.lastUsed ?? .distantPast
                let r = rhs.lastUsed ?? .distantPast
                return l != r ? l < r : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        return ascending ? base : base.reversed()
    }
}
