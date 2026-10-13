import Foundation
import XCTest
@testable import SpruceCore

final class YaraMatchingTests: XCTestCase {
    private let xprotect = YaraRuleSet(source: yaraXProtectSample, origin: "Apple XProtect")

    // MARK: XProtect-style rules

    func testMachOStringRule() {
        let hit = YaraFixture.machO("....connectToServer....zsh....")
        XCTAssertEqual(xprotect.names(hit), ["XProtect_MACOS_644e18d"])
        let match = xprotect.scan(Data(hit)).first
        XCTAssertEqual(match?.origin, "Apple XProtect")
        XCTAssertEqual(match?.description, "MACOS.644e18d")
        XCTAssertEqual(match?.meta("description"), .text("MACOS.644e18d"))
        // Same strings without the Mach-O header, or only one of three strings.
        XCTAssertEqual(xprotect.names(YaraFixture.bytes("....connectToServer....zsh....")), [])
        XCTAssertEqual(xprotect.names(YaraFixture.machO("....connectToServer....")), [])
        XCTAssertEqual(xprotect.names(YaraFixture.machO("/tmp/.helper zsh")), ["XProtect_MACOS_644e18d"])
        // Every Mach-O magic number counts.
        for magic: [UInt8] in [[0xFE, 0xED, 0xFA, 0xCE], [0xCE, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA]] {
            XCTAssertEqual(xprotect.names(magic + YaraFixture.bytes("zsh connectToServer")), ["XProtect_MACOS_644e18d"])
        }
    }

    func testAnonymousStringsWildcardAndBoundedJump() {
        XCTAssertEqual(xprotect.names(YaraFixture.machO("Method_Name adload")), ["XProtect_AdLoad_B_2"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO("MethodXName ad\u{0}\u{0}\u{0}load")), ["XProtect_AdLoad_B_2"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO("MethodXName ad\u{0}\u{0}\u{0}\u{0}load")), [], "jump longer than 3")
        XCTAssertEqual(xprotect.names(YaraFixture.machO("MethodName adload")), [], "?? needs exactly one byte")
        XCTAssertEqual(xprotect.match(YaraFixture.machO("Method_Name adload")).first?.tags, ["dropper"])
        // filesize < 100KB
        let big = YaraFixture.machO(YaraFixture.bytes("Method_Name adload") + [UInt8](repeating: 0x20, count: 110_000))
        XCTAssertEqual(xprotect.names(big), [])
        XCTAssertEqual(xprotect.names(YaraFixture.machO("Method_Name adload"), fileSize: 200_000), [])
    }

    func testNibbleWildcards() {
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x72, 0x77, 0x35, 0x41, 0x42, 0x43])), ["XProtect_MACOS_Nibbles"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x82, 0x77, 0x35, 0x41, 0x42, 0x43])), [])
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x4A, 0x5B, 0xC4, 0x44, 0x45, 0x46, 0x47])), ["XProtect_MACOS_Nibbles"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x4A, 0x5B, 0xC5, 0x44, 0x45, 0x46, 0x47])), [])
    }

    func testJumpsAndAlternativesRule() {
        let j1 = YaraFixture.bytes("AAAA") + [0x00] + YaraFixture.bytes("BBBB")
        let j2 = YaraFixture.bytes("CCCC") + [UInt8](repeating: 0x2E, count: 35) + YaraFixture.bytes("DDDD")
        let j3 = YaraFixture.bytes("EEEE") + [UInt8](repeating: 0x2E, count: 5000) + YaraFixture.bytes("FFFF")
        XCTAssertEqual(xprotect.names(YaraFixture.machO(j1 + j2)), ["XProtect_MACOS_Jumps"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO(j2 + j3)), ["XProtect_MACOS_Jumps"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO(j1 + j3)), ["XProtect_MACOS_Jumps"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO(j1)), [])
        let shortJump = YaraFixture.bytes("CCCC") + [UInt8](repeating: 0x2E, count: 29) + YaraFixture.bytes("DDDD")
        XCTAssertEqual(xprotect.names(YaraFixture.machO(j1 + shortJump)), [])
        let longJump = YaraFixture.bytes("AAAA") + [0, 0, 0] + YaraFixture.bytes("BBBB")
        XCTAssertEqual(xprotect.names(YaraFixture.machO(longJump + shortJump)), [])
        // Unbounded jump in reverse order doesn't count.
        let reversed = YaraFixture.bytes("FFFF....EEEE")
        XCTAssertEqual(xprotect.names(YaraFixture.machO(j1 + reversed)), [])

        // ( 19 | 17 ) and ( 90 90 | 90 90 90 | 90 90 90 90 )
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x47, 0x47, 0x19, 0x48, 0x48, 0x90, 0x90, 0x49])), ["XProtect_MACOS_Jumps"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x47, 0x47, 0x17, 0x48, 0x48, 0x90, 0x90, 0x90, 0x90, 0x49])),
                       ["XProtect_MACOS_Jumps"])
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x47, 0x47, 0x18, 0x48, 0x48, 0x90, 0x90, 0x49])), [])
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x47, 0x47, 0x19, 0x48, 0x48, 0x90, 0x49])), [])
        XCTAssertEqual(xprotect.names(YaraFixture.machO([0x47, 0x47, 0x19, 0x48, 0x48] + [UInt8](repeating: 0x90, count: 5) + [0x49])), [])
    }

    func testHashRule() {
        XCTAssertEqual(xprotect.names(YaraFixture.bytes("abc")), ["XProtect_MACOS_Hash"])
        XCTAssertEqual(xprotect.names(YaraFixture.bytes("abd")), [])
        // Only the start of the file was read: the whole-file hash is unknown.
        XCTAssertEqual(xprotect.names(YaraFixture.bytes("abc"), fileSize: 10), [])
    }

    func testScriptRule() {
        XCTAssertEqual(xprotect.names(YaraFixture.bytes("#!/bin/zsh\ncurl ${A} ${B}\n")), ["XProtect_MACOS_Script"])
        XCTAssertEqual(xprotect.names(YaraFixture.bytes("#!/bin/zsh\ncurl ${A}\n")), [], "#b2 > 1")
        XCTAssertEqual(xprotect.names(YaraFixture.bytes(" #!/bin/zsh\ncurl ${A} ${B}\n")), [], "$shebang at 0")
        XCTAssertEqual(xprotect.names(YaraFixture.bytes("#!/bin/zsh\ncurl ${A} ${B} safe-marker\n")), [], "not any of ($c*)")
    }

    func testPERule() {
        XCTAssertEqual(xprotect.names(YaraFixture.pe(YaraFixture.bytes("evil"))), ["XProtect_PE_Thing"])
        var broken = YaraFixture.pe(YaraFixture.bytes("evil"))
        broken[0x80] = 0x51
        XCTAssertEqual(xprotect.names(broken), [])
        var outOfRange = YaraFixture.pe(YaraFixture.bytes("evil"))
        outOfRange[0x3D] = 0x10 // e_lfanew points past the end: uint32() is undefined.
        XCTAssertEqual(xprotect.names(outOfRange), [])
        XCTAssertEqual(xprotect.names(YaraFixture.bytes("MZ evil")), [])
    }

    // MARK: Hex strings

    func testHexMatchingDetails() {
        let data = YaraFixture.bytes("xxABCDxxAB\u{1}CDxxAZCD")
        XCTAssertTrue(yaraHolds("#a == 2", strings: "$a = { 41 ?? 43 44 }", data))
        XCTAssertTrue(yaraHolds("#a == 1 and @a[1] == 8", strings: "$a = { 41 42 ~43 43 }", data))
        XCTAssertTrue(yaraHolds("#a == 3", strings: "$a = { 41 ( 42 | 42 01 | 5A ) 43 }", data))
        let jumps = YaraFixture.bytes("ACD.ABCD.AB\u{1}CD")
        XCTAssertTrue(yaraHolds("#a == 2 and !a[1] == 3 and !a[2] == 4 and @a[2] == 4", strings: "$a = { 41 [0-1] 43 44 }", jumps))
        // Alternatives before the atom are matched backwards.
        let more = data + YaraFixture.bytes("ABC")
        XCTAssertTrue(yaraHolds("#a == 3 and @a[1] == 2 and @a[2] == 15 and @a[3] == 19", strings: "$a = { ( 41 42 | 41 5A ) 43 }", more))
        // Only alternatives: each branch prefix becomes an atom.
        XCTAssertTrue(yaraHolds("#a == 3 and @a[1] == 2 and @a[2] == 15 and !a[2] == 2 and @a[3] == 19",
                                strings: "$a = { ( 41 42 43 | 41 5A ) }", more))
        // No literal byte at all: found by a linear scan.
        XCTAssertTrue(yaraHolds("#a == 3", strings: "$a = { 4? ?2 }", YaraFixture.bytes("AB.AB.QR.BR")))
        XCTAssertTrue(yaraHolds("$a at 0 and #a == 1", strings: "$a = { ?? ( 41 | 42 ) }", YaraFixture.bytes(".A")))
        // Atom in the middle with variable parts on both sides.
        XCTAssertTrue(yaraHolds("@a[1] == 1 and !a[1] == 11", strings: "$a = { 30 [1-3] 61 62 63 64 [1-3] 39 }",
                                YaraFixture.bytes("X0..abcd...9X")))
        XCTAssertTrue(yaraHolds("$a and $b", strings: "$a = { 00 00 }\n$b = { FF }", [0x01, 0x00, 0x00, 0xFF]))
    }

    func testChainedSegments() {
        let gap = [UInt8](repeating: 0x2E, count: 10_000)
        let data = YaraFixture.bytes("ABC") + gap + YaraFixture.bytes("DEF") + gap + YaraFixture.bytes("GHI")
        XCTAssertTrue(yaraHolds("#a == 1 and @a[1] == 0 and !a[1] == 20009", strings: "$a = { 41 42 43 [-] 44 45 46 [10000-] 47 48 49 }", data))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = { 41 42 43 [-] 44 45 46 [10001-] 47 48 49 }", data))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = { 41 42 43 [9000-11000] 44 45 46 }", data))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = { 41 42 43 [300-400] 44 45 46 }", data))
        // Every start before the second part is its own match.
        XCTAssertTrue(yaraHolds("#a == 3", strings: "$a = { 41 [-] 42 }", YaraFixture.bytes("AxAxAxB")))
    }

    // MARK: Text strings and modifiers

    func testTextModifiers() {
        let wide = YaraFixture.wide("evil")
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\"", YaraFixture.bytes("so evil")))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\"", wide))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" wide", wide))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\" wide", YaraFixture.bytes("evil")))
        XCTAssertTrue(yaraHolds("#a == 2", strings: "$a = \"evil\" ascii wide", YaraFixture.bytes("evil ") + wide))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" nocase", YaraFixture.bytes("so EvIl")))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\"", YaraFixture.bytes("so EvIl")))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" wide nocase", YaraFixture.wide("EVIL")))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"a1-B\" nocase", YaraFixture.bytes("A1-b")))

        // fullword
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" fullword", YaraFixture.bytes("so evil.")))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" fullword", YaraFixture.bytes("evil")))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\" fullword", YaraFixture.bytes("devil")))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\" fullword", YaraFixture.bytes("evil2")))
        XCTAssertTrue(yaraHolds("#a == 1 and @a[1] == 6", strings: "$a = \"evil\" fullword", YaraFixture.bytes("evils evil")))
        let wordWide = YaraFixture.wide("d") + wide
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\" wide fullword", wordWide))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" wide fullword", [0x20, 0x00] + wide + [0x2E, 0x00]))

        // xor
        let key: UInt8 = 0x5A
        let xored = Array("evil".utf8).map { $0 ^ key }
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" xor", [0x00] + xored + [0x00]))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" xor", YaraFixture.bytes("evil")), "key 0 is the plain text")
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\" xor(0x01-0xff)", YaraFixture.bytes("evil")))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" xor(0x01-0xff)", xored))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\" xor(0x01-0x10)", xored))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" xor(90)", xored))
        XCTAssertTrue(yaraHolds("$a", strings: "$a = \"evil\" xor wide", wide.map { $0 ^ key }))
        XCTAssertFalse(yaraHolds("$a", strings: "$a = \"evil\" xor fullword", YaraFixture.bytes("a") + xored.map { $0 ^ key ^ 0x01 }))
        XCTAssertTrue(yaraHolds("$a and $b", strings: "$a = \"evil\" private\n$b = { 65 76 } private", YaraFixture.bytes("evil")))
    }

    // MARK: Quantifiers, counts and positions

    func testQuantifiers() {
        let strings = """
            $a1 = "alpha"
            $a2 = "apple"
            $b1 = "beta"
            $c1 = "gamma"
        """
        let data = YaraFixture.bytes("alpha beta apple")
        XCTAssertTrue(yaraHolds("any of them", strings: strings, data))
        XCTAssertFalse(yaraHolds("all of them", strings: strings, data))
        XCTAssertFalse(yaraHolds("none of them", strings: strings, data))
        XCTAssertTrue(yaraHolds("none of ($c*)", strings: strings, data))
        XCTAssertTrue(yaraHolds("3 of them", strings: strings, data))
        XCTAssertFalse(yaraHolds("4 of them", strings: strings, data))
        XCTAssertTrue(yaraHolds("0 of ($c1)", strings: strings, data))
        XCTAssertFalse(yaraHolds("0 of them", strings: strings, data))
        XCTAssertTrue(yaraHolds("75% of them", strings: strings, data))
        XCTAssertFalse(yaraHolds("76% of them", strings: strings, data))
        XCTAssertTrue(yaraHolds("all of ($a*)", strings: strings, data))
        XCTAssertTrue(yaraHolds("2 of ($a1,$b1,$c1)", strings: strings, data))
        XCTAssertFalse(yaraHolds("2 of ($a1,$c1)", strings: strings, data))
        XCTAssertTrue(yaraHolds("all of ($a*, $b1)", strings: strings, data))
        XCTAssertTrue(yaraHolds("(not any of ($c*))", strings: strings, data))
        XCTAssertTrue(yaraHolds("any of ($a*) at 0", strings: strings, data))
        XCTAssertFalse(yaraHolds("all of ($a*) at 0", strings: strings, data))
        XCTAssertTrue(yaraHolds("all of ($a*, $b1) in (0..20)", strings: strings, data))
        XCTAssertFalse(yaraHolds("all of ($a*, $b1) in (0..10)", strings: strings, data))
        XCTAssertTrue(yaraHolds("1 + 1 == 2 and (1 + 1) of ($a*)", strings: strings, data))
    }

    func testCountsOffsetsAndLengths() {
        let strings = """
            $a = "ab"
            $b = { 61 [0-2] 63 }
        """
        let data = YaraFixture.bytes("ab..ab..ab.abc")
        XCTAssertTrue(yaraHolds("#a == 4", strings: strings, data))
        XCTAssertTrue(yaraHolds("#a > 3 and #a < 5 and #a >= 4 and #a <= 4 and #a != 3", strings: strings, data))
        XCTAssertTrue(yaraHolds("#a in (0..5) == 2", strings: strings, data))
        XCTAssertTrue(yaraHolds("#a in (5..100) == 2", strings: strings, data))
        XCTAssertTrue(yaraHolds("@a[1] == 0 and @a[2] == 4 and @a[4] == 11 and @a == 0", strings: strings, data))
        XCTAssertTrue(yaraHolds("!a[1] == 2 and !b == 3 and @b[1] == 11", strings: strings, data))
        XCTAssertTrue(yaraHolds("not defined @a[5] and not defined @a[0] and not defined !a[9]", strings: strings, data))
        XCTAssertTrue(yaraHolds("$a at 4 and not $a at 5 and $a at 2 + 2", strings: strings, data))
        XCTAssertTrue(yaraHolds("$a in (1..4) and not $a in (1..3) and $b in (10..20)", strings: strings, data))
        XCTAssertTrue(yaraHolds("#b == 1 and #missing_safe == 0", strings: strings + "\n$missing_safe = \"zz\"", data))
    }

    func testForLoops() {
        let strings = """
            $a = "ab"
            $b = "cd"
            $c = "zz"
        """
        let data = YaraFixture.bytes("ab cd ab cd ab")
        XCTAssertTrue(yaraHolds("for all i in (1..#a) : ( @a[i] < 100 )", strings: strings, data))
        XCTAssertFalse(yaraHolds("for all i in (1..#a) : ( @a[i] < 10 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for any i in (1..#a) : ( @a[i] == 6 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for none i in (1..#a) : ( @a[i] == 7 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for 2 i in (1..#a) : ( @a[i] > 0 )", strings: strings, data))
        XCTAssertFalse(yaraHolds("for 3 i in (1..#a) : ( @a[i] > 0 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for 50% i in (1..4) : ( i > 2 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for any i in (0, 3, 6) : ( uint8(i) == 0x63 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for all i in (\"x\", \"y\") : ( i != \"z\" )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for all i in (5..1) : ( false )", strings: strings, data), "an empty range is vacuously true")
        XCTAssertFalse(yaraHolds("for any i in (5..1) : ( true )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for any i in (1..3) : ( for any j in (1..3) : ( i * j == 6 ) )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for any of ($a, $b) : ( $ at 3 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for all of ($a, $b) : ( # >= 2 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for 2 of them : ( @[1] < 4 or ! > 1 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for any of them : ( # == 3 and @[3] == 12 )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for none of ($c) : ( $ )", strings: strings, data))
        XCTAssertTrue(yaraHolds("for all of them : ( $ in (0..20) or # == 0 )", strings: strings, data))
        XCTAssertFalse(yaraHolds("for any i in (1..filesize) : ( false )", strings: strings, data))
    }

    // MARK: Numbers and data

    func testIntegerReads() {
        let data: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0xFF]
        XCTAssertTrue(yaraHolds("uint8(0) == 1 and uint8(4) == 255 and int8(4) == -1", data))
        XCTAssertTrue(yaraHolds("uint16(0) == 0x0201 and uint16be(0) == 0x0102", data))
        XCTAssertTrue(yaraHolds("uint32(0) == 0x04030201 and uint32be(0) == 0x01020304", data))
        XCTAssertTrue(yaraHolds("int16(3) == -252 and int16be(3) == 0x04FF and uint8be(1) == 2", data))
        XCTAssertTrue(yaraHolds("int32(1) == -16514302 and int32be(0) == 16909060", data))
        XCTAssertTrue(yaraHolds("not defined uint32(2) and not defined uint8(5) and not defined uint8(-1)", data))
        XCTAssertTrue(yaraHolds("uint8(uint8(0)) == 2 and uint8(uint8(uint8(0))) == 3", data))
        XCTAssertFalse(yaraHolds("uint32(2) == 0", data))
    }

    func testArithmeticBitwiseAndComparisons() {
        let data = YaraFixture.bytes("0123456789")
        XCTAssertTrue(yaraHolds("(1 + 2) * 3 == 9 and 10 \\ 3 == 3 and 10 % 3 == 1 and -7 \\ 2 == -3", data))
        XCTAssertTrue(yaraHolds("0x0F & 0xFC == 0x0C and 1 << 4 == 16 and 256 >> 4 == 16 and 7 ^ 2 == 5 and 4 | 1 == 5", data))
        XCTAssertTrue(yaraHolds("~0 == -1 and -5 < 0 and - -5 == 5 and 1 << 64 == 0", data))
        XCTAssertTrue(yaraHolds("not defined (1 \\ 0) and not defined (1 % 0) and not defined (1 << -1)", data))
        XCTAssertTrue(yaraHolds("filesize == 10 and filesize * 2 == 20 and filesize - 11 == -1", data))
        XCTAssertTrue(yaraHolds("1.5 + 1 == 2.5 and 3 \\ 2.0 == 1.5 and 2.5 > 2", data))
        XCTAssertTrue(yaraHolds("\"abc\" == \"abc\" and \"abc\" != \"abd\" and \"abc\" < \"abd\"", data))
        XCTAssertTrue(yaraHolds("\"Hello\" icontains \"ELL\" and not (\"Hello\" contains \"ELL\")", data))
        XCTAssertTrue(yaraHolds("\"Hello\" iendswith \"LO\" and \"Hello\" endswith \"lo\" and \"Hello\" iequals \"hello\"", data))
        XCTAssertTrue(yaraHolds("9223372036854775807 + 1 < 0", data), "integers wrap like YARA's int64")
        XCTAssertTrue(yaraHolds("filesize > 5MB", data, fileSize: 6 << 20), "filesize is the real size")
    }

    func testUndefinedSemantics() {
        let data: [UInt8] = [1, 2]
        XCTAssertFalse(yaraHolds("uint32(100) == 1", data))
        XCTAssertFalse(yaraHolds("not (uint32(100) == 1)", data), "not undefined stays undefined")
        XCTAssertTrue(yaraHolds("uint32(100) == 1 or true", data))
        XCTAssertFalse(yaraHolds("uint32(100) == 1 and true", data))
        XCTAssertTrue(yaraHolds("not (uint32(100) == 1 and true)", data), "and turns undefined into false")
        XCTAssertTrue(yaraHolds("defined uint8(0) and not defined uint32(0)", data))
    }

    // MARK: Rules

    func testPrivateRulesAndReferences() {
        let source = #"""
        private rule small { condition: filesize < 10 }
        rule tiny_marker { strings: $m = "mark" condition: small and $m }
        rule not_small { condition: not small }
        rule either { condition: any of (tiny_marker, not_small) }
        """#
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.names(YaraFixture.bytes("mark")), ["tiny_marker", "either"])
        XCTAssertEqual(set.names(YaraFixture.bytes("mark 123456789")), ["not_small", "either"])
    }

    func testGlobalRulesGateEverything() {
        let source = """
        global rule size_cap { condition: filesize < 100 }
        private global rule needs_marker { strings: $m = "ok" condition: $m }
        rule anything { condition: true }
        """
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.skipped, [])
        XCTAssertEqual(set.names(YaraFixture.bytes("ok")), ["size_cap", "anything"])
        XCTAssertEqual(set.names(YaraFixture.bytes("no")), [])
        XCTAssertEqual(set.names(YaraFixture.bytes("ok") + [UInt8](repeating: 0, count: 200)), [])
    }

    func testScanWithDataSliceAndOrigin() {
        let set = YaraRuleSet(source: #"rule r { strings: $a = "needle" condition: $a at 0 }"#, origin: "Spruce threat feed")
        let full = Data(YaraFixture.bytes("xxneedle"))
        let slice = full[2...]
        XCTAssertEqual(set.scan(slice).map(\.origin), ["Spruce threat feed"])
        let result = set.scanDetailed(slice, fileSize: 100)
        XCTAssertEqual(result.bytesScanned, 6)
        XCTAssertEqual(result.fileSize, 100)
        XCTAssertEqual(result.notes, [])
    }
}

private extension YaraRuleSet {
    func match(_ bytes: [UInt8]) -> [YaraRuleMatch] { scan(Data(bytes)) }
}
