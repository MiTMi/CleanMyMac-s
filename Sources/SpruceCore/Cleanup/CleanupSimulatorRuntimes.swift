import Foundation

/// A simulator runtime (system image) Xcode installed, as `simctl runtime list -j` reports it.
///
/// Runtimes are managed by macOS (disk images mounted by `simdiskimaged`), so Cleanup never
/// deletes their files: the engine removes a runtime with `simctl runtime delete <id>`.
public struct CleanupSimulatorRuntime: Sendable, Hashable {
    public var identifier: String
    /// "iOS", "tvOS", "watchOS", "visionOS"…
    public var platform: String
    public var version: String
    public var build: String?
    public var sizeBytes: Int64
    /// The disk image (or runtime bundle) on disk, when reported.
    public var path: String?
    public var lastUsed: Date?
    public var isDeletable: Bool

    public init(identifier: String, platform: String, version: String, build: String? = nil, sizeBytes: Int64,
                path: String? = nil, lastUsed: Date? = nil, isDeletable: Bool = true) {
        self.identifier = identifier
        self.platform = platform
        self.version = version
        self.build = build
        self.sizeBytes = sizeBytes
        self.path = path
        self.lastUsed = lastUsed
        self.isDeletable = isDeletable
    }
}

public enum CleanupSimulatorRuntimes {
    /// Parses the output of `simctl runtime list -j`: an object keyed by runtime identifier
    /// whose values describe each runtime. Unknown or malformed entries are skipped.
    public static func parse(_ data: Data) -> [CleanupSimulatorRuntime] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let entries = object as? [String: Any] else { return [] }
        var out: [CleanupSimulatorRuntime] = []
        for (key, value) in entries {
            guard let entry = value as? [String: Any] else { continue }
            let identifier = (entry["identifier"] as? String) ?? key
            guard isValidIdentifier(identifier) else { continue }
            let version = (entry["version"] as? String) ?? ""
            out.append(CleanupSimulatorRuntime(
                identifier: identifier,
                platform: platformName(entry["platformIdentifier"] as? String,
                                       runtimeIdentifier: entry["runtimeIdentifier"] as? String),
                version: version.isEmpty ? "?" : version,
                build: entry["build"] as? String,
                sizeBytes: int64(entry["sizeBytes"]) ?? 0,
                path: entry["path"] as? String,
                lastUsed: (entry["lastUsedAt"] as? String).flatMap(date),
                isDeletable: bool(entry["deletable"]) ?? false
            ))
        }
        return out.sorted { ($0.platform, $0.version, $0.identifier) < ($1.platform, $1.version, $1.identifier) }
    }

    /// A runtime identifier is a UUID; anything else is never passed to simctl.
    public static func isValidIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, identifier.count <= 64, identifier.first != "-" else { return false }
        return identifier.utf8.allSatisfy { byte in
            (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
                || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "f"))
                || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "F"))
                || byte == UInt8(ascii: "-")
        }
    }

    static func platformName(_ platformIdentifier: String?, runtimeIdentifier: String?) -> String {
        let platform = (platformIdentifier ?? "").lowercased()
        if platform.hasSuffix("iphonesimulator") { return "iOS" }
        if platform.hasSuffix("appletvsimulator") { return "tvOS" }
        if platform.hasSuffix("watchsimulator") { return "watchOS" }
        if platform.hasSuffix("xrsimulator") { return "visionOS" }
        // "com.apple.CoreSimulator.SimRuntime.iOS-17-0" → "iOS"
        if let runtime = runtimeIdentifier, let last = runtime.split(separator: ".").last,
           let name = last.split(separator: "-").first, !name.isEmpty {
            return name == "xrOS" ? "visionOS" : String(name)
        }
        return "Simulator"
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let number as Int: return Int64(number)
        case let number as Int64: return number
        case let number as Double: return Int64(number)
        case let number as NSNumber: return number.int64Value
        default: return nil
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        default: return nil
        }
    }

    private static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
