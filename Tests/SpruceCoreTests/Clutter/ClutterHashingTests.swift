import Foundation
import XCTest
@testable import SpruceCore

final class ClutterSHA256Tests: XCTestCase {
    private let vectors: [(String, String)] = [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
         "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
        ("The quick brown fox jumps over the lazy dog",
         "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"),
    ]

    func testKnownVectorsSoftware() {
        for (input, expected) in vectors {
            var h = ClutterSoftwareSHA256()
            h.update(Data(input.utf8))
            XCTAssertEqual(ClutterHex.string(h.finalized()), expected, "software digest of \"\(input)\"")
        }
    }

    func testKnownVectorsPlatform() {
        for (input, expected) in vectors {
            XCTAssertEqual(ClutterSHA256.hex(input), expected, "platform digest of \"\(input)\"")
        }
    }

    func testMillionA() {
        let data = Data(repeating: 0x61, count: 1_000_000)
        let expected = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        var soft = ClutterSoftwareSHA256()
        soft.update(data)
        XCTAssertEqual(ClutterHex.string(soft.finalized()), expected)
        XCTAssertEqual(ClutterSHA256.hex(data), expected)
    }

    func testIncrementalMatchesOneShot() {
        let data = ClutterFixture.noise(10_007, seed: 42)
        let oneShot = ClutterSHA256.hex(data)
        for chunk in [1, 3, 63, 64, 65, 127, 1000] {
            var soft = ClutterSoftwareSHA256()
            var platform = ClutterSHA256()
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunk, data.count)
                soft.update(data.subdata(in: offset..<end))
                platform.update(data.subdata(in: offset..<end))
                offset = end
            }
            XCTAssertEqual(ClutterHex.string(soft.finalized()), oneShot, "chunk \(chunk)")
            XCTAssertEqual(ClutterHex.string(platform.finalized()), oneShot, "chunk \(chunk)")
        }
    }

    func testPaddingBoundaries() {
        // Lengths around the 55/56/64-byte padding edges must agree between implementations.
        for length in [54, 55, 56, 57, 63, 64, 65, 119, 120, 128] {
            let data = ClutterFixture.noise(length, seed: UInt64(length))
            var soft = ClutterSoftwareSHA256()
            soft.update(data)
            XCTAssertEqual(ClutterHex.string(soft.finalized()), ClutterSHA256.hex(data), "length \(length)")
        }
    }

    func testFinalizedDoesNotConsume() {
        var h = ClutterSoftwareSHA256()
        h.update(Data("ab".utf8))
        _ = h.finalized()
        h.update(Data("c".utf8))
        XCTAssertEqual(ClutterHex.string(h.finalized()), vectors[1].1)
    }
}

final class ClutterFileHasherTests: XCTestCase {
    var fixture: ClutterFixture!

    override func setUp() { fixture = ClutterFixture() }
    override func tearDown() { fixture.remove() }

    func testFullHashMatchesDataHash() {
        let data = ClutterFixture.noise(3_000_000, seed: 7)
        let path = fixture.file("Documents/big.bin", contents: data)
        XCTAssertEqual(ClutterFileHasher.fullHash(path: path, expectedSize: Int64(data.count)), ClutterSHA256.hex(data))
        XCTAssertNil(ClutterFileHasher.fullHash(path: path, expectedSize: 12), "size mismatch must fail")
        XCTAssertNil(ClutterFileHasher.fullHash(path: path, shouldContinue: { false }))
    }

    func testPartialHashSmallFileCoversContent() {
        let a = fixture.file("a.txt", contents: Data("hello world".utf8))
        let b = fixture.file("b.txt", contents: Data("hello world".utf8))
        let c = fixture.file("c.txt", contents: Data("hello earth".utf8))
        let ha = ClutterFileHasher.partialHash(path: a, size: 11)
        XCTAssertNotNil(ha)
        XCTAssertEqual(ha, ClutterFileHasher.partialHash(path: b, size: 11))
        XCTAssertNotEqual(ha, ClutterFileHasher.partialHash(path: c, size: 11))
        XCTAssertNil(ClutterFileHasher.partialHash(path: a, size: 5), "stale size must fail")
        XCTAssertTrue(ClutterFileHasher.partialCoversWholeFile(size: 128 * 1024))
        XCTAssertFalse(ClutterFileHasher.partialCoversWholeFile(size: 128 * 1024 + 1))
    }

    func testPartialHashIgnoresMiddleButFullDoesNot() {
        var first = ClutterFixture.noise(400_000, seed: 1)
        var second = first
        second[200_000] ^= 0xFF
        let a = fixture.file("x/a.bin", contents: first)
        let b = fixture.file("x/b.bin", contents: second)
        let size = Int64(first.count)
        XCTAssertEqual(ClutterFileHasher.partialHash(path: a, size: size), ClutterFileHasher.partialHash(path: b, size: size))
        XCTAssertNotEqual(ClutterFileHasher.fullHash(path: a), ClutterFileHasher.fullHash(path: b))
        first[0] ^= 0x01
        let c = fixture.file("x/c.bin", contents: first)
        XCTAssertNotEqual(ClutterFileHasher.partialHash(path: a, size: size), ClutterFileHasher.partialHash(path: c, size: size))
    }

    func testRefusesSymlinks() throws {
        let target = fixture.file("real.bin", bytes: 1000)
        let link = fixture.home + "/link.bin"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        XCTAssertNil(ClutterFileHasher.fullHash(path: link))
        XCTAssertNil(ClutterFileHasher.partialHash(path: link, size: 1000))
    }
}

final class ClutterDuplicateFinderTests: XCTestCase {
    var fixture: ClutterFixture!

    override func setUp() { fixture = ClutterFixture() }
    override func tearDown() { fixture.remove() }

    private func walk(_ settings: ClutterScanSettings = ClutterScanSettings(duplicateMinimumSize: 1)) -> [ClutterFile] {
        ClutterWalker(paths: fixture.paths, settings: settings).walk(locations: [fixture.home]).files
    }

    func testFindsIdenticalFilesAndKeepsOneOutsideDownloads() {
        let content = ClutterFixture.noise(300_000, seed: 3)
        fixture.file("Downloads/report.pdf", contents: content, age: 10 * ClutterFixture.day)
        fixture.file("Documents/report.pdf", contents: content, age: 5 * ClutterFixture.day)
        fixture.file("Desktop/report copy.pdf", contents: content, age: 20 * ClutterFixture.day)
        // Same size, different content: not a duplicate.
        fixture.file("Documents/other.pdf", contents: ClutterFixture.noise(300_000, seed: 4))
        let finder = ClutterDuplicateFinder(paths: fixture.paths)
        let groups = finder.findDuplicates(in: walk(), minimumSize: 1)
        XCTAssertEqual(groups.count, 1)
        let group = groups[0]
        XCTAssertEqual(group.files.count, 3)
        // Downloads loses to Documents/Desktop; "copy" loses to the clean name.
        XCTAssertEqual(group.keeperPath, fixture.home + "/Documents/report.pdf")
        XCTAssertEqual(group.files.first?.path, group.keeperPath)
        XCTAssertEqual(group.hash, ClutterSHA256.hex(content))
        XCTAssertEqual(group.copies.count, 2)
        let selected = ClutterSmartSelection(paths: fixture.paths).selection(for: groups)
        XCTAssertEqual(selected, [fixture.home + "/Downloads/report.pdf", fixture.home + "/Desktop/report copy.pdf"])
    }

    func testSkipsZeroByteAndCountsHardLinksOnce() throws {
        fixture.file("Documents/empty1.txt", bytes: 0)
        fixture.file("Documents/empty2.txt", bytes: 0)
        let original = fixture.file("Documents/data.bin", contents: ClutterFixture.noise(5000, seed: 9))
        try FileManager.default.linkItem(atPath: original, toPath: fixture.home + "/Documents/hardlink.bin")
        let groups = ClutterDuplicateFinder(paths: fixture.paths).findDuplicates(in: walk(), minimumSize: 1)
        XCTAssertTrue(groups.isEmpty, "zero-byte files and hard links of one file are not duplicates: \(groups)")
    }

    func testSmallFilesConfirmedByPartialHashOnly() {
        let content = Data("tiny but identical".utf8)
        fixture.file("Downloads/a.txt", contents: content)
        fixture.file("Downloads/b.txt", contents: content)
        let fullCalls = ClutterAtomicCounter()
        let finder = ClutterDuplicateFinder(paths: fixture.paths, fullHasher: { file, _ in
            fullCalls.add(1)
            return ClutterFileHasher.fullHash(path: file.path)
        })
        let groups = finder.findDuplicates(in: walk(), minimumSize: 1)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(fullCalls.current, 0)
    }

    func testMinimumSizeAppliesOutsideDownloadsOnly() {
        let content = ClutterFixture.noise(2_000, seed: 5)
        fixture.file("Documents/a.bin", contents: content)
        fixture.file("Documents/b.bin", contents: content)
        fixture.file("Downloads/c.bin", contents: content)
        fixture.file("Downloads/d.bin", contents: content)
        let settings = ClutterScanSettings(duplicateMinimumSize: 1)
        let files = walk(settings)
        let groups = ClutterDuplicateFinder(paths: fixture.paths).findDuplicates(in: files, minimumSize: 100_000)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.name)), ["c.bin", "d.bin"])
    }

    func testStopsWhenAsked() {
        let content = ClutterFixture.noise(300_000, seed: 11)
        fixture.file("Documents/a.bin", contents: content)
        fixture.file("Documents/b.bin", contents: content)
        let groups = ClutterDuplicateFinder(paths: fixture.paths)
            .findDuplicates(in: walk(), minimumSize: 1, shouldContinue: { false })
        XCTAssertTrue(groups.isEmpty)
    }

    func testParallelMapPreservesOrder() {
        let input = Array(0..<500)
        let output = ClutterParallel.map(input, concurrency: 8) { _, value in value * 2 }
        XCTAssertEqual(output.compactMap { $0 }, input.map { $0 * 2 })
    }
}

final class ClutterSmartSelectionTests: XCTestCase {
    let paths = ClutterPaths(home: "/Users/test")

    func testCopyMarkers() {
        for name in ["report copy.pdf", "report copy 2.pdf", "report (1).pdf", "Copy of report.pdf",
                     "report (Jane's conflicted copy 2024-01-02).pdf", "photo-1.jpg", "photo_2.jpg"] {
            XCTAssertTrue(ClutterSmartSelection.hasCopyMarker(name), name)
        }
        for name in ["report.pdf", "IMG_1234.JPG", "copyright.txt", "2024 budget.xlsx", "photo-2024.jpg",
                     "scan (draft).pdf"] {
            XCTAssertFalse(ClutterSmartSelection.hasCopyMarker(name), name)
        }
    }

    func testKeeperRankingOrder() {
        let selection = ClutterSmartSelection(paths: paths)
        let old = Date(timeIntervalSince1970: 1_000_000)
        let new = Date(timeIntervalSince1970: 2_000_000)
        // Outside Downloads beats older-in-Downloads.
        let a = clutterFile("/Users/test/Downloads/x.bin", modified: old)
        let b = clutterFile("/Users/test/Documents/x.bin", modified: new)
        XCTAssertEqual(selection.keeper(of: [a, b])?.path, b.path)
        // Trash counts as transient too.
        let t = clutterFile("/Users/test/.Trash/x.bin", modified: old)
        XCTAssertEqual(selection.keeper(of: [t, b])?.path, b.path)
        // Local beats cloud.
        let cloud = clutterFile("/Users/test/Library/Mobile Documents/com~apple~CloudDocs/x.bin", modified: old)
        XCTAssertEqual(selection.keeper(of: [cloud, b])?.path, b.path)
        // Oldest wins among equals.
        let c = clutterFile("/Users/test/Pictures/x.bin", modified: old)
        XCTAssertEqual(selection.keeper(of: [b, c])?.path, c.path)
        XCTAssertEqual(selection.keeperReason(c, among: [b, c]), "Kept the oldest copy")
        // Shortest path breaks ties.
        let d = clutterFile("/Users/test/Pictures/2019/trip/x.bin", modified: old)
        XCTAssertEqual(selection.keeper(of: [d, c])?.path, c.path)
        // Creation date beats modification date.
        let e = clutterFile("/Users/test/Movies/deep/er/x.bin", modified: new, created: old.addingTimeInterval(-10))
        XCTAssertEqual(selection.keeper(of: [c, e])?.path, e.path)
    }

    func testCloudCopiesAreNotPreselected() {
        let selection = ClutterSmartSelection(paths: paths)
        let local = clutterFile("/Users/test/Documents/x.bin")
        let cloud = clutterFile("/Users/test/Library/CloudStorage/Dropbox/x.bin")
        let dl = clutterFile("/Users/test/Downloads/x.bin")
        let group = selection.makeGroup(hash: "h", files: [cloud, dl, local])
        XCTAssertEqual(group.keeperPath, local.path)
        XCTAssertEqual(selection.selection(for: [group]), [dl.path])
    }
}
