import Foundation
import XCTest
@testable import SpruceCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A throwaway home folder for Clutter tests (never the real home).
final class ClutterFixture {
    static let day: TimeInterval = 86_400

    let root: String
    let home: String

    init() {
        let base = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        root = (base as NSString).appendingPathComponent("spruce-clutter-\(UUID().uuidString)")
        home = root + "/home"
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    var paths: ClutterPaths { ClutterPaths(home: home) }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }

    /// Creates a file below home with the given contents (or `bytes` of a repeated byte).
    @discardableResult
    func file(_ relative: String, bytes: Int = 4_096, fill: UInt8 = 0x41, contents: Data? = nil,
              age: TimeInterval = 0) -> String {
        let path = (home as NSString).appendingPathComponent(relative)
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: contents ?? Data(repeating: fill, count: bytes))
        if age > 0 { setAge(path, age) }
        return path
    }

    func setAge(_ path: String, _ age: TimeInterval) {
        let t = Date().addingTimeInterval(-age).timeIntervalSince1970
        var times = [timeval(tv_sec: time_t(t), tv_usec: 0), timeval(tv_sec: time_t(t), tv_usec: 0)]
        _ = utimes(path, &times)
    }

    /// Deterministic pseudo-random bytes.
    static func noise(_ count: Int, seed: UInt64) -> Data {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            bytes[i] = UInt8(truncatingIfNeeded: state >> 33)
        }
        return Data(bytes)
    }
}

/// Builds a ClutterFile without touching the disk.
func clutterFile(_ path: String, size: Int64 = 1_000_000, modified: Date = Date(), created: Date? = nil,
                 lastOpened: Date? = nil, accessed: Date? = nil, inode: UInt64 = 0, isCloud: Bool = false,
                 isFolder: Bool = false) -> ClutterFile {
    ClutterFile(path: path, size: size, modified: modified, accessed: accessed, created: created, lastOpened: lastOpened,
                inode: inode, isFolder: isFolder, isCloud: isCloud)
}
