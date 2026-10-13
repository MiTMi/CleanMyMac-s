import Foundation
import SpruceCore

/// Automatic malware scans while Spruce is open.
///
/// `NSBackgroundActivityScheduler` wakes this object about once an hour at a moment the
/// system finds convenient (on power, not busy). Each wake compares the schedule chosen on
/// the Protection hub (`ProtectionBackgroundSchedule`, weekly by default) with the date of
/// the last malware scan of any kind in Activity history, and runs a Quick scan when one
/// is due. The scheduler isn't persisted across launches, which is why it polls hourly
/// instead of waiting a whole week from each launch.
///
/// Results are kept by the engine for review (`ProtectionEngine.lastAutomaticReport`),
/// recorded in history like any malware scan, and announced with a notification when
/// something was found. Nothing is ever removed automatically.
final class ProtectionBackgroundScanner: @unchecked Sendable {
    static let identifier = "app.spruce.protection.background"
    static let defaultsKey = "app.spruce.protection.backgroundScan"

    /// The chosen schedule (per Mac, in user defaults).
    static var storedSchedule: ProtectionBackgroundSchedule {
        get { ProtectionBackgroundSchedule(setting: UserDefaults.standard.string(forKey: defaultsKey)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    private let lock = NSLock()
    private var scheduler: NSBackgroundActivityScheduler?
    private var isScanning = false
    private weak var engine: ProtectionEngine?

    /// Starts the hourly check (idempotent).
    func start(engine: ProtectionEngine) {
        lock.lock()
        defer { lock.unlock() }
        guard scheduler == nil else { return }
        self.engine = engine
        let scheduler = NSBackgroundActivityScheduler(identifier: Self.identifier)
        scheduler.repeats = true
        scheduler.interval = 3600
        scheduler.tolerance = 1800
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            guard let self else {
                completion(.finished)
                return
            }
            Task.detached(priority: .utility) {
                let result = await self.runIfDue()
                completion(result)
            }
        }
        self.scheduler = scheduler
    }

    /// True when the system asks running background work to stop for now.
    private var shouldDefer: Bool {
        lock.lock()
        defer { lock.unlock() }
        return scheduler?.shouldDefer ?? false
    }

    private var currentEngine: ProtectionEngine? {
        lock.lock()
        defer { lock.unlock() }
        return engine
    }

    private func runIfDue() async -> NSBackgroundActivityScheduler.Result {
        guard let engine = currentEngine else { return .finished }
        let schedule = Self.storedSchedule
        guard schedule != .off else { return .finished }
        let lastScan = await MainActor.run {
            HistoryStore.shared.history.entries.filter { $0.kind == .malwareScan }.map(\.date).max()
        }
        guard schedule.isDue(lastScan: lastScan) else { return .finished }
        if shouldDefer { return .deferred }
        guard beginScan() else { return .finished }
        defer { endScan() }
        _ = try? await engine.runAutomaticScan()
        return .finished
    }

    private func beginScan() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isScanning else { return false }
        isScanning = true
        return true
    }

    private func endScan() {
        lock.lock()
        isScanning = false
        lock.unlock()
    }
}
