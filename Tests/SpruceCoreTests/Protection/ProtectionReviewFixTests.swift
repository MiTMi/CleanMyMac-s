import Foundation
import XCTest
@testable import SpruceCore

/// Cloud placeholders, legitimate programs started by flagged jobs, ignore-aware reports,
/// launchctl safety, Firefox channels and automatic scans.
final class ProtectionReviewFixTests: XCTestCase {
    var fx: ProtectionFixture!

    override func setUp() {
        super.setUp()
        fx = ProtectionFixture()
    }

    override func tearDown() {
        fx.remove()
        super.tearDown()
    }

    // MARK: Reading files

    func testSnifferReadsSafely() {
        XCTAssertNil(ProtectionFileSniffer.readPrefix(of: fx.path("~/missing"), limit: 16))
        let script = fx.text("~/run.sh", "#!/bin/zsh\necho hi\n", executable: true)
        XCTAssertEqual(ProtectionFileSniffer.type(of: script), .script(interpreter: "zsh"))
        XCTAssertEqual(ProtectionFileSniffer.readPrefix(of: script, limit: 2), Data("#!".utf8))
        XCTAssertEqual(ProtectionFileSniffer.text(of: script), "#!/bin/zsh\necho hi\n")
        // A folder can be opened but not read: no crash, no data.
        let folder = fx.directory("~/folder")
        XCTAssertEqual(ProtectionFileSniffer.type(of: folder), .other)
    }

    func testOrdinaryFilesAreNotCloudPlaceholders() throws {
        let file = fx.file("~/Documents/report.txt", Data(repeating: 7, count: 8192))
        let entry = try XCTUnwrap(FileWalker.entry(at: file))
        XCTAssertFalse(ProtectionFileSniffer.isCloudPlaceholder(entry))
        let empty = fx.file("~/Documents/empty.txt", Data())
        XCTAssertFalse(ProtectionFileSniffer.isCloudPlaceholder(try XCTUnwrap(FileWalker.entry(at: empty))))
    }

    // MARK: Cloud-only files are never read

    func testDeepScanSkipsCloudOnlyFiles() throws {
        let knownHash = "d94f62ec4b6ffcec35d5e639d02a52ce226629a5eb3e2a7190174ea8d3b40b5b"
        let cloudTool = fx.machO("~/Desktop/tool")
        let localTool = fx.machO("~/Projects/tool")
        let cloudApp = fx.app("~/Documents/Helper.app", bundleID: "com.example.helper")
        let probe = ProtectionStaticProbe(hashes: [cloudTool: knownHash, localTool: knownHash],
                                          defaultSigning: ProtectionSigningInfo(status: .unsigned),
                                          cloudOnlyPaths: [cloudTool, cloudApp + "/Contents/MacOS/main"])
        let report = try fx.scanner(probe: probe).scan(depth: .deep)
        XCTAssertFalse(report.findings.contains { $0.path == cloudTool }, "An online-only file is never opened or hashed")
        XCTAssertTrue(report.findings.contains { $0.path == localTool })
        XCTAssertFalse(report.findings.contains { $0.path == cloudApp },
                       "An app whose program is online-only is not judged by its (unread) signature")
    }

    func testCloudOnlyKnownLocationIsStillReportedByPath() throws {
        let helper = fx.machO("~/.helper")
        let probe = ProtectionStaticProbe(defaultSigning: ProtectionSigningInfo(status: .unsigned), cloudOnlyPaths: [helper])
        let report = try fx.scanner(probe: probe).scan(depth: .quick)
        let finding = try XCTUnwrap(report.findings.first { $0.path == helper })
        XCTAssertTrue(finding.isKnownThreat)
        XCTAssertNil(finding.signing, "Its signature isn't checked (that would download it)")
    }

    // MARK: Flagged jobs that start legitimate apps

    func testFlaggedAgentDoesNotTakeTheLegitimateAppItStarts() throws {
        let chrome = fx.app("/Applications/Google Chrome.app", bundleID: "com.google.Chrome", executable: "Google Chrome")
        let program = chrome + "/Contents/MacOS/Google Chrome"
        let plist = fx.launchPlist("~/Library/LaunchAgents/com.chrome.extensionsPop.plist", label: "com.chrome.extensionsPop",
                                   arguments: [program, "--load-extension=/private/var/tmp/ext"])
        let google = ProtectionSigningInfo(status: .signed, teamID: "EQHXZ8M8AV", authority: "Developer ID Application: Google LLC")
        let probe = ProtectionStaticProbe(signatures: [program: google, chrome: google],
                                          defaultSigning: ProtectionSigningInfo(status: .unsigned))
        let report = try fx.scanner(probe: probe).scan(depth: .quick)
        let finding = try XCTUnwrap(report.findings.first { $0.path == plist })
        XCTAssertEqual(finding.family, "ChromeLoader")
        XCTAssertTrue(finding.isRecommendedForRemoval)
        XCTAssertTrue(finding.relatedPaths.isEmpty, "Google Chrome must not be removed with the agent")
        XCTAssertTrue(finding.reasons.contains { $0.contains("Google Chrome") && $0.contains("stays where it is") })
    }

    func testFlaggedAgentTakesAnUnsignedAppItStarts() throws {
        let bundle = fx.app("~/Library/Application Support/Pop/Pop.app", bundleID: "com.pop.app", executable: "Pop")
        let plist = fx.launchPlist("~/Library/LaunchAgents/com.chrome.extensionsPop.plist", label: "com.chrome.extensionsPop",
                                   arguments: [bundle + "/Contents/MacOS/Pop"])
        let report = try fx.scanner().scan(depth: .quick)
        let finding = try XCTUnwrap(report.findings.first { $0.path == plist })
        XCTAssertEqual(finding.relatedPaths, [bundle])
    }

    func testFlaggedAgentKeepsASignedStandaloneProgram() throws {
        let tool = fx.machO("/Users/Shared/VendorTool/vendortool")
        let plist = fx.launchPlist("~/Library/LaunchAgents/com.chrome.extension.plist", label: "com.chrome.extension",
                                   arguments: [tool])
        let probe = ProtectionStaticProbe(signatures: [tool: ProtectionSigningInfo(status: .signed, teamID: "ABCDE12345")],
                                          defaultSigning: ProtectionSigningInfo(status: .unsigned))
        let report = try fx.scanner(probe: probe).scan(depth: .quick)
        let finding = try XCTUnwrap(report.findings.first { $0.path == plist })
        XCTAssertTrue(finding.relatedPaths.isEmpty)
    }

    // MARK: Ignore list

    func testReportExcludesIgnoredFindings() {
        let a = ProtectionThreatFinding(id: "/Users/me/Library/LaunchAgents/a.plist", name: "a.plist", category: .adware,
                                        severity: .high, evidence: .knownIndicator, reasons: ["x"], kind: .launchAgent,
                                        path: "/Users/me/Library/LaunchAgents/a.plist")
        let b = ProtectionThreatFinding(id: "/Applications/B.app", name: "B.app", category: .pua, severity: .medium,
                                        evidence: .knownIndicator, reasons: ["y"], kind: .application, path: "/Applications/B.app")
        let cron = ProtectionThreatFinding(id: "cron:* * * * * x", name: "x", category: .suspicious, severity: .medium,
                                           evidence: .heuristic, reasons: ["z"], kind: .cronJob, path: nil,
                                           cronLine: "* * * * * x")
        let report = ProtectionMalwareReport(depth: .quick, findings: [a, b, cron], itemsScanned: 10, duration: 1)
        XCTAssertEqual(report.excludingIgnored(SpruceSettings()).threatCount, 3)

        var settings = SpruceSettings()
        settings.ignoredPaths = ["/Applications/B.app"]
        settings.ignoredItemIDs = [cron.id]
        let filtered = report.excludingIgnored(settings)
        XCTAssertEqual(filtered.findings.map(\.id), [a.id])
        XCTAssertEqual(filtered.itemsScanned, 10)
    }

    func testRemovalPlanKnowsTheEvidence() throws {
        let known = ProtectionThreatFinding(id: "/x/a.plist", name: "a", category: .adware, severity: .high,
                                            evidence: .knownIndicator, reasons: [], kind: .launchAgent, path: "/x/a.plist")
        var guess = known
        guess.evidence = .heuristic
        XCTAssertEqual(try XCTUnwrap(ProtectionRemovalPlan(item: known.scanItem)).isKnownThreat, true)
        XCTAssertEqual(try XCTUnwrap(ProtectionRemovalPlan(item: guess.scanItem)).isKnownThreat, false)
    }

    // MARK: launchctl safety

    func testLaunchLabelValidation() {
        XCTAssertTrue(ProtectionLaunchControl.isSafeLabel("com.vendor.agent-2_x+y@z:1"))
        XCTAssertFalse(ProtectionLaunchControl.isSafeLabel(""))
        XCTAssertFalse(ProtectionLaunchControl.isSafeLabel("-bad"))
        XCTAssertFalse(ProtectionLaunchControl.isSafeLabel("com.evil/../../x"))
        XCTAssertFalse(ProtectionLaunchControl.isSafeLabel("com.evil agent"))
        XCTAssertFalse(ProtectionLaunchControl.isSafeLabel("com.évil"))
        XCTAssertTrue(ProtectionLaunchControl.isAppleLabel("Com.Apple.mDNSResponder"))
    }

    func testLaunchPolicyNeverTouchesMacOSServices() {
        let system: Set<String> = ["com.apple.mdnsresponder", "com.apple.windowserver"]
        let copy = ProtectionLaunchControl.policy(plistPath: "/Library/LaunchDaemons/.com.apple.WindowServer.plist",
                                                  label: "com.apple.WindowServer", systemLabels: system,
                                                  catalogMatchedLabel: false)
        XCTAssertFalse(copy.mayStop)
        XCTAssertFalse(copy.mayDisable)

        let masquerade = ProtectionLaunchControl.policy(plistPath: "/Users/me/Library/LaunchAgents/com.apple.questd.plist",
                                                        label: "com.apple.questd", systemLabels: system,
                                                        catalogMatchedLabel: false)
        XCTAssertTrue(masquerade.mayStop)
        XCTAssertFalse(masquerade.mayDisable, "Apple-style labels are never turned off")

        let renamed = ProtectionLaunchControl.policy(plistPath: "/Library/LaunchDaemons/com.evil.helper.plist",
                                                     label: "com.google.keystone.daemon", systemLabels: system,
                                                     catalogMatchedLabel: false)
        XCTAssertTrue(renamed.mayStop)
        XCTAssertFalse(renamed.mayDisable, "A label that differs from the file name could be another vendor's job")

        let catalogLabel = ProtectionLaunchControl.policy(plistPath: "/Library/LaunchDaemons/x.plist", label: "com.xdivcmp",
                                                          systemLabels: system, catalogMatchedLabel: true)
        XCTAssertTrue(catalogLabel.mayDisable)

        let plain = ProtectionLaunchControl.policy(plistPath: "/Library/LaunchDaemons/com.evil.helper.plist",
                                                   label: "com.evil.helper", systemLabels: system, catalogMatchedLabel: false)
        XCTAssertTrue(plain.mayStop)
        XCTAssertTrue(plain.mayDisable)

        XCTAssertFalse(ProtectionLaunchControl.policy(plistPath: "/x/a.plist", label: nil, systemLabels: [],
                                                      catalogMatchedLabel: false).mayStop)
        XCTAssertFalse(ProtectionLaunchControl.policy(plistPath: "/x/a.plist", label: "a b", systemLabels: [],
                                                      catalogMatchedLabel: false).mayStop)
    }

    func testJobsAreOnlyStoppedWhenLoadedFromTheFlaggedPlist() {
        let ours = "/Library/LaunchDaemons/com.evil.helper.plist"
        let policy = ProtectionLaunchControl.policy(plistPath: ours, label: "com.evil.helper", systemLabels: [],
                                                    catalogMatchedLabel: false)
        let printed = """
        system/com.evil.helper = {
        \tactive count = 1
        \tpath = /Library/LaunchDaemons/com.evil.helper.plist
        \tstate = running
        }
        """
        let loaded = ProtectionLaunchControl.loadState(printStatus: 0, output: printed)
        XCTAssertEqual(loaded, .loaded(plistPath: ours))
        XCTAssertTrue(ProtectionLaunchControl.shouldStop(policy: policy, plistPath: ours, state: loaded))
        XCTAssertTrue(ProtectionLaunchControl.shouldStop(policy: policy, plistPath: ours.uppercased(), state: loaded))

        let other = ProtectionLaunchControl.loadState(printStatus: 0, output: "\tpath = /Library/LaunchDaemons/com.vendor.real.plist\n")
        XCTAssertFalse(ProtectionLaunchControl.shouldStop(policy: policy, plistPath: ours, state: other))
        XCTAssertFalse(ProtectionLaunchControl.shouldStop(policy: policy, plistPath: ours, state: .loaded(plistPath: nil)))

        let missing = ProtectionLaunchControl.loadState(
            printStatus: 113, output: "Could not find service \"com.evil.helper\" in domain for system")
        XCTAssertEqual(missing, .notLoaded)
        XCTAssertFalse(ProtectionLaunchControl.shouldStop(policy: policy, plistPath: ours, state: missing))

        let unknown = ProtectionLaunchControl.loadState(printStatus: 1, output: "")
        XCTAssertEqual(unknown, .unknown)
        XCTAssertTrue(ProtectionLaunchControl.shouldStop(policy: policy, plistPath: ours, state: unknown))
        let renamed = ProtectionLaunchControl.policy(plistPath: ours, label: "com.other", systemLabels: [],
                                                     catalogMatchedLabel: false)
        XCTAssertFalse(ProtectionLaunchControl.shouldStop(policy: renamed, plistPath: ours, state: unknown))
    }

    func testDisabledOverridesParsing() {
        let output = """
        disabled services = {
        \t"com.evil.helper" => disabled
        \t"com.vendor.ok" => enabled
        \t"com.old.style" => true
        }
        login item associations = {
        \t"com.x" => disabled
        }
        """
        let map = ProtectionLaunchControl.disabledOverrides(fromPrintDisabled: output)
        XCTAssertEqual(map, ["com.evil.helper": true, "com.vendor.ok": false, "com.old.style": true])
    }

    func testSystemLabelsReadFileNamesAndLabels() {
        let folder = fx.directory("/System/Library/LaunchDaemons")
        fx.plist("/System/Library/LaunchDaemons/com.apple.mDNSResponder.plist", ["Label": "com.apple.mDNSResponder"])
        fx.plist("/System/Library/LaunchDaemons/bootps.plist", ["Label": "com.apple.bootpd"])
        let labels = ProtectionLaunchControl.systemLabels(folders: [folder, fx.path("/missing")])
        XCTAssertTrue(labels.contains("com.apple.mdnsresponder"))
        XCTAssertTrue(labels.contains("com.apple.bootpd"))
        XCTAssertTrue(labels.contains("bootps"))
    }

    // MARK: Firefox channels

    func testEveryFirefoxChannelCountsAsFirefox() throws {
        let firefox = try XCTUnwrap(ProtectionPrivacyCatalog.browser(.firefox))
        XCTAssertTrue(firefox.bundleIDs.contains("org.mozilla.firefox"))
        XCTAssertTrue(firefox.bundleIDs.contains("org.mozilla.firefoxdeveloperedition"))
        XCTAssertTrue(firefox.bundleIDs.contains("org.mozilla.nightly"))
    }

    func testGeckoProfileFolderAndLockOwner() {
        let data = "/Users/me/Library/Application Support/Firefox"
        let cache = "/Users/me/Library/Caches/Firefox"
        XCTAssertEqual(ProtectionPrivacyCatalog.geckoProfileFolder(of: data + "/Profiles/ab12.dev-edition-default/cookies.sqlite",
                                                                  dataRoot: data, cacheRoot: cache),
                       data + "/Profiles/ab12.dev-edition-default")
        XCTAssertEqual(ProtectionPrivacyCatalog.geckoProfileFolder(of: cache + "/Profiles/cd34.default-release",
                                                                  dataRoot: data, cacheRoot: cache),
                       data + "/Profiles/cd34.default-release")
        XCTAssertNil(ProtectionPrivacyCatalog.geckoProfileFolder(of: data + "/profiles.ini", dataRoot: data, cacheRoot: cache))
        XCTAssertNil(ProtectionPrivacyCatalog.geckoProfileFolder(of: "/tmp/x", dataRoot: data, cacheRoot: cache))

        XCTAssertEqual(ProtectionPrivacyCatalog.geckoLockOwnerPID(symlinkTarget: "192.168.1.5:+4242"), 4242)
        XCTAssertEqual(ProtectionPrivacyCatalog.geckoLockOwnerPID(symlinkTarget: "127.0.0.1:77"), 77)
        XCTAssertNil(ProtectionPrivacyCatalog.geckoLockOwnerPID(symlinkTarget: "garbage"))
        XCTAssertNil(ProtectionPrivacyCatalog.geckoLockOwnerPID(symlinkTarget: "1.2.3.4:+"))
    }

    // MARK: Automatic scans and new apps

    func testBackgroundScheduleIsDue() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertEqual(ProtectionBackgroundSchedule(setting: nil), .weekly)
        XCTAssertEqual(ProtectionBackgroundSchedule(setting: "Daily"), .daily)
        XCTAssertEqual(ProtectionBackgroundSchedule(setting: "nonsense"), .weekly)
        XCTAssertFalse(ProtectionBackgroundSchedule.off.isDue(lastScan: nil, now: now))
        XCTAssertTrue(ProtectionBackgroundSchedule.weekly.isDue(lastScan: nil, now: now))
        XCTAssertFalse(ProtectionBackgroundSchedule.weekly.isDue(lastScan: now.addingTimeInterval(-6 * 86_400), now: now))
        XCTAssertTrue(ProtectionBackgroundSchedule.weekly.isDue(lastScan: now.addingTimeInterval(-7 * 86_400), now: now))
        XCTAssertTrue(ProtectionBackgroundSchedule.daily.isDue(lastScan: now.addingTimeInterval(-90_000), now: now))
    }

    func testNewApplicationsAreWatched() throws {
        let added = ProtectionLaunchWatch.addedApplications(previous: ["Safari.app"],
                                                            current: ["Safari.app", "New.app", ".Hidden.app", "notes.txt", "Tool.APP"])
        XCTAssertEqual(added, ["New.app", "Tool.APP"])

        let bundle = fx.app("/Applications/Advanced Mac Cleaner.app", bundleID: "com.techyutils.cleaner")
        let finding = try XCTUnwrap(fx.scanner().evaluateApplication(at: bundle))
        XCTAssertEqual(finding.category, .pua)
        XCTAssertNil(fx.scanner().evaluateApplication(at: fx.app("/Applications/Fine.app", bundleID: "com.example.fine")))

        let event = ProtectionRealtimeEvent(path: bundle, label: nil, domain: .user, kind: .application, finding: finding)
        XCTAssertTrue(event.isApplication)
        XCTAssertEqual(event.notificationTitle, "Threat installed")
        XCTAssertEqual(event.name, "Advanced Mac Cleaner.app")
    }
}
