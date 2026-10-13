import Foundation

// Pure logic behind the Storage and Devices cards: the startup disk's condition (SMART,
// as `diskutil info -plist` reports it without root), mounted external drives and their
// Eject messages, and when the Trash is worth walking again.

// MARK: - Disk condition

/// SMART status of a disk as `diskutil` reports it.
public enum MonitorDiskCondition: String, Sendable, Equatable, Codable {
    case verified
    case failing
    case notSupported
    case unknown

    /// Maps `diskutil`'s `SMARTStatus` value ("Verified", "Failing", "Not Supported").
    public init(smartStatus: String?) {
        switch smartStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "verified"?: self = .verified
        case "failing"?, "failed"?: self = .failing
        case "not supported"?, "unsupported"?: self = .notSupported
        default: self = .unknown
        }
    }

    public var label: String {
        switch self {
        case .verified: return "Healthy"
        case .failing: return "Failing"
        case .notSupported: return "Not reported"
        case .unknown: return "Unknown"
        }
    }
}

/// What is known about the startup disk's hardware condition.
public struct MonitorDiskHealth: Sendable, Equatable {
    public var condition: MonitorDiskCondition
    /// 0...100: what's left of the drive's rated endurance (100 − NVMe "percentage used").
    public var lifeLeftPercent: Int?
    /// Drive temperature in degrees Celsius.
    public var temperatureCelsius: Double?

    public init(condition: MonitorDiskCondition, lifeLeftPercent: Int? = nil, temperatureCelsius: Double? = nil) {
        self.condition = condition
        self.lifeLeftPercent = lifeLeftPercent.map { min(100, max(0, $0)) }
        self.temperatureCelsius = temperatureCelsius
    }

    public var isFailing: Bool { condition == .failing }

    /// True when there is something worth showing.
    public var hasDetails: Bool {
        condition == .verified || condition == .failing || lifeLeftPercent != nil || temperatureCelsius != nil
    }

    /// "Healthy · 98% life left · 38 °C" (parts that are unknown are left out).
    public func summary(inCelsius: Bool = true) -> String {
        var parts: [String] = []
        switch condition {
        case .verified, .failing: parts.append(condition.label)
        case .notSupported, .unknown: break
        }
        if let lifeLeftPercent { parts.append("\(lifeLeftPercent)% life left") }
        if let temperatureCelsius { parts.append(MonitorFormat.temperature(temperatureCelsius, inCelsius: inCelsius)) }
        return parts.isEmpty ? condition.label : parts.joined(separator: " · ")
    }

    /// The physical reading's details, with the volume's verdict when the physical disk's
    /// own status is unknown. A failing verdict from either side wins.
    public func merged(over volume: MonitorDiskHealth?) -> MonitorDiskHealth {
        guard let volume else { return self }
        var result = self
        if volume.condition == .failing || result.condition == .unknown { result.condition = volume.condition }
        if result.lifeLeftPercent == nil { result.lifeLeftPercent = volume.lifeLeftPercent }
        if result.temperatureCelsius == nil { result.temperatureCelsius = volume.temperatureCelsius }
        return result
    }

    /// Parses `diskutil info -plist <volume or disk>`. Returns nil when the data is not a
    /// `diskutil` property list.
    public static func parse(diskutilPlist data: Data) -> MonitorDiskHealth? {
        guard let info = dictionary(from: data) else { return nil }
        let condition = MonitorDiskCondition(smartStatus: info["SMARTStatus"] as? String)
        var lifeLeft: Int?
        var temperature: Double?
        // NVMe log values (macOS 13+ on the whole physical disk). Apple marks them as
        // "may vary", so each one is optional and sanity-checked.
        if let nvme = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any] {
            if let used = integer(nvme["PERCENTAGE_USED"]), used >= 0 {
                lifeLeft = max(0, 100 - used)
            }
            temperature = celsius(fromNVMe: integer(nvme["TEMPERATURE"]))
        }
        return MonitorDiskHealth(condition: condition, lifeLeftPercent: lifeLeft, temperatureCelsius: temperature)
    }

    /// The whole physical disk behind an APFS volume ("disk0" for a physical store
    /// "disk0s2"), or nil when the plist names none.
    public static func physicalWholeDisk(diskutilPlist data: Data) -> String? {
        guard let info = dictionary(from: data) else { return nil }
        let stores = info["APFSPhysicalStores"] as? [[String: Any]] ?? []
        let store = stores.compactMap { $0["APFSPhysicalStore"] as? String }.first
        guard let store, let whole = wholeDisk(of: store) else { return nil }
        // Only the volume's own disk name is ever passed on (never a path or an option).
        return whole
    }

    /// "disk0" for "disk0s2" or "disk0"; nil for anything that isn't a BSD disk name.
    public static func wholeDisk(of identifier: String) -> String? {
        let name = identifier.hasPrefix("/dev/") ? String(identifier.dropFirst(5)) : identifier
        guard name.hasPrefix("disk") else { return nil }
        let digits = name.dropFirst(4).prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = name.dropFirst(4 + digits.count)
        // Either nothing more, or a partition suffix "s<number>…".
        if !rest.isEmpty {
            guard rest.first == "s", rest.dropFirst().first.map({ $0.isASCII && $0.isNumber }) == true else { return nil }
        }
        return "disk" + digits
    }

    /// NVMe reports Kelvin; some tools report Celsius. Anything implausible is dropped.
    static func celsius(fromNVMe value: Int?) -> Double? {
        guard let value else { return nil }
        if (200...400).contains(value) { return Double(value) - 273.15 }
        if (1...130).contains(value) { return Double(value) }
        return nil
    }

    private static func dictionary(from data: Data) -> [String: Any]? {
        guard !data.isEmpty,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return object as? [String: Any]
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

// MARK: - External drives

/// A mounted volume shown in the Devices card with an Eject button.
public struct MonitorVolume: Sendable, Equatable, Identifiable {
    /// Mount point, e.g. "/Volumes/Backup".
    public var path: String
    public var name: String
    public var totalBytes: Int64
    public var availableBytes: Int64
    /// "APFS", "ExFAT"…
    public var format: String?
    public var isRemovable: Bool
    public var isInternal: Bool

    public var id: String { path }

    public init(path: String, name: String, totalBytes: Int64, availableBytes: Int64, format: String? = nil,
                isRemovable: Bool = false, isInternal: Bool = false) {
        self.path = path
        self.name = name.isEmpty ? (path as NSString).lastPathComponent : name
        self.totalBytes = max(0, totalBytes)
        self.availableBytes = min(max(0, availableBytes), max(0, totalBytes))
        self.format = format
        self.isRemovable = isRemovable
        self.isInternal = isInternal
    }

    public var usedFraction: Double {
        totalBytes > 0 ? Double(totalBytes - availableBytes) / Double(totalBytes) : 0
    }

    /// "312 GB free of 1 TB".
    public var capacityText: String {
        guard totalBytes > 0 else { return "Capacity unknown" }
        return "\(ByteFormat.string(availableBytes)) free of \(ByteFormat.string(totalBytes))"
    }

    public var symbol: String {
        if isRemovable && !isInternal { return "sdcard" }
        return "externaldrive"
    }

    /// Whether a mounted volume belongs in the Devices card: local volumes the user can
    /// eject (external disks, card readers, disk images), never the startup disk or the
    /// system's own volumes. Network shares are left out (reading them can stall).
    public static func shouldList(path: String, isRootFileSystem: Bool?, isLocal: Bool?, isBrowsable: Bool?,
                                  isEjectable: Bool?, isRemovable: Bool?, isInternal: Bool?) -> Bool {
        let standardized = (path as NSString).standardizingPath
        guard standardized != "/", isRootFileSystem != true else { return false }
        if standardized.hasPrefix("/System/Volumes/") || standardized == "/System/Volumes" { return false }
        guard isLocal != false, isBrowsable != false else { return false }
        return isEjectable == true || isRemovable == true || isInternal == false
    }

    /// By name, then mount point.
    public static func arranged(_ volumes: [MonitorVolume]) -> [MonitorVolume] {
        var seen = Set<String>()
        return volumes.filter { seen.insert($0.path).inserted }.sorted { a, b in
            let byName = a.name.localizedCaseInsensitiveCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.path < b.path
        }
    }
}

/// A process that has files open on a volume (from `lsof -F pc`).
public struct MonitorFileHolder: Sendable, Equatable {
    public var pid: Int32
    public var command: String

    public init(pid: Int32, command: String) {
        self.pid = pid
        self.command = command
    }
}

/// Result of ejecting one drive.
public enum MonitorEjectResult: Sendable, Equatable {
    case ejected
    case failed(String)
}

public enum MonitorEject {
    /// Processes in `lsof -F pc` output ("p<pid>" then "c<command>" lines), one per pid,
    /// in order of appearance. `excludingPIDs` drops e.g. Spruce itself.
    public static func holders(fromLsof output: String, excludingPIDs: Set<Int32> = []) -> [MonitorFileHolder] {
        var result: [MonitorFileHolder] = []
        var seen = Set<Int32>()
        var pid: Int32?
        for raw in output.split(whereSeparator: \.isNewline) {
            guard let tag = raw.first else { continue }
            let value = String(raw.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
            case "c":
                guard let current = pid, !excludingPIDs.contains(current), !value.isEmpty,
                      seen.insert(current).inserted else { continue }
                result.append(MonitorFileHolder(pid: current, command: value))
            default:
                continue
            }
        }
        return result
    }

    /// Unique display names, in order.
    public static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// "“Backup” is in use by Preview and Terminal. Quit them, then try again." When the
    /// apps can't be named: "“Backup” couldn't be ejected. <reason>".
    public static func failureMessage(volume: String, holders: [String], reason: String?) -> String {
        let names = uniqueNames(holders)
        let quoted = "\u{201C}\(volume)\u{201D}"
        if !names.isEmpty {
            let shown = Array(names.prefix(3))
            var list = shown.count == 1 ? shown[0]
                : shown.dropLast().joined(separator: ", ") + " and " + shown[shown.count - 1]
            if names.count > shown.count { list = shown.joined(separator: ", ") + " and \(names.count - shown.count) more" }
            let pronoun = names.count == 1 ? "it" : "them"
            return "\(quoted) is in use by \(list). Quit \(pronoun), then try again."
        }
        let detail = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return detail.isEmpty ? "\(quoted) couldn't be ejected. It may be in use."
            : "\(quoted) couldn't be ejected. \(detail)"
    }
}

// MARK: - Trash schedule

/// Modification dates of the Trash folders (`~/.Trash` and each volume's
/// `.Trashes/<uid>`). Adding or removing an item changes its folder's date, and mounting
/// or ejecting a drive changes the set of folders.
public struct MonitorTrashSignature: Sendable, Equatable {
    /// Folder path → modification time (seconds since 1970). Folders whose date could not
    /// be read are absent.
    public var stamps: [String: Double]

    public init(stamps: [String: Double] = [:]) {
        self.stamps = stamps
    }
}

/// The last Trash measurement.
public struct MonitorTrashReading: Sendable, Equatable {
    public var status: MonitorTrashStatus
    public var date: Date
    public var signature: MonitorTrashSignature

    public init(status: MonitorTrashStatus, date: Date, signature: MonitorTrashSignature) {
        self.status = status
        self.date = date
        self.signature = signature
    }
}

/// Decides when the Trash is walked again. Walking a large Trash can take many seconds,
/// so it only happens when the Trash changed, not on a fixed timer.
public enum MonitorTrashSchedule {
    public static func shouldMeasure(force: Bool, last: MonitorTrashReading?, current: MonitorTrashSignature,
                                     now: Date) -> Bool {
        guard let last else { return true }
        let age = now.timeIntervalSince(last.date)
        if age < 0 { return true }   // the clock moved back
        if case .needsAccess = last.status {
            // Listing fails at once without Full Disk Access; try again now and then.
            return force || age >= MonitorSampling.trashAccessRetry
        }
        if last.signature != current { return true }
        if force && age >= MonitorSampling.trashForcedRefresh { return true }
        return age >= MonitorSampling.trashMaximumAge
    }
}
