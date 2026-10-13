import Foundation
import XCTest
@testable import SpruceCore

final class ApplicationsMachOTests: XCTestCase {

    private func bytes(_ values: [UInt32], bigEndian: Bool) -> Data {
        var data = Data()
        for v in values {
            let ordered = bigEndian ? v.bigEndian : v.littleEndian
            withUnsafeBytes(of: ordered) { data.append(contentsOf: $0) }
        }
        return data
    }

    func testThinBinaries() {
        let arm = bytes([0xFEED_FACF, 0x0100_000C, 0, 2], bigEndian: false)
        XCTAssertEqual(ApplicationsMachO.cpus(fromHeader: arm), [.arm64])
        let intel = bytes([0xFEED_FACF, 0x0100_0007, 3, 2], bigEndian: false)
        XCTAssertEqual(ApplicationsMachO.cpus(fromHeader: intel), [.x86_64])
        XCTAssertEqual(ApplicationsArchitecture.from([.x86_64]), .intel)
        XCTAssertEqual(ApplicationsArchitecture.from([.arm64]), .appleSilicon)
    }

    func testUniversalBinary() {
        // fat header + two fat_arch records (cputype, subtype, offset, size, align)
        let fat = bytes([0xCAFE_BABE, 2, 0x0100_0007, 3, 0x4000, 100, 14, 0x0100_000C, 0, 0x8000, 100, 14], bigEndian: true)
        let cpus = ApplicationsMachO.cpus(fromHeader: fat)
        XCTAssertEqual(cpus, [.x86_64, .arm64])
        XCTAssertEqual(ApplicationsArchitecture.from(cpus), .universal)
    }

    func testRejectsJavaClassesAndGarbage() {
        let javaClass = bytes([0xCAFE_BABE, 0x0000_0034], bigEndian: true)
        XCTAssertEqual(ApplicationsMachO.cpus(fromHeader: javaClass), [])
        XCTAssertEqual(ApplicationsMachO.cpus(fromHeader: Data("#!/bin/sh\necho hi\n".utf8)), [])
        XCTAssertEqual(ApplicationsArchitecture.from([]), .unknown)
        XCTAssertEqual(ApplicationsArchitecture.from([.i386]), .legacy32)
    }
}

final class ApplicationsModelTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testUnusedRule() {
        let old = now.addingTimeInterval(-200 * 86_400)
        let recent = now.addingTimeInterval(-10 * 86_400)
        XCTAssertTrue(ApplicationsUnusedRule.isUnused(lastUsed: old, dateAdded: nil, now: now, days: 180))
        XCTAssertFalse(ApplicationsUnusedRule.isUnused(lastUsed: recent, dateAdded: old, now: now, days: 180))
        XCTAssertTrue(ApplicationsUnusedRule.isUnused(lastUsed: nil, dateAdded: old, now: now, days: 180), "never opened")
        XCTAssertFalse(ApplicationsUnusedRule.isUnused(lastUsed: nil, dateAdded: nil, now: now, days: 180))
        var app = ApplicationsAppInfo(path: "/Applications/A.app", name: "A", bundleID: "com.a.a", lastUsed: old)
        XCTAssertTrue(ApplicationsUnusedRule.isUnused(app, now: now, days: 180))
        app.isRunning = true
        XCTAssertFalse(ApplicationsUnusedRule.isUnused(app, now: now, days: 180))
    }

    func testVendorNames() {
        XCTAssertEqual(ApplicationsVendorName.derive(certificateSummary: "Developer ID Application: Google LLC (EQHXZ8M8AV)",
                                                     bundleID: "com.google.Chrome"), "Google")
        XCTAssertEqual(ApplicationsVendorName.derive(certificateSummary: "Developer ID Application: Rogue Amoeba Software, Inc. (7266XEXAPM)",
                                                     bundleID: "com.rogueamoeba.audiohijack"), "Rogue Amoeba Software")
        XCTAssertEqual(ApplicationsVendorName.derive(certificateSummary: nil, bundleID: "org.mozilla.firefox"), "Mozilla")
        XCTAssertEqual(ApplicationsVendorName.derive(certificateSummary: nil, bundleID: "com.knollsoft.Rectangle"), "Knollsoft")
        XCTAssertEqual(ApplicationsVendorName.derive(certificateSummary: "Apple Mac OS Application Signing",
                                                     bundleID: "com.apple.dt.Xcode"), "Apple")
        XCTAssertEqual(ApplicationsVendorName.derive(certificateSummary: nil, bundleID: "Weird"), "Other")
    }

    func testFacetsAndVendors() {
        let old = now.addingTimeInterval(-400 * 86_400)
        let apps = [
            ApplicationsAppInfo(path: "/Applications/Chrome.app", name: "Chrome", bundleID: "com.google.Chrome", vendor: "Google",
                                architecture: .universal, size: 500),
            ApplicationsAppInfo(path: "/Applications/Drive.app", name: "Drive", bundleID: "com.google.drive", vendor: "Google",
                                architecture: .intel, source: .homebrew, size: 300, lastUsed: old),
            ApplicationsAppInfo(path: "/Applications/Pages.app", name: "Pages", bundleID: "com.apple.iWork.Pages", vendor: "Apple",
                                architecture: .appleSilicon, source: .appStore, size: 900),
            ApplicationsAppInfo(path: "/System/Applications/Mail.app", name: "Mail", bundleID: "com.apple.mail", vendor: "Apple",
                                isSystem: true),
        ]
        func ids(_ facet: ApplicationsAppFacet, selected: Set<String> = []) -> [String] {
            ApplicationsAppFilter.apps(apps, facet: facet, unusedDays: 180, selected: selected, now: now).map(\.name)
        }
        XCTAssertEqual(ids(.all), ["Chrome", "Drive", "Pages"])
        XCTAssertEqual(ids(.system), ["Mail"])
        XCTAssertEqual(ids(.unused), ["Drive"])
        XCTAssertEqual(ids(.intelOnly), ["Drive"])
        XCTAssertEqual(ids(.appStore), ["Pages"])
        XCTAssertEqual(ids(.homebrew), ["Drive"])
        XCTAssertEqual(ids(.vendor("Google")), ["Chrome", "Drive"])
        XCTAssertEqual(ids(.selected, selected: ["/Applications/Pages.app", "/System/Applications/Mail.app"]), ["Pages"])
        XCTAssertEqual(ApplicationsAppFilter.vendors(apps).map(\.name), ["Google"])
        XCTAssertEqual(ApplicationsAppFilter.sorted(apps, by: .size).first?.name, "Pages")
        XCTAssertEqual(ApplicationsAppFilter.search(apps, query: "goo").count, 2)
    }

    func testComponentChecklistModes() {
        let tree = ApplicationsTempTree()
        let appPath = tree.dir("Applications/Foo.app")
        let prefs = tree.file("Library/Preferences/com.foo.app.plist", bytes: 100)
        let agent = tree.file("Library/LaunchAgents/com.foo.app.helper.plist", bytes: 100)
        let shared = tree.dir("Library/Group Containers/group.foo")
        let app = ApplicationsAppInfo(path: appPath, name: "Foo", bundleID: "com.foo.app", size: 1000)
        let candidates = [
            ApplicationsLeftoverCandidate(path: prefs, kind: .preferences, confidence: .owned, reason: "Named after com.foo.app"),
            ApplicationsLeftoverCandidate(path: agent, kind: .launchItems, confidence: .owned, reason: "Named after com.foo.app"),
            ApplicationsLeftoverCandidate(path: shared, kind: .containers, confidence: .owned, reason: "Group", sharedWith: ["Bar"]),
        ]
        var groups = ApplicationsComponents.groups(app: app, candidates: candidates, inDock: true, mode: .uninstall)
        XCTAssertEqual(groups.first?.id, ApplicationsComponents.groupID(.application))
        let selectedNames = Set(groups.selectedItems.map(\.title))
        XCTAssertTrue(selectedNames.contains("Foo.app"))
        XCTAssertTrue(selectedNames.contains("com.foo.app.plist"))
        XCTAssertTrue(selectedNames.contains("com.foo.app.helper.plist"))
        XCTAssertFalse(selectedNames.contains("group.foo"), "shared items are never pre-selected")
        XCTAssertEqual(groups.selectedItems.filter { $0.deletion == .custom }.count, 1, "Dock icon")
        XCTAssertEqual(ApplicationsComponents.mode(of: groups), .uninstall)
        XCTAssertTrue(ApplicationsComponents.removesApp(groups.selectedItems))
        XCTAssertEqual(groups.allItems.first { $0.title == "com.foo.app.plist" }?.metadata["bundleID"], "com.foo.app")

        ApplicationsComponents.apply(mode: .reset, to: &groups)
        let resetNames = Set(groups.selectedItems.map(\.title))
        XCTAssertEqual(resetNames, ["com.foo.app.plist"], "reset keeps the app, its helpers and shared data")
        XCTAssertEqual(ApplicationsComponents.mode(of: groups), .reset)
        XCTAssertFalse(ApplicationsComponents.removesApp(groups.selectedItems))

        let sharedID = groups.allItems.first { $0.title == "group.foo" }!.id
        groups.setSelected(true, itemID: sharedID)
        XCTAssertNil(ApplicationsComponents.mode(of: groups), "a hand-made selection is custom")
    }

    func testCheckupTileAndReview() {
        let brew = ApplicationsUpdate(appPath: "/Applications/Firefox.app", bundleID: "org.mozilla.firefox", name: "Firefox",
                                      installedVersion: "120.0", availableVersion: "121.0", source: .homebrew, caskToken: "firefox")
        let store = ApplicationsUpdate(appPath: "/Applications/Pages.app", bundleID: "com.apple.iWork.Pages", name: "Pages",
                                       installedVersion: "13.0", availableVersion: "14.0", source: .appStore)
        let orphan = ScanGroup(id: "o", title: "Gone", items: [ScanItem(id: "/x", title: "x", size: 5_000_000, safety: .review)])
        let review = ApplicationsCheckupPlan.review(updates: [brew, store], orphanGroups: [orphan])
        XCTAssertEqual(review.count, 2)
        XCTAssertEqual(review[0].items.count, 1, "only unattended (Homebrew) updates can be run from Checkup")
        XCTAssertTrue(review.selectedItems.isEmpty, "nothing is pre-selected")
        XCTAssertEqual(review[0].items[0].deletion, .custom)

        let tile = ApplicationsCheckupPlan.tile(updates: [brew, store], updatesChecked: true, orphanGroups: [orphan])
        XCTAssertEqual(tile.headline, "2 updates")
        XCTAssertEqual(tile.status, .info)
        XCTAssertFalse(tile.isSelected)

        let leftoversOnly = ApplicationsCheckupPlan.tile(updates: [], updatesChecked: true, orphanGroups: [orphan])
        XCTAssertEqual(leftoversOnly.headline, "5 MB")
        let clear = ApplicationsCheckupPlan.tile(updates: [], updatesChecked: false, orphanGroups: [])
        XCTAssertEqual(clear.status, .clear)
    }
}
