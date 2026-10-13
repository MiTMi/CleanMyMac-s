import Foundation
import XCTest
@testable import SpruceCore

final class YaraRegexTests: XCTestCase {

    // MARK: Apple's expressions

    /// The regular-expression strings of XProtect 5366 (the only rules an earlier engine skipped).
    static let appleRules = #"""
    rule macos_adload_shell_script_obfuscation { strings: $a2 = /([A-Z]{1}\=\"[a-z]{1}\"\;){5,}/ condition: $a2 }
    rule XProtect_MACOS_TIMELYTURTLE_INDR { strings: $a3 = /(\$\{[A-Z]{1}\}){5,}/ condition: $a3 }
    rule XProtect_MACOS_MISOMESA_C2 { strings: $a3 = /curl -X POST -H \"cl: 0\" --max-time 300 -F \"file=@\/tmp\/[^\/]*\.zip\" -F/ condition: $a3 }
    rule XProtect_MACOS_MISOMAGIC_PE { strings: $a1 = /https:\/\/[a-z0-9]{3,7}\.pages\.dev\/[a-z0-9]{5,10}\.avif2/ condition: $a1 }
    rule XProtect_MACOS_TIMELYTURTLE_DYCASWOCB { strings: $a3 = /com\.apple\.[a-z]{5,10}/ condition: $a3 }
    rule XProtect_MACOS_TIMELYTURTLE_LELINO { strings: $b2 = /https?:\/\/[a-z0-9\-\.]+\/curl\/[a-f0-9]{64}/ condition: $b2 }
    rule XProtect_MACOS_TIMELYTURTLE_TRNO_L { strings: $c0 = /https?:\/\/[a-z0-9\-\.]+\/ledger\/start\/[a-f0-9]{64}/ condition: $c0 }
    rule XProtect_MACOS_TIMELYTURTLE_TRNO_T { strings: $c0 = /https?:\/\/[a-z0-9\-\.]+\/trezor\/start\/[a-f0-9]{64}/ condition: $c0 }
    """#

    static let hex64 = String(repeating: "0123456789abcdef", count: 4)

    func testApplesExpressionsAllLoad() {
        let set = YaraRuleSet(source: Self.appleRules, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.activeRuleCount, 8)
    }

    func testApplesExpressionsMatchTheirTargetsAndNothingElse() {
        let set = YaraRuleSet(source: Self.appleRules, origin: "test")
        let cases: [(name: String, hit: String, miss: String)] = [
            ("macos_adload_shell_script_obfuscation",
             #"x A="b";B="c";C="d";D="e";E="f"; y"#, #"A="b";B="c";C="d";D="e"; y"#),
            ("XProtect_MACOS_TIMELYTURTLE_INDR", "echo ${A}${B}${C}${D}${E}", "echo ${A}${B}${C}${D}"),
            ("XProtect_MACOS_MISOMESA_C2",
             #"curl -X POST -H "cl: 0" --max-time 300 -F "file=@/tmp/out.zip" -F x"#,
             #"curl -X POST -H "cl: 0" --max-time 300 -F "file=@/tmp/a/b.zip" -F x"#),
            ("XProtect_MACOS_MISOMAGIC_PE", "https://abc12.pages.dev/x1y2z3.avif2", "https://ab.pages.dev/x1y2z3.avif2"),
            ("XProtect_MACOS_TIMELYTURTLE_DYCASWOCB", "com.apple.updater", "com.apple.abc"),
            ("XProtect_MACOS_TIMELYTURTLE_LELINO", "GET http://evil-site.example/curl/" + Self.hex64,
             "GET http://evil-site.example/curl/" + Self.hex64.dropLast()),
            ("XProtect_MACOS_TIMELYTURTLE_TRNO_L", "https://a.b-c.io/ledger/start/" + Self.hex64,
             "https://a.b-c.io/ledger/stop/" + Self.hex64),
            ("XProtect_MACOS_TIMELYTURTLE_TRNO_T", "https://x.io/trezor/start/" + Self.hex64,
             "https://x.io/trezor/start/" + Self.hex64.uppercased()),
        ]
        for item in cases {
            XCTAssertEqual(set.names(YaraFixture.machO(item.hit)), [item.name], item.name)
            XCTAssertEqual(set.names(YaraFixture.machO(item.miss)), [], item.name)
        }
        // All of them in one file, among noise.
        var body = YaraFixture.noise(20_000)
        for item in cases { body += YaraFixture.bytes(" " + item.hit + " ") + YaraFixture.noise(300, seed: 7) }
        XCTAssertEqual(Set(set.names(YaraFixture.machO(body))), Set(cases.map(\.name)))
    }

    func testApplesExpressionsGetAtoms() throws {
        func regex(_ source: String, wide: Bool = false) throws -> YaraRegex {
            try YaraRegex(root: YaraRegexParser.parse(Array(source.utf8), caseless: false, dotAll: false), wide: wide)
        }
        let http = try regex(#"https?:\/\/[a-z0-9\-\.]+\/curl\/[a-f0-9]{64}"#)
        XCTAssertEqual(http.atom?.bytes.map(\.value), Array("http".utf8))
        XCTAssertEqual(http.atom?.leadMin, 0)
        // Inside the first iteration of a repeated group, one character after the start.
        let adload = try regex(#"([A-Z]{1}\=\"[a-z]{1}\"\;){5,}"#)
        XCTAssertEqual(adload.atom?.bytes.map(\.value), Array("=\"".utf8))
        XCTAssertEqual(adload.atom.map { $0.leadMin...$0.leadMax }, 1...1)
        let dollar = try regex(#"(\$\{[A-Z]{1}\}){5,}"#)
        XCTAssertEqual(dollar.atom?.bytes.map(\.value), Array("${".utf8))
        // A literal far behind an unbounded repeat can't be an atom.
        XCTAssertNil(try regex(#"[a-z]+xyz"#).atom)
        // Wide atoms interleave zero bytes.
        XCTAssertEqual(try regex("ab", wide: true).atom?.bytes.map(\.value), [0x61, 0, 0x62, 0])
    }

    // MARK: Syntax

    func testClassesEscapesAndDot() {
        let s = #"$a = /[^a-c\d][\x41-\x43]\.\w\s\D/"#
        XCTAssertTrue(yaraHolds("$a", strings: s, YaraFixture.bytes("zB.k x")))
        XCTAssertFalse(yaraHolds("$a", strings: s, YaraFixture.bytes("aB.k x")))
        XCTAssertFalse(yaraHolds("$a", strings: s, YaraFixture.bytes("zB.k 5")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /a[]b]c/"#, YaraFixture.bytes("a]c")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /x[a-]y/"#, YaraFixture.bytes("x-y")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /tab\there/"#, YaraFixture.bytes("tab\there")))
        // `.` skips newlines unless the s flag is given.
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /ab.cd/"#, YaraFixture.bytes("ab\ncd")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /ab.cd/s"#, YaraFixture.bytes("ab\ncd")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /ab.cd/"#, YaraFixture.bytes("abXcd")))
    }

    func testQuantifiersGroupsAndAlternation() {
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /colou?r/"#, YaraFixture.bytes("color")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /colou?r/"#, YaraFixture.bytes("colour")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /x\d{2,3}y/"#, YaraFixture.bytes("x123y")))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /x\d{2,3}y/"#, YaraFixture.bytes("x1234y")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /x\d{,2}y/"#, YaraFixture.bytes("xy")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /x(ab|cd)+y/"#, YaraFixture.bytes("xabcdaby")))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /x(ab|cd)+y/"#, YaraFixture.bytes("xy and xay")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /(?:cat|dog)fish/"#, YaraFixture.bytes("dogfish")))
        // A brace that isn't a repeat count is a literal.
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /a{b}/"#, YaraFixture.bytes("a{b}")))
    }

    func testAnchorsAndWordBoundaries() {
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /^#!\/bin\/sh/"#, YaraFixture.bytes("#!/bin/sh\necho")))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /^#!\/bin\/sh/"#, YaraFixture.bytes(" #!/bin/sh")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /exit 0$/"#, YaraFixture.bytes("x\nexit 0")))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /exit 0$/"#, YaraFixture.bytes("exit 0\n")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /\bcurl\b/"#, YaraFixture.bytes("run curl now")))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /\bcurl\b/"#, YaraFixture.bytes("libcurls")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /url\B/"#, YaraFixture.bytes("urls")))
    }

    func testCaseFlagsAndModifiers() {
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /evil[a-c]/i"#, YaraFixture.bytes("EViLB")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /evil[a-c]/ nocase"#, YaraFixture.bytes("eVILc")))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /evil[a-c]/"#, YaraFixture.bytes("EVILB")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /pa[s]+word/ wide"#, YaraFixture.wide("my password")))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /pa[s]+word/ wide"#, YaraFixture.bytes("my password")))
        let both = #"$a = /pa[s]+word/ ascii wide"#
        XCTAssertTrue(yaraHolds("$a", strings: both, YaraFixture.bytes("my password")))
        XCTAssertTrue(yaraHolds("$a", strings: both, YaraFixture.wide("my password")))
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /ev[il]+/ fullword"#, YaraFixture.bytes("so evil.")))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /ev[il]+/ fullword"#, YaraFixture.bytes("devilish")))
    }

    func testCountsOffsetsAndLengths() {
        let data = YaraFixture.bytes("ab1 ab22 ab333")
        XCTAssertTrue(yaraHolds("#a == 3", strings: #"$a = /ab\d+/"#, data))
        XCTAssertTrue(yaraHolds("@a[2] == 4 and !a[2] == 4", strings: #"$a = /ab\d+/"#, data))
        // Lazy quantifiers take the shortest match.
        XCTAssertTrue(yaraHolds("!a[1] == 3", strings: #"$a = /ab\d+?/"#, data))
        XCTAssertTrue(yaraHolds("$a at 9", strings: #"$a = /ab3{3}/"#, data))
    }

    // MARK: Limits

    func testMatchesReachAtMostFourKilobytes() {
        let near = YaraFixture.bytes("start") + [UInt8](repeating: 0x41, count: 4_000) + YaraFixture.bytes("end")
        let far = YaraFixture.bytes("start") + [UInt8](repeating: 0x41, count: 4_200) + YaraFixture.bytes("end")
        XCTAssertTrue(yaraHolds("$a", strings: #"$a = /start.*end/"#, near))
        XCTAssertFalse(yaraHolds("$a", strings: #"$a = /start.*end/"#, far))
    }

    func testHostileExpressionsFinishQuickly() {
        let data = [UInt8](repeating: UInt8(ascii: "a"), count: 20_000)
        let started = Date()
        // Classic catastrophic backtracking, and an expression without any atom.
        let set = YaraRuleSet(source: #"""
        rule nested { strings: $a = /(a+)+b/ condition: $a }
        rule anywhere { strings: $a = /[a-z]+[0-9]/ condition: $a }
        rule groups { strings: $a = /((a|aa)+)+c/ condition: $a }
        """#, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.names(data), [])
        // The required character is there, so the backtracking really runs and its work
        // budget has to stop it.
        let tempting = [UInt8](repeating: UInt8(ascii: "a"), count: 3_000) + YaraFixture.bytes("cb")
        let budgeted = YaraRuleSet(source: #"rule nested { strings: $a = /(a+)+bc/ condition: $a }"#, origin: "test")
        let result = budgeted.scanDetailed(Data(tempting))
        XCTAssertEqual(result.matches.map(\.name), [])
        XCTAssertFalse(result.notes.isEmpty, "the budget note explains why the string stopped")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testUnsupportedOrBrokenExpressionsSkipOnlyTheirRule() {
        let set = YaraRuleSet(source: #"""
        rule ok { strings: $a = /fine/ condition: $a }
        rule backref { strings: $a = /(a)\1/ condition: $a }
        rule unclosed_group { strings: $a = /(ab/ condition: $a }
        rule unclosed_class { strings: $a = /[ab/ condition: $a }
        rule empty_match { strings: $a = /x?/ condition: $a }
        rule nothing_to_repeat { strings: $a = /a|*b/ condition: $a }
        rule too_many_groups { strings: $a = /(ab){100}/ condition: $a }
        rule too_many_repeats { strings: $a = /a{5000}/ condition: $a }
        rule backwards { strings: $a = /a{3,2}/ condition: $a }
        rule bad_hex { strings: $a = /\x4/ condition: $a }
        rule bad_flag { strings: $a = /abc/x condition: $a }
        rule xor_regex { strings: $a = /abc/ xor condition: $a }
        rule ok_last { strings: $a = /last/ condition: $a }
        """#, origin: "test")
        XCTAssertEqual(set.rules.map(\.name), ["ok", "ok_last"])
        XCTAssertEqual(set.skipped.count, 11)
        XCTAssertEqual(set.names(YaraFixture.bytes("fine and last")), ["ok", "ok_last"])
    }
}
