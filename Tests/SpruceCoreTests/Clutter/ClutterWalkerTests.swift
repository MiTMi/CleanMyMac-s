import Foundation
import XCTest
@testable import SpruceCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class ClutterWalkerTests: XCTestCase {
    var fixture: ClutterFixture!

    override func setUp() { fixture = ClutterFixture() }
    override func tearDown() { fixture.remove() }

    private var smallSettings: ClutterScanSettings {
        ClutterScanSettings(largeFileThreshold: 1_000, oldFileDays: 30, oldMinimumSize: 1_000, duplicateMinimumSize: 1_000,
                            similarImageMinimumSize: 1_000)
    }

    func testExclusions() {
        fixture.file("Documents/keep.bin", bytes: 5_000)
        fixture.file("Library/Caches/huge.bin", bytes: 5_000)
        fixture.file(".hidden/secret.bin", bytes: 5_000)
        fixture.file("Documents/.dotfile.bin", bytes: 5_000)
        fixture.file("Projects/app/node_modules/dep/blob.bin", bytes: 5_000)
        fixture.file("Pictures/Photos Library.photoslibrary/originals/IMG_1.heic", bytes: 5_000)
        fixture.file("Music/Music/Media.localized/song.m4a", bytes: 5_000)
        fixture.file("Applications/Tool.app/Contents/MacOS/tool", bytes: 5_000)
        fixture.file("Documents/tiny.txt", bytes: 10)
        let result = ClutterWalker(paths: fixture.paths, settings: smallSettings).walk(locations: [fixture.home])
        XCTAssertEqual(result.files.map(\.name), ["keep.bin"])
        XCTAssertFalse(result.stopped)
        XCTAssertGreaterThan(result.examined, 0)
    }

    func testPackagesAreSingleItems() {
        fixture.file("Documents/Backup.sparsebundle/bands/0", bytes: 3_000)
        fixture.file("Documents/Backup.sparsebundle/bands/1", bytes: 3_000)
        fixture.file("Documents/Backup.sparsebundle/Info.plist", bytes: 100)
        let result = ClutterWalker(paths: fixture.paths, settings: smallSettings).walk(locations: [fixture.home])
        XCTAssertEqual(result.files.count, 1)
        let package = result.files[0]
        XCTAssertEqual(package.name, "Backup.sparsebundle")
        XCTAssertTrue(package.isPackage)
        XCTAssertEqual(package.kind, .installers)
        XCTAssertGreaterThanOrEqual(package.size, 6_000)
    }

    func testLibraryAllowedWhenChosenExplicitly() {
        fixture.file("Library/Stuff/blob.bin", bytes: 5_000)
        let walker = ClutterWalker(paths: fixture.paths, settings: smallSettings)
        XCTAssertTrue(walker.walk(locations: [fixture.home]).files.isEmpty)
        XCTAssertEqual(walker.walk(locations: [fixture.home + "/Library/Stuff"]).files.map(\.name), ["blob.bin"])
    }

    func testPlaceholdersAreSkippedNotRead() throws {
        // A sparse file with a length but no allocated blocks looks like a dataless placeholder.
        let path = fixture.home + "/Documents/cloud.bin"
        try? FileManager.default.createDirectory(atPath: fixture.home + "/Documents", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        let fd = open(path, O_WRONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        XCTAssertEqual(ftruncate(fd, 5_000_000), 0)
        close(fd)
        guard let entry = FileWalker.entry(at: path), entry.allocatedSize == 0 else {
            throw XCTSkip("File system does not create sparse files")
        }
        let result = ClutterWalker(paths: fixture.paths, settings: smallSettings).walk(locations: [fixture.home])
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.skippedPlaceholders, 1)
    }

    func testNestedLocationsWalkedOnce() {
        fixture.file("Documents/a.bin", bytes: 5_000)
        let result = ClutterWalker(paths: fixture.paths, settings: smallSettings)
            .walk(locations: [fixture.home + "/Documents", fixture.home, fixture.home + "/Documents/"])
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(ClutterPaths.collapsed(["~/Documents", "~", "/Volumes/X", "~"]),
                       [ClutterPaths.standardized(NSHomeDirectory()), "/Volumes/X"])
        XCTAssertEqual(ClutterPaths.walkRoots(for: "/"), ["/Users"])
    }

    func testStopEndsWalk() {
        for i in 0..<900 { fixture.file("Documents/f\(i).bin", bytes: 1_500) }
        let result = ClutterWalker(paths: fixture.paths, settings: smallSettings)
            .walk(locations: [fixture.home], shouldContinue: { false })
        XCTAssertTrue(result.stopped)
        XCTAssertLessThan(result.files.count, 900)
    }

    func testListDownloadsTopLevel() {
        fixture.file("Downloads/Installer.dmg", bytes: 2_000)
        fixture.file("Downloads/Unpacked/inner/file.txt", bytes: 3_000)
        fixture.file("Downloads/.DS_Store", bytes: 10)
        fixture.file("Downloads/Partial.mov.download/Info.plist", bytes: 100)
        let items = ClutterWalker(paths: fixture.paths, settings: smallSettings).listDownloads()
        XCTAssertEqual(Set(items.map(\.name)), ["Installer.dmg", "Unpacked", "Partial.mov.download"])
        let folder = items.first { $0.name == "Unpacked" }
        XCTAssertEqual(folder?.isFolder, true)
        XCTAssertGreaterThanOrEqual(folder?.size ?? 0, 3_000)
        XCTAssertEqual(items.first { $0.name == "Partial.mov.download" }?.isPackage, true)
    }

    func testPathRules() {
        let paths = ClutterPaths(home: "/Users/test")
        XCTAssertTrue(paths.isInDownloads("/Users/test/Downloads/a"))
        XCTAssertTrue(paths.isInDownloads("/users/TEST/downloads/a"))
        XCTAssertFalse(paths.isInDownloads("/Users/test/Downloads"))
        XCTAssertTrue(paths.isTransient("/Users/test/.Trash/a"))
        XCTAssertTrue(paths.isTransient("/Volumes/Ext/.Trashes/501/a"))
        XCTAssertTrue(paths.isTransient("/private/var/folders/xy/a"))
        XCTAssertFalse(paths.isTransient("/Users/test/Documents/a"))
        XCTAssertTrue(paths.isCloud("/Users/test/Library/CloudStorage/GoogleDrive-x/a"))
        XCTAssertFalse(paths.isCloud("/Users/test/Documents/a"))
        XCTAssertTrue(paths.isExcluded("/Volumes/Ext/System", name: "System", root: "/Volumes/Ext"))
        XCTAssertFalse(paths.isExcluded("/Volumes/Ext/Photos", name: "Photos", root: "/Volumes/Ext"))
        XCTAssertTrue(paths.isExcluded("/Users/other", name: "other", root: "/Users"))
        XCTAssertFalse(paths.isExcluded("/Users/test", name: "test", root: "/Users"))
        XCTAssertFalse(paths.isExcluded("/Users/Shared", name: "Shared", root: "/Users"))
    }
}

final class ClutterLargeOldTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let settings = ClutterScanSettings(largeFileThreshold: 50_000_000, oldFileDays: 180, oldMinimumSize: 10_000_000)

    private func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    func testReasons() {
        let big = clutterFile("/h/big.mov", size: 60_000_000, modified: days(1), accessed: days(1))
        let old = clutterFile("/h/old.zip", size: 20_000_000, modified: days(400), accessed: days(400))
        let both = clutterFile("/h/both.dmg", size: 80_000_000, modified: days(400), accessed: days(400))
        let small = clutterFile("/h/small.txt", size: 1_000, modified: days(900), accessed: days(900))
        let recentlyOpened = clutterFile("/h/doc.pdf", size: 20_000_000, modified: days(400), lastOpened: days(3),
                                         accessed: days(400))
        let edited = clutterFile("/h/vm.vmdk", size: 20_000_000, modified: days(2), lastOpened: days(500), accessed: days(500))
        XCTAssertEqual(ClutterLargeOldFilter.reason(for: big, settings: settings, now: now), .large)
        XCTAssertEqual(ClutterLargeOldFilter.reason(for: old, settings: settings, now: now), .old)
        XCTAssertEqual(ClutterLargeOldFilter.reason(for: both, settings: settings, now: now), .largeAndOld)
        XCTAssertNil(ClutterLargeOldFilter.reason(for: small, settings: settings, now: now))
        XCTAssertNil(ClutterLargeOldFilter.reason(for: recentlyOpened, settings: settings, now: now))
        XCTAssertNil(ClutterLargeOldFilter.reason(for: edited, settings: settings, now: now))
        let items = ClutterLargeOldFilter.items(from: [old, small, big, both], settings: settings, now: now)
        XCTAssertEqual(items.map(\.file.name), ["both.dmg", "big.mov", "old.zip"])
    }

    func testLastUsedPrefersSpotlightThenAccessTime() {
        let a = clutterFile("/h/a", modified: days(300), lastOpened: days(10), accessed: days(200))
        XCTAssertEqual(a.lastUsed, days(10))
        let b = clutterFile("/h/b", modified: days(300), accessed: days(200))
        XCTAssertEqual(b.lastUsed, days(200))
        XCTAssertEqual(b.effectiveLastUse, days(200))
    }

    func testKindClassification() {
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.MOV", isDirectory: false, isPackage: false), .movies)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.flac", isDirectory: false, isPackage: false), .music)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.heic", isDirectory: false, isPackage: false), .pictures)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.dmg", isDirectory: false, isPackage: false), .installers)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.tar.gz", isDirectory: false, isPackage: false), .archives)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.vmdk", isDirectory: false, isPackage: false), .virtualMachines)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.pdf", isDirectory: false, isPackage: false), .documents)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.key", isDirectory: true, isPackage: true), .documents)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b", isDirectory: true, isPackage: false), .folders)
        XCTAssertEqual(ClutterKindClassifier.kind(forPath: "/a/b.xyz", isDirectory: false, isPackage: false), .other)
    }

    func testBuckets() {
        XCTAssertEqual(ClutterSizeBucket.bucket(for: 6_000_000_000), .huge)
        XCTAssertEqual(ClutterSizeBucket.bucket(for: 2_000_000_000), .large)
        XCTAssertEqual(ClutterSizeBucket.bucket(for: 200_000_000), .medium)
        XCTAssertEqual(ClutterSizeBucket.bucket(for: 60_000_000), .small)
        XCTAssertEqual(ClutterAgeBucket.bucket(for: days(2), now: now), .thisWeek)
        XCTAssertEqual(ClutterAgeBucket.bucket(for: days(20), now: now), .thisMonth)
        XCTAssertEqual(ClutterAgeBucket.bucket(for: days(90), now: now), .months)
        XCTAssertEqual(ClutterAgeBucket.bucket(for: days(250), now: now), .halfYear)
        XCTAssertEqual(ClutterAgeBucket.bucket(for: days(800), now: now), .overAYear)
    }

    func testQueryFiltersAndSorts() {
        let items = [
            ClutterLargeOldItem(file: clutterFile("/h/Movies/b.mov", size: 3_000_000_000, modified: days(5), accessed: days(5)), reason: .large),
            ClutterLargeOldItem(file: clutterFile("/h/Docs/a.pdf", size: 20_000_000, modified: days(400), accessed: days(400)), reason: .old),
            ClutterLargeOldItem(file: clutterFile("/h/Movies/c.mkv", size: 70_000_000, modified: days(300), accessed: days(300)), reason: .largeAndOld),
        ]
        var query = ClutterLargeOldQuery()
        XCTAssertEqual(query.apply(items, selected: [], now: now).map(\.file.name), ["b.mov", "c.mkv", "a.pdf"])
        query.kind = .movies
        XCTAssertEqual(query.apply(items, selected: [], now: now).map(\.file.name), ["b.mov", "c.mkv"])
        query.scope = .old
        XCTAssertEqual(query.apply(items, selected: [], now: now).map(\.file.name), ["c.mkv"])
        query = ClutterLargeOldQuery()
        query.sort = .name
        query.ascending = true
        XCTAssertEqual(query.apply(items, selected: [], now: now).map(\.file.name), ["a.pdf", "b.mov", "c.mkv"])
        query.sort = .lastOpened
        XCTAssertEqual(query.apply(items, selected: [], now: now).map(\.file.name), ["a.pdf", "c.mkv", "b.mov"])
        query = ClutterLargeOldQuery()
        query.scope = .selected
        XCTAssertEqual(query.apply(items, selected: ["/h/Docs/a.pdf"], now: now).map(\.file.name), ["a.pdf"])
        query = ClutterLargeOldQuery()
        query.search = "movies/c"
        XCTAssertEqual(query.apply(items, selected: [], now: now).map(\.file.name), ["c.mkv"])
        query = ClutterLargeOldQuery()
        query.sizeBucket = .large
        XCTAssertEqual(query.apply(items, selected: [], now: now).map(\.file.name), ["b.mov"])
        query = ClutterLargeOldQuery()
        query.ageBucket = .overAYear
        XCTAssertEqual(query.apply(items, selected: [], now: now).map(\.file.name), ["a.pdf"])
    }

    func testSettingsFromSpruceSettings() {
        var spruce = SpruceSettings()
        spruce.largeFileThreshold = 200_000_000
        spruce.oldFileDays = 365
        let s = ClutterScanSettings(spruce)
        XCTAssertEqual(s.largeFileThreshold, 200_000_000)
        XCTAssertEqual(s.oldFileDays, 365)
        XCTAssertEqual(s.walkMinimumSize, 50_000)
        let tiny = ClutterScanSettings(largeFileThreshold: 5_000)
        XCTAssertEqual(tiny.oldMinimumSize, 5_000, "old minimum never exceeds the large threshold")
    }
}
