import Foundation
import XCTest
@testable import SpruceCore

final class SpaceMapScannerTests: XCTestCase {
    private var root: String = ""

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "spacemap-scan-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/Movies/Trips", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Docs", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Many", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Skip/Inner", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Photo.photoslibrary/originals", withIntermediateDirectories: true)
        try write(root + "/Movies/Trips/rome.mov", bytes: 300_000)
        try write(root + "/Movies/clip.mp4", bytes: 120_000)
        try write(root + "/Docs/report.pdf", bytes: 20_000)
        try write(root + "/Docs/.hidden", bytes: 5_000)
        try write(root + "/Skip/Inner/secret.bin", bytes: 500_000)
        try write(root + "/Photo.photoslibrary/originals/img.heic", bytes: 40_000)
        for i in 0..<12 {
            try write(root + "/Many/file\(i).txt", bytes: 1_000 + i * 100)
        }
        try write(root + "/Many/large.bin", bytes: 90_000)
        try write(root + "/big.iso", bytes: 200_000)
        try fm.linkItem(atPath: root + "/big.iso", toPath: root + "/Docs/big-link.iso")
        try fm.createSymbolicLink(atPath: root + "/Docs/movies-link", withDestinationPath: root + "/Movies")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func write(_ path: String, bytes: Int) throws {
        var data = Data(count: bytes)
        // Non-zero content so no file system stores it sparsely.
        data.withUnsafeMutableBytes { buffer in
            for i in stride(from: 0, to: buffer.count, by: 512) { buffer[i] = UInt8(truncatingIfNeeded: i / 512 + 1) }
        }
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func scan(_ options: SpaceMapScanOptions = SpaceMapScanOptions(workers: 4)) async throws -> SpaceMapScanOutput {
        try await SpaceMapScanner.scan(path: root, options: options)
    }

    func testTotalsMatchDiskUsageWithHardLinksCountedOnce() async throws {
        let output = try await scan()
        let expected = DiskUsage.measure(root)
        XCTAssertEqual(output.root.size, expected.bytes)
        XCTAssertEqual(output.stats.bytes, expected.bytes)
        XCTAssertEqual(output.root.path, SpaceMapScanner.standardize(root))
        XCTAssertGreaterThan(output.stats.folders, 5)
        XCTAssertEqual(output.stats.fraction, 1)
        // Both directory entries of the hard link exist, only one carries the bytes.
        let iso = try XCTUnwrap(output.root.child(named: "big.iso"))
        let link = try XCTUnwrap(output.root.node(atPath: SpaceMapScanner.standardize(root) + "/Docs/big-link.iso"))
        XCTAssertEqual(min(iso.size, link.size), 0)
        XCTAssertGreaterThan(max(iso.size, link.size), 0)
    }

    func testTreeShapeOrderAndKinds() async throws {
        let output = try await scan()
        let tree = output.root
        let sizes = tree.children.map(\.size)
        XCTAssertEqual(sizes, sizes.sorted(by: >), "children are largest first")
        let movies = try XCTUnwrap(tree.child(named: "Movies"))
        XCTAssertEqual(movies.kind, .directory)
        XCTAssertEqual(movies.fileCount, 2)
        XCTAssertEqual(movies.folderCount, 1)
        XCTAssertEqual(movies.children.first?.name, "Trips")
        let library = try XCTUnwrap(tree.child(named: "Photo.photoslibrary"))
        XCTAssertEqual(library.kind, .package)
        XCTAssertEqual(library.fileCount, 1, "packages are measured inside")
        let docs = try XCTUnwrap(tree.child(named: "Docs"))
        let link = try XCTUnwrap(docs.child(named: "movies-link"))
        XCTAssertEqual(link.kind, .symlink)
        XCTAssertLessThan(link.size, 100_000, "symlinks are never followed")
        XCTAssertNotNil(docs.child(named: ".hidden"))
        XCTAssertTrue(tree.children.allSatisfy { $0.parent === tree })
        XCTAssertGreaterThan(movies.modified?.timeIntervalSince1970 ?? 0, 0)
        XCTAssertNotEqual(movies.inode, 0)
    }

    func testFoldingKeepsLargestFiles() async throws {
        let options = SpaceMapScanOptions(fold: SpaceMapFoldPolicy(maxFilesPerFolder: 3, alwaysKeepBytes: 80_000), workers: 2)
        let output = try await scan(options)
        let many = try XCTUnwrap(output.root.child(named: "Many"))
        XCTAssertEqual(many.fileCount, 13)
        let folded = many.children.filter { $0.kind == .smallFiles }
        XCTAssertEqual(folded.count, 1)
        XCTAssertEqual(folded.first?.fileCount, 10)
        XCTAssertEqual(many.children.filter { $0.kind == .file }.count, 3)
        XCTAssertNotNil(many.child(named: "large.bin"))
        XCTAssertEqual(folded.first?.name, "10 smaller files")
        XCTAssertFalse(folded.first?.isReal ?? true)
        XCTAssertEqual(many.size, DiskUsage.measure(root + "/Many").bytes)
    }

    func testSmallFoldersWithManyItemsCollapseAndLoadInFull() async throws {
        let base = SpaceMapScanner.standardize(root)
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/Cache/a/b", withIntermediateDirectories: true)
        for i in 0..<30 { try write(root + "/Cache/a/f\(i).dat", bytes: 600) }
        for i in 0..<20 { try write(root + "/Cache/a/b/g\(i).dat", bytes: 600) }
        let full = try await scan()
        let policy = SpaceMapFoldPolicy(collapseBelowBytes: 10_000_000, collapseMinItems: 12)
        let output = try await scan(SpaceMapScanOptions(fold: policy, workers: 3))

        // Totals are exact, whatever is collapsed.
        XCTAssertEqual(output.root.size, full.root.size)
        XCTAssertEqual(output.root.fileCount, full.root.fileCount)
        XCTAssertEqual(output.root.folderCount, full.root.folderCount)
        XCTAssertFalse(output.root.isCollapsed, "the scan root is never collapsed")

        let cache = try XCTUnwrap(output.root.child(named: "Cache"))
        let fullCache = try XCTUnwrap(full.root.child(named: "Cache"))
        XCTAssertTrue(cache.isCollapsed)
        XCTAssertTrue(cache.children.isEmpty)
        XCTAssertTrue(cache.canZoom, "a collapsed folder can still be opened")
        XCTAssertEqual(cache.size, fullCache.size)
        XCTAssertEqual(cache.fileCount, 50)
        XCTAssertEqual(cache.folderCount, 2)
        // Folders with few items are kept as they are.
        let movies = try XCTUnwrap(output.root.child(named: "Movies"))
        XCTAssertFalse(movies.isCollapsed)
        XCTAssertNotNil(movies.child(named: "Trips"))
        XCTAssertEqual(output.stats.files, full.stats.files)

        // Loading the collapsed folder in full brings everything back without changing totals.
        let options = SpaceMapScanOptions(fold: policy, workers: 3).rescanning(cache, inFull: true)
        XCTAssertEqual(options.fold.collapseBelowBytes, 0)
        XCTAssertEqual(options.rootName, "Cache")
        XCTAssertEqual(options.expectedBytes, cache.size)
        let fresh = try await SpaceMapScanner.scan(path: base + "/Cache", options: options)
        let before = output.root.size
        cache.replaceContents(with: fresh.root)
        XCTAssertFalse(cache.isCollapsed)
        XCTAssertEqual(output.root.size, before)
        XCTAssertNotNil(output.root.node(atPath: base + "/Cache/a/b/g3.dat"))
        XCTAssertFalse(try XCTUnwrap(cache.child(named: "a")).isCollapsed)

        // A folder loaded in full that grew past the threshold is folded like a scan would.
        let sizeBefore = full.root.size
        let collapsedCount = policy.collapseDescendants(of: full.root)
        XCTAssertGreaterThan(collapsedCount, 0)
        XCTAssertTrue(try XCTUnwrap(full.root.child(named: "Cache")).isCollapsed)
        XCTAssertFalse(full.root.isCollapsed)
        XCTAssertEqual(full.root.size, sizeBefore)
        XCTAssertEqual(SpaceMapFoldPolicy().collapseDescendants(of: output.root), 0, "no threshold, nothing to do")
    }

    func testRescanOptionsKeepCollapsingUnlessLoadingInFull() {
        let node = SpaceMapNode.folder("Docs", children: [.file("a", size: 4_096)])
        let base = SpaceMapScanOptions(fold: SpaceMapFoldPolicy(collapseBelowBytes: 5_000_000), workers: 2,
                                       expectedBytes: 9_999, rootName: "Disk")
        let rescan = base.rescanning(node)
        XCTAssertEqual(rescan.fold.collapseBelowBytes, 5_000_000)
        XCTAssertEqual(rescan.rootName, "Docs")
        XCTAssertEqual(rescan.expectedBytes, 4_096)
        XCTAssertEqual(rescan.workers, 2)
        XCTAssertEqual(rescan.boundary, base.boundary)
        XCTAssertEqual(base.rescanning(node, inFull: true).fold.collapseBelowBytes, 0)
    }

    func testCollapseThresholdScalesWithTheVolume() {
        XCTAssertEqual(SpaceMapFoldPolicy.collapseThreshold(volumeUsed: nil), 16_000_000)
        XCTAssertEqual(SpaceMapFoldPolicy.collapseThreshold(volumeUsed: 0), 16_000_000)
        XCTAssertEqual(SpaceMapFoldPolicy.collapseThreshold(volumeUsed: 300_000_000_000), 30_000_000)
        XCTAssertEqual(SpaceMapFoldPolicy.collapseThreshold(volumeUsed: 2_000_000_000), 4_000_000)
        XCTAssertEqual(SpaceMapFoldPolicy.collapseThreshold(volumeUsed: 8_000_000_000_000), 256_000_000)
        XCTAssertEqual(SpaceMapFoldPolicy().collapseBelowBytes, 0, "collapsing is opt-in")
    }

    func testExclusionsAndHiddenFiles() async throws {
        let base = SpaceMapScanner.standardize(root)
        let options = SpaceMapScanOptions(boundary: SpaceMapBoundary(excludedPaths: [base + "/Skip"]),
                                          workers: 3, includeHidden: false)
        let output = try await scan(options)
        XCTAssertNil(output.root.child(named: "Skip"))
        XCTAssertNil(output.root.node(atPath: base + "/Docs/.hidden"))
        let skipBytes = DiskUsage.measure(root + "/Skip").bytes
        let hiddenBytes = DiskUsage.measure(root + "/Docs/.hidden").bytes
        XCTAssertEqual(output.root.size, DiskUsage.measure(root).bytes - skipBytes - hiddenBytes)
    }

    func testWorkerCountDoesNotChangeTotals() async throws {
        let single = try await scan(SpaceMapScanOptions(workers: 1))
        let many = try await scan(SpaceMapScanOptions(workers: 8))
        XCTAssertEqual(single.root.size, many.root.size)
        XCTAssertEqual(single.root.fileCount, many.root.fileCount)
        XCTAssertEqual(single.root.folderCount, many.root.folderCount)
        XCTAssertEqual(single.root.children.map(\.name), many.root.children.map(\.name))
    }

    func testProgressAndExpectedFraction() async throws {
        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: [SpaceMapScanStats] = []
            func append(_ stats: SpaceMapScanStats) {
                lock.lock()
                stored.append(stats)
                lock.unlock()
            }
            var reports: [SpaceMapScanStats] {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
        }
        let box = Box()
        let options = SpaceMapScanOptions(workers: 1, expectedBytes: 1)
        _ = try await SpaceMapScanner.scan(path: root, options: options) { stats in
            box.append(stats)
        }
        let reports = box.reports
        XCTAssertFalse(reports.isEmpty)
        XCTAssertTrue(reports.allSatisfy { ($0.fraction ?? 0) <= 0.99 })
    }

    func testFileRootAndMissingRoot() async throws {
        let output = try await SpaceMapScanner.scan(path: root + "/big.iso")
        XCTAssertEqual(output.root.kind, .file)
        XCTAssertEqual(output.root.fileCount, 1)
        do {
            _ = try await SpaceMapScanner.scan(path: root + "/does-not-exist")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SpruceError, .notFound(root + "/does-not-exist"))
        }
    }

    func testCancellationThrows() async throws {
        let path = root
        let task = Task {
            try await SpaceMapScanner.scan(path: path, options: SpaceMapScanOptions(workers: 2))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? SpruceError, .cancelled)
        }
    }

    func testRescanReplacesSubtree() async throws {
        let output = try await scan()
        let base = SpaceMapScanner.standardize(root)
        let docs = try XCTUnwrap(output.root.child(named: "Docs"))
        let before = output.root.size
        let docsBefore = docs.size
        try write(root + "/Docs/new.key", bytes: 250_000)
        let fresh = try await SpaceMapScanner.scan(path: base + "/Docs", options: SpaceMapScanOptions(workers: 2),
                                                   hardLinks: SpaceMapHardLinkRegistry())
        let freshSize = fresh.root.size
        docs.replaceContents(with: fresh.root)
        XCTAssertNotNil(output.root.node(atPath: base + "/Docs/new.key"))
        XCTAssertEqual(docs.size, freshSize)
        XCTAssertEqual(output.root.size, before - docsBefore + freshSize)
        XCTAssertGreaterThan(output.root.size, before + 240_000)
        XCTAssertTrue(docs.children.allSatisfy { $0.parent === docs })
    }

    func testStandardize() {
        XCTAssertEqual(SpaceMapScanner.standardize("/"), "/")
        XCTAssertEqual(SpaceMapScanner.standardize("//Users//me/"), "/Users/me")
        XCTAssertEqual(SpaceMapScanner.standardize("/a/./b"), "/a/b")
    }

    func testUnreadableFolderIsFlagged() async throws {
        #if canImport(Glibc) || canImport(Darwin)
        guard getuid() != 0 else { throw XCTSkip("root can read every folder") }
        #endif
        let locked = root + "/Locked"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        try write(locked + "/a.bin", bytes: 10_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
        let output = try await scan()
        XCTAssertEqual(output.root.child(named: "Locked")?.isUnreadable, true)
        XCTAssertEqual(output.stats.unreadableFolders, 1)
    }
}
