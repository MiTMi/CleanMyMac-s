import AppKit
import Combine
import QuickLook
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the SpaceMap module. CONTRACT: keep the type name `SpaceMapView` and `init()`.
struct SpaceMapView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SpaceMapRootScreen(engine: model.spaceMap)
    }
}

/// Hosts the Space Map journey (location → scanning → map → Trash → done), routes the
/// `spaceMap` tool id and owns the removal confirmation and Quick Look.
struct SpaceMapRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: SpaceMapScreenModel

    init(engine: SpaceMapEngine) {
        _screen = State(initialValue: SpaceMapScreenModel.shared(for: engine))
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
            screen.refreshTargets()
            consumePendingTool()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            screen.refreshTargets()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            screen.refreshTargets()
        }
        .sheet(isPresented: $screen.removalSheetShown) {
            SpaceMapRemovalSheet(screen: screen)
        }
        .quickLookPreview($screen.previewURL)
    }

    private var routeKey: String {
        switch screen.phase {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .results: return "results"
        case .removing: return "removing"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen.phase {
        case .idle:
            SpaceMapTargetsScreen(screen: screen, hasFullDiskAccess: model.hasFullDiskAccess)
        case .scanning:
            SpaceMapScanningScreen(screen: screen)
        case .results:
            SpaceMapResultsScreen(screen: screen, hasFullDiskAccess: model.hasFullDiskAccess)
        case .removing:
            ScanningView(module: .spaceMap, progress: screen.removalProgress, title: "Moving to the Trash…",
                         showsBytes: false)
        case .done:
            if let outcome = screen.outcome {
                DoneView(module: .spaceMap, outcome: outcome, headline: doneHeadline(outcome),
                         doneTitle: "Back to Map", onDone: { screen.showRemaining() })
            } else {
                SpaceMapResultsScreen(screen: screen, hasFullDiskAccess: model.hasFullDiskAccess)
            }
        case .failed(let message):
            FailureView(module: .spaceMap, message: message, title: "Couldn't map this location.",
                        retryTitle: "Try Again", onRetry: { screen.retry() })
        }
    }

    private func doneHeadline(_ outcome: RunOutcome) -> String? {
        guard outcome.freedBytes > 0 else { return nil }
        return "\(ByteFormat.string(outcome.freedBytes)) moved to the Trash"
    }

    private func consumePendingTool() {
        guard model.pendingTool == "spaceMap" else { return }
        model.pendingTool = nil
        screen.openFromTool()
    }
}
