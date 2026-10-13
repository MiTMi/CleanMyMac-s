import Foundation
import XCTest
@testable import SpruceCore

/// XProtect-style rules that only match Spruce's own test markers.
let ruleScanAppleRules = #"""
import "hash"

private rule Macho
{
    meta:
        description = "private rule to match Mach-O binaries"
    condition:
        uint32(0) == 0xfeedface or uint32(0) == 0xcefaedfe or uint32(0) == 0xfeedfacf or uint32(0) == 0xcffaedfe or uint32(0) == 0xcafebabe or uint32(0) == 0xbebafeca
}

rule XProtect_MACOS_ADLOAD_D
{
    meta:
        description = "MACOS.ADLOAD.D"
    strings:
        $a = "spruce-test-adload-marker"
        $b = { 61 64 5f 67 6f }
    condition:
        Macho and all of them
}

rule XProtect_MACOS_644e18d
{
    meta:
        description = "MACOS.644e18d"
    strings:
        $a = "spruce-test-generic-marker"
    condition:
        Macho and $a
}

rule XProtect_MACOS_Script_Marker : dropper
{
    meta:
        description = "MACOS.c0ffee1"
    strings:
        $s = "#!"
        $m = "spruce-test-script-marker"
    condition:
        $s at 0 and $m
}

rule XProtect_Too_Broad
{
    meta:
        description = "MACOS.broad"
    condition:
        Macho
}

rule Uses_PE
{
    condition:
        pe.number_of_sections > 1
}
"""#

/// Threat-list rules that only match Spruce's own test markers.
let ruleScanFeedRules = #"""
rule Spruce_Pirrit_Helper
{
    meta:
        description = "Pirrit helper script"
        family = "pirrit"
    strings:
        $a = "spruce-test-feed-marker"
    condition:
        $a
}

rule Spruce_Custom
{
    meta:
        description = "Example.Stealer.A"
        category = "stealer"
        severity = "critical"
    strings:
        $a = "spruce-test-custom-marker"
    condition:
        $a
}
"""#

final class ProtectionRuleScanTests: XCTestCase {
    var fx: ProtectionFixture!
    let fakeHash = String(repeating: "0123456789abcdef", count: 4)

    override func setUp() {
        super.setUp()
        fx = ProtectionFixture()
    }

    override func tearDown() {
        fx.remove()
        super.tearDown()
    }

    var appleSource: ProtectionRuleSource {
        .appleXProtect(YaraRuleSet(source: ruleScanAppleRules, origin: ProtectionRuleSource.appleXProtectName))
    }

    var feedSource: ProtectionRuleSource {
        .threatList(YaraRuleSet(source: ruleScanFeedRules, origin: ProtectionRuleSource.threatListName))
    }

    func scanner(_ probe: ProtectionStaticProbe = ProtectionStaticProbe(defaultSigning: ProtectionSigningInfo(status: .unsigned)),
                 sources: [ProtectionRuleSource]? = nil) -> ProtectionMalwareScanner {
        var scanner = fx.scanner(probe: probe)
        scanner.ruleSources = sources ?? [appleSource, feedSource]
        return scanner
    }

    @discardableResult
    func program(_ logical: String, _ marker: String) -> String {
        fx.file(logical, Data(YaraFixture.machO(marker)), executable: true)
    }

    func testXProtectRuleFlagsAProgramAndNamesItsFamily() throws {
        let adload = program("~/Library/Application Support/Helper/updater", "spruce-test-adload-marker ad_go")
        let generic = program("/Users/Shared/tool", "spruce-test-generic-marker")
        let plain = fx.machO("~/Library/Application Support/Helper/plain")
        let probe = ProtectionStaticProbe(hashes: [adload: fakeHash], defaultSigning: ProtectionSigningInfo(status: .unsigned))
        let report = try scanner(probe).scan(depth: .balanced)

        let finding = try XCTUnwrap(report.findings.first { $0.path == adload })
        XCTAssertEqual(finding.evidence, .ruleMatch)
        XCTAssertEqual(finding.evidence.label, "Known malware pattern")
        XCTAssertEqual(finding.family, "Adload")
        XCTAssertEqual(finding.category, .adware)
        XCTAssertEqual(finding.severity, .high)
        XCTAssertEqual(finding.reason, "Matches Apple's XProtect rule for MACOS.ADLOAD.D")
        XCTAssertEqual(finding.ruleHits, [ProtectionRuleHit(source: "Apple XProtect", rule: "XProtect_MACOS_ADLOAD_D",
                                                            detail: "MACOS.ADLOAD.D")])
        XCTAssertEqual(finding.ruleSources, ["Apple XProtect"])
        XCTAssertEqual(finding.programPath, adload)
        XCTAssertEqual(finding.sha256, fakeHash, "Rule findings carry the hash for VirusTotal")
        XCTAssertTrue(finding.isKnownThreat)
        XCTAssertTrue(finding.isRecommendedForRemoval)
        XCTAssertEqual(ProtectionThreatGroup.of(finding), .malware)

        let item = finding.scanItem
        XCTAssertEqual(item.metadata[ProtectionMetaKey.evidence], "ruleMatch")
        XCTAssertEqual(item.metadata[ProtectionMetaKey.ruleSources], "Apple XProtect")
        XCTAssertEqual(item.metadata[ProtectionMetaKey.rules], "XProtect_MACOS_ADLOAD_D")
        XCTAssertEqual(item.metadata[ProtectionMetaKey.ruleLabels], "MACOS.ADLOAD.D")
        XCTAssertEqual(item.metadata[ProtectionMetaKey.program], adload)
        XCTAssertEqual(item.title, "Adload · updater")
        XCTAssertEqual(ProtectionRemovalPlan(item: item)?.isKnownThreat, true)

        let other = try XCTUnwrap(report.findings.first { $0.path == generic })
        XCTAssertEqual(other.family, "XProtect: MACOS.644e18d")
        XCTAssertEqual(other.category, .malware)
        XCTAssertEqual(other.category.title, "Malware")
        XCTAssertEqual(ProtectionThreatGroup.of(other), .malware)

        XCTAssertEqual(report.findings.first { $0.path == plain }?.ruleHits ?? [], [],
                       "A rule that matches every program is switched off")

        // Without rule sources the same files carry no rule evidence.
        let plainReport = try fx.scanner(probe: probe).scan(depth: .balanced)
        XCTAssertFalse(plainReport.findings.contains { $0.evidence == .ruleMatch || !$0.ruleHits.isEmpty })
    }

    func testAppleSignedOnlineOnlyAndOversizedFilesAreNotChecked() throws {
        let apple = program("/Users/Shared/apple-tool", "spruce-test-generic-marker")
        let cloud = program("/Users/Shared/cloud-tool", "spruce-test-generic-marker")
        let probe = ProtectionStaticProbe(signatures: [apple: ProtectionSigningInfo(status: .apple)],
                                          defaultSigning: ProtectionSigningInfo(status: .unsigned), cloudOnlyPaths: [cloud])
        let report = try scanner(probe).scan(depth: .balanced)
        XCTAssertNil(report.findings.first { $0.path == apple }, "Rule matches on Apple-signed files are ignored")
        XCTAssertNil(report.findings.first { $0.path == cloud }, "Online-only files are never read")

        let local = program("/Users/Shared/local-tool", "spruce-test-generic-marker")
        let entry = FileWalker.entry(at: local)
        var small = scanner(probe)
        XCTAssertEqual(small.ruleVerdicts(forFile: local, entry: entry, signing: nil).count, 1)
        small.maxHashBytes = 32
        XCTAssertEqual(small.ruleVerdicts(forFile: local, entry: entry, signing: nil), [], "Files above maxHashBytes are skipped")
        small.maxHashBytes = 100_000_000
        small.maxRuleScanBytes = 40
        XCTAssertEqual(small.ruleVerdicts(forFile: local, entry: entry, signing: nil), [], "The marker lies past what the rules see")
        XCTAssertEqual(small.ruleVerdicts(forFile: local, entry: entry, signing: ProtectionSigningInfo(status: .apple)), [])
        XCTAssertEqual(scanner(probe, sources: []).ruleVerdicts(forFile: local, entry: entry, signing: nil), [])
    }

    func testStartupJobWhoseProgramMatchesAThreatListRule() throws {
        let script = fx.text("~/Library/Application Support/Helper/run.sh",
                             "#!/bin/sh\n# spruce-test-feed-marker\nexit 0\n", executable: true)
        let plist = fx.launchPlist("~/Library/LaunchAgents/com.helper.run.plist", label: "com.helper.run",
                                   arguments: ["/bin/sh", script])
        let report = try scanner().scan(depth: .quick)
        let finding = try XCTUnwrap(report.findings.first { $0.path == plist })
        XCTAssertEqual(finding.evidence, .ruleMatch)
        XCTAssertEqual(finding.family, "Pirrit")
        XCTAssertEqual(finding.category, .adware)
        XCTAssertTrue(finding.reasons.contains("The program it starts matches the Spruce threat list rule for Pirrit helper script"))
        XCTAssertTrue(finding.relatedPaths.contains(script), "The matching program is removed with its startup job")
        XCTAssertEqual(finding.programPath, script)
        XCTAssertEqual(finding.ruleSources, ["Spruce threat list"])
        XCTAssertEqual(finding.launchLabel, "com.helper.run")
    }

    func testApplicationsAreJudgedByTheirMainProgram() throws {
        let bundle = fx.app("/Applications/Player.app", bundleID: "com.example.player")
        let exe = program("/Applications/Player.app/Contents/MacOS/main", "spruce-test-custom-marker")
        let appleBundle = fx.app("/Applications/Apple Thing.app", bundleID: "com.apple.thing")
        program("/Applications/Apple Thing.app/Contents/MacOS/main", "spruce-test-custom-marker")
        let probe = ProtectionStaticProbe(signatures: [appleBundle: ProtectionSigningInfo(status: .apple)],
                                          defaultSigning: ProtectionSigningInfo(status: .signed, teamID: "ABCDE12345"))
        let report = try scanner(probe).scan(depth: .balanced)

        let finding = try XCTUnwrap(report.findings.first { $0.path == bundle })
        XCTAssertEqual(finding.kind, .application)
        XCTAssertEqual(finding.family, "Example.Stealer.A")
        XCTAssertEqual(finding.category, .stealer)
        XCTAssertEqual(finding.severity, .critical)
        XCTAssertEqual(finding.reason, "Matches the Spruce threat list rule for Example.Stealer.A")
        XCTAssertEqual(finding.programPath, exe)
        XCTAssertNil(report.findings.first { $0.path == appleBundle })

        // Real-time protection checks new apps the same way.
        XCTAssertEqual(scanner(probe).evaluateApplication(at: bundle)?.family, "Example.Stealer.A")
        XCTAssertNil(scanner(probe, sources: []).evaluateApplication(at: bundle))
        XCTAssertNil(scanner(probe).evaluateApplication(at: appleBundle))
    }

    func testRuleMatchesMergeWithCatalogAndHeuristicFindings() throws {
        let amos = program("~/.helper", "spruce-test-adload-marker ad_go")
        let hidden = program("/Library/Application Support/.qx/hlpr", "spruce-test-generic-marker")
        let report = try scanner().scan(depth: .balanced)

        let known = report.findings.filter { $0.path == amos }
        XCTAssertEqual(known.count, 1)
        XCTAssertEqual(known.first?.family, "Atomic Stealer (AMOS)", "Catalog families win")
        XCTAssertEqual(known.first?.evidence, .knownIndicator)
        XCTAssertEqual(known.first?.severity, .critical)
        XCTAssertEqual(known.first?.reasons.first, "Location used by Atomic Stealer (AMOS)")
        XCTAssertTrue(known.first?.reasons.contains("Matches Apple's XProtect rule for MACOS.ADLOAD.D") == true)
        XCTAssertEqual(known.first?.ruleHits.count, 1)

        let flagged = try XCTUnwrap(report.findings.first { $0.path == hidden })
        XCTAssertEqual(flagged.evidence, .ruleMatch, "Rule matches beat heuristics")
        XCTAssertEqual(flagged.reason, "Matches Apple's XProtect rule for MACOS.644e18d")
        XCTAssertGreaterThan(flagged.reasons.count, 1, "Heuristic reasons are kept")
        XCTAssertGreaterThan(flagged.score, 0)
    }

    func testScanStateMergesRuleEvidence() {
        var state = ProtectionScanState(threshold: 50, progress: nil, isCancelled: { false })
        let hit = ProtectionRuleHit(source: "Apple XProtect", rule: "R", detail: "MACOS.R")
        let heuristic = ProtectionThreatFinding(id: "/x", name: "x", category: .suspicious, severity: .medium,
                                                evidence: .heuristic, reasons: ["Hidden"], kind: .executable, path: "/x",
                                                sha256: "abc", score: 60, programPath: "/x")
        let rule = ProtectionThreatFinding(id: "/x", name: "x", family: "XProtect: MACOS.R", category: .malware,
                                           severity: .high, evidence: .ruleMatch, reasons: ["Matches R"], kind: .executable,
                                           path: "/x", ruleHits: [hit])
        state.add(heuristic)
        state.add(rule)
        var merged = state.findings["/x"]
        XCTAssertEqual(merged?.evidence, .ruleMatch)
        XCTAssertEqual(merged?.reasons, ["Matches R", "Hidden"])
        XCTAssertEqual(merged?.score, 60)
        XCTAssertEqual(merged?.programPath, "/x")
        XCTAssertEqual(merged?.sha256, "abc")
        XCTAssertEqual(merged?.ruleHits, [hit])

        let catalog = ProtectionThreatFinding(id: "/x", name: "x", family: "Adload", category: .adware, severity: .high,
                                              evidence: .knownIndicator, reasons: ["Location used by Adload"],
                                              kind: .executable, path: "/x")
        state.add(catalog)
        merged = state.findings["/x"]
        XCTAssertEqual(merged?.evidence, .knownIndicator)
        XCTAssertEqual(merged?.family, "Adload")
        XCTAssertEqual(merged?.reasons, ["Location used by Adload", "Matches R", "Hidden"])
        XCTAssertEqual(merged?.ruleHits, [hit])

        // A weaker finding arriving later doesn't replace the stronger one.
        state.add(heuristic)
        XCTAssertEqual(state.findings["/x"]?.evidence, .knownIndicator)
    }

    func testHelpersPeriodicScriptsAndContainers() throws {
        let helper = program("/Library/PrivilegedHelperTools/com.example.helper", "spruce-test-generic-marker")
        let periodic = fx.text("/etc/periodic/daily/500.example", "#!/bin/sh\n# spruce-test-script-marker\nexit 0\n")
        var image = YaraFixture.machO("spruce-test-generic-marker")
        image += [UInt8](repeating: 0, count: 64)
        let dmg = fx.file("~/Downloads/Player.dmg", Data(image))
        let probe = ProtectionStaticProbe(signatures: [helper: ProtectionSigningInfo(status: .signed, teamID: "ABCDE12345")],
                                          defaultSigning: ProtectionSigningInfo(status: .unsigned))
        let report = try scanner(probe).scan(depth: .deep)

        let helperFinding = try XCTUnwrap(report.findings.first { $0.path == helper })
        XCTAssertEqual(helperFinding.kind, .privilegedHelper)
        XCTAssertEqual(helperFinding.evidence, .ruleMatch)
        XCTAssertEqual(helperFinding.programPath, helper)

        let script = try XCTUnwrap(report.findings.first { $0.path == periodic })
        XCTAssertEqual(script.kind, .periodicScript)
        XCTAssertEqual(script.family, "XProtect: MACOS.c0ffee1")
        XCTAssertEqual(script.category, .dropper, "The rule's tag names the category")

        XCTAssertNil(report.findings.first { $0.path == dmg }, "Disk images aren't checked against rules")
    }

    func testRuleSourcesSwitchOffBroadRulesAndExplainSkippedOnes() {
        let source = appleSource
        XCTAssertEqual(source.name, "Apple XProtect")
        XCTAssertEqual(source.kind, .appleXProtect)
        XCTAssertEqual(source.disabledRules, ["XProtect_Too_Broad"])
        XCTAssertEqual(source.rules.activeRuleCount, 4)
        XCTAssertEqual(source.activeRuleCount, 3)
        XCTAssertTrue(source.notes.contains("Rule XProtect_Too_Broad isn't used: it matches ordinary files."))
        XCTAssertTrue(source.notes.contains { $0.hasPrefix("Rule Uses_PE isn't used:") })
        XCTAssertEqual(source.scan(Data(YaraFixture.machO()), fileSize: 64), [])

        let unchecked = ProtectionRuleSource(kind: .appleXProtect, rules: source.rules, checkSamples: false)
        XCTAssertEqual(unchecked.disabledRules, [])
        XCTAssertEqual(unchecked.scan(Data(YaraFixture.machO()), fileSize: 64).map(\.name), ["XProtect_Too_Broad"])
        XCTAssertEqual(feedSource.name, "Spruce threat list")
        XCTAssertEqual(feedSource.disabledRules, [])
        XCTAssertTrue(ProtectionRuleSource.threatList(.empty).isEmpty)
    }

    func testLoadsAppleRulesFromTheNewestLocation() throws {
        XCTAssertNil(ProtectionRuleSource.loadAppleXProtect(root: fx.root))
        let legacy = fx.text(ProtectionRuleSource.appleXProtectPaths[1], ruleScanAppleRules)
        let fromLegacy = try XCTUnwrap(ProtectionRuleSource.loadAppleXProtect(root: fx.root))
        XCTAssertEqual(fromLegacy.location, legacy)
        XCTAssertEqual(fromLegacy.kind, .appleXProtect)
        XCTAssertEqual(fromLegacy.activeRuleCount, 3)

        // macOS 15 keeps the current copy in /private/var/protected; an unusable file there
        // falls back to the other location.
        let current = fx.text(ProtectionRuleSource.appleXProtectPaths[0], "private rule OnlyPrivate { condition: true }")
        XCTAssertEqual(ProtectionRuleSource.loadAppleXProtect(root: fx.root)?.location, legacy)
        fx.text(ProtectionRuleSource.appleXProtectPaths[0], ruleScanAppleRules)
        XCTAssertEqual(ProtectionRuleSource.loadAppleXProtect(root: fx.root)?.location, current)
    }

    func testClassifierNamesFamiliesFromDescriptionsNamesAndTags() {
        let catalog = ProtectionThreatCatalog.standard
        func verdict(_ name: String, _ description: String?, tags: [String] = [], meta: [YaraMeta] = [],
                     source: ProtectionRuleSource? = nil) -> ProtectionRuleVerdict {
            var all = meta
            if let description { all.insert(YaraMeta(key: "description", value: .text(description)), at: 0) }
            let match = YaraRuleMatch(name: name, tags: tags, meta: all, origin: "test")
            return ProtectionRuleClassifier.verdict(for: match, source: source ?? appleSource, catalog: catalog)
        }
        XCTAssertEqual(verdict("XProtect_MACOS_ADLOAD_D", "MACOS.ADLOAD.D").familyName, "Adload")
        XCTAssertEqual(verdict("XProtect_OSX_Pirrit", "OSX.Pirrit").familyID, "pirrit")
        XCTAssertEqual(verdict("XProtect_OSX_Bundlore_D", nil).familyName, "Bundlore")
        XCTAssertEqual(verdict("XProtect_MACOS_SHLAYER", "MACOS.SHLAYER.GEN").category, .dropper)
        XCTAssertEqual(verdict("XProtect_OSX_Genieo_C", "OSX.Genieo.C").category, .browserHijacker)
        XCTAssertEqual(verdict("XProtect_OSX_InstallCore_A", "OSX.InstallCore.A").familyName, "InstallCore")
        XCTAssertEqual(verdict("XProtect_MACOS_KEYSTEAL_A", "MACOS.KEYSTEAL.A").category, .stealer)
        XCTAssertEqual(verdict("XProtect_AMOS", "MACOS.AMOS.B").severity, .critical)
        XCTAssertEqual(verdict("XProtect_MACOS_Miami", "MACOS.MIAMI").familyName, "XProtect: MACOS.MIAMI",
                       "Whole words only (MaMi isn't Miami)")
        let tagged = verdict("XProtect_MACOS_abc123", "MACOS.abc123", tags: ["backdoor"])
        XCTAssertEqual(tagged.familyName, "XProtect: MACOS.abc123")
        XCTAssertEqual(tagged.category, .backdoor)
        XCTAssertEqual(tagged.severity, .high)
        XCTAssertNil(tagged.familyID)
        XCTAssertEqual(verdict("XProtect_MACOS_abc123", "MACOS.abc123").category, .malware)
        XCTAssertEqual(verdict("XProtect_NoDescription", nil).familyName, "XProtect: XProtect_NoDescription")

        // Apple's rules don't get to pick a family through meta; the threat list's do.
        let familyMeta = [YaraMeta(key: "family", value: .text("amos"))]
        XCTAssertEqual(verdict("XProtect_MACOS_1234", "MACOS.1234", meta: familyMeta).familyName, "XProtect: MACOS.1234")
        let feedMeta = [YaraMeta(key: "family", value: .text("Genieo")), YaraMeta(key: "category", value: .text("pua")),
                        YaraMeta(key: "severity", value: .text("low"))]
        let feed = verdict("Spruce_Genieo", "Genieo helper", meta: feedMeta, source: feedSource)
        XCTAssertEqual(feed.familyName, "Genieo")
        XCTAssertEqual(feed.category, .pua)
        XCTAssertEqual(feed.severity, .low)
        XCTAssertEqual(feed.reason, "Matches the Spruce threat list rule for Genieo helper")
        let named = verdict("Spruce_X", "X.A", meta: [YaraMeta(key: "family_name", value: .text("Custom Name"))], source: feedSource)
        XCTAssertEqual(named.familyName, "Custom Name")
        XCTAssertEqual(named.severity, .high)

        let apple = verdict("XProtect_MACOS_ADLOAD_D", "MACOS.ADLOAD.D")
        XCTAssertEqual(apple.reason, "Matches Apple's XProtect rule for MACOS.ADLOAD.D")
        XCTAssertEqual(apple.reason(aboutProgram: true), "The program it starts matches Apple's XProtect rule for MACOS.ADLOAD.D")
        let lab = ProtectionRuleSource(kind: .other, name: "Lab rules", rules: .empty)
        XCTAssertEqual(verdict("Lab_1", "Lab.One", source: lab).reason, "Matches the Lab rules rule for Lab.One")
    }
}
