import Foundation
import XCTest
@testable import SpruceCore

/// A throwaway system root with a fake home folder for Protection scanner tests.
final class ProtectionFixture {
    let root: String
    let home: String
    let space: ProtectionPathSpace

    init() {
        let base = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        root = (base as NSString).appendingPathComponent("spruce-protection-\(UUID().uuidString)")
        home = root + "/Users/tester"
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        space = ProtectionPathSpace(home: home, root: root)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }

    /// Real path for a logical path ("~/…" or "/…" inside the fake root).
    func path(_ logical: String) -> String { space.real(logical) }

    @discardableResult
    func file(_ logical: String, _ contents: Data = Data("data".utf8), executable: Bool = false) -> String {
        let real = path(logical)
        try? FileManager.default.createDirectory(atPath: (real as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: real, contents: contents)
        if executable {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: real)
        }
        return real
    }

    @discardableResult
    func text(_ logical: String, _ text: String, executable: Bool = false) -> String {
        file(logical, Data(text.utf8), executable: executable)
    }

    /// A fake 64-bit Mach-O (just the magic number and padding).
    @discardableResult
    func machO(_ logical: String) -> String {
        var bytes: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]
        bytes += [UInt8](repeating: 0, count: 60)
        return file(logical, Data(bytes), executable: true)
    }

    @discardableResult
    func directory(_ logical: String) -> String {
        let real = path(logical)
        try? FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        return real
    }

    /// Writes a property list.
    @discardableResult
    func plist(_ logical: String, _ dict: [String: Any]) -> String {
        let data = (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
        return file(logical, data)
    }

    /// Writes a launchd plist.
    @discardableResult
    func launchPlist(_ logical: String, label: String, arguments: [String], runAtLoad: Bool = true,
                     keepAlive: Bool = false, environment: [String: String]? = nil) -> String {
        var dict: [String: Any] = ["Label": label, "ProgramArguments": arguments, "RunAtLoad": runAtLoad, "KeepAlive": keepAlive]
        if let environment { dict["EnvironmentVariables"] = environment }
        return plist(logical, dict)
    }

    /// Writes a minimal application bundle.
    @discardableResult
    func app(_ logical: String, bundleID: String, executable: String = "main") -> String {
        let bundle = directory(logical)
        plist(logical + "/Contents/Info.plist", ["CFBundleIdentifier": bundleID, "CFBundleExecutable": executable])
        machO(logical + "/Contents/MacOS/" + executable)
        return bundle
    }

    func scanner(probe: ProtectionStaticProbe = ProtectionStaticProbe(defaultSigning: ProtectionSigningInfo(status: .unsigned)),
                 crontab: String? = nil) -> ProtectionMalwareScanner {
        ProtectionMalwareScanner(space: space, probe: probe, crontab: crontab, userName: "tester")
    }
}
