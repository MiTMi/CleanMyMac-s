import Foundation

/// A point-in-time reading of the machine's vital signs.
/// Produced by `SystemMonitor` (SpruceMac); consumed by the monitor UI, health score and alerts.
public struct SystemSnapshot: Sendable, Equatable {
    public enum MemoryPressure: String, Sendable, Codable { case normal, warning, critical }

    public var date = Date()
    /// Overall CPU load, 0...1.
    public var cpuLoad: Double = 0
    public var cpuTemperature: Double?
    public var memoryTotal: Int64 = 0
    public var memoryUsed: Int64 = 0
    public var memoryPressure: MemoryPressure = .normal
    public var swapUsed: Int64 = 0
    public var diskTotal: Int64 = 0
    /// Available for important usage (includes purgeable space), like Finder shows.
    public var diskAvailable: Int64 = 0
    public var diskPurgeable: Int64 = 0
    public var trashSize: Int64 = 0
    public var batteryLevel: Double?          // 0...1, nil on desktops (Mac mini)
    public var batteryHealth: Double?         // max capacity / design capacity
    public var batteryCycles: Int?
    public var isCharging: Bool?
    public var networkDownBytesPerSec: Double = 0
    public var networkUpBytesPerSec: Double = 0
    public var uptime: TimeInterval = 0
    public var thermalState: String = "nominal"

    public init() {}

    public var diskUsedFraction: Double {
        diskTotal > 0 ? 1 - Double(diskAvailable) / Double(diskTotal) : 0
    }

    public var memoryUsedFraction: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }
}
