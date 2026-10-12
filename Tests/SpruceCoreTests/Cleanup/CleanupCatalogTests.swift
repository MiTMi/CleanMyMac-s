import Foundation
import XCTest
@testable import SpruceCore

final class CleanupCatalogTests: XCTestCase {

    func testCategoriesAreUniqueAndCoverEveryRule() {
        let ids = CleanupCatalog.categories.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(ids.contains("systemJunk.userCaches"))
        XCTAssertTrue(ids.contains("mailAttachments"))
        XCTAssertTrue(ids.contains("trashBins"))
        for rule in CleanupCatalog.rules {
            XCTAssertTrue(ids.contains(rule.category.rawValue), rule.id)
        }
        let ruleIDs = CleanupCatalog.rules.map(\.id)
        XCTAssertEqual(ruleIDs.count, Set(ruleIDs).count, "rule ids must be unique")
    }

    func testToolIdentifiersMapToSections() {
        XCTAssertEqual(CleanupSection(toolID: "cleanup.systemJunk"), .systemJunk)
        XCTAssertEqual(CleanupSection(toolID: "cleanup.mailAttachments"), .mailAttachments)
        XCTAssertEqual(CleanupSection(toolID: "cleanup.trash"), .trashBins)
        XCTAssertNil(CleanupSection(toolID: "clutter.duplicates"))
    }

    func testSafetyInvariants() {
        for rule in CleanupCatalog.rules {
            if rule.safety != .safe { XCTAssertFalse(rule.defaultSelected, "\(rule.id) must not be pre-selected") }
            if rule.category == .iosBackups { XCTAssertEqual(rule.deletion, .trash) }
            XCTAssertNotEqual(rule.deletion, .custom, "\(rule.id): Cleanup only trashes or removes")
            XCTAssertFalse(rule.paths.contains { $0.contains(".app/") }, "\(rule.id) must not reach inside app bundles")
        }
    }

    private func sample(_ component: String) -> String {
        component.replacingOccurrences(of: "*", with: "sample").replacingOccurrences(of: "?", with: "x")
    }

    /// Every rule must produce targets that PathGuard accepts with the rule's deletion
    /// method (and the extra zones the rule declares), so the scanner never offers
    /// something FileRemover would refuse.
    func testEveryRuleTargetPassesPathGuard() {
        let home = "/Users/test"
        let context = CleanupContext(home: home, userTempDir: "/private/var/folders/ab/xyz/T",
                                     userCacheDir: "/private/var/folders/ab/xyz/C")
        for rule in CleanupCatalog.rules {
            if rule.analyzer.producesInsightsOnly || rule.analyzer == .externalTrash || rule.analyzer == .mailStored {
                continue
            }
            for raw in rule.paths {
                guard let absolute = CleanupScanner.resolveToken(raw, context: context) else {
                    XCTFail("\(rule.id): unresolved \(raw)")
                    continue
                }
                let concrete = "/" + CleanupPaths.components(absolute).map(sample).joined(separator: "/")
                let target: String
                let zone: String
                switch rule.target {
                case .each:
                    target = concrete
                    zone = (concrete as NSString).deletingLastPathComponent
                case .contents, .files:
                    target = concrete + "/child"
                    zone = concrete
                case .findFiles:
                    let name = sample(rule.namePatterns.first ?? "file")
                    target = concrete + "/sub/" + name
                    zone = concrete + "/sub"
                }
                let guardian = PathGuard(home: home, extraPermanentZones: rule.addsPermanentZone ? [zone] : [])
                let options: PathGuard.Options = rule.analyzer == .launchAgent ? .allowLaunchItems : []
                let verdict = guardian.check(target, method: rule.deletion, options: options)
                XCTAssertTrue(verdict.isAllowed, "\(rule.id): \(target) refused — \(verdict.reason ?? "")")
                if rule.addsPermanentZone {
                    XCTAssertTrue(CleanupCatalog.isDeclaredZone(zone, rule: rule, context: context),
                                  "\(rule.id): zone \(zone) not recognised")
                }
            }
        }
    }

    func testZonesMustBelongToTheirRule() {
        let context = CleanupContext(home: "/Users/test")
        let vscode = CleanupCatalog.rule(id: "dev.vscode")!
        XCTAssertTrue(CleanupCatalog.isDeclaredZone("/Users/test/Library/Application Support/Code/Cache",
                                                    rule: vscode, context: context))
        XCTAssertFalse(CleanupCatalog.isDeclaredZone("/Users/test/Documents", rule: vscode, context: context))
        XCTAssertFalse(CleanupCatalog.isDeclaredZone("/Users/test/Library/Application Support",
                                                     rule: vscode, context: context))
        let userCaches = CleanupCatalog.rule(id: "caches.user")!
        XCTAssertFalse(CleanupCatalog.isDeclaredZone("/Users/test/Library/Caches/x", rule: userCaches, context: context),
                       "rules without extra zones never declare one")
        let external = CleanupCatalog.rule(id: "trash.external")!
        let withVolume = CleanupContext(home: "/Users/test", uid: 501,
                                        externalVolumes: [CleanupVolume(path: "/Volumes/USB", name: "USB")])
        XCTAssertTrue(CleanupCatalog.isDeclaredZone("/Volumes/USB/.Trashes/501", rule: external, context: withVolume))
        XCTAssertFalse(CleanupCatalog.isDeclaredZone("/Volumes/USB/.Trashes/502", rule: external, context: withVolume))
        XCTAssertFalse(CleanupCatalog.isDeclaredZone("/Volumes/USB", rule: external, context: withVolume))
    }

    func testPathHelpers() {
        XCTAssertEqual(CleanupPaths.familyKey("Cache.db-wal"), "Cache.db")
        XCTAssertEqual(CleanupPaths.familyKey("Cache.db"), "Cache.db")
        XCTAssertEqual(CleanupPaths.versionKey("iPhone15,2 17.5.1 (21F90)"), [17, 5, 1])
        XCTAssertEqual(CleanupPaths.versionKey("16.4 (20E247)"), [16, 4])
        XCTAssertNil(CleanupPaths.versionKey("Latest"))
        XCTAssertTrue(CleanupPaths.versionLess([16, 4], [17, 0]))
        XCTAssertFalse(CleanupPaths.versionLess([17, 0], [17]))
        XCTAssertTrue(CleanupOwnership.looksLikeBundleID("com.google.Chrome"))
        XCTAssertTrue(CleanupOwnership.looksLikeBundleID("md.obsidian"))
        XCTAssertFalse(CleanupOwnership.looksLikeBundleID("Homebrew"))
        XCTAssertFalse(CleanupOwnership.looksLikeBundleID("Google Chrome"))
        XCTAssertEqual(CleanupOwnership.owner(forName: "Google"), "com.google.Chrome")
        XCTAssertEqual(CleanupOwnership.owner(forGroupContainer: "UBF8T346G9.com.microsoft.teams"), "com.microsoft.teams")
        XCTAssertEqual(CleanupOwnership.owner(forGroupContainer: "group.com.example.shared"), "com.example.shared")
        XCTAssertEqual(CleanupOwnership.preferenceDomain(fileName: "com.apple.screensaver.0123456789AB.plist"),
                       "com.apple.screensaver")
        XCTAssertTrue(CleanupOwnership.matches(owner: "com.example.app.helper", bundleID: "com.example.app"))
        XCTAssertFalse(CleanupOwnership.matches(owner: "com.example.application", bundleID: "com.example.app"))
        XCTAssertFalse(CleanupOwnership.matches(owner: "com", bundleID: "com.example.app"))
    }
}
