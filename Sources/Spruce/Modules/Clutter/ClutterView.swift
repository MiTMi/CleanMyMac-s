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
/// routes `clutter.*` tool ids, adds folders dropped on it or handed over from Finder to
/// the places it scans, and owns the shared confirmations and Quick Look.
struct ClutterRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: ClutterScreenModel
    @State private var isDropTargeted = false

    init(engine: ClutterEngine) {
        _screen = State(initialValue: ClutterScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
            if isDropTargeted {
                ClutterDropOverlay()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { ClutterToastHost(screen: screen) }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .animation(Motion.quick, value: isDropTargeted)
        // Folders dropped anywhere on the module join the places Clutter scans. A drop never
        // starts a scan or removes anything.
        .dropDestination(for: URL.self) { urls, _ in
            screen.receiveFolders(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .onAppear {
            screen.refreshVolumes()
            consumePendingTool()
            consumePendingFiles()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .onChange(of: model.pendingFiles) { _, _ in consumePendingFiles() }
        // Location names, free space and availability are probed off the main thread;
        // probe again whenever they may have changed.
        .onChange(of: screen.locations) { _, _ in screen.refreshVolumes() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screen.refreshVolumes()
        }
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

    /// Folders from Finder ("Find Clutter with Spruce") join the places Clutter scans.
    private func consumePendingFiles() {
        let files = model.takePendingFiles(for: .clutter)
        guard !files.isEmpty else { return }
        screen.receiveFolders(files)
    }
}

/// Shown while folders are dragged over Clutter.
struct ClutterDropOverlay: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let palette = ModuleID.clutter.palette
        ZStack {
            RoundedRectangle(cornerRadius: Radius.container, style: .continuous)
                .fill(Color.black.opacity(0.35))
            RoundedRectangle(cornerRadius: Radius.container, style: .continuous)
                .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            VStack(spacing: Spacing.s) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(palette.accentText)
                Text("Drop folders to look for clutter in them")
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                Text("They join the places Clutter scans. Nothing is scanned or removed until you say so.")
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

/// Bottom toast that dismisses itself after six seconds.
struct ClutterToastHost: View {
    @Bindable var screen: ClutterScreenModel
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
