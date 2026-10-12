import AppKit
import CoreServices
import Foundation
import Security
import SpruceCore

/// Finds installed apps and reads their metadata.
struct ApplicationsCatalogReader {
    let home: String

    init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    /// Vendors whose security, VPN or management suites must be removed with their own uninstaller.
    static let vendorUninstallerPrefixes = [
        "com.crowdstrike.", "com.sentinelone.", "com.eset.", "com.jamf", "com.jamfsoftware.", "com.paloaltonetworks.",
        "com.cisco.secureclient", "com.cisco.anyconnect", "com.microsoft.wdav", "com.sophos.", "com.kaspersky.",
        "com.bitdefender.", "com.trendmicro.", "com.mcafee.", "com.symantec.", "com.norton.", "com.avast.", "com.avg.",
        "com.webroot.", "com.carbonblack.", "com.vmware.carbonblack", "com.tanium.", "io.kandji.", "com.kandji.",
        "com.mosyle.", "com.addigy.", "com.zscaler.", "com.netskope.", "com.forcepoint.", "com.f-secure.",
    ]

    // MARK: Discovery

    /// `.app` bundles in /Applications (and one level of sub-folders), ~/Applications (same),
    /// and macOS's own apps (marked as system).
    func bundlePaths() -> [(path: String, isSystem: Bool)] {
        var result: [(String, Bool)] = []
        var seen = Set<String>()
        func add(_ path: String, system: Bool) {
            let key = (path as NSString).standardizingPath.lowercased()
            guard seen.insert(key).inserted else { return }
            result.append((path, system))
        }
        func scan(_ folder: String, depth: Int, system: Bool) {
            for child in DiskUsage.children(of: folder, includeHidden: false) {
                guard let entry = FileWalker.entry(at: child) else { continue }
                let isApp = child.lowercased().hasSuffix(".app")
                if entry.isSymlink {
                    // /Applications/Safari.app points into Apple's cryptex: a system app.
                    guard isApp else { continue }
                    let resolved = (child as NSString).resolvingSymlinksInPath
                    if resolved.hasPrefix("/System/") { add(child, system: true) }
                    continue
                }
                guard entry.isDirectory else { continue }
                if isApp {
                    add(child, system: system || child.hasPrefix("/System/"))
                } else if depth > 0 {
                    scan(child, depth: depth - 1, system: system)
                }
            }
        }
        scan("/Applications", depth: 1, system: false)
        scan((home as NSString).appendingPathComponent("Applications"), depth: 1, system: false)
        scan("/System/Applications", depth: 1, system: true)
        return result
    }

    // MARK: Metadata

    struct Context {
        var runningPaths: Set<String>
        var runningBundleIDs: Set<String>
        /// `.app` file name (lowercased) → Homebrew cask token.
        var caskTokens: [String: String]
        var ownBundlePath: String
        var ownBundleID: String?
    }

    /// Reads one app. `measure` returns the bundle's allocated size (nil skips measuring).
    func readApp(path: String, isSystem: Bool, context: Context, measure: ((String, String, String) -> Int64)?) -> ApplicationsAppInfo? {
        let fm = FileManager.default
        let contents = (path as NSString).appendingPathComponent("Contents")
        var plistPath = (contents as NSString).appendingPathComponent("Info.plist")
        var isWrappedIOS = false
        if !fm.fileExists(atPath: plistPath) {
            // iPhone/iPad apps on Apple silicon: Foo.app/WrappedBundle → Wrapper/Foo.app
            let wrapped = (path as NSString).appendingPathComponent("WrappedBundle/Info.plist")
            guard fm.fileExists(atPath: wrapped) else { return nil }
            plistPath = wrapped
            isWrappedIOS = true
        }
        guard let plist = ApplicationsPlist.dictionary(atPath: plistPath) else { return nil }
        let bundleID = (plist["CFBundleIdentifier"] as? String) ?? ""
        if (path as NSString).standardizingPath == context.ownBundlePath { return nil }
        if let own = context.ownBundleID, !bundleID.isEmpty, bundleID == own, !isSystem { return nil }

        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var displayName = fm.displayName(atPath: path)
        if displayName.lowercased().hasSuffix(".app") { displayName = String(displayName.dropLast(4)) }
        if displayName.isEmpty { displayName = fileName }
        let names = [fileName, plist["CFBundleName"] as? String, plist["CFBundleDisplayName"] as? String]
            .compactMap { $0 }.filter { !$0.isEmpty }

        let version = (plist["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let build = (plist["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let executable = plist["CFBundleExecutable"] as? String
        let executablePath: String? = executable.map {
            isWrappedIOS
                ? (path as NSString).appendingPathComponent("WrappedBundle/\($0)")
                : (contents as NSString).appendingPathComponent("MacOS/\($0)")
        }
        let architecture = executablePath.flatMap(ApplicationsMachO.cpus(atPath:)).map(ApplicationsArchitecture.from) ?? .unknown

        var source: ApplicationsAppSource = .other
        let lowerPath = path.lowercased()
        if fm.fileExists(atPath: (contents as NSString).appendingPathComponent("_MASReceipt/receipt"))
            || fm.fileExists(atPath: (path as NSString).appendingPathComponent("Wrapper/iTunesMetadata.plist")) {
            source = .appStore
        } else if lowerPath.contains("/applications/setapp/") || bundleID.lowercased().hasSuffix("-setapp") {
            source = .setapp
        } else if let token = context.caskTokens[(path as NSString).lastPathComponent.lowercased()], !token.isEmpty {
            source = .homebrew
        } else if isSteamLauncher(contents: contents) {
            source = .steam
        }

        var feed = (plist["SUFeedURL"] as? String) ?? (plist["SUFeedUrl"] as? String)
        feed = feed?.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \n"))
        if feed?.isEmpty == true { feed = nil }
        if feed == nil, fm.fileExists(atPath: (contents as NSString).appendingPathComponent("Frameworks/DevMateKit.framework")),
           !bundleID.isEmpty {
            feed = "https://updates.devmate.com/\(bundleID).xml"
        }
        if source == .setapp || source == .appStore { feed = nil }

        let signing = Self.signingInfo(path: path)
        let vendor = ApplicationsVendorName.derive(certificateSummary: signing.certificateSummary, bundleID: bundleID)
        let dates = Self.spotlightDates(path: path)
        let standardized = (path as NSString).standardizingPath
        let running = context.runningPaths.contains(standardized)
            || (!bundleID.isEmpty && context.runningBundleIDs.contains(bundleID.lowercased()) && !isSystem)
        let size = measure?(path, version, build) ?? 0
        let lowerID = bundleID.lowercased()

        return ApplicationsAppInfo(
            path: path, name: displayName, bundleID: bundleID, version: version.isEmpty ? build : version, build: build,
            executableName: executable, vendor: vendor, teamID: signing.teamID, architecture: architecture, source: source,
            isSystem: isSystem, size: size, lastUsed: dates.lastUsed, dateAdded: dates.added, isRunning: running,
            sparkleFeedURL: feed, caskToken: context.caskTokens[(path as NSString).lastPathComponent.lowercased()],
            prefersVendorUninstaller: Self.vendorUninstallerPrefixes.contains { lowerID.hasPrefix($0) },
            appGroups: signing.appGroups, embeddedBundleIDs: isSystem ? [] : Self.embeddedBundleIDs(contents: contents),
            names: names)
    }

    private func isSteamLauncher(contents: String) -> Bool {
        let script = (contents as NSString).appendingPathComponent("MacOS/run.sh")
        guard let handle = FileHandle(forReadingAtPath: script) else { return false }
        defer { try? handle.close() }
        let head = String(decoding: handle.readData(ofLength: 4096), as: UTF8.self)
        return head.contains("steam://run/")
    }

    // MARK: Spotlight

    /// `kMDItemLastUsedDate` and `kMDItemDateAdded` from the Spotlight index.
    static func spotlightDates(path: String) -> (lastUsed: Date?, added: Date?) {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return (nil, nil) }
        let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        let added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        return (lastUsed, added)
    }

    // MARK: Code signing

    struct SigningInfo {
        var teamID: String?
        var certificateSummary: String?
        var appGroups: [String]
    }

    /// Team id, leaf certificate summary and app-group entitlements (signature not validated).
    static func signingInfo(path: String) -> SigningInfo {
        var result = SigningInfo(teamID: nil, certificateSummary: nil, appGroups: [])
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let code = staticCode else { return result }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any] else { return result }
        result.teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        if let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first {
            result.certificateSummary = SecCertificateCopySubjectSummary(leaf) as String?
        }
        if let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
           let groups = entitlements["com.apple.security.application-groups"] as? [String] {
            result.appGroups = groups
        }
        return result
    }

    // MARK: Embedded bundles

    /// Bundle ids of login items, XPC services, helpers, app extensions and privileged helpers
    /// shipped inside the app.
    static func embeddedBundleIDs(contents: String) -> [String] {
        let fm = FileManager.default
        var ids: [String] = []
        let folders = ["Library/LoginItems", "XPCServices", "PlugIns", "Helpers", "Frameworks", "Library/LaunchServices",
                       "Library/SystemExtensions"]
        for folder in folders {
            let dir = (contents as NSString).appendingPathComponent(folder)
            guard let children = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for child in children {
                let childPath = (dir as NSString).appendingPathComponent(child)
                let ext = (child as NSString).pathExtension.lowercased()
                if ["app", "xpc", "appex", "systemextension"].contains(ext) {
                    let plist = ApplicationsPlist.dictionary(atPath: (childPath as NSString).appendingPathComponent("Contents/Info.plist"))
                    if let id = plist?["CFBundleIdentifier"] as? String, !id.isEmpty { ids.append(id) }
                } else if folder == "Library/LaunchServices", ApplicationsTokens.isReverseDNS(child) {
                    // Privileged helper tools are named after their label.
                    ids.append(child)
                }
            }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: Homebrew casks (file-based, no brew run needed)

    /// `.app` file name (lowercased) → cask token, read from Caskroom metadata.
    static func caskTokensFromCaskroom() -> [String: String] {
        let fm = FileManager.default
        var map: [String: String] = [:]
        for caskroom in ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"] {
            guard let tokens = try? fm.contentsOfDirectory(atPath: caskroom) else { continue }
            for token in tokens where !token.hasPrefix(".") {
                let metadata = (caskroom as NSString).appendingPathComponent("\(token)/.metadata")
                guard let versions = try? fm.contentsOfDirectory(atPath: metadata) else { continue }
                var newest: (date: Date, path: String)?
                for version in versions where !version.hasPrefix(".") {
                    let versionDir = (metadata as NSString).appendingPathComponent(version)
                    guard let stamps = try? fm.contentsOfDirectory(atPath: versionDir) else { continue }
                    for stamp in stamps where !stamp.hasPrefix(".") {
                        let json = (versionDir as NSString).appendingPathComponent("\(stamp)/Casks/\(token).json")
                        guard let modified = FileWalker.entry(at: json)?.modified else { continue }
                        if newest == nil || modified > newest!.date { newest = (modified, json) }
                    }
                }
                guard let newest, let data = fm.contents(atPath: newest.path),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let wrapped = try? JSONSerialization.data(withJSONObject: ["casks": [object]]) else { continue }
                for cask in ApplicationsHomebrew.parseInfo(wrapped) {
                    for app in cask.appArtifacts { map[app.lowercased()] = token }
                }
            }
        }
        return map
    }
}
