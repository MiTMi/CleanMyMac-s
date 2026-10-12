import Foundation

/// Types of add-ons the Extensions tool lists.
public enum ApplicationsExtensionKind: String, Codable, Sendable, CaseIterable {
    /// Modern app extensions registered with PlugInKit (Share, Finder, Safari, widgets…).
    case appExtension
    case quickLook
    case spotlight
    case preferencePane
    case internetPlugin
    case screenSaver
    case inputMethod
    case service

    public var title: String {
        switch self {
        case .appExtension: return "App Extensions"
        case .quickLook: return "Quick Look Plug-ins"
        case .spotlight: return "Spotlight Importers"
        case .preferencePane: return "Preference Panes"
        case .internetPlugin: return "Internet Plug-ins"
        case .screenSaver: return "Screen Savers"
        case .inputMethod: return "Input Methods"
        case .service: return "Services"
        }
    }

    public var symbol: String {
        switch self {
        case .appExtension: return "puzzlepiece.extension"
        case .quickLook: return "eye"
        case .spotlight: return "magnifyingglass"
        case .preferencePane: return "gearshape.2"
        case .internetPlugin: return "globe"
        case .screenSaver: return "sparkles.tv"
        case .inputMethod: return "keyboard"
        case .service: return "gearshape.arrow.triangle.2.circlepath"
        }
    }

    public var detail: String {
        switch self {
        case .appExtension: return "Extensions that apps add to Finder, Share menus, Safari, widgets and more. Turning one off is reversible."
        case .quickLook: return "Generators that preview file types in Quick Look. macOS 15 and later no longer loads legacy generators."
        case .spotlight: return "Importers that let Spotlight index file types."
        case .preferencePane: return "Panels added to System Settings."
        case .internetPlugin: return "Legacy browser plug-ins. Modern browsers no longer load most of them."
        case .screenSaver: return "Screen savers you installed."
        case .inputMethod: return "Additional keyboard input methods."
        case .service: return "Actions added to the Services menu."
        }
    }
}

/// One extension or plug-in.
public struct ApplicationsExtensionInfo: Identifiable, Hashable, Sendable, Codable {
    /// `pluginkit:<identifier>` for app extensions, the file path for plug-in files.
    public var id: String
    public var name: String
    public var kind: ApplicationsExtensionKind
    /// Short category for app extensions ("Share", "Finder", "Safari"…).
    public var category: String?
    public var identifier: String?
    public var version: String?
    public var path: String?
    /// The app that contains the extension.
    public var hostAppName: String?
    public var hostAppPath: String?
    /// nil when the item cannot be turned on/off (plug-in files).
    public var isEnabled: Bool?
    /// Installed for this user only (`~/Library`), as opposed to all users.
    public var isUserDomain: Bool

    public init(id: String, name: String, kind: ApplicationsExtensionKind, category: String? = nil, identifier: String? = nil,
                version: String? = nil, path: String? = nil, hostAppName: String? = nil, hostAppPath: String? = nil,
                isEnabled: Bool? = nil, isUserDomain: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.category = category
        self.identifier = identifier
        self.version = version
        self.path = path
        self.hostAppName = hostAppName
        self.hostAppPath = hostAppPath
        self.isEnabled = isEnabled
        self.isUserDomain = isUserDomain
    }

    /// App extensions are switched on/off with `pluginkit -e use|ignore`.
    public var canToggle: Bool { kind == .appExtension && identifier != nil && isEnabled != nil }
    /// Plug-in files can be moved to the Trash; app extensions go away with their host app.
    public var canRemove: Bool { kind != .appExtension && path != nil }
}

/// One record of `pluginkit -mAvvv` output.
public struct ApplicationsPluginKitEntry: Sendable, Hashable {
    /// "+" (turned on by the user), "-" (turned off), "=" (superseded), "!" (debug) or nil (default).
    public var election: Character?
    public var identifier: String
    public var version: String
    public var path: String?
    public var parentBundle: String?
    public var displayName: String?
    public var parentName: String?
    /// The extension point (`SDK` key), e.g. `com.apple.share-services`.
    public var extensionPoint: String?

    public var isEnabled: Bool { election != "-" }
}

public enum ApplicationsPluginKit {

    /// Parses `pluginkit -mAvvv` output:
    ///
    /// ```
    /// +    com.foo.Share(1.2)
    ///             Path = /Applications/Foo.app/Contents/PlugIns/Share.appex
    ///              SDK = com.apple.share-services
    ///    Parent Bundle = /Applications/Foo.app
    ///     Display Name = Foo
    /// ```
    public static func parse(_ output: String) -> [ApplicationsPluginKitEntry] {
        var entries: [ApplicationsPluginKitEntry] = []
        var current: ApplicationsPluginKitEntry?
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            if let range = line.range(of: " = ") {
                guard current != nil else { continue }
                let key = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "Path": current?.path = value
                case "Parent Bundle": current?.parentBundle = value
                case "Display Name": current?.displayName = value
                case "Parent Name": current?.parentName = value
                case "SDK": current?.extensionPoint = value
                default: break
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let header = parseHeader(line) else { continue }
            if let finished = current { entries.append(finished) }
            current = header
        }
        if let finished = current { entries.append(finished) }
        return entries
    }

    /// "+    com.foo.bar(1.0)" / "     com.foo.bar(1.0)" → entry with election and version.
    static func parseHeader(_ line: String) -> ApplicationsPluginKitEntry? {
        guard let first = line.first else { return nil }
        var election: Character?
        var rest = Substring(line)
        if "+-=!?".contains(first) {
            election = first
            rest = rest.dropFirst()
        }
        let body = rest.trimmingCharacters(in: .whitespaces)
        guard body.hasSuffix(")"), let open = body.lastIndex(of: "("), open > body.startIndex else { return nil }
        let identifier = String(body[..<open]).trimmingCharacters(in: .whitespaces)
        let version = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
        guard !identifier.isEmpty, !identifier.contains(" ") else { return nil }
        return ApplicationsPluginKitEntry(election: election, identifier: identifier, version: version)
    }

    /// Third-party extensions only (no Apple ids, nothing inside the system volume),
    /// one record per identifier.
    public static func thirdParty(_ entries: [ApplicationsPluginKitEntry]) -> [ApplicationsPluginKitEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            let id = entry.identifier.lowercased()
            if id.hasPrefix("com.apple.") { return false }
            if let path = entry.path, isSystemPath(path) { return false }
            return seen.insert(id).inserted
        }
    }

    static func isSystemPath(_ path: String) -> Bool {
        ["/System/", "/usr/", "/Library/Apple/", "/private/var/"].contains { path.hasPrefix($0) }
    }

    /// Friendly name of an extension point.
    public static func categoryTitle(_ point: String?) -> String {
        guard let point = point?.lowercased() else { return "Other" }
        let table: [(String, String)] = [
            ("com.apple.share-services", "Share Menu"),
            ("com.apple.findersync", "Finder"),
            ("com.apple.finder", "Finder"),
            ("com.apple.widgetkit-extension", "Widgets"),
            ("com.apple.widget-extension", "Widgets"),
            ("com.apple.notificationcenter", "Widgets"),
            ("com.apple.quicklook", "Quick Look"),
            ("com.apple.safari", "Safari"),
            ("com.apple.spotlight", "Spotlight"),
            ("com.apple.fileprovider", "File Providers"),
            ("com.apple.photo-editing", "Photos"),
            ("com.apple.services", "Actions"),
            ("com.apple.ui-services", "Actions"),
            ("com.apple.intents", "Siri & Shortcuts"),
            ("com.apple.appintents", "Siri & Shortcuts"),
            ("com.apple.authentication-services", "Passwords"),
            ("com.apple.mail", "Mail"),
            ("com.apple.message-payload-provider", "Messages"),
            ("com.apple.keyboard-service", "Keyboards"),
            ("com.apple.textinput", "Keyboards"),
            ("com.apple.screensaver", "Screen Savers"),
            ("com.apple.networkextension", "Network"),
            ("com.apple.background-asset", "Background Downloads"),
            ("com.apple.thumbnail", "Quick Look"),
            ("com.apple.preview", "Quick Look"),
            ("com.apple.callkit", "Calls"),
            ("com.apple.usernotifications", "Notifications"),
        ]
        for (prefix, title) in table where point.hasPrefix(prefix) { return title }
        return "Other"
    }

    /// Converts parsed entries into extension records.
    public static func extensions(from entries: [ApplicationsPluginKitEntry]) -> [ApplicationsExtensionInfo] {
        thirdParty(entries).map { entry in
            let hostName = entry.parentName ?? entry.parentBundle.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
            let name = entry.displayName ?? entry.path.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                ?? entry.identifier
            return ApplicationsExtensionInfo(
                id: "pluginkit:" + entry.identifier, name: name, kind: .appExtension,
                category: categoryTitle(entry.extensionPoint), identifier: entry.identifier, version: entry.version,
                path: entry.path, hostAppName: hostName, hostAppPath: entry.parentBundle, isEnabled: entry.isEnabled,
                isUserDomain: true)
        }
    }
}

/// Folders that hold plug-in files, per kind.
public enum ApplicationsExtensionCatalog {
    public struct Location: Sendable, Hashable {
        public var path: String
        public var kind: ApplicationsExtensionKind
        public var extensions: Set<String>
        public var isUserDomain: Bool
    }

    public static func locations(home: String = NSHomeDirectory()) -> [Location] {
        let kinds: [(String, ApplicationsExtensionKind, Set<String>)] = [
            ("QuickLook", .quickLook, ["qlgenerator"]),
            ("Spotlight", .spotlight, ["mdimporter"]),
            ("PreferencePanes", .preferencePane, ["prefpane"]),
            ("Internet Plug-Ins", .internetPlugin, ["plugin", "webplugin"]),
            ("Screen Savers", .screenSaver, ["saver", "qtz"]),
            ("Input Methods", .inputMethod, ["app", "bundle", "component", "inputmethod"]),
            ("Services", .service, ["workflow", "service"]),
        ]
        var result: [Location] = []
        let userLibrary = (home as NSString).appendingPathComponent("Library")
        for (folder, kind, exts) in kinds {
            result.append(Location(path: (userLibrary as NSString).appendingPathComponent(folder), kind: kind,
                                   extensions: exts, isUserDomain: true))
            result.append(Location(path: ("/Library" as NSString).appendingPathComponent(folder), kind: kind,
                                   extensions: exts, isUserDomain: false))
        }
        return result
    }

    /// Plug-in files in the catalog's folders. `info` reads (name, identifier, version) from a bundle.
    public static func files(locations: [Location], listDirectory: (String) -> [String] = ApplicationsLeftoverMatcher.defaultList,
                             info: (String) -> (name: String?, identifier: String?, version: String?)) -> [ApplicationsExtensionInfo] {
        var result: [ApplicationsExtensionInfo] = []
        for location in locations {
            for name in listDirectory(location.path) where !name.hasPrefix(".") {
                let ext = (name as NSString).pathExtension.lowercased()
                guard location.extensions.contains(ext) else { continue }
                let path = (location.path as NSString).appendingPathComponent(name)
                let meta = info(path)
                let display = meta.name.flatMap { $0.isEmpty ? nil : $0 } ?? (name as NSString).deletingPathExtension
                result.append(ApplicationsExtensionInfo(
                    id: path, name: display, kind: location.kind, identifier: meta.identifier, version: meta.version,
                    path: path, isEnabled: nil, isUserDomain: location.isUserDomain))
            }
        }
        return result
    }

    /// Reads name/identifier/version from a bundle's Info.plist (Foundation only).
    public static func bundleInfo(atPath path: String) -> (name: String?, identifier: String?, version: String?) {
        let plist = ApplicationsPlist.dictionary(atPath: (path as NSString).appendingPathComponent("Contents/Info.plist"))
            ?? ApplicationsPlist.dictionary(atPath: (path as NSString).appendingPathComponent("Info.plist"))
        guard let plist else { return (nil, nil, nil) }
        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["NSPrefPaneIconLabel"] as? String)
            ?? (plist["CFBundleName"] as? String)
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        return (name, plist["CFBundleIdentifier"] as? String, version)
    }
}
