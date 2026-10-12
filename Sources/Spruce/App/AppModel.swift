import Foundation
import Observation
import SpruceCore
import SpruceMac

/// App-wide state: navigation, shared stores, and the module engines.
///
/// CONTRACT: module views read engines and stores from here via
/// `@Environment(AppModel.self)`. Engines are created once and live for the app's
/// lifetime, so scan results survive navigation.
@MainActor
@Observable
final class AppModel {
    /// The app's single model (also reachable from AppKit callbacks such as notifications).
    static let shared = AppModel()

    var selection: ModuleID = .checkup
    /// Set by any view to request navigation to a module and (optionally) a sub-tool.
    var pendingTool: String?

    let settings = SettingsStore.shared
    let history = HistoryStore.shared
    let monitor = SystemMonitor.shared

    let cleanup = CleanupEngine()
    let protection = ProtectionEngine()
    let performance = PerformanceEngine()
    let applications = ApplicationsEngine()
    let clutter = ClutterEngine()
    let spaceMap = SpaceMapEngine()
    let cloudStorage = CloudStorageEngine()

    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess

    init() {}

    /// Every engine that can contribute to Checkup, in tile order. Checkup itself applies
    /// `settings.checkupModules` (it needs the full list for "Include" / "Try Again").
    var checkupContributors: [CheckupContributor] {
        [cleanup, protection, performance, applications, clutter]
    }

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }

    /// Navigate to a module, optionally opening one of its tools.
    func open(_ module: ModuleID, tool: String? = nil) {
        selection = module
        pendingTool = tool
    }
}
