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
                            detail: "Verifies code signatures and matches files against documented malware and Apple's XProtect rules."),
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
    /// The last automatic scan since launch.
    private(set) var automaticReport: ProtectionMalwareReport?
    private(set) var privacyReport: ProtectionPrivacyReport?
    private(set) var permissionsReport: ProtectionPermissionsReport?
    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess

    var browserPrompt: ProtectionBrowserPrompt?
    private(set) var isQuittingBrowsers = false
    var confirmThreatRemoval = false
    var confirmPrivacyClean = false
    var confirmPermissionReset = false

    /// Rows whose "Check with VirusTotal" was pressed and hasn't come back yet (the engine's
    /// `detection.virusTotalPending` follows a moment later).
    private(set) var virusTotalRequests: Set<String> = []
    /// Rows whose VirusTotal page couldn't be opened (no readable file to fingerprint).
    private(set) var virusTotalLinkProblems: [String: String] = [:]

    /// How often Spruce scans on its own (Protection hub › Automatic scans).
    var backgroundSchedule: ProtectionBackgroundSchedule {
        didSet {
            if backgroundSchedule != oldValue { engine.backgroundSchedule = backgroundSchedule }
        }
    }

    @ObservationIgnored private var scanStarts: [ProtectionTool: Date] = [:]
    /// The automatic scan whose results were last put into Malware Removal.
    @ObservationIgnored private var adoptedAutomaticScan: Date?

    static func shared(for engine: ProtectionEngine) -> ProtectionScreenModel {
        ProtectionScreenRegistry.model(for: engine)
    }

    fileprivate init(engine: ProtectionEngine) {
        self.engine = engine
        // The engine records each malware scan as `.malwareScan` itself (Activity's health
        // reads its threat count), so the flow doesn't add a generic `.scan` entry.
        malware = ScanFlowModel(module: .protection, scanner: engine, historyKind: ProtectionTool.malware.historyKind,
                                recordsScanHistory: false)
        privacy = ScanFlowModel(module: .protection, scanner: engine.privacy, historyKind: ProtectionTool.privacy.historyKind)
        permissions = ScanFlowModel(module: .protection, scanner: engine.permissions,
                                    historyKind: ProtectionTool.permissions.historyKind)
        backgroundSchedule = engine.backgroundSchedule
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
        adoptAutomaticResults()
        applyVirusTotalAnswers()
        if appleStatus == nil { refreshAppleStatus() }
        refreshDetectionStatus()
    }

    /// Re-reads what the hub shows about the detection sources (Apple's XProtect rules, the
    /// threat list, the VirusTotal key). Cheap after the first time; never blocks the screen.
    func refreshDetectionStatus() {
        let engine = self.engine
        Task { await engine.refreshDetectionStatus() }
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
    /// Findings ignored since the scan are left out, so the copy matches the review list.
    func syncReports() {
        let settings = SettingsStore.shared.settings
        malwareReport = engine.lastMalwareReport?.excludingIgnored(settings)
        automaticReport = engine.lastAutomaticReport?.excludingIgnored(settings)
        privacyReport = engine.privacy.lastReport
        permissionsReport = engine.permissions.lastReport
    }

    /// An automatic scan finished while Spruce was open.
    func automaticScanFinished() {
        syncReports()
        adoptAutomaticResults()
    }

    /// Puts the threats of the latest automatic scan into Malware Removal for review,
    /// unless the user is in the middle of something there. Each automatic scan is
    /// adopted once (Start Over doesn't bring it back).
    func adoptAutomaticResults() {
        guard let report = engine.lastAutomaticReport, report.date > (adoptedAutomaticScan ?? .distantPast) else { return }
        // Superseded by a newer scan or removal: its list would be out of date.
        let newerActivity = [engine.lastMalwareReport?.date, malware.lastScanDate, malware.outcome?.date].compactMap { $0 }
        if newerActivity.contains(where: { $0 > report.date }) {
            adoptedAutomaticScan = report.date
            return
        }
        switch malware.phase {
        case .idle, .failed:
            break
        case .done where malware.groups.isEmpty:
            break
        case .results where (malware.lastScanDate ?? .distantPast) < report.date && malware.groups.isEmpty:
            break
        default:
            return
        }
        adoptedAutomaticScan = report.date
        let groups = SettingsStore.shared.settings.filteringIgnored(ProtectionThreatFinding.scanGroups(report.findings))
        guard !groups.isEmpty else { return }
        malware.groups = groups
        malware.showRemaining()
    }

    func phaseChanged(_ tool: ProtectionTool, from old: ScanFlowModel.Phase, to new: ScanFlowModel.Phase) {
        if new == .scanning {
            scanStarts[tool] = Date()
        }
        if old == .scanning && new == .results {
            syncReports()
            // Answers that came back before the list was shown.
            if tool == .malware { applyVirusTotalAnswers() }
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
        if tool == .malware { adoptAutomaticResults() }
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

    /// Never reports this threat again, and updates the counts that mention it.
    func ignoreThreat(_ item: ScanItem) {
        malware.ignore(item)
        syncReports()
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

    // MARK: VirusTotal

    /// What the screens show about Apple's rules, the threat list and VirusTotal.
    var detection: ProtectionDetectionState { engine.detection }

    /// Puts VirusTotal answers that arrived since the scan on the review rows (the engine
    /// updates its own results; the flow's list is a copy). An answer only goes on a row
    /// whose file it is about, and selection never changes.
    func applyVirusTotalAnswers() {
        let known = detection.virusTotalByItemID
        guard !known.isEmpty, !malware.groups.isEmpty else { return }
        var answers: [String: VirusTotalVerdict] = [:]
        for item in malware.groups.allItems {
            guard let verdict = known[item.id], ProtectionThreatPresentation.isAbout(verdict, item) else { continue }
            answers[item.id] = verdict
        }
        var groups = malware.groups
        if groups.applyVirusTotal(answers) { malware.groups = groups }
    }

    /// The VirusTotal answer for a row's file: recorded on the row, arrived since, or known
    /// for its hash. Answers about another file (the file at that path changed) are left out.
    func virusTotalVerdict(for item: ScanItem) -> VirusTotalVerdict? {
        guard let hash = item.protectionSHA256 else { return detection.verdict(for: item) }
        let candidates = [detection.virusTotalByItemID[item.id], item.virusTotalVerdict, detection.virusTotalBySHA256[hash]]
        return candidates.compactMap { $0 }.first { ProtectionThreatPresentation.isAbout($0, item) }
    }

    /// True while the row's file is being looked up (or waits for a free lookup).
    func isCheckingVirusTotal(_ item: ScanItem) -> Bool {
        virusTotalRequests.contains(item.id) || detection.isLookingUp(item)
    }

    /// "Check with VirusTotal": the engine fingerprints the file on this Mac and sends only
    /// its SHA-256 (the file is never uploaded). Runs in the background; the answer lands on
    /// the row through `detection`, and a problem is kept there for the row.
    func checkWithVirusTotal(_ item: ScanItem) {
        guard !isCheckingVirusTotal(item) else { return }
        virusTotalRequests.insert(item.id)
        virusTotalLinkProblems[item.id] = nil
        let engine = self.engine
        Task { [weak self] in
            _ = await engine.checkWithVirusTotal(item)
            guard let self else { return }
            self.virusTotalRequests.remove(item.id)
            self.applyVirusTotalAnswers()
        }
    }

    /// "Open in VirusTotal": the file's page on virustotal.com in the browser. The hash is
    /// computed on this Mac when the row has none; nothing is sent until the page opens.
    func openInVirusTotal(_ item: ScanItem) {
        virusTotalLinkProblems[item.id] = nil
        let engine = self.engine
        Task { [weak self] in
            if let page = await engine.virusTotalPage(for: item) {
                NSWorkspace.shared.open(page)
            } else {
                self?.virusTotalLinkProblems[item.id] = "Spruce couldn't read this file to fingerprint it, so it has no VirusTotal page."
            }
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
        lines(item, ProtectionMetaKey.related)
    }

    /// The YARA rules that matched the row's file: where each set comes from ("Apple
    /// XProtect") and each rule as "what it detects (rule name)".
    static func ruleMatches(_ item: ScanItem) -> (sources: [String], rules: [String]) {
        let names = lines(item, ProtectionMetaKey.rules)
        let labels = lines(item, ProtectionMetaKey.ruleLabels)
        let rules = names.enumerated().map { index, name -> String in
            let label = labels.indices.contains(index) ? labels[index] : name
            return label == name ? name : "\(label) (\(name))"
        }
        return (lines(item, ProtectionMetaKey.ruleSources), rules)
    }

    /// True when the row has a file VirusTotal can be asked about (or its hash).
    static func canCheckWithVirusTotal(_ item: ScanItem) -> Bool {
        item.protectionLookupPath != nil || item.protectionSHA256 != nil
    }

    /// False when the answer is about a different file than the row's (known hashes differ).
    static func isAbout(_ verdict: VirusTotalVerdict, _ item: ScanItem) -> Bool {
        guard let hash = item.protectionSHA256 else { return true }
        return VirusTotalAPI.normalizedSHA256(verdict.sha256) == hash
    }

    /// Short marker for the row ("VirusTotal 34/72"), nil when there's nothing to flag.
    static func virusTotalChip(_ verdict: VirusTotalVerdict) -> (text: String, color: Color)? {
        switch verdict.level {
        case .flagged: return ("VirusTotal \(verdict.malicious)/\(verdict.engines)", StatusColor.danger)
        case .someFlags: return ("VirusTotal \(verdict.malicious + verdict.suspicious)/\(verdict.engines)", StatusColor.warning)
        case .clean: return ("VirusTotal 0/\(verdict.engines)", StatusColor.success)
        case .unknown: return nil
        }
    }

    private static func lines(_ item: ScanItem, _ key: String) -> [String] {
        (item.metadata[key] ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

/// Opens Settings on the Protection tab (the tab is remembered in user defaults, which the
/// Settings window follows).
@MainActor
enum ProtectionSettingsLink {
    static func open(_ openSettings: OpenSettingsAction) {
        UserDefaults.standard.set(SettingsTab.protection.rawValue, forKey: SettingsTab.storageKey)
        openSettings()
    }
}
