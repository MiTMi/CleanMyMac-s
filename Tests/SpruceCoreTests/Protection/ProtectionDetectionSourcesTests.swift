import Foundation
import XCTest
@testable import SpruceCore

final class ProtectionDetectionSourcesTests: XCTestCase {
    private var root: String!

    override func setUp() {
        super.setUp()
        let base = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        root = (base as NSString).appendingPathComponent("spruce-detection-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: root)
        super.tearDown()
    }

    /// Rules in XProtect's style that only match a made-up marker.
    static let rules = #"""
    private rule Macho
    {
        condition:
            uint32(0) == 0xfeedfacf or uint32(0) == 0xcffaedfe
    }

    rule XProtect_MACOS_SPRUCE_TEST
    {
        meta:
            description = "MACOS.SPRUCE.TEST"
        strings:
            $a = "spruce-detection-test-marker"
        condition:
            Macho and $a
    }

    rule Uses_Regex
    {
        strings:
            $r = /spruce[0-9]+/
        condition:
            $r
    }
    """#

    /// Mimics an XProtect bundle: the rules and an Info.plist with a version.
    @discardableResult
    private func xprotectBundle(_ folder: String, rules: String, version: String?) -> String {
        let contents = (root as NSString).appendingPathComponent(folder + "/XProtect.bundle/Contents")
        try? FileManager.default.createDirectory(atPath: contents + "/Resources", withIntermediateDirectories: true)
        if let version {
            let plist = try! PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version],
                                                            format: .xml, options: 0)
            _ = FileManager.default.createFile(atPath: contents + "/Info.plist", contents: plist)
        }
        let path = contents + "/Resources/XProtect.yara"
        _ = FileManager.default.createFile(atPath: path, contents: Data(rules.utf8))
        return path
    }

    private var newPath: String { root + "/new/XProtect.bundle/Contents/Resources/XProtect.yara" }
    private var oldPath: String { root + "/old/XProtect.bundle/Contents/Resources/XProtect.yara" }

    // MARK: Apple's rules

    func testAppleRulesPreferTheNewLocationAndReadTheBundleVersion() {
        xprotectBundle("new", rules: Self.rules, version: "5310")
        xprotectBundle("old", rules: Self.rules, version: "5297")
        let loader = ProtectionAppleRulesLoader(paths: [newPath, oldPath])
        let (source, status) = loader.load()
        XCTAssertEqual(source?.location, newPath)
        XCTAssertEqual(source?.name, "Apple XProtect")
        XCTAssertEqual(status.path, newPath)
        XCTAssertEqual(status.version, "5310")
        XCTAssertEqual(status.activeRuleCount, 1, "The private rule doesn't count")
        XCTAssertEqual(status.skippedRuleCount, 1, "The regex rule is skipped")
        XCTAssertTrue(status.isAvailable)
        XCTAssertNil(status.unavailableReason)
        XCTAssertEqual(status.summary, "Version 5310 · 1 rule")
        XCTAssertFalse(status.notes.isEmpty)
    }

    func testAppleRulesFallBackToTheOldLocation() {
        xprotectBundle("old", rules: Self.rules, version: "5297")
        let loader = ProtectionAppleRulesLoader(paths: [newPath, oldPath])
        XCTAssertEqual(loader.load().source?.location, oldPath)

        // A new copy without usable rules doesn't hide the old one.
        xprotectBundle("new", rules: "rule Broken { condition: pe.is_dll() }", version: "6000")
        let (source, status) = loader.load()
        XCTAssertEqual(source?.location, oldPath)
        XCTAssertEqual(status.version, "5297")
    }

    func testAppleRulesAreCompiledOnceUntilTheFileChanges() throws {
        let path = xprotectBundle("new", rules: Self.rules, version: "1")
        let loader = ProtectionAppleRulesLoader(paths: [path])
        _ = loader.load()
        _ = loader.load()
        XCTAssertEqual(loader.status.activeRuleCount, 1)
        XCTAssertEqual(loader.compiles, 1)

        let more = Self.rules + "\nrule Another { strings: $a = \"spruce-detection-other\" condition: $a }\n"
        try Data(more.utf8).write(to: URL(fileURLWithPath: path))
        let (_, status) = loader.load()
        XCTAssertEqual(loader.compiles, 2)
        XCTAssertEqual(status.activeRuleCount, 2)
    }

    func testAppleRulesReportWhyTheyAreUnavailable() {
        let missing = ProtectionAppleRulesLoader(paths: [newPath, oldPath]).load()
        XCTAssertNil(missing.source)
        XCTAssertFalse(missing.status.isAvailable)
        XCTAssertEqual(missing.status.unavailableReason, ProtectionAppleRulesStatus.notFound)
        XCTAssertEqual(missing.status.summary, ProtectionAppleRulesStatus.notFound)

        xprotectBundle("new", rules: "rule Only_PE { condition: pe.number_of_sections > 1 }", version: nil)
        let unusable = ProtectionAppleRulesLoader(paths: [newPath, oldPath]).load()
        XCTAssertNil(unusable.source)
        XCTAssertEqual(unusable.status.path, newPath)
        XCTAssertEqual(unusable.status.unavailableReason, ProtectionAppleRulesStatus.noUsableRules)
        XCTAssertEqual(unusable.status.skippedRuleCount, 1)
    }

    // MARK: Threat list cache

    private var cache: ProtectionThreatFeedCache {
        ProtectionThreatFeedCache(directory: URL(fileURLWithPath: root + "/ThreatFeed", isDirectory: true))
    }

    private func feedJSON(version: Int, label: String = "com.sprucetestfamily.agent") -> Data {
        Data("""
        {"format": 1, "version": \(version), "updated": "2026-10-13",
         "families": [{"id": "sprucetestfamily", "name": "Spruce Test Family", "category": "adware", "severity": "high"}],
         "indicators": [{"kind": "launchLabel", "pattern": "\(label)", "family": "sprucetestfamily"}]}
        """.utf8)
    }

    private let feedRules = Data("""
    rule Spruce_List_Test { meta: family = "sprucetestfamily" strings: $a = "spruce-list-test-marker" condition: $a }
    """.utf8)

    func testStoringADownloadedListAndReadingItBack() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let (snapshot, result) = cache.apply(feed: .downloaded(feedJSON(version: 3), etag: "\"f1\""),
                                             rules: .downloaded(feedRules, etag: "\"r1\""), now: now)
        XCTAssertEqual(result.outcome, .updated)
        XCTAssertEqual(result.message, "The threat list was updated to version 3.")
        XCTAssertEqual(snapshot.feed.version, 3)
        XCTAssertEqual(snapshot.indicatorCount, 1)
        XCTAssertEqual(snapshot.catalog.matchLabel("com.sprucetestfamily.agent")?.family.name, "Spruce Test Family")
        XCTAssertEqual(snapshot.ruleSources.first?.activeRuleCount, 1)
        XCTAssertEqual(snapshot.ruleSources.first?.kind, .threatList)
        XCTAssertEqual(result.status.lastChecked, now)
        XCTAssertEqual(result.status.lastUpdated, now)
        XCTAssertEqual(result.status.feedETag, "\"f1\"")
        XCTAssertEqual(result.status.rulesETag, "\"r1\"")
        XCTAssertNil(result.status.lastError)
        XCTAssertEqual(result.status.summary, "Version 3 · 1 indicator · 1 rule")

        let reloaded = cache.load()
        XCTAssertEqual(reloaded.feed.version, 3)
        XCTAssertEqual(reloaded.indicatorCount, 1)
        XCTAssertEqual(reloaded.ruleSources.count, 1)
        XCTAssertEqual(reloaded.status, result.status)
        XCTAssertEqual(cache.conditionalETags(for: reloaded.status).feed, "\"f1\"")
        XCTAssertEqual(cache.conditionalETags(for: reloaded.status).rules, "\"r1\"")
        XCTAssertFalse(reloaded.status.isCheckDue(now: now.addingTimeInterval(3_600)))
        XCTAssertTrue(reloaded.status.isCheckDue(now: now.addingTimeInterval(86_400)))
    }

    func testNotModifiedAndFailedChecksKeepTheCachedList() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = cache.apply(feed: .downloaded(feedJSON(version: 3), etag: "\"f1\""), rules: .downloaded(feedRules, etag: nil), now: start)

        let later = start.addingTimeInterval(90_000)
        let (same, upToDate) = cache.apply(feed: .notModified, rules: .notModified, now: later)
        XCTAssertEqual(upToDate.outcome, .upToDate)
        XCTAssertEqual(same.feed.version, 3)
        XCTAssertEqual(upToDate.status.lastChecked, later)
        XCTAssertEqual(upToDate.status.lastUpdated, start)

        let offline = "Spruce couldn't reach the threat list."
        let (kept, failed) = cache.apply(feed: .failed(offline), rules: .failed(offline), now: later.addingTimeInterval(90_000))
        XCTAssertEqual(failed.outcome, .failed(offline), "The same problem is reported once")
        XCTAssertEqual(kept.feed.version, 3)
        XCTAssertEqual(kept.ruleSources.count, 1)
        XCTAssertEqual(failed.status.lastError, offline)
        XCTAssertEqual(failed.status.version, 3)

        // Sending the same files again only refreshes the validators.
        let (_, again) = cache.apply(feed: .downloaded(feedJSON(version: 3), etag: "\"f2\""), rules: .skipped,
                                     now: later.addingTimeInterval(200_000))
        XCTAssertEqual(again.outcome, .upToDate)
        XCTAssertEqual(again.status.feedETag, "\"f2\"")
        XCTAssertNil(again.status.lastError)
    }

    func testBadOrOlderDownloadsAreRefusedWithoutLosingTheCache() {
        _ = cache.apply(feed: .downloaded(feedJSON(version: 5), etag: nil), rules: .skipped)

        let (afterOlder, older) = cache.apply(feed: .downloaded(feedJSON(version: 4, label: "com.sprucetestfamily.other"), etag: nil),
                                              rules: .skipped)
        XCTAssertEqual(afterOlder.feed.version, 5)
        guard case .failed(let message) = older.outcome else { return XCTFail("An older list must not replace the cached one") }
        XCTAssertTrue(message.contains("older"))

        let (afterJunk, junk) = cache.apply(feed: .downloaded(Data("<html>".utf8), etag: nil),
                                            rules: .downloaded(Data(count: ProtectionThreatFeed.maxRulesBytes + 1), etag: nil))
        XCTAssertEqual(afterJunk.feed.version, 5)
        guard case .failed = junk.outcome else { return XCTFail("Unreadable files must be refused") }
        XCTAssertNotNil(junk.status.lastError)

        // A good rules file is kept even when the feed next to it is bad.
        let (mixed, mixedResult) = cache.apply(feed: .downloaded(Data("{}".utf8), etag: nil), rules: .downloaded(feedRules, etag: nil))
        XCTAssertEqual(mixedResult.outcome, .updated)
        XCTAssertEqual(mixed.feed.version, 5)
        XCTAssertEqual(mixed.ruleSources.count, 1)
        XCTAssertNotNil(mixedResult.status.lastError)
    }

    func testDamagedCacheFilesAreIgnored() throws {
        _ = cache.apply(feed: .downloaded(feedJSON(version: 2), etag: "\"f\""), rules: .skipped)
        try Data("not json".utf8).write(to: cache.feedFile)
        let snapshot = cache.load()
        XCTAssertTrue(snapshot.feed.isEmpty)
        XCTAssertEqual(snapshot.indicatorCount, 0)
        XCTAssertNil(cache.conditionalETags(for: snapshot.status).rules, "No rules file, so no ETag to offer")

        cache.clear()
        XCTAssertNil(cache.conditionalETags(for: snapshot.status).feed, "No feed file, so no ETag to offer")
        XCTAssertEqual(cache.load().status, ProtectionThreatFeedStatus())
        XCTAssertTrue(ProtectionThreatListSnapshot.empty.ruleSources.isEmpty)
    }

    func testCheckResultMessages() {
        var status = ProtectionThreatFeedStatus()
        XCTAssertEqual(ProtectionThreatFeedCheckResult(outcome: .updated, status: status).message, "The threat list was updated.")
        status.version = 4
        XCTAssertEqual(ProtectionThreatFeedCheckResult(outcome: .updated, status: status).message,
                       "The threat list was updated to version 4.")
        XCTAssertEqual(ProtectionThreatFeedCheckResult(outcome: .upToDate, status: status).message, "The threat list is up to date.")
        XCTAssertEqual(ProtectionThreatFeedCheckResult(outcome: .failed("Nope."), status: status).message, "Nope.")
        XCTAssertFalse(ProtectionThreatFeedCheckResult(outcome: .notDue, status: status).message.isEmpty)
        XCTAssertFalse(ProtectionThreatFeedCheckResult(outcome: .turnedOff, status: status).message.isEmpty)
    }

    // MARK: Settings

    func testSettingsDecodeTheDetectionTogglesWithDefaults() throws {
        let old = try JSONDecoder().decode(SpruceSettings.self, from: Data(#"{"scanDepth": "deep"}"#.utf8))
        XCTAssertTrue(old.threatFeedEnabled)
        XCTAssertTrue(old.virusTotalAutoCheck)
        XCTAssertEqual(old.scanDepth, "deep")

        let off = try JSONDecoder().decode(SpruceSettings.self, from: Data(#"{"threatFeedEnabled": false, "virusTotalAutoCheck": false}"#.utf8))
        XCTAssertFalse(off.threatFeedEnabled)
        XCTAssertFalse(off.virusTotalAutoCheck)

        let wrongType = try JSONDecoder().decode(SpruceSettings.self, from: Data(#"{"threatFeedEnabled": "yes"}"#.utf8))
        XCTAssertTrue(wrongType.threatFeedEnabled)

        var settings = SpruceSettings()
        settings.virusTotalAutoCheck = false
        let encoded = try JSONEncoder().encode(settings)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(text.contains("virusTotalAutoCheck"))
        XCTAssertFalse(text.lowercased().contains("apikey"), "The VirusTotal key never goes into settings")
        XCTAssertEqual(try JSONDecoder().decode(SpruceSettings.self, from: encoded), settings)
    }
}
