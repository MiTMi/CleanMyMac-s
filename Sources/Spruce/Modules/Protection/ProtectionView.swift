import AppKit
import Combine
import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Protection module. CONTRACT: keep the type name `ProtectionView` and `init()`.
struct ProtectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProtectionRootScreen(engine: model.protection)
    }
}

/// Hosts the hub and the three tools, routes `protection.*` tool ids and shows the shared
/// confirmations and sheets.
struct ProtectionRootScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: ProtectionScreenModel

    init(engine: ProtectionEngine) {
        _screen = State(initialValue: ProtectionScreenModel.shared(for: engine))
    }

    var body: some View {
        ZStack {
            content
                .id(routeKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: routeKey)
        .onAppear {
            screen.appeared()
            consumePendingTool()
        }
        .onChange(of: model.pendingTool) { _, _ in consumePendingTool() }
        .onChange(of: screen.malware.phase) { old, new in screen.phaseChanged(.malware, from: old, to: new) }
        .onChange(of: screen.privacy.phase) { old, new in screen.phaseChanged(.privacy, from: old, to: new) }
        .onChange(of: screen.permissions.phase) { old, new in screen.phaseChanged(.permissions, from: old, to: new) }
        .onReceive(NotificationCenter.default.publisher(for: ProtectionRealtimeMonitor.eventNotification)) { _ in
            screen.reloadRealtimeEvents()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProtectionEngine.automaticScanNotification)) { _ in
            screen.automaticScanFinished()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screen.refreshFullDiskAccess()
        }
        .sheet(item: $screen.browserPrompt) { prompt in
            ProtectionBrowserQuitSheet(prompt: prompt,
                                       onQuit: { screen.quitBrowsersAndClean() },
                                       onSkip: { screen.skipRunningBrowsers() },
                                       onCancel: { screen.cancelBrowserPrompt() })
        }
        .modifier(ProtectionConfirmations(screen: screen))
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
            ProtectionHubScreen(screen: screen)
        case .tool(let tool):
            ProtectionToolScreen(screen: screen, tool: tool, flow: screen.flow(for: tool))
        }
    }

    private func consumePendingTool() {
        guard let toolID = model.pendingTool, let tool = ProtectionTool(toolID: toolID) else { return }
        model.pendingTool = nil
        screen.open(tool)
    }
}

/// The confirmation dialogs for removing threats, clearing non-safe traces and resetting permissions.
private struct ProtectionConfirmations: ViewModifier {
    @Bindable var screen: ProtectionScreenModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(threatTitle, isPresented: $screen.confirmThreatRemoval, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { screen.removeThreatsNow() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They were flagged by how they behave, not by a known signature, so make sure you don't need them. Everything goes to the Trash, where you can put it back.")
            }
            .confirmationDialog(privacyTitle, isPresented: $screen.confirmPrivacyClean, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { screen.cleanPrivacyNow() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(privacyMessage)
            }
            .confirmationDialog(resetTitle, isPresented: $screen.confirmPermissionReset, titleVisibility: .visible) {
                Button("Reset Access", role: .destructive) { screen.resetPermissionsNow() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each app loses this access and asks for it again the next time it needs it. You can also change access in System Settings › Privacy & Security.")
            }
    }

    private var threatTitle: String {
        let count = screen.selectedThreatsNeedingReview.count
        return "Remove \(CountFormat.items(count, singular: "item")) Spruce isn't sure about?"
    }

    private var privacyTitle: String {
        "Clear data you may want to keep?"
    }

    private var privacyMessage: String {
        let kinds = Set(screen.selectedPrivacyNeedingReview.compactMap { item in
            item.metadata[ProtectionPrivacyMetaKey.kind].flatMap(ProtectionTraceKind.init(rawValue:))
        })
        var parts: [String] = []
        if kinds.contains(.cookies) || kinds.contains(.siteData) { parts.append("you'll be signed out of websites") }
        if kinds.contains(.autofill) { parts.append("saved form entries will be gone") }
        if kinds.contains(.sessions) { parts.append("tabs from your last session won't come back") }
        if kinds.contains(.topSites) { parts.append("frequently visited sites and icons will be rebuilt") }
        if kinds.contains(.history) { parts.append("Firefox restores its bookmarks from its latest backup") }
        if kinds.contains(.downloadLog) { parts.append("the record of past downloads is cleared") }
        let detail = parts.isEmpty ? "Some selected items aren't cleared by default." : "After this, " + parts.joined(separator: ", ") + "."
        return detail + " Saved passwords and bookmarks files are never touched."
    }

    private var resetTitle: String {
        "Reset access for \(CountFormat.items(screen.permissions.selectedCount, singular: "app permission"))?"
    }
}

/// Switches a tool between its idle, scanning, results, running, done and failure screens.
struct ProtectionToolScreen: View {
    @Bindable var screen: ProtectionScreenModel
    var tool: ProtectionTool
    @Bindable var flow: ScanFlowModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            phaseContent
                .id(phaseKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: phaseKey)
        .focusedSceneValue(\.spruceFlow, menuActions)
    }

    // MARK: Main menu

    /// Scan and Edit menu actions. Stop is offered while scanning only (removal has no
    /// Stop button either); Run Selected… is not offered, because the tools' orbs act on
    /// a safe selection without a confirmation and the menu may only open one.
    private var menuActions: SpruceFlowActions {
        var actions = SpruceFlowActions()
        actions.context = "protection.\(tool.rawValue).\(ObjectIdentifier(flow).hashValue)"
        switch flow.phase {
        case .idle, .done, .failed:
            actions.scanAgain = { screen.startScan(tool) }
        case .scanning:
            actions.stop = { flow.cancel() }
        case .running:
            break
        case .results:
            guard screen.browserPrompt == nil, !screen.isQuittingBrowsers else { break }
            actions.scanAgain = { screen.startScan(tool) }
            guard !flow.groups.allItems.isEmpty else { break }
            if tool == .malware {
                // Items Spruce can't remove itself stay unchecked; risky ones need their own click.
                actions.selectAll = {
                    selectItems { ProtectionThreatPresentation.isRemovable($0) && $0.safety != .risky }
                }
                actions.selectRecommended = {
                    selectItems { ProtectionThreatPresentation.isRemovable($0) && $0.safety == .safe }
                }
            } else {
                actions.selectAll = { flow.selectAll(true) }
                actions.selectRecommended = { flow.selectRecommended() }
            }
            actions.deselectAll = { flow.selectAll(false) }
        }
        return actions
    }

    /// Sets every item's selection with one update of the flow's results.
    private func selectItems(_ include: @escaping (ScanItem) -> Bool) {
        func apply(_ group: inout ScanGroup) {
            for i in group.items.indices { group.items[i].isSelected = include(group.items[i]) }
            for j in group.children.indices { apply(&group.children[j]) }
        }
        var groups = flow.groups
        for i in groups.indices { apply(&groups[i]) }
        flow.groups = groups
    }

    private var phaseKey: String {
        switch flow.phase {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .results: return "results"
        case .running: return "running"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch flow.phase {
        case .idle:
            ProtectionToolIdleScreen(screen: screen, tool: tool)
        case .scanning:
            ScanningView(module: .protection, progress: flow.progress, title: tool.scanningTitle,
                         onStop: { flow.cancel() }, showsBytes: tool == .privacy)
        case .results:
            resultsContent
        case .running:
            ScanningView(module: .protection, progress: flow.progress, title: tool.runningTitle,
                         showsBytes: tool == .privacy)
        case .done:
            if let outcome = flow.outcome {
                DoneView(module: .protection, outcome: outcome, headline: doneHeadline(outcome),
                         doneTitle: flow.groups.isEmpty ? "Done" : "Review Remaining",
                         flow: flow, putBackConfirmation: putBackConfirmation) {
                    screen.finish(tool)
                }
            } else {
                EmptyStateView(module: .protection, title: "All done", message: "Nothing else to do here.",
                               actionTitle: "Back", action: { screen.finish(tool) })
            }
        case .failed(let message):
            FailureView(module: .protection, message: message) { screen.startScan(tool) }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        switch tool {
        case .malware: ProtectionMalwareResultsScreen(screen: screen, flow: flow)
        case .privacy: ProtectionPrivacyResultsScreen(screen: screen, flow: flow)
        case .permissions: ProtectionPermissionsResultsScreen(screen: screen, flow: flow)
        }
    }

    /// Putting removed threats back asks first.
    private var putBackConfirmation: String? {
        guard tool == .malware else { return nil }
        return "These items were flagged as threats. Put them back only if you're sure they're safe: "
            + "startup items among them run again at the next login."
    }

    private func doneHeadline(_ outcome: RunOutcome) -> String? {
        switch tool {
        case .malware:
            if outcome.processedCount == 0 { return "No threats were removed" }
            return outcome.processedCount == 1 ? "Threat removed" : "\(outcome.processedCount) threats removed"
        case .privacy:
            return outcome.freedBytes > 0 ? nil : (outcome.processedCount > 0 ? "Traces cleared" : "Nothing was cleared")
        case .permissions:
            if outcome.processedCount == 0 { return "No permissions were reset" }
            return outcome.processedCount == 1 ? "Permission reset" : "\(outcome.processedCount) permissions reset"
        }
    }
}

/// A tool's intro screen with a way back to the hub.
struct ProtectionToolIdleScreen: View {
    @Bindable var screen: ProtectionScreenModel
    var tool: ProtectionTool

    var body: some View {
        ZStack(alignment: .topLeading) {
            idle
            PrismBackButton(title: "Protection") { screen.showHub() }
                .padding(.leading, Spacing.l)
                .padding(.top, Spacing.topInset)
        }
    }

    @ViewBuilder
    private var idle: some View {
        switch tool {
        case .malware:
            ModuleIdleView(module: .protection, title: tool.title, subtitle: tool.tagline, features: tool.features,
                           actionTitle: "Scan", actionSubtitle: "\(screen.engine.configuredDepth.title) scan",
                           notice: malwareNotice, noticeActionTitle: screen.hasFullDiskAccess ? nil : "Grant Access",
                           accessory: AnyView(ProtectionScanDepthPicker()),
                           action: { screen.startScan(.malware) },
                           onNoticeAction: { Permissions.openFullDiskAccessSettings() })
        case .privacy:
            ModuleIdleView(module: .protection, title: tool.title, subtitle: tool.tagline, features: tool.features,
                           actionTitle: "Scan",
                           notice: screen.hasFullDiskAccess ? nil : "Safari's data is protected by macOS. Allow Full Disk Access to include it.",
                           noticeActionTitle: screen.hasFullDiskAccess ? nil : "Grant Access",
                           action: { screen.startScan(.privacy) },
                           onNoticeAction: { Permissions.openFullDiskAccessSettings() })
        case .permissions:
            ModuleIdleView(module: .protection, title: tool.title, subtitle: tool.tagline, features: tool.features,
                           actionTitle: "Scan",
                           notice: screen.hasFullDiskAccess ? nil : "macOS keeps app permissions in a protected place. Spruce needs Full Disk Access to read them.",
                           noticeActionTitle: screen.hasFullDiskAccess ? nil : "Grant Access",
                           lensMood: screen.hasFullDiskAccess ? .standard : .limited,
                           action: { screen.startScan(.permissions) },
                           onNoticeAction: { Permissions.openFullDiskAccessSettings() })
        }
    }

    private var malwareNotice: String? {
        if !screen.hasFullDiskAccess {
            return "Without Full Disk Access some locations can't be checked."
        }
        if let report = screen.malwareReport {
            let found = report.threatCount == 0 ? "no threats" : CountFormat.items(report.threatCount, singular: "threat")
            return "Last scan \(DurationFormat.relative(report.date)): \(found)."
        }
        return nil
    }
}

/// Quick / Balanced / Deep, stored in Settings › Protection.
struct ProtectionScanDepthPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let depth = ProtectionScanDepth(setting: model.settings.settings.scanDepth)
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker("Scan mode", selection: Binding(
                get: { ProtectionScanDepth(setting: model.settings.settings.scanDepth) },
                set: { model.settings.settings.scanDepth = $0.rawValue }
            )) {
                ForEach(ProtectionScanDepth.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)
            Text("\(depth.coverage) \(depth.speed).")
                .font(SpruceFont.caption)
                .foregroundStyle(PrismInk(contrast).tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scan mode")
    }
}
