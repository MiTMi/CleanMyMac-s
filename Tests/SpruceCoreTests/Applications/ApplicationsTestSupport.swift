import Foundation
import XCTest
@testable import SpruceCore

/// A throw-away directory tree for Applications tests (never the real home folder).
final class ApplicationsTempTree {
    let root: String

    init() {
        root = (NSTemporaryDirectory() as NSString).appendingPathComponent("spruce-apps-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }

    func path(_ relative: String) -> String {
        (root as NSString).appendingPathComponent(relative)
    }

    @discardableResult
    func dir(_ relative: String) -> String {
        let p = path(relative)
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }

    @discardableResult
    func file(_ relative: String, bytes: Int = 16, modified: Date? = nil) -> String {
        let p = path(relative)
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: p, contents: Data(repeating: 0x41, count: bytes))
        if let modified { setModified(p, modified) }
        return p
    }

    @discardableResult
    func plist(_ relative: String, _ value: [String: Any]) -> String {
        let p = path(relative)
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        FileManager.default.createFile(atPath: p, contents: data)
        return p
    }

    func setModified(_ path: String, _ date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    /// Writes a minimal (stored, uncompressed) zip archive containing the given entry names.
    @discardableResult
    func zip(_ relative: String, entries: [String]) -> String {
        var data = Data()
        var central = Data()
        func put16(_ d: inout Data, _ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        func put32(_ d: inout Data, _ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        for name in entries {
            let nameData = Data(name.utf8)
            let offset = data.count
            // Local file header.
            put32(&data, 0x0403_4B50)
            for _ in 0..<5 { put16(&data, 0) }          // version, flags, method, time, date
            for _ in 0..<3 { put32(&data, 0) }          // crc, compressed, uncompressed
            put16(&data, nameData.count)
            put16(&data, 0)
            data.append(nameData)
            // Central directory header.
            put32(&central, 0x0201_4B50)
            put16(&central, 20)
            put16(&central, 20)
            for _ in 0..<4 { put16(&central, 0) }       // flags, method, time, date
            for _ in 0..<3 { put32(&central, 0) }       // crc, compressed, uncompressed
            put16(&central, nameData.count)
            for _ in 0..<4 { put16(&central, 0) }       // extra, comment, disk, internal attrs
            put32(&central, 0)                           // external attrs
            put32(&central, offset)
            central.append(nameData)
        }
        let centralOffset = data.count
        data.append(central)
        put32(&data, 0x0605_4B50)
        put16(&data, 0)
        put16(&data, 0)
        put16(&data, entries.count)
        put16(&data, entries.count)
        put32(&data, central.count)
        put32(&data, centralOffset)
        put16(&data, 0)
        let p = path(relative)
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: p, contents: data)
        return p
    }
}

func applicationsIdentity(_ bundleID: String, name: String, bundlePath: String, executable: String? = nil,
                          groups: [String] = [], embedded: [String] = [], team: String? = nil) -> ApplicationsAppIdentity {
    ApplicationsAppIdentity(bundleID: bundleID, bundlePath: bundlePath, names: [name], executableName: executable ?? name,
                            teamID: team, vendorToken: ApplicationsVendorName.token(bundleID: bundleID),
                            appGroups: groups, embeddedBundleIDs: embedded)
}
