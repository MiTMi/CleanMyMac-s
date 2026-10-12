import Foundation
import XCTest
@testable import SpruceCore

final class CleanupProgressTests: XCTestCase {

    private func item(_ id: String, size: Int64) -> ScanItem {
        ScanItem(id: id, title: id, size: size, safety: .safe)
    }

    func testTallyTracksEachSectionFromWaitingToFound() throws {
        let scanner = CleanupScanner(context: CleanupContext(home: "/Users/test"))
        let rules = scanner.rules(for: [.systemJunk, .trashBins])
        var tally = CleanupScanTally(rules: rules, sections: [.trashBins, .systemJunk])

        XCTAssertEqual(tally.sections.map(\.section), [.systemJunk, .trashBins], "display order")
        XCTAssertEqual(tally.progress(for: .systemJunk)?.status, .waiting)
        XCTAssertNil(tally.progress(for: .mailAttachments))
        XCTAssertEqual(tally.fraction, 0)

        let trashRules = rules.filter { $0.category.section == .trashBins }
        XCTAssertFalse(trashRules.isEmpty)
        let first = try XCTUnwrap(trashRules.first)
        tally.start(first)
        tally.start(first)   // idempotent
        XCTAssertEqual(tally.progress(for: .trashBins)?.startedRules, 1)
        XCTAssertEqual(tally.progress(for: .trashBins)?.status, .running)

        for (index, rule) in trashRules.enumerated() {
            tally.start(rule)
            let items = index == 0 ? [item("a", size: 1_000), item("b", size: 500)] : []
            let result = CleanupRuleResult(ruleID: rule.id, category: rule.category, items: items)
            tally.finish(result)
            tally.finish(result)   // idempotent
        }
        let trash = try XCTUnwrap(tally.progress(for: .trashBins))
        XCTAssertTrue(trash.isFinished)
        XCTAssertEqual(trash.status, .found(1_500))
        XCTAssertEqual(trash.itemsFound, 2)
        XCTAssertEqual(tally.bytesFound, 1_500)
        XCTAssertEqual(tally.progress(for: .systemJunk)?.status, .waiting)

        let total = Double(rules.count)
        XCTAssertEqual(tally.fraction ?? -1, Double(trashRules.count) / total, accuracy: 0.0001)
    }

    func testUnavailableAndExcludedSections() {
        let mailRules = CleanupCatalog.rules.filter { $0.category.section == .mailAttachments }
        var tally = CleanupScanTally(rules: mailRules, sections: [.mailAttachments, .trashBins])
        XCTAssertEqual(tally.progress(for: .trashBins)?.status, .excluded, "no rules → excluded in Settings")

        for rule in mailRules {
            tally.start(rule)
            tally.finish(CleanupRuleResult(ruleID: rule.id, category: rule.category,
                                           unavailable: CleanupUnavailable(category: rule.category, reason: .fullDiskAccess)))
        }
        XCTAssertEqual(tally.progress(for: .mailAttachments)?.status, .unavailable("Needs Full Disk Access"))

        var denied = CleanupScanTally(rules: mailRules, sections: [.mailAttachments])
        for rule in mailRules {
            denied.finish(CleanupRuleResult(ruleID: rule.id, category: rule.category,
                                            unavailable: CleanupUnavailable(category: rule.category, reason: .permissionDenied)))
        }
        XCTAssertEqual(denied.progress(for: .mailAttachments)?.status, .unavailable("macOS denied access"))

        var clean = CleanupScanTally(rules: mailRules, sections: [.mailAttachments])
        for rule in mailRules {
            clean.finish(CleanupRuleResult(ruleID: rule.id, category: rule.category))
        }
        XCTAssertEqual(clean.progress(for: .mailAttachments)?.status, .nothingFound)
    }

    func testCatalogNeverOffersAppBundleTrimming() {
        let ids = CleanupCatalog.categories.map(\.id)
        XCTAssertFalse(ids.contains { $0.localizedCaseInsensitiveContains("language") })
        XCTAssertFalse(ids.contains { $0.localizedCaseInsensitiveContains("universal") })
        for rule in CleanupCatalog.rules {
            XCTAssertFalse(rule.paths.contains { $0.hasSuffix(".lproj") || $0.contains(".lproj/") }, rule.id)
        }
    }
}
