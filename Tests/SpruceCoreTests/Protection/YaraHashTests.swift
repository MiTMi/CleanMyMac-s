import Foundation
import XCTest
@testable import SpruceCore

final class YaraHashTests: XCTestCase {
    private func hex(_ digest: (UnsafeRawBufferPointer) -> [UInt8], _ bytes: [UInt8]) -> String {
        bytes.withUnsafeBytes { ClutterHex.string(digest($0)) }
    }

    private func hex(_ digest: (UnsafeRawBufferPointer) -> [UInt8], _ text: String) -> String {
        hex(digest, Array(text.utf8))
    }

    func testMD5Vectors() {
        XCTAssertEqual(hex(YaraDigest.md5, ""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(hex(YaraDigest.md5, "abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(hex(YaraDigest.md5, "The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
        XCTAssertEqual(hex(YaraDigest.md5, "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "8215ef0796a20bcaaae116d3876c664a")
        XCTAssertEqual(hex(YaraDigest.md5, String(repeating: "1234567890", count: 8)), "57edf4a22be3c955ac49da2e2107b67a")
        XCTAssertEqual(hex(YaraDigest.md5, [UInt8](repeating: 0x61, count: 1_000_000)), "7707d6ae4e027c70eea2a935c2296f21")
    }

    func testSHA1Vectors() {
        XCTAssertEqual(hex(YaraDigest.sha1, ""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(hex(YaraDigest.sha1, "abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(hex(YaraDigest.sha1, "The quick brown fox jumps over the lazy dog"), "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")
        XCTAssertEqual(hex(YaraDigest.sha1, "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
        XCTAssertEqual(hex(YaraDigest.sha1, [UInt8](repeating: 0x61, count: 1_000_000)), "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
    }

    func testPaddingBoundaries() {
        // Digests of bytes (i % 251) around the 55/56/64-byte padding edges (from Python's hashlib).
        let expected: [(Int, String, String)] = [
            (55, "6912ee65fff2d9f9ce2508cddf8bcda0", "8ae2d46729cfe68ff927af5eec9c7d1b66d65ac2"),
            (56, "51fdd1acda72405dfdfa03fcb85896d7", "636e2ec698dac903498e648bd2f3af641d3c88cb"),
            (63, "48a6295221902e8e0938f773a7185e72", "6d942da0c4392b123528f2905c713a3ce28364bd"),
            (64, "b2d3f56bc197fd985d5965079b5e7148", "c6138d514ffa2135bfce0ed0b8fac65669917ec7"),
            (65, "8bd7053801c768420faf816fadba971c", "69bd728ad6e13cd76ff19751fde427b00e395746"),
            (119, "1c772251899a7ff007400b888d6b2042", "41c89d06001bab4ab78736b44efe7ce18ce6ae08"),
            (120, "b7ba1efc6022e9ed272f00b8831e26e6", "d3dbd653bd8597b7475321b60a36891278e6a04a"),
            (1000, "a24f1e3ef66950e1327f210e3997ba2c", "c9c960a0b925474fab83942cc27d504fc24ac37b"),
        ]
        for (length, md5, sha1) in expected {
            let bytes = (0..<length).map { UInt8($0 % 251) }
            XCTAssertEqual(hex(YaraDigest.md5, bytes), md5, "md5 of \(length) bytes")
            XCTAssertEqual(hex(YaraDigest.sha1, bytes), sha1, "sha1 of \(length) bytes")
        }
    }

    func testSHA256CRC32AndChecksum() {
        XCTAssertEqual(hex(YaraDigest.sha256, "abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let crc: (String) -> UInt32 = { text in Array(text.utf8).withUnsafeBytes { YaraDigest.crc32($0) } }
        XCTAssertEqual(crc("abc"), 0x352441c2)
        XCTAssertEqual(crc("123456789"), 0xcbf43926)
        XCTAssertEqual(crc("The quick brown fox jumps over the lazy dog"), 0x414fa339)
        XCTAssertEqual(crc(""), 0)
        XCTAssertEqual(Array("abc".utf8).withUnsafeBytes { YaraDigest.checksum32($0) }, 294)
    }

    func testHashModuleInConditions() {
        let abc = YaraFixture.bytes("abc")
        XCTAssertTrue(yaraHolds(#"hash.sha1(0, filesize) == "a9993e364706816aba3e25717850c26c9cd0d89d""#, abc))
        XCTAssertTrue(yaraHolds(#"hash.md5(0, 3) == "900150983cd24fb0d6963f7d28e17f72""#, abc))
        XCTAssertTrue(yaraHolds(#"hash.sha256(0, filesize) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad""#, abc))
        XCTAssertTrue(yaraHolds("hash.crc32(0, filesize) == 0x352441c2 and hash.checksum32(0, filesize) == 294", abc))
        XCTAssertTrue(yaraHolds(#"hash.md5(1, 1) == "92eb5ffee6ae2fec3ad71c777531578f""#, abc), "md5 of \"b\"")
        XCTAssertTrue(yaraHolds(#"hash.md5("abc") == "900150983cd24fb0d6963f7d28e17f72" and hash.crc32("abc") == 0x352441c2"#, []))
        // Like YARA, a range past the end of a fully read file stops at the end…
        XCTAssertTrue(yaraHolds(#"hash.sha1(0, 22032) == "a9993e364706816aba3e25717850c26c9cd0d89d""#, abc))
        // …but past the part that was read it is unknown.
        XCTAssertFalse(yaraHolds(#"hash.sha1(0, 22032) == "a9993e364706816aba3e25717850c26c9cd0d89d""#, abc, fileSize: 50_000))
        XCTAssertTrue(yaraHolds("not defined hash.sha1(0, 22032)", abc, fileSize: 50_000))
        XCTAssertTrue(yaraHolds("not defined hash.md5(3, 1) and not defined hash.md5(-1, 2) and not defined hash.md5(0, -1)", abc))
        XCTAssertFalse(yaraHolds(#"hash.sha1(0, filesize) == "da39a3ee5e6b4b0d3255bfef95601890afd80709""#, []),
                       "an empty file has no data to hash")
        // Uppercase hex doesn't equal YARA's lowercase digests (same as YARA).
        XCTAssertFalse(yaraHolds(#"hash.md5(0, 3) == "900150983CD24FB0D6963F7D28E17F72""#, abc))
        XCTAssertTrue(yaraHolds(#"hash.md5(0, 3) iequals "900150983CD24FB0D6963F7D28E17F72""#, abc))
    }

    func testRepeatedHashesAreComputedOnce() {
        // Many rules hashing the same range must stay fast on a larger buffer.
        var source = ""
        for index in 0..<50 {
            source += "rule h\(index) { condition: hash.sha256(0, filesize) == \"\(String(repeating: "0", count: 63))\(index % 10)\" }\n"
        }
        let set = YaraRuleSet(source: source, origin: "test")
        XCTAssertEqual(set.activeRuleCount, 50)
        let data = Data(YaraFixture.noise(2 << 20))
        let start = Date()
        XCTAssertEqual(set.scan(data), [])
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
