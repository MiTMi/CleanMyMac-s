import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One `<item>` of a Sparkle appcast.
public struct ApplicationsAppcastItem: Sendable, Hashable, Codable {
    public var title: String?
    /// `sparkle:version` — the build, compared with `CFBundleVersion`.
    public var version: String?
    /// `sparkle:shortVersionString` — shown to people.
    public var shortVersion: String?
    public var minimumSystemVersion: String?
    public var maximumSystemVersion: String?
    public var minimumAutoupdateVersion: String?
    /// `sparkle:channel`; nil means the default (release) channel.
    public var channel: String?
    public var hardwareRequirements: [String]
    public var isCritical: Bool
    /// `sparkle:informationalUpdate`: no download, only a link.
    public var isInformational: Bool
    /// Release notes embedded in `<description>` (HTML or plain text).
    public var descriptionText: String?
    public var releaseNotesLink: String?
    public var fullReleaseNotesLink: String?
    public var link: String?
    public var pubDate: Date?
    public var enclosureURL: String?
    public var enclosureLength: Int64?
    public var enclosureOS: String?

    public init(title: String? = nil, version: String? = nil, shortVersion: String? = nil, minimumSystemVersion: String? = nil,
                maximumSystemVersion: String? = nil, minimumAutoupdateVersion: String? = nil, channel: String? = nil,
                hardwareRequirements: [String] = [], isCritical: Bool = false, isInformational: Bool = false,
                descriptionText: String? = nil, releaseNotesLink: String? = nil, fullReleaseNotesLink: String? = nil,
                link: String? = nil, pubDate: Date? = nil, enclosureURL: String? = nil, enclosureLength: Int64? = nil,
                enclosureOS: String? = nil) {
        self.title = title
        self.version = version
        self.shortVersion = shortVersion
        self.minimumSystemVersion = minimumSystemVersion
        self.maximumSystemVersion = maximumSystemVersion
        self.minimumAutoupdateVersion = minimumAutoupdateVersion
        self.channel = channel
        self.hardwareRequirements = hardwareRequirements
        self.isCritical = isCritical
        self.isInformational = isInformational
        self.descriptionText = descriptionText
        self.releaseNotesLink = releaseNotesLink
        self.fullReleaseNotesLink = fullReleaseNotesLink
        self.link = link
        self.pubDate = pubDate
        self.enclosureURL = enclosureURL
        self.enclosureLength = enclosureLength
        self.enclosureOS = enclosureOS
    }

    /// The version people see: short version, else build, else the title's version.
    public var displayVersion: String {
        if let shortVersion, !shortVersion.isEmpty { return shortVersion }
        if let version, !version.isEmpty { return version }
        return title ?? ""
    }

    /// True for items on a non-release channel or with a pre-release-looking version.
    public var isPrerelease: Bool {
        if let channel, !channel.isEmpty, channel.lowercased() != "release" { return true }
        return ApplicationsVersion.isPrerelease(displayVersion)
    }
}

/// Parses Sparkle appcasts and picks the best update for the running Mac.
public enum ApplicationsAppcast {

    public static func parse(_ data: Data) -> [ApplicationsAppcastItem] {
        let delegate = ApplicationsAppcastParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.items
    }

    /// The newest item the running Mac can install, or nil.
    ///
    /// Skips items requiring a newer (or older) macOS, items for other hardware, informational
    /// non-release builds, non-macOS enclosures and — unless `includePrereleases` — beta channels.
    public static func bestItem(_ items: [ApplicationsAppcastItem], currentOS: String = ApplicationsVersion.currentOS,
                                isAppleSilicon: Bool = true, includePrereleases: Bool = false) -> ApplicationsAppcastItem? {
        let eligible = items.filter { item in
            if !includePrereleases && item.isPrerelease { return false }
            if !ApplicationsVersion.osSatisfies(minimum: item.minimumSystemVersion, current: currentOS) { return false }
            if !ApplicationsVersion.osSatisfies(maximum: item.maximumSystemVersion, current: currentOS) { return false }
            if let os = item.enclosureOS?.lowercased(), !os.isEmpty, os != "macos", os != "osx" { return false }
            if item.hardwareRequirements.contains(where: { $0.lowercased() == "arm64" }) && !isAppleSilicon { return false }
            if item.version == nil && item.shortVersion == nil { return false }
            return true
        }
        return eligible.max { lhs, rhs in
            let l = lhs.version ?? lhs.displayVersion
            let r = rhs.version ?? rhs.displayVersion
            let byBuild = ApplicationsVersion.compare(l, r)
            if byBuild != .orderedSame { return byBuild == .orderedAscending }
            return ApplicationsVersion.compare(lhs.displayVersion, rhs.displayVersion) == .orderedAscending
        }
    }

    /// RFC 822 dates as used in RSS ("Tue, 10 Sep 2024 14:03:00 +0000").
    public static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z",
                       "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm Z", "yyyy-MM-dd'T'HH:mm:ssZ",
                       "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}

/// XMLParser delegate collecting appcast items. Element names are matched by their local
/// part, so any namespace prefix bound to Sparkle's namespace works.
final class ApplicationsAppcastParserDelegate: NSObject, XMLParserDelegate {
    private(set) var items: [ApplicationsAppcastItem] = []
    private var current: ApplicationsAppcastItem?
    private var text = ""
    private var depthInItem = 0
    /// Depth of the open `<description>` element, while inside it.
    private var descriptionDepth: Int?

    private static func local(_ qualified: String) -> (prefix: String?, name: String) {
        if let colon = qualified.firstIndex(of: ":") {
            return (String(qualified[..<colon]), String(qualified[qualified.index(after: colon)...]))
        }
        return (nil, qualified)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let (prefix, name) = Self.local(elementName)
        if let descriptionDepth, current != nil, depthInItem >= descriptionDepth {
            // Un-escaped HTML inside <description>: keep the markup as text.
            depthInItem += 1
            text += "<\(elementName)>"
            return
        }
        text = ""
        if name == "item" && current == nil {
            current = ApplicationsAppcastItem()
            depthInItem = 0
            return
        }
        guard current != nil else { return }
        depthInItem += 1
        if name == "description" && prefix == nil {
            descriptionDepth = depthInItem
        }
        if name == "enclosure" {
            applyEnclosure(attributeDict)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let (prefix, name) = Self.local(elementName)
        guard current != nil else { return }
        if let descriptionDepth, depthInItem > descriptionDepth {
            depthInItem -= 1
            text += "</\(elementName)>"
            return
        }
        if name == "item" && depthInItem == 0 {
            if let item = current { items.append(item) }
            current = nil
            return
        }
        depthInItem = max(0, depthInItem - 1)
        if name == "description" && prefix == nil { descriptionDepth = nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        switch name {
        case "title": if prefix == nil { current?.title = value }
        case "link": if prefix == nil { current?.link = value }
        case "pubDate": current?.pubDate = ApplicationsAppcast.parseDate(value)
        case "description": if prefix == nil, !value.isEmpty { current?.descriptionText = value }
        case "version": if prefix != nil, !value.isEmpty { current?.version = value }
        case "shortVersionString": if !value.isEmpty { current?.shortVersion = value }
        case "minimumSystemVersion": if !value.isEmpty { current?.minimumSystemVersion = value }
        case "maximumSystemVersion": if !value.isEmpty { current?.maximumSystemVersion = value }
        case "minimumAutoupdateVersion": if !value.isEmpty { current?.minimumAutoupdateVersion = value }
        case "channel": if prefix != nil, !value.isEmpty { current?.channel = value }
        case "hardwareRequirements":
            current?.hardwareRequirements = value.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        case "criticalUpdate": current?.isCritical = true
        case "informationalUpdate": current?.isInformational = true
        case "releaseNotesLink": if !value.isEmpty { current?.releaseNotesLink = value }
        case "fullReleaseNotesLink": if !value.isEmpty { current?.fullReleaseNotesLink = value }
        default: break
        }
    }

    private func applyEnclosure(_ attributes: [String: String]) {
        var byLocal: [String: String] = [:]
        for (key, value) in attributes { byLocal[Self.local(key).name] = value }
        let os = byLocal["os"]
        // Prefer a macOS enclosure when an item lists several.
        if current?.enclosureURL != nil, let os, os.lowercased() != "macos" { return }
        if let url = byLocal["url"] { current?.enclosureURL = url }
        if let length = byLocal["length"], let bytes = Int64(length) { current?.enclosureLength = bytes }
        current?.enclosureOS = os
        if current?.version == nil, let version = byLocal["version"], !version.isEmpty { current?.version = version }
        if current?.shortVersion == nil, let short = byLocal["shortVersionString"], !short.isEmpty { current?.shortVersion = short }
    }
}
