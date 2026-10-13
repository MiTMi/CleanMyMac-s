import Foundation

/// Where the app keeps its own files. Overridable for tests.
public enum SprucePaths {
    nonisolated(unsafe) public static var applicationSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Spruce", isDirectory: true)
    }()

    nonisolated(unsafe) public static var logs: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Spruce", isDirectory: true)

    public static var settingsFile: URL { applicationSupport.appendingPathComponent("settings.json") }
    public static var historyFile: URL { applicationSupport.appendingPathComponent("history.json") }
    public static var operationsLog: URL { logs.appendingPathComponent("operations.log") }
}

/// Reads and writes a Codable value as JSON, atomically (pretty-printed by default).
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL
    /// Human-readable output (indented, sorted keys). Large, frequently written files
    /// such as the activity history turn this off.
    public let prettyPrinted: Bool

    public init(url: URL, prettyPrinted: Bool = true) {
        self.url = url
        self.prettyPrinted = prettyPrinted
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : []
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}

/// Append-only, human-readable log of every destructive operation the app performs.
///
/// Format (tab separated): ISO-8601 date, module, action, result, bytes, path/detail.
/// The file is rotated at `rotationSize` (the previous file is kept as `operations.1.log`).
public final class OperationLog: @unchecked Sendable {
    public static let shared = OperationLog(url: SprucePaths.operationsLog)

    public let url: URL
    /// Size at which the log is rotated.
    public let rotationSize: UInt64
    private let lock = NSLock()
    private var handle: FileHandle?
    private var handleInode: UInt64?
    private let formatter: ISO8601DateFormatter = ISO8601DateFormatter()

    public init(url: URL, rotationSize: UInt64 = 5_000_000) {
        self.url = url
        self.rotationSize = rotationSize
    }

    deinit {
        try? handle?.close()
    }

    /// The previous log after a rotation (`operations.1.log`).
    public var rotatedURL: URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "log" : url.pathExtension
        return url.deletingLastPathComponent().appendingPathComponent("\(base).1.\(ext)")
    }

    public func record(module: ModuleID, action: String, result: String, bytes: Int64 = 0, detail: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = [
            formatter.string(from: Date()),
            module.rawValue,
            action,
            result,
            String(bytes),
            detail.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "),
        ].joined(separator: "\t") + "\n"
        do {
            let file = try openHandle()
            let end = try file.seekToEnd()
            try file.write(contentsOf: Data(line.utf8))
            if end + UInt64(line.utf8.count) >= rotationSize {
                rotate()
            }
        } catch {
            // Logging must never break a cleanup run. Try a fresh handle next time.
            try? handle?.close()
            handle = nil
            handleInode = nil
        }
    }

    /// Most recent lines (newest last). Reads backwards from the end of the file, so it
    /// stays cheap however large the log grows; falls back to the rotated file when the
    /// current one holds fewer lines.
    public func tail(_ count: Int = 200) -> [String] {
        guard count > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        var lines = Self.lastLines(of: url, count: count)
        if lines.count < count {
            lines = Self.lastLines(of: rotatedURL, count: count - lines.count) + lines
        }
        return lines
    }

    // MARK: Private (call with the lock held)

    private func openHandle() throws -> FileHandle {
        // Reopen when the file was removed or replaced behind our back (deleted in Finder,
        // saved by an editor…): the cached handle would write to the old, unlinked file.
        let inode = currentInode()
        if let handle, inode != nil, inode == handleInode { return handle }
        try? handle?.close()
        handle = nil
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if inode == nil {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let opened = try FileHandle(forWritingTo: url)
        handle = opened
        handleInode = currentInode()
        return opened
    }

    private func currentInode() -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        handleInode = nil
        let fm = FileManager.default
        try? fm.removeItem(at: rotatedURL)
        try? fm.moveItem(at: url, to: rotatedURL)
    }

    static func lastLines(of url: URL, count: Int) -> [String] {
        guard count > 0, let file = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd(), size > 0 else { return [] }
        let chunk: UInt64 = 64 * 1024
        var offset = size
        var buffer = Data()
        var newlines = 0
        // Read until we hold more newlines than lines wanted (the first line may be partial).
        while offset > 0 && newlines <= count {
            let length = min(chunk, offset)
            offset -= length
            do {
                try file.seek(toOffset: offset)
                guard let data = try file.read(upToCount: Int(length)), !data.isEmpty else { break }
                newlines += data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
                buffer = data + buffer
            } catch {
                break
            }
        }
        var lines = String(decoding: buffer, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty {
            // The first line was cut by the chunk boundary.
            lines.removeFirst()
        }
        return lines.suffix(count).map(String.init)
    }
}

// MARK: - Settings

/// All persisted user preferences. Every field has a default so older files decode.
public struct SpruceSettings: Codable, Equatable, Sendable {
    // General
    public var playSounds: Bool = true
    public var launchAtLogin: Bool = false
    public var showMenuBarMonitor: Bool = true
    public var hasCompletedOnboarding: Bool = false
    public var reduceAmbientMotion: Bool = false

    // Scanning — which modules Checkup includes.
    public var checkupModules: [ModuleID] = ModuleID.checkupContributors
    /// Cleanup categories (rule group ids) excluded from scans.
    public var excludedCleanupCategories: [String] = []
    /// Minimum file size for Large & Old Files, in bytes.
    public var largeFileThreshold: Int64 = 50_000_000
    /// Files not opened for this many days count as "old".
    public var oldFileDays: Int = 180
    /// Apps not opened for this many days count as "unused".
    public var unusedAppDays: Int = 180
    /// Folders Clutter scans by default (tilde paths).
    public var clutterLocations: [String] = ["~"]

    // Ignore list — paths (tilde form allowed) never shown in any scan result.
    public var ignoredPaths: [String] = []
    /// Bundle identifiers never offered for update/uninstall/leftover removal.
    public var ignoredBundleIDs: [String] = []
    /// Item ids (engine-defined) the user chose to ignore, e.g. a specific update.
    public var ignoredItemIDs: [String] = []

    // Protection
    public var realtimeProtection: Bool = true
    public var scanDepth: String = "balanced"   // "quick" | "balanced" | "deep"

    // Monitor & notifications
    public var notifyLowDisk: Bool = true
    public var lowDiskThresholdPercent: Int = 10
    public var notifyHighMemory: Bool = true
    /// Alert when one app keeps a core busy for minutes.
    public var notifyHighCPU: Bool = true
    public var notifyTrashSize: Bool = true
    public var trashSizeThreshold: Int64 = 2_000_000_000
    public var notifyUpdates: Bool = true
    public var notifyThreats: Bool = true
    public var weeklyCleanupReminder: Bool = true
    public var temperatureUnitCelsius: Bool = true

    public init() {}

    public init(from decoder: Decoder) throws {
        // Decode leniently: unknown/missing keys fall back to defaults.
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ current: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil ?? current }
        playSounds = v(.playSounds, playSounds)
        launchAtLogin = v(.launchAtLogin, launchAtLogin)
        showMenuBarMonitor = v(.showMenuBarMonitor, showMenuBarMonitor)
        hasCompletedOnboarding = v(.hasCompletedOnboarding, hasCompletedOnboarding)
        reduceAmbientMotion = v(.reduceAmbientMotion, reduceAmbientMotion)
        checkupModules = v(.checkupModules, checkupModules)
        excludedCleanupCategories = v(.excludedCleanupCategories, excludedCleanupCategories)
        largeFileThreshold = v(.largeFileThreshold, largeFileThreshold)
        oldFileDays = v(.oldFileDays, oldFileDays)
        unusedAppDays = v(.unusedAppDays, unusedAppDays)
        clutterLocations = v(.clutterLocations, clutterLocations)
        ignoredPaths = v(.ignoredPaths, ignoredPaths)
        ignoredBundleIDs = v(.ignoredBundleIDs, ignoredBundleIDs)
        ignoredItemIDs = v(.ignoredItemIDs, ignoredItemIDs)
        realtimeProtection = v(.realtimeProtection, realtimeProtection)
        scanDepth = v(.scanDepth, scanDepth)
        notifyLowDisk = v(.notifyLowDisk, notifyLowDisk)
        lowDiskThresholdPercent = v(.lowDiskThresholdPercent, lowDiskThresholdPercent)
        notifyHighMemory = v(.notifyHighMemory, notifyHighMemory)
        notifyHighCPU = v(.notifyHighCPU, notifyHighCPU)
        notifyTrashSize = v(.notifyTrashSize, notifyTrashSize)
        trashSizeThreshold = v(.trashSizeThreshold, trashSizeThreshold)
        notifyUpdates = v(.notifyUpdates, notifyUpdates)
        notifyThreats = v(.notifyThreats, notifyThreats)
        weeklyCleanupReminder = v(.weeklyCleanupReminder, weeklyCleanupReminder)
        temperatureUnitCelsius = v(.temperatureUnitCelsius, temperatureUnitCelsius)
    }

    /// True if `path` (or one of its ancestors) is on the ignore list.
    public func isIgnored(path: String) -> Bool {
        let key = PathGuard.key((path as NSString).standardizingPath)
        return ignoredPaths.contains { ignored in
            let ik = PathGuard.key((ignored.expandingTilde as NSString).standardizingPath)
            return PathGuard.isInsideOrEqual(key, ik)
        }
    }

    /// Removes ignored items from scan results.
    public func filteringIgnored(_ groups: [ScanGroup]) -> [ScanGroup] {
        groups.compactMap { group in
            var g = group
            g.items = g.items.filter { item in
                if ignoredItemIDs.contains(item.id) { return false }
                if let bundleID = item.metadata["bundleID"], ignoredBundleIDs.contains(bundleID) { return false }
                if let url = item.url, isIgnored(path: url.path) { return false }
                return true
            }
            g.children = filteringIgnored(g.children)
            return g.isEmpty ? nil : g
        }
    }
}

// MARK: - Activity history

/// One recorded event in the Activity dashboard.
public struct ActivityEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case scan, clean, malwareScan, threatRemoved, maintenance, uninstall, update, cloudFreed, other
        /// Marker for a whole Checkup run (bytes are recorded on the per-module entries).
        case checkup
        /// Login/background items turned off or removed.
        case startupItems
    }

    public var id: UUID
    public var date: Date
    public var module: ModuleID
    public var kind: Kind
    public var bytes: Int64
    public var count: Int
    public var summary: String

    public init(id: UUID = UUID(), date: Date = Date(), module: ModuleID, kind: Kind, bytes: Int64 = 0, count: Int = 0, summary: String) {
        self.id = id
        self.date = date
        self.module = module
        self.kind = kind
        self.bytes = bytes
        self.count = count
        self.summary = summary
    }
}

/// Persisted list of activity entries with simple aggregation helpers.
public struct ActivityHistory: Codable, Sendable, Equatable {
    public var entries: [ActivityEntry] = []

    public init(entries: [ActivityEntry] = []) { self.entries = entries }

    public mutating func append(_ entry: ActivityEntry, limit: Int = 5000) {
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    public mutating func record(_ outcome: RunOutcome, kind: ActivityEntry.Kind) {
        append(ActivityEntry(date: outcome.date, module: outcome.module, kind: kind, bytes: outcome.freedBytes,
                             count: outcome.processedCount, summary: outcome.summary))
    }

    public func totalBytes(kind: ActivityEntry.Kind? = nil, since: Date? = nil) -> Int64 {
        entries.filter { (kind == nil || $0.kind == kind) && (since == nil || $0.date >= since!) }
            .reduce(0) { $0 + $1.bytes }
    }

    public func count(kind: ActivityEntry.Kind, since: Date? = nil) -> Int {
        entries.filter { $0.kind == kind && (since == nil || $0.date >= since!) }.reduce(0) { $0 + max($1.count, 1) }
    }

    public func lastDate(of kind: ActivityEntry.Kind) -> Date? {
        entries.filter { $0.kind == kind }.map(\.date).max()
    }
}

// MARK: - Engines

/// A scanner whose results are reviewable groups of items, and which can act on a
/// selection of those items. Most modules expose one or more of these.
public protocol GroupScanner: AnyObject {
    /// Scans and returns grouped results (already filtered by the ignore list).
    func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup]
    /// Acts on the given (selected) items: removes, trashes, disables, evicts…
    func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome
}
