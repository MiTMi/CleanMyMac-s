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
/// `spaceMap` tool id, maps folders handed over from Finder, and owns the removal
/// confirmation and Quick Look.
struct SpaceMapRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: SpaceMapScreenModel
    @State private var isDropTargeted = false

    init(engine: SpaceMapEngine) {
        _screen = State(initialValue: SpaceMapScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
            if isDropTargeted {
                SpaceMapDropOverlay()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .animation(Motion.quick, value: isDropTargeted)
        // A folder dropped anywhere on the module (the location cards included) is mapped;
        // a file maps the folder it is in. Mapping never removes anything.
        .dropDestination(for: URL.self) { urls, _ in
            screen.receiveDrop(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted && screen.acceptsDrops
        }
        .onAppear {
            screen.refreshTargets()
            consumePendingTool()
            consumePendingFiles()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .onChange(of: model.pendingFiles) { _, _ in consumePendingFiles() }
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
        // A folder that came with the navigation is mapped once the tool is open.
        consumePendingFiles()
    }

    /// A folder from Finder ("Map Folder with Spruce", the Dock icon, Open With) becomes the
    /// root of the map (a file maps its enclosing folder). Mapping never removes anything.
    private func consumePendingFiles() {
        guard let first = model.takePendingFiles(for: .spaceMap).first else { return }
        screen.mapFolder(first)
    }
}

/// Shown while a folder is dragged over Space Map.
struct SpaceMapDropOverlay: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let palette = ModuleID.spaceMap.palette
        ZStack {
            RoundedRectangle(cornerRadius: Radius.container, style: .continuous)
                .fill(Color.black.opacity(0.35))
            RoundedRectangle(cornerRadius: Radius.container, style: .continuous)
                .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            VStack(spacing: Spacing.s) {
                Image(systemName: "circle.hexagongrid")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(palette.accentText)
                Text("Drop a folder to map it")
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                Text("A file maps the folder it's in. Nothing is moved or removed.")
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
