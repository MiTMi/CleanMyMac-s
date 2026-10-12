import AppKit
import Combine
import QuickLook
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Clutter module. CONTRACT: keep the type name `ClutterView` and `init()`.
struct ClutterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ClutterRootScreen(engine: model.clutter)
    }
}

/// Hosts the Clutter journey (locations → scanning → dashboard and tools → Trash → done),
/// routes `clutter.*` tool ids and owns the shared confirmations and Quick Look.
struct ClutterRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: ClutterScreenModel

    init(engine: ClutterEngine) {
        _screen = State(initialValue: ClutterScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .onAppear {
            screen.refreshVolumes()
            consumePendingTool()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            screen.refreshVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            screen.refreshVolumes()
        }
        .sheet(item: $screen.removalRequest) { request in
            ClutterRemovalSheet(request: request,
                                onCancel: { screen.removalRequest = nil },
                                onConfirm: { removeAll in screen.confirmRemoval(allowRemovingAllCopies: removeAll) })
        }
        .confirmationDialog("Start a new scan?", isPresented: $screen.confirmNewScan, titleVisibility: .visible) {
            Button("New Scan") { screen.newScan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current results and your selection will be discarded. Nothing is removed.")
        }
        .quickLookPreview($screen.previewURL)
    }

    private var routeKey: String {
        switch screen.phase {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .results:
            switch screen.route {
            case .dashboard: return "dashboard"
            case .tool(let tool): return "tool.\(tool.rawValue)"
            }
        case .removing: return "removing"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen.phase {
        case .idle:
            ClutterIdleScreen(screen: screen)
        case .scanning:
            ScanningView(module: .clutter, progress: screen.progress, title: scanningTitle,
                         onStop: { screen.cancelScan() }, steps: screen.steps)
        case .results:
            results
        case .removing:
            ScanningView(module: .clutter, progress: screen.progress, title: "Moving to the Trash…",
                         showsBytes: false)
        case .done:
            if let outcome = screen.outcome {
                DoneView(module: .clutter, outcome: outcome, headline: doneHeadline(outcome),
                         doneTitle: "Done", onDone: { screen.showRemaining() })
            } else {
                results
            }
        case .failed(let message):
            FailureView(module: .clutter, message: message,
                        retryTitle: screen.canStartScan ? "Try Again" : "Choose a Location",
                        onRetry: {
                            if screen.canStartScan { screen.retry() } else { screen.dismissFailure() }
                        })
        }
    }

    @ViewBuilder
    private var results: some View {
        switch screen.route {
        case .dashboard:
            ClutterDashboardScreen(screen: screen)
        case .tool(.largeOld):
            ClutterLargeOldScreen(screen: screen)
        case .tool(.duplicates):
            ClutterDuplicatesScreen(screen: screen)
        case .tool(.similarImages):
            ClutterSimilarScreen(screen: screen)
        case .tool(.downloads):
            ClutterDownloadsScreen(screen: screen)
        }
    }

    private var scanningTitle: String {
        if let tool = screen.focusTool { return "Looking for \(tool.title.lowercased())…" }
        return "Looking for clutter…"
    }

    private func doneHeadline(_ outcome: RunOutcome) -> String? {
        guard outcome.freedBytes > 0 else { return nil }
        return "\(ByteFormat.string(outcome.freedBytes)) moved to the Trash"
    }

    private func consumePendingTool() {
        guard let toolID = model.pendingTool, let tool = ClutterTool(toolID: toolID) else { return }
        model.pendingTool = nil
        screen.open(tool)
    }
}
