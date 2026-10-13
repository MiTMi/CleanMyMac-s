import Foundation
import XCTest
@testable import SpruceCore

final class MonitorDiskHealthTests: XCTestCase {
    private func plist(_ object: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }

    func testSMARTStatusValues() {
        XCTAssertEqual(MonitorDiskCondition(smartStatus: "Verified"), .verified)
        XCTAssertEqual(MonitorDiskCondition(smartStatus: "Failing"), .failing)
        XCTAssertEqual(MonitorDiskCondition(smartStatus: "Not Supported"), .notSupported)
        XCTAssertEqual(MonitorDiskCondition(smartStatus: nil), .unknown)
        XCTAssertEqual(MonitorDiskCondition(smartStatus: "whatever"), .unknown)
    }

    func testParsesVolumePlistAndPhysicalStore() throws {
        let data = try plist([
            "SMARTStatus": "Verified",
            "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]],
            "DeviceIdentifier": "disk3s1s1",
        ])
        let health = try XCTUnwrap(MonitorDiskHealth.parse(diskutilPlist: data))
        XCTAssertEqual(health.condition, .verified)
        XCTAssertNil(health.temperatureCelsius)
        XCTAssertEqual(MonitorDiskHealth.physicalWholeDisk(diskutilPlist: data), "disk0")
    }

    func testParsesNVMeDetails() throws {
        let data = try plist([
            "SMARTStatus": "Verified",
            "SMARTDeviceSpecificKeysMayVaryNotGuaranteed": ["PERCENTAGE_USED": 3, "TEMPERATURE": 311],
        ])
        let health = try XCTUnwrap(MonitorDiskHealth.parse(diskutilPlist: data))
        XCTAssertEqual(health.lifeLeftPercent, 97)
        XCTAssertEqual(try XCTUnwrap(health.temperatureCelsius), 37.85, accuracy: 0.01, "NVMe reports Kelvin")
        XCTAssertEqual(health.summary(inCelsius: true), "Healthy · 97% life left · 38 °C")
        XCTAssertEqual(health.summary(inCelsius: false), "Healthy · 97% life left · 100 °F")
    }

    func testImplausibleValuesAreDropped() throws {
        let data = try plist([
            "SMARTDeviceSpecificKeysMayVaryNotGuaranteed": ["PERCENTAGE_USED": 140, "TEMPERATURE": 9000],
        ])
        let health = try XCTUnwrap(MonitorDiskHealth.parse(diskutilPlist: data))
        XCTAssertEqual(health.lifeLeftPercent, 0, "worn past its rating")
        XCTAssertNil(health.temperatureCelsius)
        XCTAssertEqual(health.condition, .unknown)
        XCTAssertNil(MonitorDiskHealth.parse(diskutilPlist: Data("not a plist".utf8)))
        XCTAssertNil(MonitorDiskHealth.parse(diskutilPlist: Data()))
    }

    func testWholeDiskNames() {
        XCTAssertEqual(MonitorDiskHealth.wholeDisk(of: "disk0s2"), "disk0")
        XCTAssertEqual(MonitorDiskHealth.wholeDisk(of: "disk12"), "disk12")
        XCTAssertEqual(MonitorDiskHealth.wholeDisk(of: "/dev/disk4s1"), "disk4")
        XCTAssertNil(MonitorDiskHealth.wholeDisk(of: "disk"))
        XCTAssertNil(MonitorDiskHealth.wholeDisk(of: "disk0x"))
        XCTAssertNil(MonitorDiskHealth.wholeDisk(of: "-rf"))
        XCTAssertNil(MonitorDiskHealth.wholeDisk(of: "/Volumes/disk0"))
    }

    func testMergeKeepsFailingVerdict() {
        let volume = MonitorDiskHealth(condition: .failing)
        let physical = MonitorDiskHealth(condition: .verified, lifeLeftPercent: 90, temperatureCelsius: 40)
        let merged = physical.merged(over: volume)
        XCTAssertEqual(merged.condition, .failing)
        XCTAssertEqual(merged.lifeLeftPercent, 90)
        let unknown = MonitorDiskHealth(condition: .unknown, temperatureCelsius: 35)
        XCTAssertEqual(unknown.merged(over: MonitorDiskHealth(condition: .verified)).condition, .verified)
    }

    func testFailingDiskIsCriticalIssue() {
        var snap = SystemSnapshot()
        snap.diskTotal = 500_000_000_000
        snap.diskAvailable = 200_000_000_000
        let healthy = MonitorHealth.assess(snap, context: MonitorHealthContext())
        XCTAssertTrue(healthy.issues.isEmpty)
        let failing = MonitorHealth.assess(snap, context: MonitorHealthContext(diskFailing: true))
        XCTAssertEqual(failing.status, .critical)
        XCTAssertEqual(failing.issues.first?.kind, .diskHealth)
        XCTAssertEqual(failing.score, 60)
        XCTAssertEqual(failing.headline, "Startup disk is failing")
    }
}

final class MonitorVolumeTests: XCTestCase {
    func testWhichVolumesAreListed() {
        func list(_ path: String, root: Bool? = false, local: Bool? = true, browsable: Bool? = true,
                  ejectable: Bool? = false, removable: Bool? = false, onInternalDisk: Bool? = true) -> Bool {
            MonitorVolume.shouldList(path: path, isRootFileSystem: root, isLocal: local, isBrowsable: browsable,
                                     isEjectable: ejectable, isRemovable: removable, isInternal: onInternalDisk)
        }
        XCTAssertFalse(list("/", root: true, ejectable: true))
        XCTAssertFalse(list("/System/Volumes/Data", onInternalDisk: true))
        XCTAssertFalse(list("/Volumes/Second", onInternalDisk: true), "internal partition, not ejectable")
        XCTAssertTrue(list("/Volumes/Backup", ejectable: true, onInternalDisk: false))
        XCTAssertTrue(list("/Volumes/Card", removable: true))
        XCTAssertTrue(list("/Volumes/Installer", ejectable: true), "disk images can be ejected")
        XCTAssertFalse(list("/Volumes/Share", local: false, ejectable: true, onInternalDisk: false), "network shares skipped")
        XCTAssertFalse(list("/Volumes/Hidden", browsable: false, ejectable: true))
    }

    func testVolumeFigures() {
        let volume = MonitorVolume(path: "/Volumes/Backup", name: "", totalBytes: 1_000_000_000_000,
                                   availableBytes: 250_000_000_000)
        XCTAssertEqual(volume.name, "Backup")
        XCTAssertEqual(volume.usedFraction, 0.75, accuracy: 1e-9)
        XCTAssertEqual(volume.capacityText, "\(ByteFormat.string(250_000_000_000)) free of \(ByteFormat.string(1_000_000_000_000))")
        let odd = MonitorVolume(path: "/Volumes/X", name: "X", totalBytes: 10, availableBytes: 50)
        XCTAssertEqual(odd.availableBytes, 10)
        XCTAssertEqual(MonitorVolume.arranged([odd, volume, odd]).map(\.name), ["Backup", "X"])
    }

    func testLsofHolders() {
        let output = "p120\ncPreview\np121\ncTerminal\np120\ncPreview\np999\ncSpruce\n"
        let holders = MonitorEject.holders(fromLsof: output, excludingPIDs: [999])
        XCTAssertEqual(holders, [MonitorFileHolder(pid: 120, command: "Preview"),
                                 MonitorFileHolder(pid: 121, command: "Terminal")])
        XCTAssertTrue(MonitorEject.holders(fromLsof: "").isEmpty)
    }

    func testEjectMessages() {
        XCTAssertEqual(MonitorEject.failureMessage(volume: "Backup", holders: ["Preview"], reason: nil),
                       "\u{201C}Backup\u{201D} is in use by Preview. Quit it, then try again.")
        XCTAssertEqual(MonitorEject.failureMessage(volume: "Backup", holders: ["Preview", "Terminal", "Preview"], reason: nil),
                       "\u{201C}Backup\u{201D} is in use by Preview and Terminal. Quit them, then try again.")
        XCTAssertEqual(MonitorEject.failureMessage(volume: "B", holders: ["A", "C", "D", "E", "F"], reason: nil),
                       "\u{201C}B\u{201D} is in use by A, C, D and 2 more. Quit them, then try again.")
        XCTAssertEqual(MonitorEject.failureMessage(volume: "B", holders: [], reason: "The disk is busy."),
                       "\u{201C}B\u{201D} couldn't be ejected. The disk is busy.")
        XCTAssertEqual(MonitorEject.failureMessage(volume: "B", holders: [], reason: nil),
                       "\u{201C}B\u{201D} couldn't be ejected. It may be in use.")
    }
}

final class MonitorTrashScheduleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private let sig = MonitorTrashSignature(stamps: ["/Users/me/.Trash": 100])

    private func reading(_ status: MonitorTrashStatus = .measured(10), at date: Date? = nil,
                         signature: MonitorTrashSignature? = nil) -> MonitorTrashReading {
        MonitorTrashReading(status: status, date: date ?? t0, signature: signature ?? sig)
    }

    func testFirstReadingMeasures() {
        XCTAssertTrue(MonitorTrashSchedule.shouldMeasure(force: false, last: nil, current: sig, now: t0))
    }

    func testUnchangedTrashIsNotWalkedAgain() {
        let last = reading()
        XCTAssertFalse(MonitorTrashSchedule.shouldMeasure(force: false, last: last, current: sig, now: t0 + 60))
        XCTAssertFalse(MonitorTrashSchedule.shouldMeasure(force: false, last: last, current: sig, now: t0 + 1800))
        XCTAssertFalse(MonitorTrashSchedule.shouldMeasure(force: true, last: last, current: sig, now: t0 + 30),
                       "opening the menu right after a measurement doesn't walk again")
        XCTAssertTrue(MonitorTrashSchedule.shouldMeasure(force: true, last: last, current: sig, now: t0 + 700))
        XCTAssertTrue(MonitorTrashSchedule.shouldMeasure(force: false, last: last, current: sig, now: t0 + 3700),
                      "safety net for changes deep inside trashed folders")
    }

    func testChangedFolderOrNewVolumeMeasures() {
        let last = reading()
        let touched = MonitorTrashSignature(stamps: ["/Users/me/.Trash": 101])
        XCTAssertTrue(MonitorTrashSchedule.shouldMeasure(force: false, last: last, current: touched, now: t0 + 10))
        var mounted = sig
        mounted.stamps["/Volumes/Backup/.Trashes/501"] = 50
        XCTAssertTrue(MonitorTrashSchedule.shouldMeasure(force: false, last: last, current: mounted, now: t0 + 10))
    }

    func testNoAccessIsRetriedCheaply() {
        let last = reading(.needsAccess)
        XCTAssertFalse(MonitorTrashSchedule.shouldMeasure(force: false, last: last, current: sig, now: t0 + 20))
        XCTAssertTrue(MonitorTrashSchedule.shouldMeasure(force: false, last: last, current: sig, now: t0 + 61))
        XCTAssertTrue(MonitorTrashSchedule.shouldMeasure(force: true, last: last, current: sig, now: t0 + 5))
    }

    func testClockMovingBackMeasures() {
        XCTAssertTrue(MonitorTrashSchedule.shouldMeasure(force: false, last: reading(), current: sig, now: t0 - 100))
    }
}

final class MonitorCareTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 3_000_000)

    func testProtectionStates() {
        let scanned = now.addingTimeInterval(-2 * 86_400)
        let ok = MonitorProtectionSummary(realtimeEnabled: true, hasFullDiskAccess: true, unresolvedThreats: 0,
                                          lastScan: scanned, now: now)
        XCTAssertEqual(ok.state, .protected)
        XCTAssertEqual(ok.title, "Protected")
        XCTAssertEqual(ok.detail, "Real-time on · scanned 2 d ago")
        XCTAssertEqual(ok.action, .scan)
        XCTAssertEqual(ok.status, .good)

        let threats = MonitorProtectionSummary(realtimeEnabled: false, hasFullDiskAccess: false, unresolvedThreats: 2,
                                               lastScan: scanned, now: now)
        XCTAssertEqual(threats.state, .threats(2), "threats outrank everything")
        XCTAssertEqual(threats.title, "2 Threats")
        XCTAssertEqual(threats.action, .review)
        XCTAssertEqual(threats.status, .critical)

        let off = MonitorProtectionSummary(realtimeEnabled: false, hasFullDiskAccess: false, unresolvedThreats: 0,
                                           lastScan: nil, now: now)
        XCTAssertEqual(off.state, .off)
        XCTAssertEqual(off.action, .turnOn)
        XCTAssertEqual(off.actionTitle, "Turn On")
        XCTAssertEqual(off.detail, "Real-time protection is off · not scanned yet")

        let noAccess = MonitorProtectionSummary(realtimeEnabled: true, hasFullDiskAccess: false, unresolvedThreats: 0,
                                                lastScan: nil, now: now)
        XCTAssertEqual(noAccess.state, .needsAccess)
        XCTAssertEqual(noAccess.title, "Needs Access")
        XCTAssertEqual(noAccess.action, .allowAccess)
        XCTAssertEqual(noAccess.status, .attention)
    }

    func testWeeklyReminder() {
        XCTAssertFalse(MonitorReminder.weeklyCheckupDue(daysSinceCheckup: nil, enabled: true))
        XCTAssertFalse(MonitorReminder.weeklyCheckupDue(daysSinceCheckup: 6, enabled: true))
        XCTAssertTrue(MonitorReminder.weeklyCheckupDue(daysSinceCheckup: 7, enabled: true))
        XCTAssertFalse(MonitorReminder.weeklyCheckupDue(daysSinceCheckup: 9, enabled: false))
        XCTAssertEqual(MonitorReminder.weeklyCheckupTitle(days: 8), "Your weekly Checkup is due")
        XCTAssertEqual(MonitorReminder.weeklyCheckupTitle(days: 20), "It's been 20 days since your last Checkup")
    }

    func testFormatting() {
        XCTAssertEqual(MonitorFormat.ago(5), "just now")
        XCTAssertEqual(MonitorFormat.ago(12 * 60), "12 min ago")
        XCTAssertEqual(MonitorFormat.ago(3 * 3600 + 5), "3 h ago")
        XCTAssertEqual(MonitorFormat.ago(50 * 3600), "2 d ago")
        XCTAssertEqual(MonitorFormat.ago(-.infinity), "just now")
        XCTAssertEqual(MonitorFormat.temperature(37.6), "38 °C")
        XCTAssertEqual(MonitorFormat.temperature(37.78, inCelsius: false), "100 °F")
    }
}
