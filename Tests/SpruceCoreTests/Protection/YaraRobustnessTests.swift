import Foundation
import XCTest
@testable import SpruceCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class YaraRobustnessTests: XCTestCase {

    private func reason(_ set: YaraRuleSet, _ name: String) -> String {
        set.skipped.first { $0.name == name }?.reason ?? "(not skipped)"
    }

    // MARK: Skipped rules

    func testUnsupportedConstructsSkipOnlyTheirRules() {
        let source = #"""
        import "hash"
        import "pe"
        import "math"

        rule ok_first { strings: $a = "fine" condition: $a }
        rule regex_string { strings: $a = /ev[il]+/i condition: $a }
        rule uses_regex_rule { condition: regex_string }
        rule uses_uses { condition: uses_regex_rule or true }
        rule pe_module { condition: pe.number_of_sections > 2 }
        rule pe_call { condition: pe.exports("evil") }
        rule math_module { condition: math.entropy(0, filesize) > 7.5 }
        rule macho_loop { condition: for any s in macho.segments : ( s.name == "x" ) }
        rule matches_op { strings: $a = "x" condition: $a and "abc" matches /a.c/ }
        rule base64_string { strings: $a = "evil" base64 condition: $a }
        rule entry { condition: entrypoint == 0 }
        rule unknown_hash { condition: hash.sha512(0, filesize) == "x" }
        rule unknown_name { condition: no_such_rule }
        rule unknown_string { condition: $nope }
        rule anonymous_outside { strings: $ = "x" condition: $ }
        rule them_without_strings { condition: any of them }
        rule mixed_set { strings: $a = "x" condition: any of ($a, ok_first) }
        rule xor_nocase { strings: $a = "x" xor nocase condition: $a }
        rule hex_modifier { strings: $a = { 41 } wide condition: $a }
        rule empty_text { strings: $a = "" condition: $a }
        rule ok_last { condition: ok_first }
        """#
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.rules.map(\.name), ["ok_first", "ok_last"])
        XCTAssertEqual(set.names(YaraFixture.bytes("all fine")), ["ok_first", "ok_last"])
        let expected: [String: String] = [
            "regex_string": "regular expression",
            "uses_regex_rule": "Uses rule regex_string, which was skipped",
            "uses_uses": "Uses rule uses_regex_rule, which was skipped",
            "pe_module": "pe module",
            "pe_call": "pe module",
            "math_module": "math module",
            "macho_loop": "macho module",
            "matches_op": "regular expressions",
            "base64_string": "base64",
            "entry": "entrypoint",
            "unknown_hash": "hash.sha512",
            "unknown_name": "unknown identifier no_such_rule",
            "unknown_string": "$nope",
            "anonymous_outside": "anonymous string",
            "them_without_strings": "no strings",
            "mixed_set": "mix strings and rules",
            "xor_nocase": "xor and nocase",
            "hex_modifier": "private modifier",
            "empty_text": "is empty",
        ]
        XCTAssertEqual(Set(set.skipped.map(\.name)), Set(expected.keys))
        for (name, text) in expected {
            XCTAssertTrue(reason(set, name).contains(text), "\(name): \(reason(set, name))")
        }
        XCTAssertEqual(set.warnings.count, 2)
        XCTAssertTrue(set.warnings.contains { $0.contains("pe module") })
        // Skipped rules are listed in file order with their lines.
        XCTAssertEqual(set.skipped.map(\.line), set.skipped.map(\.line).sorted())
    }

    func testSyntaxErrorsMidFileKeepLaterRules() {
        let source = """
        rule good_one { condition: true }
        rule missing_brace { strings: $a = "x" condition: $a
        rule good_two { condition: filesize > 0 }
        rule bad_string { strings: $a = "unterminated condition: $a }
        rule good_three { condition: true }
        this is not a rule
        rule good_four { condition: true }
        rule bad_hex { strings: $a = { 41 4G } condition: $a }
        rule good_five { condition: true }
        rule bad_token { condition: true and and }
        rule good_six { condition: true }
        rule bad_meta { meta: x = condition: true }
        rule good_seven { condition: true }
        rule depends_on_broken { condition: missing_brace }
        rule bad_character { condition: true ` }
        rule good_eight { condition: true }
        rule
        """
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.rules.map(\.name), ["good_one", "good_two", "good_three", "good_four", "good_five",
                                               "good_six", "good_seven", "good_eight"])
        XCTAssertEqual(set.skipped.map(\.name), ["missing_brace", "bad_string", "", "bad_hex", "bad_token", "bad_meta",
                                                 "depends_on_broken", "bad_character", ""])
        XCTAssertTrue(reason(set, "missing_brace").hasPrefix("Syntax error on line 3"), reason(set, "missing_brace"))
        XCTAssertTrue(reason(set, "bad_string").contains("never ends"))
        XCTAssertTrue(reason(set, "bad_hex").contains("hex string"))
        XCTAssertTrue(reason(set, "depends_on_broken").contains("Uses rule missing_brace"))
        XCTAssertEqual(set.skipped[2].line, 6)
        XCTAssertEqual(set.names(YaraFixture.bytes("x")).count, 8)
    }

    func testDuplicatesAndLoops() {
        let source = """
        rule dup { condition: true }
        rule dup { condition: false }
        rule dup_strings { strings: $a = "x" $a = "y" condition: $a }
        rule self_ref { condition: self_ref }
        rule cycle_a { condition: cycle_b }
        rule cycle_b { condition: cycle_a or true }
        rule on_cycle { condition: cycle_a }
        rule wildcard_loop { condition: any of (wildcard_*) }
        rule wildcard_helper { condition: wildcard_loop }
        rule fine { condition: true }
        """
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.rules.map(\.name), ["dup", "fine"])
        XCTAssertTrue(reason(set, "dup").contains("earlier"))
        XCTAssertTrue(reason(set, "dup_strings").contains("Defines $a twice"))
        XCTAssertTrue(reason(set, "self_ref").contains("Refers to itself"))
        XCTAssertTrue(reason(set, "cycle_a").contains("through other rules"))
        XCTAssertTrue(reason(set, "cycle_b").contains("through other rules"))
        XCTAssertTrue(reason(set, "on_cycle").contains("Uses rule cycle_a"), reason(set, "on_cycle"))
        XCTAssertTrue(reason(set, "wildcard_loop").contains("through other rules"))
        XCTAssertEqual(set.names([1]), ["dup", "fine"])
    }

    func testNestingAndLengthLimits() {
        let deep = String(repeating: "(", count: 40) + "true" + String(repeating: ")", count: 40)
        let notChain = String(repeating: "not ", count: 100) + "false"
        let longOr = (0..<200).map { "filesize == \($0)" }.joined(separator: " or ")
        let longSum = (0..<60).map { _ in "1" }.joined(separator: " + ") + " == 60"
        let okSum = (0..<30).map { _ in "1" }.joined(separator: " + ") + " == 30"
        let tooLong = (0..<100).map { _ in "1" }.joined(separator: " + ") + " == 100"
        let source = """
        rule deep { condition: \(deep) }
        rule not_chain { condition: \(notChain) }
        rule long_or { condition: \(longOr) }
        rule long_sum { condition: \(longSum) }
        rule ok_sum { condition: \(okSum) }
        rule too_long { condition: \(tooLong) }
        rule after { condition: true }
        rule huge_parens { condition: \(String(repeating: "(", count: 20_000)) }
        rule after_huge { condition: true }
        """
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.rules.map(\.name), ["long_or", "ok_sum", "after", "after_huge"])
        XCTAssertTrue(reason(set, "deep").contains("nested too deeply"))
        XCTAssertTrue(reason(set, "not_chain").contains("nested too deeply"))
        XCTAssertTrue(reason(set, "long_sum").contains("too complex"))
        XCTAssertTrue(reason(set, "too_long").contains("too long"))
        XCTAssertTrue(reason(set, "huge_parens").contains("nested too deeply"))
        XCTAssertEqual(set.names(Array(repeating: 0, count: 150)), ["long_or", "ok_sum", "after", "after_huge"])
        XCTAssertEqual(set.names(Array(repeating: 0, count: 250)), ["ok_sum", "after", "after_huge"])

        let nestedHex = "{ 41 " + String(repeating: "( 42 ", count: 20) + String(repeating: "| 43 ) ", count: 20) + "}"
        let hexSet = YaraRuleSet(source: "rule h { strings: $a = \(nestedHex) condition: $a }", origin: "test")
        XCTAssertTrue(reason(hexSet, "h").contains("too deeply"), reason(hexSet, "h"))
    }

    func testGarbageNeverCrashes() {
        let noise = YaraFixture.noise(20_000, seed: 7)
        let inputs = [
            String(decoding: noise, as: UTF8.self),
            String(repeating: "rule { } condition: $ ", count: 500),
            String(repeating: "{", count: 5000),
            "rule a { strings: $a = { 41 42",
            "rule a { condition: \"unterminated",
            "rule a { condition: true } /* never closed",
            "rule a : { condition: true }",
            "private",
            "rule a { condition: for any i in (1..10) : }",
        ]
        for input in inputs {
            let set = YaraRuleSet(source: input, origin: "test")
            XCTAssertEqual(set.activeRuleCount, set.rules.filter { !$0.isPrivate }.count)
            _ = set.scan(Data(noise.prefix(4096)))
        }
        XCTAssertEqual(YaraRuleSet(source: "rule a { condition: true } /* never closed", origin: "t").rules.map(\.name), ["a"])
    }

    // MARK: Limits

    func testMatchesPerStringAreCapped() {
        let set = YaraRuleSet(source: #"rule many { strings: $a = "A" condition: #a == 1000 }"#, origin: "test")
        let result = set.scanDetailed(Data(repeating: 0x41, count: 5000))
        XCTAssertEqual(result.matches.map(\.name), ["many"])
        XCTAssertTrue(result.notes.contains { $0.contains("more than 1000") }, "\(result.notes)")

        let small = set.scanDetailed(Data(repeating: 0x41, count: 5000), limits: YaraScanLimits(maxMatchesPerString: 10))
        XCTAssertEqual(small.matches, [])
    }

    func testHostileBacktrackingIsBounded() {
        let source = #"""
        rule hostile { strings: $a = { 41 [0-200] 41 [0-200] 41 [0-200] 41 [0-200] 42 } condition: $a }
        rule hostile_unbounded { strings: $b = { 41 [-] 41 [-] 41 [-] 43 } condition: $b }
        rule zeros { strings: $c = { 00 00 00 00 [0-100] F? } condition: $c }
        rule normal { strings: $d = "needle" condition: $d }
        """#
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.skipped, [])
        var data = [UInt8](repeating: 0x41, count: 256 << 10) + [UInt8](repeating: 0, count: 256 << 10)
        data += YaraFixture.bytes("needle")

        // Each pathological string runs out of its own budget; the others are still found.
        let start = Date()
        let result = set.scanDetailed(Data(data), limits: YaraScanLimits(maxStepsPerCandidate: 10_000,
                                                                         maxStepsPerString: 300_000,
                                                                         maxTotalSteps: 5_000_000))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertEqual(result.matches.map(\.name), ["normal"])
        XCTAssertTrue(result.notes.contains { $0.contains("too much work") }, "\(result.notes)")

        // The scan-wide budget is the last line of defence.
        let capped = set.scanDetailed(Data(data), limits: YaraScanLimits(maxStepsPerCandidate: 10_000,
                                                                         maxTotalSteps: 500_000))
        XCTAssertTrue(capped.notes.contains { $0.contains("work limit") }, "\(capped.notes)")
        XCTAssertFalse(capped.matches.contains { $0.name == "hostile" })
    }

    func testLoopLimit() {
        let set = YaraRuleSet(source: "rule big { condition: for any i in (0..10000000) : ( i == 5 ) }\nrule ok { condition: true }",
                              origin: "test")
        let result = set.scanDetailed(Data([1]))
        XCTAssertEqual(result.matches.map(\.name), ["ok"])
        XCTAssertTrue(result.notes.contains { $0.contains("too long") })
        let generous = set.scanDetailed(Data([1]), limits: YaraScanLimits(maxLoopIterations: 20_000_000))
        XCTAssertEqual(generous.matches.map(\.name), ["big", "ok"])
    }

    func testLinearScanLimit() {
        let set = YaraRuleSet(source: "rule late { strings: $a = { 4? 5? ?A } condition: $a }", origin: "test")
        let data = [UInt8](repeating: 0, count: 3000) + [0x41, 0x5A, 0x5A]
        XCTAssertEqual(set.names(data), ["late"])
        let limited = set.scanDetailed(Data(data), limits: YaraScanLimits(linearScanBytes: 1000))
        XCTAssertEqual(limited.matches, [])
        XCTAssertFalse(limited.notes.isEmpty)
    }

    func testPerformance300RulesOn2MB() {
        var rng = YaraFixture.noise(300 * 64, seed: 99).makeIterator()
        func randomHex(_ count: Int) -> [UInt8] { (0..<count).map { _ in rng.next() ?? 0x5A } }
        func hexText(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

        var source = "import \"hash\"\nprivate rule Macho { condition: uint32(0) == 0xfeedfacf or uint32(0) == 0xcffaedfe }\n"
        var planted: [UInt8] = []
        var plantedNames: [String] = []
        for index in 0..<300 {
            let a = randomHex(12), b = randomHex(14), c = randomHex(10)
            let strings = """
                $a1 = { \(hexText(Array(a[0..<6]))) ?? \(hexText(Array(a[7...]))) }
                $a2 = { \(hexText(Array(b[0..<7]))) [0-4] \(hexText(Array(b[7...]))) }
                $b1 = "\(c.map { String(UnicodeScalar(UInt8(0x61) + $0 % 26)) }.joined())" nocase
            """
            let condition: String
            switch index % 4 {
            case 0: condition = "Macho and 2 of them"
            case 1: condition = "Macho and any of ($a*)"
            case 2: condition = "filesize < 10MB and all of them"
            default: condition = "Macho and #a1 > 0 and $b1"
            }
            source += "rule XProtect_Gen_\(index) : gen { meta: description = \"Gen.\(index)\" strings:\n\(strings)\n condition: \(condition) }\n"
            if index % 100 == 1 {
                planted += a + [0x2E] + b
                plantedNames.append("XProtect_Gen_\(index)")
            }
        }
        source += "rule XProtect_Gen_Hash { condition: hash.sha1(0, filesize) == \"0000000000000000000000000000000000000000\" }\n"

        let compileStart = Date()
        let set = YaraRuleSet(source: source, origin: "perf")
        let compileTime = Date().timeIntervalSince(compileStart)
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.activeRuleCount, 301)

        var data = YaraFixture.machO(YaraFixture.noise(2 << 20, seed: 1234))
        data.replaceSubrange(100_000..<100_000 + planted.count, with: planted)
        let scanStart = Date()
        let result = set.scanDetailed(Data(data))
        let scanTime = Date().timeIntervalSince(scanStart)
        XCTAssertEqual(result.matches.map(\.name), plantedNames)
        XCTAssertEqual(result.notes, [])
        print("YARA performance: compile \(String(format: "%.3f", compileTime)) s, scan 2 MB with 301 rules \(String(format: "%.3f", scanTime)) s")
        XCTAssertLessThan(compileTime, 3)
        XCTAssertLessThan(scanTime, 3)
    }

    func testWildcardRuleSetsAreCapped() {
        var source = (0..<1_100).map { "private rule r\($0) { condition: filesize == \($0) }" }.joined(separator: "\n")
        source += "\nrule too_wide { condition: any of (r*) }"
        source += "\nrule narrow { condition: any of (r10*) }"
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertTrue(reason(set, "too_wide").contains("more than 1000 rules"), reason(set, "too_wide"))
        // r10, r100…r109, r1000…r1099
        XCTAssertEqual(set.names([UInt8](repeating: 0, count: 105)), ["narrow"])
        XCTAssertEqual(set.names([UInt8](repeating: 0, count: 1_050)), ["narrow"])
        XCTAssertEqual(set.names([UInt8](repeating: 0, count: 11)), [])
    }

    func testRulesUsedInsideLoopsKeepTheirOwnLoopState() {
        let source = """
        rule outer { condition: for any i in (1..3) : ( inner and i == 3 ) and for all k in (7..8) : ( later and k > 6 ) }
        rule inner { condition: for all i in (1..2) : ( i > 0 ) }
        private rule later { condition: for any i in (100..101) : ( i == 101 ) }
        """
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.names([0]), ["outer", "inner"])
    }

    func testLargeRuleFile() {
        var source = "import \"hash\"\n"
        for index in 0..<3_000 {
            source += "rule big_\(index) : t { meta: description = \"Big \(index)\" strings: $a = \"marker-\(index)-x\" "
            source += "$b = { \(YaraFixture.hex("id\(index)")) ?? 7A } condition: $a or ($b and filesize < 1MB) }\n"
        }
        let start = Date()
        let set = YaraRuleSet(source: source, origin: "test")
        let compileTime = Date().timeIntervalSince(start)
        XCTAssertEqual(set.activeRuleCount, 3_000)
        var data = YaraFixture.noise(512 << 10, seed: 5)
        data += YaraFixture.bytes(" marker-1234-x id77.z ")
        let scanStart = Date()
        XCTAssertEqual(set.names(data), ["big_77", "big_1234"])
        let scanTime = Date().timeIntervalSince(scanStart)
        print("YARA performance: compile 3000 rules \(String(format: "%.3f", compileTime)) s, scan 512 KB \(String(format: "%.3f", scanTime)) s")
        XCTAssertLessThan(compileTime, 5)
        XCTAssertLessThan(scanTime, 3)
    }

    func testConcurrentScansShareOneRuleSet() {
        let set = YaraRuleSet(source: yaraXProtectSample, origin: "test")
        let inputs = [YaraFixture.machO("zsh connectToServer"), YaraFixture.bytes("abc"), YaraFixture.pe(YaraFixture.bytes("evil"))]
        let expected = inputs.map { set.names($0) }
        let results = UnsafeMutableBufferPointer<[String]>.allocate(capacity: 60)
        results.initialize(repeating: [])
        defer { results.deallocate() }
        DispatchQueue.concurrentPerform(iterations: 60) { index in
            results[index] = set.names(inputs[index % 3])
        }
        for index in 0..<60 { XCTAssertEqual(results[index], expected[index % 3]) }
    }

    // MARK: Files

    func testScanFile() throws {
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("spruce-yara-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let file = directory + "/sample.bin"
        let contents = YaraFixture.bytes("....needle") + [UInt8](repeating: 0x20, count: 5000) + YaraFixture.bytes("late-marker")
        XCTAssertTrue(FileManager.default.createFile(atPath: file, contents: Data(contents)))
        let empty = directory + "/empty.bin"
        XCTAssertTrue(FileManager.default.createFile(atPath: empty, contents: Data()))

        let set = YaraRuleSet(source: #"""
        rule early { strings: $n = "needle" condition: $n and filesize > 5000 }
        rule late { strings: $l = "late-marker" condition: $l }
        rule empty_file { condition: filesize == 0 }
        """#, origin: "test")

        XCTAssertEqual(set.scanFile(atPath: file, maxBytes: 100).map(\.name), ["early"])
        XCTAssertEqual(set.scanFile(atPath: file, maxBytes: 1 << 20).map(\.name), ["early", "late"])
        let detailed = set.scanFileDetailed(atPath: file, maxBytes: 100)
        XCTAssertEqual(detailed?.bytesScanned, 100)
        XCTAssertEqual(detailed?.fileSize, contents.count)
        XCTAssertEqual(set.scanFile(atPath: empty, maxBytes: 100).map(\.name), ["empty_file"])

        let link = directory + "/link.bin"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: file)
        XCTAssertNil(set.scanFileDetailed(atPath: link, maxBytes: 100), "symlinks are not followed")
        XCTAssertNil(set.scanFileDetailed(atPath: directory, maxBytes: 100))
        XCTAssertNil(set.scanFileDetailed(atPath: directory + "/missing", maxBytes: 100))
        XCTAssertEqual(set.scanFile(atPath: directory + "/missing", maxBytes: 100), [])

        let prefix = YaraRuleSet.readPrefix(ofFile: file, maxBytes: 10)
        XCTAssertEqual(prefix?.data, Data(YaraFixture.bytes("....needle")))
        XCTAssertEqual(prefix?.fileSize, contents.count)
        XCTAssertNil(YaraRuleSet.readPrefix(ofFile: link, maxBytes: 10))

        let fromData = YaraRuleSet(data: Data(#"rule d { strings: $a = "needle" condition: $a }"#.utf8) + Data([0xFF, 0xFE]),
                                   origin: "feed")
        XCTAssertEqual(fromData.rules.map(\.name), ["d"])
        XCTAssertEqual(fromData.scanFile(atPath: file, maxBytes: 100).map(\.origin), ["feed"])

        let fifo = directory + "/pipe"
        if mkfifo(fifo, 0o644) == 0 {
            XCTAssertNil(set.scanFileDetailed(atPath: fifo, maxBytes: 100), "special files are skipped without blocking")
        }
    }
}
