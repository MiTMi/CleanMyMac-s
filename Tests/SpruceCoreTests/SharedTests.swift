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

    func testSystemStateInVarAndPreferencesIsProtected() {
        for p in ["/Library/Preferences/SystemConfiguration", "/Library/Preferences/SystemConfiguration/preferences.plist",
                  "/Library/Preferences/com.apple.loginwindow.plist", "/Library/Preferences/com.apple.alf.plist",
                  "/Library/Preferences/.GlobalPreferences.plist", "/Library/Managed Preferences/x.plist",
                  "/private/var/run/x", "/var/at/tabs", "/private/var/spool/cron", "/private/var/networkd/x",
                  "/private/var/folders/ab", "/private/var/folders/ab/xyz", "/var/folders/ab/xyz/T",
                  "/private/var/folders/ab/xyz/C", "/private/var/folders/ab/xyz/0/com.apple.LaunchServices",
                  "/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/-Caches-/x"] {
            XCTAssertFalse(guardian.check(p, method: .trash).isAllowed, "should deny \(p)")
        }
        // Third-party preferences, logs, temporary files and per-user temp/cache contents stay reachable.
        XCTAssertTrue(guardian.check("/Library/Preferences/com.vendor.app.plist", method: .trash).isAllowed)
        XCTAssertTrue(guardian.check("/private/var/log/vendor.log", method: .remove).isAllowed)
        XCTAssertTrue(guardian.check("/var/tmp/vendor-file", method: .remove).isAllowed)
        XCTAssertTrue(guardian.check("/private/var/folders/ab/xyz/T/com.vendor/x", method: .remove).isAllowed)
        XCTAssertTrue(guardian.check("/var/folders/ab/xyz/C/com.vendor", method: .remove).isAllowed)
    }

    func testIrreplaceableDataIsNeverDeletedPermanently() {
        let backup = "/Users/test/Library/Application Support/MobileSync/Backup/00008101-000A"
        let archive = "/Users/test/Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive"
        for p in [backup, archive] {
            XCTAssertFalse(guardian.check(p, method: .remove).isAllowed, "\(p) must not be deleted permanently")
            XCTAssertTrue(guardian.check(p, method: .trash).isAllowed, "\(p) may go to the Trash")
        }
    }

    func testPrivilegedAllowlist() {
        let g = PathGuard(home: "/Users/test", userTemporaryDirectory: "/var/folders/ab/xyz/T/", uid: 501)
        XCTAssertEqual(g.userVarFolder, "/private/var/folders/ab/xyz")
        // Places root may act.
        XCTAssertTrue(g.checkPrivileged("/Applications/Foo.app", options: .allowAppBundles).isAllowed)
        XCTAssertTrue(g.checkPrivileged("/Library/Application Support/Vendor").isAllowed)
        XCTAssertTrue(g.checkPrivileged("/Library/Caches/com.vendor", method: .remove).isAllowed)
        XCTAssertTrue(g.checkPrivileged("/Library/PrivilegedHelperTools/com.vendor.helper").isAllowed)
        XCTAssertTrue(g.checkPrivileged("/Library/LaunchDaemons/com.vendor.plist", options: .allowLaunchItems).isAllowed)
        XCTAssertTrue(g.checkPrivileged("/Users/test/.Trash/Old.app", method: .remove, options: .allowAppBundles).isAllowed)
        XCTAssertTrue(g.checkPrivileged("/private/var/folders/ab/xyz/T/thing", method: .remove).isAllowed)
        XCTAssertTrue(g.checkPrivileged("/Volumes/Ext/.Trashes/501/old", method: .remove).isAllowed)
        // Allowed for the user, refused as administrator.
        XCTAssertTrue(g.check("/Library/Fonts/Vendor.otf").isAllowed)
        XCTAssertFalse(g.checkPrivileged("/Library/Fonts/Vendor.otf").isAllowed)
        XCTAssertTrue(g.check("/private/var/folders/cd/other/T/x", method: .remove).isAllowed)
        XCTAssertFalse(g.checkPrivileged("/private/var/folders/cd/other/T/x", method: .remove).isAllowed)
        XCTAssertFalse(g.checkPrivileged("/Volumes/Ext/.Trashes/502/old", method: .remove).isAllowed)
        XCTAssertFalse(g.checkPrivileged("/Volumes/Ext/Projects/x").isAllowed)
        XCTAssertFalse(g.checkPrivileged("/Library/Extensions/Vendor.kext").isAllowed)
        // Never, whatever the method.
        XCTAssertFalse(g.checkPrivileged("/Library/Preferences/SystemConfiguration").isAllowed)
        XCTAssertFalse(g.checkPrivileged("/private/var/folders/ab/xyz/0/x").isAllowed)
    }

    func testVarFolderDetection() {
        XCTAssertEqual(PathGuard.varFolder(ofTemporaryDirectory: "/private/var/folders/AB/Xyz_12/T"), "/private/var/folders/ab/xyz_12")
        XCTAssertNil(PathGuard.varFolder(ofTemporaryDirectory: "/tmp/"))
        XCTAssertNil(PathGuard.varFolder(ofTemporaryDirectory: "/private/var/folders/ab/xyz/C"))
    }

    func testEmptyingTheTrashIgnoresNameMarkers() {
        // The user already threw these away; emptying the Trash must be able to finish.
        XCTAssertTrue(guardian.check("/Users/test/.Trash/1Password 7 Backup", method: .remove).isAllowed)
        XCTAssertTrue(guardian.check("/Users/test/.Trash/wallet.dat", method: .remove).isAllowed)
        // …but nowhere else.
        XCTAssertFalse(guardian.check("/Users/test/Documents/wallet.dat", method: .trash).isAllowed)
        XCTAssertFalse(guardian.check("/Users/test/Library/Caches/com.1password.x", method: .remove).isAllowed)
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

    func testRunOutcomeDecodesOlderFilesAndMergesTrash() throws {
        let json = #"{"module":"cleanup","date":"2026-01-01T00:00:00Z","freedBytes":10,"processedCount":1,"removedItemIDs":["a"],"failures":[],"summary":"x"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(RunOutcome.self, from: Data(json.utf8))
        XCTAssertEqual(old.freedBytes, 10)
        XCTAssertEqual(old.trashedBytes, 0)
        XCTAssertTrue(old.trashRunIDs.isEmpty)

        let run = UUID()
        let a = RunOutcome(module: .cleanup, freedBytes: 100, processedCount: 2, trashedBytes: 60, trashedCount: 1, trashRunIDs: [run])
        let b = RunOutcome(module: .cleanup, freedBytes: 5, processedCount: 1)
        let merged = RunOutcome.merged([a, b], module: .cleanup)
        XCTAssertEqual(merged.freedBytes, 105)
        XCTAssertEqual(merged.trashedBytes, 60)
        XCTAssertEqual(merged.trashedCount, 1)
        XCTAssertEqual(merged.trashRunIDs, [run])
        XCTAssertTrue(merged.didAnything)
        XCTAssertFalse(RunOutcome(module: .cleanup).didAnything)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let roundTrip = try decoder.decode(RunOutcome.self, from: encoder.encode(a))
        XCTAssertEqual(roundTrip.trashRunIDs, [run])
        XCTAssertEqual(roundTrip.trashedBytes, 60)
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

final class PersistenceTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("spruce-persist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testOperationLogTailAndRotation() {
        let log = OperationLog(url: dir.appendingPathComponent("operations.log"), rotationSize: 4_000)
        for i in 0..<200 {
            log.record(module: .cleanup, action: "remove", result: "ok", bytes: Int64(i), detail: "/tmp/item-\(i)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.rotatedURL.path), "the log rotates at its size cap")
        let size = (try? FileManager.default.attributesOfItem(atPath: log.url.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertLessThan(size, 4_200)
        let last = log.tail(3)
        XCTAssertEqual(last.count, 3)
        XCTAssertTrue(last[2].hasSuffix("/tmp/item-199"))
        XCTAssertTrue(last[1].hasSuffix("/tmp/item-198"))
        // More lines than the current file holds come from the rotated file, in order.
        let many = log.tail(80)
        XCTAssertEqual(many.count, 80)
        XCTAssertTrue(many.last!.hasSuffix("/tmp/item-199"))
        XCTAssertTrue(many.first!.hasSuffix("/tmp/item-120"))
        XCTAssertEqual(log.tail(0), [])
    }

    func testOperationLogTailReadsBackwardsAcrossChunks() throws {
        let url = dir.appendingPathComponent("big.log")
        var text = ""
        for i in 0..<5_000 { text += "line \(i) " + String(repeating: "x", count: 40) + "\n" }
        try text.write(to: url, atomically: true, encoding: .utf8)
        let lines = OperationLog.lastLines(of: url, count: 2_000)
        XCTAssertEqual(lines.count, 2_000)
        XCTAssertTrue(lines.first!.hasPrefix("line 3000 "))
        XCTAssertTrue(lines.last!.hasPrefix("line 4999 "))
    }

    func testOperationLogRecoversWhenTheFileIsDeleted() throws {
        let log = OperationLog(url: dir.appendingPathComponent("operations.log"))
        log.record(module: .cleanup, action: "remove", result: "ok", detail: "first")
        try FileManager.default.removeItem(at: log.url)
        log.record(module: .cleanup, action: "remove", result: "ok", detail: "second")
        XCTAssertEqual(log.tail(5).count, 1)
        XCTAssertTrue(log.tail(5)[0].hasSuffix("second"))
    }

    func testOperationLogFollowsAReplacedFile() throws {
        let log = OperationLog(url: dir.appendingPathComponent("operations.log"))
        log.record(module: .cleanup, action: "remove", result: "ok", detail: "first")
        // An editor saving the file atomically swaps in a new inode.
        try "edited\n".write(to: log.url, atomically: true, encoding: .utf8)
        log.record(module: .cleanup, action: "remove", result: "ok", detail: "second")
        let lines = log.tail(5)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first, "edited")
        XCTAssertTrue(lines.last!.hasSuffix("second"))
    }

    func testCompactJSONStoreRoundTrip() throws {
        let store = JSONFileStore<ActivityHistory>(url: dir.appendingPathComponent("history.json"), prettyPrinted: false)
        var history = ActivityHistory()
        history.append(ActivityEntry(date: Date(timeIntervalSince1970: 1_800_000_000), module: .cleanup, kind: .clean,
                                     bytes: 5, count: 1, summary: "x"))
        try store.save(history)
        let text = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertFalse(text.contains("\n"), "compact output has no line breaks")
        XCTAssertEqual(store.load(), history)
    }
}
