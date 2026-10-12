import Foundation
import Observation
import SpruceCore

/// Live system metrics for the menu bar monitor, Activity health score and alerts.
///
/// CONTRACT (used by Activity, Checkup and the menu bar — keep these):
/// * `SystemMonitor.shared`
/// * `snapshot: SystemSnapshot` (observable, refreshed while started)
/// * `start()` / `stop()` / `refresh()`
@Observable
public final class SystemMonitor {
    public static let shared = SystemMonitor()

    public private(set) var snapshot = SystemSnapshot()

    public init() {}

    public func start() {}
    public func stop() {}
    public func refresh() {}
}
