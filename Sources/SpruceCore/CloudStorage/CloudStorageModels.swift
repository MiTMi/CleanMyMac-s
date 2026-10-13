import Foundation

// MARK: - Sync status

/// What macOS reports about a file's sync state (filled in by the Mac engine from the
/// `ubiquitousItem…` resource values; unknown values stay nil / false).
public struct CloudStorageSyncStatus: Hashable, Sendable, Codable {
    /// iCloud's download state of the item.
    public enum Download: String, Codable, Sendable, Hashable {
        /// A local copy exists and is the latest version.
        case current
        /// A local copy exists but a newer version is in the cloud.
        case downloaded
        /// Only in the cloud.
        case notDownloaded
    }

    public var download: Download?
    /// True once the cloud has the latest content; nil when the provider doesn't say.
    public var isUploaded: Bool?
    public var isUploading: Bool
    public var isDownloading: Bool
    public var hasConflicts: Bool
    /// The user asked for a download that hasn't finished yet (set by the engine).
    public var downloadRequested: Bool

    public init(download: Download? = nil, isUploaded: Bool? = nil, isUploading: Bool = false,
                isDownloading: Bool = false, hasConflicts: Bool = false, downloadRequested: Bool = false) {
        self.download = download
        self.isUploaded = isUploaded
        self.isUploading = isUploading
        self.isDownloading = isDownloading
        self.hasConflicts = hasConflicts
        self.downloadRequested = downloadRequested
    }

    public static let unknown = CloudStorageSyncStatus()
}

// MARK: - File record

/// One file (or package, counted as one document) inside a provider's folder.
public struct CloudStorageFileRecord: Identifiable, Hashable, Sendable, Codable {
    /// Absolute path.
    public var path: String
    /// Size of the file's contents (what the cloud stores).
    public var logicalSize: Int64
    /// Bytes allocated on this Mac's disk (0 for online-only placeholders).
    public var allocatedSize: Int64
    /// The file exists here only as an online-only placeholder (APFS dataless).
    public var isCloudOnly: Bool
    /// A package document (`.pages`, `.logicx`…) measured as a whole.
    public var isPackage: Bool
    /// Files represented (1 for a plain file).
    public var fileCount: Int
    public var modified: Date
    /// Last opened, when known (Spotlight).
    public var lastUsed: Date?
    public var inode: UInt64
    public var area: CloudStorageArea
    public var status: CloudStorageSyncStatus

    public init(path: String, logicalSize: Int64, allocatedSize: Int64, isCloudOnly: Bool, isPackage: Bool = false,
                fileCount: Int = 1, modified: Date, lastUsed: Date? = nil, inode: UInt64 = 0,
                area: CloudStorageArea = .drive, status: CloudStorageSyncStatus = .unknown) {
        self.path = path
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.isCloudOnly = isCloudOnly
        self.isPackage = isPackage
        self.fileCount = fileCount
        self.modified = modified
        self.lastUsed = lastUsed
        self.inode = inode
        self.area = area
        self.status = status
    }

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
    /// Folder containing the file, home-abbreviated.
    public var folderLine: String { (path as NSString).deletingLastPathComponent.abbreviatingHome }

    /// Bytes this file occupies on this Mac.
    public var localBytes: Int64 { isCloudOnly ? 0 : allocatedSize }

    /// Size shown for the file in the cloud (logical size, never smaller than the local copy).
    public var cloudBytes: Int64 { max(logicalSize, localBytes) }

    /// Path relative to the provider root ("Projects/Video/final.mov").
    public func relativePath(in provider: CloudStorageProvider) -> String {
        for root in [provider.rootPath] + provider.additionalRoots {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if path.hasPrefix(prefix) {
                let rel = String(path.dropFirst(prefix.count))
                if root == provider.rootPath { return rel }
                return CloudStorageDiscovery.appFolderName(root) + "/" + rel
            }
        }
        return path.abbreviatingHome
    }
}

// MARK: - Stats

/// Local-versus-cloud totals for one provider (or several, when merged).
public struct CloudStorageStats: Hashable, Sendable, Codable {
    /// Logical size of every known file (what the cloud stores).
    public var cloudBytes: Int64 = 0
    /// Bytes downloaded to this Mac (allocated).
    public var localBytes: Int64 = 0
    /// Logical size of online-only files.
    public var cloudOnlyBytes: Int64 = 0
    public var fileCount: Int = 0
    public var localFileCount: Int = 0
    public var cloudOnlyFileCount: Int = 0
    public var folderCount: Int = 0
    /// Online-only folders whose contents haven't been listed on this Mac yet.
    public var unlistedFolderCount: Int = 0
    /// Folders macOS didn't let us read (no permission).
    public var unreadableFolderCount: Int = 0
    /// Downloaded files at or above the "large" threshold.
    public var largeLocalCount: Int = 0
    public var largeLocalBytes: Int64 = 0

    public init() {}

    /// Counts one file.
    public mutating func add(_ record: CloudStorageFileRecord, largeThreshold: Int64) {
        let files = max(record.fileCount, 1)
        fileCount += files
        cloudBytes += record.cloudBytes
        if record.isCloudOnly {
            cloudOnlyFileCount += files
            cloudOnlyBytes += record.logicalSize
        } else {
            localFileCount += files
            localBytes += record.localBytes
            if record.localBytes >= largeThreshold {
                largeLocalCount += 1
                largeLocalBytes += record.localBytes
            }
        }
    }

    /// Adds another provider's totals.
    public mutating func merge(_ other: CloudStorageStats) {
        cloudBytes += other.cloudBytes
        localBytes += other.localBytes
        cloudOnlyBytes += other.cloudOnlyBytes
        fileCount += other.fileCount
        localFileCount += other.localFileCount
        cloudOnlyFileCount += other.cloudOnlyFileCount
        folderCount += other.folderCount
        unlistedFolderCount += other.unlistedFolderCount
        unreadableFolderCount += other.unreadableFolderCount
        largeLocalCount += other.largeLocalCount
        largeLocalBytes += other.largeLocalBytes
    }

    /// Share of the provider's content that is downloaded to this Mac (0…1).
    public var localFraction: Double {
        let total = max(cloudBytes, localBytes)
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(localBytes) / Double(total)))
    }

    /// True when nothing at all was found.
    public var isEmpty: Bool { fileCount == 0 && unlistedFolderCount == 0 }
}

// MARK: - Report

/// The result of scanning one provider.
public struct CloudStorageProviderReport: Identifiable, Hashable, Sendable, Codable {
    public var provider: CloudStorageProvider
    public var stats: CloudStorageStats
    /// Largest downloaded files, biggest local footprint first.
    public var largestLocal: [CloudStorageFileRecord]
    /// Largest online-only files, biggest first.
    public var largestCloudOnly: [CloudStorageFileRecord]
    public var scanDate: Date
    /// The root folder could not be read at all (macOS denied access).
    public var accessDenied: Bool
    /// False when the scan was stopped before it finished.
    public var isComplete: Bool

    public init(provider: CloudStorageProvider, stats: CloudStorageStats = CloudStorageStats(),
                largestLocal: [CloudStorageFileRecord] = [], largestCloudOnly: [CloudStorageFileRecord] = [],
                scanDate: Date = Date(), accessDenied: Bool = false, isComplete: Bool = true) {
        self.provider = provider
        self.stats = stats
        self.largestLocal = largestLocal
        self.largestCloudOnly = largestCloudOnly
        self.scanDate = scanDate
        self.accessDenied = accessDenied
        self.isComplete = isComplete
    }

    public var id: String { provider.id }

    /// Replaces records with re-measured versions (after freeing or downloading) and
    /// keeps the totals consistent: files that became online-only move from the local
    /// list to the cloud-only list.
    public func applying(_ updates: [CloudStorageFileRecord], largeThreshold: Int64) -> CloudStorageProviderReport {
        guard !updates.isEmpty else { return self }
        var byPath: [String: CloudStorageFileRecord] = [:]
        for update in updates { byPath[update.path] = update }
        var result = self
        var local: [CloudStorageFileRecord] = []
        var movedToCloud: [CloudStorageFileRecord] = []
        for old in largestLocal {
            guard let new = byPath.removeValue(forKey: old.path) else {
                local.append(old)
                continue
            }
            result.stats.replace(old, with: new, largeThreshold: largeThreshold)
            if new.isCloudOnly {
                movedToCloud.append(new)
            } else {
                local.append(new)
            }
        }
        var cloud: [CloudStorageFileRecord] = []
        for old in largestCloudOnly {
            guard let new = byPath.removeValue(forKey: old.path) else {
                cloud.append(old)
                continue
            }
            result.stats.replace(old, with: new, largeThreshold: largeThreshold)
            if new.isCloudOnly {
                cloud.append(new)
            } else {
                local.append(new)
            }
        }
        result.largestLocal = CloudStorageRanking.sorted(local, by: .local)
        result.largestCloudOnly = CloudStorageRanking.sorted(cloud + movedToCloud, by: .logical)
        return result
    }

    /// The report without the listed files `isRemoved` matches, taken out of the totals
    /// too — what a scan that skipped them would have reported.
    public func removing(where isRemoved: (CloudStorageFileRecord) -> Bool,
                         largeThreshold: Int64) -> CloudStorageProviderReport {
        var result = self
        var local: [CloudStorageFileRecord] = []
        for record in largestLocal {
            if isRemoved(record) {
                result.stats.remove(record, largeThreshold: largeThreshold)
            } else {
                local.append(record)
            }
        }
        var cloud: [CloudStorageFileRecord] = []
        for record in largestCloudOnly {
            if isRemoved(record) {
                result.stats.remove(record, largeThreshold: largeThreshold)
            } else {
                cloud.append(record)
            }
        }
        result.largestLocal = local
        result.largestCloudOnly = cloud
        return result
    }

    /// The report without listed files that are on the ignore list (by path, or by item
    /// id, which is the path here), as a new scan with these settings would show it.
    public func removingIgnored(_ settings: SpruceSettings, largeThreshold: Int64) -> CloudStorageProviderReport {
        guard !settings.ignoredPaths.isEmpty || !settings.ignoredItemIDs.isEmpty else { return self }
        let ids = Set(settings.ignoredItemIDs)
        return removing(where: { ids.contains($0.id) || settings.isIgnored(path: $0.path) },
                        largeThreshold: largeThreshold)
    }
}

extension CloudStorageStats {
    /// Swaps one file's contribution for its re-measured version.
    mutating func replace(_ old: CloudStorageFileRecord, with new: CloudStorageFileRecord, largeThreshold: Int64) {
        remove(old, largeThreshold: largeThreshold)
        add(new, largeThreshold: largeThreshold)
    }

    mutating func remove(_ record: CloudStorageFileRecord, largeThreshold: Int64) {
        let files = max(record.fileCount, 1)
        fileCount = max(0, fileCount - files)
        cloudBytes = max(0, cloudBytes - record.cloudBytes)
        if record.isCloudOnly {
            cloudOnlyFileCount = max(0, cloudOnlyFileCount - files)
            cloudOnlyBytes = max(0, cloudOnlyBytes - record.logicalSize)
        } else {
            localFileCount = max(0, localFileCount - files)
            localBytes = max(0, localBytes - record.localBytes)
            if record.localBytes >= largeThreshold {
                largeLocalCount = max(0, largeLocalCount - 1)
                largeLocalBytes = max(0, largeLocalBytes - record.localBytes)
            }
        }
    }
}

// MARK: - Overview

/// Totals across every scanned provider.
public struct CloudStorageOverview: Hashable, Sendable {
    public var stats: CloudStorageStats
    public var providerCount: Int
    /// Downloaded bytes that "Free Up Locally" could act on (excludes legacy sync folders).
    public var freeableBytes: Int64

    public init(reports: [CloudStorageProviderReport]) {
        var stats = CloudStorageStats()
        var freeable: Int64 = 0
        for report in reports {
            stats.merge(report.stats)
            if report.provider.mechanism.canFreeUpLocally { freeable += report.stats.localBytes }
        }
        self.stats = stats
        self.providerCount = reports.count
        self.freeableBytes = freeable
    }
}

// MARK: - Scan progress

/// Live counters while one provider is scanned.
public struct CloudStorageScanTick: Sendable, Equatable {
    public var providerID: String
    public var filesSeen: Int
    public var localBytes: Int64
    public var cloudBytes: Int64
    public var currentPath: String?
    public var finished: Bool

    public init(providerID: String, filesSeen: Int = 0, localBytes: Int64 = 0, cloudBytes: Int64 = 0,
                currentPath: String? = nil, finished: Bool = false) {
        self.providerID = providerID
        self.filesSeen = filesSeen
        self.localBytes = localBytes
        self.cloudBytes = cloudBytes
        self.currentPath = currentPath
        self.finished = finished
    }
}

public typealias CloudStorageScanTickHandler = @Sendable (CloudStorageScanTick) -> Void
