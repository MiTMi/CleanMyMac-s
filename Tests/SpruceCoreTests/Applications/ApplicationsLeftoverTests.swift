import Foundation
import XCTest
@testable import SpruceCore

final class ApplicationsLeftoverTests: XCTestCase {

    private func matcher(_ tree: ApplicationsTempTree) -> ApplicationsLeftoverMatcher {
        ApplicationsLeftoverMatcher(roots: ApplicationsLeftoverCatalog.roots(home: tree.path("home")))
    }

    func testFindsBundleIDNameTeamAndGroupMatches() {
        let tree = ApplicationsTempTree()
        let app = tree.dir("Applications/Maestro Studio.app")
        tree.dir("home/Library/Application Support/com.knoll.maestro")
        tree.dir("home/Library/Application Support/Maestro Studio")
        tree.dir("home/Library/Caches/com.knoll.maestro.ShipIt")
        tree.file("home/Library/Preferences/com.knoll.maestro.plist")
        tree.file("home/Library/Preferences/ByHost/com.knoll.maestro.0A1B2C3D-1111-2222-3333-444455556666.plist")
        tree.dir("home/Library/Group Containers/ABCDE12345.com.knoll.maestro")
        tree.dir("home/Library/Group Containers/group.shared.knoll")
        tree.dir("home/Library/Containers/com.knoll.maestro.ShareExtension")
        tree.dir("home/Library/Saved Application State/com.knoll.maestro.savedState")
        tree.file("home/Library/HTTPStorages/com.knoll.maestro.binarycookies")
        tree.file("home/Library/Logs/DiagnosticReports/MaestroStudio-2024-05-01-101010.ips")
        // Not this app's:
        tree.dir("home/Library/Application Support/com.knoll.other")
        tree.dir("home/Library/Application Support/Maestro")
        tree.dir("home/Library/Caches/com.apple.Safari")
        tree.file("home/Library/Preferences/com.knoll.maestroplus.plist")

        let identity = ApplicationsAppIdentity(bundleID: "com.knoll.maestro", bundlePath: app, names: ["Maestro Studio"],
                                               executableName: "MaestroStudio", teamID: "ABCDE12345",
                                               vendorToken: "knoll", appGroups: ["group.shared.knoll"],
                                               embeddedBundleIDs: ["com.knoll.maestro.ShareExtension"])
        let found = matcher(tree).candidates(for: identity)
        let names = Set(found.map { ($0.path as NSString).lastPathComponent })

        for expected in ["com.knoll.maestro", "Maestro Studio", "com.knoll.maestro.ShipIt", "com.knoll.maestro.plist",
                         "com.knoll.maestro.0A1B2C3D-1111-2222-3333-444455556666.plist", "ABCDE12345.com.knoll.maestro",
                         "group.shared.knoll", "com.knoll.maestro.ShareExtension", "com.knoll.maestro.savedState",
                         "com.knoll.maestro.binarycookies", "MaestroStudio-2024-05-01-101010.ips"] {
            XCTAssertTrue(names.contains(expected), "missing \(expected)")
        }
        for unexpected in ["com.knoll.other", "Maestro", "com.apple.Safari", "com.knoll.maestroplus.plist"] {
            XCTAssertFalse(names.contains(unexpected), "must not match \(unexpected)")
        }
        let byName = Dictionary(found.map { (($0.path as NSString).lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byName["com.knoll.maestro"]?.confidence, .owned)
        XCTAssertEqual(byName["Maestro Studio"]?.confidence, .strong)
        XCTAssertEqual(byName["com.knoll.maestro.plist"]?.kind, .preferences)
        XCTAssertTrue(byName["com.knoll.maestro"]?.isPreselected ?? false)
        XCTAssertTrue(byName["com.knoll.maestro.plist"]?.isResetPreselected ?? false)
    }

    func testVendorFolderChildrenMatch() {
        let tree = ApplicationsTempTree()
        let app = tree.dir("Applications/Google Chrome.app")
        tree.dir("home/Library/Application Support/Google/Chrome")
        tree.dir("home/Library/Application Support/Google/Drive")
        tree.dir("home/Library/Caches/Google/Chrome")
        let identity = applicationsIdentity("com.google.Chrome", name: "Google Chrome", bundlePath: app)
        let paths = matcher(tree).candidates(for: identity).map(\.path)
        XCTAssertTrue(paths.contains(tree.path("home/Library/Application Support/Google/Chrome")))
        XCTAssertTrue(paths.contains(tree.path("home/Library/Caches/Google/Chrome")))
        XCTAssertFalse(paths.contains(tree.path("home/Library/Application Support/Google/Drive")))
        XCTAssertFalse(paths.contains(tree.path("home/Library/Application Support/Google")), "the vendor folder itself is shared")
    }

    func testSharedAndMoreSpecificOwners() {
        let tree = ApplicationsTempTree()
        let pro = tree.dir("Applications/Foo Pro.app")
        let lite = tree.dir("Applications/Foo.app")
        let copy = tree.dir("home/Applications/Foo.app")
        tree.dir("home/Library/Caches/com.foo.app")
        tree.dir("home/Library/Caches/com.foo.app.pro")
        let fooLite = applicationsIdentity("com.foo.app", name: "Foo", bundlePath: lite)
        let fooPro = applicationsIdentity("com.foo.app.pro", name: "Foo Pro", bundlePath: pro)
        let fooCopy = applicationsIdentity("com.foo.app", name: "Foo", bundlePath: copy)

        let liteFound = matcher(tree).candidates(for: fooLite, others: [fooPro])
        let liteNames = liteFound.map { ($0.path as NSString).lastPathComponent }
        XCTAssertTrue(liteNames.contains("com.foo.app"))
        XCTAssertFalse(liteNames.contains("com.foo.app.pro"), "belongs to the more specific app")

        let withCopy = matcher(tree).candidates(for: fooLite, others: [fooCopy])
        let shared = withCopy.first { ($0.path as NSString).lastPathComponent == "com.foo.app" }
        XCTAssertEqual(shared?.sharedWith, ["Foo"])
        XCTAssertFalse(shared?.isPreselected ?? true, "data shared by two copies is never pre-selected")
    }

    func testCommonNamesAndGenericIDsAreConservative() {
        let tree = ApplicationsTempTree()
        let app = tree.dir("Applications/Music.app")
        tree.dir("home/Library/Application Support/Music")
        tree.dir("home/Library/Caches/com.github.Electron.helper")
        let music = applicationsIdentity("com.example.music", name: "Music", bundlePath: app)
        XCTAssertTrue(matcher(tree).candidates(for: music).isEmpty, "\"Music\" is too generic to match by name")

        let electronApp = tree.dir("Applications/Thing.app")
        let electron = applicationsIdentity("com.github.Electron", name: "Thing", bundlePath: electronApp)
        XCTAssertTrue(matcher(tree).candidates(for: electron).isEmpty, "generic ids only match exactly")
    }

    func testLaunchAgentOwnershipAndCollapse() {
        let tree = ApplicationsTempTree()
        let app = tree.dir("Applications/Widget Maker.app")
        tree.plist("home/Library/LaunchAgents/net.helper.daemon.plist",
                   ["Label": "net.helper.daemon", "ProgramArguments": [app + "/Contents/MacOS/helper", "--run"]])
        tree.plist("home/Library/LaunchAgents/org.unrelated.plist",
                   ["Label": "org.unrelated", "Program": "/usr/local/bin/unrelated"])
        tree.dir("home/Library/Application Support/com.wm.widgetmaker/Sub")
        let identity = applicationsIdentity("com.wm.widgetmaker", name: "Widget Maker", bundlePath: app)
        let found = matcher(tree).candidates(for: identity)
        let names = found.map { ($0.path as NSString).lastPathComponent }
        XCTAssertTrue(names.contains("net.helper.daemon.plist"))
        XCTAssertFalse(names.contains("org.unrelated.plist"))
        XCTAssertEqual(found.first { $0.kind == .launchItems }?.confidence, .owned)
        XCTAssertFalse(names.contains("Sub"))
    }

    func testNeverMatchesInsideAppBundles() {
        let tree = ApplicationsTempTree()
        let home = tree.path("home")
        let app = tree.dir("home/Library/Application Support/com.weird.app/Weird.app")
        let identity = applicationsIdentity("com.weird.app", name: "Weird", bundlePath: app)
        let found = ApplicationsLeftoverMatcher(roots: ApplicationsLeftoverCatalog.roots(home: home)).candidates(for: identity)
        XCTAssertTrue(found.isEmpty, "the folder containing the bundle must not be offered")
    }

    func testTokens() {
        XCTAssertEqual(ApplicationsTokens.strippedName("Bartender 5"), "Bartender")
        XCTAssertEqual(ApplicationsTokens.strippedName("Firefox Nightly"), "Firefox")
        XCTAssertNil(ApplicationsTokens.strippedName("Microsoft Edge"))
        XCTAssertEqual(ApplicationsTokens.bundleMatch("ABCDE12345.com.foo.bar", bundleID: "com.foo.bar", allowEmbedded: true), .embedded)
        XCTAssertEqual(ApplicationsTokens.bundleMatch("com.foo.barista", bundleID: "com.foo.bar", allowEmbedded: true), .none)
        XCTAssertEqual(ApplicationsTokens.bundleMatch("com.foo.x", bundleID: "com.foo", allowEmbedded: true), .none)
        XCTAssertTrue(ApplicationsTokens.isReverseDNS("com.foo.bar"))
        XCTAssertFalse(ApplicationsTokens.isReverseDNS("Foo Bar"))
        XCTAssertFalse(ApplicationsTokens.isReverseDNS("com.foo"))
        XCTAssertEqual(ApplicationsTokens.ownerKey(fromEntryName: "ABCDE12345.group.com.foo.bar")?.key, "com.foo.bar")
        XCTAssertEqual(ApplicationsTokens.ownerKey(fromEntryName: "ABCDE12345.group.com.foo.bar")?.teamID, "ABCDE12345")
        XCTAssertEqual(ApplicationsTokens.ownerKey(fromEntryName: "com.foo.bar.0A1B2C3D-1111-2222-3333-444455556666.plist")?.key, "com.foo.bar")
        XCTAssertEqual(ApplicationsTokens.displayName(forOwnerKey: "com.knollsoft.Rectangle"), "Rectangle")
        XCTAssertEqual(ApplicationsTokens.displayName(forOwnerKey: "com.vendor.bigapp.helper"), "Bigapp")
    }
}

final class ApplicationsOrphanTests: XCTestCase {

    func testFindsOnlyUnownedReverseDNSEntries() {
        let tree = ApplicationsTempTree()
        let home = tree.path("home")
        let old = Date(timeIntervalSinceNow: -40 * 86_400)
        tree.dir("home/Library/Application Support/com.gone.app")
        tree.file("home/Library/Preferences/com.gone.app.plist", modified: old)
        tree.dir("home/Library/Containers/com.gone.app")
        tree.dir("home/Library/Caches/com.installed.app")
        tree.dir("home/Library/Caches/com.installed.app.helper")
        tree.dir("home/Library/Caches/com.apple.Music")
        tree.dir("home/Library/Caches/org.sparkle-project.Sparkle")
        tree.dir("home/Library/Caches/Some Plain Name")
        tree.dir("home/Library/Group Containers/TEAM123456.com.team.shared")
        tree.dir("home/Library/Caches/com.recent.app")
        for p in ["home/Library/Application Support/com.gone.app", "home/Library/Containers/com.gone.app",
                  "home/Library/Caches/com.installed.app", "home/Library/Caches/com.installed.app.helper",
                  "home/Library/Caches/com.apple.Music", "home/Library/Caches/org.sparkle-project.Sparkle",
                  "home/Library/Caches/Some Plain Name", "home/Library/Group Containers/TEAM123456.com.team.shared"] {
            tree.setModified(tree.path(p), old)
        }

        let installed = applicationsIdentity("com.installed.app", name: "Installed", bundlePath: "/Applications/Installed.app",
                                             team: "TEAM123456")
        let index = ApplicationsInstalledIndex(identities: [installed])
        let orphans = ApplicationsOrphanDetector(roots: ApplicationsLeftoverCatalog.orphanRoots(home: home)).detect(index: index)

        XCTAssertEqual(orphans.map(\.ownerKey), ["com.gone.app"])
        XCTAssertEqual(orphans.first?.entries.count, 3)
        XCTAssertEqual(orphans.first?.displayName, "Gone")
    }

    func testBrokenLaunchAgentsOnly() {
        let tree = ApplicationsTempTree()
        let home = tree.path("home")
        tree.plist("home/Library/LaunchAgents/com.gone.updater.plist",
                   ["Label": "com.gone.updater", "Program": tree.path("missing/updater")])
        let existing = tree.file("bin/tool")
        tree.plist("home/Library/LaunchAgents/com.cli.tool.plist", ["Label": "com.cli.tool", "Program": existing])
        let orphans = ApplicationsOrphanDetector(roots: ApplicationsLeftoverCatalog.orphanRoots(home: home))
            .detect(index: ApplicationsInstalledIndex(identities: []))
        XCTAssertEqual(orphans.map(\.ownerKey), ["com.gone.updater"])
        XCTAssertTrue(orphans.first?.entries.first?.isBrokenLaunchJob ?? false)
    }

    func testIndexOwnership() {
        let a = applicationsIdentity("com.vendor.product", name: "Product", bundlePath: "/Applications/Product.app",
                                     groups: ["group.com.vendor.shared"], embedded: ["com.vendor.product.helper"])
        let index = ApplicationsInstalledIndex(identities: [a], extraBundleIDs: ["org.running.thing"])
        XCTAssertTrue(index.owns(ownerKey: "com.vendor.product"))
        XCTAssertTrue(index.owns(ownerKey: "com.vendor.product.ShipIt"))
        XCTAssertTrue(index.owns(ownerKey: "com.vendor.shared"))
        XCTAssertTrue(index.owns(ownerKey: "org.running.thing"))
        XCTAssertFalse(index.owns(ownerKey: "com.vendor.other"))
        XCTAssertEqual(index.sameVendorApp(ownerKey: "com.vendor.other"), "Product")
    }

    func testPlanBuildsUnselectedReviewGroups() {
        let tree = ApplicationsTempTree()
        let path = tree.file("x/com.gone.app.plist", bytes: 4096)
        let group = ApplicationsOrphanGroup(ownerKey: "com.gone.app", displayName: "App",
                                            entries: [ApplicationsOrphanEntry(path: path, kind: .preferences)])
        let groups = ApplicationsOrphanPlan.groups([group])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].allItems.count, 1)
        XCTAssertFalse(groups[0].allItems[0].isSelected)
        XCTAssertEqual(groups[0].allItems[0].safety, .review)
        XCTAssertNotNil(groups[0].allItems[0].metadata["inode"])
    }
}

final class ApplicationsInstallerTests: XCTestCase {

    func testInstallerKeys() {
        XCTAssertEqual(ApplicationsInstallerDetector.installerKey(fileName: "Firefox 121.0.dmg"), "firefox")
        XCTAssertEqual(ApplicationsInstallerDetector.installerKey(fileName: "Slack-4.36.140-macOS.dmg"), "slack")
        XCTAssertEqual(ApplicationsInstallerDetector.installerKey(fileName: "rectangle0.79.dmg"), "rectangle")
        XCTAssertEqual(ApplicationsInstallerDetector.installerKey(fileName: "VSCode-darwin-universal.zip"), "vscode")
        XCTAssertEqual(ApplicationsInstallerDetector.installerKey(fileName: "googlechrome.dmg"), "googlechrome")
    }

    func testZipIndexReadsTopLevelEntries() {
        let tree = ApplicationsTempTree()
        let zip = tree.zip("a.zip", entries: ["Visual Studio Code.app/", "Visual Studio Code.app/Contents/Info.plist",
                                               "__MACOSX/._x", "README.txt"])
        XCTAssertEqual(ApplicationsZipIndex.topLevelEntries(atPath: zip), ["Visual Studio Code.app", "README.txt"])
        let notZip = tree.file("b.zip", bytes: 100)
        XCTAssertNil(ApplicationsZipIndex.topLevelEntries(atPath: notZip))
    }

    func testScanClassifiesAndMatches() {
        let tree = ApplicationsTempTree()
        let old = Date(timeIntervalSinceNow: -60 * 86_400)
        tree.file("Downloads/Firefox 121.0.dmg", bytes: 2048, modified: old)
        tree.file("Downloads/Unknown Tool 1.0.pkg", bytes: 1024, modified: old)
        tree.file("Downloads/sub/deeper/Slack-4.36.dmg", bytes: 1024)
        tree.zip("Downloads/VSCode-darwin-universal.zip", entries: ["Visual Studio Code.app/", "Visual Studio Code.app/Contents/x"])
        tree.zip("Downloads/photos.zip", entries: ["IMG_0001.jpg"])
        tree.file("Downloads/notes.txt")
        tree.file("Desktop/Mounted.dmg", bytes: 512, modified: old)
        tree.dir("Downloads/Already.app/Contents")

        let detector = ApplicationsInstallerDetector(roots: [(tree.path("Downloads"), 2), (tree.path("Desktop"), 0)])
        let found = detector.scan(installedAppNames: ["Firefox", "Visual Studio Code", "Slack", "Mounted"],
                                  attachedImages: [tree.path("Desktop/Mounted.dmg")])
        let byName = Dictionary(found.map { (($0.path as NSString).lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(Set(byName.keys), ["Firefox 121.0.dmg", "Unknown Tool 1.0.pkg", "Slack-4.36.dmg",
                                           "VSCode-darwin-universal.zip", "Mounted.dmg"])
        XCTAssertEqual(byName["Firefox 121.0.dmg"]?.installedApp, "Firefox")
        XCTAssertEqual(byName["VSCode-darwin-universal.zip"]?.installedApp, "Visual Studio Code")
        XCTAssertEqual(byName["VSCode-darwin-universal.zip"]?.kind, .appArchive)
        XCTAssertNil(byName["Unknown Tool 1.0.pkg"]?.installedApp)
        XCTAssertTrue(byName["Firefox 121.0.dmg"]?.isSafe() ?? false)
        XCTAssertFalse(byName["Slack-4.36.dmg"]?.isSafe() ?? true, "recent downloads are not pre-selected")
        XCTAssertFalse(byName["Mounted.dmg"]?.isSafe() ?? true, "mounted images are not pre-selected")

        let groups = ApplicationsInstallerPlan.groups(found)
        let selected = groups.selectedItems.map { ($0.url!.path as NSString).lastPathComponent }
        XCTAssertEqual(selected, ["Firefox 121.0.dmg"])
    }
}
