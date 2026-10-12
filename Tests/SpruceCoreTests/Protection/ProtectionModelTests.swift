import Foundation
import XCTest
@testable import SpruceCore

final class ProtectionModelTests: XCTestCase {

    private func finding(_ id: String, evidence: ThreatEvidence, category: ThreatCategory, severity: ThreatSeverity = .high,
                         manual: String? = nil, kind: ProtectionItemKind = .launchAgent) -> ProtectionThreatFinding {
        ProtectionThreatFinding(id: id, name: (id as NSString).lastPathComponent, family: evidence == .heuristic ? nil : "Fam",
                                category: category, severity: severity, evidence: evidence, reasons: ["Because"],
                                kind: kind, path: id, relatedPaths: ["/x/payload"], launchLabel: "com.x",
                                launchDomain: .system, signing: ProtectionSigningInfo(status: .adHoc), score: 70,
                                size: 1234, inode: 42, manualRemovalNote: manual)
    }

    func testScanDepthParsing() {
        XCTAssertEqual(ProtectionScanDepth(setting: "deep"), .deep)
        XCTAssertEqual(ProtectionScanDepth(setting: "QUICK"), .quick)
        XCTAssertEqual(ProtectionScanDepth(setting: "nonsense"), .balanced)
        XCTAssertLessThan(ProtectionScanDepth.deep.heuristicThreshold, ProtectionScanDepth.quick.heuristicThreshold)
    }

    func testSelectionRules() {
        let known = finding("/a/known.plist", evidence: .knownIndicator, category: .adware)
        XCTAssertTrue(known.scanItem.isSelected)
        XCTAssertEqual(known.scanItem.safety, .safe)
        XCTAssertEqual(known.scanItem.deletion, .trash)

        let pua = finding("/a/pua.app", evidence: .knownIndicator, category: .pua, kind: .application)
        XCTAssertFalse(pua.scanItem.isSelected)
        XCTAssertEqual(pua.scanItem.safety, .review)

        let heuristic = finding("/a/h.plist", evidence: .heuristic, category: .suspicious)
        XCTAssertFalse(heuristic.scanItem.isSelected)

        let manual = finding("/etc/x", evidence: .knownIndicator, category: .adware, manual: "Do it yourself")
        XCTAssertFalse(manual.scanItem.isSelected)
        XCTAssertEqual(manual.scanItem.deletion, .custom)
    }

    func testRemovalPlanRoundTrip() throws {
        let f = finding("/Library/LaunchDaemons/com.x.plist", evidence: .knownHash, category: .stealer, kind: .launchDaemon)
        let plan = try XCTUnwrap(ProtectionRemovalPlan(item: f.scanItem))
        XCTAssertEqual(plan.primaryPath, "/Library/LaunchDaemons/com.x.plist")
        XCTAssertEqual(plan.relatedPaths, ["/x/payload"])
        XCTAssertEqual(plan.launchLabel, "com.x")
        XCTAssertEqual(plan.launchDomain, .system)
        XCTAssertEqual(plan.kind, .launchDaemon)
        XCTAssertEqual(plan.inode, "42")
        XCTAssertTrue(plan.isLaunchJob)
        XCTAssertEqual(f.scanItem.metadata[ProtectionMetaKey.inode], "42")

        let other = ScanItem(id: "x", title: "x")
        XCTAssertNil(ProtectionRemovalPlan(item: other))
    }

    func testGroupsAreOrderedBySeverity() {
        let findings = [
            finding("/a/1", evidence: .heuristic, category: .suspicious, severity: .medium),
            finding("/a/2", evidence: .knownIndicator, category: .adware, severity: .high),
            finding("/a/3", evidence: .knownIndicator, category: .stealer, severity: .critical),
            finding("/a/4", evidence: .knownIndicator, category: .pua, severity: .medium),
        ]
        let groups = ProtectionThreatFinding.scanGroups(findings)
        XCTAssertEqual(groups.map(\.id), [ProtectionThreatGroup.malware.rawValue, ProtectionThreatGroup.unwanted.rawValue,
                                         ProtectionThreatGroup.suspicious.rawValue])
        XCTAssertEqual(groups[0].items.map(\.id), ["/a/3", "/a/2"])
    }

    func testSigningSummary() {
        XCTAssertEqual(ProtectionSigningInfo(status: .unsigned).summary, "Unsigned")
        XCTAssertTrue(ProtectionSigningInfo(status: .signed, teamID: "ABC").summary.contains("ABC"))
        XCTAssertTrue(ProtectionSigningInfo(status: .apple).isTrustedIdentity)
        XCTAssertFalse(ProtectionSigningInfo(status: .adHoc).isTrustedIdentity)
    }

    func testCronParsingAndEditing() {
        let text = "# comment\nMAILTO=\"\"\n@reboot /tmp/x.sh\n*/5 * * * * echo hi > /dev/null\nbad line\n"
        let entries = ProtectionCron.entries(in: text)
        XCTAssertEqual(entries.map(\.schedule), ["@reboot", "*/5 * * * *"])
        XCTAssertEqual(entries[1].command, "echo hi > /dev/null")
        let edited = ProtectionCron.removing(["@reboot /tmp/x.sh"], from: text)
        XCTAssertFalse(edited.contains("@reboot"))
        XCTAssertTrue(edited.contains("*/5 * * * * echo hi"))
        XCTAssertTrue(edited.hasSuffix("\n"))
        XCTAssertTrue(ProtectionCron.isEmptyCrontabMessage("crontab: no crontab for tester"))
    }

    func testAppleSecurityParsers() {
        XCTAssertEqual(ProtectionAppleSecurityParser.gatekeeperEnabled("assessments enabled\n"), true)
        XCTAssertEqual(ProtectionAppleSecurityParser.gatekeeperEnabled("assessments disabled"), false)
        XCTAssertEqual(ProtectionAppleSecurityParser.sipEnabled("System Integrity Protection status: enabled."), true)
        XCTAssertEqual(ProtectionAppleSecurityParser.sipEnabled("System Integrity Protection status: disabled."), false)
        XCTAssertEqual(ProtectionAppleSecurityParser.fileVaultOn("FileVault is On."), true)
        XCTAssertEqual(ProtectionAppleSecurityParser.fileVaultOn("FileVault is Off."), false)
        XCTAssertEqual(ProtectionAppleSecurityParser.firewallEnabled("Firewall is enabled. (State = 1)"), true)
        XCTAssertEqual(ProtectionAppleSecurityParser.firewallEnabled("Firewall is disabled. (State = 0)"), false)
        XCTAssertNil(ProtectionAppleSecurityParser.firewallEnabled("garbage"))
        XCTAssertTrue(ProtectionAppleSecurityParser.isVersion("5310", newerThan: "5297"))
        XCTAssertTrue(ProtectionAppleSecurityParser.isVersion("2.1.10", newerThan: "2.1.9"))
        XCTAssertFalse(ProtectionAppleSecurityParser.isVersion("1.0", newerThan: "1.0.0"))
        let plist = try? PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "5310"], format: .xml, options: 0)
        XCTAssertEqual(plist.flatMap(ProtectionAppleSecurityParser.bundleVersion), "5310")
        let status = ProtectionAppleStatus(gatekeeperEnabled: true, sipEnabled: false, fileVaultOn: nil, firewallEnabled: false)
        XCTAssertEqual(status.disabledLayers, ["System Integrity Protection", "Firewall"])
    }
}
