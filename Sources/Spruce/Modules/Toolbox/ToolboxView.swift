import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Toolbox module. CONTRACT: keep the type name `ToolboxView` and `init()`.
struct ToolboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ToolboxRootScreen(screen: ToolboxScreenModel.shared)
    }
}

/// Hosts the hub and the Toolbox-only tools, and routes `toolbox.*` tool ids.
struct ToolboxRootScreen: View {
    @Bindable var screen: ToolboxScreenModel
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .onAppear {
            consumePendingTool()
            consumePendingFiles()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .onChange(of: model.pendingFiles) { _, _ in consumePendingFiles() }
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
            ToolboxHubScreen(screen: screen)
        case .tool(.shredder):
            ToolboxShredderScreen(shredder: screen.shredder, onBack: { screen.showHub() })
        case .tool(.screenCleaning):
            ToolboxScreenCleaningScreen(onBack: { screen.showHub() })
        case .tool(.emptyTrash):
            ToolboxEmptyTrashScreen(trash: screen.trash, onBack: { screen.showHub() })
        case .tool(.freeRAM):
            ToolboxTaskScreen(kind: .freeRAM, task: screen.memory, onBack: { screen.showHub() })
        case .tool(.flushDNS):
            ToolboxTaskScreen(kind: .flushDNS, task: screen.dns, onBack: { screen.showHub() })
        }
    }

    private func consumePendingTool() {
        guard let toolID = model.pendingTool, let tool = ToolboxLocalTool(toolID: toolID) else { return }
        model.pendingTool = nil
        screen.open(tool)
        // Files that came with the navigation are staged once the tool is open.
        consumePendingFiles()
    }

    /// Files from Finder ("Shred with Spruce", the Dock icon, Open With) that
    /// `AppModel.openFiles` sent to the Toolbox: the Shredder is its only file destination.
    /// They're listed unchecked; shredding still needs the Shredder's confirmation.
    private func consumePendingFiles() {
        let files = model.takePendingFiles(for: .toolbox)
        guard !files.isEmpty else { return }
        screen.stageForShredding(files)
    }
}

// MARK: - Shared chrome

/// Back link shown at the top-left of every Toolbox tool screen.
struct ToolboxBackBar: View {
    var onBack: () -> Void

    var body: some View {
        HStack {
            PrismBackButton(title: "Toolbox", action: onBack)
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }
}

/// A tool screen with the back bar layered over its content.
struct ToolboxToolFrame<Content: View>: View {
    var onBack: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ToolboxBackBar(onBack: onBack)
        }
    }
}
