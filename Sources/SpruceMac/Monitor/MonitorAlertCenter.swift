import Foundation
import SpruceCore

/// Runs the alert rules on every sample and posts notifications through
/// `Notifier`. Cooldowns are persisted so a relaunch does not re-alert.
/// Used on the main thread only.
final class MonitorAlertCenter {
    private var engine: MonitorAlertEngine
    private let store: JSONFileStore<MonitorAlertState>

    init(url: URL = SprucePaths.applicationSupport.appendingPathComponent("monitor-alerts.json")) {
        store = JSONFileStore(url: url)
        var state = store.load() ?? MonitorAlertState()
        // Sustain windows describe the previous session; start them afresh.
        state.lowDiskStreak = 0
        state.criticalPressureSince = nil
        state.highCPUSince = [:]
        engine = MonitorAlertEngine(state: state)
    }

    func process(_ sample: MonitorAlertSample, settings: MonitorAlertSettings) {
        let alerts = engine.evaluate(sample, settings: settings)
        guard !alerts.isEmpty else { return }
        for alert in alerts {
            let target: (module: ModuleID, tool: String?)
            switch alert.kind {
            case .lowDisk: target = (.cleanup, "cleanup.systemJunk")
            case .trashSize: target = (.cleanup, "cleanup.trash")
            case .memoryPressure, .highCPUApp: target = (.performance, "performance.consumers")
            }
            Notifier.post(id: alert.id, title: alert.title, body: alert.body,
                          module: target.module.rawValue, tool: target.tool)
        }
        try? store.save(engine.state)
    }
}
