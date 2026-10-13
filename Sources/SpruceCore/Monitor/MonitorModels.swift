import Foundation

// MARK: - Power

/// The machine's battery, or an attached UPS (Mac mini). Absent on a desktop
/// without a UPS.
public struct MonitorPowerInfo: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case internalBattery
        case ups
    }

    public var kind: Kind
    public var name: String
    /// Charge, 0...1.
    public var level: Double?
    public var isCharging: Bool
    public var isCharged: Bool
    /// True on AC power (adapter connected, or the UPS has mains power).
    public var onExternalPower: Bool
    /// Minutes until empty; nil while macOS is still calculating or on AC.
    public var minutesToEmpty: Int?
    /// Minutes until full; nil while calculating or not charging.
    public var minutesToFull: Int?
    /// Full-charge capacity / design capacity, 0...1 (internal battery only).
    public var health: Double?
    public var cycleCount: Int?

    public init(kind: Kind, name: String, level: Double? = nil, isCharging: Bool = false, isCharged: Bool = false,
                onExternalPower: Bool = true, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil,
                health: Double? = nil, cycleCount: Int? = nil) {
        self.kind = kind
        self.name = name
        self.level = level.map(monitorClamp01)
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.onExternalPower = onExternalPower
        self.minutesToEmpty = minutesToEmpty.flatMap { $0 > 0 ? $0 : nil }
        self.minutesToFull = minutesToFull.flatMap { $0 > 0 ? $0 : nil }
        self.health = health.map(monitorClamp01)
        self.cycleCount = cycleCount
    }

    /// Card title.
    public var title: String { kind == .ups ? "UPS" : "Battery" }

    /// One-line state: "Charging · 1:12 to full", "3:40 left", "Charged", "On UPS battery"…
    public var statusText: String {
        if isCharging {
            if let minutes = minutesToFull { return "Charging · \(MonitorFormat.hoursMinutes(minutes)) to full" }
            return "Charging"
        }
        if onExternalPower {
            if kind == .ups { return "On mains power" }
            return isCharged || (level ?? 0) >= 0.995 ? "Charged" : "On power adapter · not charging"
        }
        let source = kind == .ups ? "On UPS battery" : "On battery"
        if let minutes = minutesToEmpty { return "\(source) · \(MonitorFormat.hoursMinutes(minutes)) left" }
        return "\(source) · calculating…"
    }

    /// True when health has dropped below Apple's "service recommended" level.
    public var needsService: Bool {
        guard let health else { return false }
        return health < MonitorBatteryMath.serviceThreshold
    }
}

// MARK: - Connected devices

/// A peripheral that reports its battery (Magic Keyboard, Mouse, Trackpad…).
public struct MonitorDevice: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// 0...100, nil when the device does not report a battery.
    public var batteryPercent: Int?

    public init(id: String, name: String, batteryPercent: Int?) {
        self.id = id
        self.name = name
        self.batteryPercent = batteryPercent.map { min(100, max(0, $0)) }
    }

    /// Below 20 % a device is shown in red and sorted to the top.
    public static let lowBatteryPercent = 20

    public var isLowBattery: Bool {
        guard let batteryPercent else { return false }
        return batteryPercent < Self.lowBatteryPercent
    }

    /// SF Symbol for the device, inferred from its product name.
    public var symbol: String { Self.symbol(for: name) }

    public static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("mouse") { return "computermouse" }
        if n.contains("trackpad") { return "hand.point.up.left" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("headphone") || n.contains("beats") || n.contains("buds") { return "headphones" }
        if n.contains("controller") || n.contains("gamepad") { return "gamecontroller" }
        if n.contains("speaker") { return "hifispeaker" }
        if n.contains("pencil") { return "applepencil" }
        return "dot.radiowaves.left.and.right"
    }

    /// Low battery first (emptiest first), then by name; duplicates (several HID
    /// services of the same device) are dropped.
    public static func arranged(_ devices: [MonitorDevice]) -> [MonitorDevice] {
        var seen = Set<String>()
        let unique = devices.filter { seen.insert($0.id).inserted }
        return unique.sorted { a, b in
            if a.isLowBattery != b.isLowBattery { return a.isLowBattery }
            if a.isLowBattery, let pa = a.batteryPercent, let pb = b.batteryPercent, pa != pb { return pa < pb }
            let byName = a.name.localizedCaseInsensitiveCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.id < b.id
        }
    }
}

// MARK: - Trash

/// What the monitor knows about the size of the Trash.
public enum MonitorTrashStatus: Sendable, Equatable {
    /// Not measured yet.
    case measuring
    /// `~/.Trash` cannot be listed without Full Disk Access.
    case needsAccess
    case measured(Int64)

    public var bytes: Int64? {
        if case .measured(let bytes) = self { return bytes }
        return nil
    }
}

// MARK: - Formatting

public enum MonitorFormat {
    /// Throughput in decimal units: "0 B/s", "512 B/s", "84 KB/s", "1.2 MB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        if value < 1000 { return "\(Int(value.rounded())) B/s" }
        let units = ["KB/s", "MB/s", "GB/s", "TB/s"]
        var scaled = value / 1000
        var unit = 0
        while scaled >= 999.5, unit < units.count - 1 {
            scaled /= 1000
            unit += 1
        }
        return "\(compact(scaled)) \(units[unit])"
    }

    /// "42%" for a 0...1 fraction.
    public static func percent(_ fraction: Double) -> String {
        let value = fraction.isFinite ? fraction : 0
        return "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    /// Process CPU in percent of one core: "0.4%", "12%", "140%".
    public static func cpuPercent(_ percent: Double) -> String {
        let value = percent.isFinite ? max(0, percent) : 0
        if value < 10 { return trimmed(String(format: "%.1f", value)) + "%" }
        return "\(Int(value.rounded()))%"
    }

    /// Uptime: "45 s", "12 min", "3 h 12 min", "6 d 4 h".
    public static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        if total < 60 { return "\(total) s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 {
            let rem = minutes % 60
            return rem == 0 ? "\(hours) h" : "\(hours) h \(rem) min"
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours == 0 ? "\(days) d" : "\(days) d \(remHours) h"
    }

    /// Time since an event, compact: "just now", "12 min ago", "3 h ago", "2 d ago".
    public static func ago(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? Int(max(0, seconds)) : 0
        if total < 60 { return "just now" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        return "\(hours / 24) d ago"
    }

    /// "38 °C" or "100 °F" from degrees Celsius.
    public static func temperature(_ celsius: Double, inCelsius: Bool = true) -> String {
        let value = celsius.isFinite ? celsius : 0
        if inCelsius { return "\(Int(value.rounded())) °C" }
        return "\(Int((value * 9 / 5 + 32).rounded())) °F"
    }

    /// "3:05" for 185 minutes.
    public static func hoursMinutes(_ minutes: Int) -> String {
        let m = max(0, minutes)
        let mm = m % 60
        return "\(m / 60):" + (mm < 10 ? "0\(mm)" : "\(mm)")
    }

    /// Memory pressure as a word.
    public static func pressure(_ pressure: SystemSnapshot.MemoryPressure) -> String {
        switch pressure {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        }
    }

    /// `ProcessInfo.ThermalState` names as shown to the user.
    public static func thermal(_ state: String) -> String {
        switch state {
        case "fair": return "Warm"
        case "serious": return "Hot"
        case "critical": return "Overheating"
        default: return "Cool"
        }
    }

    private static func compact(_ value: Double) -> String {
        value < 10 ? trimmed(String(format: "%.1f", value)) : String(Int(value.rounded()))
    }

    private static func trimmed(_ s: String) -> String {
        s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
