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
    /// Scan › Run Selected… asks here first (the Run orb runs directly).
    @State private var confirmMenuRun = false
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
        .onChange(of: session.phase) { _, phase in
            if phase != .results { confirmMenuRun = false }
        }
        .focusedSceneValue(\.spruceFlow, menuActions)
        .confirmationDialog(menuRunTitle, isPresented: $confirmMenuRun, titleVisibility: .visible) {
            Button("Run") {
                // `requestRun` still asks to quit apps that hold up selected items.
                session.requestRun()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only what's selected is touched. Checkup runs the areas one after another.")
        }
    }

    // MARK: Main menu

    /// Scan and Edit menu actions for the current phase. Run Selected… only opens the
    /// confirmation above; nothing is offered while a review sheet or the quit-apps
    /// prompt is open.
    private var menuActions: SpruceFlowActions {
        var actions = SpruceFlowActions()
        let modules = model.settings.settings.checkupModules
        switch session.phase {
        case .idle, .done:
            if !modules.isEmpty { actions.scanAgain = { startScan() } }
        case .scanning:
            actions.stop = { session.stopScan() }
        case .running:
            if !session.stopRequested { actions.stop = { session.requestStop() } }
        case .results:
            let blocked = session.isReviewing || session.quitPrompt != nil || session.isWaitingForApps
                || !session.rescanning.isEmpty
            guard !blocked else { break }
            if !modules.isEmpty { actions.scanAgain = { requestScanAgain() } }
            let summary = session.summary
            if !summary.isEmpty { actions.reviewAndRun = { confirmMenuRun = true } }
            if summary.selectableCount > 0 {
                actions.selectAll = { session.setAllTiles(selected: true) }
                actions.deselectAll = { session.setAllTiles(selected: false) }
                actions.selectRecommended = { session.selectRecommendedTiles() }
            }
        }
        return actions
    }

    private var menuRunTitle: String {
        let count = session.summary.modules.count
        return "Run \(CountFormat.items(count, singular: "area"))?"
    }

    /// Scan Again from the menu on the results screen: asks first when it would clear
    /// the tiles and review choices the user set (the results screen shows the alert).
    private func requestScanAgain() {
        if session.hasCustomChoices {
            session.scanAgainPrompt = true
        } else {
            startScan()
        }
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

    /// `checkup.scan` (weekly reminder, Activity's Run Checkup, Dock menu) starts a fresh
    /// scan unless one is running or the results on screen are recent; stale results that
    /// hold the user's choices ask first. The app stays open for weeks, so an old results
    /// or completion screen must not stand in for the scan that was asked for.
    private func handle(tool: String?) {
        guard let tool, tool.hasPrefix("checkup") else { return }
        model.pendingTool = nil
        guard tool == Self.scanToolID, !model.settings.settings.checkupModules.isEmpty else { return }
        switch CheckupScanRequest.response(to: session.scanRequestScreen) {
        case .startScan:
            startScan()
        case .askToScanAgain:
            session.scanAgainPrompt = true
        case .showCurrent:
            break
        }
    }
}
