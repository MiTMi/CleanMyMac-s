import Foundation
import XCTest
@testable import SpruceCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class CleanupScannerTests: XCTestCase {
    private var fx: CleanupFixture!
    private let day = CleanupFixture.day

    override func setUp() {
        super.setUp()
        fx = CleanupFixture()
    }

    override func tearDown() {
        fx.remove()
        super.tearDown()
    }

    // MARK: User caches

    func testUserCacheRowCountsOnlyChildrenOlderThanAnHour() throws {
        let old = fx.file("Library/Caches/com.example.app/old.bin", bytes: 60_000, age: 2 * day)
        fx.file("Library/Caches/com.example.app/fresh.bin", bytes: 60_000, age: 60)
        let (scanner, report) = fx.scan(fx.context(), sections: [.systemJunk])

        let item = try XCTUnwrap(report.item(endingWith: "Library/Caches/com.example.app"))
        XCTAssertTrue(report.items(in: CleanupCategory.userCaches.rawValue).contains(item))
        let oldSize = try XCTUnwrap(FileWalker.entry(at: old)).allocatedSize
        XCTAssertEqual(item.size, oldSize, "only the old child is counted")
        XCTAssertEqual(item.metadata[CleanupMetadataKey.ruleID], "caches.user")
        XCTAssertEqual(item.metadata[CleanupMetadataKey.bundleID], "com.example.app")
        XCTAssertEqual(item.metadata[CleanupMetadataKey.mode], "contents")
        let folder = try XCTUnwrap(FileWalker.entry(at: fx.home + "/Library/Caches/com.example.app"))
        XCTAssertEqual(item.metadata[CleanupMetadataKey.inode], String(folder.inode))
        XCTAssertTrue(item.isSelected)
        XCTAssertEqual(item.deletion, .remove)

        let expansion = scanner.expand(item)
        XCTAssertNil(expansion.failure)
        XCTAssertEqual(expansion.targets.map { $0.url?.lastPathComponent }, ["old.bin"])
        XCTAssertEqual(expansion.targets.first?.deletion, .remove)
        XCTAssertEqual(expansion.targets.first?.metadata[CleanupMetadataKey.parentID], item.id)
        XCTAssertNotNil(expansion.targets.first?.metadata[CleanupMetadataKey.inode])
    }

    func testProtectedCachesAndSymlinksAreNeverOffered() {
        fx.file("Library/Caches/com.spotify.client/Data/track.bin", age: 3 * day)
        fx.file("Library/Caches/CloudKit/state.db", age: 3 * day)
        fx.file("Library/Caches/com.apple.Spotlight/index", age: 3 * day)
        fx.file("Library/Caches/com.crowdstrike.falcon/cache.bin", age: 3 * day)
        fx.file("Library/Caches/com.spruce.test/own.bin", age: 3 * day)
        let outside = fx.file("outside/precious.txt", age: 3 * day, in: fx.root)
        try? FileManager.default.createSymbolicLink(atPath: fx.home + "/Library/Caches/evil",
                                                    withDestinationPath: (outside as NSString).deletingLastPathComponent)
        fx.file("Library/Caches/com.example.ok/cache.bin", age: 3 * day)

        let (_, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let ids = report.groups.allItems.map(\.id)
        XCTAssertTrue(ids.contains { $0.hasSuffix("com.example.ok") })
        for forbidden in ["com.spotify.client", "CloudKit", "com.apple.Spotlight", "com.crowdstrike.falcon",
                          "com.spruce.test", "evil"] {
            XCTAssertFalse(ids.contains { $0.hasSuffix(forbidden) }, "\(forbidden) must not be offered")
        }
        XCTAssertFalse(ids.contains { $0.hasPrefix(fx.root + "/outside") })
    }

    func testRunningAppCacheIsSelectedButBlockedUntilTheAppQuits() throws {
        // CleanMyMac 5 behaviour: an open app's cache is selected, and cleaning asks to
        // quit the app first; it is never removed while the app is open.
        fx.file("Library/Caches/com.example.app/cache.bin", age: 2 * day)
        let (scanner, report) = fx.scan(fx.context(running: ["com.example.app"]), sections: [.systemJunk])
        let item = try XCTUnwrap(report.item(endingWith: "com.example.app"))
        XCTAssertTrue(item.isSelected)
        XCTAssertEqual(item.metadata[CleanupMetadataKey.inUse], "1")
        XCTAssertEqual(item.metadata[CleanupMetadataKey.quitToClean], "1")
        XCTAssertEqual(item.metadata[CleanupMetadataKey.recommended], "1")
        XCTAssertNotNil(scanner.blockingReason(for: item))

        // A helper of the app (reverse-DNS child) counts as the same owner.
        fx.file("Library/Caches/com.example.app.helper/cache.bin", age: 2 * day)
        let (_, second) = fx.scan(fx.context(running: ["com.example.app"]), sections: [.systemJunk])
        let helper = try XCTUnwrap(second.item(endingWith: "com.example.app.helper"))
        XCTAssertEqual(helper.metadata[CleanupMetadataKey.quitToClean], "1")
        XCTAssertEqual(CleanupOwnership.runningOwners(of: [item], running: ["com.example.app", "com.other"]),
                       ["com.example.app"])
    }

    func testSharedFirefoxFolderIsInUseWhileAnyFirefoxChannelIsOpen() throws {
        fx.file("Library/Caches/Firefox/Profiles/abcd.default/cache2/entries/0A1B", age: 2 * day)
        fx.ageFolders(fx.home + "/Library/Caches/Firefox/Profiles/abcd.default/cache2/entries", age: 2 * day)

        let (_, closed) = fx.scan(fx.context(running: ["com.example.other"]), sections: [.systemJunk])
        let idle = try XCTUnwrap(closed.item(endingWith: "Library/Caches/Firefox"))
        XCTAssertNil(idle.metadata[CleanupMetadataKey.inUse])
        XCTAssertEqual(idle.metadata[CleanupMetadataKey.bundleID], "org.mozilla.firefox")

        for channel in ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
                        "org.mozilla.firefoxbeta"] {
            let (scanner, report) = fx.scan(fx.context(running: [channel]), sections: [.systemJunk])
            let item = try XCTUnwrap(report.item(endingWith: "Library/Caches/Firefox"), channel)
            XCTAssertTrue(item.isSelected, channel)
            XCTAssertEqual(item.metadata[CleanupMetadataKey.inUse], "1", channel)
            XCTAssertEqual(item.metadata[CleanupMetadataKey.quitToClean], "1", channel)
            XCTAssertNotNil(scanner.blockingReason(for: item), channel)
            XCTAssertEqual(CleanupOwnership.runningOwners(of: [item], running: [channel, "com.other"]), [channel])
        }
    }

    func testEarlierRulesClaimTheirFoldersFromGenericCaches() throws {
        fx.file("Library/Caches/Homebrew/downloads/abc--wget.bottle.tar.gz", bytes: 40_000, age: 3 * day)
        let api = fx.file("Library/Caches/Homebrew/api/formula.jws.json", bytes: 20_000, age: 3 * day)
        fx.ageFolders(fx.home + "/Library/Caches/Homebrew/api", age: 3 * day)
        let (scanner, report) = fx.scan(fx.context(), sections: [.systemJunk])

        let brew = try XCTUnwrap(report.item(endingWith: "Library/Caches/Homebrew/downloads"))
        XCTAssertEqual(brew.metadata[CleanupMetadataKey.ruleID], "dev.homebrew")
        XCTAssertTrue(report.items(in: CleanupCategory.devJunk.rawValue).contains(brew))

        let generic = try XCTUnwrap(report.item(endingWith: "Library/Caches/Homebrew"))
        XCTAssertEqual(generic.metadata[CleanupMetadataKey.ruleID], "caches.user")
        let targets = scanner.expand(generic).targets.compactMap { $0.url?.path }
        XCTAssertEqual(targets, [(api as NSString).deletingLastPathComponent])
    }

    func testExcludedCategoriesAndIgnoreListAreHonoured() {
        fx.file("Library/Caches/com.example.app/cache.bin", age: 2 * day)
        let brew = fx.file("Library/Caches/Homebrew/downloads/pkg.tar.gz", age: 3 * day)
        fx.file("Library/Logs/MyApp/old.log", age: 30 * day)
        var settings = SpruceSettings()
        settings.excludedCleanupCategories = [CleanupCategory.userCaches.rawValue]
        settings.ignoredPaths = [(brew as NSString).deletingLastPathComponent]
        let (_, report) = fx.scan(fx.context(), settings: settings, sections: [.systemJunk])
        XCTAssertTrue(report.items(in: CleanupCategory.userCaches.rawValue).isEmpty)
        XCTAssertTrue(report.items(in: CleanupCategory.devJunk.rawValue).isEmpty)
        XCTAssertFalse(report.items(in: CleanupCategory.userLogs.rawValue).isEmpty)

        settings.excludedCleanupCategories = [CleanupSection.systemJunk.rawValue]
        let (_, none) = fx.scan(fx.context(), settings: settings, sections: [.systemJunk])
        XCTAssertTrue(none.groups.isEmpty)
    }

    func testSQLiteFamiliesStayTogether() throws {
        fx.file("Library/Caches/com.db.app/Cache.db", age: 2 * day)
        fx.file("Library/Caches/com.db.app/Cache.db-wal", age: 60)
        fx.file("Library/Caches/com.db.app/Cache.db-shm", age: 2 * day)
        fx.file("Library/Caches/com.db.app/other.bin", age: 2 * day)
        let (scanner, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let item = try XCTUnwrap(report.item(endingWith: "com.db.app"))
        let names = scanner.expand(item).targets.compactMap { $0.url?.lastPathComponent }
        XCTAssertEqual(names, ["other.bin"])
    }

    // MARK: Logs & temp

    func testLogFilesOlderThanAWeekAreTargetedFolderByFolder() throws {
        fx.file("Library/Logs/MyApp/old.log", age: 10 * day)
        fx.file("Library/Logs/MyApp/new.log", age: day)
        fx.file("Library/Logs/MyApp/archive/older.log", age: 40 * day)
        fx.file("Library/Logs/standalone.log", age: 9 * day)
        let (scanner, report) = fx.scan(fx.context(), sections: [.systemJunk])

        let row = try XCTUnwrap(report.item(endingWith: "Library/Logs/MyApp"))
        XCTAssertEqual(row.metadata[CleanupMetadataKey.mode], "files")
        let targets = scanner.expand(row).targets.compactMap { $0.url?.lastPathComponent }.sorted()
        XCTAssertEqual(targets, ["old.log", "older.log"])
        let file = try XCTUnwrap(report.item(endingWith: "Library/Logs/standalone.log"))
        XCTAssertEqual(file.metadata[CleanupMetadataKey.mode], "whole")
    }

    func testTemporaryFilesAreOwnOldAndNotOfRunningApps() throws {
        let tmp = fx.directory("T", in: fx.root)
        fx.file("stale.tmp", age: 5 * day, in: tmp)
        fx.file("fresh.tmp", age: 60, in: tmp)
        fx.file("server.lock", age: 5 * day, in: tmp)
        fx.file("com.run.app/state.tmp", age: 5 * day, in: tmp)
        fx.file("com.idle.app/state.tmp", age: 5 * day, in: tmp)
        let context = fx.context(running: ["com.run.app"], tempDir: tmp)
        let (scanner, report) = fx.scan(context, sections: [.systemJunk])
        let row = try XCTUnwrap(report.items(in: CleanupCategory.tempFiles.rawValue).first)
        let targets = scanner.expand(row).targets.compactMap { $0.url?.path }.sorted()
        XCTAssertEqual(targets, [tmp + "/com.idle.app/state.tmp", tmp + "/stale.tmp"])
    }

    // MARK: Xcode

    func testDeviceSupportKeepsTheNewestVersionUnselected() throws {
        fx.file("Library/Developer/Xcode/iOS DeviceSupport/16.4 (20E247)/Symbols/a", age: 30 * day)
        fx.file("Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 17.5.1 (21F90)/Symbols/a", age: 40 * day)
        fx.ageFolders(fx.home + "/Library/Developer/Xcode/iOS DeviceSupport/16.4 (20E247)/Symbols", age: 30 * day)
        fx.ageFolders(fx.home + "/Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 17.5.1 (21F90)/Symbols",
                      age: 40 * day)
        let (_, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let old = try XCTUnwrap(report.item(endingWith: "16.4 (20E247)"))
        let newest = try XCTUnwrap(report.item(endingWith: "17.5.1 (21F90)"))
        XCTAssertTrue(old.isSelected)
        XCTAssertFalse(newest.isSelected)
        XCTAssertEqual(newest.safety, .review)
    }

    func testXcodeJunkIsNotSelectedWhileBuildToolsRun() throws {
        fx.file("Library/Developer/Xcode/DerivedData/MyApp-abcdefghijklmnopqrstuvwxyzab/Build/x.o", age: 3 * day)
        fx.ageFolders(fx.home + "/Library/Developer/Xcode/DerivedData/MyApp-abcdefghijklmnopqrstuvwxyzab/Build",
                      age: 3 * day)
        let (_, idle) = fx.scan(fx.context(), sections: [.systemJunk])
        let item = try XCTUnwrap(idle.item(endingWith: "MyApp-abcdefghijklmnopqrstuvwxyzab"))
        XCTAssertEqual(item.title, "MyApp")
        XCTAssertTrue(item.isSelected)
        let (scanner, busy) = fx.scan(fx.context(processes: ["xcodebuild"]), sections: [.systemJunk])
        let blocked = try XCTUnwrap(busy.item(endingWith: "MyApp-abcdefghijklmnopqrstuvwxyzab"))
        XCTAssertFalse(blocked.isSelected)
        XCTAssertNotNil(scanner.blockingReason(for: blocked))
    }

    // MARK: Broken items

    func testBrokenPreferencesDetection() {
        let prefs = "Library/Preferences/"
        fx.file(prefs + "com.broken.app.plist", contents: Data("not a plist {".utf8))
        fx.file(prefs + "com.empty.app.plist", contents: Data())
        let valid = try! PropertyListSerialization.data(fromPropertyList: ["Key": "Value"], format: .xml, options: 0)
        fx.file(prefs + "com.good.app.plist", contents: valid)
        fx.file(prefs + ".GlobalPreferences.plist", contents: Data("garbage".utf8))
        fx.file(prefs + "com.temp.app.plist.Ab3dE9", age: 3 * day, contents: valid)
        fx.file(prefs + "com.keep.app.plist.backup", age: 3 * day, contents: valid)
        let (_, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let names = Set(report.items(in: CleanupCategory.brokenPreferences.rawValue).compactMap { $0.url?.lastPathComponent })
        XCTAssertEqual(names, ["com.broken.app.plist", "com.empty.app.plist", "com.temp.app.plist.Ab3dE9"])
        XCTAssertTrue(report.items(in: CleanupCategory.brokenPreferences.rawValue).allSatisfy { $0.deletion == .trash })
    }

    func testBrokenLaunchAgentsPointToMissingPrograms() throws {
        let tool = fx.file("bin/tool", in: fx.root)
        func agent(_ name: String, program: String) {
            let plist: [String: Any] = ["Label": name, "ProgramArguments": [program, "--flag"]]
            let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            fx.file("Library/LaunchAgents/\(name).plist", contents: data)
        }
        agent("com.vendor.gone", program: fx.root + "/removed/App.app/Contents/MacOS/helper")
        agent("com.vendor.present", program: tool)
        agent("com.apple.something", program: fx.root + "/missing/apple")
        agent("com.vendor.relative", program: "relative/tool")
        let (_, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let items = report.items(in: CleanupCategory.brokenLoginItems.rawValue)
        XCTAssertEqual(items.map(\.title), ["com.vendor.gone"])
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.metadata[CleanupMetadataKey.launchItem], "1")
        XCTAssertEqual(item.deletion, .trash)
    }

    private func launchAgent(_ name: String, program: String) {
        let plist: [String: Any] = ["Label": name, "Program": program]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        fx.file("Library/LaunchAgents/\(name).plist", contents: data)
    }

    func testLaunchTargetPresenceOnlyCountsConfirmedMissingPrograms() throws {
        let tool = fx.file("bin/tool", in: fx.root)
        XCTAssertEqual(CleanupScanner.presence(of: tool), .present)
        XCTAssertEqual(CleanupScanner.presence(of: fx.root + "/bin/gone"), .missing)
        XCTAssertEqual(CleanupScanner.presence(of: fx.root + "/removed/App.app/Contents/MacOS/helper"), .missing,
                       "the nearest existing folder can be listed")

        // A symlink loop: lstat fails with ELOOP, not ENOENT.
        let loop = fx.root + "/loop"
        try FileManager.default.createSymbolicLink(atPath: loop, withDestinationPath: loop)
        XCTAssertEqual(CleanupScanner.presence(of: loop + "/helper"), .unknown)

        // A folder that links to a volume or folder that isn't there.
        let linked = fx.root + "/linked"
        try FileManager.default.createSymbolicLink(atPath: linked, withDestinationPath: fx.root + "/unmounted")
        XCTAssertEqual(CleanupScanner.presence(of: linked + "/bin/helper"), .unknown)

        // A component that is a file: ENOTDIR is not "no such file".
        XCTAssertEqual(CleanupScanner.presence(of: tool + "/helper"), .unknown)
    }

    func testLaunchTargetInAFolderWeCannotSearchIsNotReported() throws {
        try XCTSkipIf(getuid() == 0, "root can search any folder")
        let vendor = fx.directory("vendor/private", in: fx.root)
        fx.file("vendor/private/helper", in: fx.root)
        chmod(vendor, 0o000)
        defer { chmod(vendor, 0o755) }
        XCTAssertEqual(CleanupScanner.presence(of: vendor + "/helper"), .unknown, "EACCES is not missing")
        launchAgent("com.vendor.restricted", program: vendor + "/helper")
        launchAgent("com.vendor.gone", program: fx.root + "/vendor/removed/helper")
        let (_, report) = fx.scan(fx.context(), sections: [.systemJunk])
        XCTAssertEqual(report.items(in: CleanupCategory.brokenLoginItems.rawValue).map(\.title), ["com.vendor.gone"])
    }

    func testBrokenLaunchAgentsSkipUncheckablePrograms() throws {
        let loop = fx.root + "/loop"
        try FileManager.default.createSymbolicLink(atPath: loop, withDestinationPath: loop)
        let linked = fx.root + "/linked"
        try FileManager.default.createSymbolicLink(atPath: linked, withDestinationPath: fx.root + "/unmounted")
        launchAgent("com.vendor.loop", program: loop + "/helper")
        launchAgent("com.vendor.linked", program: linked + "/helper")
        launchAgent("com.vendor.gone", program: fx.root + "/removed/helper")
        let (_, report) = fx.scan(fx.context(), sections: [.systemJunk])
        XCTAssertEqual(report.items(in: CleanupCategory.brokenLoginItems.rawValue).map(\.title), ["com.vendor.gone"])
    }

    func testBrokenLaunchAgentIsSkippedWhenItsProgramComesBack() throws {
        let program = fx.root + "/opt/vendor/helper"
        launchAgent("com.vendor.helper", program: program)
        let (scanner, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let item = try XCTUnwrap(report.items(in: CleanupCategory.brokenLoginItems.rawValue).first)
        XCTAssertNil(scanner.blockingReason(for: item), "still missing: can be cleaned")

        fx.file("opt/vendor/helper", in: fx.root)
        XCTAssertNotNil(scanner.blockingReason(for: item), "reinstalled since the scan")

        try FileManager.default.removeItem(atPath: try XCTUnwrap(item.url?.path))
        XCTAssertNil(scanner.blockingReason(for: item), "plist already gone: the remover counts it as done")
    }

    // MARK: Trash

    func testTrashBinsOnStartupDiskAndConnectedDrives() throws {
        fx.file(".Trash/report.pdf", age: day)
        fx.file(".Trash/.DS_Store", age: day)
        let volume = fx.directory("Volumes/Backup", in: fx.root)
        fx.file(".Trashes/\(CleanupContext.currentUID)/old-movie.mov", bytes: 30_000, age: day, in: volume)
        fx.file(".Trashes/999999/someone-else.bin", age: day, in: volume)
        let volumes = [CleanupVolume(path: volume, name: "Backup")]

        let (_, module) = fx.scan(fx.context(volumes: volumes), sections: [.trashBins])
        let startup = module.items(in: "trashBins.startup")
        XCTAssertEqual(startup.map(\.title), ["report.pdf"])
        XCTAssertTrue(startup.allSatisfy { $0.isSelected && $0.deletion == .remove })
        let external = module.items(in: "trashBins.volume.\(volume)")
        XCTAssertEqual(external.map(\.title), ["old-movie.mov"])
        XCTAssertTrue(external[0].isSelected)
        XCTAssertEqual(external[0].metadata[CleanupMetadataKey.zone], volume + "/.Trashes/\(CleanupContext.currentUID)")

        let (_, checkup) = fx.scan(fx.context(purpose: .checkup, volumes: volumes), sections: [.trashBins])
        XCTAssertTrue(checkup.items(in: "trashBins.startup").allSatisfy(\.isSelected))
        XCTAssertFalse(checkup.items(in: "trashBins.volume.\(volume)").contains(where: \.isSelected),
                       "Checkup never pre-selects a connected drive's Trash")
    }

    // MARK: Full Disk Access & Mail

    func testCategoriesNeedingFullDiskAccessAreReportedUnavailable() {
        fx.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/ABC/invoice.pdf", age: day)
        let (_, report) = fx.scan(fx.context(fullDiskAccess: false), sections: [.mailAttachments])
        XCTAssertTrue(report.groups.isEmpty)
        XCTAssertTrue(report.unavailable.contains { $0.category == .mailAttachments && $0.reason == .fullDiskAccess })
        XCTAssertTrue(report.isLimitedByFullDiskAccess)
    }

    func testMailAttachmentsAreSelectedOnlyWhenRecoverable() throws {
        fx.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/ABC/invoice.pdf", age: day)
        let base = "Library/Mail/V10/"
        fx.file(base + "SERVER-UUID/INBOX.mbox/X/Data/1/Attachments/101/2/photo.jpg", bytes: 20_000)
        fx.file(base + "SERVER-UUID/INBOX.mbox/X/Data/1/Messages/101.partial.emlx")
        fx.file(base + "POP-UUID/INBOX.mbox/Y/Data/Attachments/7/1/contract.pdf", bytes: 20_000)
        fx.file(base + "Mailboxes/Archive.mbox/Z/Data/Attachments/9/1/notes.txt", bytes: 20_000)
        fx.file("Library/Mail/V9/OLD-UUID/INBOX.mbox/Data/Attachments/1/1/old.bin", bytes: 20_000)
        let accounts = ["SERVER-UUID": CleanupMailAccount(name: "Work", kind: .server),
                        "POP-UUID": CleanupMailAccount(name: "Home", kind: .pop)]
        let (_, report) = fx.scan(fx.context(mailAccounts: accounts), sections: [.mailAttachments])

        let opened = try XCTUnwrap(report.items(in: "mailAttachments.opened").first)
        XCTAssertEqual(opened.title, "invoice.pdf")
        XCTAssertTrue(opened.isSelected)
        let server = try XCTUnwrap(report.items(in: "mailAttachments.account.SERVER-UUID").first)
        XCTAssertEqual(server.title, "photo.jpg")
        XCTAssertTrue(server.isSelected)
        XCTAssertEqual(server.deletion, .trash)
        let pop = try XCTUnwrap(report.items(in: "mailAttachments.account.POP-UUID").first)
        XCTAssertEqual(pop.safety, .risky)
        XCTAssertFalse(pop.isSelected)
        let local = try XCTUnwrap(report.items(in: "mailAttachments.account.Mailboxes").first)
        XCTAssertFalse(local.isSelected)
        XCTAssertNil(report.item(endingWith: "old.bin"), "only the current Mail store is scanned")
        XCTAssertNil(report.item(endingWith: "101.partial.emlx"), "messages are never offered")

        let (_, running) = fx.scan(fx.context(running: ["com.apple.mail"], mailAccounts: accounts),
                                   sections: [.mailAttachments])
        XCTAssertFalse(running.groups.allItems.contains(where: \.isSelected), "nothing is selected while Mail is open")
    }

    // MARK: iOS

    func testIOSBackupsAreNeverSelectedAndTheLatestIsFlagged() throws {
        let backups = "Library/Application Support/MobileSync/Backup/"
        func backup(_ folder: String, date: Date) {
            let info: [String: Any] = ["Device Name": "Ana's iPhone", "Last Backup Date": date,
                                       "Product Version": "17.5", "Target Identifier": "UDID-1"]
            let data = try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            fx.file(backups + folder + "/Info.plist", contents: data)
            fx.file(backups + folder + "/Manifest.db", bytes: 50_000)
        }
        backup("UDID-1", date: Date().addingTimeInterval(-2 * day))
        backup("UDID-1-20240101-101010", date: Date().addingTimeInterval(-300 * day))
        let (_, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let items = report.items(in: CleanupCategory.iosBackups.rawValue)
        XCTAssertEqual(items.count, 2)
        XCTAssertFalse(items.contains(where: \.isSelected))
        XCTAssertTrue(items.allSatisfy { $0.deletion == .trash && $0.title == "Ana's iPhone" })
        let latest = items.filter { $0.metadata[CleanupMetadataKey.latestBackup] == "1" }
        XCTAssertEqual(latest.map { $0.url?.lastPathComponent }, ["UDID-1"])
    }

    // MARK: Checkup, insights, expansion safety

    func testCheckupGathersOnlySafeUserLevelItems() {
        fx.file("Library/Caches/com.example.app/cache.bin", age: 2 * day)
        fx.file(".gradle/caches/modules-2/files/lib.jar", age: 3 * day)
        fx.file("Library/Caches/com.vendor.daemon/blob", age: 30 * day, in: fx.system)
        fx.file("Library/Developer/Xcode/Archives/2024-01-01/App.xcarchive/Info.plist", age: 30 * day)
        let (_, report) = fx.scan(fx.context(purpose: .checkup))
        let items = report.groups.allItems
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.safety == .safe })
        XCTAssertTrue(items.allSatisfy { $0.metadata[CleanupMetadataKey.needsAdmin] == nil })
        XCTAssertNil(report.item(endingWith: ".gradle/caches"))
        XCTAssertNil(report.item(endingWith: "App.xcarchive"))

        let (_, module) = fx.scan(fx.context(), sections: [.systemJunk])
        XCTAssertNotNil(module.item(endingWith: ".gradle/caches"))
        XCTAssertEqual(module.item(endingWith: ".gradle/caches")?.isSelected, false)
        let system = module.item(endingWith: "Library/Caches/com.vendor.daemon")
        XCTAssertEqual(system?.metadata[CleanupMetadataKey.needsAdmin], "1")
    }

    func testInformationalCategoriesProduceInsightsOnly() {
        fx.file("Users/Deleted Users/bob.dmg", bytes: 40_000, in: fx.system)
        fx.file(".DocumentRevisions-V100/db-V1/db.sqlite", bytes: 40_000, in: fx.system)
        let (_, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let ids = Set(report.insights.map(\.id))
        XCTAssertTrue(ids.contains("deletedUsers.bob.dmg"))
        XCTAssertTrue(ids.contains("documentVersions"))
        XCTAssertFalse(report.groups.allItems.contains { $0.id.contains("Deleted Users") || $0.id.contains("DocumentRevisions") })
    }

    func testExpansionRefusesAFolderReplacedSinceTheScan() throws {
        fx.file("Library/Caches/com.example.app/cache.bin", age: 2 * day)
        let (scanner, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let item = try XCTUnwrap(report.item(endingWith: "com.example.app"))
        let folder = fx.home + "/Library/Caches/com.example.app"
        try FileManager.default.removeItem(atPath: folder)
        fx.file("Library/Caches/placeholder", age: 2 * day)   // keep inode numbers from being reused at once
        fx.file("Library/Caches/com.example.app/other.bin", age: 2 * day)
        let expansion = scanner.expand(item)
        XCTAssertNotNil(expansion.failure)
        XCTAssertTrue(expansion.targets.isEmpty)
    }

    func testOldUpdatesFromSparkleRespectTheTenDayWindow() {
        fx.file("Library/Caches/com.vendor.app/org.sparkle-project.Sparkle/PersistentDownloads/abc/Update.zip", age: 20 * day)
        fx.ageFolders(fx.home + "/Library/Caches/com.vendor.app/org.sparkle-project.Sparkle/PersistentDownloads/abc",
                      upTo: fx.home + "/Library/Caches/com.vendor.app/org.sparkle-project.Sparkle/PersistentDownloads",
                      age: 20 * day)
        fx.file("Library/Caches/com.vendor.app/org.sparkle-project.Sparkle/PersistentDownloads/new/Update.zip", age: day)
        fx.file("Library/Caches/com.vendor.app/Cache.db", age: 2 * day)
        let (scanner, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let updates = report.items(in: CleanupCategory.oldUpdates.rawValue)
        XCTAssertEqual(updates.compactMap { $0.url?.lastPathComponent }, ["abc"])
        XCTAssertEqual(updates.first?.metadata[CleanupMetadataKey.owner], "com.vendor.app")
        // The generic cache row of the same app never includes Sparkle's folder.
        if let cache = report.item(endingWith: "Library/Caches/com.vendor.app") {
            let names = scanner.expand(cache).targets.compactMap { $0.url?.lastPathComponent }
            XCTAssertEqual(names, ["Cache.db"])
        } else {
            XCTFail("generic cache row missing")
        }
    }

    func testFolderNamesWithGlobCharactersDoNotDefeatClaims() throws {
        let app = "Library/Caches/com.vendor[1]*"
        fx.file(app + "/org.sparkle-project.Sparkle/PersistentDownloads/abc/Update.zip", age: 20 * day)
        fx.file(app + "/blob.bin", age: 2 * day)
        let (scanner, report) = fx.scan(fx.context(), sections: [.systemJunk])
        let row = try XCTUnwrap(report.item(endingWith: "Library/Caches/com.vendor[1]*"))
        let names = scanner.expand(row).targets.compactMap { $0.url?.lastPathComponent }
        XCTAssertEqual(names, ["blob.bin"], "the Sparkle folder belongs to Old Updates")
        XCTAssertEqual(CleanupPaths.escapeGlob("/a/b[1]*?"), "/a/b[[]1][*][?]")
    }

    func testCheckupKeepsCachesOfOpenAppsButLeavesOtherBlockedAndReviewItemsOut() throws {
        fx.file("Library/Caches/com.busy.app/cache.bin", age: 2 * day)
        fx.file("Library/Caches/com.idle.app/cache.bin", age: 2 * day)
        fx.file("Library/Developer/Xcode/DerivedData/MyApp-abcdefghijklmnopqrstuvwxyzab/Build/x.o", age: 3 * day)
        fx.ageFolders(fx.home + "/Library/Developer/Xcode/DerivedData/MyApp-abcdefghijklmnopqrstuvwxyzab/Build",
                      age: 3 * day)
        let context = fx.context(running: ["com.busy.app", "com.apple.dt.Xcode"], purpose: .checkup)
        let (_, report) = fx.scan(context, sections: [.systemJunk])
        XCTAssertNotNil(report.item(endingWith: "com.idle.app"))
        // Checkup's Run asks to quit the app, like the Cleanup module.
        let busy = try XCTUnwrap(report.item(endingWith: "com.busy.app"))
        XCTAssertEqual(busy.metadata[CleanupMetadataKey.quitToClean], "1")
        // Rules that skip open apps (Xcode junk while Xcode runs) stay out of Checkup.
        XCTAssertNil(report.item(endingWith: "MyApp-abcdefghijklmnopqrstuvwxyzab"))
        XCTAssertTrue(report.groups.allItems.allSatisfy(\.isSelected))
    }

    func testOpenAppCacheCountsRecentContentDownToTheFloorAndCleansItOnlyOnceTheAppQuit() throws {
        fx.file("Library/Caches/com.busy.app/old.bin", bytes: 10_000, age: 2 * day)
        fx.file("Library/Caches/com.busy.app/warm.bin", bytes: 20_000, age: 20 * 60)
        fx.file("Library/Caches/com.busy.app/live.bin", bytes: 30_000, age: 60)

        // Closed: content written in the last hour is neither counted nor removed.
        let (_, closed) = fx.scan(fx.context(), sections: [.systemJunk])
        let idle = try XCTUnwrap(closed.item(endingWith: "com.busy.app"))
        XCTAssertNil(idle.metadata[CleanupMetadataKey.quitToClean])

        // Open: the age limit shrinks to a few minutes, since nothing goes before the app quits.
        let (busyScanner, open) = fx.scan(fx.context(running: ["com.busy.app"]), sections: [.systemJunk])
        let item = try XCTUnwrap(open.item(endingWith: "com.busy.app"))
        XCTAssertGreaterThan(item.size, idle.size)
        XCTAssertNotNil(busyScanner.blockingReason(for: item), "never removed while the app is open")

        // After the app quit, cleaning takes the warm file, but not what was written in
        // the last few minutes (a helper may still be writing it).
        let (quitScanner, _) = fx.scan(fx.context(), sections: [.systemJunk])
        XCTAssertNil(quitScanner.blockingReason(for: item))
        let names = Set(quitScanner.expand(item).targets.compactMap { $0.url?.lastPathComponent })
        XCTAssertEqual(names, ["old.bin", "warm.bin"])
        // A row scanned while the app was closed keeps the full age limit.
        let idleNames = quitScanner.expand(idle).targets.compactMap { $0.url?.lastPathComponent }
        XCTAssertEqual(idleNames, ["old.bin"])
    }

    func testQuitFirstFileRowChangedJustBeforeCleaningIsSkipped() throws {
        // A loose cache file named after the app is a whole row; the floor applies to it too.
        let path = fx.file("Library/Caches/com.busy.app", age: 2 * day)
        let (_, open) = fx.scan(fx.context(running: ["com.busy.app"]), sections: [.systemJunk])
        let item = try XCTUnwrap(open.item(endingWith: "Library/Caches/com.busy.app"))
        XCTAssertEqual(item.metadata[CleanupMetadataKey.quitToClean], "1")
        let (quitScanner, _) = fx.scan(fx.context(), sections: [.systemJunk])
        XCTAssertEqual(quitScanner.expand(item).targets.count, 1)
        fx.setAge(path, 30)
        let expansion = quitScanner.expand(item)
        XCTAssertNotNil(expansion.failure)
        XCTAssertTrue(expansion.targets.isEmpty)
    }

    func testCacheHeldOnlyByABackgroundHelperStaysUnchecked() throws {
        // A background-only process can't be quit from the sheet, so its app's cache is
        // left alone (the old behaviour) instead of being selected and never cleaned.
        fx.file("Library/Caches/com.example.app/cache.bin", age: 2 * day)
        let context = fx.context(running: ["com.example.app.agent"], quittable: [])
        let (scanner, report) = fx.scan(context, sections: [.systemJunk])
        let item = try XCTUnwrap(report.item(endingWith: "com.example.app"))
        XCTAssertFalse(item.isSelected)
        XCTAssertEqual(item.metadata[CleanupMetadataKey.inUse], "1")
        XCTAssertNil(item.metadata[CleanupMetadataKey.quitToClean])
        XCTAssertNotNil(scanner.blockingReason(for: item))
        let (_, checkup) = fx.scan(fx.context(running: ["com.example.app.agent"], quittable: [], purpose: .checkup),
                                   sections: [.systemJunk])
        XCTAssertNil(checkup.item(endingWith: "com.example.app"))
    }

    func testGroupContainerCachesOfOpenAppsStayUncheckedAndProtectedVendorsAreNeverOffered() throws {
        let groups = "Library/Group Containers/"
        fx.file(groups + "ABCDE12345.com.example.app/Library/Caches/blob.bin", age: 2 * day)
        fx.file(groups + "ABCDE12345.com.crowdstrike.falcon/Library/Caches/blob.bin", age: 2 * day)
        fx.file(groups + "group.com.nordvpn.macos/Library/Caches/blob.bin", age: 2 * day)
        let (_, report) = fx.scan(fx.context(running: ["com.example.app"]), sections: [.systemJunk])
        let item = try XCTUnwrap(report.item(endingWith: "ABCDE12345.com.example.app/Library/Caches"))
        // Extensions sharing the container can't be seen by the running-app check.
        XCTAssertFalse(item.isSelected)
        XCTAssertNil(item.metadata[CleanupMetadataKey.quitToClean])
        XCTAssertNil(report.item(endingWith: "com.crowdstrike.falcon/Library/Caches"))
        XCTAssertNil(report.item(endingWith: "group.com.nordvpn.macos/Library/Caches"))
    }

    func testOldLogsOfOpenAppsAreSelectedWithoutQuittingThem() throws {
        fx.file("Library/Logs/com.example.app/old.log", age: 10 * day)
        fx.ageFolders(fx.home + "/Library/Logs/com.example.app", age: 10 * day)
        let (scanner, report) = fx.scan(fx.context(running: ["com.example.app"]), sections: [.systemJunk])
        let item = try XCTUnwrap(report.item(endingWith: "Library/Logs/com.example.app"))
        XCTAssertTrue(item.isSelected)
        XCTAssertNil(item.metadata[CleanupMetadataKey.inUse])
        XCTAssertNil(item.metadata[CleanupMetadataKey.owner], "no quit prompt for week-old logs")
        XCTAssertNil(scanner.blockingReason(for: item))
        XCTAssertTrue(CleanupOwnership.runningOwners(of: [item], running: ["com.example.app"]).isEmpty)
    }
}
