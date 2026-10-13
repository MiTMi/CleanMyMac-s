import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Performance module. CONTRACT: keep the type name `PerformanceView` and `init()`.
struct PerformanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PerformanceRootScreen(engine: model.performance)
    }
}

/// Hosts the hub and the four tools, routes `performance.*` tool ids and shows the
/// module's sheets, confirmations and toasts.
struct PerformanceRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: PerformanceScreenModel

    init(engine: PerformanceEngine) {
        _screen = State(initialValue: PerformanceScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
            PerformanceToastHost(screen: screen)
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .onAppear {
            screen.appeared()
            consumePendingTool()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .sheet(item: $screen.quitPrompt) { prompt in
            PerformanceQuitAppsSheet(prompt: prompt,
                                     onQuit: { screen.quitAppsAndRun() },
                                     onSkip: { screen.runWithoutBlockedTasks() },
                                     onCancel: { screen.cancelQuitPrompt() })
        }
        .modifier(PerformanceConfirmations(screen: screen))
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
            PerformanceHubScreen(screen: screen)
        case .tool(.maintenance):
            PerformanceMaintenanceScreen(screen: screen)
        case .tool(.loginItems):
            PerformanceStartupScreen(screen: screen, tool: .loginItems)
        case .tool(.backgroundItems):
            PerformanceStartupScreen(screen: screen, tool: .backgroundItems)
        case .tool(.consumers):
            PerformanceConsumersScreen(screen: screen)
        }
    }

    private func consumePendingTool() {
        guard let toolID = model.pendingTool, let tool = PerformanceTool(toolID: toolID) else { return }
        model.pendingTool = nil
        screen.open(tool)
    }
}

// MARK: - Confirmations

/// Remove-items and force-quit confirmations.
private struct PerformanceConfirmations: ViewModifier {
    @Bindable var screen: PerformanceScreenModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(removalTitle, isPresented: $screen.confirmRemoval, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { screen.confirmRemove() }
                Button("Cancel", role: .cancel) { screen.cancelRemoval() }
            } message: {
                Text(removalMessage)
            }
            .confirmationDialog(forceQuitTitle, isPresented: $screen.confirmForceQuit, titleVisibility: .visible) {
                Button("Force Quit", role: .destructive) { screen.confirmForceQuitNow() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Unsaved changes in it will be lost.")
            }
    }

    private var removalTitle: String {
        let items = screen.removalCandidates
        if items.count == 1, let only = items.first { return "Remove \u{201C}\(only.name)\u{201D}?" }
        return "Remove \(CountFormat.items(items.count))?"
    }

    private var removalMessage: String {
        let items = screen.removalCandidates
        let hasLogin = items.contains { $0.kind == .loginItem }
        let hasLaunch = items.contains { $0.kind != .loginItem }
        var parts: [String] = []
        if hasLogin { parts.append("Login items stop opening when you log in.") }
        if hasLaunch {
            parts.append("Background items are stopped and their files move to the Trash, where you can put them back.")
        }
        if items.contains(where: { $0.kind == .systemDaemon }) {
            parts.append("System daemons need your administrator password.")
        }
        parts.append("The apps themselves stay installed and may add them again; turning an item off is the reversible choice.")
        return parts.joined(separator: " ")
    }

    private var forceQuitTitle: String {
        "Force quit \(screen.forceQuitCandidate?.name ?? "this app")?"
    }
}

// MARK: - Quit apps sheet

/// "Close these apps first?" before tasks that need an app closed (Mail compaction).
struct PerformanceQuitAppsSheet: View {
    var prompt: PerformanceQuitPrompt
    var onQuit: () -> Void
    var onSkip: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let names = prompt.apps.map(\.name)
        PrismSheetCard(title: names.count == 1 ? "Close \(names[0]) first?" : "Close these apps first?",
                       message: "Some selected tasks work on data these apps keep open. They're asked to quit normally, so they can offer to save first.",
                       primaryTitle: "Close and Run", onCancel: onCancel, onPrimary: onQuit) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(prompt.apps, id: \.bundleID) { app in
                    HStack(spacing: Spacing.s) {
                        ItemIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID),
                                 symbol: "app", size: 26, module: .performance)
                        Text(app.name)
                            .font(SpruceFont.bodyStrong)
                            .foregroundStyle(Ink.primary)
                        Spacer()
                        Text(tasksNeeding(app))
                            .font(SpruceFont.caption)
                            .foregroundStyle(PrismInk(contrast).tertiary)
                            .lineLimit(1)
                    }
                }
                if prompt.tasks.count > prompt.apps.count {
                    PrismTextButton(title: "Run the other tasks without closing", symbol: "forward.end", module: .performance,
                                    action: onSkip)
                        .padding(.top, Spacing.xs)
                }
            }
        }
    }

    private func tasksNeeding(_ app: PerformanceAppToQuit) -> String {
        prompt.tasks.filter { id in PerformanceTaskCatalog.definition(id).appsToQuit.contains { $0.bundleID == app.bundleID } }
            .map { PerformanceTaskCatalog.definition($0).title }
            .joined(separator: ", ")
    }
}

// MARK: - Toast

/// Bottom toast with auto-dismissal after six seconds.
struct PerformanceToastHost: View {
    @Bindable var screen: PerformanceScreenModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = screen.toast {
                PrismToast(message: toast.message,
                           symbol: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                           tint: toast.isError ? StatusColor.warning : StatusColor.success,
                           actionTitle: toast.actionTitle,
                           action: toast.action == nil ? nil : { screen.performToastAction() })
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
