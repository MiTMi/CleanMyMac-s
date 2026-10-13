import Foundation
import XCTest
@testable import SpruceCore

final class CloudStoragePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func record(_ name: String = "a.mov", local: Int64 = 5_000_000, cloudOnly: Bool = false,
                        modifiedDaysAgo: Double = 60, usedDaysAgo: Double? = nil,
                        area: CloudStorageArea = .drive, status: CloudStorageSyncStatus = .unknown) -> CloudStorageFileRecord {
        CloudStorageFileRecord(path: "/cloud/\(name)", logicalSize: max(local, 1_000), allocatedSize: cloudOnly ? 0 : local,
                               isCloudOnly: cloudOnly, modified: now.addingTimeInterval(-modifiedDaysAgo * day),
                               lastUsed: usedDaysAgo.map { now.addingTimeInterval(-$0 * day) }, area: area, status: status)
    }

    func testOldSyncedFileIsRecommended() {
        let policy = CloudStorageEvictionPolicy()
        let verdict = policy.eligibility(for: record(status: CloudStorageSyncStatus(download: .current, isUploaded: true)),
                                         mechanism: .iCloud, now: now)
        XCTAssertEqual(verdict, .recommended)
        XCTAssertEqual(verdict.safety, .safe)
        XCTAssertTrue(verdict.canSelect)
    }

    func testUnknownUploadStateStillRecommendedForFileProvider() {
        XCTAssertEqual(CloudStorageEvictionPolicy().eligibility(for: record(), mechanism: .fileProvider, now: now), .recommended)
    }

    func testBlockedCases() {
        let policy = CloudStorageEvictionPolicy()
        let cases: [(CloudStorageFileRecord, CloudStorageMechanism)] = [
            (record(), .syncFolder),
            (record(cloudOnly: true), .iCloud),
            (record(status: CloudStorageSyncStatus(hasConflicts: true)), .iCloud),
            (record(status: CloudStorageSyncStatus(isUploaded: false)), .iCloud),
            (record(status: CloudStorageSyncStatus(isUploading: true)), .fileProvider),
            (record(status: CloudStorageSyncStatus(isDownloading: true)), .fileProvider),
            (record(status: CloudStorageSyncStatus(downloadRequested: true)), .fileProvider),
        ]
        for (item, mechanism) in cases {
            let verdict = policy.eligibility(for: item, mechanism: mechanism, now: now)
            XCTAssertFalse(verdict.canSelect, "\(item.status) \(mechanism)")
            XCTAssertNotNil(verdict.reason)
            XCTAssertEqual(verdict.safety, .risky)
        }
    }

    func testReviewCases() {
        let policy = CloudStorageEvictionPolicy(recentModificationDays: 7, recentUseDays: 30)
        let cases = [
            record(modifiedDaysAgo: 2),
            record(usedDaysAgo: 10),
            record(area: .desktopAndDocuments),
            record(area: .appFolder),
            record(status: CloudStorageSyncStatus(download: .downloaded, isUploaded: true)),
        ]
        for item in cases {
            let verdict = policy.eligibility(for: item, mechanism: .iCloud, now: now)
            XCTAssertTrue(verdict.canSelect)
            XCTAssertFalse(verdict.isRecommended)
            XCTAssertEqual(verdict.safety, .review)
        }
        // Used long ago and changed long ago: fine.
        XCTAssertEqual(policy.eligibility(for: record(modifiedDaysAgo: 40, usedDaysAgo: 45), mechanism: .iCloud, now: now),
                       .recommended)
    }

    func testZeroDayThresholdsDisableRecencyRules() {
        let policy = CloudStorageEvictionPolicy(recentModificationDays: 0, recentUseDays: 0)
        XCTAssertEqual(policy.eligibility(for: record(modifiedDaysAgo: 0, usedDaysAgo: 0), mechanism: .iCloud, now: now),
                       .recommended)
    }

    func testEvictionLadder() {
        XCTAssertEqual(CloudStorageEvictionPlanner.strategies(for: .iCloud, tools: .none), [.fileManager])
        XCTAssertEqual(CloudStorageEvictionPlanner.strategies(for: .iCloud, tools: CloudStorageToolAvailability(brctl: true)),
                       [.fileManager, .brctl])
        XCTAssertEqual(CloudStorageEvictionPlanner.strategies(for: .fileProvider, tools: CloudStorageToolAvailability(brctl: true)),
                       [.fileManager])
        XCTAssertEqual(CloudStorageEvictionPlanner.strategies(for: .fileProvider,
                                                              tools: CloudStorageToolAvailability(fileProviderCtlEvict: true)),
                       [.fileManager, .fileProviderCtl])
        XCTAssertTrue(CloudStorageEvictionPlanner.strategies(for: .syncFolder,
                                                             tools: CloudStorageToolAvailability(brctl: true, fileProviderCtlEvict: true)).isEmpty)
    }

    func testFreedDetection() {
        let before = record(local: 16_000_000)
        var after = before
        after.allocatedSize = 4_096
        XCTAssertTrue(CloudStorageEvictionPlanner.isFreed(before: before, after: after), "a tiny stub counts as freed")
        after.allocatedSize = 8_000_000
        XCTAssertFalse(CloudStorageEvictionPlanner.isFreed(before: before, after: after))
        after.isCloudOnly = true
        XCTAssertTrue(CloudStorageEvictionPlanner.isFreed(before: before, after: after))
    }

    func testFileProviderCtlHelpParsing() {
        let old = """
        usage: fileproviderctl <command> [options]
          dump [-l] [<provider>]
          evict <path>
          materialize <path>
        """
        let new = """
        usage: fileproviderctl <command>
          dump        Dump the state of the file provider daemon
          check       Check a domain; you can no longer evict or materialize from here
        """
        XCTAssertTrue(CloudStorageToolAvailability.helpListsVerb("evict", in: old))
        XCTAssertTrue(CloudStorageToolAvailability.helpListsVerb("materialize", in: old))
        XCTAssertFalse(CloudStorageToolAvailability.helpListsVerb("evict", in: new))
        XCTAssertTrue(CloudStorageToolAvailability.helpListsVerb("evict", in: "fileproviderctl evict [-n] <item>"))
    }
}

final class CloudStorageRankingTests: XCTestCase {
    private func file(_ name: String, local: Int64, logical: Int64? = nil, cloudOnly: Bool = false) -> CloudStorageFileRecord {
        CloudStorageFileRecord(path: "/c/\(name)", logicalSize: logical ?? local, allocatedSize: cloudOnly ? 0 : local,
                               isCloudOnly: cloudOnly, modified: Date(timeIntervalSince1970: 0))
    }

    func testTopFilesKeepsBiggest() {
        var top = CloudStorageTopFiles(limit: 3, minimumSize: 10, measure: .local)
        for (i, size) in [5, 40, 12, 90, 33, 70, 11, 8, 100, 64].enumerated() {
            top.insert(file("f\(i)", local: Int64(size)))
        }
        XCTAssertEqual(top.sorted.map(\.localBytes), [100, 90, 70])
        XCTAssertEqual(top.count, 3)
    }

    func testTopFilesUsesLogicalForCloudOnly() {
        var top = CloudStorageTopFiles(limit: 2, measure: .logical)
        top.insert(file("a", local: 0, logical: 500, cloudOnly: true))
        top.insert(file("b", local: 0, logical: 900, cloudOnly: true))
        top.insert(file("c", local: 0, logical: 0, cloudOnly: true))
        XCTAssertEqual(top.sorted.map(\.name), ["b", "a"])
    }

    func testStableTieBreak() {
        let sorted = CloudStorageRanking.sorted([file("b", local: 10), file("a", local: 10), file("c", local: 20)], by: .local)
        XCTAssertEqual(sorted.map(\.name), ["c", "a", "b"])
    }

    func testStatsMergeAndOverview() {
        var a = CloudStorageStats()
        a.add(file("x", local: 1_000), largeThreshold: 500)
        a.add(file("y", local: 0, logical: 3_000, cloudOnly: true), largeThreshold: 500)
        XCTAssertEqual(a.localBytes, 1_000)
        XCTAssertEqual(a.cloudBytes, 4_000)
        XCTAssertEqual(a.localFraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(a.largeLocalCount, 1)

        let reports = [
            CloudStorageProviderReport(provider: CloudStorageProvider(kind: .iCloudDrive, mechanism: .iCloud, rootPath: "/a"), stats: a),
            CloudStorageProviderReport(provider: CloudStorageProvider(kind: .dropbox, mechanism: .syncFolder, rootPath: "/b"), stats: a),
        ]
        let overview = CloudStorageOverview(reports: reports)
        XCTAssertEqual(overview.providerCount, 2)
        XCTAssertEqual(overview.stats.localBytes, 2_000)
        XCTAssertEqual(overview.freeableBytes, 1_000, "legacy sync folders can't be freed")
        XCTAssertEqual(CloudStorageText.localLine(a), "1 KB of 4 KB on this Mac")
    }

    func testTextSummaries() {
        XCTAssertEqual(CloudStorageText.freeUpSummary(freedCount: 0, freedBytes: 0, failedCount: 0), "No local copies were removed")
        XCTAssertTrue(CloudStorageText.freeUpSummary(freedCount: 2, freedBytes: 2_000_000, failedCount: 1).contains("1 file stayed"))
        XCTAssertTrue(CloudStorageText.downloadSummary(requested: 3, failed: 0).hasPrefix("Downloading 3 files"))
        XCTAssertTrue(CloudStorageText.manualAdvice(for: .oneDrive).contains("Free Up Space"))
        var stats = CloudStorageStats()
        XCTAssertNil(CloudStorageText.unlistedLine(stats))
        stats.unlistedFolderCount = 2
        XCTAssertEqual(CloudStorageText.unlistedLine(stats), "Plus 2 online-only folders not listed on this Mac (not counted)")
    }
}
