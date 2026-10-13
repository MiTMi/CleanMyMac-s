import Foundation
import XCTest
@testable import SpruceCore

final class ProtectionThreatFeedTests: XCTestCase {
    /// An obviously made-up hash (tests never use real samples).
    static let fakeHash = String(repeating: "0123456789abcdef", count: 4)

    func feed(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> ProtectionThreatFeed {
        try ProtectionThreatFeed.parse(Data(json.utf8))
    }

    /// One-indicator feed for checking a single pattern.
    func verdict(_ kind: String, _ pattern: String, family: String = "adload") -> (accepted: Bool, reason: String?) {
        let entry: [String: Any] = ["kind": kind, "pattern": pattern, "family": family]
        let object: [String: Any] = ["format": 1, "version": 1, "indicators": [entry]]
        let data = try! JSONSerialization.data(withJSONObject: object)
        let parsed = try! ProtectionThreatFeed.parse(data)
        return (!parsed.indicators.isEmpty, parsed.rejected.first)
    }

    func testParsesAValidFeedAndMergesItWithTheBuiltInCatalog() throws {
        let parsed = try feed("""
        {
          "about": "ignored",
          "format": 1,
          "version": 7,
          "updated": "2026-10-13",
          "families": [
            {"id": "examplestealer", "name": "Example Stealer", "category": "stealer", "severity": "critical",
             "summary": "Steals browser passwords."},
            {"id": "exampleads", "name": "Example Ads", "category": "Adware", "severity": "HIGH"},
            {"id": "adload", "name": "Not Adload", "category": "pua", "severity": "low"}
          ],
          "indicators": [
            {"kind": "path", "pattern": "~/Library/LaunchAgents/com.examplestealer.agent.plist", "family": "examplestealer"},
            {"kind": "launchLabel", "pattern": "com.examplestealer.agent", "family": "examplestealer"},
            {"kind": "bundleID", "pattern": "com.exampleads.*", "family": "exampleads"},
            {"kind": "bundleName", "pattern": "Example Ads Helper.app", "family": "exampleads"},
            {"kind": "teamID", "pattern": "zzzzz99999", "family": "examplestealer"},
            {"kind": "sha256", "pattern": "\(Self.fakeHash.uppercased())", "family": "adload"},
            {"kind": "pathRegex", "pattern": "^~/Library/Application Support/\\\\.exst[0-9]{4}(/|$)", "family": "examplestealer",
             "executableOnly": true},
            {"kind": "launchLabel", "pattern": "com.xdivcmp", "family": "amos"},
            {"kind": "launchLabel", "pattern": "com.examplestealer.agent", "family": "exampleads"},
            {"kind": "launchLabel", "pattern": "com.nobody.agent", "family": "missing"}
          ]
        }
        """)
        XCTAssertEqual(parsed.format, 1)
        XCTAssertEqual(parsed.version, 7)
        XCTAssertEqual(parsed.updated, ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z"))
        XCTAssertEqual(parsed.families.map(\.id), ["examplestealer", "exampleads"])
        XCTAssertEqual(parsed.families[1].category, .adware)
        XCTAssertEqual(parsed.families[1].severity, .high)
        XCTAssertEqual(parsed.families[1].summary, "Listed in Spruce's downloaded threat list.")
        XCTAssertEqual(parsed.indicators.count, 7)
        XCTAssertTrue(parsed.indicators.allSatisfy { $0.origin == .threatList })
        XCTAssertEqual(parsed.duplicateCount, 2, "The built-in AMOS label and the repeated label are skipped")
        XCTAssertEqual(parsed.rejected.count, 2)
        XCTAssertTrue(parsed.rejected.contains { $0.contains("\"adload\"") && $0.contains("built-in one is kept") })
        XCTAssertTrue(parsed.rejected.contains { $0.contains("\"missing\" isn't defined") })

        let catalog = ProtectionThreatCatalog.standard.merging(parsed)
        XCTAssertEqual(catalog.family(id: "adload")?.name, "Adload", "Built-in families win")
        XCTAssertEqual(catalog.families.count, ProtectionThreatCatalog.standard.families.count + 2)
        XCTAssertEqual(catalog.threatListIndicatorCount, 7)
        XCTAssertEqual(catalog.matchLabel("com.examplestealer.agent")?.family.name, "Example Stealer")
        XCTAssertEqual(catalog.matchBundleID("com.exampleads.helper")?.family.id, "exampleads")
        XCTAssertEqual(catalog.matchBundleName("Example Ads Helper.app")?.family.id, "exampleads")
        XCTAssertEqual(catalog.matchTeamID("ZZZZZ99999")?.indicator.origin, .threatList)
        XCTAssertEqual(catalog.matchHash(Self.fakeHash)?.family.id, "adload")
        XCTAssertEqual(catalog.matchPath("~/Library/LaunchAgents/com.examplestealer.agent.plist", isExecutable: false)?.family.id,
                       "examplestealer")
        XCTAssertNil(catalog.matchPath("~/Library/Application Support/.exst1234/x", isExecutable: false),
                     "Ancestors are matched as folders, not programs")
        XCTAssertEqual(catalog.matchPath("~/Library/Application Support/.exst1234", isExecutable: true)?.family.id,
                       "examplestealer")
        // Built-in matches keep their wording; downloaded ones say where they came from.
        XCTAssertEqual(catalog.matchLabel("com.xdivcmp")?.indicator.origin, .builtIn)
        XCTAssertEqual(catalog.matchLabel("com.xdivcmp")?.reason, "Startup job name used by Atomic Stealer (AMOS)")
        XCTAssertEqual(catalog.matchLabel("com.examplestealer.agent")?.reason,
                       "Startup job name used by Example Stealer (from the downloaded threat list)")
        // The built-in catalog is unchanged.
        XCTAssertNil(ProtectionThreatCatalog.standard.matchLabel("com.examplestealer.agent"))
        XCTAssertEqual(ProtectionThreatCatalog.standard.threatListIndicatorCount, 0)
    }

    func testMergingNeverOverridesTheBuiltInCatalog() {
        let builtInHash = "d94f62ec4b6ffcec35d5e639d02a52ce226629a5eb3e2a7190174ea8d3b40b5b"
        let family = ProtectionThreatFamily(id: "other", name: "Other", category: .pua, severity: .low, summary: "")
        let clash = ProtectionThreatFamily(id: "amos", name: "Fake AMOS", category: .pua, severity: .low, summary: "")
        let feed = ProtectionThreatFeed(version: 1, families: [family, clash], indicators: [
            ProtectionIndicator(.sha256, builtInHash, family: "other", origin: .threatList),
            ProtectionIndicator(.teamID, "4X5KZ42L4B", family: "other", origin: .threatList),
            ProtectionIndicator(.path, "/tmp/runner", family: "other", executableOnly: true, origin: .threatList),
            ProtectionIndicator(.launchLabel, "com.other.agent", family: "other"),
            ProtectionIndicator(.launchLabel, "com.ghost.agent", family: "ghost", origin: .threatList),
        ])
        let catalog = ProtectionThreatCatalog.standard.merging(feed)
        XCTAssertEqual(catalog.matchHash(builtInHash)?.family.id, "adload")
        XCTAssertEqual(catalog.matchTeamID("4X5KZ42L4B")?.family.id, "shlayer")
        XCTAssertEqual(catalog.matchPath("/tmp/runner", isExecutable: true)?.family.id, "macsync")
        XCTAssertEqual(catalog.family(id: "amos")?.name, "Atomic Stealer (AMOS)")
        XCTAssertEqual(catalog.matchLabel("com.other.agent")?.indicator.origin, .threatList, "Merged indicators are tagged")
        XCTAssertNil(catalog.matchLabel("com.ghost.agent"), "Indicators of unknown families are dropped")
        XCTAssertEqual(catalog.indicators.count, ProtectionThreatCatalog.standard.indicators.count + 1)
        XCTAssertEqual(ProtectionThreatCatalog.standard.merging(.empty).indicators.count,
                       ProtectionThreatCatalog.standard.indicators.count)
    }

    func testLiteralPathIndexKeepsCatalogOrder() {
        let a = ProtectionThreatFamily(id: "a", name: "A", category: .adware, severity: .high, summary: "")
        let b = ProtectionThreatFamily(id: "b", name: "B", category: .adware, severity: .high, summary: "")
        let catalog = ProtectionThreatCatalog(families: [a, b], indicators: [
            ProtectionIndicator(.path, "~/Library/Evil/*.plist", family: "a"),
            ProtectionIndicator(.path, "~/Library/Evil/x.plist", family: "b"),
            ProtectionIndicator(.path, "~/Library/Evil/Y.bin", family: "a", executableOnly: true),
            ProtectionIndicator(.path, "~/Library/Evil/y.bin", family: "b"),
        ])
        XCTAssertEqual(catalog.matchPath("~/Library/Evil/x.plist", isExecutable: false)?.family.id, "a", "The earlier glob wins")
        XCTAssertEqual(catalog.matchPath("~/library/evil/Y.BIN", isExecutable: true)?.family.id, "a")
        XCTAssertEqual(catalog.matchPath("~/Library/Evil/y.bin", isExecutable: false)?.family.id, "b")
        XCTAssertNil(catalog.matchPath("~/Library/Evil/z.bin", isExecutable: true))
    }

    func testOverBroadPathPatternsAreRefused() {
        let refused = [
            "/", "~", "~/*", "~/", "~/Library", "~/Library/*", "~/Library/LaunchAgents/*", "~/Library/LaunchAgents/*.plist",
            "~/.helper", "/tmp/*", "/tmp/php*", "/Users/*/Library/x", "/Library/Application Support",
            "/Library/LaunchDaemons/com.*.plist", "~/Library/Application Support/Google", "Library/LaunchAgents/x.plist",
            "~/Library//x", "~/Library/x/", "~/Library/../x/y", "/Applications/Example.app", "~/Documents/a?",
            "~/Library/LaunchAgents/com.example.agent.plist",
        ]
        for pattern in refused {
            let result = verdict("path", pattern)
            XCTAssertFalse(result.accepted, pattern)
            XCTAssertNotNil(result.reason, pattern)
        }
        let accepted = [
            "~/Library/LaunchAgents/com.examplestealer.agent.plist", "/Library/LaunchDaemons/com.*.net-prefs.plist",
            "/tmp/runner2", "~/Library/Application Support/.exst", "/Library/Application Support/ExampleAds/*.bin",
        ]
        for pattern in accepted {
            XCTAssertTrue(verdict("path", pattern).accepted, "\(pattern): \(verdict("path", pattern).reason ?? "")")
        }
        XCTAssertTrue(verdict("path", "~/*").reason?.contains("too broad") == true)
        // Built-in patterns pass the checks but are skipped as duplicates.
        let builtIn = verdict("path", "/Library/LaunchDaemons/com.*.net-preferences.plist")
        XCTAssertFalse(builtIn.accepted)
        XCTAssertNil(builtIn.reason)
        XCTAssertTrue(verdict("path", "~/Library/LaunchAgents/*.plist").reason?.contains("too broad") == true)
    }

    func testRegularExpressionsMustBeAnchoredAndSpecific() {
        let refused = [
            "^~/.*", "^/.*", ".*evil", "~/Library/Evil", "^/(private/)?tmp/php[A-Za-z0-9]{6}$", "^/tmp/php[A-Za-z0-9]{6}$",
            "^~/Library/Evil/x|.*", "^~/Library/Evil/(a+)+$", "^~/Library/Evil/(x)\\1", "^~/Library/[",
            "^~/Library/LaunchAgents/", "^~/Library/LaunchAgents/com\\..*", "^~/Library/Evil/?",
        ]
        for pattern in refused {
            XCTAssertFalse(verdict("pathRegex", pattern).accepted, pattern)
        }
        let accepted = [
            #"^~/Library/Application Support/\.[0-9]{20,}(/|$)"#, #"^/private/tmp/php[A-Za-z0-9]{7}$"#,
            #"^~/Library/LaunchAgents/com\.exst[0-9]{3}\.plist$"#, "^~/Library/Evil/(Corp|Inc)/x", "^/Library/Evil/run$",
        ]
        for pattern in accepted {
            XCTAssertTrue(verdict("pathRegex", pattern).accepted, "\(pattern): \(verdict("pathRegex", pattern).reason ?? "")")
        }
        XCTAssertEqual(ProtectionThreatFeedValidator.literalComponentCount(regexAfterCaret: #"~/Library/Application Support/\.x+"#), 2)
        XCTAssertEqual(ProtectionThreatFeedValidator.literalComponentCount(regexAfterCaret: "/tmp/runner$"), 2)
        XCTAssertEqual(ProtectionThreatFeedValidator.literalComponentCount(regexAfterCaret: "/tmp/runner/?"), 1)
        XCTAssertEqual(ProtectionThreatFeedValidator.literalComponentCount(regexAfterCaret: #"/a\d/b/c"#), 0)
    }

    func testRegularExpressionsMustBeQuickToCheck() {
        let support = "^~/Library/Application Support/"
        let refused = [
            support + "(.|.)*!$", support + ".*.*.*!$", support + String(repeating: "(.|.)", count: 8) + "!$",
            support + String(repeating: ".{0,30}", count: 3) + "!$", support + "x(ab){2}", support + "x(ab)+",
            support + "x(a|b)*", support + "x.*?.*!$", support + "x[a-z]+[0-9]+\\.?app",
            "^/Library/Application Support/" + String(repeating: ".*", count: 20) + "!$",
        ]
        for pattern in refused {
            let result = verdict("pathRegex", pattern)
            XCTAssertFalse(result.accepted, pattern)
            XCTAssertTrue(result.reason?.contains("very long to check") == true, "\(pattern): \(result.reason ?? "")")
        }
        // Patterns in the style of the built-in ones stay fine.
        let accepted = [
            #"^/private/tmp/\.[^/]{9,}/(player|install)\.app(/|$)"#, #"^/private/tmp/(x/)?\.[^/]{9,}/(player|install)\.app(/|$)"#,
            #"^~/Library/Application Support/\.[0-9]{21,}(/|$)"#, #"^~/Library/Evil/\.local-[0-9A-F]{8}-[0-9A-F]{12}(/|$)"#,
            #"^~/Library/Application Support/\.exst[0-9]{2,4}[a-z*+?|]{3}(/|$)"#, #"^~/Library/Evil/(a|b|c|d|e)$"#,
        ]
        for pattern in accepted {
            XCTAssertTrue(verdict("pathRegex", pattern).accepted, "\(pattern): \(verdict("pathRegex", pattern).reason ?? "")")
        }
        XCTAssertNil(ProtectionThreatFeedValidator.regexCostProblem(#"^/x/y/\(a\)+b{3}"#), "Escaped parentheses aren't groups")
        XCTAssertNotNil(ProtectionThreatFeedValidator.regexCostProblem("^/x/y/(a|b|c|d|e|f)"))
    }

    func testPatternsMayNotPointIntoTheUsersFiles() {
        let paths = [
            "~/Pictures/Photos Library.photoslibrary", "~/Documents/Taxes", "~/Desktop/Projects", "~/Documents/Work/*.docx",
            "~/Downloads/Invoice.pdf", "~/Music/Music/Media.localized", "~/Library/Mobile Documents/com~apple~CloudDocs/x",
            "~/Library/CloudStorage/Dropbox/x", "~/Library/Mail/V10", "~/Library/Messages/chat.db", "~/library/safari/Bookmarks.plist",
            "~/Library/Containers/com.apple.Notes/Data", "~/Library/Containers/com.apple.*/Data",
            "~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite", "/Users/Shared/Projects",
            "/Users/someone/Documents/x", "/Volumes/Backup/Projects", "/Library/Application Support/Old.photoslibrary",
            "~/Library/Keychains/login.keychain-db",
        ]
        for pattern in paths {
            let result = verdict("path", pattern)
            XCTAssertFalse(result.accepted, pattern)
            XCTAssertTrue(result.reason?.contains("your own files") == true, "\(pattern): \(result.reason ?? "")")
        }
        let regexes = [
            "^~/Documents/Work/.*", #"^~/Library/Containers/com\.apple\.photos(/|$)"#, "^~/Library/Containers/[a-z]+evil",
            #"^~/Library/Messages/Attachments/.*\.heic$"#, #"^/Users/Shared/evil[0-9]{3}$"#,
            #"^/Library/Evil/x\.photoslibrary$"#,
        ]
        for pattern in regexes {
            let result = verdict("pathRegex", pattern)
            XCTAssertFalse(result.accepted, pattern)
            XCTAssertTrue(result.reason?.contains("your own files") == true, "\(pattern): \(result.reason ?? "")")
        }
        // Malware locations next to them stay fine.
        for pattern in ["~/Library/Containers/com.evilcorp.agent", "~/Library/Application Support/Documents Helper",
                        "/Library/Application Support/EvilPhotos/run", "~/Library/Group Containers/ZZZZZ99999.evil/x"] {
            XCTAssertTrue(verdict("path", pattern).accepted, "\(pattern): \(verdict("path", pattern).reason ?? "")")
        }
        XCTAssertTrue(verdict("pathRegex", #"^~/Library/Containers/com\.evilcorp\.[a-z]{4}(/|$)"#).accepted)
    }

    func testHashesTeamsAndNamesAreChecked() {
        XCTAssertFalse(verdict("sha256", "abc").accepted)
        XCTAssertFalse(verdict("sha256", String(repeating: "g", count: 64)).accepted)
        XCTAssertFalse(verdict("sha256", ProtectionThreatFeedValidator.emptyFileSHA256).accepted)
        XCTAssertFalse(verdict("sha256", " " + Self.fakeHash).accepted, "No stray spaces")
        XCTAssertTrue(verdict("sha256", Self.fakeHash).accepted)

        XCTAssertFalse(verdict("teamID", "ABC").accepted)
        XCTAssertFalse(verdict("teamID", "ABCDE-1234").accepted)
        XCTAssertFalse(verdict("teamID", "EQHXZ8M8AV").accepted, "Widely used developers can't be flagged")
        XCTAssertFalse(verdict("teamID", ProtectionThreatCatalog.adobeTeamID).accepted)
        XCTAssertTrue(verdict("teamID", "ZZZZZ99999").accepted)

        for label in ["com.*", "*.agent", "com.apple.*", "com.google.*", "com..evil", "com.evil agent", "com.example.*"] {
            XCTAssertFalse(verdict("launchLabel", label).accepted, label)
        }
        XCTAssertTrue(verdict("launchLabel", "com.evilcorp.*").accepted)
        XCTAssertTrue(verdict("launchLabel", "com.apple.questd2").accepted, "Look-alike Apple names are fine")
        for id in ["com.*", "com.google.*", "com.microsoft.*", "org.mozilla.*", "*.example.app"] {
            XCTAssertFalse(verdict("bundleID", id).accepted, id)
        }
        XCTAssertTrue(verdict("bundleID", "com.evilcorp.cleaner").accepted)
        for name in ["*.app", "Inst*", "Install*.app", "*Helper*.app", "Example*.app", "a/b.app"] {
            XCTAssertFalse(verdict("bundleName", name).accepted, name)
        }
        XCTAssertTrue(verdict("bundleName", "Evil Cleaner Pro*.app").accepted)

        XCTAssertFalse(verdict("registryKey", "x").accepted)
        XCTAssertTrue(verdict("registryKey", "x").reason?.contains("isn't one of") == true)
        XCTAssertFalse(verdict("path", "").accepted)
        XCTAssertFalse(verdict("launchLabel", "com.evil.agent\n").accepted)
    }

    func testBadEntriesAreLeftOutOneByOne() throws {
        let parsed = try feed("""
        {"format": 1, "version": 2, "updated": "last tuesday",
         "families": [
           {"id": "good", "name": "Good", "category": "trojan", "severity": "medium"},
           {"id": "Bad Id", "name": "Bad", "category": "trojan", "severity": "medium"},
           {"id": "noname", "category": "trojan", "severity": "medium"},
           {"id": "badcat", "name": "Bad cat", "category": "virus", "severity": "medium"},
           {"id": "badsev", "name": "Bad sev", "category": "trojan", "severity": 3},
           {"id": "good", "name": "Again", "category": "trojan", "severity": "medium"},
           "not an object"
         ],
         "indicators": [
           {"kind": "launchLabel", "pattern": "com.goodfamily.agent", "family": "good"},
           {"kind": "launchLabel", "pattern": 12, "family": "good"},
           {"kind": "launchLabel", "pattern": "com.goodfamily.other"},
           {"kind": "launchLabel", "pattern": "com.goodfamily.third", "family": "badcat"}
         ]}
        """)
        XCTAssertEqual(parsed.families.map(\.id), ["good"])
        XCTAssertEqual(parsed.indicators.map(\.pattern), ["com.goodfamily.agent"])
        XCTAssertNil(parsed.updated)
        XCTAssertEqual(parsed.rejected.count, 10)
        XCTAssertTrue(parsed.rejected.contains { $0.contains("\"updated\" date") })
        XCTAssertTrue(parsed.rejected.contains { $0.hasPrefix("Family 2") && $0.contains("lowercase") })
        XCTAssertTrue(parsed.rejected.contains { $0.hasPrefix("Family 4") && $0.contains("\"virus\"") })
        XCTAssertTrue(parsed.rejected.contains { $0.hasPrefix("Family 6") && $0.contains("used twice") })
        XCTAssertTrue(parsed.rejected.contains { $0.hasPrefix("Family 7") && $0.contains("isn't a valid entry") })
        XCTAssertTrue(parsed.rejected.contains { $0.hasPrefix("Indicator 3") && $0.contains("names no family") })
        XCTAssertTrue(parsed.rejected.contains { $0.hasPrefix("Indicator 4") && $0.contains("\"badcat\" isn't defined") })
    }

    func testWholeFileProblemsRefuseTheFeed() {
        func error(_ text: String) -> ProtectionThreatFeedError? {
            do {
                _ = try ProtectionThreatFeed.parse(Data(text.utf8))
                return nil
            } catch {
                return error as? ProtectionThreatFeedError
            }
        }
        XCTAssertEqual(error("<html>404</html>"), .unreadable("It isn't a JSON object."))
        XCTAssertEqual(error("[1, 2]"), .unreadable("It isn't a JSON object."))
        XCTAssertEqual(error(#"{"version": 1}"#), .unreadable("It has no \"format\" number."))
        XCTAssertEqual(error(#"{"format": 2, "version": 1}"#), .unsupportedFormat(2))
        XCTAssertEqual(error(#"{"format": 0, "version": 1}"#), .unsupportedFormat(0))
        XCTAssertEqual(error(#"{"format": 1}"#), .unreadable("It has no \"version\" number of 1 or more."))
        XCTAssertEqual(error(#"{"format": 1, "version": 1, "families": {}}"#),
                       .unreadable("Its \"families\" field has the wrong type."))
        XCTAssertEqual(error(#"{"format": "1", "version": 1}"#), .unreadable("Its \"format\" field has the wrong type."))
        XCTAssertNil(error(#"{"format": 1, "version": 1}"#))
        XCTAssertTrue(error(#"{"format": 2, "version": 1}"#)?.description.contains("newer version of Spruce") == true)

        let many = Array(repeating: #"{"kind":"sha256","pattern":"x","family":"adload"}"#, count: ProtectionThreatFeed.maxIndicators + 1)
        XCTAssertEqual(error(#"{"format":1,"version":1,"indicators":[\#(many.joined(separator: ","))]}"#),
                       .tooManyIndicators(ProtectionThreatFeed.maxIndicators + 1))
        let big = Data(count: ProtectionThreatFeed.maxFeedBytes + 1)
        XCTAssertThrowsError(try ProtectionThreatFeed.parse(big)) { error in
            XCTAssertEqual(error as? ProtectionThreatFeedError,
                           .tooLarge(bytes: ProtectionThreatFeed.maxFeedBytes + 1, limit: ProtectionThreatFeed.maxFeedBytes))
        }
    }

    func testRulesDownloadIsSizeCappedAndCompiled() throws {
        let rules = try ProtectionThreatFeed.rules(from: Data(#"rule Spruce_Test { strings: $a = "spruce-feed-test" condition: $a }"#.utf8))
        XCTAssertEqual(rules.origin, ProtectionRuleSource.threatListName)
        XCTAssertEqual(rules.activeRuleCount, 1)
        XCTAssertThrowsError(try ProtectionThreatFeed.rules(from: Data(count: ProtectionThreatFeed.maxRulesBytes + 1)))
        XCTAssertTrue(ProtectionThreatFeed.isAllowedDownloadURL(ProtectionThreatFeed.feedURL))
        XCTAssertTrue(ProtectionThreatFeed.isAllowedDownloadURL(ProtectionThreatFeed.rulesURL))
        XCTAssertFalse(ProtectionThreatFeed.isAllowedDownloadURL(URL(string: "http://raw.githubusercontent.com/x")!))
        XCTAssertFalse(ProtectionThreatFeed.isAllowedDownloadURL(URL(fileURLWithPath: "/tmp/feed.json")))
    }

    func testStatusSchedulingAndDecoding() throws {
        var status = ProtectionThreatFeedStatus()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(status.isCheckDue(now: now))
        XCTAssertEqual(status.summary, "Not downloaded yet")
        status.recordCheck(at: now.addingTimeInterval(-3_600), error: "Offline")
        XCTAssertFalse(status.isCheckDue(now: now), "Checked an hour ago")
        XCTAssertEqual(status.lastError, "Offline")
        XCTAssertTrue(status.isCheckDue(now: now.addingTimeInterval(86_400)))
        XCTAssertTrue(status.isCheckDue(now: now.addingTimeInterval(-7_200)), "The clock went back")

        let parsed = ProtectionThreatFeed(version: 3, families: [], indicators: [
            ProtectionIndicator(.launchLabel, "com.evilcorp.agent", family: "adload", origin: .threatList),
        ], rejected: ["x"])
        let rules = ProtectionRuleSource.threatList(YaraRuleSet(source: """
        rule A { strings: $a = "spruce-status-a" condition: $a }
        rule B { strings: $a = "unsupported" base64 condition: $a }
        rule C { condition: filesize >= 0 }
        """, origin: ProtectionRuleSource.threatListName))
        status.recordUpdate(feed: parsed, rules: rules, at: now)
        XCTAssertNil(status.lastError)
        XCTAssertEqual(status.version, 3)
        XCTAssertEqual(status.indicatorCount, 1)
        XCTAssertEqual(status.rejectedCount, 1)
        XCTAssertEqual(status.ruleCount, 1)
        XCTAssertEqual(status.skippedRuleCount, 2, "One unsupported, one matching harmless files")
        XCTAssertEqual(status.summary, "Version 3 · 1 indicator · 1 rule")

        let data = try JSONEncoder().encode(status)
        XCTAssertEqual(try JSONDecoder().decode(ProtectionThreatFeedStatus.self, from: data), status)
        let old = try JSONDecoder().decode(ProtectionThreatFeedStatus.self, from: Data(#"{"version": 2, "ruleCount": "x"}"#.utf8))
        XCTAssertEqual(old.version, 2)
        XCTAssertEqual(old.ruleCount, 0)
        XCTAssertNil(old.lastChecked)

        XCTAssertTrue(ProtectionThreatFeed.shouldReplace(cachedVersion: nil, with: parsed))
        XCTAssertTrue(ProtectionThreatFeed.shouldReplace(cachedVersion: 3, with: parsed))
        XCTAssertFalse(ProtectionThreatFeed.shouldReplace(cachedVersion: 4, with: parsed))
    }
}

/// The files in ThreatFeed/ must always pass Spruce's own checks.
final class ThreatFeedRepositoryTests: XCTestCase {
    static var folder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ThreatFeed")
    }

    func testPublishedFeedPassesValidation() throws {
        let data = try Data(contentsOf: Self.folder.appendingPathComponent("feed.json"))
        XCTAssertLessThanOrEqual(data.count, ProtectionThreatFeed.maxFeedBytes)
        let feed = try ProtectionThreatFeed.parse(data)
        XCTAssertEqual(feed.format, ProtectionThreatFeed.supportedFormat)
        XCTAssertGreaterThanOrEqual(feed.version, 1)
        XCTAssertNotNil(feed.updated)
        XCTAssertEqual(feed.rejected, [], "Every published entry must pass")
        XCTAssertEqual(feed.duplicateCount, 0, "Published indicators shouldn't repeat the built-in catalog")
    }

    func testPublishedRulesCompileCleanly() throws {
        let data = try Data(contentsOf: Self.folder.appendingPathComponent("rules.yara"))
        let source = ProtectionRuleSource.threatList(try ProtectionThreatFeed.rules(from: data))
        XCTAssertEqual(source.rules.skipped, [], "Every published rule must load")
        XCTAssertEqual(source.rules.warnings, [])
        XCTAssertEqual(source.disabledRules, [], "No published rule may match ordinary files")
    }
}
