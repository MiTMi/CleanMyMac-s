import Foundation
import XCTest
@testable import SpruceCore

final class YaraParserTests: XCTestCase {

    func testXProtectStyleFileLoadsEveryRule() {
        let set = YaraRuleSet(source: yaraXProtectSample, origin: "Apple XProtect")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.warnings, [])
        XCTAssertEqual(set.imports, ["hash"])
        XCTAssertEqual(set.rules.map(\.name), [
            "Macho", "PE", "XProtect_MACOS_644e18d", "XProtect_AdLoad_B_2", "XProtect_MACOS_Nibbles",
            "XProtect_MACOS_Jumps", "XProtect_MACOS_Hash", "XProtect_MACOS_Script", "XProtect_PE_Thing",
        ])
        XCTAssertEqual(set.rules.filter(\.isPrivate).map(\.name), ["Macho", "PE"])
        XCTAssertEqual(set.activeRuleCount, 7)
        XCTAssertEqual(set.origin, "Apple XProtect")

        let adload = set.rules.first { $0.name == "XProtect_AdLoad_B_2" }
        XCTAssertEqual(adload?.tags, ["dropper"])
        XCTAssertEqual(adload?.description, "AdLoad.B.2")
        XCTAssertEqual(adload?.meta, [
            YaraMeta(key: "description", value: .text("AdLoad.B.2")),
            YaraMeta(key: "xprotect_rule", value: .boolean(true)),
            YaraMeta(key: "gk_first_launch_only", value: .boolean(true)),
            YaraMeta(key: "match_type", value: .integer(2)),
        ])
        XCTAssertEqual(set.rules.first { $0.name == "Macho" }?.description, "private rule to match Mach-O binaries")
        XCTAssertEqual(set.rules.first { $0.name == "XProtect_MACOS_Script" }?.tags, ["script"])
        XCTAssertGreaterThan(set.rules.first { $0.name == "PE" }?.line ?? 0, 1)
    }

    func testHashModuleWorksWithoutImport() {
        let set = YaraRuleSet(source: #"rule h { condition: hash.md5(0, filesize) == "900150983cd24fb0d6963f7d28e17f72" }"#,
                              origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.names(YaraFixture.bytes("abc")), ["h"])
    }

    func testCommentsEscapesAndNumbers() {
        let source = #"""
        /* A block comment
           over several lines */
        rule commented // trailing comment
        {
            meta:
                author = "Spruce \"tests\""   // escaped quotes
                version = -3
                size = 0x10
            strings:
                $esc = "A\x42\tC\\D\n"
                $hex = { 41 /* inline */ 42 // to the end of the line
                         43 }
            condition:
                $esc and $hex and filesize < 1KB and 2MB == 2097152 and 0x1F == 31 and 0o17 == 15
                /* a comment inside the condition */ and 1.5 < 2
        }
        """#
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.rules.first?.meta, [
            YaraMeta(key: "author", value: .text("Spruce \"tests\"")),
            YaraMeta(key: "version", value: .integer(-3)),
            YaraMeta(key: "size", value: .integer(16)),
        ])
        XCTAssertEqual(set.names(YaraFixture.bytes("xxAB\tC\\D\nxxABC")), ["commented"])
        XCTAssertEqual(set.names(YaraFixture.bytes("xxAB\tC\\Dxx ABC")), [])
    }

    func testHexStringSyntaxVariants() {
        let variants = [
            "{ 63 6f 6e 6e }",
            "{ 4d 65 ?? 68 }",
            "{ 7? 77 3? 41 }",
            "{ 4? ?4 41 42 }",
            "{ 41 42 [0-3] 43 44 }",
            "{ 41 42 [0 - 2] 43 44 }",
            "{ 41 42 [30 - 40] 43 44 }",
            "{ 41 42 [5] 43 44 }",
            "{ 41 42 [2-] 43 44 }",
            "{ 41 42 [-] 43 44 }",
            "{ 41 42 [300-400] 43 44 }",
            "{ 41 ( 19 | 17 ) 42 }",
            "{ 41 (48 | 49) 42 }",
            "{ 41 (90 90 | 90 90 90 | 90 90 90 90) 42 }",
            "{ 41 ( 42 ( 43 | 44 ) | 45 [1-2] 46 ) 47 }",
            "{ ( 41 42 | 43 44 ) 45 }",
            "{ 41 ~42 ~?3 44 }",
            "{\n 41 42\n 43 44\n }",
            "{ 41 [2][3] 42 }",
        ]
        for hex in variants {
            let set = YaraRuleSet(source: "rule r { strings: $a = \(hex) condition: $a }", origin: "test")
            XCTAssertEqual(set.skipped, [], hex)
            XCTAssertEqual(set.activeRuleCount, 1, hex)
        }
    }

    func testInvalidHexStringsSkipTheirRule() {
        let invalid = [
            "{ }": "empty",
            "{ [2] 41 }": "start with a jump",
            "{ 41 [2] }": "end with a jump",
            "{ 41 [3-1] 42 }": "backwards",
            "{ 41 ( 42 [-] 43 | 44 ) 45 }": "unbounded jumps",
            "{ 41 ( 42 | ) 43 }": "empty alternative",
            "{ 41 ( 42 43 }": "unclosed",
            "{ 41 42 ) }": "unmatched",
            "{ 4 }": "byte",
            "{ 41 [-5] 42 }": "malformed jump",
            "{ ~?? 41 }": "never match",
        ]
        for (hex, reason) in invalid {
            let set = YaraRuleSet(source: "rule bad { strings: $a = \(hex) condition: $a }\nrule good { condition: true }",
                                  origin: "test")
            XCTAssertEqual(set.rules.map(\.name), ["good"], hex)
            XCTAssertEqual(set.skipped.map(\.name), ["bad"], hex)
            XCTAssertTrue(set.skipped.first?.reason.contains(reason) ?? false, "\(hex): \(set.skipped.first?.reason ?? "")")
        }
    }

    func testStringModifiersParse() {
        let source = #"""
        rule mods {
            strings:
                $a = "alpha" ascii wide nocase fullword private
                $b = "beta" xor
                $c = "gamma" xor(0x01-0xff)
                $d = "delta" xor(5) wide
                $e = { 41 42 } private
            condition:
                any of them
        }
        """#
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.activeRuleCount, 1)
    }

    func testConditionSyntaxCoverage() {
        let conditions = [
            "all of them", "any of them", "none of them", "2 of them", "50% of them",
            "1 of ($a*)", "all of ($b*)", "2 of ($a1,$a2,$b1)", "(not any of ($b*))", "any of ($a1, $b*)",
            "#b1 > 15", "#a1 == 0", "#a1 in (0..100) == 1", "$a1 at 0", "$a1 at 10 + 2", "$a1 in (0..100)",
            "@a1[1] == 3", "@a1 == 3", "!a1[1] == 3", "!a1 > 0",
            "for any of ($a*) : ( $ at 0 )", "for all of them : ( # < 5 )", "for 2 of ($a1, $a2) : ( @ > 1 )",
            "for any of them : ( !  > 0 )",
            "for any i in (1..#a1) : ( @a1[i] < 100 )", "for all i in (0, 4, 8) : ( uint8(i) != 0x41 )",
            "for 50% i in (1..10) : ( i > 5 )",
            "for any i in (1..2) : ( for any j in (1..2) : ( i * j == 4 ) )",
            "uint8(0) == 1", "uint16(0) == 1", "uint32(0) == 1", "uint16be(0) == 1", "uint32be(0) == 1",
            "int8(0) == -1", "int16(0) == -1", "int32(0) == -1", "int16be(0) == 1", "int32be(0) == 1", "uint8be(0) == 1",
            "uint32(uint32(0x3C)) == 0x4550", "filesize < 15MB", "filesize <= 40000", "filesize > 200",
            "1 + 2 * 3 - 4 \\ 2 % 3 == 5", "(5 & 3) | (1 << 2) ^ (16 >> 1) == 13", "~0 == -1", "-5 < 0",
            "true", "false or true", "not false", "defined filesize", "1.5 < 2.5",
            "\"abc\" contains \"b\"", "\"abc\" icontains \"B\"", "\"abc\" startswith \"a\"", "\"abc\" istartswith \"A\"",
            "\"abc\" endswith \"c\"", "\"abc\" iendswith \"C\"", "\"abc\" iequals \"ABC\"",
            "hash.sha1(0, filesize) == \"x\"", "hash.sha1(0, 22032) == \"x\"", "hash.md5(\"abc\") != \"\"",
            "hash.sha256(0, 10) != \"\"", "hash.crc32(0, filesize) == 0", "hash.checksum32(0, filesize) > 0",
            "any of ($a1, $a2) at 0", "all of ($b*) in (0..filesize)",
        ]
        let strings = """
            $a1 = "one"
            $a2 = { 74 77 6f }
            $b1 = "three"
            $ = "anonymous"
        """
        for condition in conditions {
            let set = YaraRuleSet(source: "rule r {\n strings:\n\(strings)\n condition:\n \(condition)\n}", origin: "test")
            XCTAssertEqual(set.skipped, [], condition)
            XCTAssertEqual(set.activeRuleCount, 1, condition)
        }
    }

    func testRuleSetsAndForwardReferences() {
        let source = #"""
        rule uses_later { condition: later and any of (helper_*) }
        private rule helper_one { condition: filesize > 1 }
        private rule helper_two { condition: filesize > 100 }
        rule later { condition: all of (helper_one, helper_two) or 1 of (helper_*) }
        """#
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.names(YaraFixture.bytes("hello")), ["uses_later", "later"])
        XCTAssertEqual(set.names(YaraFixture.bytes("h")), [])
    }

    func testGlobalAndPrivateFlags() {
        let source = """
        global rule g1 { condition: true }
        private global rule g2 { condition: true }
        global private rule g3 { condition: true }
        rule plain { condition: true }
        """
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.rules.map(\.isGlobal), [true, true, true, false])
        XCTAssertEqual(set.rules.map(\.isPrivate), [false, true, true, false])
        XCTAssertEqual(set.activeRuleCount, 2)
    }

    func testEmptyAndCommentOnlySources() {
        for source in ["", "   \n\n", "// nothing here\n/* or here */", "import \"hash\""] {
            let set = YaraRuleSet(source: source, origin: "test")
            XCTAssertTrue(set.isEmpty, source)
            XCTAssertEqual(set.skipped, [], source)
            XCTAssertEqual(set.scan(Data([1, 2, 3])), [])
        }
        XCTAssertTrue(YaraRuleSet.empty.isEmpty)
    }
}
