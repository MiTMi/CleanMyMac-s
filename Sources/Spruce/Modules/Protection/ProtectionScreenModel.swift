import AppKit
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Tools

/// The three Protection tools reachable from the hub (and by tool id from anywhere).
enum ProtectionTool: String, CaseIterable, Identifiable {
    case malware
    case privacy
    case permissions

    var id: String { rawValue }

    /// Navigation id (`AppModel.open(.protection, tool:)`).
    var toolID: String { "protection.\(rawValue)" }

    init?(toolID: String) {
        guard let tool = ProtectionTool.allCases.first(where: { $0.toolID == toolID }) else { return nil }
        self = tool
    }

    var title: String {
        switch self {
        case .malware: return "Malware Removal"
        case .privacy: return "Privacy"
        case .permissions: return "App Permissions"
        }
    }

    var tagline: String {
        switch self {
        case .malware: return "Find adware, spyware and other threats hiding on your Mac, and remove them safely."
        case .privacy: return "Clear browsing traces and the recent-items lists macOS keeps about you."
        case .permissions: return "See which apps can use your camera, microphone, screen, keyboard and files."
        }
    }

    var symbol: String {
        switch self {
        case .malware: return "shield.checkered"
        case .privacy: return "hand.raised.fill"
        case .permissions: return "lock.shield.fill"
        }
    }

    var features: [IdleFeature] {
        switch self {
        case .malware:
            return [
                IdleFeature(symbol: "bolt.horizontal.circle", title: "Startup items and helpers",
                            detail: "Checks how threats usually stay on a Mac: launch agents, daemons, helper tools and scheduled jobs."),
                IdleFeature(symbol: "checkmark.seal", title: "Signatures and known samples",
                            detail: "Verifies code signatures and matches files against documented malware."),
                IdleFeature(symbol: "trash", title: "Safe removal",
                            detail: "Stops what's running, then moves threats to the Trash so nothing is lost by mistake."),
            ]
        case .privacy:
            return [
                IdleFeature(symbol: "globe", title: "Every browser",
                            detail: "History, cookies, downloads lists, autofill and site data of Safari, Chrome, Firefox and more."),
                IdleFeature(symbol: "list.bullet.rectangle", title: "macOS lists",
                            detail: "Recent apps, documents and servers, Quick Look thumbnails and the download log."),
                IdleFeature(symbol: "key", title: "Passwords stay",
                            detail: "Saved passwords, bookmarks and open tab groups are never touched."),
            ]
        case .permissions:
            return [
                IdleFeature(symbol: "camera", title: "Camera, mic and screen",
                            detail: "Powerful permissions first: screen recording, accessibility, input monitoring and full disk access."),
                IdleFeature(symbol: "archivebox", title: "Leftover permissions",
                            detail: "Spots permissions still held by apps you've deleted."),
                IdleFeature(symbol: "arrow.counterclockwise", title: "Reset or adjust",
                            detail: "Reset an app's access so it asks again, or jump to the right System Settings pane."),
            ]
        }
    }

    var scanningTitle: String {
        switch self {
        case .malware: return "Looking for threats…"
        case .privacy: return "Looking for privacy traces…"
        case .permissions: return "Reading app permissions…"
        }
    }

    var runningTitle: String {
        switch self {
        case .malware: return "Removing threats…"
        case .privacy: return "Clearing traces…"
        case .permissions: return "Resetting permissions…"
        }
    }

    var historyKind: ActivityEntry.Kind {
        switch self {
        case .malware: return .threatRemoved
        case .privacy: return .clean
        case .permissions: return .other
        }
    }
}

/// Running browsers whose selected data can't be cleared until they quit.
struct ProtectionBrowserPrompt: Identifiable {
    let id = UUID()
    var sourceIDs: [String]

    var names: [String] { sourceIDs.map { ProtectionPrivacyCleaner.name(ofSource: $0) } }
}

// MARK: - Screen model

/// UI state of the Protection module. One instance per engine lives for the whole app
/// session (the module view is recreated on navigation), so each tool keeps its results.
@MainActor
@Observable
final class ProtectionScreenModel {
    enum Route: Equatable {
        case hub
        case tool(ProtectionTool)
    }

    let engine: ProtectionEngine
    let malware: ScanFlowModel
    let privacy: ScanFlowModel
    let permissions: ScanFlowModel

    var route: Route = .hub
    private(set) var appleStatus: ProtectionAppleStatus?
    private(set) var isReadingAppleStatus = false
    private(set) var realtimeEvents: [ProtectionRealtimeEvent] = []
    private(set) var malwareReport: ProtectionMalwareReport?
    private(set) var privacyReport: ProtectionPrivacyReport?
    private(set) var permissionsReport: ProtectionPermissionsReport?
    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess

    var browserPrompt: ProtectionBrowserPrompt?
    private(set) var isQuittingBrowsers = false
    var confirmThreatRemoval = false
    var confirmPrivacyClean = false
    var confirmPermissionReset = false

    @ObservationIgnored private var scanStarts: [ProtectionTool: Date] = [:]

    static func shared(for engine: ProtectionEngine) -> ProtectionScreenModel {
        ProtectionScreenRegistry.model(for: engine)
    }

    fileprivate init(engine: ProtectionEngine) {
        self.engine = engine
        malware = ScanFlowModel(module: .protection, scanner: engine, historyKind: ProtectionTool.malware.historyKind)
        privacy = ScanFlowModel(module: .protection, scanner: engine.privacy, historyKind: ProtectionTool.privacy.historyKind)
        permissions = ScanFlowModel(module: .protection, scanner: engine.permissions,
                                    historyKind: ProtectionTool.permissions.historyKind)
        malwareReport = engine.lastMalwareReport
    }

    func flow(for tool: ProtectionTool) -> ScanFlowModel {
        switch tool {
        case .malware: return malware
        case .privacy: return privacy
        case .permissions: return permissions
        }
    }

    // MARK: Lifecycle

    func appeared() {
        refreshFullDiskAccess()
        reloadRealtimeEvents()
        syncReports()
        if appleStatus == nil { refreshAppleStatus() }
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }

    func reloadRealtimeEvents() {
        realtimeEvents = engine.realtimeEvents
    }

    func refreshAppleStatus() {
        guard !isReadingAppleStatus else { return }
        isReadingAppleStatus = true
        let engine = self.engine
        Task { [weak self] in
            let status = await engine.appleProtectionStatus()
            guard let self else { return }
            self.appleStatus = status
            self.isReadingAppleStatus = false
        }
    }

    /// Picks up the engines' latest reports (results may arrive while another module is shown).
    func syncReports() {
        malwareReport = engine.lastMalwareReport
        privacyReport = engine.privacy.lastReport
        permissionsReport = engine.permissions.lastReport
    }

    func phaseChanged(_ tool: ProtectionTool, from old: ScanFlowModel.Phase, to new: ScanFlowModel.Phase) {
        if new == .scanning {
            scanStarts[tool] = Date()
        }
        if old == .scanning && new == .results {
            syncReports()
            let found = !flow(for: tool).groups.allItems.isEmpty
            if tool == .malware && found {
                SpruceSound.play(.attention)
            } else if let start = scanStarts[tool], Date().timeIntervalSince(start) >= 1.5 {
                SpruceSound.play(.scanComplete)
            }
            scanStarts[tool] = nil
        }
        if new == .done {
            syncReports()
        }
    }

    // MARK: Navigation

    func open(_ tool: ProtectionTool) {
        route = .tool(tool)
    }

    func showHub() {
        route = .hub
    }

    func startScan(_ tool: ProtectionTool) {
        route = .tool(tool)
        refreshFullDiskAccess()
        SpruceSound.play(.scanStart)
        flow(for: tool).startScan()
    }

    /// Discards a tool's results.
    func startOver(_ tool: ProtectionTool) {
        flow(for: tool).reset()
    }

    /// From the done screen: remaining items, or back to the hub when nothing is left.
    func finish(_ tool: ProtectionTool) {
        let flow = flow(for: tool)
        let wasEmpty = flow.groups.isEmpty
        flow.showRemaining()
        if wasEmpty { route = .hub }
    }

    // MARK: Malware

    var selectedThreatsNeedingReview: [ScanItem] {
        malware.selectedItems.filter { $0.safety != .safe }
    }

    func requestThreatRemoval() {
        guard !malware.selectedItems.isEmpty else { return }
        if !selectedThreatsNeedingReview.isEmpty {
            confirmThreatRemoval = true
        } else {
            malware.run()
        }
    }

    func removeThreatsNow() {
        confirmThreatRemoval = false
        malware.run()
    }

    /// Selects or clears every removable threat of a group (items Spruce can't remove stay unchecked).
    func setThreatGroup(_ groupID: String, selected: Bool) {
        guard let group = malware.groups.first(where: { $0.id == groupID }) else { return }
        for item in group.allItems {
            let removable = selected && ProtectionThreatPresentation.isRemovable(item)
            malware.setSelected(removable, itemID: item.id)
        }
    }

    // MARK: Privacy

    var selectedPrivacyNeedingReview: [ScanItem] {
        privacy.selectedItems.filter { $0.safety != .safe }
    }

    /// Browsers that are open right now and own selected items.
    func runningBrowsersInSelection() -> [String] {
        let sources = Set(privacy.selectedItems.compactMap { $0.metadata[ProtectionPrivacyMetaKey.source] })
        return sources.filter { !ProtectionPrivacyCleaner.runningApplications(sourceID: $0).isEmpty }.sorted()
    }

    /// Browsers that are open right now and have data in the results.
    func runningBrowsersInResults() -> [String] {
        let sources = Set(privacy.groups.allItems.compactMap { $0.metadata[ProtectionPrivacyMetaKey.source] })
        return sources.filter { !ProtectionPrivacyCleaner.runningApplications(sourceID: $0).isEmpty }.sorted()
    }

    func requestPrivacyClean() {
        guard !privacy.selectedItems.isEmpty else { return }
        let running = runningBrowsersInSelection()
        if !running.isEmpty {
            browserPrompt = ProtectionBrowserPrompt(sourceIDs: running)
            return
        }
        continuePrivacyClean()
    }

    private func continuePrivacyClean() {
        if !selectedPrivacyNeedingReview.isEmpty {
            confirmPrivacyClean = true
        } else {
            privacy.run()
        }
    }

    func cleanPrivacyNow() {
        confirmPrivacyClean = false
        privacy.run()
    }

    /// Asks the browsers in the prompt to quit, then cleans (items of browsers that refuse
    /// to quit are skipped by the engine and reported).
    func quitBrowsersAndClean() {
        guard let prompt = browserPrompt else { return }
        browserPrompt = nil
        isQuittingBrowsers = true
        Task { [weak self] in
            _ = await ProtectionPrivacyCleaner.quit(sourceIDs: Set(prompt.sourceIDs))
            guard let self else { return }
            self.isQuittingBrowsers = false
            self.continuePrivacyClean()
        }
    }

    /// Quits browsers from the results banner without cleaning.
    func quitBrowsers(_ sourceIDs: [String]) {
        guard !sourceIDs.isEmpty else { return }
        isQuittingBrowsers = true
        Task { [weak self] in
            _ = await ProtectionPrivacyCleaner.quit(sourceIDs: Set(sourceIDs))
            self?.isQuittingBrowsers = false
        }
    }

    /// Deselects the open browsers' items and cleans the rest.
    func skipRunningBrowsers() {
        guard let prompt = browserPrompt else { return }
        browserPrompt = nil
        let skipped = Set(prompt.sourceIDs)
        for item in privacy.selectedItems {
            if let source = item.metadata[ProtectionPrivacyMetaKey.source], skipped.contains(source) {
                privacy.setSelected(false, itemID: item.id)
            }
        }
        guard !privacy.selectedItems.isEmpty else { return }
        continuePrivacyClean()
    }

    func cancelBrowserPrompt() {
        browserPrompt = nil
    }

    // MARK: Permissions

    func requestPermissionReset() {
        guard !permissions.selectedItems.isEmpty else { return }
        confirmPermissionReset = true
    }

    func resetPermissionsNow() {
        confirmPermissionReset = false
        permissions.run()
    }

    func reset(_ item: ScanItem) {
        permissions.run([item])
    }
}

/// Keeps one `ProtectionScreenModel` per engine for the app's lifetime.
@MainActor
private enum ProtectionScreenRegistry {
    static var models: [ObjectIdentifier: ProtectionScreenModel] = [:]

    static func model(for engine: ProtectionEngine) -> ProtectionScreenModel {
        let key = ObjectIdentifier(engine)
        if let existing = models[key] { return existing }
        let created = ProtectionScreenModel(engine: engine)
        models[key] = created
        return created
    }
}

// MARK: - Presentation helpers

/// Display helpers for threat items (decoded from `ScanItem.metadata`).
enum ProtectionThreatPresentation {
    /// False for items Spruce can't remove itself (protected locations, configuration profiles).
    static func isRemovable(_ item: ScanItem) -> Bool {
        item.metadata[ProtectionMetaKey.manual] == nil
    }

    static func severity(_ item: ScanItem) -> ThreatSeverity {
        Int(item.metadata[ProtectionMetaKey.severity] ?? "").flatMap(ThreatSeverity.init(rawValue:)) ?? .medium
    }

    static func severityColor(_ severity: ThreatSeverity) -> Color {
        switch severity {
        case .critical, .high: return StatusColor.danger
        case .medium: return StatusColor.warning
        case .low: return StatusColor.info
        }
    }

    static func category(_ item: ScanItem) -> ThreatCategory {
        ThreatCategory(rawValue: item.metadata[ProtectionMetaKey.category] ?? "") ?? .suspicious
    }

    static func evidence(_ item: ScanItem) -> ThreatEvidence {
        ThreatEvidence(rawValue: item.metadata[ProtectionMetaKey.evidence] ?? "") ?? .heuristic
    }

    static func kind(_ item: ScanItem) -> ProtectionItemKind {
        ProtectionItemKind(rawValue: item.metadata[ProtectionMetaKey.kind] ?? "") ?? .file
    }

    static func reasons(_ item: ScanItem) -> [String] {
        (item.metadata[ProtectionMetaKey.reasons] ?? item.note ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func related(_ item: ScanItem) -> [String] {
        (item.metadata[ProtectionMetaKey.related] ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
