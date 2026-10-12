import Darwin
import Foundation
import SpruceCore

/// Real-time protection: watches the launchd folders malware uses to stay on a Mac and
/// alerts when a new third-party startup item appears (notify-only, never removes on its
/// own). Each new item is evaluated with the malware scanner, so known threats and
/// suspicious items get a stronger alert.
///
/// Folder changes arrive through `DispatchSource` file-system sources (one per folder);
/// a one-minute timer re-checks everything as a fallback and picks up folders that are
/// created later. Alerts respect Settings › Protection (`realtimeProtection`), the
/// threat-notification toggle (`notifyThreats`) and the ignore list.
public final class ProtectionRealtimeMonitor: @unchecked Sendable {
    /// Posted on the main thread for every new startup item; `userInfo["event"]` holds the
    /// `ProtectionRealtimeEvent`.
    public static let eventNotification = Notification.Name("SpruceProtectionRealtimeEvent")
    public static let eventKey = "event"

    struct Folder: Hashable {
        var path: String
        var domain: ProtectionLaunchDomain
        var kind: ProtectionItemKind
    }

    private let probe: ProtectionMacSystemProbe
    private let queue = DispatchQueue(label: "app.spruce.protection.realtime", qos: .utility)
    private let lock = NSLock()

    // Confined to `queue`.
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var snapshots: [String: Set<String>] = [:]
    private var timer: DispatchSourceTimer?
    private var pendingCheck: DispatchWorkItem?
    private var active = false

    // Guarded by `lock`.
    private var runningFlag = false
    private var events: [ProtectionRealtimeEvent] = []

    init(probe: ProtectionMacSystemProbe) {
        self.probe = probe
    }

    /// True while the folders are being watched.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return runningFlag
    }

    /// New startup items noticed since launch, newest first (at most 50).
    public var recentEvents: [ProtectionRealtimeEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    /// The watched folders.
    var folders: [Folder] {
        [
            Folder(path: NSHomeDirectory() + "/Library/LaunchAgents", domain: .user, kind: .launchAgent),
            Folder(path: "/Library/LaunchAgents", domain: .user, kind: .launchAgent),
            Folder(path: "/Library/LaunchDaemons", domain: .system, kind: .launchDaemon),
        ]
    }

    /// Starts watching (idempotent). Items already present are not reported.
    public func start() {
        queue.async { [weak self] in
            guard let self, !self.active else { return }
            self.active = true
            self.setRunning(true)
            for folder in self.folders {
                self.snapshots[folder.path] = Self.listing(folder.path)
                self.attach(folder)
            }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))
            timer.setEventHandler { [weak self] in self?.check() }
            self.timer = timer
            timer.resume()
        }
    }

    /// Stops watching (idempotent).
    public func stop() {
        queue.async { [weak self] in
            guard let self, self.active else { return }
            self.active = false
            self.setRunning(false)
            self.pendingCheck?.cancel()
            self.pendingCheck = nil
            self.timer?.cancel()
            self.timer = nil
            for source in self.sources.values { source.cancel() }
            self.sources.removeAll()
            self.snapshots.removeAll()
        }
    }

    // MARK: Watching (on `queue`)

    private func setRunning(_ value: Bool) {
        lock.lock()
        runningFlag = value
        lock.unlock()
    }

    private func attach(_ folder: Folder) {
        guard sources[folder.path] == nil else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename],
                                                               queue: queue)
        let path = folder.path
        source.setEventHandler { [weak self] in
            guard let self, let current = self.sources[path] else { return }
            let mask = current.data
            if mask.contains(.delete) || mask.contains(.rename) {
                // The folder itself went away or was replaced: re-attach on the next check.
                current.cancel()
                self.sources[path] = nil
            }
            self.scheduleCheck()
        }
        source.setCancelHandler {
            close(fd)
        }
        sources[folder.path] = source
        source.resume()
    }

    /// Coalesces bursts of events (installers write several files at once).
    private func scheduleCheck() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pendingCheck = work
        queue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func check() {
        guard active else { return }
        var added: [(Folder, String)] = []
        for folder in folders {
            if sources[folder.path] == nil { attach(folder) }
            let current = Self.listing(folder.path)
            let previous = snapshots[folder.path] ?? []
            for name in ProtectionLaunchWatch.addedItems(previous: previous, current: current) {
                added.append((folder, folder.path + "/" + name))
            }
            snapshots[folder.path] = current
        }
        guard !added.isEmpty else { return }
        let home = NSHomeDirectory()
        let scanner = ProtectionMalwareScanner(space: ProtectionPathSpace(home: home), probe: probe)
        let threshold = ProtectionScanDepth.balanced.heuristicThreshold
        let newEvents = added.map { folder, path -> ProtectionRealtimeEvent in
            let item = ProtectionLaunchItem.parse(path: path, domain: folder.domain, kind: folder.kind, home: home)
            let finding = scanner.evaluateLaunchPlist(path: path, domain: folder.domain, kind: folder.kind, threshold: threshold)
            return ProtectionRealtimeEvent(path: path, label: item.label, domain: folder.domain, kind: folder.kind,
                                           finding: finding)
        }
        DispatchQueue.main.async { [weak self] in
            self?.deliver(newEvents)
        }
    }

    private static func listing(_ path: String) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
    }

    // MARK: Delivery (main thread)

    private func deliver(_ newEvents: [ProtectionRealtimeEvent]) {
        let settings = SettingsStore.shared.settings
        guard settings.realtimeProtection else { return }
        let visible = newEvents.filter { !settings.isIgnored(path: $0.path) }
        guard !visible.isEmpty else { return }
        lock.lock()
        events = Array((visible.reversed() + events).prefix(50))
        lock.unlock()
        for event in visible {
            if settings.notifyThreats {
                Notifier.post(id: "app.spruce.protection.realtime.\(event.id.uuidString)", title: event.notificationTitle,
                              body: event.notificationBody, module: ModuleID.protection.rawValue, tool: "protection.malware")
            }
            if event.isThreat {
                HistoryStore.shared.record(ActivityEntry(module: .protection, kind: .other, count: 1,
                                                         summary: "Real-time protection flagged \(event.name)"))
            }
            NotificationCenter.default.post(name: Self.eventNotification, object: self, userInfo: [Self.eventKey: event])
        }
    }
}
