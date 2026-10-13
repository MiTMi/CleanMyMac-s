import AppKit
import Foundation
import Observation
import SpruceCore

/// Malware/persistence scan, privacy traces and app permissions.
///
/// CONTRACT (used by AppModel and Checkup — keep these signatures):
/// * `public init()`
/// * `CheckupContributor` conformance (`checkupScan`, `checkupRun`)
/// * `GroupScanner` conformance (`scan`, `perform`) for the module's main review list
///
/// `scan` is the malware scan at the depth chosen in Settings (`scanDepth`). `perform`
/// acts on any Protection item: threats are stopped and moved to the Trash, privacy traces
/// are cleared, permissions are reset — routed by the item's `protection.tool` metadata.
/// The Privacy and App Permissions tools have their own scanners (`privacy`,
/// `permissions`) so each tool can run its own scan → review → act journey.
///
/// Detection beyond the built-in catalog (`detection` holds what the screens show):
/// * Apple's XProtect rules, read from macOS and run by the built-in YARA engine (offline).
/// * Spruce's threat list (feed.json + rules.yara from the project's GitHub repository),
///   checked at most once a day before a scan or with `checkThreatListNow()`, while
///   Settings › Protection › Download threat list is on. It can only add detections.
/// * VirusTotal lookups with the user's own key (Keychain): after a scan for heuristic and
///   rule-based findings (Settings › Protection, on by default once a key is saved) and with
///   `checkWithVirusTotal(_:)`. Only SHA-256 hashes are sent; files are never uploaded.
public final class ProtectionEngine: CheckupContributor, GroupScanner, @unchecked Sendable {
    /// Threats found by the last Checkup scan. Written by background scans and read and
    /// edited by the Checkup screen, so it lives behind the engine's lock.
    public var checkupReview: [ScanGroup] {
        get { state.current.checkupReview }
        set { state.update { $0.checkupReview = newValue } }
    }
    public let module: ModuleID = .protection

    /// Posted on the main thread after an automatic (background) scan finished.
    public static let automaticScanNotification = Notification.Name("SpruceProtectionAutomaticScan")
    /// Posted on the main thread when a VirusTotal answer arrives for a malware row:
    /// `userInfo[virusTotalItemKey]` is the row id (`ScanItem.id`), `userInfo[virusTotalVerdictKey]`
    /// the `VirusTotalVerdict`. The engine's own results (`lastMalwareReport`, `checkupReview`)
    /// already carry it; review lists the UI keeps apply it with `[ScanGroup].applyVirusTotal(_:)`.
    public static let virusTotalNotification = Notification.Name("SpruceProtectionVirusTotalVerdict")
    public static let virusTotalItemKey = "itemID"
    public static let virusTotalVerdictKey = "verdict"

    /// Browser and macOS privacy traces.
    public let privacy: ProtectionPrivacyCleaner
    /// Apps holding macOS privacy permissions.
    public let permissions: ProtectionPermissionsReviewer
    /// Watches startup-item folders while real-time protection is on.
    public let realtime: ProtectionRealtimeMonitor
    /// Apple's XProtect rules, the threat list and VirusTotal lookups, as the Protection
    /// screens and Settings show them (observable; changes on the main thread).
    public let detection = ProtectionDetectionState()

    let probe = ProtectionMacSystemProbe()
    /// XProtect rules and the cached threat list the scanners are built with.
    let library = ProtectionDetectionLibrary()
    let feedUpdater: ProtectionThreatFeedUpdater
    let virusTotal = ProtectionVirusTotalClient()
    let state = ProtectionLocked(ProtectionEngineState())
    private let background = ProtectionBackgroundScanner()
    /// The automatic VirusTotal lookups of the last scan (cancelled by the next scan).
    let automaticLookups = ProtectionLocked<Task<Void, Never>?>(nil)

    /// Files bigger than this aren't fingerprinted for VirusTotal (like the scanner's hashing).
    static let maxFingerprintBytes: Int64 = 100_000_000

    public init() {
        privacy = ProtectionPrivacyCleaner()
        permissions = ProtectionPermissionsReviewer()
        realtime = ProtectionRealtimeMonitor(probe: probe, library: library)
        feedUpdater = ProtectionThreatFeedUpdater(library: library)
        // Real-time protection and the threat list follow Settings › Protection for the app's
        // whole lifetime, and automatic scans run on the schedule chosen on the Protection hub.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.followRealtimeSetting()
            self.followDetectionSettings()
            self.background.start(engine: self)
            let engine = self
            Task.detached(priority: .utility) { await engine.publishVirusTotalState() }
        }
    }

    // MARK: Results

    /// The last completed malware scan (module, Checkup or automatic), without the
    /// findings the user ignored.
    public var lastMalwareReport: ProtectionMalwareReport? { state.current.malwareReport }

    /// The last automatic (background) scan since launch.
    public var lastAutomaticReport: ProtectionMalwareReport? { state.current.automaticReport }

    /// How often automatic Quick scans run (stored per Mac in user defaults).
    public var backgroundSchedule: ProtectionBackgroundSchedule {
        get { ProtectionBackgroundScanner.storedSchedule }
        set { ProtectionBackgroundScanner.storedSchedule = newValue }
    }

    /// macOS's own protection layers, as last read by `appleProtectionStatus()`.
    public var lastAppleStatus: ProtectionAppleStatus? { state.current.appleStatus }

    /// The scan depth currently chosen in Settings.
    public var configuredDepth: ProtectionScanDepth {
        ProtectionScanDepth(setting: SettingsStore.shared.settings.scanDepth)
    }

    // MARK: GroupScanner (malware)

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        let settings = await ProtectionMac.settings()
        let report = try await scanMalware(depth: ProtectionScanDepth(setting: settings.scanDepth), progress: progress)
        return settings.filteringIgnored(ProtectionThreatFinding.scanGroups(report.findings))
    }

    /// Runs a malware scan: startup items, helpers, known threat locations, cron, browser
    /// policies (all depths); apps, Application Support and shared folders (balanced, deep);
    /// the whole home folder (deep). Signatures are checked with the Security framework
    /// and suspicious files are hashed against known samples. Online-only cloud files are
    /// never downloaded. The report leaves out findings on the ignore list, so its count,
    /// the history entry and Activity's health match the review list.
    public func scanMalware(depth: ProtectionScanDepth, progress: @escaping ProgressHandler) async throws -> ProtectionMalwareReport {
        try await scanMalware(depth: depth, automatic: false, progress: progress)
    }

    func scanMalware(depth: ProtectionScanDepth, automatic: Bool,
                     progress: @escaping ProgressHandler) async throws -> ProtectionMalwareReport {
        progress(ScanProgress(fraction: 0, message: "Preparing a \(depth.title.lowercased()) scan…"))
        let before = await ProtectionMac.settings()
        library.isThreatListEnabled = before.threatFeedEnabled
        // The lookups of the previous scan's findings stop; this scan queues its own.
        cancelAutomaticLookups()
        await refreshThreatListIfDue()
        let crontab = await Self.readCrontab()
        let raw = try await ProtectionMac.runBlocking(qos: automatic ? .utility : .userInitiated) { [self] flag in
            // Built here, off the main thread: the first scan compiles Apple's XProtect rules.
            let scanner = self.makeScanner(crontab: crontab)
            return try scanner.scan(depth: depth, progress: progress, isCancelled: { flag.isCancelled })
        }
        let settings = await ProtectionMac.settings()
        let report = await withRememberedVirusTotalAnswers(raw.excludingIgnored(settings))
        state.update {
            $0.malwareReport = report
            if automatic { $0.automaticReport = report }
        }
        let kind = automatic ? "Automatic \(depth.title.lowercased())" : depth.title
        let summary = report.threatCount == 0
            ? "\(kind) malware scan: no threats"
            : "\(kind) malware scan: \(CountFormat.items(report.threatCount, singular: "threat"))"
        await ProtectionMac.record(ActivityEntry(module: .protection, kind: .malwareScan, count: report.threatCount, summary: summary))
        if settings.virusTotalAutoCheck { startAutomaticLookups(for: report) }
        return report
    }

    /// The automatic Quick scan: keeps its results for review and alerts when it found
    /// something (respecting the threat-notification setting).
    @discardableResult
    func runAutomaticScan() async throws -> ProtectionMalwareReport {
        let report = try await scanMalware(depth: .quick, automatic: true, progress: { _ in })
        await MainActor.run {
            if report.threatCount > 0, SettingsStore.shared.settings.notifyThreats {
                let known = report.knownCount > 0
                Notifier.post(id: "app.spruce.protection.automatic.\(Int(report.date.timeIntervalSince1970))",
                              title: known ? "Threats found" : "Suspicious items found",
                              body: "An automatic quick scan found \(CountFormat.items(report.threatCount, singular: "item")) to review. "
                                  + "Open Spruce › Protection › Malware Removal to remove them.",
                              module: ModuleID.protection.rawValue, tool: "protection.malware")
            }
            NotificationCenter.default.post(name: Self.automaticScanNotification, object: self)
        }
        return report
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let threats = items.filter { $0.metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.malwareTool }
        let traces = items.filter { $0.metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.privacyTool }
        let grants = items.filter { $0.metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.permissionsTool }
        var outcomes: [RunOutcome] = []
        if !threats.isEmpty { outcomes.append(await removeThreats(threats, progress: progress)) }
        if !traces.isEmpty { outcomes.append(try await privacy.perform(traces, progress: progress)) }
        if !grants.isEmpty { outcomes.append(try await permissions.perform(grants, progress: progress)) }
        if outcomes.count == 1, let only = outcomes.first { return only }
        if outcomes.isEmpty { return RunOutcome(module: module, summary: "Nothing to do") }
        return RunOutcome.merged(outcomes, module: module, summary: outcomes.map(\.summary).joined(separator: " · "))
    }

    // MARK: CheckupContributor

    /// Quick malware scan; known threats are pre-selected in `checkupReview`.
    public func checkupScan(progress: @escaping ProgressHandler) async throws -> CheckupTile {
        let report = try await scanMalware(depth: .quick, progress: progress)
        let settings = await ProtectionMac.settings()
        let groups = settings.filteringIgnored(ProtectionThreatFinding.scanGroups(report.findings))
        checkupReview = groups
        return ProtectionCheckupSummary.tile(for: groups, unreadableLocations: report.unreadableLocations.count)
    }

    /// Removes only the threats selected in `checkupReview`.
    public func checkupRun(progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let selected = checkupReview.selectedItems
        guard !selected.isEmpty else { return RunOutcome(module: module, summary: "No threats selected") }
        let outcome = try await perform(selected, progress: progress)
        let done = Set(outcome.removedItemIDs)
        state.update { $0.checkupReview.removeItems(withIDs: done) }
        return outcome
    }

    // MARK: Apple protection

    /// Reads XProtect's version and the state of Gatekeeper, SIP, FileVault and the firewall.
    public func appleProtectionStatus() async -> ProtectionAppleStatus {
        let status = await ProtectionAppleStatusReader.read()
        state.update { $0.appleStatus = status }
        return status
    }

    // MARK: Real-time protection

    /// Starts watching LaunchAgents/LaunchDaemons folders for new third-party startup items.
    public func startRealtimeProtection() { realtime.start() }

    /// Stops the watcher (it starts again when real-time protection is switched on).
    public func stopRealtimeProtection() { realtime.stop() }

    public var isRealtimeProtectionActive: Bool { realtime.isRunning }

    /// Startup items noticed since launch, newest first.
    public var realtimeEvents: [ProtectionRealtimeEvent] { realtime.recentEvents }

    private func followRealtimeSetting() {
        let enabled = withObservationTracking {
            SettingsStore.shared.settings.realtimeProtection
        } onChange: { [weak self] in
            guard let engine = self else { return }
            DispatchQueue.main.async { engine.followRealtimeSetting() }
        }
        if enabled {
            realtime.start()
        } else {
            realtime.stop()
        }
    }

    // MARK: Helpers

    /// A scanner with the built-in catalog merged with the threat list (while it's on), and
    /// Apple's XProtect rules plus the threat list's rules. Call off the main thread.
    func makeScanner(crontab: String?) -> ProtectionMalwareScanner {
        let inputs = library.scannerInputs()
        return ProtectionMalwareScanner(space: ProtectionPathSpace(home: NSHomeDirectory()), catalog: inputs.catalog,
                                        probe: probe, crontab: crontab, ruleSources: inputs.ruleSources)
    }

    /// The user's crontab, or nil when there is none.
    static func readCrontab() async -> String? {
        let result = await Shell.run("/usr/bin/crontab", ["-l"], timeout: 10)
        guard result.status == 0 else { return nil }
        return result.stdout
    }
}

/// Latest results kept by the engine.
struct ProtectionEngineState: Sendable {
    var malwareReport: ProtectionMalwareReport?
    var automaticReport: ProtectionMalwareReport?
    var appleStatus: ProtectionAppleStatus?
    var checkupReview: [ScanGroup] = []
}
