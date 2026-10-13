import Foundation
import XCTest
@testable import SpruceCore

// MARK: - Sparkle updates installed in place

final class ApplicationsSparkleInstallTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()
    private let signature = Data(repeating: 9, count: 64).base64EncodedString()

    private func app(key: String? = nil, team: String? = "ABCDE12345") -> ApplicationsAppInfo {
        ApplicationsAppInfo(path: "/Applications/Rectangle.app", name: "Rectangle", bundleID: "com.knollsoft.Rectangle",
                            version: "0.79", build: "79", teamID: team, sparkleFeedURL: "https://example.com/appcast.xml",
                            sparklePublicEDKey: key, codeSignature: .identified)
    }

    private func update(url: String = "https://example.com/Rectangle0.80.dmg", signature: String? = nil,
                        major: Bool = false, type: String? = nil) -> ApplicationsUpdate {
        ApplicationsUpdate(appPath: "/Applications/Rectangle.app", bundleID: "com.knollsoft.Rectangle", name: "Rectangle",
                           installedVersion: "0.79", availableVersion: "0.80", source: .sparkle, downloadURL: URL(string: url),
                           isMajor: major, edSignature: signature, availableBuild: "80", installationType: type)
    }

    func testAppcastReadsSignatureAndSkipsDeltas() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <title>0.80</title><sparkle:version>80</sparkle:version><sparkle:shortVersionString>0.80</sparkle:shortVersionString>
        <enclosure url="https://example.com/Rectangle0.80.dmg" length="1000" type="application/octet-stream" sparkle:edSignature="\(signature)"/>
        <sparkle:deltas>
        <enclosure url="https://example.com/Rectangle79-80.delta" sparkle:deltaFrom="79" length="10" sparkle:edSignature="AAAA"/>
        </sparkle:deltas>
        </item></channel></rss>
        """
        let items = ApplicationsAppcast.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].enclosureURL, "https://example.com/Rectangle0.80.dmg", "a delta never replaces the full download")
        XCTAssertEqual(items[0].edSignature, signature)
        let built = ApplicationsUpdate.fromAppcast(items[0], app: app(key: key), feedURL: nil)
        XCTAssertEqual(built?.edSignature, signature)
        XCTAssertEqual(built?.availableBuild, "80")
    }

    func testOnlySignedSecureArchivesAreInstalledInPlace() {
        let signed = app(key: key)
        XCTAssertNil(ApplicationsSparkleInstallPlan.blocker(update: update(signature: signature), app: signed))
        XCTAssertEqual(ApplicationsSparkleInstallPlan.method(for: update(signature: signature), app: signed), .sparkle)

        XCTAssertNotNil(ApplicationsSparkleInstallPlan.blocker(update: update(), app: signed), "no signature")
        XCTAssertNotNil(ApplicationsSparkleInstallPlan.blocker(update: update(signature: signature), app: app()), "no key in the app")
        XCTAssertNotNil(ApplicationsSparkleInstallPlan.blocker(update: update(signature: signature), app: app(key: key, team: nil)),
                        "no team to compare the new version with")
        XCTAssertNotNil(ApplicationsSparkleInstallPlan.blocker(update: update(url: "http://example.com/a.zip", signature: signature),
                                                               app: signed), "plain HTTP")
        XCTAssertNotNil(ApplicationsSparkleInstallPlan.blocker(update: update(url: "https://example.com/a.pkg", signature: signature),
                                                               app: signed), "installer packages")
        XCTAssertNotNil(ApplicationsSparkleInstallPlan.blocker(update: update(signature: signature, type: "package"), app: signed))
        XCTAssertNotNil(ApplicationsSparkleInstallPlan.blocker(update: update(signature: signature, major: true), app: signed),
                        "major upgrades go to the developer's page")
        XCTAssertNotNil(ApplicationsSparkleInstallPlan.blocker(update: update(signature: "short"), app: signed), "malformed signature")
        XCTAssertEqual(ApplicationsSparkleInstallPlan.method(for: update(), app: signed), .handOff)
    }

    func testArchiveSniffing() {
        XCTAssertEqual(ApplicationsSparkleInstallPlan.sniff(header: Data([0x50, 0x4B, 0x03, 0x04, 0, 0]), trailer: Data()), .zip)
        XCTAssertEqual(ApplicationsSparkleInstallPlan.sniff(header: Data([0x1F, 0x8B, 8]), trailer: Data()), .tar)
        XCTAssertEqual(ApplicationsSparkleInstallPlan.sniff(header: Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]), trailer: Data()), .tar)
        var trailer = Data("koly".utf8)
        trailer.append(Data(repeating: 0, count: 508))
        XCTAssertEqual(ApplicationsSparkleInstallPlan.sniff(header: Data(repeating: 0, count: 512), trailer: trailer), .diskImage)
        XCTAssertNil(ApplicationsSparkleInstallPlan.sniff(header: Data("xar!".utf8), trailer: trailer), "flat installer package")
        XCTAssertNil(ApplicationsSparkleInstallPlan.sniff(header: Data("<html>".utf8), trailer: Data()))
    }

    func testReplacementMustBeTheSameAppAndNewer() {
        let installed = app(key: key)
        XCTAssertTrue(ApplicationsSparkleInstallPlan.acceptsReplacement(installed: installed, newBundleID: "com.knollsoft.rectangle",
                                                                         newVersion: "0.80", newBuild: "80"))
        XCTAssertFalse(ApplicationsSparkleInstallPlan.acceptsReplacement(installed: installed, newBundleID: "com.evil.app",
                                                                          newVersion: "0.80", newBuild: "80"))
        XCTAssertFalse(ApplicationsSparkleInstallPlan.acceptsReplacement(installed: installed, newBundleID: "com.knollsoft.Rectangle",
                                                                          newVersion: "0.78", newBuild: "78"), "never a downgrade")
    }

    func testCheckupOffersSignedSparkleUpdatesUnticked() {
        let signed = app(key: key)
        let sparkle = update(signature: signature)
        let unsigned = ApplicationsUpdate(appPath: "/Applications/Other.app", bundleID: "com.other", name: "Other",
                                          installedVersion: "1", availableVersion: "2", source: .sparkle,
                                          downloadURL: URL(string: "https://example.com/o.zip"))
        let orphan = ScanGroup(id: "o", title: "Gone", items: [ScanItem(id: "/x", title: "x", size: 5, safety: .safe)])
        let review = ApplicationsCheckupPlan.review(updates: [sparkle, unsigned], orphanGroups: [orphan], apps: [signed])
        XCTAssertEqual(review.first?.title, "App Updates")
        XCTAssertEqual(review.first?.items.map(\.title), ["Rectangle 0.80"])
        XCTAssertEqual(review.first?.items.first?.metadata[ApplicationsMeta.updateMethod], "sparkle")
        XCTAssertTrue(review.selectedItems.isEmpty, "Checkup never pre-selects updates or leftovers")
    }
}

// MARK: - Update notifications

final class ApplicationsUpdateAlertTests: XCTestCase {
    private func update(_ name: String, _ version: String, critical: Bool = false) -> ApplicationsUpdate {
        ApplicationsUpdate(appPath: "/Applications/\(name).app", bundleID: "com.example.\(name.lowercased())", name: name,
                           installedVersion: "1.0", availableVersion: version, source: .sparkle, isCritical: critical)
    }

    func testDueOncePerDay() {
        let now = Date()
        XCTAssertTrue(ApplicationsUpdateAlertPlan.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(ApplicationsUpdateAlertPlan.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(ApplicationsUpdateAlertPlan.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertTrue(ApplicationsUpdateAlertPlan.isDue(lastCheck: now.addingTimeInterval(86_400 * 3), now: now),
                      "a clock set back doesn't stop checks")
    }

    func testOnlyNewVersionsAreAnnounced() {
        let vlc = update("VLC", "3.0.21")
        let rectangle = update("Rectangle", "0.80")
        var notified: [String] = []
        XCTAssertEqual(ApplicationsUpdateAlertPlan.newUpdates([vlc, rectangle], notified: notified).count, 2)
        notified = ApplicationsUpdateAlertPlan.remembered(after: [vlc, rectangle], previously: notified)
        XCTAssertTrue(ApplicationsUpdateAlertPlan.newUpdates([vlc, rectangle], notified: notified).isEmpty)

        let newerVLC = update("VLC", "3.0.22")
        XCTAssertEqual(ApplicationsUpdateAlertPlan.newUpdates([newerVLC, rectangle], notified: notified).map(\.name), ["VLC"])
        notified = ApplicationsUpdateAlertPlan.remembered(after: [newerVLC], previously: notified)
        XCTAssertEqual(notified, [newerVLC.skipVersionKey], "versions no longer offered are forgotten")
    }

    func testMessage() {
        let one = ApplicationsUpdateAlertPlan.message(newUpdates: [update("VLC", "3.0.21")], totalAvailable: 1)
        XCTAssertEqual(one.title, "Update available for VLC")
        XCTAssertEqual(one.body, "VLC 3.0.21. Review it in Spruce.")
        let many = ApplicationsUpdateAlertPlan.message(
            newUpdates: [update("VLC", "3"), update("Rectangle", "1"), update("Zed", "2", critical: true), update("Arc", "4")],
            totalAvailable: 6)
        XCTAssertEqual(many.title, "6 app updates available")
        XCTAssertTrue(many.body.hasPrefix("Zed 2, Arc 4, Rectangle 1 and 1 more"), many.body)
        XCTAssertTrue(many.body.contains("important"))
    }

    func testStateDecodesLeniently() throws {
        let state = try JSONDecoder().decode(ApplicationsUpdateAlertState.self, from: Data("{}".utf8))
        XCTAssertEqual(state, ApplicationsUpdateAlertState())
    }
}

// MARK: - Apps dragged to the Trash

final class ApplicationsTrashedAppTests: XCTestCase {
    func testSkipReasons() {
        func reason(_ id: String, ignored: [String] = [], spruce: Bool = false, elsewhere: Bool = false,
                    running: Bool = false) -> ApplicationsTrashedAppRules.Skip? {
            ApplicationsTrashedAppRules.skipReason(bundleID: id, ownBundleID: "app.spruce.Spruce", ignoredBundleIDs: ignored,
                                                   removedBySpruce: spruce, installedElsewhere: elsewhere, isRunning: running)
        }
        XCTAssertNil(reason("com.example.tool"))
        XCTAssertEqual(reason(""), .noBundleID)
        XCTAssertEqual(reason("com.apple.Safari"), .apple)
        XCTAssertEqual(reason("app.spruce.spruce"), .spruce)
        XCTAssertEqual(reason("com.example.tool", ignored: ["COM.EXAMPLE.TOOL"]), .ignored)
        XCTAssertEqual(reason("com.example.tool", spruce: true), .removedBySpruce)
        XCTAssertEqual(reason("com.example.tool", elsewhere: true), .stillInstalled, "an update replaced it")
        XCTAssertEqual(reason("com.example.tool", running: true), .running)
    }

    func testWorthOfferingAndMessage() {
        XCTAssertFalse(ApplicationsTrashedAppRules.isWorthOffering(bytes: 10_000_000, count: 0, hasLaunchItem: false))
        XCTAssertFalse(ApplicationsTrashedAppRules.isWorthOffering(bytes: 20_000, count: 3, hasLaunchItem: false))
        XCTAssertTrue(ApplicationsTrashedAppRules.isWorthOffering(bytes: 20_000, count: 1, hasLaunchItem: true))
        XCTAssertTrue(ApplicationsTrashedAppRules.isWorthOffering(bytes: 2_000_000, count: 4, hasLaunchItem: false))
        let message = ApplicationsTrashedAppRules.message(appName: "Tool", count: 14, bytes: 312_000_000)
        XCTAssertEqual(message.title, "Finish removing \u{201C}Tool\u{201D}?")
        XCTAssertTrue(message.body.hasPrefix("Tool left 14 items (312 MB)"), message.body)
        XCTAssertEqual(ApplicationsTrashedAppRules.notificationID(bundleID: "Com.Example.Tool"), "app.spruce.trashed.com.example.tool")
    }

    func testTrashPathsAndNewBundles() {
        XCTAssertTrue(ApplicationsTrashedAppRules.isInTrash("/Users/me/.Trash/Tool.app", home: "/Users/me"))
        XCTAssertTrue(ApplicationsTrashedAppRules.isInTrash("/Volumes/Disk/.Trashes/501/Tool.app", home: "/Users/me"))
        XCTAssertFalse(ApplicationsTrashedAppRules.isInTrash("/Applications/Tool.app", home: "/Users/me"))
        XCTAssertFalse(ApplicationsTrashedAppRules.isInTrash("/Users/me/.Trash", home: "/Users/me"))
        XCTAssertEqual(ApplicationsTrashedAppRules.newBundles(previous: ["Old.app"], current: ["Old.app", "New.app", "notes.txt"]),
                       ["New.app"])
    }

    func testRemovedAppLog() {
        let identity = applicationsIdentity("com.example.tool", name: "Tool", bundlePath: "/Users/me/.Trash/Tool.app")
        let now = Date()
        var log = ApplicationsRemovedAppLog()
        log.record(ApplicationsRemovedApp(bundleID: "com.example.tool", name: "Tool", trashedPath: identity.bundlePath,
                                          removedAt: now.addingTimeInterval(-60), identity: identity))
        log.record(ApplicationsRemovedApp(bundleID: "Com.Example.Tool", name: "Tool", trashedPath: identity.bundlePath,
                                          removedAt: now, identity: identity))
        XCTAssertEqual(log.apps.count, 1, "one entry per app")
        log.record(ApplicationsRemovedApp(bundleID: "com.example.old", name: "Old", trashedPath: "/x",
                                          removedAt: now.addingTimeInterval(-40 * 86_400), identity: identity))
        log.prune(now: now, installedBundleIDs: [])
        XCTAssertEqual(log.apps.map(\.bundleID), ["Com.Example.Tool"], "old entries expire")
        log.prune(now: now, installedBundleIDs: ["com.example.tool"])
        XCTAssertTrue(log.apps.isEmpty, "put back → forgotten")
    }

    func testRemovedAppGroupsPreselectOnlyClearMatches() {
        let tree = ApplicationsTempTree()
        let identity = applicationsIdentity("com.example.tool", name: "Tool", bundlePath: tree.path(".Trash/Tool.app"))
        tree.file("Library/Preferences/com.example.tool.plist", bytes: 100)
        tree.file("Library/Caches/com.example.tool/cache.db", bytes: 5000)
        tree.file("Library/Application Support/Tool/data.db", bytes: 5000)
        tree.file("Library/Application Support/Shared/x", bytes: 10)
        let other = applicationsIdentity("com.example.toolpro", name: "Tool Pro", bundlePath: "/Applications/Tool Pro.app")
        let roots = ApplicationsLeftoverCatalog.roots(home: tree.root).filter { !$0.isSystemDomain }
        let candidates = ApplicationsLeftoverMatcher(roots: roots).candidates(for: identity, others: [other])
        let removed = ApplicationsRemovedApp(bundleID: "com.example.tool", name: "Tool", trashedPath: identity.bundlePath,
                                             identity: identity)
        let groups = ApplicationsRemovedAppPlan.groups([(app: removed, candidates: candidates, inTrash: true)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].id.hasPrefix(ApplicationsRemovedAppPlan.groupPrefix))
        let names = Set(groups[0].items.map(\.title))
        XCTAssertTrue(names.contains("com.example.tool.plist"))
        XCTAssertTrue(names.contains("com.example.tool"))
        XCTAssertFalse(names.contains("Shared"))
        XCTAssertTrue(groups[0].items.allSatisfy { $0.metadata[ApplicationsMeta.removedApp] == "com.example.tool" })
        XCTAssertFalse(groups.selectedItems.isEmpty, "files that clearly belong to the trashed app are ticked")
        XCTAssertTrue(groups.selectedItems.allSatisfy { $0.safety == .safe })
        let selectedKinds = Set(groups.selectedItems.compactMap { $0.metadata[ApplicationsMeta.kind] })
        XCTAssertFalse(selectedKinds.contains(ApplicationsComponentKind.applicationSupport.rawValue),
                       "data folders are never pre-selected")
        XCTAssertTrue(selectedKinds.contains(ApplicationsComponentKind.preferences.rawValue))

        let orphan = ScanGroup(id: "o", title: "Tool", items: [
            ScanItem.file(URL(fileURLWithPath: tree.path("Library/Preferences/com.example.tool.plist")), size: 1, safety: .review),
            ScanItem.file(URL(fileURLWithPath: tree.path("Library/Preferences/com.example.gone.plist")), size: 1, safety: .review),
        ])
        let remaining = ApplicationsRemovedAppPlan.excluding(Set(groups.allItems.compactMap { $0.url?.path }), from: [orphan])
        XCTAssertEqual(remaining.allItems.map(\.title), ["com.example.gone.plist"], "a file is listed once")
    }
}

// MARK: - Suspicious apps

final class ApplicationsSuspiciousTests: XCTestCase {
    private func app(_ signature: ApplicationsCodeSignature, quarantined: Bool = false, system: Bool = false,
                     source: ApplicationsAppSource = .other) -> ApplicationsAppInfo {
        ApplicationsAppInfo(path: "/Applications/X.app", name: "X", bundleID: "com.x", source: source, isSystem: system,
                            codeSignature: signature, isQuarantined: quarantined)
    }

    func testReasons() {
        XCTAssertTrue(ApplicationsSuspicion.reasons(app(.identified)).isEmpty)
        XCTAssertTrue(ApplicationsSuspicion.reasons(app(.unknown)).isEmpty)
        XCTAssertTrue(ApplicationsSuspicion.reasons(app(.identified, quarantined: true)).isEmpty,
                      "a signed app waiting for its first launch is fine")
        XCTAssertEqual(ApplicationsSuspicion.reasons(app(.broken)).count, 1)
        XCTAssertEqual(ApplicationsSuspicion.reasons(app(.adHoc, quarantined: true)).count, 2)
        XCTAssertTrue(ApplicationsSuspicion.reasons(app(.unsigned, system: true)).isEmpty, "macOS's own apps never")
    }

    func testFacet() {
        let apps = [app(.identified), app(.unsigned), app(.broken, system: true)]
        let suspicious = ApplicationsAppFilter.apps(apps, facet: .suspicious, unusedDays: 180)
        XCTAssertEqual(suspicious.count, 1)
        XCTAssertEqual(suspicious.first?.codeSignature, .unsigned)
        XCTAssertEqual(ApplicationsAppFacet.suspicious.title, "Suspicious")
    }
}
