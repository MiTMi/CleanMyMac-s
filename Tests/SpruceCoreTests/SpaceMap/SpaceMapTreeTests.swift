import Foundation
import XCTest
@testable import SpruceCore

/// Builds a small fixed tree:
/// /data (root)
///   movies/      a.mov 600, b.mov 300
///   docs/        x.pdf 50, deep/ y.txt 30
///   big.iso 400
///   tiny.txt 2
enum SpaceMapFixture {
    static func tree() -> SpaceMapNode {
        let movies = SpaceMapNode.folder("movies", children: [.file("b.mov", size: 300), .file("a.mov", size: 600)])
        let deep = SpaceMapNode.folder("deep", children: [.file("y.txt", size: 30)])
        let docs = SpaceMapNode.folder("docs", children: [.file("x.pdf", size: 50), deep])
        return SpaceMapNode.folder("Data", basePath: "/data",
                                   children: [.file("tiny.txt", size: 2), docs, .file("big.iso", size: 400), movies])
    }
}

final class SpaceMapNodeTests: XCTestCase {
    func testPostOrderAggregationAndOrder() {
        let root = SpaceMapFixture.tree()
        XCTAssertEqual(root.size, 600 + 300 + 50 + 30 + 400 + 2)
        XCTAssertEqual(root.fileCount, 6)
        XCTAssertEqual(root.folderCount, 3)
        XCTAssertEqual(root.children.map(\.name), ["movies", "big.iso", "docs", "tiny.txt"])
        XCTAssertEqual(root.child(named: "movies")?.children.map(\.name), ["a.mov", "b.mov"])
        XCTAssertEqual(root.child(named: "docs")?.size, 80)
        XCTAssertEqual(root.itemCount, 9)
    }

    func testPathsAncestryAndLookup() throws {
        let root = SpaceMapFixture.tree()
        let deep = try XCTUnwrap(root.node(atPath: "/data/docs/deep"))
        XCTAssertEqual(deep.path, "/data/docs/deep")
        XCTAssertEqual(deep.ancestry.map(\.name), ["Data", "docs", "deep"])
        XCTAssertEqual(deep.depth, 2)
        XCTAssertTrue(deep.root === root)
        XCTAssertTrue(deep.isDescendant(of: root))
        XCTAssertFalse(root.isDescendant(of: deep))
        XCTAssertEqual(root.childOnPath(to: deep)?.name, "docs")
        XCTAssertNil(root.node(atPath: "/data/nope"))
        XCTAssertNil(root.node(atPath: "/elsewhere"))
        XCTAssertEqual(root.node(atPath: "/data")?.name, "Data")
        XCTAssertEqual(deep.url?.path, "/data/docs/deep")
    }

    func testRootAtSlashBuildsChildPaths() {
        let root = SpaceMapNode.folder("Macintosh HD", basePath: "/", children: [.folder("Users", children: [])])
        XCTAssertEqual(root.children.first?.path, "/Users")
    }

    func testDetachPropagatesToAncestors() throws {
        let root = SpaceMapFixture.tree()
        let deep = try XCTUnwrap(root.node(atPath: "/data/docs/deep"))
        deep.detach()
        XCTAssertNil(deep.parent)
        XCTAssertEqual(root.child(named: "docs")?.size, 50)
        XCTAssertEqual(root.size, 1382 - 30)
        XCTAssertEqual(root.fileCount, 5)
        XCTAssertEqual(root.folderCount, 2)

        let movie = try XCTUnwrap(root.node(atPath: "/data/movies/a.mov"))
        movie.detach()
        // movies (300) now sorts below big.iso (400).
        XCTAssertEqual(root.children.map(\.name), ["big.iso", "movies", "docs", "tiny.txt"])
    }

    func testReplaceContentsAppliesDelta() throws {
        let root = SpaceMapFixture.tree()
        let docs = try XCTUnwrap(root.child(named: "docs"))
        let fresh = SpaceMapNode.folder("docs", children: [.file("x.pdf", size: 50), .file("new.key", size: 2000)])
        docs.replaceContents(with: fresh)
        XCTAssertEqual(docs.size, 2050)
        XCTAssertEqual(docs.children.map(\.name), ["new.key", "x.pdf"])
        XCTAssertTrue(docs.children.allSatisfy { $0.parent === docs })
        XCTAssertEqual(root.size, 1382 - 80 + 2050)
        XCTAssertEqual(root.children.first?.name, "docs")
        XCTAssertEqual(root.fileCount, 6 - 2 + 2)
        XCTAssertEqual(root.folderCount, 2)
    }

    func testInsertChildAddsPseudoNode() {
        let root = SpaceMapFixture.tree()
        let system = SpaceMapNode(name: SpaceMapAccounting.systemNodeName, kind: .system, size: 5000)
        root.insertChild(system)
        XCTAssertEqual(root.size, 1382 + 5000)
        XCTAssertTrue(root.children.first === system)
        XCTAssertFalse(system.isReal)
        XCTAssertNil(system.url)
    }
}

final class SpaceMapPresentationTests: XCTestCase {
    private func files(_ sizes: [Int64]) -> SpaceMapNode {
        let children = sizes.enumerated().map { SpaceMapNode.file("f\($0.offset)", size: $0.element) }
        return SpaceMapNode.folder("root", basePath: "/r", children: children)
    }

    func testGroupingRespectsLimit() {
        let folder = files((1...40).map { Int64(1000 - $0) })
        let grouped = SpaceMapGrouping.group(folder.children, limit: 24, minShare: 0)
        XCTAssertEqual(grouped.visible.count, 24)
        XCTAssertEqual(grouped.smaller?.count, 16)
        XCTAssertEqual(grouped.smaller?.bytes, folder.children.suffix(16).reduce(0) { $0 + $1.size })
        XCTAssertEqual(grouped.smaller?.title, "16 smaller items")
    }

    func testGroupingFoldsTinySharesButKeepsLargest() {
        let folder = files([100_000, 50_000, 10, 9, 8])
        let grouped = SpaceMapGrouping.group(folder.children, limit: 24, minShare: 0.01)
        XCTAssertEqual(grouped.visible.map(\.size), [100_000, 50_000])
        XCTAssertEqual(grouped.smaller?.count, 3)

        let single = files([100_000, 50_000, 10])
        let groupedSingle = SpaceMapGrouping.group(single.children, limit: 24, minShare: 0.01)
        XCTAssertEqual(groupedSingle.visible.count, 3, "a lone leftover is shown on its own")
        XCTAssertNil(groupedSingle.smaller)

        let zeros = files([0, 0, 0])
        XCTAssertEqual(SpaceMapGrouping.group(zeros.children).visible.count, 3)
        XCTAssertTrue(SpaceMapGrouping.group([]).visible.isEmpty)
    }

    func testBreadcrumbsCollapseTheMiddle() {
        var node = SpaceMapNode.folder("leaf", children: [])
        for name in ["e", "d", "c", "b", "a"] {
            node = SpaceMapNode.folder(name, children: [node])
        }
        let root = SpaceMapNode.folder("Disk", basePath: "/", children: [node])
        guard let leaf = root.node(atPath: "/a/b/c/d/e/leaf") else { return XCTFail("missing leaf") }
        let crumbs = SpaceMapBreadcrumbs.trail(to: leaf, maxVisible: 5)
        XCTAssertEqual(crumbs.count, 5)
        guard case .node(let first) = crumbs[0], case .collapsed(let hidden) = crumbs[1],
              case .node(let last) = crumbs[4] else { return XCTFail("unexpected shape") }
        XCTAssertTrue(first === root)
        XCTAssertEqual(hidden.map(\.name), ["a", "b", "c"])
        XCTAssertTrue(last === leaf)
        XCTAssertEqual(SpaceMapBreadcrumbs.trail(to: root).count, 1)
    }

    func testSelectionDropsCoveredDescendants() throws {
        let root = SpaceMapFixture.tree()
        let docs = try XCTUnwrap(root.child(named: "docs"))
        let pdf = try XCTUnwrap(root.node(atPath: "/data/docs/x.pdf"))
        let iso = try XCTUnwrap(root.child(named: "big.iso"))
        let system = SpaceMapNode(name: "System", kind: .system, size: 10)
        root.insertChild(system)
        let topmost = SpaceMapSelection.topmost([pdf, docs, iso, iso, system])
        XCTAssertEqual(topmost.map(\.name), ["docs", "big.iso"])
        XCTAssertEqual(SpaceMapSelection.totalBytes([pdf, docs, iso]), 480)
        XCTAssertEqual(SpaceMapSelection.totalFiles([pdf, docs, iso]), 3)
        let ancestors = SpaceMapSelection.ancestorIDs(of: [pdf])
        XCTAssertTrue(ancestors.contains(docs.id))
        XCTAssertTrue(ancestors.contains(root.id))
        XCTAssertFalse(ancestors.contains(pdf.id))
    }

    func testHistorySkipsDetachedFolders() throws {
        let root = SpaceMapFixture.tree()
        let docs = try XCTUnwrap(root.child(named: "docs"))
        let deep = try XCTUnwrap(root.node(atPath: "/data/docs/deep"))
        let movies = try XCTUnwrap(root.child(named: "movies"))
        var history = SpaceMapHistory()
        history.leave(root)       // root → docs
        history.leave(docs)       // docs → deep
        XCTAssertTrue(history.canGoBack)
        let back = history.goBack(from: deep, root: root)
        XCTAssertTrue(back === docs)
        XCTAssertTrue(history.canGoForward)
        let forward = history.goForward(from: docs, root: root)
        XCTAssertTrue(forward === deep)

        history.leave(deep)       // deep → movies
        docs.detach()             // deep left the tree with docs
        let skipped = history.goBack(from: movies, root: root)
        XCTAssertTrue(skipped === root, "detached entries are skipped")
        history.reset()
        XCTAssertFalse(history.canGoBack)
    }
}

final class SpaceMapAccountingTests: XCTestCase {
    func testVolumeFigures() {
        let volume = SpaceMapVolumeInfo(name: "Macintosh HD", capacity: 1000, available: 300,
                                        availableForImportantUsage: 450)
        XCTAssertEqual(volume.used, 700)
        XCTAssertEqual(volume.purgeable, 150)
        XCTAssertEqual(volume.availableIncludingPurgeable, 450)
        XCTAssertEqual(volume.usedFraction, 0.7, accuracy: 1e-9)
        XCTAssertEqual(volume.unattributedBytes(scanned: 500), 200)
        XCTAssertEqual(volume.unattributedBytes(scanned: 900), 0)
        let plain = SpaceMapVolumeInfo(name: "USB", capacity: 100, available: 40)
        XCTAssertEqual(plain.purgeable, 0)
    }

    func testSystemNodeIsCapacityMinusFreeMinusScanned() {
        let root = SpaceMapFixture.tree()   // 1382 bytes scanned
        let volume = SpaceMapVolumeInfo(name: "Disk", capacity: 10_000, available: 4_000,
                                        availableForImportantUsage: 5_000)
        let node = SpaceMapAccounting.attachSystemNode(to: root, volume: volume, minimumBytes: 1)
        XCTAssertEqual(node?.size, 6_000 - 1382)
        XCTAssertEqual(root.size, 6_000)
        XCTAssertEqual(node?.kind, .system)
        XCTAssertNil(SpaceMapAccounting.attachSystemNode(to: SpaceMapFixture.tree(), volume: volume, minimumBytes: 10_000))
        let detail = SpaceMapAccounting.systemNodeDetail(volume: volume, unreadableFolders: 3)
        XCTAssertTrue(detail.contains("purgeable"))
        XCTAssertTrue(detail.contains("3 folders"))
    }

    func testTargetSubtitles() {
        let volume = SpaceMapVolumeInfo(name: "Macintosh HD", capacity: 500_000_000_000, available: 200_000_000_000)
        let startup = SpaceMapTarget(kind: .startup, path: "/", title: "Macintosh HD", symbol: "internaldrive", volume: volume)
        XCTAssertTrue(startup.coversWholeVolume)
        XCTAssertEqual(startup.subtitle, "300 GB used of 500 GB")
        let folder = SpaceMapTarget(kind: .folder, path: "/opt/data", title: "data", symbol: "folder")
        XCTAssertFalse(folder.coversWholeVolume)
        XCTAssertEqual(folder.subtitle, "/opt/data")
        XCTAssertNotEqual(startup.id, folder.id)
    }
}

final class SpaceMapCatalogTests: XCTestCase {
    func testFileTypes() {
        XCTAssertEqual(SpaceMapFileType.forFileName("Trip.MOV"), .video)
        XCTAssertEqual(SpaceMapFileType.forFileName("song.flac"), .audio)
        XCTAssertEqual(SpaceMapFileType.forFileName("IMG_1.heic"), .image)
        XCTAssertEqual(SpaceMapFileType.forFileName("Installer.dmg"), .diskImage)
        XCTAssertEqual(SpaceMapFileType.forFileName("backup.tar.gz"), .archive)
        XCTAssertEqual(SpaceMapFileType.forFileName("Report.pdf"), .document)
        XCTAssertEqual(SpaceMapFileType.forFileName("main.swift"), .code)
        XCTAssertEqual(SpaceMapFileType.forFileName("README"), .other)
        let app = SpaceMapNode.folder("Xcode.app", kind: .package, children: [])
        XCTAssertEqual(SpaceMapFileType.of(app), .application)
        XCTAssertEqual(SpaceMapFileType.of(SpaceMapNode.folder("Photos Library.photoslibrary", kind: .package, children: [])), .package)
        XCTAssertFalse(SpaceMapFileType.video.symbol.isEmpty)
        XCTAssertTrue(SpaceMapCatalog.isPackage(name: "Final Cut.fcpbundle"))
        XCTAssertFalse(SpaceMapCatalog.isPackage(name: "folder.with.dots"))
    }

    func testKnownFolderDescriptions() {
        let home = "/Users/tester"
        XCTAssertEqual(SpaceMapCatalog.description(forPath: home, home: home), "Your home folder")
        XCTAssertNotNil(SpaceMapCatalog.description(forPath: home + "/Library/Caches", home: home))
        XCTAssertNotNil(SpaceMapCatalog.description(forPath: home + "/Downloads/", home: home))
        XCTAssertNotNil(SpaceMapCatalog.description(forPath: "/System", home: home))
        XCTAssertNotNil(SpaceMapCatalog.description(forPath: "/var/folders", home: home))
        XCTAssertNil(SpaceMapCatalog.description(forPath: home + "/Projects/app", home: home))
    }

    func testProtectionReasons() throws {
        let home = NSTemporaryDirectory() + "spacemap-home-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/Projects", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let guardian = PathGuard(home: home)

        let project = SpaceMapNode.folder("Projects", children: [.file("big.bin", size: 10)])
        let documents = SpaceMapNode.folder("Documents", children: [])
        let library = SpaceMapNode.folder("Library", children: [
            .folder("CloudStorage", children: [.folder("Dropbox", children: [])]),
            .folder("Caches", children: [.folder("com.example", children: [])]),
        ])
        let root = SpaceMapNode.folder("Home", basePath: home, children: [project, documents, library])
        let system = SpaceMapNode(name: "System", kind: .system, size: 1)
        root.insertChild(system)

        XCTAssertNil(SpaceMapCatalog.protectionReason(for: project, guardian: guardian))
        let bin = try XCTUnwrap(root.node(atPath: home + "/Projects/big.bin"))
        XCTAssertNil(SpaceMapCatalog.protectionReason(for: bin, guardian: guardian))
        XCTAssertNotNil(SpaceMapCatalog.protectionReason(for: documents, guardian: guardian), "standard folders stay")
        XCTAssertNotNil(SpaceMapCatalog.protectionReason(for: root, guardian: guardian))
        XCTAssertNotNil(SpaceMapCatalog.protectionReason(for: system, guardian: guardian))
        let dropbox = try XCTUnwrap(root.node(atPath: home + "/Library/CloudStorage/Dropbox"))
        XCTAssertEqual(SpaceMapCatalog.protectionReason(for: dropbox, guardian: guardian),
                       "Cloud files; manage them in Cloud Storage")
        let cache = try XCTUnwrap(root.node(atPath: home + "/Library/Caches/com.example"))
        XCTAssertNil(SpaceMapCatalog.protectionReason(for: cache, guardian: guardian))

        var settings = SpruceSettings()
        settings.ignoredPaths = [home + "/Projects"]
        XCTAssertEqual(SpaceMapCatalog.protectionReason(for: bin, guardian: guardian, settings: settings),
                       "On your ignore list")
    }
}
