import AppKit
import Foundation
import SpruceCore

// Storage readers that are too slow for the 2-second sampling queue: the Trash walk,
// the startup disk's SMART status, mounted external drives and ejecting them.

// MARK: - Trash

/// Keeps the Trash size current without walking it on a timer. Every
/// `MonitorSampling.trashCheckInterval` it reads the Trash folders' modification dates and
/// walks the Trash only when they changed (see `MonitorTrashSchedule`). Runs on its own
/// serial queue, so a long walk never delays the CPU, memory and network samples.
final class MonitorTrashWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.spruce.monitor.trash", qos: .utility)
    /// Accessed only on `queue`.
    private var lastCheck = Date.distantPast
    private var last: MonitorTrashReading?

    /// Checks the Trash when due and calls `deliver` (on the watcher's queue) after a new
    /// measurement. `force` (the menu was opened) checks at once.
    func poll(force: Bool, deliver: @escaping @Sendable (MonitorTrashStatus) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            guard force || now.timeIntervalSince(self.lastCheck) >= MonitorSampling.trashCheckInterval else { return }
            self.lastCheck = now
            let folders = MonitorDiskProbe.trashFolders()
            let signature = MonitorDiskProbe.trashSignature(folders)
            guard MonitorTrashSchedule.shouldMeasure(force: force, last: self.last, current: signature, now: now) else { return }
            deliver(self.measure(folders: folders, signature: signature))
        }
    }

    /// Measures now, whatever the schedule says (after emptying the Trash).
    func measureNow() async -> MonitorTrashStatus {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .measuring)
                    return
                }
                let folders = MonitorDiskProbe.trashFolders()
                let status = self.measure(folders: folders, signature: MonitorDiskProbe.trashSignature(folders))
                continuation.resume(returning: status)
            }
        }
    }

    /// Runs on `queue`. The signature is taken before the walk, so a change made during
    /// it is picked up by the next check.
    private func measure(folders: [String], signature: MonitorTrashSignature) -> MonitorTrashStatus {
        let status = MonitorDiskProbe.trashStatus(folders)
        last = MonitorTrashReading(status: status, date: Date(), signature: signature)
        lastCheck = Date()
        return status
    }
}

// MARK: - Disk health

enum MonitorDiskHealthProbe {
    private static let diskutil = "/usr/sbin/diskutil"

    /// SMART status of the startup disk, plus life left and temperature when macOS
    /// reports them for the physical drive. `diskutil info` needs no administrator rights.
    static func read() async -> MonitorDiskHealth? {
        guard FileManager.default.isExecutableFile(atPath: diskutil) else { return nil }
        let volume = await Shell.run(diskutil, ["info", "-plist", "/"], timeout: 20)
        guard volume.status == 0 else { return nil }
        let volumeData = Data(volume.stdout.utf8)
        let volumeHealth = MonitorDiskHealth.parse(diskutilPlist: volumeData)
        guard let whole = MonitorDiskHealth.physicalWholeDisk(diskutilPlist: volumeData) else { return volumeHealth }
        let disk = await Shell.run(diskutil, ["info", "-plist", whole], timeout: 20)
        guard disk.status == 0, let physical = MonitorDiskHealth.parse(diskutilPlist: Data(disk.stdout.utf8)) else {
            return volumeHealth
        }
        return physical.merged(over: volumeHealth)
    }
}

// MARK: - External drives

enum MonitorVolumeProbe {
    private static let keys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsLocalKey,
        .volumeIsBrowsableKey, .volumeIsRootFileSystemKey, .volumeLocalizedFormatDescriptionKey,
    ]

    /// Mounted local volumes the user can eject (external disks, cards, disk images).
    static func externalVolumes() -> [MonitorVolume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                          options: [.skipHiddenVolumes]) ?? []
        var volumes: [MonitorVolume] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard MonitorVolume.shouldList(path: url.path, isRootFileSystem: values.volumeIsRootFileSystem,
                                           isLocal: values.volumeIsLocal, isBrowsable: values.volumeIsBrowsable,
                                           isEjectable: values.volumeIsEjectable, isRemovable: values.volumeIsRemovable,
                                           isInternal: values.volumeIsInternal) else { continue }
            volumes.append(MonitorVolume(
                path: url.path,
                name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
                totalBytes: Int64(values.volumeTotalCapacity ?? 0),
                availableBytes: Int64(values.volumeAvailableCapacity ?? 0),
                format: values.volumeLocalizedFormatDescription,
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal ?? false
            ))
        }
        return MonitorVolume.arranged(volumes)
    }
}

enum MonitorEjector {
    /// Unmounts and ejects the drive mounted at `path` (a normal eject: macOS refuses while
    /// files on it are open, so nothing is lost). Returns nil on success, else a message
    /// naming the apps that keep it busy when they can be found.
    static func eject(path: String, name: String) async -> String? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let failure: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: error.localizedDescription)
                }
            }
        }
        guard let failure else { return nil }
        // Still mounted elsewhere? Then it did go away (e.g. ejected by Finder meanwhile).
        if !FileManager.default.fileExists(atPath: path) { return nil }
        let holders = await holderNames(of: path)
        return MonitorEject.failureMessage(volume: name, holders: holders, reason: failure)
    }

    /// Apps with files open on the volume (`lsof` lists the user's own processes; system
    /// processes such as Spotlight can't be named without root).
    private static func holderNames(of path: String) async -> [String] {
        let lsof = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: lsof) else { return [] }
        // `+f --` makes lsof treat the mount point as a file system: every open file on it.
        let result = await Shell.run(lsof, ["-w", "+c", "0", "-Fpc", "+f", "--", path], timeout: 5)
        let holders = MonitorEject.holders(fromLsof: result.stdout, excludingPIDs: [getpid()])
        return await MainActor.run {
            holders.map { holder in
                NSRunningApplication(processIdentifier: holder.pid)?.localizedName ?? holder.command
            }
        }
    }
}
