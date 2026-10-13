import Foundation

/// Bundle ids, app groups and team ids of everything installed — used to decide whether a
/// Library entry still has an owner.
public struct ApplicationsInstalledIndex: Sendable {
    public private(set) var bundleIDs: Set<String> = []
    /// Every dot-boundary prefix of every installed id ("com.foo.bar.baz" → "com.foo.bar", "com.foo").
    public private(set) var bundleIDPrefixes: Set<String> = []
    public private(set) var appGroups: Set<String> = []
    public private(set) var teamIDs: Set<String> = []
    /// `tld.vendor` of installed ids, to explain "another app from this developer is installed".
    public private(set) var vendorPrefixes: [String: String] = [:]

    public init(identities: [ApplicationsAppIdentity], extraBundleIDs: [String] = []) {
        for identity in identities {
            for id in identity.allBundleIDs { add(id, appName: identity.names.first) }
            for group in identity.appGroups {
                let lower = group.lowercased()
                appGroups.insert(lower)
                if lower.hasPrefix("group.") { appGroups.insert(String(lower.dropFirst("group.".count))) }
                // "TEAMID.com.foo.shared" → also "com.foo.shared"
                if let dot = group.firstIndex(of: "."), ApplicationsTokens.isTeamID(String(group[..<dot])) {
                    appGroups.insert(String(group[group.index(after: dot)...]).lowercased())
                }
            }
            if let team = identity.teamID, !team.isEmpty { teamIDs.insert(team) }
        }
        for id in extraBundleIDs { add(id.lowercased(), appName: nil) }
    }

    private mutating func add(_ id: String, appName: String?) {
        let lower = id.lowercased()
        guard !lower.isEmpty else { return }
        bundleIDs.insert(lower)
        let parts = lower.split(separator: ".")
        if parts.count > 1 {
            for length in 1..<parts.count {
                bundleIDPrefixes.insert(parts.prefix(length).joined(separator: "."))
            }
        }
        if parts.count >= 3, let appName, ApplicationsVendorName.genericTLDs.contains(String(parts[0])) {
            let vendor = parts.prefix(2).joined(separator: ".")
            if vendorPrefixes[vendor] == nil { vendorPrefixes[vendor] = appName }
        }
    }

    /// True when an installed app (or one of its helpers or groups) owns `ownerKey`.
    public func owns(ownerKey: String, teamID: String? = nil) -> Bool {
        let key = ownerKey.lowercased()
        if bundleIDs.contains(key) || bundleIDPrefixes.contains(key) { return true }
        // An installed id is a dot-prefix of the key (com.foo.app → com.foo.app.helper).
        let parts = key.split(separator: ".")
        if parts.count > 1 {
            for length in 1..<parts.count where bundleIDs.contains(parts.prefix(length).joined(separator: ".")) {
                return true
            }
        }
        if appGroups.contains(key) || appGroups.contains("group." + key) { return true }
        if let teamID, teamIDs.contains(teamID) { return true }
        return false
    }

    /// The name of an installed app from the same developer, if any.
    public func sameVendorApp(ownerKey: String) -> String? {
        let parts = ownerKey.lowercased().split(separator: ".")
        guard parts.count >= 3 else { return nil }
        return vendorPrefixes[parts.prefix(2).joined(separator: ".")]
    }
}

/// One file of a removed app.
public struct ApplicationsOrphanEntry: Sendable, Hashable, Codable {
    public var path: String
    public var kind: ApplicationsComponentKind
    /// A launch agent whose program no longer exists.
    public var isBrokenLaunchJob: Bool
    public var modified: Date?

    public init(path: String, kind: ApplicationsComponentKind, isBrokenLaunchJob: Bool = false, modified: Date? = nil) {
        self.path = path
        self.kind = kind
        self.isBrokenLaunchJob = isBrokenLaunchJob
        self.modified = modified
    }
}

/// All files left by one removed app (one owner bundle id).
public struct ApplicationsOrphanGroup: Sendable, Hashable, Identifiable, Codable {
    public var id: String { ownerKey.lowercased() }
    public var ownerKey: String
    public var displayName: String
    public var entries: [ApplicationsOrphanEntry]
    /// Name of an installed app from the same developer (it may still use these files).
    public var sameVendorApp: String?

    public init(ownerKey: String, displayName: String, entries: [ApplicationsOrphanEntry] = [], sameVendorApp: String? = nil) {
        self.ownerKey = ownerKey
        self.displayName = displayName
        self.entries = entries
        self.sameVendorApp = sameVendorApp
    }

    public var note: String {
        var text = "Files named after \(ownerKey). No installed app uses this identifier, so the app was probably removed. Spruce can't be certain — check before removing."
        if let sameVendorApp {
            text += " \(sameVendorApp) is from the same developer and might still use them."
        }
        if entries.contains(where: \.isBrokenLaunchJob) {
            text += " Includes a launch agent whose program no longer exists."
        }
        return text
    }
}

/// Finds files in the user's Library that belong to apps that are no longer installed.
///
/// Review-only and deliberately narrow: only reverse-DNS names (bundle-id-like) are
/// considered, Apple and shared runtime/updater ids are excluded, anything an installed
/// app, helper, group or team could own is skipped, recently modified entries are skipped
/// (something is still writing to them), and launch agents count only when broken.
public struct ApplicationsOrphanDetector {
    public var roots: [ApplicationsSearchRoot]
    public var listDirectory: (String) -> [String]
    public var modificationDate: (String) -> Date?
    public var readLaunchJob: (String) -> ApplicationsLaunchJob?
    public var fileExists: (String) -> Bool
    /// Entries modified more recently than this are still in use by something.
    public var minimumAge: TimeInterval

    public init(roots: [ApplicationsSearchRoot] = ApplicationsLeftoverCatalog.orphanRoots(),
                listDirectory: @escaping (String) -> [String] = ApplicationsLeftoverMatcher.defaultList,
                modificationDate: @escaping (String) -> Date? = { FileWalker.entry(at: $0)?.modified },
                readLaunchJob: @escaping (String) -> ApplicationsLaunchJob? = ApplicationsLaunchJob.read(atPath:),
                fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                minimumAge: TimeInterval = 86_400) {
        self.roots = roots
        self.listDirectory = listDirectory
        self.modificationDate = modificationDate
        self.readLaunchJob = readLaunchJob
        self.fileExists = fileExists
        self.minimumAge = minimumAge
    }

    /// Identifier prefixes never reported: Apple, and shared runtimes, SDKs and updaters
    /// whose owner app lives outside the Applications folders.
    public static let excludedPrefixes: [String] = [
        "com.apple.", "apple.", "systemgroup.", "com.google.keystone", "com.google.googleupdater",
        "com.google.softwareupdate", "com.microsoft.autoupdate", "com.microsoft.office", "com.microsoft.oneauth",
        "com.microsoft.identity", "com.microsoft.errorreporting", "org.sparkle-project.", "com.crashlytics",
        "io.sentry", "com.plausiblelabs.", "com.squirrel.", "com.github.electron", "com.electron.", "org.chromium.",
        "com.adobe.acc", "com.adobe.ccx", "com.adobe.agsservice", "com.adobe.adobeupdate", "com.adobe.arm",
        "com.adobe.crashreporter", "homebrew.", "org.homebrew.", "org.mozilla.updater", "org.openjdk.",
        "com.oracle.java", "net.java.", "org.python.", "com.openssh.", "org.gpgtools.", "com.mozilla.updater",
        "com.spotify.webhelper", "com.facebook.sdk", "com.firebase.", "com.google.firebase", "com.segment.",
        "com.amplitude.", "com.bugsnag.", "com.hockeyapp.", "net.hockeyapp.", "com.instabug.",
    ]

    public static func isExcluded(_ ownerKey: String) -> Bool {
        let lower = ownerKey.lowercased()
        return excludedPrefixes.contains { lower.hasPrefix($0) || lower == $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
    }

    public func detect(index: ApplicationsInstalledIndex, now: Date = Date()) -> [ApplicationsOrphanGroup] {
        var groups: [String: ApplicationsOrphanGroup] = [:]
        for root in roots {
            for name in listDirectory(root.path) where !name.hasPrefix(".") {
                let path = (root.path as NSString).appendingPathComponent(name)
                guard let owner = ApplicationsTokens.ownerKey(fromEntryName: name) else { continue }
                if Self.isExcluded(owner.key) || index.owns(ownerKey: owner.key, teamID: owner.teamID) { continue }

                var broken = false
                if root.modes.contains(.launchJobs) {
                    guard name.lowercased().hasSuffix(".plist"), let job = readLaunchJob(path),
                          job.isBroken(fileExists: fileExists) else { continue }
                    if let label = job.label, index.owns(ownerKey: label) { continue }
                    broken = true
                }
                let modified = modificationDate(path)
                if !broken, let modified, now.timeIntervalSince(modified) < minimumAge { continue }

                let key = owner.key.lowercased()
                var group = groups[key] ?? ApplicationsOrphanGroup(
                    ownerKey: owner.key, displayName: ApplicationsTokens.displayName(forOwnerKey: owner.key),
                    sameVendorApp: index.sameVendorApp(ownerKey: owner.key))
                group.entries.append(ApplicationsOrphanEntry(path: path, kind: root.kind, isBrokenLaunchJob: broken, modified: modified))
                groups[key] = group
            }
        }
        return groups.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
