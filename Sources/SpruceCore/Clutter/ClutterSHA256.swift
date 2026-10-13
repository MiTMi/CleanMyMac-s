import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Portable SHA-256

/// A straightforward FIPS 180-4 SHA-256 implementation in pure Swift.
///
/// Used where CryptoKit is unavailable (Linux CI) and as a reference in tests on macOS.
public struct ClutterSoftwareSHA256: Sendable {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    private var pending: [UInt8] = []
    private var length: UInt64 = 0

    public init() {
        pending.reserveCapacity(64)
    }

    /// Feeds more bytes.
    public mutating func update(bytes: UnsafeRawBufferPointer) {
        guard let base = bytes.baseAddress, bytes.count > 0 else { return }
        length &+= UInt64(bytes.count)
        var offset = 0
        if !pending.isEmpty {
            let take = min(64 - pending.count, bytes.count)
            pending.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[0..<take]))
            offset = take
            if pending.count == 64 {
                let block = pending
                block.withUnsafeBytes { compress($0.baseAddress!) }
                pending.removeAll(keepingCapacity: true)
            }
        }
        while bytes.count - offset >= 64 {
            compress(base + offset)
            offset += 64
        }
        if offset < bytes.count {
            pending.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[offset..<bytes.count]))
        }
    }

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { update(bytes: $0) }
    }

    public mutating func update(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { update(bytes: $0) }
    }

    /// The 32-byte digest of everything fed so far (the hasher itself is unchanged).
    public func finalized() -> [UInt8] {
        var copy = self
        var tail = copy.pending
        let bitLength = copy.length &* 8
        tail.append(0x80)
        while tail.count % 64 != 56 { tail.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            tail.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        tail.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                copy.compress(raw.baseAddress! + offset)
                offset += 64
            }
        }
        var digest: [UInt8] = []
        digest.reserveCapacity(32)
        for word in copy.state {
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word))
        }
        return digest
    }

    @inline(__always)
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    private mutating func compress(_ block: UnsafeRawPointer) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let b0 = UInt32(block.load(fromByteOffset: i * 4, as: UInt8.self))
            let b1 = UInt32(block.load(fromByteOffset: i * 4 + 1, as: UInt8.self))
            let b2 = UInt32(block.load(fromByteOffset: i * 4 + 2, as: UInt8.self))
            let b3 = UInt32(block.load(fromByteOffset: i * 4 + 3, as: UInt8.self))
            w[i] = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
        for i in 16..<64 {
            let s0 = Self.rotr(w[i - 15], 7) ^ Self.rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = Self.rotr(w[i - 2], 17) ^ Self.rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for i in 0..<64 {
            let s1 = Self.rotr(e, 6) ^ Self.rotr(e, 11) ^ Self.rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let t1 = h &+ s1 &+ ch &+ Self.k[i] &+ w[i]
            let s0 = Self.rotr(a, 2) ^ Self.rotr(a, 13) ^ Self.rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            h = g
            g = f
            f = e
            e = d &+ t1
            d = c
            c = b
            b = a
            a = t1 &+ t2
        }
        state[0] &+= a
        state[1] &+= b
        state[2] &+= c
        state[3] &+= d
        state[4] &+= e
        state[5] &+= f
        state[6] &+= g
        state[7] &+= h
    }
}

// MARK: - Platform SHA-256

/// SHA-256 backed by CryptoKit (hardware accelerated on Apple Silicon) when available,
/// otherwise by `ClutterSoftwareSHA256`. Both produce identical digests.
public struct ClutterSHA256 {
    #if canImport(CryptoKit)
    private var hasher = CryptoKit.SHA256()
    #else
    private var hasher = ClutterSoftwareSHA256()
    #endif

    public init() {}

    public mutating func update(bytes: UnsafeRawBufferPointer) {
        guard bytes.count > 0 else { return }
        #if canImport(CryptoKit)
        hasher.update(bufferPointer: bytes)
        #else
        hasher.update(bytes: bytes)
        #endif
    }

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { update(bytes: $0) }
    }

    public mutating func update(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { update(bytes: $0) }
    }

    /// The 32-byte digest of everything fed so far.
    public func finalized() -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(hasher.finalize())
        #else
        return hasher.finalized()
        #endif
    }

    /// Lowercase hex digest of `data`.
    public static func hex(_ data: Data) -> String {
        var h = ClutterSHA256()
        h.update(data)
        return ClutterHex.string(h.finalized())
    }

    /// Lowercase hex digest of a UTF-8 string.
    public static func hex(_ string: String) -> String {
        hex(Data(string.utf8))
    }
}

public enum ClutterHex {
    private static let digits: [Character] = Array("0123456789abcdef")

    public static func string(_ bytes: [UInt8]) -> String {
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0F)])
        }
        return out
    }
}

// MARK: - File hashing

/// Reads files with POSIX I/O (never follows symlinks) and hashes them for the
/// duplicate finder.
public enum ClutterFileHasher {
    /// Bytes read from each end of a file for the quick "partial" hash.
    public static let partialChunk = 64 * 1024

    /// True when the partial hash already covers the whole file.
    public static func partialCoversWholeFile(size: Int64) -> Bool {
        size <= Int64(partialChunk * 2)
    }

    /// SHA-256 of `size ‖ first 64 KB ‖ last 64 KB` (the whole file when it is at most
    /// 128 KB). Returns nil if the file can't be read or its size changed.
    public static func partialHash(path: String, size: Int64) -> String? {
        guard size > 0 else { return nil }
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        disableCaching(fd)
        var hasher = ClutterSHA256()
        var sizeLE = UInt64(size).littleEndian
        withUnsafeBytes(of: &sizeLE) { hasher.update(bytes: $0) }

        if partialCoversWholeFile(size: size) {
            guard let data = readFully(fd, offset: 0, count: Int(size)), data.count == Int(size) else { return nil }
            data.withUnsafeBytes { hasher.update(bytes: $0) }
            // A file that grew since the walk is not the file we measured.
            if readFully(fd, offset: size, count: 1)?.isEmpty == false { return nil }
        } else {
            guard let head = readFully(fd, offset: 0, count: partialChunk), head.count == partialChunk,
                  let tail = readFully(fd, offset: size - Int64(partialChunk), count: partialChunk),
                  tail.count == partialChunk else { return nil }
            head.withUnsafeBytes { hasher.update(bytes: $0) }
            tail.withUnsafeBytes { hasher.update(bytes: $0) }
        }
        return ClutterHex.string(hasher.finalized())
    }

    /// SHA-256 of the whole file, streamed in 1 MB chunks. Returns nil if the file can't
    /// be read, its size differs from `expectedSize`, or `shouldContinue` returns false.
    public static func fullHash(path: String, expectedSize: Int64? = nil, chunkSize: Int = 1 << 20,
                                shouldContinue: () -> Bool = { true }) -> String? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        disableCaching(fd)
        var hasher = ClutterSHA256()
        var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: max(4096, chunkSize))
        while true {
            if !shouldContinue() { return nil }
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                read(fd, raw.baseAddress, raw.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { break }
            buffer.withUnsafeBytes { raw in
                hasher.update(bytes: UnsafeRawBufferPointer(rebasing: raw[0..<count]))
            }
            total += Int64(count)
        }
        if let expectedSize, total != expectedSize { return nil }
        return ClutterHex.string(hasher.finalized())
    }

    private static func readFully(_ fd: Int32, offset: Int64, count: Int) -> Data? {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        var done = 0
        let ok: Bool = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            while done < count {
                let n = pread(fd, base + done, count - done, off_t(offset + Int64(done)))
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if n == 0 { break }
                done += n
            }
            return true
        }
        guard ok else { return nil }
        if done < count { data.removeSubrange(done..<count) }
        return data
    }

    /// Hashing gigabytes should not evict everything else from the unified buffer cache.
    private static func disableCaching(_ fd: Int32) {
        #if canImport(Darwin)
        _ = fcntl(fd, F_NOCACHE, 1)
        #endif
    }
}
