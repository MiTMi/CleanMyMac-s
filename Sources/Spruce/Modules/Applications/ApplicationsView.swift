import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Applications module. CONTRACT: keep the type name `ApplicationsView` and `init()`.
struct ApplicationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ApplicationsRootScreen(engine: model.applications)
    }
}

/// Hosts the overview and the five tools, routes `applications.*` tool ids and presents
/// the module's confirmations and toasts.
struct ApplicationsRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: ApplicationsScreenModel

    init(engine: ApplicationsEngine) {
        _screen = State(initialValue: ApplicationsScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
            ApplicationsToastHost(screen: screen)
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .onAppear { consumePendingTool() }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .sheet(item: $screen.uninstallRequest) { request in
            ApplicationsUninstallSheet(request: request,
                                       onConfirm: { screen.confirmUninstall() },
                                       onCancel: { screen.cancelUninstall() })
        }
        .sheet(item: $screen.updateQuitPrompt) { prompt in
            ApplicationsUpdateQuitSheet(prompt: prompt,
                                        onQuit: { screen.quitAndInstall() },
                                        onSkip: { screen.installSkippingOpen() },
                                        onCancel: { screen.cancelQuitPrompt() })
        }
        .sheet(item: $screen.extensionRemoval) { ext in
            ApplicationsExtensionRemovalSheet(ext: ext,
                                              onConfirm: { screen.confirmExtensionRemoval() },
                                              onCancel: { screen.extensionRemoval = nil })
        }
    }

    private var routeKey: String {
        switch screen.route {
        case .hub: return "hub"
        case .tool(let tool): return tool.rawValue
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen.route {
        case .hub:
            ApplicationsHubScreen(screen: screen)
        case .tool(.uninstaller):
            ApplicationsUninstallerScreen(screen: screen)
        case .tool(.updater):
            ApplicationsUpdaterScreen(screen: screen)
        case .tool(.leftovers):
            ApplicationsFilesScreen(screen: screen, review: screen.leftovers, tool: .leftovers)
        case .tool(.installers):
            ApplicationsFilesScreen(screen: screen, review: screen.installers, tool: .installers)
        case .tool(.extensions):
            ApplicationsExtensionsScreen(screen: screen)
        }
    }

    private func consumePendingTool() {
        guard let toolID = model.pendingTool, let tool = ApplicationsTool(toolID: toolID) else { return }
        model.pendingTool = nil
        screen.open(tool)
    }
}

// MARK: - Toast

/// Bottom toast that dismisses itself after six seconds.
struct ApplicationsToastHost: View {
    @Bindable var screen: ApplicationsScreenModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = screen.toast {
                PrismToast(message: toast.message,
                           symbol: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                           tint: toast.isError ? StatusColor.warning : StatusColor.success)
                    .frame(maxWidth: 640)
                    .padding(.bottom, Spacing.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: screen.toast?.id)
        .task(id: screen.toast?.id) {
            guard let id = screen.toast?.id else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if screen.toast?.id == id { screen.toast = nil }
        }
    }
}
