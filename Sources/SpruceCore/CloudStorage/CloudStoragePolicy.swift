import Foundation

// MARK: - Eligibility

/// Whether a downloaded file can have its local copy removed, and whether Spruce
/// suggests it.
public enum CloudStorageEligibility: Hashable, Sendable {
    /// Safe to free: fully synced and untouched for a while. Pre-selected.
    case recommended
    /// Can be freed, but the user should decide (recently changed, essential folder…).
    case review(String)
    /// Can't be freed right now (not uploaded, conflicts, legacy sync folder…).
    case blocked(String)

    public var canSelect: Bool {
        if case .blocked = self { return false }
        return true
    }

    public var isRecommended: Bool { self == .recommended }

    public var reason: String? {
        switch self {
        case .recommended: return nil
        case .review(let reason), .blocked(let reason): return reason
        }
    }

    /// The matching shared safety level (blocked items are never offered).
    public var safety: SafetyLevel {
        switch self {
        case .recommended: return .safe
        case .review: return .review
        case .blocked: return .risky
        }
    }
}

/// Rules for suggesting which local copies to free.
///
/// Removing a local copy never deletes anything from the cloud, but a file that is
/// still uploading, has conflicts or is in active use should stay put.
public struct CloudStorageEvictionPolicy: Hashable, Sendable, Codable {
    /// Files changed within this many days are not suggested.
    public var recentModificationDays: Int
    /// Files opened within this many days are not suggested.
    public var recentUseDays: Int

    public init(recentModificationDays: Int = 7, recentUseDays: Int = 30) {
        self.recentModificationDays = max(0, recentModificationDays)
        self.recentUseDays = max(0, recentUseDays)
    }

    public func eligibility(for record: CloudStorageFileRecord, mechanism: CloudStorageMechanism,
                            now: Date = Date()) -> CloudStorageEligibility {
        guard mechanism.canFreeUpLocally else {
            return .blocked("This app keeps every file on your Mac; switch it to online-only files in the app")
        }
        if record.isCloudOnly || record.localBytes == 0 {
            return .blocked("Already stored only in the cloud")
        }
        let status = record.status
        if status.hasConflicts {
            return .blocked("Has unresolved sync conflicts")
        }
        if status.isUploading || status.isUploaded == false {
            return .blocked("Not fully uploaded yet")
        }
        if status.isDownloading || status.downloadRequested {
            return .blocked("Downloading right now")
        }
        if status.download == .downloaded {
            return .review("A newer version is waiting in the cloud")
        }
        switch record.area {
        case .appFolder:
            return .review("Saved by an app in its iCloud folder")
        case .desktopAndDocuments:
            return .review("Synced from your Desktop or Documents folder")
        case .drive:
            break
        }
        let day: TimeInterval = 86_400
        if recentModificationDays > 0,
           now.timeIntervalSince(record.modified) < Double(recentModificationDays) * day {
            return .review("Changed in the last \(CountFormat.items(recentModificationDays, singular: "day"))")
        }
        if recentUseDays > 0, let lastUsed = record.lastUsed,
           now.timeIntervalSince(lastUsed) < Double(recentUseDays) * day {
            return .review("Opened in the last \(CountFormat.items(recentUseDays, singular: "day"))")
        }
        return .recommended
    }
}

// MARK: - Eviction ladder

/// The ways Spruce can ask macOS to drop a local copy, tried in order.
public enum CloudStorageEvictionStrategy: String, Sendable, Hashable, CaseIterable {
    /// `FileManager.evictUbiquitousItem(at:)`.
    case fileManager
    /// `/usr/bin/brctl evict <path>` (iCloud Drive, run as the user).
    case brctl
    /// `/usr/bin/fileproviderctl evict <path>` (File Provider; removed in macOS 14.4).
    case fileProviderCtl

    public var title: String {
        switch self {
        case .fileManager: return "macOS"
        case .brctl: return "iCloud tool"
        case .fileProviderCtl: return "File Provider tool"
        }
    }
}

/// Which command-line helpers exist on this Mac.
public struct CloudStorageToolAvailability: Hashable, Sendable {
    public var brctl: Bool
    public var fileProviderCtlEvict: Bool
    public var fileProviderCtlMaterialize: Bool

    public init(brctl: Bool = false, fileProviderCtlEvict: Bool = false, fileProviderCtlMaterialize: Bool = false) {
        self.brctl = brctl
        self.fileProviderCtlEvict = fileProviderCtlEvict
        self.fileProviderCtlMaterialize = fileProviderCtlMaterialize
    }

    public static let none = CloudStorageToolAvailability()

    /// True when `fileproviderctl`'s usage text lists `verb` as a command.
    ///
    /// Usage lines look like `  evict <path>` or `fileproviderctl evict [-n] <item>`;
    /// mentions inside sentences don't count.
    public static func helpListsVerb(_ verb: String, in helpText: String) -> Bool {
        let verb = verb.lowercased()
        for rawLine in helpText.split(whereSeparator: \.isNewline) {
            let tokens = rawLine.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let first = tokens.first else { continue }
            if first == verb { return true }
            if first.hasSuffix("fileproviderctl"), tokens.count > 1, tokens[1] == verb { return true }
        }
        return false
    }
}

public enum CloudStorageEvictionPlanner {
    /// Strategies to try for a provider, in order.
    public static func strategies(for mechanism: CloudStorageMechanism,
                                  tools: CloudStorageToolAvailability) -> [CloudStorageEvictionStrategy] {
        switch mechanism {
        case .syncFolder:
            return []
        case .iCloud:
            return tools.brctl ? [.fileManager, .brctl] : [.fileManager]
        case .fileProvider:
            return tools.fileProviderCtlEvict ? [.fileManager, .fileProviderCtl] : [.fileManager]
        }
    }

    /// Whether a re-measured file counts as freed: online-only now, or (for providers
    /// that keep a tiny stub) at most 1/16 of its former local size.
    public static func isFreed(before: CloudStorageFileRecord, after: CloudStorageFileRecord) -> Bool {
        if after.isCloudOnly || after.localBytes == 0 { return true }
        guard before.localBytes > 0 else { return false }
        return after.localBytes * 16 <= before.localBytes
    }
}

// MARK: - Wording

/// User-facing explanations (Spruce's own wording).
public enum CloudStorageText {
    /// What "Free Up Locally" does, for the results screen and the confirmation.
    public static func evictionExplanation(providerName: String) -> String {
        "Free Up Locally removes only the downloaded copy from this Mac. The file stays in \(providerName) and on your other devices, keeps its place in Finder, and downloads again when you open it — you'll need an internet connection then."
    }

    /// Advice when a provider refused to drop a local copy.
    public static func manualAdvice(for kind: CloudStorageProviderKind) -> String {
        "\(kind.title) kept its local copy. Control-click the file in Finder and choose “\(kind.finderCommandHint)”."
    }

    /// Summary line for a finished Free Up Locally run.
    public static func freeUpSummary(freedCount: Int, freedBytes: Int64, failedCount: Int) -> String {
        var parts: [String] = []
        if freedCount > 0 {
            parts.append("Freed \(ByteFormat.string(freedBytes)) on this Mac from \(CountFormat.items(freedCount, singular: "file")); they're still in the cloud")
        } else {
            parts.append("No local copies were removed")
        }
        if failedCount > 0 {
            parts.append("\(CountFormat.items(failedCount, singular: "file")) stayed on this Mac")
        }
        return parts.joined(separator: " · ")
    }

    /// Summary line for a download request.
    public static func downloadSummary(requested: Int, failed: Int) -> String {
        var line = requested > 0
            ? "Downloading \(CountFormat.items(requested, singular: "file")) in the background"
            : "Nothing was downloaded"
        if failed > 0 { line += " · \(CountFormat.items(failed, singular: "file")) couldn't start" }
        return line
    }

    /// "12.4 GB of 30.1 GB on this Mac".
    public static func localLine(_ stats: CloudStorageStats) -> String {
        "\(ByteFormat.string(stats.localBytes)) of \(ByteFormat.string(max(stats.cloudBytes, stats.localBytes))) on this Mac"
    }

    /// Extra line for online-only folders whose contents weren't listed.
    public static func unlistedLine(_ stats: CloudStorageStats) -> String? {
        guard stats.unlistedFolderCount > 0 else { return nil }
        return "Plus \(CountFormat.items(stats.unlistedFolderCount, singular: "online-only folder")) not listed on this Mac (not counted)"
    }
}
