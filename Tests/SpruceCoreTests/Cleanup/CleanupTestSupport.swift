import Foundation
import XCTest
@testable import SpruceCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A throwaway home folder and system root for Cleanup scanner tests.
final class CleanupFixture {
    static let day: TimeInterval = 86_400

    let root: String
    let home: String
    let system: String

    init() {
        let base = CleanupPaths.realPath(NSTemporaryDirectory())
        root = (base as NSString).appendingPathComponent("spruce-cleanup-\(UUID().uuidString)")
        home = root + "/home"
        system = root + "/sys"
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: system, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }

    /// Creates a file below `base` (home by default) with `bytes` of data, `age` seconds old.
    @discardableResult
    func file(_ relative: String, bytes: Int = 8_192, age: TimeInterval = 30 * day, in base: String? = nil,
              contents: Data? = nil) -> String {
        let path = ((base ?? home) as NSString).appendingPathComponent(relative)
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        let data = contents ?? Data(repeating: 0x41, count: bytes)
        FileManager.default.createFile(atPath: path, contents: data)
        setAge(path, age)
        return path
    }

    @discardableResult
    func directory(_ relative: String, in base: String? = nil) -> String {
        let path = ((base ?? home) as NSString).appendingPathComponent(relative)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Sets access and modification time.
    func setAge(_ path: String, _ age: TimeInterval) {
        let t = Date().addingTimeInterval(-age).timeIntervalSince1970
        var times = [timeval(tv_sec: time_t(t), tv_usec: 0), timeval(tv_sec: time_t(t), tv_usec: 0)]
        _ = utimes(path, &times)
    }

    /// Ages every folder from `path` up to (not including) `stop`, so folder mtimes
    /// changed by creating children don't count as recent activity.
    func ageFolders(_ path: String, upTo stop: String? = nil, age: TimeInterval = 30 * day) {
        var current = path
        let limit = stop ?? home
        while current.count > limit.count, current.hasPrefix(limit) {
            setAge(current, age)
            current = (current as NSString).deletingLastPathComponent
        }
    }

    func context(
        running: Set<String> = [],
        processes: Set<String> = [],
        fullDiskAccess: Bool = true,
        purpose: CleanupScanPurpose = .module,
        volumes: [CleanupVolume] = [],
        tempDir: String? = nil,
        mailAccounts: [String: CleanupMailAccount] = [:]
    ) -> CleanupContext {
        CleanupContext(
            home: home, systemRoot: system, uid: CleanupContext.currentUID, userTempDir: tempDir,
            userCacheDir: nil, startupVolumeName: "Test HD", externalVolumes: volumes,
            runningBundleIDs: running, runningProcessNames: processes, hasFullDiskAccess: fullDiskAccess,
            ownBundleID: "com.spruce.test", mailAccounts: mailAccounts, now: Date(), purpose: purpose,
            documentRevisionsPaths: ["/.DocumentRevisions-V100"], deletedUsersPath: "/Users/Deleted Users"
        )
    }

    func scan(_ context: CleanupContext, settings: SpruceSettings = SpruceSettings(),
              sections: Set<CleanupSection> = Set(CleanupSection.allCases)) -> (CleanupScanner, CleanupScanReport) {
        let scanner = CleanupScanner(context: context, settings: settings)
        return (scanner, scanner.scan(sections: sections))
    }
}

extension CleanupScanReport {
    func items(in groupID: String) -> [ScanItem] {
        func find(_ groups: [ScanGroup]) -> ScanGroup? {
            for g in groups {
                if g.id == groupID { return g }
                if let c = find(g.children) { return c }
            }
            return nil
        }
        return find(groups)?.allItems ?? []
    }

    func item(endingWith suffix: String) -> ScanItem? {
        groups.allItems.first { $0.id.hasSuffix(suffix) }
    }
}
