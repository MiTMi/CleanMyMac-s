import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the CloudStorage module. CONTRACT: keep the type name `CloudStorageView` and `init()`.
struct CloudStorageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CloudStorageRootScreen(engine: model.cloudStorage)
    }
}

/// Hosts the Cloud Storage journey (providers → scanning → results → freeing up →
/// done), routes the `cloudStorage` tool id and owns the confirmation sheet.
struct CloudStorageRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: CloudStorageScreenModel

    init(engine: CloudStorageEngine) {
        _screen = State(initialValue: CloudStorageScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
            if let toast = screen.toast {
                PrismToast(message: toast, symbol: "icloud.fill", tint: ModuleID.cloudStorage.palette.accentText)
                    .padding(.bottom, 132)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .onAppear {
            screen.refreshProviders()
            consumePendingTool()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .sheet(isPresented: $screen.confirmShown) {
            CloudStorageConfirmSheet(screen: screen)
        }
    }

    private var routeKey: String {
        switch screen.phase {
        case .providers: return "providers"
        case .scanning: return "scanning"
        case .results: return "results"
        case .freeingUp: return "freeingUp"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen.phase {
        case .providers:
            CloudStorageProvidersScreen(screen: screen)
        case .scanning:
            ScanningView(module: .cloudStorage, progress: screen.scanProgress, title: "Measuring your cloud folders…",
                         onStop: { screen.cancelScan() },
                         steps: screen.scanningProviders.map { screen.scanStep(for: $0) })
        case .results:
            CloudStorageResultsScreen(screen: screen)
        case .freeingUp:
            ScanningView(module: .cloudStorage, progress: screen.workProgress, title: "Freeing up space on this Mac…")
        case .done:
            if let outcome = screen.outcome {
                DoneView(module: .cloudStorage, outcome: outcome, headline: doneHeadline(outcome),
                         doneTitle: "Back to Results", onDone: { screen.showResults() })
            } else {
                CloudStorageResultsScreen(screen: screen)
            }
        case .failed(let message):
            FailureView(module: .cloudStorage, message: message, title: "Couldn't measure your cloud folders.",
                        retryTitle: "Try Again", onRetry: { screen.retry() })
        }
    }

    private func doneHeadline(_ outcome: RunOutcome) -> String? {
        guard outcome.freedBytes > 0 else { return nil }
        return "\(ByteFormat.string(outcome.freedBytes)) freed on this Mac"
    }

    private func consumePendingTool() {
        guard model.pendingTool == "cloudStorage" else { return }
        model.pendingTool = nil
        screen.openFromTool()
    }
}
