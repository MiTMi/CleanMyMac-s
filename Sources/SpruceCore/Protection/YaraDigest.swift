import Foundation

// Digests for YARA's hash module, in plain Swift so they work on Linux too. SHA-256 reuses
// the Clutter implementation (CryptoKit on macOS, portable code elsewhere).

enum YaraDigest {
    // MARK: MD5 (RFC 1321)

    private static let md5Shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    private static let md5Constants: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ]

    static func md5(_ bytes: UnsafeRawBufferPointer) -> [UInt8] {
        var state: (UInt32, UInt32, UInt32, UInt32) = (0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476)
        var words = [UInt32](repeating: 0, count: 16)
        blocks(of: bytes, bigEndianLength: false) { block in
            for i in 0..<16 {
                words[i] = UInt32(block[i * 4]) | UInt32(block[i * 4 + 1]) << 8
                    | UInt32(block[i * 4 + 2]) << 16 | UInt32(block[i * 4 + 3]) << 24
            }
            var (a, b, c, d) = state
            for i in 0..<64 {
                var f: UInt32
                let g: Int
                switch i >> 4 {
                case 0:
                    f = (b & c) | (~b & d)
                    g = i
                case 1:
                    f = (d & b) | (~d & c)
                    g = (5 * i + 1) & 15
                case 2:
                    f = b ^ c ^ d
                    g = (3 * i + 5) & 15
                default:
                    f = c ^ (b | ~d)
                    g = (7 * i) & 15
                }
                f = f &+ a &+ md5Constants[i] &+ words[g]
                a = d
                d = c
                c = b
                b = b &+ rotateLeft(f, md5Shifts[i])
            }
            state = (state.0 &+ a, state.1 &+ b, state.2 &+ c, state.3 &+ d)
        }
        var out: [UInt8] = []
        out.reserveCapacity(16)
        for word in [state.0, state.1, state.2, state.3] {
            for shift in stride(from: 0, through: 24, by: 8) { out.append(UInt8(truncatingIfNeeded: word >> UInt32(shift))) }
        }
        return out
    }

    // MARK: SHA-1 (FIPS 180-4)

    static func sha1(_ bytes: UnsafeRawBufferPointer) -> [UInt8] {
        var state: (UInt32, UInt32, UInt32, UInt32, UInt32) = (0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0)
        var words = [UInt32](repeating: 0, count: 80)
        blocks(of: bytes, bigEndianLength: true) { block in
            for i in 0..<16 {
                words[i] = UInt32(block[i * 4]) << 24 | UInt32(block[i * 4 + 1]) << 16
                    | UInt32(block[i * 4 + 2]) << 8 | UInt32(block[i * 4 + 3])
            }
            for i in 16..<80 {
                words[i] = rotateLeft(words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16], 1)
            }
            var (a, b, c, d, e) = state
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = rotateLeft(a, 5) &+ f &+ e &+ k &+ words[i]
                e = d
                d = c
                c = rotateLeft(b, 30)
                b = a
                a = temp
            }
            state = (state.0 &+ a, state.1 &+ b, state.2 &+ c, state.3 &+ d, state.4 &+ e)
        }
        var out: [UInt8] = []
        out.reserveCapacity(20)
        for word in [state.0, state.1, state.2, state.3, state.4] {
            for shift in stride(from: 24, through: 0, by: -8) { out.append(UInt8(truncatingIfNeeded: word >> UInt32(shift))) }
        }
        return out
    }

    // MARK: SHA-256

    static func sha256(_ bytes: UnsafeRawBufferPointer) -> [UInt8] {
        var hasher = ClutterSHA256()
        hasher.update(bytes: bytes)
        return hasher.finalized()
    }

    // MARK: CRC-32 (IEEE 802.3, as zlib) and YARA's checksum32

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        crcTable.withUnsafeBufferPointer { table in
            for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Sum of all bytes, wrapping at 32 bits.
    static func checksum32(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var sum: UInt32 = 0
        for byte in bytes { sum &+= UInt32(byte) }
        return sum
    }

    // MARK: Helpers

    @inline(__always)
    private static func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }

    /// Feeds 64-byte blocks of `bytes` followed by Merkle–Damgård padding with the bit length.
    private static func blocks(of bytes: UnsafeRawBufferPointer, bigEndianLength: Bool,
                               _ process: (UnsafeRawBufferPointer) -> Void) {
        let fullBlocks = bytes.count / 64
        for index in 0..<fullBlocks {
            process(UnsafeRawBufferPointer(rebasing: bytes[index * 64..<index * 64 + 64]))
        }
        var tail = Array(bytes[(fullBlocks * 64)...])
        tail.append(0x80)
        while tail.count % 64 != 56 { tail.append(0) }
        let bitLength = UInt64(bytes.count) &* 8
        for k in 0..<8 {
            let shift = bigEndianLength ? UInt64(56 - 8 * k) : UInt64(8 * k)
            tail.append(UInt8(truncatingIfNeeded: bitLength >> shift))
        }
        tail.withUnsafeBytes { raw in
            for index in 0..<raw.count / 64 {
                process(UnsafeRawBufferPointer(rebasing: raw[index * 64..<index * 64 + 64]))
            }
        }
    }
}
