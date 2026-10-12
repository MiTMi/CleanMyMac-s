import Foundation
import IOKit
import IOKit.ps
import SpruceCore

/// Battery / UPS state (IOPowerSources + `AppleSmartBattery`) and Bluetooth
/// peripheral batteries (IORegistry). Everything here is best-effort: a Mac mini
/// has no internal battery, and accessories that do not publish a battery level
/// are simply not listed.
enum MonitorPowerProbe {
    // IOPSKeys.h string values (kIOPS…Key / …Value).
    private enum Key {
        static let type = "Type"
        static let internalBattery = "InternalBattery"
        static let ups = "UPS"
        static let isPresent = "Is Present"
        static let name = "Name"
        static let currentCapacity = "Current Capacity"
        static let maxCapacity = "Max Capacity"
        static let isCharging = "Is Charging"
        static let isCharged = "Is Charged"
        static let powerSourceState = "Power Source State"
        static let acPower = "AC Power"
        static let timeToEmpty = "Time to Empty"
        static let timeToFull = "Time to Full Charge"
    }

    /// The internal battery, else an attached UPS, else nil (a Mac mini on mains).
    static func read() -> MonitorPowerInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var battery: [String: Any]?
        var ups: [String: Any]?
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let present = description[Key.isPresent] as? Bool, !present { continue }
            let type = description[Key.type] as? String
            if type == Key.internalBattery, battery == nil {
                battery = description
            } else if type == Key.ups, ups == nil {
                ups = description
            }
        }
        if let battery {
            let smart = smartBattery()
            return info(from: battery, kind: .internalBattery, health: smart.health, cycles: smart.cycles)
        }
        if let ups {
            return info(from: ups, kind: .ups, health: nil, cycles: nil)
        }
        return nil
    }

    private static func info(from description: [String: Any], kind: MonitorPowerInfo.Kind,
                             health: Double?, cycles: Int?) -> MonitorPowerInfo {
        let current = (description[Key.currentCapacity] as? NSNumber)?.doubleValue
        let maximum = (description[Key.maxCapacity] as? NSNumber)?.doubleValue ?? 100
        let level = current.map { maximum > 0 ? $0 / maximum : $0 / 100 }
        let state = description[Key.powerSourceState] as? String
        return MonitorPowerInfo(
            kind: kind,
            name: (description[Key.name] as? String) ?? (kind == .ups ? "UPS" : "Battery"),
            level: level,
            isCharging: (description[Key.isCharging] as? Bool) ?? false,
            isCharged: (description[Key.isCharged] as? Bool) ?? false,
            onExternalPower: state == Key.acPower,
            minutesToEmpty: (description[Key.timeToEmpty] as? NSNumber)?.intValue,
            minutesToFull: (description[Key.timeToFull] as? NSNumber)?.intValue,
            health: health,
            cycleCount: cycles
        )
    }

    /// Cycle count and health (full-charge / design capacity) from `AppleSmartBattery`.
    private static func smartBattery() -> (health: Double?, cycles: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func integer(_ key: String) -> Int? {
            guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() else { return nil }
            return (value as? NSNumber)?.intValue
        }
        let health = MonitorBatteryMath.health(maxCapacity: integer("MaxCapacity"),
                                               rawMaxCapacity: integer("AppleRawMaxCapacity"),
                                               designCapacity: integer("DesignCapacity"))
        return (health, integer("CycleCount"))
    }

    /// Peripherals that publish `BatteryPercent` in the IORegistry (Magic Keyboard,
    /// Mouse and Trackpad over Bluetooth or USB).
    static func devices() -> [MonitorDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [MonitorDevice] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  let percent = (properties["BatteryPercent"] as? NSNumber)?.intValue else { continue }
            let name = (properties["Product"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Accessory"
            let id = (properties["DeviceAddress"] as? String)
                ?? (properties["SerialNumber"] as? String)
                ?? name
            devices.append(MonitorDevice(id: id, name: name, batteryPercent: percent))
        }
        return MonitorDevice.arranged(devices)
    }
}
