import Foundation
import XCTest
@testable import SpruceCore

/// Synthetic file contents for YARA engine tests.
enum YaraFixture {
    /// A 64-bit Mach-O magic number, zero padding, then `body`.
    static func machO(_ body: [UInt8] = [], padding: Int = 60) -> [UInt8] {
        [0xCF, 0xFA, 0xED, 0xFE] + [UInt8](repeating: 0, count: padding) + body
    }

    static func machO(_ text: String) -> [UInt8] { machO(Array(text.utf8)) }

    /// A minimal PE file: "MZ", e_lfanew (0x3C) pointing at "PE\0\0" at 0x80, then `body`.
    static func pe(_ body: [UInt8] = []) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 0x84)
        bytes[0] = 0x4D
        bytes[1] = 0x5A
        bytes[0x3C] = 0x80
        bytes[0x80] = 0x50
        bytes[0x81] = 0x45
        return bytes + body
    }

    static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    /// UTF-16LE form of ASCII text, as YARA's `wide` modifier expects.
    static func wide(_ text: String) -> [UInt8] { text.utf8.flatMap { [$0, UInt8(0)] } }

    /// Deterministic pseudo-random bytes (xorshift).
    static func noise(_ count: Int, seed: UInt64 = 0x9E3779B97F4A7C15) -> [UInt8] {
        var state = seed
        var out = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            out[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        return out
    }

    /// Text for the hex bytes of `text` ("ab" → "61 62").
    static func hex(_ text: String) -> String {
        text.utf8.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

extension YaraRuleSet {
    /// Names of the rules that match `bytes`.
    func names(_ bytes: [UInt8], fileSize: Int? = nil) -> [String] {
        scan(Data(bytes), fileSize: fileSize).map(\.name)
    }
}

/// Compiles one rule with `condition` (and optional `strings`) and reports whether it matches.
/// Fails the test when the rule doesn't load.
func yaraHolds(_ condition: String, strings: String = "", _ bytes: [UInt8], fileSize: Int? = nil,
               file: StaticString = #filePath, line: UInt = #line) -> Bool {
    var source = "rule t {\n"
    if !strings.isEmpty { source += "strings:\n\(strings)\n" }
    source += "condition:\n\(condition)\n}\n"
    let set = YaraRuleSet(source: source, origin: "test")
    XCTAssertEqual(set.skipped, [], "rule didn't load: \(condition)", file: file, line: line)
    return set.scan(Data(bytes), fileSize: fileSize).count == 1
}

/// XProtect-style rules in the shapes Apple's XProtect.yara uses.
let yaraXProtectSample = #"""
import "hash"

private rule Macho
{
    meta:
        description = "private rule to match Mach-O binaries"
    condition:
        uint32(0) == 0xfeedface or uint32(0) == 0xcefaedfe or uint32(0) == 0xfeedfacf or uint32(0) == 0xcffaedfe or uint32(0) == 0xcafebabe or uint32(0) == 0xbebafeca
}

private rule PE
{
    meta:
        description = "private rule to match PE binaries"
    condition:
        uint16(0) == 0x5a4d and uint32(uint32(0x3C)) == 0x4550
}

rule XProtect_MACOS_644e18d
{
    meta:
        description = "MACOS.644e18d"
    strings:
        $a = { 63 6f 6e 6e 65 63 74 54 6f 53 65 72 76 65 72 }
        $b = { 2f 74 6d 70 2f 2e 68 65 6c 70 65 72 }
        $c = "zsh"
    condition:
        Macho and 2 of them
}

rule XProtect_AdLoad_B_2 : dropper
{
    meta:
        description = "AdLoad.B.2"
        xprotect_rule = true
        gk_first_launch_only = true
        match_type = 2
    strings:
        $ = { 4d 65 74 68 6f 64 ?? 4e 61 6d 65 }
        $ = { 61 64 [0-3] 6c 6f 61 64 }
    condition:
        Macho and filesize < 100KB and all of them
}

rule XProtect_MACOS_Nibbles
{
    meta:
        description = "MACOS.nibbles"
    strings:
        $a1 = { 7? 77 3? 41 42 43 }
        $a2 = { 4? 5? ?4 44 45 46 47 }
    condition:
        Macho and any of ($a*)
}

rule XProtect_MACOS_Jumps
{
    meta:
        description = "MACOS.jumps"
    strings:
        $j1 = { 41 41 41 41 [0 - 2] 42 42 42 42 }
        $j2 = { 43 43 43 43 [30 - 40] 44 44 44 44 }
        $j3 = { 45 45 45 45 [-] 46 46 46 46 }
        $alt = { 47 47 ( 19 | 17 ) 48 48 ( 90 90 | 90 90 90 | 90 90 90 90 ) 49 }
    condition:
        Macho and (2 of ($j1,$j2,$j3) or $alt)
}

rule XProtect_MACOS_Hash
{
    meta:
        description = "MACOS.hash"
    condition:
        filesize <= 40000 and hash.sha1(0, filesize) == "a9993e364706816aba3e25717850c26c9cd0d89d"
}

rule XProtect_MACOS_Script : script
{
    meta:
        description = "MACOS.script"
    strings:
        $shebang = "#!"
        $b1 = "curl"
        $b2 = "${"
        $c1 = "safe-marker"
    condition:
        $shebang at 0 and filesize < 200 and #b2 > 1 and $b1 and (not any of ($c*))
}

rule XProtect_PE_Thing
{
    strings:
        $a = "evil"
    condition:
        PE and $a
}
"""#
