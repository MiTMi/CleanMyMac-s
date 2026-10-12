import Foundation

// MARK: - Update records

/// Where an update comes from (and therefore how it is applied).
public enum ApplicationsUpdateSource: String, Codable, Sendable, CaseIterable {
    /// Mac App Store — handed off to the App Store app.
    case appStore
    /// The app's own Sparkle updater — the app installs it when opened.
    case sparkle
    /// A Homebrew cask — `brew upgrade --cask` runs it unattended.
    case homebrew

    public var title: String {
        switch self {
        case .appStore: return "App Store"
        case .sparkle: return "In-app updates"
        case .homebrew: return "Homebrew"
        }
    }

    public var symbol: String {
        switch self {
        case .appStore: return "bag"
        case .sparkle: return "arrow.down.app"
        case .homebrew: return "mug"
        }
    }

    /// How the update is applied, for the detail pane.
    public var actionDetail: String {
        switch self {
        case .appStore: return "Updates are installed by the App Store app."
        case .sparkle: return "The app downloads and installs this update itself when you open it."
        case .homebrew: return "Spruce runs Homebrew to download and install this update."
        }
    }
}

/// One available update for an installed app.
public struct ApplicationsUpdate: Identifiable, Hashable, Sendable, Codable {
    public var id: String { bundleID.lowercased() + "|" + source.rawValue }
    public var appPath: String
    public var bundleID: String
    public var name: String
    public var installedVersion: String
    public var availableVersion: String
    public var source: ApplicationsUpdateSource
    /// Plain-text release notes, when the source provides them.
    public var releaseNotes: String?
    public var releaseNotesURL: URL?
    /// Direct download (Sparkle enclosure) or download page.
    public var downloadURL: URL?
    /// `macappstore://` link for App Store apps.
    public var storeURL: URL?
    public var caskToken: String?
    public var releaseDate: Date?
    public var downloadSize: Int64?
    /// First version number increases — may need a new licence; never pre-selected.
    public var isMajor: Bool
    public var isCritical: Bool
    public var minimumSystemVersion: String?

    public init(appPath: String, bundleID: String, name: String, installedVersion: String, availableVersion: String,
                source: ApplicationsUpdateSource, releaseNotes: String? = nil, releaseNotesURL: URL? = nil,
                downloadURL: URL? = nil, storeURL: URL? = nil, caskToken: String? = nil, releaseDate: Date? = nil,
                downloadSize: Int64? = nil, isMajor: Bool = false, isCritical: Bool = false, minimumSystemVersion: String? = nil) {
        self.appPath = appPath
        self.bundleID = bundleID
        self.name = name
        self.installedVersion = installedVersion
        self.availableVersion = availableVersion
        self.source = source
        self.releaseNotes = releaseNotes
        self.releaseNotesURL = releaseNotesURL
        self.downloadURL = downloadURL
        self.storeURL = storeURL
        self.caskToken = caskToken
        self.releaseDate = releaseDate
        self.downloadSize = downloadSize
        self.isMajor = isMajor
        self.isCritical = isCritical
        self.minimumSystemVersion = minimumSystemVersion
    }

    /// Homebrew updates can be applied without the user (Checkup "Run").
    public var isUnattended: Bool { source == .homebrew && caskToken != nil }

    /// Settings key that ignores every update of this app.
    public var ignoreAppKey: String { ApplicationsUpdateIgnore.appKey(bundleID: bundleID) }
    /// Settings key that skips only this version.
    public var skipVersionKey: String { ApplicationsUpdateIgnore.versionKey(bundleID: bundleID, version: availableVersion) }
}

/// Ignore-list keys for updates (stored in `SpruceSettings.ignoredItemIDs`).
public enum ApplicationsUpdateIgnore {
    public static let prefix = "applications.update:"

    public static func appKey(bundleID: String) -> String { prefix + bundleID.lowercased() }

    public static func versionKey(bundleID: String, version: String) -> String {
        prefix + bundleID.lowercased() + "@" + version
    }

    public static func isIgnored(_ update: ApplicationsUpdate, ignoredItemIDs: [String], ignoredBundleIDs: [String] = []) -> Bool {
        if ignoredBundleIDs.contains(where: { $0.caseInsensitiveCompare(update.bundleID) == .orderedSame }) { return true }
        let ids = Set(ignoredItemIDs)
        return ids.contains(update.ignoreAppKey) || ids.contains(update.skipVersionKey)
    }

    /// Removes ignored updates; also drops updates offered by more than one source,
    /// keeping the preferred one (App Store, then Homebrew, then Sparkle).
    public static func filtered(_ updates: [ApplicationsUpdate], ignoredItemIDs: [String],
                                ignoredBundleIDs: [String] = []) -> [ApplicationsUpdate] {
        let rank: [ApplicationsUpdateSource: Int] = [.appStore: 0, .homebrew: 1, .sparkle: 2]
        var best: [String: ApplicationsUpdate] = [:]
        for update in updates where !isIgnored(update, ignoredItemIDs: ignoredItemIDs, ignoredBundleIDs: ignoredBundleIDs) {
            let key = update.appPath
            if let existing = best[key], rank[existing.source, default: 9] <= rank[update.source, default: 9] { continue }
            best[key] = update
        }
        return best.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Sparkle → update

public extension ApplicationsUpdate {
    /// Builds an update from the best appcast item when it is newer than the installed app.
    static func fromAppcast(_ item: ApplicationsAppcastItem, app: ApplicationsAppInfo, feedURL: URL?) -> ApplicationsUpdate? {
        guard ApplicationsVersion.isUpdate(availableVersion: item.displayVersion, availableBuild: item.version,
                                           installedVersion: app.version, installedBuild: app.build) else { return nil }
        let notes = item.descriptionText.map(ApplicationsHTMLText.plainText(_:)).flatMap { $0.isEmpty ? nil : $0 }
        let notesLink = (item.releaseNotesLink ?? item.fullReleaseNotesLink).flatMap(URL.init(string:))
        let download = item.isInformational
            ? (item.link.flatMap(URL.init(string:)) ?? item.enclosureURL.flatMap(URL.init(string:)))
            : (item.enclosureURL.flatMap(URL.init(string:)) ?? item.link.flatMap(URL.init(string:)))
        var major = ApplicationsVersion.isMajorUpgrade(from: app.version, to: item.displayVersion)
        if let minimumAuto = item.minimumAutoupdateVersion, !app.build.isEmpty,
           ApplicationsVersion.compare(app.build, minimumAuto) == .orderedAscending {
            major = true
        }
        return ApplicationsUpdate(
            appPath: app.path, bundleID: app.bundleID, name: app.name, installedVersion: app.version.isEmpty ? app.build : app.version,
            availableVersion: item.displayVersion, source: .sparkle, releaseNotes: notes, releaseNotesURL: notesLink,
            downloadURL: download, releaseDate: item.pubDate, downloadSize: item.enclosureLength, isMajor: major,
            isCritical: item.isCritical, minimumSystemVersion: item.minimumSystemVersion)
    }
}

// MARK: - iTunes lookup (App Store)

/// Response of `https://itunes.apple.com/lookup`.
public struct ApplicationsITunesLookup: Decodable, Sendable {
    public var resultCount: Int
    public var results: [ApplicationsITunesApp]
}

/// The fields of an iTunes lookup result Spruce uses.
public struct ApplicationsITunesApp: Decodable, Sendable, Hashable {
    public var bundleId: String?
    public var trackId: Int?
    public var trackName: String?
    public var version: String?
    public var trackViewUrl: String?
    public var releaseNotes: String?
    public var currentVersionReleaseDate: String?
    public var minimumOsVersion: String?
    public var sellerName: String?
    public var artistName: String?
    public var fileSizeBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case bundleId, trackId, trackName, version, trackViewUrl, releaseNotes, currentVersionReleaseDate,
             minimumOsVersion, sellerName, artistName, fileSizeBytes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try? c.decodeIfPresent(String.self, forKey: .bundleId)
        trackId = try? c.decodeIfPresent(Int.self, forKey: .trackId)
        trackName = try? c.decodeIfPresent(String.self, forKey: .trackName)
        version = try? c.decodeIfPresent(String.self, forKey: .version)
        trackViewUrl = try? c.decodeIfPresent(String.self, forKey: .trackViewUrl)
        releaseNotes = try? c.decodeIfPresent(String.self, forKey: .releaseNotes)
        currentVersionReleaseDate = try? c.decodeIfPresent(String.self, forKey: .currentVersionReleaseDate)
        minimumOsVersion = try? c.decodeIfPresent(String.self, forKey: .minimumOsVersion)
        sellerName = try? c.decodeIfPresent(String.self, forKey: .sellerName)
        artistName = try? c.decodeIfPresent(String.self, forKey: .artistName)
        // Apple sends the size as a string; accept a number too.
        if let text = try? c.decodeIfPresent(String.self, forKey: .fileSizeBytes) {
            fileSizeBytes = Int64(text)
        } else {
            fileSizeBytes = try? c.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        }
    }

    public var releaseDate: Date? {
        guard let currentVersionReleaseDate else { return nil }
        return ISO8601DateFormatter().date(from: currentVersionReleaseDate)
    }

    /// The App Store app link (`https://apps.apple.com/...` rewritten to `macappstore://`).
    public var storeURL: URL? {
        if let trackViewUrl, var components = URLComponents(string: trackViewUrl) {
            components.scheme = "macappstore"
            components.query = nil
            if let url = components.url { return url }
        }
        if let trackId { return URL(string: "macappstore://apps.apple.com/app/id\(trackId)") }
        return nil
    }
}

public enum ApplicationsITunes {
    /// Lookup URL for a bundle id. `entity` is `desktopSoftware` (Mac apps) or `macSoftware`.
    public static func lookupURL(bundleID: String, country: String, entity: String = "desktopSoftware") -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: country.lowercased()),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "1"),
        ]
        return components?.url
    }

    public static func decode(_ data: Data) -> [ApplicationsITunesApp] {
        (try? JSONDecoder().decode(ApplicationsITunesLookup.self, from: data))?.results ?? []
    }

    /// An update when the store version is newer and the running macOS can install it.
    /// Only for apps with an App Store receipt (a direct-download build would get false hits).
    public static func update(from result: ApplicationsITunesApp, app: ApplicationsAppInfo,
                              currentOS: String = ApplicationsVersion.currentOS) -> ApplicationsUpdate? {
        guard app.source == .appStore, let version = result.version, !version.isEmpty else { return nil }
        if let id = result.bundleId, id.caseInsensitiveCompare(app.bundleID) != .orderedSame { return nil }
        guard ApplicationsVersion.isNewer(version, than: app.version.isEmpty ? app.build : app.version),
              ApplicationsVersion.osSatisfies(minimum: result.minimumOsVersion, current: currentOS) else { return nil }
        let notes = result.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ApplicationsUpdate(
            appPath: app.path, bundleID: app.bundleID, name: app.name, installedVersion: app.version,
            availableVersion: version, source: .appStore, releaseNotes: notes?.isEmpty == true ? nil : notes,
            storeURL: result.storeURL ?? URL(string: "macappstore://showUpdatesPage"), releaseDate: result.releaseDate,
            downloadSize: result.fileSizeBytes, isMajor: ApplicationsVersion.isMajorUpgrade(from: app.version, to: version),
            minimumSystemVersion: result.minimumOsVersion)
    }
}

// MARK: - Homebrew

/// An installed cask, from `brew info --cask --installed --json=v2`.
public struct ApplicationsCaskInfo: Sendable, Hashable, Codable {
    public var token: String
    public var names: [String]
    /// Installed `.app` file names ("Firefox.app").
    public var appArtifacts: [String]
    public var version: String
    public var installedVersion: String?
    public var autoUpdates: Bool
    public var homepage: String?

    public init(token: String, names: [String] = [], appArtifacts: [String] = [], version: String = "",
                installedVersion: String? = nil, autoUpdates: Bool = false, homepage: String? = nil) {
        self.token = token
        self.names = names
        self.appArtifacts = appArtifacts
        self.version = version
        self.installedVersion = installedVersion
        self.autoUpdates = autoUpdates
        self.homepage = homepage
    }
}

/// An outdated cask, from `brew outdated --cask --greedy --json=v2`.
public struct ApplicationsCaskOutdated: Sendable, Hashable, Codable {
    public var token: String
    public var installedVersions: [String]
    public var currentVersion: String

    public init(token: String, installedVersions: [String], currentVersion: String) {
        self.token = token
        self.installedVersions = installedVersions
        self.currentVersion = currentVersion
    }
}

public enum ApplicationsHomebrew {
    /// Where `brew` lives (Apple silicon, then Intel).
    public static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    public static func parseInfo(_ data: Data) -> [ApplicationsCaskInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap { cask in
            guard let token = cask["token"] as? String else { return nil }
            let names = cask["name"] as? [String] ?? []
            let installed: String?
            if let text = cask["installed"] as? String {
                installed = text
            } else if let list = cask["installed"] as? [String] {
                installed = list.last
            } else {
                installed = nil
            }
            return ApplicationsCaskInfo(
                token: token, names: names, appArtifacts: appArtifacts(cask["artifacts"]),
                version: cask["version"] as? String ?? "", installedVersion: installed,
                autoUpdates: cask["auto_updates"] as? Bool ?? false, homepage: cask["homepage"] as? String)
        }
    }

    /// `.app` names from a cask's `artifacts`: `[{"app": ["Foo.app"]}]` or
    /// `[{"app": ["Foo.app", {"target": "Bar.app"}]}]` (installed as Bar.app).
    static func appArtifacts(_ value: Any?) -> [String] {
        guard let artifacts = value as? [Any] else { return [] }
        var apps: [String] = []
        for artifact in artifacts {
            guard let dict = artifact as? [String: Any], let list = dict["app"] as? [Any] else { continue }
            var pending: String?
            for element in list {
                if let name = element as? String {
                    if let pending { apps.append(pending) }
                    pending = name
                } else if let options = element as? [String: Any], let target = options["target"] as? String {
                    pending = (target as NSString).lastPathComponent
                }
            }
            if let pending { apps.append(pending) }
        }
        return apps.filter { $0.lowercased().hasSuffix(".app") }
    }

    public static func parseOutdated(_ data: Data) -> [ApplicationsCaskOutdated] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap { cask in
            guard let token = cask["name"] as? String ?? cask["token"] as? String,
                  let current = cask["current_version"] as? String else { return nil }
            let installed: [String]
            if let list = cask["installed_versions"] as? [String] {
                installed = list
            } else if let single = cask["installed_versions"] as? String {
                installed = [single]
            } else {
                installed = []
            }
            return ApplicationsCaskOutdated(token: token, installedVersions: installed, currentVersion: current)
        }
    }

    /// Updates for outdated casks, matched to installed apps by artifact file name and
    /// confirmed against the app's real Info.plist version (apps that updated themselves
    /// are not reported).
    public static func updates(outdated: [ApplicationsCaskOutdated], casks: [ApplicationsCaskInfo],
                               apps: [ApplicationsAppInfo]) -> [ApplicationsUpdate] {
        var byFile: [String: ApplicationsAppInfo] = [:]
        for app in apps where !app.isSystem {
            byFile[((app.path as NSString).lastPathComponent).lowercased()] = app
        }
        let infoByToken = Dictionary(casks.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [ApplicationsUpdate] = []
        for entry in outdated {
            guard let info = infoByToken[entry.token],
                  let app = info.appArtifacts.lazy.compactMap({ byFile[$0.lowercased()] }).first,
                  let latest = ApplicationsVersion.splitCaskVersion(entry.currentVersion) else { continue }
            let installed = app.version.isEmpty ? app.build : app.version
            guard ApplicationsVersion.isNewer(latest.version, than: installed)
                    || (latest.build != nil && !app.build.isEmpty && ApplicationsVersion.compare(latest.version, installed) == .orderedSame
                        && ApplicationsVersion.isNewer(latest.build!, than: app.build)) else { continue }
            result.append(ApplicationsUpdate(
                appPath: app.path, bundleID: app.bundleID, name: app.name, installedVersion: installed,
                availableVersion: latest.version, source: .homebrew,
                downloadURL: info.homepage.flatMap(URL.init(string:)), caskToken: entry.token,
                isMajor: ApplicationsVersion.isMajorUpgrade(from: installed, to: latest.version)))
        }
        return result
    }

    /// Maps installed apps (by `.app` file name) to cask tokens.
    public static func caskTokens(casks: [ApplicationsCaskInfo]) -> [String: String] {
        var map: [String: String] = [:]
        for cask in casks {
            for app in cask.appArtifacts { map[app.lowercased()] = cask.token }
        }
        return map
    }
}

// MARK: - Release notes

/// Turns release-note HTML into readable plain text (lists become bullets).
public enum ApplicationsHTMLText {
    public static func plainText(_ html: String) -> String {
        var s = html
        guard s.contains("<") || s.contains("&") else { return collapse(s) }
        for tag in ["script", "style", "head"] {
            while let start = s.range(of: "<\(tag)", options: .caseInsensitive),
                  let end = s.range(of: "</\(tag)>", options: .caseInsensitive, range: start.upperBound..<s.endIndex) {
                s.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        let replacements: [(String, String)] = [
            ("<br>", "\n"), ("<br/>", "\n"), ("<br />", "\n"), ("<li>", "\n• "), ("</p>", "\n\n"), ("</div>", "\n"),
            ("</h1>", "\n\n"), ("</h2>", "\n\n"), ("</h3>", "\n\n"), ("</h4>", "\n\n"), ("</ul>", "\n"), ("</ol>", "\n"),
            ("</tr>", "\n"),
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        // <li class="x"> and other attributed list items.
        s = s.replacingOccurrences(of: "<li [^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        return collapse(s)
    }

    static func decodeEntities(_ text: String) -> String {
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
            "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "bull": "•", "copy": "©",
            "reg": "®", "trade": "™",
        ]
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "&", let semi = text[index...].prefix(12).firstIndex(of: ";") {
                let name = String(text[text.index(after: index)..<semi])
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst(), radix: 10).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
                } else {
                    decoded = named[name.lowercased()]
                }
                if let decoded {
                    result += decoded
                    index = text.index(after: semi)
                    continue
                }
            }
            result.append(ch)
            index = text.index(after: index)
        }
        return result
    }

    static func collapse(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        var blank = 0
        for line in lines {
            if line.isEmpty {
                blank += 1
                if blank == 1 && !out.isEmpty { out.append("") }
            } else {
                blank = 0
                out.append(line)
            }
        }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n")
    }
}
