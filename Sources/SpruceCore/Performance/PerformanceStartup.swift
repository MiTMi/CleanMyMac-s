import Foundation

// MARK: - launchd property lists

/// Where a launchd property list lives, which decides how it is managed.
public enum PerformanceLaunchDomain: String, Codable, Sendable, CaseIterable, Hashable {
    /// `~/Library/LaunchAgents` — runs in your session, managed without a password.
    case userAgent
    /// `/Library/LaunchAgents` — runs in every user's session.
    case globalAgent
    /// `/Library/LaunchDaemons` — runs as root for the whole Mac; changes need a password.
    case systemDaemon

    public func folder(home: String) -> String {
        switch self {
        case .userAgent: return (home as NSString).appendingPathComponent("Library/LaunchAgents")
        case .globalAgent: return "/Library/LaunchAgents"
        case .systemDaemon: return "/Library/LaunchDaemons"
        }
    }
}

/// A parsed launch agent/daemon property list.
public struct PerformanceLaunchPlist: Sendable, Hashable {
    public var path: String
    /// False when the file isn't a property list with a dictionary at its root.
    public var isValid: Bool
    public var label: String?
    /// `Program`, with a leading `~` expanded.
    public var program: String?
    public var programArguments: [String]
    /// `BundleProgram`: a path relative to the owning app bundle (SMAppService-style plists).
    public var bundleProgram: String?
    public var runAtLoad: Bool
    /// True when `KeepAlive` is `true` or a conditions dictionary.
    public var keepAlive: Bool
    /// The plist's own `Disabled` key (launchd's override database takes precedence).
    public var disabledKey: Bool
    public var associatedBundleIdentifiers: [String]
    public var startInterval: Int?
    public var hasCalendarInterval: Bool

    public init(path: String, isValid: Bool, label: String? = nil, program: String? = nil, programArguments: [String] = [],
                bundleProgram: String? = nil, runAtLoad: Bool = false, keepAlive: Bool = false, disabledKey: Bool = false,
                associatedBundleIdentifiers: [String] = [], startInterval: Int? = nil, hasCalendarInterval: Bool = false) {
        self.path = path
        self.isValid = isValid
        self.label = label
        self.program = program
        self.programArguments = programArguments
        self.bundleProgram = bundleProgram
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.disabledKey = disabledKey
        self.associatedBundleIdentifiers = associatedBundleIdentifiers
        self.startInterval = startInterval
        self.hasCalendarInterval = hasCalendarInterval
    }

    /// The program launchd starts: `Program`, else the first `ProgramArguments` entry.
    public var executable: String? {
        if let program, !program.isEmpty { return program }
        if let first = programArguments.first, !first.isEmpty { return first }
        return nil
    }

    /// File name without `.plist`.
    public var fileStem: String {
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".plist") ? String(name.dropLast(6)) : name
    }

    /// Parses plist data (XML or binary). Never throws.
    public static func parse(data: Data, path: String, home: String = NSHomeDirectory()) -> PerformanceLaunchPlist {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = object as? [String: Any] else {
            return PerformanceLaunchPlist(path: path, isValid: false)
        }
        let label = (dict["Label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let arguments = (dict["ProgramArguments"] as? [Any])?.compactMap { $0 as? String } ?? []
        let program = (dict["Program"] as? String).map { expandTilde($0, home: home) }
        let keepAlive: Bool
        if let flag = plistBool(dict["KeepAlive"]) {
            keepAlive = flag
        } else {
            keepAlive = dict["KeepAlive"] is [String: Any]
        }
        var associated: [String] = []
        if let list = dict["AssociatedBundleIdentifiers"] as? [Any] {
            associated = list.compactMap { $0 as? String }
        } else if let single = dict["AssociatedBundleIdentifiers"] as? String {
            associated = [single]
        }
        let interval = plistInt(dict["StartInterval"])
        return PerformanceLaunchPlist(
            path: path,
            isValid: true,
            label: label,
            program: program,
            programArguments: arguments.enumerated().map { $0.offset == 0 ? expandTilde($0.element, home: home) : $0.element },
            bundleProgram: dict["BundleProgram"] as? String,
            runAtLoad: plistBool(dict["RunAtLoad"]) ?? false,
            keepAlive: keepAlive,
            disabledKey: plistBool(dict["Disabled"]) ?? false,
            associatedBundleIdentifiers: associated,
            startInterval: interval,
            hasCalendarInterval: dict["StartCalendarInterval"] != nil
        )
    }

    /// Reads and parses a plist file. Unreadable files come back invalid.
    public static func load(path: String, home: String = NSHomeDirectory()) -> PerformanceLaunchPlist {
        guard let data = FileManager.default.contents(atPath: path) else {
            return PerformanceLaunchPlist(path: path, isValid: false)
        }
        return parse(data: data, path: path, home: home)
    }

    /// Lists the `.plist` files of a launchd folder, sorted by name.
    public static func plistPaths(in folder: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        return names.filter { $0.hasSuffix(".plist") && !$0.hasPrefix(".") }.sorted()
            .map { (folder as NSString).appendingPathComponent($0) }
    }

    /// Bool from a plist value (`Bool`, or `NSNumber` as some Foundation versions return).
    static func plistBool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    static func plistInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }
}

// MARK: - Installed apps (vendor attribution)

public struct PerformanceInstalledApp: Sendable, Hashable, Codable {
    public var bundleID: String
    public var name: String
    public var path: String

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

/// Finds apps in the usual folders by reading their Info.plist (no LaunchServices needed).
public enum PerformanceAppScanner {
    public static func defaultFolders(home: String) -> [String] {
        ["/Applications", (home as NSString).appendingPathComponent("Applications")]
    }

    /// Apps directly inside each folder, plus one level of plain sub-folders
    /// (e.g. `/Applications/Utilities`, `/Applications/Adobe Photoshop 2025`).
    public static func scan(folders: [String]) -> [PerformanceInstalledApp] {
        var out: [PerformanceInstalledApp] = []
        var seen = Set<String>()
        func visit(_ folder: String, depth: Int) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return }
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = (folder as NSString).appendingPathComponent(name)
                if name.hasSuffix(".app") {
                    if let app = read(appAt: path), seen.insert(app.bundleID.lowercased()).inserted {
                        out.append(app)
                    }
                } else if depth == 0 {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                        visit(path, depth: 1)
                    }
                }
            }
        }
        for folder in folders { visit(folder, depth: 0) }
        return out
    }

    public static func read(appAt path: String) -> PerformanceInstalledApp? {
        let infoPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: infoPath),
              let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let bundleID = dict["CFBundleIdentifier"] as? String, !bundleID.isEmpty else { return nil }
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let display = (dict["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let bundleName = (dict["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // The file name is what people see in Finder; prefer it over CFBundleName.
        return PerformanceInstalledApp(bundleID: bundleID, name: display ?? (fileName.isEmpty ? (bundleName ?? bundleID) : fileName),
                                       path: path)
    }
}

/// Lookup table used to tie launch items to the app (and vendor) they belong to.
public struct PerformanceAppIndex: Sendable {
    public let apps: [PerformanceInstalledApp]
    private let byBundleID: [String: PerformanceInstalledApp]

    public init(apps: [PerformanceInstalledApp]) {
        self.apps = apps
        var map: [String: PerformanceInstalledApp] = [:]
        for app in apps where map[app.bundleID.lowercased()] == nil {
            map[app.bundleID.lowercased()] = app
        }
        byBundleID = map
    }

    public func app(bundleID: String) -> PerformanceInstalledApp? {
        byBundleID[bundleID.lowercased()]
    }

    /// The app whose bundle contains `path` (outermost `.app`), if it is installed.
    public func app(containing path: String) -> PerformanceInstalledApp? {
        guard let bundle = PerformanceVendor.outermostAppBundle(in: path) else { return nil }
        let key = bundle.lowercased()
        return apps.first { $0.path.lowercased() == key }
    }

    /// An app whose bundle id equals the label or is a dotted prefix of it
    /// (`com.docker.docker` ⇐ `com.docker.docker.helper`), boundary-aware.
    public func app(matchingLabel label: String) -> PerformanceInstalledApp? {
        let l = label.lowercased()
        var best: PerformanceInstalledApp?
        for app in apps {
            let id = app.bundleID.lowercased()
            if l == id || l.hasPrefix(id + ".") {
                if best == nil || id.count > best!.bundleID.count { best = app }
            }
        }
        return best
    }

    /// Apps whose bundle id shares the label's organisation prefix (`com.google`).
    public func apps(inOrganization org: String) -> [PerformanceInstalledApp] {
        let o = org.lowercased()
        return apps.filter { PerformanceVendor.organization(of: $0.bundleID) == o }
    }
}

/// Who an item belongs to.
public struct PerformanceVendorMatch: Sendable, Hashable {
    /// Grouping key (organisation prefix such as `com.google`, or a name).
    public var key: String
    /// Display name for the vendor group.
    public var name: String
    /// The owning app, when one could be identified.
    public var app: PerformanceInstalledApp?

    public init(key: String, name: String, app: PerformanceInstalledApp?) {
        self.key = key
        self.name = name
        self.app = app
    }
}

public enum PerformanceVendor {
    /// Common organisation prefixes whose second component doesn't read well as a name.
    static let knownNames: [String: String] = [
        "com.google": "Google", "com.microsoft": "Microsoft", "com.adobe": "Adobe", "us.zoom": "Zoom",
        "com.docker": "Docker", "org.mozilla": "Mozilla", "com.dropbox": "Dropbox", "com.getdropbox": "Dropbox",
        "com.jetbrains": "JetBrains", "com.logitech": "Logitech", "com.logi": "Logitech", "com.valvesoftware": "Valve",
        "com.spotify": "Spotify", "com.brave": "Brave", "com.operasoftware": "Opera", "com.vmware": "VMware",
        "com.parallels": "Parallels", "com.oracle": "Oracle", "org.virtualbox": "VirtualBox", "com.cisco": "Cisco",
        "com.paloaltonetworks": "Palo Alto Networks", "com.crowdstrike": "CrowdStrike", "com.teamviewer": "TeamViewer",
        "com.anydesk": "AnyDesk", "com.tunnelbear": "TunnelBear", "net.tunnelblick": "Tunnelblick",
        "com.objective-see": "Objective-See", "com.bjango": "Bjango", "com.knollsoft": "Knollsoft",
        "org.pqrs": "Karabiner", "com.surteesstudios": "Surtees Studios", "com.agilebits": "1Password",
        "com.1password": "1Password", "com.nordvpn": "NordVPN", "com.expressvpn": "ExpressVPN",
        "com.github": "GitHub", "com.tinyspeck": "Slack", "com.hnc": "Discord", "com.citrix": "Citrix",
        "com.backblaze": "Backblaze", "com.carbonite": "Carbonite", "com.eset": "ESET", "com.sophos": "Sophos",
        "com.malwarebytes": "Malwarebytes", "com.bitdefender": "Bitdefender", "com.avast": "Avast", "com.avg": "AVG",
        "com.norton": "Norton", "com.symantec": "Symantec", "com.mcafee": "McAfee", "com.kaspersky": "Kaspersky",
        "com.razer": "Razer", "com.corsair": "Corsair", "com.steelseries": "SteelSeries", "com.elgato": "Elgato",
        "com.wacom": "Wacom", "com.epson": "Epson", "com.hp": "HP", "com.canon": "Canon", "com.brother": "Brother",
        "org.macports": "MacPorts", "homebrew": "Homebrew", "sh.brew": "Homebrew", "com.openai": "OpenAI",
        "com.amazon": "Amazon", "com.apple": "Apple",
    ]

    /// `com.google.keystone.agent` → `com.google`; names without dots → lowercased whole.
    public static func organization(of identifier: String) -> String {
        let parts = identifier.lowercased().split(separator: ".", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return identifier.lowercased() }
        return String(parts[0]) + "." + String(parts[1])
    }

    /// A readable vendor name for an organisation prefix.
    public static func displayName(forOrganization org: String) -> String {
        if let known = knownNames[org.lowercased()] { return known }
        let parts = org.split(separator: ".", omittingEmptySubsequences: true)
        let core = parts.count >= 2 ? String(parts[1]) : String(parts.first ?? Substring(org))
        guard let first = core.first else { return org }
        return String(first).uppercased() + core.dropFirst()
    }

    /// The outermost `.app` bundle in a path (`/Applications/X.app/Contents/…/Y.app/…` → `/Applications/X.app`).
    public static func outermostAppBundle(in path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var built = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            built += "/" + component
            if component.lowercased().hasSuffix(".app") { return built }
        }
        return nil
    }

    /// Attribution order: AssociatedBundleIdentifiers → program inside an app bundle →
    /// label matching an installed app → organisation prefix of the label/file name.
    public static func resolve(label: String?, fileStem: String?, executable: String?,
                               associatedBundleIDs: [String], apps: PerformanceAppIndex) -> PerformanceVendorMatch {
        for id in associatedBundleIDs {
            if let app = apps.app(bundleID: id) { return match(for: app) }
        }
        if let executable, let app = apps.app(containing: executable) { return match(for: app) }
        let identifier = label ?? fileStem ?? ""
        if !identifier.isEmpty, let app = apps.app(matchingLabel: identifier) { return match(for: app) }
        if let executable, let bundle = outermostAppBundle(in: executable) {
            // The app isn't in a scanned folder (or is gone): name the vendor after the bundle.
            let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            let key = associatedBundleIDs.first.map(organization(of:)) ?? (identifier.isEmpty ? name.lowercased() : organization(of: identifier))
            return PerformanceVendorMatch(key: key, name: name, app: nil)
        }
        let fallbackID = associatedBundleIDs.first ?? identifier
        guard !fallbackID.isEmpty else {
            let name = executable.map { ($0 as NSString).lastPathComponent } ?? "Unknown"
            return PerformanceVendorMatch(key: name.lowercased(), name: name, app: nil)
        }
        let org = organization(of: fallbackID)
        let siblings = apps.apps(inOrganization: org)
        if siblings.count == 1, let only = siblings.first {
            return PerformanceVendorMatch(key: org, name: only.name, app: only)
        }
        return PerformanceVendorMatch(key: org, name: displayName(forOrganization: org), app: nil)
    }

    private static func match(for app: PerformanceInstalledApp) -> PerformanceVendorMatch {
        PerformanceVendorMatch(key: organization(of: app.bundleID), name: app.name, app: app)
    }
}

// MARK: - Broken detection

public enum PerformanceBrokenCheck {
    /// Why a launch item can't work, or nil when it looks fine. Conservative: a program on
    /// a disk that isn't connected, or a bare command name, is never "broken".
    public static func reason(for plist: PerformanceLaunchPlist, apps: PerformanceAppIndex,
                              fileExists: (String) -> Bool) -> String? {
        guard plist.isValid else { return "This file isn't a readable launchd property list" }
        guard plist.label != nil else { return "It has no Label, so macOS can't load it" }
        if let executable = plist.executable {
            return missingProgramReason(executable, fileExists: fileExists)
        }
        if plist.bundleProgram != nil {
            let ids = plist.associatedBundleIdentifiers
            if !ids.isEmpty && !ids.contains(where: { apps.app(bundleID: $0) != nil }) {
                return "The app it belongs to is no longer installed"
            }
            return nil
        }
        return "It doesn't say which program to run"
    }

    /// For an absolute path that doesn't exist: the reason; otherwise nil.
    public static func missingProgramReason(_ path: String, fileExists: (String) -> Bool) -> String? {
        guard path.hasPrefix("/") else { return nil }          // bare command, resolved via PATH
        if fileExists(path) { return nil }
        if isOnDisconnectedVolume(path, fileExists: fileExists) { return nil }
        return "Its program is missing: \(path.abbreviatingHome)"
    }

    /// `/Volumes/<name>/…` where `/Volumes/<name>` itself isn't there (disk not connected).
    public static func isOnDisconnectedVolume(_ path: String, fileExists: (String) -> Bool) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return false }
        return !fileExists("/Volumes/" + parts[1])
    }
}

// MARK: - Startup items

/// Kinds of things that start with the Mac or your session.
public enum PerformanceStartupKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// "Open at Login" app registered the classic way (managed through System Events).
    case loginItem
    /// A login-item helper inside an app bundle, registered by the app itself.
    case appLoginItem
    case userAgent
    case globalAgent
    case systemDaemon
    /// A launch agent shipped inside an app bundle and registered by the app.
    case appAgent
    /// A launch daemon shipped inside an app bundle and registered by the app.
    case appDaemon

    public var isBackground: Bool {
        switch self {
        case .loginItem, .appLoginItem: return false
        default: return true
        }
    }

    /// Spruce can turn it on/off and remove it. App-registered items are changed in System Settings.
    public var isManageable: Bool {
        switch self {
        case .loginItem, .userAgent, .globalAgent, .systemDaemon: return true
        case .appLoginItem, .appAgent, .appDaemon: return false
        }
    }

    public var needsAdmin: Bool { self == .systemDaemon }

    public var label: String {
        switch self {
        case .loginItem: return "Opens at login"
        case .appLoginItem: return "App login item"
        case .userAgent: return "Agent · your account"
        case .globalAgent: return "Agent · all users"
        case .systemDaemon: return "System daemon"
        case .appAgent: return "App agent"
        case .appDaemon: return "App daemon"
        }
    }

    public var symbol: String {
        switch self {
        case .loginItem, .appLoginItem: return "power"
        case .userAgent, .globalAgent, .appAgent: return "gearshape.2"
        case .systemDaemon, .appDaemon: return "cpu"
        }
    }

    public init(domain: PerformanceLaunchDomain) {
        switch domain {
        case .userAgent: self = .userAgent
        case .globalAgent: self = .globalAgent
        case .systemDaemon: self = .systemDaemon
        }
    }
}

public enum PerformanceStartupStatus: String, Codable, Sendable, Hashable {
    case running
    case enabled
    case disabled
    case broken
    /// Registered by an app; on/off lives in System Settings.
    case managedBySystem

    public var title: String {
        switch self {
        case .running: return "Running"
        case .enabled: return "On"
        case .disabled: return "Off"
        case .broken: return "Broken"
        case .managedBySystem: return "Managed by macOS"
        }
    }
}

public struct PerformanceStartupItem: Identifiable, Hashable, Sendable, Codable {
    /// Plist path for launchd items, `login:<path or name>` for login items, `app:<path>` for app items.
    public var id: String
    public var kind: PerformanceStartupKind
    public var name: String
    public var label: String?
    public var plistPath: String?
    public var executablePath: String?
    public var vendorKey: String
    public var vendorName: String
    /// Owning app bundle (for its icon and name).
    public var appPath: String?
    public var appBundleID: String?
    public var isEnabled: Bool
    /// Loaded in launchd right now (nil when unknown).
    public var isLoaded: Bool?
    public var pid: Int32?
    public var brokenReason: String?
    public var runAtLoad: Bool
    public var keepAlive: Bool
    /// For classic login items: whether it opens hidden.
    public var opensHidden: Bool

    public init(id: String, kind: PerformanceStartupKind, name: String, label: String? = nil, plistPath: String? = nil,
                executablePath: String? = nil, vendorKey: String, vendorName: String, appPath: String? = nil,
                appBundleID: String? = nil, isEnabled: Bool, isLoaded: Bool? = nil, pid: Int32? = nil,
                brokenReason: String? = nil, runAtLoad: Bool = false, keepAlive: Bool = false, opensHidden: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.label = label
        self.plistPath = plistPath
        self.executablePath = executablePath
        self.vendorKey = vendorKey
        self.vendorName = vendorName
        self.appPath = appPath
        self.appBundleID = appBundleID
        self.isEnabled = isEnabled
        self.isLoaded = isLoaded
        self.pid = pid
        self.brokenReason = brokenReason
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.opensHidden = opensHidden
    }

    public var isBroken: Bool { brokenReason != nil }
    public var isBackground: Bool { kind.isBackground }
    public var canToggle: Bool { kind.isManageable && (kind == .loginItem || label != nil) }
    public var canRemove: Bool { kind.isManageable }

    public var status: PerformanceStartupStatus {
        if !kind.isManageable { return .managedBySystem }
        if isBroken { return .broken }
        if !isEnabled { return .disabled }
        if pid != nil { return .running }
        return .enabled
    }

    /// One-line status for the row.
    public var statusDetail: String {
        if let brokenReason { return brokenReason }
        switch status {
        case .managedBySystem:
            return isLoaded == true ? "Registered by its app · change it in System Settings" : "Change it in System Settings"
        case .disabled:
            return kind == .loginItem ? "Won't open at login" : "Won't start until you turn it back on"
        case .running:
            return pid.map { "Running now (process \($0))" } ?? "Running now"
        case .enabled:
            if kind == .loginItem { return opensHidden ? "Opens hidden when you log in" : "Opens when you log in" }
            if isLoaded == false && (runAtLoad || keepAlive) {
                return "Not loaded · it may be switched off in System Settings"
            }
            if keepAlive { return "Kept running by macOS" }
            if runAtLoad { return "Starts at login" }
            return "Starts when needed"
        case .broken:
            return "Broken"
        }
    }
}

/// launchd's view of one service.
public struct PerformanceLaunchService: Sendable, Hashable {
    public var label: String
    public var pid: Int32?
    public var lastExitStatus: String?

    public init(label: String, pid: Int32?, lastExitStatus: String?) {
        self.label = label
        self.pid = pid
        self.lastExitStatus = lastExitStatus
    }
}

/// launchd state of one domain (`gui/<uid>` or `system`). nil members mean "couldn't read".
public struct PerformanceLaunchDomainState: Sendable {
    public var services: [String: PerformanceLaunchService]?
    /// label → disabled
    public var overrides: [String: Bool]?

    public init(services: [String: PerformanceLaunchService]? = nil, overrides: [String: Bool]? = nil) {
        self.services = services
        self.overrides = overrides
    }

    public func isDisabled(_ label: String, plistDisabled: Bool) -> Bool {
        overrides?[label] ?? plistDisabled
    }
}

public enum PerformanceStartupBuilder {
    /// Labels and files that are never listed (Apple's own items).
    public static func isApple(label: String?, fileStem: String) -> Bool {
        let l = (label ?? "").lowercased()
        return l.hasPrefix("com.apple.") || fileStem.lowercased().hasPrefix("com.apple.")
    }

    /// Builds the item for one plist in a launchd folder. Returns nil for Apple items and
    /// for items whose label starts with one of `excludedLabelPrefixes` (our own).
    public static func item(from plist: PerformanceLaunchPlist, domain: PerformanceLaunchDomain,
                            state: PerformanceLaunchDomainState, apps: PerformanceAppIndex,
                            excludedLabelPrefixes: [String] = [],
                            fileExists: (String) -> Bool) -> PerformanceStartupItem? {
        if isApple(label: plist.label, fileStem: plist.fileStem) { return nil }
        if let label = plist.label?.lowercased(),
           excludedLabelPrefixes.contains(where: { !$0.isEmpty && label.hasPrefix($0.lowercased()) }) { return nil }
        let vendor = PerformanceVendor.resolve(label: plist.label, fileStem: plist.fileStem, executable: plist.executable,
                                               associatedBundleIDs: plist.associatedBundleIdentifiers, apps: apps)
        let service = plist.label.flatMap { state.services?[$0] }
        let loaded: Bool? = state.services == nil ? nil : (service != nil)
        let enabled = plist.label.map { !state.isDisabled($0, plistDisabled: plist.disabledKey) } ?? !plist.disabledKey
        return PerformanceStartupItem(
            id: plist.path,
            kind: PerformanceStartupKind(domain: domain),
            name: displayName(for: plist, vendor: vendor),
            label: plist.label,
            plistPath: plist.path,
            executablePath: plist.executable,
            vendorKey: vendor.key,
            vendorName: vendor.name,
            appPath: vendor.app?.path,
            appBundleID: vendor.app?.bundleID,
            isEnabled: enabled,
            isLoaded: loaded,
            pid: service?.pid,
            brokenReason: PerformanceBrokenCheck.reason(for: plist, apps: apps, fileExists: fileExists),
            runAtLoad: plist.runAtLoad,
            keepAlive: plist.keepAlive
        )
    }

    /// A readable row title: the program's name when it says more than the label.
    public static func displayName(for plist: PerformanceLaunchPlist, vendor: PerformanceVendorMatch) -> String {
        if let executable = plist.executable {
            if let helper = innermostAppName(in: executable) { return helper }
            let base = (executable as NSString).lastPathComponent
            if !base.isEmpty && base.count > 2 && !base.contains("launcher") && base != "sh" && base != "bash" && base != "zsh" {
                return base
            }
        }
        return plist.label ?? plist.fileStem
    }

    /// `…/Foo Helper.app/Contents/MacOS/x` → "Foo Helper".
    static func innermostAppName(in path: String) -> String? {
        var found: String?
        for component in path.split(separator: "/", omittingEmptySubsequences: true) where component.lowercased().hasSuffix(".app") {
            found = String(component.dropLast(4))
        }
        return found
    }

    /// A classic "Open at Login" item from System Events.
    public static func loginItem(_ legacy: PerformanceLegacyLoginItem, isEnabled: Bool, apps: PerformanceAppIndex,
                                 runningPIDs: [String: Int32] = [:], fileExists: (String) -> Bool) -> PerformanceStartupItem {
        let path = legacy.path.isEmpty ? nil : legacy.path
        var app: PerformanceInstalledApp?
        if let path {
            app = apps.app(containing: path) ?? apps.apps.first(where: { candidate in candidate.path == path })
        }
        let key: String
        if let app {
            key = PerformanceVendor.organization(of: app.bundleID)
        } else {
            key = legacy.name.lowercased()
        }
        var broken: String?
        if isEnabled, let path {
            if !fileExists(path) && !PerformanceBrokenCheck.isOnDisconnectedVolume(path, fileExists: fileExists) {
                broken = "The item it opens is missing: \(path.abbreviatingHome)"
            }
        }
        return PerformanceStartupItem(
            id: "login:" + (path ?? legacy.name),
            kind: .loginItem,
            name: legacy.name,
            executablePath: path,
            vendorKey: key,
            vendorName: app?.name ?? legacy.name,
            appPath: app?.path ?? (path?.lowercased().hasSuffix(".app") == true ? path : nil),
            appBundleID: app?.bundleID,
            isEnabled: isEnabled,
            isLoaded: nil,
            pid: path.flatMap { runningPIDs[$0] },
            brokenReason: broken,
            runAtLoad: true,
            opensHidden: legacy.hidden
        )
    }
}

// MARK: - Grouping

public struct PerformanceVendorGroup: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var appPath: String?
    public var items: [PerformanceStartupItem]

    public init(id: String, title: String, appPath: String?, items: [PerformanceStartupItem]) {
        self.id = id
        self.title = title
        self.appPath = appPath
        self.items = items
    }

    public var brokenCount: Int { items.filter(\.isBroken).count }
    public var enabledCount: Int { items.filter { $0.isEnabled && $0.kind.isManageable }.count }
}

public enum PerformanceStartupGrouping {
    /// Groups items by vendor. A group named after one app when all its items share it,
    /// after the organisation otherwise. Groups and items are sorted by name.
    public static func groups(_ items: [PerformanceStartupItem]) -> [PerformanceVendorGroup] {
        var buckets: [String: [PerformanceStartupItem]] = [:]
        var order: [String] = []
        for item in items {
            let key = item.vendorKey.isEmpty ? item.vendorName.lowercased() : item.vendorKey
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        let groups = order.map { key -> PerformanceVendorGroup in
            let members = buckets[key] ?? []
            let names = Set(members.map(\.vendorName))
            let appPaths = members.compactMap(\.appPath)
            let title: String
            if names.count == 1, let only = names.first {
                title = only
            } else if let known = PerformanceVendor.knownNames[key] {
                title = known
            } else {
                title = PerformanceVendor.displayName(forOrganization: key)
            }
            let sorted = members.sorted { lhs, rhs in
                if lhs.isBroken != rhs.isBroken { return lhs.isBroken }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return PerformanceVendorGroup(id: key, title: title, appPath: appPaths.first, items: sorted)
        }
        return groups.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: - Ignore list

/// Startup items covered by the ignore list (`SpruceSettings`) are never listed,
/// switched or removed.
public enum PerformanceStartupIgnore {
    /// True when the item's id or plist, its app's bundle id or its launchd label, or its
    /// plist, program or app (or a folder holding one of them) is on the ignore list.
    public static func isIgnored(_ item: PerformanceStartupItem, settings: SpruceSettings) -> Bool {
        if !settings.ignoredItemIDs.isEmpty {
            let ids = Set(settings.ignoredItemIDs)
            if ids.contains(item.id) { return true }
            if let plist = item.plistPath, ids.contains(plist) { return true }
        }
        if !settings.ignoredBundleIDs.isEmpty {
            let own = [item.appBundleID, item.label].compactMap { $0?.lowercased() }.filter { !$0.isEmpty }
            if settings.ignoredBundleIDs.contains(where: { own.contains($0.lowercased()) }) { return true }
        }
        guard !settings.ignoredPaths.isEmpty else { return false }
        return [item.plistPath, item.executablePath, item.appPath].contains { path in
            guard let path, path.hasPrefix("/") else { return false }
            return settings.isIgnored(path: path)
        }
    }

    /// The items the ignore list doesn't cover, in their original order.
    public static func filtered(_ items: [PerformanceStartupItem], settings: SpruceSettings) -> [PerformanceStartupItem] {
        guard !settings.ignoredItemIDs.isEmpty || !settings.ignoredBundleIDs.isEmpty || !settings.ignoredPaths.isEmpty else {
            return items
        }
        return items.filter { !isIgnored($0, settings: settings) }
    }

    /// Shown when an item reaches an action after it was added to the ignore list.
    public static let refusalReason = "It's on your ignore list, so Spruce leaves it alone."
}

// MARK: - Classic login items (System Events)

public struct PerformanceLegacyLoginItem: Codable, Hashable, Sendable {
    public var name: String
    public var path: String
    public var hidden: Bool

    public init(name: String, path: String, hidden: Bool) {
        self.name = name
        self.path = path
        self.hidden = hidden
    }
}

public enum PerformanceAppleScript {
    /// An AppleScript string literal with quotes and backslashes escaped.
    public static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Lists login items as `name<TAB>POSIX path<TAB>hidden` lines.
    public static let listLoginItemsSource = """
    set out to ""
    tell application "System Events"
        repeat with li in login items
            set n to ""
            set p to ""
            set h to "false"
            try
                set n to name of li
            end try
            try
                set p to path of li
            end try
            try
                set h to (hidden of li) as text
            end try
            set out to out & n & tab & p & tab & h & linefeed
        end repeat
    end tell
    return out
    """

    /// Deletes the login item that opens `path`. Two items can share a display name, so
    /// the name is used only for an item System Events reports without a path, and then
    /// only items that have no path either are deleted.
    public static func deleteLoginItemSource(name: String, path: String) -> String {
        if !path.isEmpty {
            return "tell application \"System Events\" to delete (every login item whose path is \(quote(path)))"
        }
        // Walk backwards by index so deleting one doesn't shift the ones still to check.
        return """
        tell application "System Events"
            repeat with i from (count of login items) to 1 by -1
                set p to ""
                try
                    set p to (path of login item i) as text
                end try
                if p is "missing value" then set p to ""
                set n to ""
                try
                    set n to name of login item i
                end try
                if p is "" and n is \(quote(name)) then delete login item i
            end repeat
        end tell
        """
    }

    public static func addLoginItemSource(path: String, hidden: Bool) -> String {
        "tell application \"System Events\" to make login item at end with properties {path:\(quote(path)), hidden:\(hidden ? "true" : "false")}"
    }

    /// Parses the output of `listLoginItemsSource`.
    public static func parseLoginItems(_ output: String) -> [PerformanceLegacyLoginItem] {
        var out: [PerformanceLegacyLoginItem] = []
        for rawLine in output.components(separatedBy: CharacterSet(charactersIn: "\n\r")) {
            guard !rawLine.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let fields = rawLine.components(separatedBy: "\t")
            let name = fields[0].trimmingCharacters(in: .whitespaces)
            let path = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespaces) : ""
            let hidden = fields.count > 2 && fields[2].trimmingCharacters(in: .whitespaces).lowercased() == "true"
            let display = name.isEmpty ? ((path as NSString).lastPathComponent as NSString).deletingPathExtension : name
            guard !display.isEmpty else { continue }
            out.append(PerformanceLegacyLoginItem(name: display, path: path == "missing value" ? "" : path, hidden: hidden))
        }
        return out
    }
}
