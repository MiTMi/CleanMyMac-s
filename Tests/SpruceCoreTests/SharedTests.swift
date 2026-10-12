import XCTest
@testable import SpruceCore

final class PathGuardTests: XCTestCase {
    let guardian = PathGuard(home: "/Users/test")

    func testRejectsMalformedPaths() {
        XCTAssertFalse(guardian.check("").isAllowed)
        XCTAssertFalse(guardian.check("relative/path").isAllowed)
        XCTAssertFalse(guardian.check("/Users/test/Library/Caches/../Keychains").isAllowed)
        XCTAssertFalse(guardian.check("/Users/test/Library/Caches/a\nb").isAllowed)
    }

    func testProtectsSystemAndRoots() {
        for p in ["/", "/System", "/System/Library/Caches/x", "/usr/bin/ls", "/Library", "/Applications",
                  "/Users", "/Users/test", "/Users/test/Documents", "/Users/test/Library",
                  "/Users/test/Library/Caches", "/Volumes", "/Volumes/External", "/private/var/db/x",
                  "/var/db/x", "/etc/hosts", "/Users/test/Library/Keychains/login.keychain-db",
                  "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/a.txt",
                  "/Users/other/Library/Caches/x", "/SYSTEM/Library", "/Library/Keychains/System.keychain"] {
            XCTAssertFalse(guardian.check(p, method: .trash).isAllowed, "should deny \(p)")
        }
    }

    func testAllowsJunkInsideZones() {
        XCTAssertTrue(guardian.check("/Users/test/Library/Caches/com.example.app", method: .remove).isAllowed)
        XCTAssertTrue(guardian.check("/Users/test/Library/Logs/Example/log.txt", method: .remove).isAllowed)
        XCTAssertTrue(guardian.check("/Users/test/Library/Developer/Xcode/DerivedData/Foo-abc", method: .remove).isAllowed)
        XCTAssertTrue(guardian.check("/Library/Caches/com.example", method: .remove).isAllowed)
    }

    func testPermanentRemovalOutsideZonesIsDenied() {
        let p = "/Users/test/Documents/report.pdf"
        XCTAssertFalse(guardian.check(p, method: .remove).isAllowed)
        XCTAssertTrue(guardian.check(p, method: .trash).isAllowed)
    }

    func testAppBundles() {
        XCTAssertFalse(guardian.check("/Applications/Foo.app").isAllowed)
        XCTAssertTrue(guardian.check("/Applications/Foo.app", options: .allowAppBundles).isAllowed)
        XCTAssertFalse(guardian.check("/Applications/Foo.app/Contents/Resources/fr.lproj", options: .allowAppBundles).isAllowed)
        XCTAssertFalse(guardian.check("/Applications/Safari.app", options: .allowAppBundles).isAllowed)
        XCTAssertFalse(guardian.check("/Users/test/Downloads/Thing.app/Contents/MacOS/x").isAllowed)
        XCTAssertTrue(guardian.check("/Users/test/Library/Caches/com.vendor.app", method: .remove).isAllowed)
    }

    func testLaunchItems() {
        let third = "/Users/test/Library/LaunchAgents/com.example.agent.plist"
        XCTAssertFalse(guardian.check(third).isAllowed)
        XCTAssertTrue(guardian.check(third, options: .allowLaunchItems).isAllowed)
        XCTAssertFalse(guardian.check("/Library/LaunchDaemons/com.apple.foo.plist", options: .allowLaunchItems).isAllowed)
    }

    func testCredentialStoresAreProtected() {
        XCTAssertFalse(guardian.check("/Users/test/Library/Application Support/1Password/data.sqlite").isAllowed)
        XCTAssertFalse(guardian.check("/Users/test/Library/Caches/com.bitwarden.desktop", method: .remove).isAllowed)
    }

    func testCaseInsensitiveAliases() {
        XCTAssertFalse(guardian.check("/system/library/foo").isAllowed)
        XCTAssertFalse(guardian.check("/var/root/x").isAllowed)
        XCTAssertEqual(PathGuard.key("/var/log/x"), "/private/var/log/x")
    }
}

final class FormatTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(ByteFormat.string(0), "Zero KB")
        XCTAssertEqual(ByteFormat.string(999), "999 bytes")
        XCTAssertEqual(ByteFormat.string(1_000), "1 KB")
        XCTAssertEqual(ByteFormat.string(1_234_567), "1.2 MB")
        XCTAssertEqual(ByteFormat.string(34_560_000_000), "34.6 GB")
        XCTAssertEqual(ByteFormat.string(120_400_000_000), "120 GB")
        XCTAssertEqual(ByteFormat.parts(4_200_000_000).value, "4.2")
        XCTAssertEqual(ByteFormat.parts(4_200_000_000).unit, "GB")
    }

    func testCounts() {
        XCTAssertEqual(CountFormat.items(1), "1 item")
        XCTAssertEqual(CountFormat.items(1204, singular: "file"), "1,204 files")
        XCTAssertEqual(CountFormat.grouped(1_000_000), "1,000,000")
    }
}

final class ModelTests: XCTestCase {
    func testSelectionDefaults() {
        XCTAssertTrue(ScanItem(id: "a", title: "a", safety: .safe).isSelected)
        XCTAssertFalse(ScanItem(id: "b", title: "b", safety: .review).isSelected)
        XCTAssertTrue(ScanItem(id: "c", title: "c", safety: .review, isSelected: true).isSelected)
        XCTAssertFalse(ScanItem(id: "d", title: "d", safety: .risky, isSelected: true).isSelected)
    }

    func testGroupSelectionAndRemoval() {
        var g = ScanGroup(id: "g", title: "G", items: [
            ScanItem(id: "1", title: "1", size: 10, safety: .safe),
            ScanItem(id: "2", title: "2", size: 20, safety: .review),
        ], children: [ScanGroup(id: "c", title: "C", items: [ScanItem(id: "3", title: "3", size: 5, safety: .risky)])])
        XCTAssertEqual(g.totalSize, 35)
        XCTAssertEqual(g.selectedSize, 10)
        XCTAssertEqual(g.selectionState, .some)
        g.setAllSelected(true)
        XCTAssertEqual(g.selectedSize, 30, "risky items are never bulk-selected")
        g.setSelected(true, itemID: "3")
        XCTAssertEqual(g.selectedSize, 35)
        g.removeItems(withIDs: ["3"])
        XCTAssertTrue(g.children.isEmpty)
    }

    func testSettingsIgnoreList() {
        var s = SpruceSettings()
        s.ignoredPaths = ["/Users/test/Library/Caches/com.keep.me"]
        XCTAssertTrue(s.isIgnored(path: "/Users/test/Library/Caches/com.keep.me/x"))
        XCTAssertFalse(s.isIgnored(path: "/Users/test/Library/Caches/com.other"))
        let groups = [ScanGroup(id: "g", title: "G", items: [
            .file(URL(fileURLWithPath: "/Users/test/Library/Caches/com.keep.me"), size: 1, safety: .safe),
            .file(URL(fileURLWithPath: "/Users/test/Library/Caches/com.other"), size: 1, safety: .safe),
        ])]
        XCTAssertEqual(s.filteringIgnored(groups).allItems.count, 1)
    }

    func testSettingsDecodeLeniently() throws {
        let json = #"{"playSounds": false, "unknownKey": 3}"#
        let s = try JSONDecoder().decode(SpruceSettings.self, from: Data(json.utf8))
        XCTAssertFalse(s.playSounds)
        XCTAssertEqual(s.oldFileDays, 180)
    }
}

final class FileWalkerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("spruce-walker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10_000).write(to: root.appendingPathComponent("a/one.bin"))
        try Data(repeating: 2, count: 20_000).write(to: root.appendingPathComponent("a/b/two.bin"))
        try Data(repeating: 3, count: 5_000).write(to: root.appendingPathComponent(".hidden"))
        try FileManager.default.linkItem(at: root.appendingPathComponent("a/one.bin"), to: root.appendingPathComponent("hardlink.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/usr"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWalkDoesNotFollowSymlinksAndCountsHardLinksOnce() {
        var files: [String] = []
        FileWalker.walk(root.path) { entry in
            if !entry.isDirectory { files.append(entry.name) }
            return .continue
        }
        XCTAssertTrue(files.contains("link"))
        XCTAssertFalse(files.contains("ls"), "must not descend into symlinked /usr")
        let usage = DiskUsage.measure(root.path)
        XCTAssertEqual(usage.fileCount, 4, "one.bin, two.bin, .hidden, link — hard link counted once")
        XCTAssertGreaterThanOrEqual(usage.bytes, 35_000)
    }

    func testHiddenAndSkip() {
        var names: [String] = []
        FileWalker.walk(root.path, options: .init(includeHidden: false)) { entry in
            names.append(entry.name)
            return entry.name == "b" ? .skipChildren : .continue
        }
        XCTAssertFalse(names.contains(".hidden"))
        XCTAssertTrue(names.contains("b"))
        XCTAssertFalse(names.contains("two.bin"))
    }

    func testGlob() {
        let matches = PathGlob.expand(root.path + "/a/*.bin")
        XCTAssertEqual(matches.map { ($0 as NSString).lastPathComponent }, ["one.bin"])
        XCTAssertEqual(PathGlob.expand(root.path + "/*/b").count, 1)
        XCTAssertTrue(PathGlob.expand(root.path + "/nope/*").isEmpty)
    }
}
