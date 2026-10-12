import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Checkup module. CONTRACT: keep the type name `CheckupView` and `init()`.
///
/// The journey lives in `CheckupSession.shared`, so a scan or run keeps going (and its
/// results stay) while the user visits other modules.
@MainActor
struct CheckupView: View {
    /// Tool id other screens may pass to `AppModel.open(.checkup, tool:)` to start a scan.
    static let scanToolID = "checkup.scan"

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var session: CheckupSession { CheckupSession.shared }

    init() {}

    var body: some View {
        ZStack {
            phaseContent
                .id(session.phase)
                .transition(.prismPhase(reduceMotion: reduceMotion))
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: session.phase)
        .onAppear { handle(tool: model.pendingTool) }
        .onChange(of: model.pendingTool) { _, tool in handle(tool: tool) }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .idle:
            CheckupIdleScreen(session: session, onScan: startScan)
        case .scanning:
            CheckupScanningScreen(session: session)
        case .results:
            CheckupResultsScreen(session: session, onScanAgain: startScan)
        case .running:
            CheckupRunningScreen(session: session)
        case .done:
            CheckupDoneScreen(session: session)
        }
    }

    private func startScan() {
        model.refreshPermissions()
        session.startScan(contributors: model.checkupContributors,
                          included: model.settings.settings.checkupModules)
    }

    private func handle(tool: String?) {
        guard let tool, tool.hasPrefix("checkup") else { return }
        model.pendingTool = nil
        if tool == Self.scanToolID, session.phase == .idle,
           !model.settings.settings.checkupModules.isEmpty {
            startScan()
        }
    }
}
