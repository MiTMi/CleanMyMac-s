import XCTest
@testable import SpruceCore

final class ToolboxCatalogTests: XCTestCase {
    /// Every tool id listed in docs/ARCHITECTURE.md.
    let architectureIDs = [
        "cleanup.systemJunk", "cleanup.mailAttachments", "cleanup.trash",
        "protection.malware", "protection.privacy", "protection.permissions",
        "performance.maintenance", "performance.loginItems", "performance.backgroundItems", "performance.consumers",
        "applications.uninstaller", "applications.updater", "applications.leftovers", "applications.installers",
        "applications.extensions",
        "clutter.largeOld", "clutter.duplicates", "clutter.similarImages", "clutter.downloads",
        "spaceMap", "cloudStorage",
        "toolbox.shredder", "toolbox.screenCleaning", "toolbox.emptyTrash", "toolbox.freeRAM", "toolbox.flushDNS",
    ]

    func testCatalogCoversEveryToolOnce() {
        let ids = ToolboxCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(architectureIDs))
        for tool in ToolboxCatalog.all {
            let prefix = tool.id.split(separator: ".").first.map(String.init) ?? tool.id
            XCTAssertEqual(ModuleID(rawValue: prefix), tool.module, tool.id)
            XCTAssertFalse(tool.caption.isEmpty)
            XCTAssertLessThanOrEqual(tool.caption.count, 60, tool.id)
        }
        XCTAssertTrue(ToolboxCatalog.defaultFavorites.allSatisfy { ToolboxCatalog.tool(id: $0) != nil })
    }

    func testGroupingKeepsOrder() {
        let groups = ToolboxCatalog.grouped()
        XCTAssertEqual(groups.map(\.group), ToolboxGroup.allCases)
        XCTAssertEqual(groups.reduce(0) { $0 + $1.tools.count }, ToolboxCatalog.all.count)
        XCTAssertEqual(groups.first { $0.group == .utilities }?.tools.map(\.id),
                       ["toolbox.emptyTrash", "toolbox.shredder", "toolbox.screenCleaning"])
    }

    func testSearchRanking() {
        XCTAssertEqual(ToolboxCatalog.search("").count, ToolboxCatalog.all.count)
        XCTAssertEqual(ToolboxCatalog.search("ram").first?.id, "toolbox.freeRAM")
        XCTAssertEqual(ToolboxCatalog.search("Uninstaller").first?.id, "applications.uninstaller")
        XCTAssertEqual(ToolboxCatalog.search("remove app").first?.id, "applications.uninstaller")
        XCTAssertEqual(ToolboxCatalog.search("DUPL").first?.id, "clutter.duplicates")
        XCTAssertEqual(ToolboxCatalog.search("dúplicates").first?.id, "clutter.duplicates")
        XCTAssertEqual(ToolboxCatalog.search("disk usage").first?.id, "spaceMap")
        XCTAssertEqual(ToolboxCatalog.search("smudge").first?.id, "toolbox.screenCleaning")
        XCTAssertEqual(ToolboxCatalog.search("dns").first?.id, "toolbox.flushDNS")
        XCTAssertTrue(ToolboxCatalog.search("zzqx").isEmpty)
        // Every word must match.
        XCTAssertTrue(ToolboxCatalog.search("trash zzqx").isEmpty)
        XCTAssertTrue(ToolboxCatalog.search("empty trash").map(\.id).contains("toolbox.emptyTrash"))
    }

    func testFavoritesWinTies() {
        let plain = ToolboxCatalog.search("trash").map(\.id)
        XCTAssertTrue(plain.contains("cleanup.trash"))
        XCTAssertTrue(plain.contains("toolbox.emptyTrash"))
        let favoured = ToolboxCatalog.search("trash", favorites: ["toolbox.emptyTrash"]).map(\.id)
        let a = favoured.firstIndex(of: "toolbox.emptyTrash")!
        let b = favoured.firstIndex(of: "cleanup.trash")!
        // "Trash Bins" is a title-prefix match and "Empty Trash" a word match, so the score decides.
        XCTAssertLessThan(b, a)
        // "memory" is an exact keyword of both Heavy Consumers and Free Up RAM.
        XCTAssertEqual(ToolboxCatalog.search("memory").first?.id, "performance.consumers")
        let tie = ToolboxCatalog.search("memory", favorites: ["toolbox.freeRAM"]).map(\.id)
        XCTAssertEqual(tie.first, "toolbox.freeRAM")
    }

    func testFavoritesResolveAndToggle() {
        XCTAssertEqual(ToolboxFavorites.resolve(nil), ToolboxCatalog.defaultFavorites)
        XCTAssertEqual(ToolboxFavorites.resolve([]), [])
        XCTAssertEqual(ToolboxFavorites.resolve(["spaceMap", "bogus", "spaceMap", "toolbox.shredder"]),
                       ["spaceMap", "toolbox.shredder"])
        var favs = ToolboxFavorites.toggled("toolbox.shredder", in: ["spaceMap"])
        XCTAssertEqual(favs, ["spaceMap", "toolbox.shredder"])
        favs = ToolboxFavorites.toggled("spaceMap", in: favs)
        XCTAssertEqual(favs, ["toolbox.shredder"])
        XCTAssertEqual(ToolboxFavorites.toggled("bogus", in: favs), favs)
        XCTAssertEqual(ToolboxFavorites.moved("b", by: -1, in: ["a", "b", "c"]), ["b", "a", "c"])
        XCTAssertEqual(ToolboxFavorites.moved("a", by: -1, in: ["a", "b"]), ["a", "b"])
    }
}

final class ToolboxSupportTests: XCTestCase {
    func testHoldTracker() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var hold = ToolboxHoldTracker(duration: 2)
        XCTAssertEqual(hold.progress(at: t0), 0)
        hold.press(at: t0)
        hold.press(at: t0.addingTimeInterval(1))      // auto-repeat keeps the start
        XCTAssertEqual(hold.progress(at: t0.addingTimeInterval(1)), 0.5, accuracy: 0.001)
        XCTAssertFalse(hold.isComplete(at: t0.addingTimeInterval(1.9)))
        XCTAssertTrue(hold.isComplete(at: t0.addingTimeInterval(2)))
        hold.release()
        XCTAssertFalse(hold.isPressed)
        XCTAssertEqual(hold.progress(at: t0.addingTimeInterval(5)), 0)
    }

    func testCleaningClock() {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = ToolboxCleaningClock(startedAt: t0, limit: 120, instructionsVisibleFor: 5)
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(30)), 90)
        XCTAssertFalse(clock.isExpired(at: t0.addingTimeInterval(119)))
        XCTAssertTrue(clock.isExpired(at: t0.addingTimeInterval(120)))
        XCTAssertEqual(clock.instructionOpacity(at: t0.addingTimeInterval(2)), 1)
        XCTAssertEqual(clock.instructionOpacity(at: t0.addingTimeInterval(30)), 0.15)
        XCTAssertEqual(ToolboxCleaningClock.clockText(90), "1:30")
        XCTAssertEqual(ToolboxCleaningClock.clockText(5.2), "0:06")
    }
}

final class ToolboxShredPlanTests: XCTestCase {
    var root: URL!
    var guardian: PathGuard!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("spruce-shred-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guardian = PathGuard(home: root.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    func testSingleFile() throws {
        let file = try write("work/secret.txt", bytes: 4_000)
        let plan = ToolboxShredPlan.make(root: file.path, guardian: guardian)
        XCTAssertNil(plan.problem)
        XCTAssertFalse(plan.isDirectory)
        XCTAssertEqual(plan.files.count, 1)
        XCTAssertEqual(plan.logicalBytes, 4_000)
        XCTAssertEqual(plan.itemCount, 1)
        XCTAssertEqual(plan.name, "secret.txt")
    }

    func testFolderCollectsRegularFiles() throws {
        _ = try write("work/folder/a.txt", bytes: 10)
        _ = try write("work/folder/sub/b.txt", bytes: 20)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("work/folder/link").path,
                                                   withDestinationPath: "/etc/hosts")
        let plan = ToolboxShredPlan.make(root: root.appendingPathComponent("work/folder").path, guardian: guardian)
        XCTAssertNil(plan.problem)
        XCTAssertTrue(plan.isDirectory)
        XCTAssertEqual(plan.files.map { ($0.path as NSString).lastPathComponent }.sorted(), ["a.txt", "b.txt"])
        XCTAssertEqual(plan.logicalBytes, 30)
        XCTAssertEqual(plan.itemCount, 4)   // a.txt, sub, sub/b.txt, link
        XCTAssertEqual(ToolboxShredPlan.summary([plan]), "1 item · \(ByteFormat.string(plan.allocatedBytes)) · 2 files")
    }

    func testRefusesSymlinksHardLinksAndMissingItems() throws {
        let file = try write("work/a.txt", bytes: 10)
        let link = root.appendingPathComponent("work/alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertNotNil(ToolboxShredPlan.make(root: link.path, guardian: guardian).problem)

        let hard = root.appendingPathComponent("work/hard.txt")
        try FileManager.default.linkItem(at: file, to: hard)
        let plan = ToolboxShredPlan.make(root: hard.path, guardian: guardian)
        XCTAssertNotNil(plan.problem)
        XCTAssertTrue(plan.problem?.contains("hard link") ?? false)

        XCTAssertNotNil(ToolboxShredPlan.make(root: root.appendingPathComponent("nope").path, guardian: guardian).problem)
        XCTAssertEqual(ToolboxShredPlan.summary([plan]), "Nothing to shred")
    }

    func testRefusesProtectedLocationsAndAppBundles() throws {
        // The home folder itself and its Documents folder are protected roots.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        XCTAssertNotNil(ToolboxShredPlan.make(root: root.appendingPathComponent("Documents").path, guardian: guardian).problem)

        // A folder that contains an application bundle is refused as a whole.
        _ = try write("work/stuff/Tool.app/Contents/Info.plist", bytes: 5)
        let plan = ToolboxShredPlan.make(root: root.appendingPathComponent("work/stuff").path, guardian: guardian)
        XCTAssertNotNil(plan.problem)
        XCTAssertTrue(plan.files.isEmpty)
    }
}
