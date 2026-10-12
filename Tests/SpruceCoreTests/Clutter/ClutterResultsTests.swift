import Foundation
import XCTest
@testable import SpruceCore

final class ClutterImageHashTests: XCTestCase {
    /// A 64×48 synthetic "photo": smooth gradients plus a bright blob.
    private func image(seed: Int, noise: Int = 0, shift: Int = 0, invert: Bool = false) -> ClutterGrayImage {
        let w = 64, h = 48
        var pixels = [UInt8](repeating: 0, count: w * h)
        var state = UInt64(seed + 1) &* 0x9E3779B97F4A7C15
        for y in 0..<h {
            for x in 0..<w {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let jitter = noise == 0 ? 0 : Int(state >> 60) % (noise + 1) - noise / 2
                let xs = x + shift
                var v = (xs * 3 + y * 2 + seed * 37) % 256
                let dx = xs - (20 + seed * 7) % w, dy = y - (16 + seed * 5) % h
                if dx * dx + dy * dy < 120 { v = 250 }
                v = min(255, max(0, v + jitter))
                pixels[y * w + x] = UInt8(invert ? 255 - v : v)
            }
        }
        return ClutterGrayImage(width: w, height: h, pixels: pixels)!
    }

    func testGradientHashes() {
        var pixels = [UInt8](repeating: 0, count: 90 * 80)
        for y in 0..<80 { for x in 0..<90 { pixels[y * 90 + x] = UInt8(x * 255 / 89) } }
        let gradient = ClutterGrayImage(width: 90, height: 80, pixels: pixels)!
        XCTAssertEqual(ClutterImageHasher.dHash(gradient), UInt64.max, "brightness increases left to right")
        let flat = ClutterGrayImage(width: 10, height: 10, pixels: [UInt8](repeating: 128, count: 100))!
        XCTAssertEqual(ClutterImageHasher.dHash(flat), 0)
        XCTAssertEqual(ClutterImageHasher.aHash(flat), 0)
        let aHash = ClutterImageHasher.aHash(gradient)
        // Right half brighter than the mean → each row is 00001111.
        XCTAssertEqual(aHash, 0x0F0F0F0F0F0F0F0F)
    }

    func testResampleAveragesAndHandlesTinyImages() {
        let image = ClutterGrayImage(width: 2, height: 2, pixels: [0, 100, 200, 255])!
        XCTAssertEqual(ClutterImageHasher.resample(image, width: 1, height: 1), [138.75])
        let up = ClutterImageHasher.resample(image, width: 4, height: 4)
        XCTAssertEqual(up.count, 16)
        XCTAssertEqual(up[0], 0)
        XCTAssertEqual(up[15], 255)
        XCTAssertNil(ClutterGrayImage(width: 3, height: 3, pixels: [1, 2]))
    }

    func testSimilarImagesAreCloseAndDifferentOnesFar() {
        let base = image(seed: 1)
        let noisy = image(seed: 1, noise: 6)
        let shifted = image(seed: 1, shift: 1)
        let other = image(seed: 9)
        let d = ClutterImageHasher.dHash
        XCTAssertLessThanOrEqual(ClutterImageHasher.hamming(d(base), d(noisy)), 7)
        XCTAssertLessThanOrEqual(ClutterImageHasher.hamming(d(base), d(shifted)), 7)
        XCTAssertGreaterThan(ClutterImageHasher.hamming(d(base), d(other)), 12)
        XCTAssertGreaterThan(ClutterImageHasher.hamming(d(base), d(image(seed: 1, invert: true))), 40)
    }

    func testBKTreeMatchesBruteForce() {
        var state: UInt64 = 12345
        var hashes: [UInt64] = []
        for _ in 0..<400 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            hashes.append(state)
        }
        // Add near neighbours so queries find something.
        for i in 0..<50 { hashes.append(hashes[i] ^ (1 << UInt64(i % 64)) ^ (1 << UInt64((i * 7) % 64))) }
        var tree = ClutterBKTree()
        for (i, h) in hashes.enumerated() { tree.insert(h, index: i) }
        XCTAssertEqual(tree.count, hashes.count)
        for probe in hashes.prefix(60) {
            for radius in [0, 2, 5, 20] {
                let expected = Set(hashes.indices.filter { ClutterImageHasher.hamming(hashes[$0], probe) <= radius })
                XCTAssertEqual(Set(tree.query(probe, radius: radius)), expected)
            }
        }
    }

    func testClusteringGroupsNearDuplicatesAndPicksBestShot() {
        let a = ClutterImageFingerprint(path: "/p/a.jpg", thumbnail: image(seed: 1), pixelWidth: 4000, pixelHeight: 3000)
        let b = ClutterImageFingerprint(path: "/p/b.jpg", thumbnail: image(seed: 1, noise: 6), pixelWidth: 1200, pixelHeight: 900)
        let c = ClutterImageFingerprint(path: "/p/c.jpg", thumbnail: image(seed: 1, shift: 1), pixelWidth: 4000, pixelHeight: 3000)
        let x = ClutterImageFingerprint(path: "/p/x.jpg", thumbnail: image(seed: 9), pixelWidth: 4000, pixelHeight: 3000)
        let y = ClutterImageFingerprint(path: "/p/y.jpg", thumbnail: image(seed: 23), pixelWidth: 4000, pixelHeight: 3000)
        let files = [
            clutterFile("/p/a.jpg", size: 3_000_000), clutterFile("/p/b.jpg", size: 500_000),
            clutterFile("/p/c.jpg", size: 3_500_000), clutterFile("/p/x.jpg"), clutterFile("/p/y.jpg"),
        ]
        let clusters = ClutterSimilarClusterer().clusters(files: files, prints: [x, b, a, y, c])
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters[0].files.map(\.path)), ["/p/a.jpg", "/p/b.jpg", "/p/c.jpg"])
        // Same pixel count: the larger file wins.
        XCTAssertEqual(clusters[0].bestPath, "/p/c.jpg")
        XCTAssertEqual(clusters[0].files.first?.path, "/p/c.jpg")
        XCTAssertEqual(clusters[0].reclaimableBytes, 3_500_000)
        XCTAssertTrue(clusters[0].id.hasPrefix("sim:"))
    }

    func testCompleteLinkageGuardPreventsChains() {
        // a–b and b–c are close, a–c is far: with a tight linkage radius they must not
        // end up in one cluster.
        let a = ClutterImageFingerprint(path: "/a", dHash: 0, aHash: 0, pixelWidth: 1, pixelHeight: 1)
        let b = ClutterImageFingerprint(path: "/b", dHash: 0b1111, aHash: 0, pixelWidth: 1, pixelHeight: 1)
        let c = ClutterImageFingerprint(path: "/c", dHash: 0b1111_1111, aHash: 0, pixelWidth: 1, pixelHeight: 1)
        let clusterer = ClutterSimilarClusterer(dHashRadius: 4, aHashRadius: 0, linkageRadius: 4)
        let clusters = clusterer.cluster([a, b, c])
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].count, 2)
        let loose = ClutterSimilarClusterer(dHashRadius: 4, aHashRadius: 0, linkageRadius: 8)
        XCTAssertEqual(loose.cluster([a, b, c]), [[0, 1, 2]])
    }
}

final class ClutterDownloadsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testCategories() {
        let cases: [(String, Bool, ClutterDownloadCategory)] = [
            ("/d/Setup.dmg", false, .installers), ("/d/a.pkg", false, .installers), ("/d/x.zip", false, .archives),
            ("/d/movie.mp4.crdownload", false, .incomplete), ("/d/big.iso.part", false, .incomplete),
            ("/d/file.download", false, .incomplete), ("/d/doc.pdf", false, .documents), ("/d/p.png", false, .images),
            ("/d/m.mov", false, .video), ("/d/s.mp3", false, .audio), ("/d/Folder", true, .folders),
            ("/d/thing.xyz", false, .other),
        ]
        for (path, isFolder, expected) in cases {
            XCTAssertEqual(ClutterDownloadsAnalyzer.category(for: clutterFile(path, isFolder: isFolder)), expected, path)
        }
    }

    func testQuarantineAndWhereFroms() {
        let parsed = ClutterDownloadsAnalyzer.parseQuarantine("0083;5fad2a6e;Safari;9B3F0F3D-1C3C-4C8B-9F0C-6B4F8E2C1A11")
        XCTAssertEqual(parsed.agent, "Safari")
        XCTAssertEqual(parsed.date, Date(timeIntervalSince1970: TimeInterval(0x5fad2a6e)))
        XCTAssertEqual(ClutterDownloadsAnalyzer.parseQuarantine("0081;5fad2a6e;sharingd;").agent, "AirDrop")
        XCTAssertNil(ClutterDownloadsAnalyzer.parseQuarantine("0081;zz;;").agent)
        XCTAssertNil(ClutterDownloadsAnalyzer.parseQuarantine("0081;zz;;").date)
        XCTAssertEqual(ClutterDownloadsAnalyzer.host(fromWhereFroms: ["https://www.github.com/x/y.zip", "https://github.com/"]),
                       "github.com")
        XCTAssertEqual(ClutterDownloadsAnalyzer.host(fromWhereFroms: ["file:///tmp/x", "http://cdn.example.org/a"]),
                       "cdn.example.org")
        XCTAssertNil(ClutterDownloadsAnalyzer.host(fromWhereFroms: ["not a url"]))
    }

    func testInstallerNames() {
        XCTAssertEqual(ClutterDownloadsAnalyzer.normalizedInstallerName("Firefox 120.0.1.dmg"), "firefox")
        XCTAssertEqual(ClutterDownloadsAnalyzer.normalizedInstallerName("VSCode-darwin-arm64.zip"), "vscode")
        XCTAssertEqual(ClutterDownloadsAnalyzer.normalizedInstallerName("Visual Studio Code-universal.dmg"), "visual studio code")
        XCTAssertEqual(ClutterDownloadsAnalyzer.normalizedInstallerName("Docker_Desktop_v4.25.2_arm64.dmg"), "docker desktop")
        let apps: Set<String> = ["firefox", "visual studio code", "docker", "google chrome"]
        XCTAssertTrue(ClutterDownloadsAnalyzer.installerMatchesInstalledApp("Firefox 120.0.1.dmg", appNames: apps))
        XCTAssertTrue(ClutterDownloadsAnalyzer.installerMatchesInstalledApp("googlechrome.dmg", appNames: apps))
        XCTAssertTrue(ClutterDownloadsAnalyzer.installerMatchesInstalledApp("Docker_Desktop_v4.25.2_arm64.dmg", appNames: apps))
        XCTAssertFalse(ClutterDownloadsAnalyzer.installerMatchesInstalledApp("Slack-4.35.dmg", appNames: apps))
    }

    func testItemsSelectionHintsAndSources() {
        let settings = ClutterScanSettings()
        let files = [
            clutterFile("/d/Old.dmg", size: 300, modified: now.addingTimeInterval(-60 * 86_400)),
            clutterFile("/d/New.dmg", size: 200, modified: now.addingTimeInterval(-2 * 86_400)),
            clutterFile("/d/stuck.crdownload", size: 100, modified: now.addingTimeInterval(-3 * 86_400)),
            clutterFile("/d/fresh.crdownload", size: 90, modified: now.addingTimeInterval(-3_600)),
            clutterFile("/d/photos.zip", size: 80, modified: now),
            clutterFile("/d/photos", size: 70, modified: now, isFolder: true),
        ]
        let meta: [String: ClutterDownloadMetadata] = [
            "/d/Old.dmg": ClutterDownloadMetadata(quarantine: "0083;5fad2a6e;Google Chrome;X",
                                                  whereFroms: ["https://dl.example.com/Old.dmg"]),
            "/d/New.dmg": ClutterDownloadMetadata(quarantine: "0083;5fad2a6e;Safari;X",
                                                  downloadedDate: now.addingTimeInterval(-2 * 86_400)),
        ]
        let items = ClutterDownloadsAnalyzer.items(from: files, metadata: meta, installedAppNames: ["old"])
        XCTAssertEqual(items.map(\.file.name), ["Old.dmg", "New.dmg", "stuck.crdownload", "fresh.crdownload", "photos.zip", "photos"])
        let old = items[0]
        XCTAssertEqual(old.sourceApp, "Google Chrome")
        XCTAssertEqual(old.sourceHost, "dl.example.com")
        XCTAssertTrue(old.installerAlreadyUsed)
        XCTAssertTrue(ClutterDownloadsAnalyzer.isOldInstaller(old, settings: settings, now: now),
                      "the quarantine time (2020) is the download date")
        XCTAssertTrue(items[4].archiveAlreadyExtracted)
        XCTAssertTrue(ClutterDownloadsAnalyzer.isStaleIncomplete(items[2], settings: settings, now: now))
        XCTAssertFalse(ClutterDownloadsAnalyzer.isStaleIncomplete(items[3], settings: settings, now: now))
        XCTAssertFalse(ClutterDownloadsAnalyzer.isOldInstaller(items[1], settings: settings, now: now))
        XCTAssertEqual(ClutterDownloadsAnalyzer.dominantSource(items), "Google Chrome")
    }
}

final class ClutterReportTests: XCTestCase {
    let paths = ClutterPaths(home: "/Users/test")
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func report() -> ClutterScanReport {
        let selection = ClutterSmartSelection(paths: paths)
        let keep = clutterFile("/Users/test/Documents/a.pdf", size: 1_000, modified: now.addingTimeInterval(-900_000), inode: 1)
        let copy = clutterFile("/Users/test/Downloads/a.pdf", size: 1_000, modified: now, inode: 2)
        let copy2 = clutterFile("/Users/test/Desktop/a copy.pdf", size: 1_000, modified: now, inode: 3)
        let dup = selection.makeGroup(hash: "abc", files: [copy, keep, copy2])
        let img1 = clutterFile("/Users/test/Pictures/1.jpg", size: 2_000)
        let img2 = clutterFile("/Users/test/Pictures/2.jpg", size: 3_000)
        let prints = [
            img1.path: ClutterImageFingerprint(path: img1.path, dHash: 0, aHash: 0, pixelWidth: 10, pixelHeight: 10),
            img2.path: ClutterImageFingerprint(path: img2.path, dHash: 1, aHash: 0, pixelWidth: 20, pixelHeight: 10),
        ]
        let sim = ClutterSimilarCluster(id: "sim:1", files: [img2, img1], fingerprints: prints, bestPath: img2.path)
        let big = ClutterLargeOldItem(file: clutterFile("/Users/test/Movies/big.mov", size: 90_000_000), reason: .large)
        let stuck = ClutterDownloadItem(file: clutterFile("/Users/test/Downloads/x.crdownload", size: 500,
                                                          modified: now.addingTimeInterval(-5 * 86_400)),
                                        category: .incomplete)
        let dmg = ClutterDownloadItem(file: clutterFile("/Users/test/Downloads/Tool.dmg", size: 4_000,
                                                        modified: now.addingTimeInterval(-90 * 86_400)),
                                      category: .installers, sourceApp: "Safari")
        let copyAsDownload = ClutterDownloadItem(file: copy, category: .documents)
        return ClutterScanReport(locations: ["~"], date: now, largeOld: [big], duplicates: [dup], similar: [sim],
                                 downloads: [dmg, stuck, copyAsDownload])
    }

    func testDefaultSelection() {
        let selected = report().defaultSelection(paths: paths, now: now)
        XCTAssertEqual(selected, ["/Users/test/Downloads/a.pdf", "/Users/test/Desktop/a copy.pdf",
                                  "/Users/test/Downloads/x.crdownload"])
    }

    func testReviewGroupsListEachFileOnce() {
        let groups = ClutterItems.reviewGroups(for: report(), paths: paths, now: now)
        let ids = groups.allItems.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(groups.map(\.id), ["clutter.duplicates", "clutter.similarImages", "clutter.downloads", "clutter.largeOld"])
        let dupItems = groups[0].allItems
        XCTAssertEqual(dupItems.filter(\.isSelected).count, 2)
        XCTAssertEqual(dupItems.first { $0.metadata[ClutterMetadataKey.keeper] == "1" }?.id, "/Users/test/Documents/a.pdf")
        XCTAssertTrue(dupItems.allSatisfy { $0.metadata[ClutterMetadataKey.set] == "dup:abc" })
        XCTAssertEqual(dupItems.first?.metadata[ClutterMetadataKey.inode], "1")
        XCTAssertTrue(groups[1].allItems.allSatisfy { !$0.isSelected }, "similar images start unselected")
        XCTAssertTrue(groups[3].allItems.allSatisfy { !$0.isSelected }, "large & old start unselected")
        let downloads = groups[2].allItems
        XCTAssertEqual(downloads.filter(\.isSelected).map(\.title), ["x.crdownload"])
        XCTAssertFalse(downloads.contains { $0.id == "/Users/test/Downloads/a.pdf" }, "already listed as a duplicate")
        XCTAssertTrue(groups.allItems.allSatisfy { $0.deletion == .trash })
    }

    func testRemovingPathsUpdatesSets() {
        var r = report()
        r.remove(paths: ["/Users/test/Documents/a.pdf"], clutterPaths: paths)
        XCTAssertEqual(r.duplicates.count, 1)
        XCTAssertEqual(r.duplicates[0].files.count, 2)
        XCTAssertEqual(r.duplicates[0].keeperPath, "/Users/test/Desktop/a copy.pdf", "outside Downloads wins")
        r.remove(paths: ["/Users/test/Desktop/a copy.pdf", "/Users/test/Pictures/2.jpg", "/Users/test/Movies/big.mov"],
                 clutterPaths: paths)
        XCTAssertTrue(r.duplicates.isEmpty)
        XCTAssertTrue(r.similar.isEmpty)
        XCTAssertTrue(r.largeOld.isEmpty)
        XCTAssertEqual(r.downloads.count, 3)
    }

    func testSummaries() {
        let r = report()
        let dup = r.summary(for: .duplicates)
        XCTAssertEqual(dup.itemCount, 2)
        XCTAssertEqual(dup.setCount, 1)
        XCTAssertEqual(dup.reclaimableBytes, 2_000)
        XCTAssertEqual(dup.headline, "2 duplicates found")
        XCTAssertEqual(r.summary(for: .similarImages).headline, "2 similar images found")
        XCTAssertEqual(r.summary(for: .largeOld).headline, "90 MB of large and old files")
        XCTAssertEqual(r.summary(for: .downloads).headline, "5.5 KB of Safari downloads")
        XCTAssertEqual(ClutterScanReport().summary(for: .duplicates).headline, "No duplicates")
        XCTAssertEqual(r.distinctFileCount, 8)
    }

    func testRemovalPlannerKeepsOneCopy() {
        let r = report()
        let groups = ClutterItems.reviewGroups(for: r, paths: paths, now: now)
        let dupItems = groups[0].allItems
        let present: (String) -> Bool = { _ in true }
        // Copies only: everything goes.
        let copiesOnly = ClutterRemovalPlanner.plan(dupItems.filter(\.isSelected), sets: r.setMembers,
                                                    preferredKeepers: r.preferredKeepers,
                                                    allowRemovingAllCopies: false, stillPresent: present)
        XCTAssertEqual(copiesOnly.items.count, 2)
        XCTAssertTrue(copiesOnly.heldBack.isEmpty)
        // All copies selected: the keeper is held back.
        let all = ClutterRemovalPlanner.plan(dupItems + dupItems, sets: r.setMembers, preferredKeepers: r.preferredKeepers,
                                             allowRemovingAllCopies: false, stillPresent: present)
        XCTAssertEqual(all.items.count, 2)
        XCTAssertEqual(all.heldBack.map(\.itemID), ["/Users/test/Documents/a.pdf"])
        // Explicit confirmation removes all.
        let confirmed = ClutterRemovalPlanner.plan(dupItems, sets: r.setMembers, preferredKeepers: r.preferredKeepers,
                                                   allowRemovingAllCopies: true, stillPresent: present)
        XCTAssertEqual(confirmed.items.count, 3)
        // Keeper vanished from disk: removing the copies would leave nothing.
        let vanished = ClutterRemovalPlanner.plan(dupItems.filter(\.isSelected), sets: r.setMembers,
                                                  preferredKeepers: r.preferredKeepers, allowRemovingAllCopies: false,
                                                  stillPresent: { $0 != "/Users/test/Documents/a.pdf" })
        XCTAssertEqual(vanished.items.count, 1)
        XCTAssertEqual(vanished.heldBack.count, 1)
    }

    func testCheckupReviewAndTile() {
        let r = report()
        let settings = ClutterScanSettings()
        let review = ClutterCheckupPlanner.review(duplicates: r.duplicates, downloads: r.downloads, paths: paths,
                                                  settings: settings, now: now)
        XCTAssertEqual(review.map(\.id), [ClutterCheckupPlanner.duplicatesGroupID, ClutterCheckupPlanner.installersGroupID])
        XCTAssertEqual(review[0].items.count, 2, "only the redundant copies are offered")
        XCTAssertTrue(review[0].items.allSatisfy(\.isSelected))
        XCTAssertEqual(review[1].items.map(\.title), ["Tool.dmg"])
        XCTAssertFalse(review[1].items[0].isSelected, "installers are review-only")
        let tile = ClutterCheckupPlanner.tile(for: review)
        XCTAssertEqual(tile.status, .attention)
        XCTAssertEqual(tile.reclaimableBytes, 2_000)
        XCTAssertEqual(tile.actionCount, 2)
        XCTAssertTrue(tile.detail.contains("1 old installer to review"))

        var deselected = review
        deselected[0].setAllSelected(false)
        let infoTile = ClutterCheckupPlanner.tile(for: deselected)
        XCTAssertEqual(infoTile.status, .info)
        XCTAssertFalse(infoTile.isSelected)
        XCTAssertEqual(ClutterCheckupPlanner.tile(for: []).status, .clear)
    }

    func testToolIDs() {
        XCTAssertEqual(ClutterTool(toolID: "clutter.largeOld"), .largeOld)
        XCTAssertEqual(ClutterTool(toolID: "clutter.similarImages"), .similarImages)
        XCTAssertNil(ClutterTool(toolID: "cleanup.trash"))
        XCTAssertEqual(ClutterTool.downloads.toolID, "clutter.downloads")
    }

    func testStageBoardFraction() {
        let board = ClutterStageBoard(stages: [.indexing, .duplicates])
        XCTAssertEqual(board.fraction, 0)
        board.set(.indexing, .done("1,000 files"))
        board.set(.duplicates, .running(0.5))
        XCTAssertEqual(board.fraction, (0.35 + 0.15) / 0.65, accuracy: 0.0001)
        board.set(.largeOld, .done("ignored"))
        XCTAssertEqual(board.state(of: .largeOld), .waiting)
        XCTAssertEqual(board.snapshot.map(\.stage), [.indexing, .duplicates])
    }
}
