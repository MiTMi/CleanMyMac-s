import Foundation
import XCTest
@testable import SpruceCore

final class CloudStorageScannerTests: XCTestCase {
    private var root: String = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "cloud-scan-\(UUID().uuidString)"
        try fm.createDirectory(atPath: root + "/Videos", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Docs/Deep", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Report.pages/Data", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/.shortcut-targets-by-id/abc", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Ignored", withIntermediateDirectories: true)

        try write(root + "/Videos/trip.mov", bytes: 3_000_000)          // local, large
        try write(root + "/Docs/notes.txt", bytes: 1_200_000)            // local
        try write(root + "/Docs/Deep/tiny.txt", bytes: 2_000)            // local, below list minimum
        try sparse(root + "/Videos/archive.mov", bytes: 8_000_000)       // online-only placeholder
        try sparse(root + "/Docs/old.zip", bytes: 2_500_000)             // online-only placeholder
        try write(root + "/Report.pages/Data/image.png", bytes: 1_500_000) // package content
        try write(root + "/Report.pages/Index.zip", bytes: 100_000)
        try write(root + "/.shortcut-targets-by-id/abc/dup.mov", bytes: 2_000_000) // excluded
        try write(root + "/Ignored/secret.mov", bytes: 2_000_000)
        try write(root + "/.DS_Store", bytes: 1_100_000)                 // bookkeeping, counted but not listed
        try fm.createSymbolicLink(atPath: root + "/Link.mov", withDestinationPath: root + "/Videos/trip.mov")
        try fm.linkItem(atPath: root + "/Docs/notes.txt", toPath: root + "/Docs/notes-hardlink.txt")
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(atPath: root)
    }

    private func write(_ path: String, bytes: Int) throws {
        // Non-zero content so no file system stores it sparsely.
        var bytesArray = [UInt8](repeating: 0, count: bytes)
        for i in stride(from: 0, to: bytes, by: 512) { bytesArray[i] = UInt8(truncatingIfNeeded: i / 512 + 1) }
        try Data(bytesArray).write(to: URL(fileURLWithPath: path))
    }

    /// A file with a real size and no allocated blocks — how online-only files look.
    private func sparse(_ path: String, bytes: Int) throws {
        XCTAssertTrue(fm.createFile(atPath: path, contents: nil))
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
    }

    private var provider: CloudStorageProvider {
        CloudStorageProvider(kind: .dropbox, mechanism: .fileProvider, rootPath: root)
    }

    private func scan(_ options: CloudStorageScanOptions = CloudStorageScanOptions(largeFileThreshold: 2_000_000)) -> CloudStorageProviderReport {
        CloudStorageScanner.scan(provider, options: options)
    }

    func testSeparatesLocalAndOnlineOnlyFiles() throws {
        let ignoredRoot = root + "/Ignored"
        let report = scan(CloudStorageScanOptions(largeFileThreshold: 2_000_000,
                                                  isIgnored: { $0.hasPrefix(ignoredRoot) }))
        let stats = report.stats
        XCTAssertTrue(report.isComplete)
        XCTAssertFalse(report.accessDenied)

        // trip, notes (hard link counted once), tiny, .DS_Store, package (2 files) + 2 placeholders.
        XCTAssertEqual(stats.cloudOnlyFileCount, 2)
        XCTAssertEqual(stats.cloudOnlyBytes, 10_500_000)
        XCTAssertEqual(stats.localFileCount, 6)
        XCTAssertEqual(stats.fileCount, 8)
        XCTAssertGreaterThanOrEqual(stats.localBytes, 3_000_000 + 1_200_000 + 1_600_000 + 1_100_000)
        XCTAssertGreaterThanOrEqual(stats.cloudBytes, stats.localBytes)
        XCTAssertEqual(stats.largeLocalCount, 1)
        XCTAssertGreaterThan(stats.localFraction, 0)
        XCTAssertLessThan(stats.localFraction, 1)

        let localNames = report.largestLocal.map(\.name)
        XCTAssertEqual(localNames.first, "trip.mov")
        XCTAssertTrue(localNames.contains("Report.pages"))
        XCTAssertTrue(localNames.contains { $0.hasPrefix("notes") })
        XCTAssertFalse(localNames.contains("tiny.txt"), "below the list minimum")
        XCTAssertFalse(localNames.contains(".DS_Store"))
        XCTAssertFalse(localNames.contains("dup.mov"), "Google Drive shortcut targets are excluded")
        XCTAssertFalse(localNames.contains("secret.mov"), "ignore list is honoured")
        XCTAssertFalse(localNames.contains("Link.mov"), "symlinks are never followed")
        XCTAssertEqual(localNames.filter { $0.hasPrefix("notes") }.count, 1, "hard links count once")

        XCTAssertEqual(report.largestCloudOnly.map(\.name), ["archive.mov", "old.zip"])
        XCTAssertTrue(report.largestCloudOnly.allSatisfy { $0.isCloudOnly && $0.localBytes == 0 })
    }

    func testPackagesAreSingleDocuments() throws {
        let report = scan()
        let package = try XCTUnwrap(report.largestLocal.first { $0.name == "Report.pages" })
        XCTAssertTrue(package.isPackage)
        XCTAssertEqual(package.fileCount, 2)
        XCTAssertEqual(package.logicalSize, 1_600_000)
        XCTAssertFalse(package.isCloudOnly)
        XCTAssertFalse(report.largestLocal.contains { $0.name == "image.png" })
    }

    func testListsAreLimitedAndSorted() {
        let report = scan(CloudStorageScanOptions(largeFileThreshold: 2_000_000, listMinimumSize: 0,
                                                  localListLimit: 2, cloudListLimit: 1))
        XCTAssertEqual(report.largestLocal.count, 2)
        XCTAssertEqual(report.largestLocal.first?.name, "trip.mov")
        XCTAssertEqual(report.largestCloudOnly.map(\.name), ["archive.mov"])
    }

    func testCancelledScanIsMarkedIncomplete() {
        let report = CloudStorageScanner.scan(provider, isCancelled: { true })
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.stats.fileCount, 0)
    }

    func testMissingRootIsAccessDenied() {
        let missing = CloudStorageProvider(kind: .box, mechanism: .fileProvider, rootPath: root + "/nope")
        let report = CloudStorageScanner.scan(missing)
        XCTAssertTrue(report.accessDenied)
        XCTAssertTrue(report.stats.isEmpty)
    }

    func testProgressReportsFinish() {
        final class Box: @unchecked Sendable {
            var ticks: [CloudStorageScanTick] = []
            let lock = NSLock()
        }
        let box = Box()
        _ = CloudStorageScanner.scan(provider, progress: { tick in
            box.lock.lock()
            box.ticks.append(tick)
            box.lock.unlock()
        })
        XCTAssertEqual(box.ticks.last?.finished, true)
        XCTAssertEqual(box.ticks.last?.providerID, root)
    }

    func testICloudDesktopAndDocumentsAreMarked() throws {
        try fm.createDirectory(atPath: root + "/Documents", withIntermediateDirectories: true)
        try write(root + "/Documents/thesis.pdf", bytes: 1_500_000)
        let iCloud = CloudStorageProvider(kind: .iCloudDrive, mechanism: .iCloud, rootPath: root)
        let report = CloudStorageScanner.scan(iCloud)
        XCTAssertEqual(report.largestLocal.first { $0.name == "thesis.pdf" }?.area, .desktopAndDocuments)
        XCTAssertEqual(report.largestLocal.first { $0.name == "trip.mov" }?.area, .drive)
    }

    func testAppFoldersAreScannedAsAppArea() throws {
        let appDocs = root + "-app/Documents"
        try fm.createDirectory(atPath: appDocs, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: root + "-app") }
        try write(appDocs + "/letter.txt", bytes: 1_300_000)
        let iCloud = CloudStorageProvider(kind: .iCloudDrive, mechanism: .iCloud, rootPath: root, additionalRoots: [appDocs])
        let report = CloudStorageScanner.scan(iCloud)
        let letter = try XCTUnwrap(report.largestLocal.first { $0.name == "letter.txt" })
        XCTAssertEqual(letter.area, .appFolder)
        XCTAssertTrue(letter.relativePath(in: iCloud).hasSuffix("/letter.txt"))
    }

    func testRemeasureSeesFreedFile() throws {
        let report = scan()
        let trip = try XCTUnwrap(report.largestLocal.first { $0.name == "trip.mov" })
        // Simulate eviction: the file keeps its size but loses its blocks.
        try fm.removeItem(atPath: trip.path)
        try sparse(trip.path, bytes: Int(trip.logicalSize))
        let after = try XCTUnwrap(CloudStorageScanner.remeasure(trip))
        XCTAssertTrue(after.isCloudOnly)
        XCTAssertEqual(after.localBytes, 0)
        XCTAssertTrue(CloudStorageEvictionPlanner.isFreed(before: trip, after: after))

        let updated = report.applying([after], largeThreshold: 2_000_000)
        XCTAssertEqual(updated.stats.localBytes, report.stats.localBytes - trip.localBytes)
        XCTAssertEqual(updated.stats.cloudOnlyFileCount, report.stats.cloudOnlyFileCount + 1)
        XCTAssertEqual(updated.stats.largeLocalCount, report.stats.largeLocalCount - 1)
        XCTAssertEqual(updated.stats.fileCount, report.stats.fileCount)
        XCTAssertFalse(updated.largestLocal.contains { $0.path == trip.path })
        XCTAssertEqual(updated.largestCloudOnly.map(\.name), ["archive.mov", "trip.mov", "old.zip"])

        try fm.removeItem(atPath: trip.path)
        XCTAssertNil(CloudStorageScanner.remeasure(trip))
    }

    // MARK: Ignore from now on

    func testRemovingTakesFilesOutOfListsAndTotals() throws {
        let report = scan()
        let trip = try XCTUnwrap(report.largestLocal.first { $0.name == "trip.mov" })
        let archive = try XCTUnwrap(report.largestCloudOnly.first { $0.name == "archive.mov" })
        let removed = report.removing(where: { $0.path == trip.path || $0.path == archive.path },
                                      largeThreshold: 2_000_000)

        XCTAssertFalse(removed.largestLocal.contains { $0.path == trip.path })
        XCTAssertFalse(removed.largestCloudOnly.contains { $0.path == archive.path })
        XCTAssertEqual(removed.largestLocal.count, report.largestLocal.count - 1)
        XCTAssertEqual(removed.largestCloudOnly.map(\.name), ["old.zip"])
        XCTAssertEqual(removed.stats.localBytes, report.stats.localBytes - trip.localBytes)
        XCTAssertEqual(removed.stats.localFileCount, report.stats.localFileCount - 1)
        XCTAssertEqual(removed.stats.largeLocalCount, report.stats.largeLocalCount - 1)
        XCTAssertEqual(removed.stats.cloudOnlyBytes, report.stats.cloudOnlyBytes - archive.logicalSize)
        XCTAssertEqual(removed.stats.cloudOnlyFileCount, report.stats.cloudOnlyFileCount - 1)
        XCTAssertEqual(removed.stats.fileCount, report.stats.fileCount - 2)
        XCTAssertEqual(removed.stats.cloudBytes, report.stats.cloudBytes - trip.cloudBytes - archive.cloudBytes)

        let untouched = report.removing(where: { _ in false }, largeThreshold: 2_000_000)
        XCTAssertEqual(untouched, report)
    }

    func testRemovingIgnoredMatchesAScanWithTheIgnoreList() throws {
        let report = scan()
        var settings = SpruceSettings()
        XCTAssertEqual(report.removingIgnored(settings, largeThreshold: 2_000_000), report,
                       "an empty ignore list changes nothing")

        settings.ignoredPaths = [root + "/Videos"]
        settings.ignoredItemIDs = [root + "/Docs/notes.txt"]
        let ignoreList = settings
        let filtered = report.removingIgnored(ignoreList, largeThreshold: 2_000_000)
        let rescanned = scan(CloudStorageScanOptions(largeFileThreshold: 2_000_000,
                                                     isIgnored: { ignoreList.isIgnored(path: $0) }))

        XCTAssertFalse(filtered.largestLocal.contains { $0.name == "trip.mov" })
        XCTAssertFalse(filtered.largestCloudOnly.contains { $0.name == "archive.mov" })
        XCTAssertFalse(filtered.largestLocal.contains { $0.path == root + "/Docs/notes.txt" })
        XCTAssertEqual(filtered.largestCloudOnly.map(\.name), rescanned.largestCloudOnly.map(\.name))
        XCTAssertEqual(filtered.stats.cloudOnlyBytes, rescanned.stats.cloudOnlyBytes)
        XCTAssertEqual(filtered.stats.cloudOnlyFileCount, rescanned.stats.cloudOnlyFileCount)
        XCTAssertEqual(filtered.stats.largeLocalCount, rescanned.stats.largeLocalCount)
    }

    // MARK: Quick Look availability

    func testAvailabilityTellsLocalFromOnlineOnly() throws {
        XCTAssertEqual(CloudStorageScanner.availability(at: root + "/Videos/trip.mov"), .local)
        XCTAssertEqual(CloudStorageScanner.availability(at: root + "/Videos/archive.mov"), .cloud)
        XCTAssertEqual(CloudStorageScanner.availability(at: root + "/Report.pages"), .local)
        XCTAssertEqual(CloudStorageScanner.availability(at: root + "/nothing-here.mov"), .missing)
        XCTAssertEqual(CloudStorageScanner.availability(at: root + "/Link.mov"), .missing, "symlinks are never followed")

        // A package with one online-only file inside isn't fully on this Mac.
        try sparse(root + "/Report.pages/Data/preview.png", bytes: 1_000_000)
        XCTAssertEqual(CloudStorageScanner.availability(at: root + "/Report.pages"), .cloud)
    }
}
