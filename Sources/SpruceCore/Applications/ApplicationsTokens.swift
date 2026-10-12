import Foundation

/// String helpers shared by the leftover matcher, the orphan detector and installer matching.
public enum ApplicationsTokens {

    /// Words too generic to identify an app by folder name alone.
    public static let commonWords: Set<String> = [
        "app", "apps", "application", "applications", "agent", "assistant", "audio", "backup", "backups",
        "browser", "cache", "caches", "calendar", "chat", "client", "common", "config", "data", "default",
        "desktop", "daemon", "documents", "dock", "downloads", "editor", "extension", "extensions", "files",
        "finder", "fonts", "frameworks", "free", "helper", "helpers", "installer", "launcher", "library",
        "lite", "local", "logs", "mac", "macos", "mail", "manager", "media", "messages", "monitor", "movies",
        "music", "network", "notes", "osx", "photos", "pictures", "player", "plugins", "plug-ins", "plus",
        "preferences", "pro", "reader", "safari", "security", "server", "service", "services", "settings",
        "shared", "siri", "spotlight", "store", "studio", "support", "sync", "system", "temp", "terminal",
        "tools", "uninstaller", "update", "updater", "user", "users", "utilities", "video", "viewer", "web",
        "widget", "widgets", "storage", "cloud", "share", "notification", "notifications", "maps",
        "news", "stocks", "books", "home", "clock", "weather", "reminders", "contacts", "preview", "tv",
        "podcasts", "freeform", "journal", "passwords", "keychain", "crash", "crashes", "reports", "temporary",
        "electron", "sparkle", "squirrel", "chromium", "webkit", "python", "java", "node", "ruby", "go",
    ]

    /// Release-channel words dropped from the end of an app name ("Firefox Nightly" → "Firefox").
    /// "Edge" is deliberately absent ("Microsoft Edge").
    static let channelSuffixes: Set<String> = [
        "beta", "nightly", "canary", "dev", "developer", "preview", "insiders", "insider", "alpha", "rc",
        "stable", "release", "lts", "edition", "technology",
    ]

    /// File suffixes stripped before comparing a Library entry with bundle ids.
    public static let dataSuffixes: [String] = [
        ".plist", ".savedState", ".binarycookies", ".sfl4", ".sfl3", ".sfl2", ".sfl", ".log", ".lock",
    ]

    /// Extensions stripped before comparing a Library entry with app names.
    public static let nameSuffixes: Set<String> = [
        "plist", "savedstate", "binarycookies", "log", "txt", "qlgenerator", "mdimporter", "prefpane",
        "plugin", "webplugin", "saver", "qtz", "workflow", "service", "bundle", "component", "app",
        "sfl2", "sfl3", "sfl4", "ips", "crash", "diag", "json",
    ]

    /// Lowercase letters and digits only ("Visual Studio Code" → "visualstudiocode").
    public static func normalized(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
            .map(Character.init))
    }

    /// Spelling variants of a name as they appear in folder names: as is, without spaces,
    /// with underscores and with dashes. Lowercased.
    public static func spellings(_ name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        let forms = [lower, lower.replacingOccurrences(of: " ", with: ""),
                     lower.replacingOccurrences(of: " ", with: "_"), lower.replacingOccurrences(of: " ", with: "-")]
        var seen = Set<String>()
        return forms.filter { seen.insert($0).inserted }
    }

    /// The name without a trailing release channel or version number
    /// ("Bartender 5" → "Bartender", "Firefox Nightly" → "Firefox"). nil when unchanged.
    public static func strippedName(_ name: String) -> String? {
        var words = name.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" }).map(String.init)
        var changed = false
        while words.count > 1, let last = words.last,
              channelSuffixes.contains(last.lowercased()) || last.allSatisfy({ $0.isNumber || $0 == "." }) {
            words.removeLast()
            changed = true
        }
        guard changed else { return nil }
        let result = words.joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    /// True when `name` is specific enough to identify an app by folder name: at least four
    /// letters/digits and not a common word.
    public static func isDistinctiveName(_ name: String) -> Bool {
        let n = normalized(name)
        guard n.count >= 4 else { return false }
        return !commonWords.contains(n) && !commonWords.contains(name.lowercased())
    }

    /// Name forms (lowercased) used to match folders against an app, longest first.
    /// Only distinctive names are included.
    public static func nameForms(for identity: ApplicationsAppIdentity) -> [String] {
        var bases: [String] = []
        for name in identity.names {
            let clean = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
            bases.append(clean)
            if let stripped = strippedName(clean) { bases.append(stripped) }
        }
        var seen = Set<String>()
        var forms: [String] = []
        for base in bases where isDistinctiveName(base) {
            for spelling in spellings(base) where seen.insert(spelling).inserted {
                forms.append(spelling)
            }
        }
        return forms.sorted { $0.count > $1.count }
    }

    /// Name forms valid only inside a vendor folder: the app name without the vendor prefix
    /// ("Google Chrome" in `Google/` → "chrome") and the bundle id's last component.
    public static func vendorChildForms(for identity: ApplicationsAppIdentity, vendorFolder: String) -> [String] {
        var bases: [String] = []
        let vendor = vendorFolder.lowercased()
        for name in identity.names {
            let clean = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
            if clean.lowercased().hasPrefix(vendor + " ") {
                bases.append(String(clean.dropFirst(vendor.count + 1)))
            }
            bases.append(clean)
        }
        if let last = identity.bundleID.split(separator: ".").last { bases.append(String(last)) }
        var seen = Set<String>()
        var forms: [String] = []
        for base in bases where normalized(base).count >= 3 && !commonWords.contains(base.lowercased()) {
            for spelling in spellings(base) where seen.insert(spelling).inserted {
                forms.append(spelling)
            }
        }
        return forms
    }

    /// The entry name with one known data suffix removed, if present (case-insensitive).
    public static func strippingDataSuffix(_ name: String) -> String {
        let lower = name.lowercased()
        for suffix in dataSuffixes where lower.hasSuffix(suffix.lowercased()) && name.count > suffix.count {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// The entry name without its extension when the extension is a known file/plug-in type.
    public static func nameStem(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, nameSuffixes.contains(ext) else { return name }
        return (name as NSString).deletingPathExtension
    }

    // MARK: Bundle ids

    /// `^[A-Za-z0-9][-A-Za-z0-9_]*(\.[A-Za-z0-9][-A-Za-z0-9_]*)+$` with at least `minimumComponents` parts.
    public static func isReverseDNS(_ s: String, minimumComponents: Int = 3) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= minimumComponents else { return false }
        for part in parts {
            guard let first = part.unicodeScalars.first, first.isASCII,
                  CharacterSet.alphanumerics.contains(first) else { return false }
            for scalar in part.unicodeScalars {
                guard scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" else { return false }
            }
        }
        // The first component must look like a domain suffix ("com", "org", "io"…).
        let tld = parts[0].lowercased()
        return tld.count >= 2 && tld.count <= 6 && tld.allSatisfy({ $0.isLetter })
    }

    /// How an entry relates to a bundle id (both compared case-insensitively).
    public enum BundleMatch: Equatable, Sendable {
        case none
        /// The entry *is* the id.
        case exact
        /// The entry starts with `id.` (helpers, ByHost files, `id.ShipIt`).
        case prefix
        /// The entry ends with `.id` or contains `.id.` (team-prefixed group containers).
        case embedded
    }

    /// Dot-boundary match of `entry` against `bundleID`.
    ///
    /// Ids with fewer than three components only match exactly, so a vendor prefix such as
    /// `com.vendor` never captures the vendor's other products.
    public static func bundleMatch(_ entry: String, bundleID: String, allowEmbedded: Bool) -> BundleMatch {
        let e = entry.lowercased()
        let id = bundleID.lowercased()
        guard !id.isEmpty else { return .none }
        if e == id { return .exact }
        let components = id.split(separator: ".").count
        guard components >= 3 else { return .none }
        if e.hasPrefix(id + ".") { return .prefix }
        if allowEmbedded && (e.hasSuffix("." + id) || e.contains("." + id + ".")) { return .embedded }
        return .none
    }

    /// Owner key of a Library entry for orphan detection: data suffixes, ByHost hardware ids,
    /// `TEAMID.` and `group.` prefixes removed. nil when the name is not reverse-DNS.
    public static func ownerKey(fromEntryName name: String) -> (key: String, teamID: String?)? {
        var s = strippingDataSuffix(name)
        // ByHost: com.foo.bar.<UUID> or com.foo.bar.<12 hex>
        let parts = s.split(separator: ".").map(String.init)
        if parts.count > 3, let last = parts.last, isHardwareID(last) {
            s = parts.dropLast().joined(separator: ".")
        }
        var teamID: String?
        if let dot = s.firstIndex(of: "."), isTeamID(String(s[..<dot])) {
            teamID = String(s[..<dot])
            s = String(s[s.index(after: dot)...])
        }
        if s.lowercased().hasPrefix("group.") {
            s = String(s.dropFirst("group.".count))
        }
        guard isReverseDNS(s) else { return nil }
        return (s, teamID)
    }

    /// Apple Developer team ids are 10 upper-case letters/digits.
    public static func isTeamID(_ s: String) -> Bool {
        s.count == 10 && s.unicodeScalars.allSatisfy { ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) }
    }

    /// A UUID (with or without dashes) or a 12-hex-digit hardware address.
    public static func isHardwareID(_ s: String) -> Bool {
        let hex = s.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32 || hex.count == 12 else { return false }
        return hex.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    /// "com.knollsoft.Rectangle" → "Rectangle"; skips generic trailing words ("helper", "mac").
    public static func displayName(forOwnerKey key: String) -> String {
        let generic: Set<String> = ["helper", "agent", "app", "mac", "macos", "osx", "desktop", "client", "launcher",
                                    "daemon", "service", "xpc", "plist", "shared", "group", "extension"]
        let parts = key.split(separator: ".").map(String.init)
        var candidate = parts.last ?? key
        var index = parts.count - 1
        while index > 1, generic.contains(candidate.lowercased()) {
            index -= 1
            candidate = parts[index]
        }
        guard let first = candidate.first else { return key }
        return String(first).uppercased() + candidate.dropFirst()
    }
}

// MARK: - Property lists and launchd jobs

/// Foundation-only property list reading (works on Linux for tests).
public enum ApplicationsPlist {
    public static func dictionary(atPath path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return dictionary(from: data)
    }

    public static func dictionary(from data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}

/// The parts of a launchd job definition that tell who owns it.
public struct ApplicationsLaunchJob: Sendable, Equatable {
    public var label: String?
    /// `Program` or `ProgramArguments[0]`.
    public var program: String?
    /// `BundleProgram` (relative to the owning app, used by `SMAppService` agents).
    public var bundleProgram: String?
    public var associatedBundleIDs: [String]

    public init(label: String? = nil, program: String? = nil, bundleProgram: String? = nil, associatedBundleIDs: [String] = []) {
        self.label = label
        self.program = program
        self.bundleProgram = bundleProgram
        self.associatedBundleIDs = associatedBundleIDs
    }

    public init?(plist: [String: Any]) {
        label = plist["Label"] as? String
        if let program = plist["Program"] as? String, !program.isEmpty {
            self.program = program
        } else if let args = plist["ProgramArguments"] as? [String], let first = args.first, !first.isEmpty {
            program = first
        } else {
            program = nil
        }
        bundleProgram = plist["BundleProgram"] as? String
        if let ids = plist["AssociatedBundleIdentifiers"] as? [String] {
            associatedBundleIDs = ids
        } else if let id = plist["AssociatedBundleIdentifiers"] as? String {
            associatedBundleIDs = [id]
        } else {
            associatedBundleIDs = []
        }
        if label == nil && program == nil && bundleProgram == nil { return nil }
    }

    public static func read(atPath path: String) -> ApplicationsLaunchJob? {
        ApplicationsPlist.dictionary(atPath: path).flatMap(ApplicationsLaunchJob.init(plist:))
    }

    /// True when the job runs code from inside `bundlePath` or names the app's bundle id
    /// in `AssociatedBundleIdentifiers`.
    public func isOwned(byBundleAt bundlePath: String, bundleID: String) -> Bool {
        if associatedBundleIDs.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) { return true }
        guard let program, program.hasPrefix("/") else { return false }
        let standardized = (program as NSString).standardizingPath
        guard !standardized.split(separator: "/").contains("..") else { return false }
        let bundle = (bundlePath as NSString).standardizingPath
        return standardized.lowercased().hasPrefix(bundle.lowercased() + "/")
    }

    /// True when the job points at an absolute program path that no longer exists.
    public func isBroken(fileExists: (String) -> Bool) -> Bool {
        guard let program, program.hasPrefix("/") else { return false }
        return !fileExists(program)
    }
}
