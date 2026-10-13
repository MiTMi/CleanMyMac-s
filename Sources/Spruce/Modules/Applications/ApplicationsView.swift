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
    @State private var isDropTargeted = false

    init(engine: ApplicationsEngine) {
        _screen = State(initialValue: ApplicationsScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
            if isDropTargeted {
                ApplicationsDropOverlay()
                    .transition(.opacity)
            }
            ApplicationsToastHost(screen: screen)
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .animation(Motion.quick, value: isDropTargeted)
        // Apps dropped here open in the Uninstaller; installers are listed in Installers.
        // A drop only shows things — removal always needs its own confirmation.
        .dropDestination(for: URL.self) { urls, _ in
            screen.receive(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted && screen.runState == .none && !screen.isInstallingUpdates
        }
        .onAppear {
            consumePendingTool()
            consumePendingFiles()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .onChange(of: model.pendingFiles) { _, _ in consumePendingFiles() }
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
        // Files that came with the navigation are shown after the tool opened.
        consumePendingFiles()
    }

    /// Apps and installers handed over from Finder (Services, Open With, the Dock icon).
    private func consumePendingFiles() {
        guard model.selection == .applications, !model.pendingFiles.isEmpty else { return }
        let files = model.pendingFiles.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "app" || ApplicationsScreenModel.installerExtensions.contains(ext)
        }
        guard !files.isEmpty else { return }
        model.pendingFiles = []
        screen.receive(files)
    }
}

/// Shown while apps or installers are dragged over the module.
struct ApplicationsDropOverlay: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        ZStack {
            RoundedRectangle(cornerRadius: Radius.container, style: .continuous)
                .fill(Color.black.opacity(0.35))
            RoundedRectangle(cornerRadius: Radius.container, style: .continuous)
                .strokeBorder(ModuleID.applications.palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            VStack(spacing: Spacing.s) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(ModuleID.applications.palette.accentText)
                Text("Drop apps to uninstall")
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                Text("Spruce shows their files first. Installers (.dmg, .pkg, .zip) go to Installers.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(ink.secondary)
            }
            .padding(Spacing.xl)
        }
        .padding(Spacing.l)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
