import Foundation

// Shared value types of the Protection module (Malware Removal, Privacy, App Permissions).
// Foundation-only so the scanners are unit-testable on Linux.

// MARK: - Scan depth

/// How much of the disk a malware scan walks. Stored in `SpruceSettings.scanDepth`.
public enum ProtectionScanDepth: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Startup items, helper tools, browser policies, cron and known threat locations.
    case quick
    /// Quick + applications, Application Support folders, shared and temporary folders.
    case balanced
    /// Balanced + every executable and installer in the home folder.
    case deep

    public var id: String { rawValue }

    /// Parses the persisted setting; unknown values fall back to `.balanced`.
    public init(setting: String) {
        self = ProtectionScanDepth(rawValue: setting.lowercased()) ?? .balanced
    }

    public var title: String {
        switch self {
        case .quick: return "Quick"
        case .balanced: return "Balanced"
        case .deep: return "Deep"
        }
    }

    public var speed: String {
        switch self {
        case .quick: return "About a minute"
        case .balanced: return "A few minutes"
        case .deep: return "Can take a while"
        }
    }

    public var coverage: String {
        switch self {
        case .quick: return "Startup items, helper tools, browser policies and known threat locations."
        case .balanced: return "Quick, plus apps, Application Support folders and shared or temporary folders."
        case .deep: return "Balanced, plus every program, script and installer in your home folder."
        }
    }

    public var purpose: String {
        switch self {
        case .quick: return "Fast triage of how threats usually stay on a Mac."
        case .balanced: return "Recommended for regular checks."
        case .deep: return "A thorough sweep, worth running about once a month."
        }
    }

    /// Minimum heuristic score reported at this depth (known threats are always reported).
    public var heuristicThreshold: Int {
        switch self {
        case .quick, .balanced: return 50
        case .deep: return 35
        }
    }
}

// MARK: - Threat classification

/// How serious a finding is.
public enum ThreatSeverity: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    public static func < (lhs: ThreatSeverity, rhs: ThreatSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    /// Heuristic findings derive their severity from the score.
    public static func fromScore(_ score: Int) -> ThreatSeverity {
        if score >= 80 { return .high }
        if score >= 50 { return .medium }
        return .low
    }
}

/// What kind of threat a finding is.
public enum ThreatCategory: String, Codable, Sendable, CaseIterable {
    case adware
    case browserHijacker
    case pua
    case stealer
    case backdoor
    case spyware
    case trojan
    case dropper
    case miner
    case ransomware
    case suspicious

    public var title: String {
        switch self {
        case .adware: return "Adware"
        case .browserHijacker: return "Browser hijacker"
        case .pua: return "Potentially unwanted app"
        case .stealer: return "Password stealer"
        case .backdoor: return "Backdoor"
        case .spyware: return "Spyware"
        case .trojan: return "Trojan"
        case .dropper: return "Malware installer"
        case .miner: return "Cryptominer"
        case .ransomware: return "Ransomware"
        case .suspicious: return "Suspicious item"
        }
    }

    /// SF Symbol for rows and badges.
    public var symbol: String {
        switch self {
        case .adware: return "megaphone.fill"
        case .browserHijacker: return "safari.fill"
        case .pua: return "questionmark.app.fill"
        case .stealer: return "key.fill"
        case .backdoor: return "door.left.hand.open"
        case .spyware: return "eye.fill"
        case .trojan: return "ladybug.fill"
        case .dropper: return "shippingbox.fill"
        case .miner: return "cpu.fill"
        case .ransomware: return "lock.doc.fill"
        case .suspicious: return "exclamationmark.triangle.fill"
        }
    }
}

/// Why something was flagged.
public enum ThreatEvidence: String, Codable, Sendable {
    /// Matched a documented indicator (path, launch label, bundle id, team id).
    case knownIndicator
    /// File content matched a known SHA-256.
    case knownHash
    /// Scored by behavioural heuristics only.
    case heuristic

    public var label: String {
        switch self {
        case .knownIndicator: return "Known threat"
        case .knownHash: return "Known malicious file"
        case .heuristic: return "Suspicious behaviour"
        }
    }
}

/// What sort of object a finding points at.
public enum ProtectionItemKind: String, Codable, Sendable {
    case launchAgent
    case launchDaemon
    case privilegedHelper
    case application
    case executable
    case script
    case installer
    case browserExtension
    case browserPolicy
    case cronJob
    case periodicScript
    case file
    case folder

    public var title: String {
        switch self {
        case .launchAgent: return "Launch agent"
        case .launchDaemon: return "Launch daemon"
        case .privilegedHelper: return "Privileged helper"
        case .application: return "Application"
        case .executable: return "Program"
        case .script: return "Script"
        case .installer: return "Installer"
        case .browserExtension: return "Browser extension"
        case .browserPolicy: return "Browser policy"
        case .cronJob: return "Scheduled job (cron)"
        case .periodicScript: return "Periodic script"
        case .file: return "File"
        case .folder: return "Folder"
        }
    }

    public var symbol: String {
        switch self {
        case .launchAgent, .launchDaemon: return "bolt.horizontal.circle"
        case .privilegedHelper: return "lock.shield"
        case .application: return "app.badge"
        case .executable: return "terminal"
        case .script: return "scroll"
        case .installer: return "shippingbox"
        case .browserExtension: return "puzzlepiece.extension"
        case .browserPolicy: return "doc.badge.gearshape"
        case .cronJob, .periodicScript: return "clock.arrow.2.circlepath"
        case .file: return "doc"
        case .folder: return "folder"
        }
    }
}

/// The launchd domain a job is loaded into.
public enum ProtectionLaunchDomain: String, Codable, Sendable {
    /// The logged-in user's GUI domain (`gui/<uid>`): all launch agents.
    case user
    /// The system domain: launch daemons (needs administrator rights to unload).
    case system
}

// MARK: - Code signing

/// Code-signing state of a file, filled in by the macOS layer (Security framework).
public struct ProtectionSigningInfo: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable {
        /// Not code (data file) or could not be evaluated.
        case unknown
        case unsigned
        /// Signed without an identity (ad-hoc / linker-signed).
        case adHoc
        /// A signature exists but does not validate (modified after signing).
        case invalid
        /// Valid signature from a developer identity.
        case signed
        /// Valid signature anchored to Apple (system or Apple apps).
        case apple
    }

    public var status: Status
    public var teamID: String?
    public var identifier: String?
    /// Common name of the leaf certificate ("Developer ID Application: …"), when known.
    public var authority: String?

    public init(status: Status, teamID: String? = nil, identifier: String? = nil, authority: String? = nil) {
        self.status = status
        self.teamID = teamID
        self.identifier = identifier
        self.authority = authority
    }

    public static let unknown = ProtectionSigningInfo(status: .unknown)

    /// Short human description ("Unsigned", "Ad-hoc signed", "Signed · Team ABCDE12345").
    public var summary: String {
        switch status {
        case .unknown: return "Signature not checked"
        case .unsigned: return "Unsigned"
        case .adHoc: return "Ad-hoc signed (no developer identity)"
        case .invalid: return "Invalid signature (modified after signing)"
        case .signed:
            if let authority, !authority.isEmpty { return authority }
            if let teamID { return "Signed · Team \(teamID)" }
            return "Signed"
        case .apple: return "Signed by Apple"
        }
    }

    /// Signed with a developer identity or by Apple.
    public var isTrustedIdentity: Bool { status == .signed || status == .apple }
}

// MARK: - Findings

/// One detected threat or suspicious item.
public struct ProtectionThreatFinding: Identifiable, Codable, Sendable, Hashable {
    /// Stable id: the standardized primary path (or "cron:<line>" for cron jobs).
    public var id: String
    /// Display name (file, app or job name).
    public var name: String
    /// Known family name ("Adload"), nil for heuristic findings.
    public var family: String?
    public var category: ThreatCategory
    public var severity: ThreatSeverity
    public var evidence: ThreatEvidence
    /// Human-readable reasons, strongest first.
    public var reasons: [String]
    public var kind: ProtectionItemKind
    /// The item to remove (plist, app bundle, file…). Nil for cron jobs.
    public var path: String?
    /// Additional items removed together with `path` (e.g. the program a launch agent runs).
    public var relatedPaths: [String]
    public var launchLabel: String?
    public var launchDomain: ProtectionLaunchDomain?
    /// Signing state of the executable behind the finding.
    public var signing: ProtectionSigningInfo?
    public var sha256: String?
    /// Heuristic score (0 for pure indicator matches).
    public var score: Int
    /// Exact crontab line for cron findings.
    public var cronLine: String?
    /// Allocated bytes of `path` + `relatedPaths`.
    public var size: Int64
    /// Inode of `path` at scan time (FileRemover re-checks it).
    public var inode: UInt64?
    /// Set when Spruce cannot remove the item itself (protected location, configuration
    /// profile…); the text explains what the user can do instead.
    public var manualRemovalNote: String?

    public init(
        id: String,
        name: String,
        family: String? = nil,
        category: ThreatCategory,
        severity: ThreatSeverity,
        evidence: ThreatEvidence,
        reasons: [String],
        kind: ProtectionItemKind,
        path: String?,
        relatedPaths: [String] = [],
        launchLabel: String? = nil,
        launchDomain: ProtectionLaunchDomain? = nil,
        signing: ProtectionSigningInfo? = nil,
        sha256: String? = nil,
        score: Int = 0,
        cronLine: String? = nil,
        size: Int64 = 0,
        inode: UInt64? = nil,
        manualRemovalNote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.category = category
        self.severity = severity
        self.evidence = evidence
        self.reasons = reasons
        self.kind = kind
        self.path = path
        self.relatedPaths = relatedPaths
        self.launchLabel = launchLabel
        self.launchDomain = launchDomain
        self.signing = signing
        self.sha256 = sha256
        self.score = score
        self.cronLine = cronLine
        self.size = size
        self.inode = inode
        self.manualRemovalNote = manualRemovalNote
    }

    /// The strongest reason.
    public var reason: String { reasons.first ?? category.title }

    /// Matched a documented indicator or hash.
    public var isKnownThreat: Bool { evidence != .heuristic }

    /// Pre-selected for removal: known threats other than potentially unwanted apps,
    /// which Spruce can remove itself. Everything else waits for the user's decision.
    public var isRecommendedForRemoval: Bool {
        isKnownThreat && category != .pua && category != .suspicious && manualRemovalNote == nil
    }

    /// Display location ("~/Library/LaunchAgents").
    public var location: String {
        if kind == .cronJob { return "Your crontab" }
        guard let path else { return "" }
        return (path as NSString).deletingLastPathComponent.abbreviatingHome
    }
}

/// Result of one malware scan.
public struct ProtectionMalwareReport: Codable, Sendable, Equatable {
    public var date: Date
    public var depth: ProtectionScanDepth
    public var findings: [ProtectionThreatFinding]
    public var itemsScanned: Int
    public var duration: TimeInterval
    /// Locations that could not be read (missing Full Disk Access, permissions).
    public var unreadableLocations: [String]

    public init(date: Date = Date(), depth: ProtectionScanDepth, findings: [ProtectionThreatFinding],
                itemsScanned: Int, duration: TimeInterval, unreadableLocations: [String] = []) {
        self.date = date
        self.depth = depth
        self.findings = findings
        self.itemsScanned = itemsScanned
        self.duration = duration
        self.unreadableLocations = unreadableLocations
    }

    /// Findings in the report. Reports kept by the engine already leave out what the user
    /// ignored (`excludingIgnored`), so this is what the review list shows.
    public var threatCount: Int { findings.count }
    public var recommendedCount: Int { findings.filter(\.isRecommendedForRemoval).count }
    public var knownCount: Int { findings.filter(\.isKnownThreat).count }

    /// The same report without the findings on the ignore list (by path or item id), so
    /// counts, history and health match the review list the user sees.
    public func excludingIgnored(_ settings: SpruceSettings) -> ProtectionMalwareReport {
        guard !settings.ignoredPaths.isEmpty || !settings.ignoredItemIDs.isEmpty || !settings.ignoredBundleIDs.isEmpty else {
            return self
        }
        let visible = Set(settings.filteringIgnored(ProtectionThreatFinding.scanGroups(findings)).allItems.map(\.id))
        var copy = self
        copy.findings = findings.filter { visible.contains($0.id) }
        return copy
    }
}

// MARK: - Scan item mapping

/// Metadata keys Protection stores in `ScanItem.metadata`.
public enum ProtectionMetaKey {
    public static let tool = "protection.tool"
    public static let family = "protection.family"
    public static let category = "protection.category"
    public static let severity = "protection.severity"
    public static let evidence = "protection.evidence"
    public static let kind = "protection.kind"
    public static let launchLabel = "protection.launchLabel"
    public static let launchDomain = "protection.launchDomain"
    public static let related = "protection.related"
    public static let signing = "protection.signing"
    public static let teamID = "protection.teamID"
    public static let sha256 = "protection.sha256"
    public static let score = "protection.score"
    public static let manual = "protection.manual"
    public static let reasons = "protection.reasons"
    public static let cronLine = "protection.cronLine"
    /// FileRemover's inode check key (shared contract).
    public static let inode = "inode"

    public static let malwareTool = "malware"
    public static let privacyTool = "privacy"
    public static let permissionsTool = "permissions"
}

/// Group ids of the malware review list.
public enum ProtectionThreatGroup: String, CaseIterable, Sendable {
    case malware = "protection.threats.malware"
    case unwanted = "protection.threats.unwanted"
    case suspicious = "protection.threats.suspicious"

    public var title: String {
        switch self {
        case .malware: return "Malware"
        case .unwanted: return "Potentially unwanted"
        case .suspicious: return "Suspicious items"
        }
    }

    public var detail: String {
        switch self {
        case .malware:
            return "Matches documented malware or adware. Removing these is recommended; they go to the Trash."
        case .unwanted:
            return "Software many security vendors flag as unwanted. Remove it only if you didn't install it on purpose."
        case .suspicious:
            return "Flagged by behaviour, not by a known signature. Look at each one before removing it."
        }
    }

    public var symbol: String {
        switch self {
        case .malware: return "exclamationmark.shield.fill"
        case .unwanted: return "questionmark.app.fill"
        case .suspicious: return "eye.trianglebadge.exclamationmark"
        }
    }

    public static func of(_ finding: ProtectionThreatFinding) -> ProtectionThreatGroup {
        if !finding.isKnownThreat || finding.category == .suspicious { return .suspicious }
        return finding.category == .pua ? .unwanted : .malware
    }
}

public extension ProtectionThreatFinding {
    /// The reviewable scan item for this finding. Known threats Spruce can remove are
    /// pre-selected (`safe`); everything else is shown unchecked (`review`).
    var scanItem: ScanItem {
        var metadata: [String: String] = [
            ProtectionMetaKey.tool: ProtectionMetaKey.malwareTool,
            ProtectionMetaKey.category: category.rawValue,
            ProtectionMetaKey.severity: String(severity.rawValue),
            ProtectionMetaKey.evidence: evidence.rawValue,
            ProtectionMetaKey.kind: kind.rawValue,
            ProtectionMetaKey.score: String(score),
            ProtectionMetaKey.reasons: reasons.joined(separator: "\n"),
        ]
        if let family { metadata[ProtectionMetaKey.family] = family }
        if let launchLabel { metadata[ProtectionMetaKey.launchLabel] = launchLabel }
        if let launchDomain { metadata[ProtectionMetaKey.launchDomain] = launchDomain.rawValue }
        if !relatedPaths.isEmpty { metadata[ProtectionMetaKey.related] = relatedPaths.joined(separator: "\n") }
        if let signing {
            metadata[ProtectionMetaKey.signing] = signing.summary
            if let team = signing.teamID { metadata[ProtectionMetaKey.teamID] = team }
        }
        if let sha256 { metadata[ProtectionMetaKey.sha256] = sha256 }
        if let manualRemovalNote { metadata[ProtectionMetaKey.manual] = manualRemovalNote }
        if let cronLine { metadata[ProtectionMetaKey.cronLine] = cronLine }
        if let inode { metadata[ProtectionMetaKey.inode] = String(inode) }

        let recommended = isRecommendedForRemoval
        let titleText = family.map { "\($0) · \(name)" } ?? name
        return ScanItem(
            id: id,
            title: titleText,
            subtitle: kind == .cronJob ? (cronLine ?? location) : location,
            url: path.map { URL(fileURLWithPath: $0) },
            size: size,
            itemCount: 1 + relatedPaths.count,
            safety: recommended ? .safe : .review,
            isSelected: recommended,
            deletion: (manualRemovalNote != nil || kind == .cronJob) ? .custom : .trash,
            symbol: category.symbol,
            note: reason,
            metadata: metadata
        )
    }

    /// Groups findings into the malware review list (Malware · Potentially unwanted · Suspicious),
    /// most severe first.
    static func scanGroups(_ findings: [ProtectionThreatFinding]) -> [ScanGroup] {
        ProtectionThreatGroup.allCases.compactMap { group in
            let members = findings
                .filter { ProtectionThreatGroup.of($0) == group }
                .sorted { ($0.severity, $0.score, $1.name) > ($1.severity, $1.score, $0.name) }
            guard !members.isEmpty else { return nil }
            return ScanGroup(id: group.rawValue, title: group.title, detail: group.detail, symbol: group.symbol,
                             safety: group == .malware ? .safe : .review, items: members.map(\.scanItem))
        }
    }
}

/// What removing one selected malware item involves, decoded from `ScanItem.metadata`
/// (so Checkup's review list, which only holds scan items, can be acted on too).
public struct ProtectionRemovalPlan: Sendable, Equatable {
    public var itemID: String
    public var title: String
    public var primaryPath: String?
    public var relatedPaths: [String]
    public var kind: ProtectionItemKind
    public var launchLabel: String?
    public var launchDomain: ProtectionLaunchDomain?
    public var cronLine: String?
    public var manualNote: String?
    public var inode: String?
    public var size: Int64
    /// Matched a documented indicator or hash (not just heuristics).
    public var isKnownThreat: Bool

    public init?(item: ScanItem) {
        guard item.metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.malwareTool else { return nil }
        itemID = item.id
        title = item.title
        primaryPath = item.url?.path
        relatedPaths = (item.metadata[ProtectionMetaKey.related] ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        kind = ProtectionItemKind(rawValue: item.metadata[ProtectionMetaKey.kind] ?? "") ?? .file
        launchLabel = item.metadata[ProtectionMetaKey.launchLabel]
        launchDomain = item.metadata[ProtectionMetaKey.launchDomain].flatMap(ProtectionLaunchDomain.init(rawValue:))
        cronLine = item.metadata[ProtectionMetaKey.cronLine]
        manualNote = item.metadata[ProtectionMetaKey.manual]
        inode = item.metadata[ProtectionMetaKey.inode]
        size = item.size
        let evidence = item.metadata[ProtectionMetaKey.evidence].flatMap(ThreatEvidence.init(rawValue:)) ?? .heuristic
        isKnownThreat = evidence != .heuristic
    }

    /// True when the item is a launchd job that should be unloaded before its files go.
    public var isLaunchJob: Bool {
        (kind == .launchAgent || kind == .launchDaemon) && primaryPath != nil
    }
}
