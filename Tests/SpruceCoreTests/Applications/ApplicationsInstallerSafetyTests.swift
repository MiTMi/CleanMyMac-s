import Foundation
import XCTest
@testable import SpruceCore

/// Old installers may only be pre-selected when Spruce is sure they are installers of an
/// installed third-party app (never personal disk images that merely share a name).
final class ApplicationsInstallerSafetyTests: XCTestCase {
    private let old = Date(timeIntervalSinceNow: -90 * 86_400)

    private func scan(_ tree: ApplicationsTempTree,
                      apps: [ApplicationsInstallerDetector.InstalledApp]) -> [String: ApplicationsInstallerFile] {
        let detector = ApplicationsInstallerDetector(roots: [(tree.path("Downloads"), 2), (tree.path("Desktop"), 0)])
        let found = detector.scan(installedApps: apps)
        return Dictionary(found.map { (($0.path as NSString).lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func testSystemAppNamesNeverMatch() {
        let tree = ApplicationsTempTree()
        tree.file("Downloads/Photos 2019.dmg", bytes: 4096, modified: old)
        tree.file("Desktop/Music.dmg", bytes: 4096, modified: old)
        tree.file("Desktop/Home Videos.dmg", bytes: 4096, modified: old)
        let byName = scan(tree, apps: [.init(name: "Photos", isSystem: true), .init(name: "Music", isSystem: true),
                                       .init(name: "Home", isSystem: true), .init(name: "Notes", isSystem: true)])
        XCTAssertEqual(byName.count, 3)
        for file in byName.values {
            XCTAssertNil(file.installedApp, file.path)
            XCTAssertFalse(file.isSafe(), file.path)
        }
    }

    func testCommonWordAndPrefixMatchesStayUnticked() {
        let tree = ApplicationsTempTree()
        tree.file("Downloads/Home Videos.dmg", bytes: 1024, modified: old)
        tree.file("Downloads/Notes 2.dmg", bytes: 1024, modified: old)
        tree.file("Downloads/Steam Library Backup.dmg", bytes: 1024, modified: old)
        tree.file("Downloads/zoomusInstaller.pkg", bytes: 1024, modified: old)
        tree.file("Downloads/Firefox 121.0.dmg", bytes: 1024, modified: old)
        let byName = scan(tree, apps: [.init(name: "Home"), .init(name: "Notes"), .init(name: "Steam"),
                                       .init(name: "zoom.us"), .init(name: "Firefox")])

        XCTAssertNil(byName["Home Videos.dmg"]?.installedApp, "a common word is not matched by prefix")
        XCTAssertEqual(byName["Notes 2.dmg"]?.installedApp, "Notes")
        XCTAssertEqual(byName["Notes 2.dmg"]?.match, .partialName, "common-word app names are only a guess")
        XCTAssertEqual(byName["Steam Library Backup.dmg"]?.installedApp, "Steam")
        XCTAssertEqual(byName["Steam Library Backup.dmg"]?.match, .partialName)
        XCTAssertEqual(byName["Steam Library Backup.dmg"]?.personalWord, "library")
        XCTAssertEqual(byName["zoomusInstaller.pkg"]?.match, .partialName)
        XCTAssertEqual(byName["Firefox 121.0.dmg"]?.match, .exactName)

        let groups = ApplicationsInstallerPlan.groups(Array(byName.values))
        let selected = groups.selectedItems.map { ($0.url!.path as NSString).lastPathComponent }
        XCTAssertEqual(selected, ["Firefox 121.0.dmg"])
        let steam = groups.allItems.first { $0.title == "Steam Library Backup.dmg" }
        XCTAssertEqual(steam?.safety, .review)
        XCTAssertTrue(steam?.subtitle?.hasPrefix("Maybe for Steam") ?? false)
        XCTAssertTrue(steam?.note?.contains("library") ?? false)
    }

    func testPersonalWordsBlockPreselection() {
        XCTAssertEqual(ApplicationsInstallerDetector.personalWord(fileName: "Photos 2019.dmg"), "photos")
        XCTAssertEqual(ApplicationsInstallerDetector.personalWord(fileName: "Firefox-backup2.dmg"), "backup")
        XCTAssertEqual(ApplicationsInstallerDetector.personalWord(fileName: "Archive.zip"), "archive")
        XCTAssertNil(ApplicationsInstallerDetector.personalWord(fileName: "Firefox 121.0.dmg"))
        XCTAssertNil(ApplicationsInstallerDetector.personalWord(fileName: "Homebrew-4.2.pkg"), "only whole words count")

        let file = ApplicationsInstallerFile(path: "/tmp/Firefox backup.dmg", kind: .diskImage, size: 1, modified: old,
                                             installedApp: "Firefox", match: .exactName, personalWord: "backup")
        XCTAssertFalse(file.isSafe())
    }

    func testEncryptedDiskImagesAreNeverPreselected() {
        let tree = ApplicationsTempTree()
        let encrypted = tree.path("Downloads/Firefox.dmg")
        try? FileManager.default.createDirectory(atPath: tree.path("Downloads"), withIntermediateDirectories: true)
        var data = Data("encrcdsa".utf8)
        data.append(Data(repeating: 0, count: 600))
        FileManager.default.createFile(atPath: encrypted, contents: data)
        tree.setModified(encrypted, old)
        let legacy = tree.path("Downloads/Rectangle.dmg")
        var legacyData = Data(repeating: 0, count: 600)
        legacyData.append(Data("cdsaencr".utf8))
        FileManager.default.createFile(atPath: legacy, contents: legacyData)
        tree.setModified(legacy, old)
        let plain = tree.file("Downloads/Slack.dmg", bytes: 600, modified: old)

        XCTAssertTrue(ApplicationsDiskImage.isEncrypted(atPath: encrypted))
        XCTAssertTrue(ApplicationsDiskImage.isEncrypted(atPath: legacy))
        XCTAssertFalse(ApplicationsDiskImage.isEncrypted(atPath: plain))

        let byName = scan(tree, apps: [.init(name: "Firefox"), .init(name: "Rectangle"), .init(name: "Slack")])
        XCTAssertEqual(byName["Firefox.dmg"]?.isEncrypted, true)
        XCTAssertFalse(byName["Firefox.dmg"]?.isSafe() ?? true)
        XCTAssertFalse(byName["Rectangle.dmg"]?.isSafe() ?? true)
        XCTAssertTrue(byName["Slack.dmg"]?.isSafe() ?? false)
        XCTAssertTrue(byName["Firefox.dmg"]?.note().contains("encrypted") ?? false)
    }

    func testArchiveContentsMatchIsConfident() {
        let tree = ApplicationsTempTree()
        let zip = tree.zip("Downloads/download (3).zip", entries: ["Rectangle.app/", "Rectangle.app/Contents/Info.plist"])
        tree.setModified(zip, old)
        let byName = scan(tree, apps: [.init(name: "Rectangle")])
        XCTAssertEqual(byName["download (3).zip"]?.match, .contents)
        XCTAssertTrue(byName["download (3).zip"]?.isSafe() ?? false)
    }

    func testDescribeHandedOverFilesNeverPreselects() {
        let tree = ApplicationsTempTree()
        let pkg = tree.file("Elsewhere/Firefox 121.0.pkg", bytes: 2048, modified: old)
        let text = tree.file("Elsewhere/readme.txt")
        let bundlePkg = tree.dir("Elsewhere/Legacy.pkg/Contents")
        let detector = ApplicationsInstallerDetector(roots: [])
        let files = detector.describe(paths: [pkg, text, (bundlePkg as NSString).deletingLastPathComponent],
                                      installedApps: [.init(name: "Firefox")])
        XCTAssertEqual(files.map { ($0.path as NSString).lastPathComponent }.sorted(), ["Firefox 121.0.pkg", "Legacy.pkg"])
        let groups = ApplicationsInstallerPlan.groups(files, preselect: false)
        XCTAssertTrue(groups.selectedItems.isEmpty)
        XCTAssertEqual(groups.allItems.count, 2)
    }
}
