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
public final class ProtectionEngine: CheckupContributor, GroupScanner, @unchecked Sendable {
    public var checkupReview: [ScanGroup] = []
    public let module: ModuleID = .protection

    /// Browser and macOS privacy traces.
    public let privacy: ProtectionPrivacyCleaner
    /// Apps holding macOS privacy permissions.
    public let permissions: ProtectionPermissionsReviewer
    /// Watches startup-item folders while real-time protection is on.
    public let realtime: ProtectionRealtimeMonitor

    let probe = ProtectionMacSystemProbe()
    private let state = ProtectionLocked(ProtectionEngineState())

    public init() {
        privacy = ProtectionPrivacyCleaner()
        permissions = ProtectionPermissionsReviewer()
        realtime = ProtectionRealtimeMonitor(probe: probe)
        // Real-time protection follows Settings › Protection for the app's whole lifetime.
        DispatchQueue.main.async { [weak self] in
            self?.followRealtimeSetting()
        }
    }

    // MARK: Results

    /// The last completed malware scan (module or Checkup).
    public var lastMalwareReport: ProtectionMalwareReport? { state.current.malwareReport }

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
    /// and suspicious files are hashed against known samples.
    public func scanMalware(depth: ProtectionScanDepth, progress: @escaping ProgressHandler) async throws -> ProtectionMalwareReport {
        progress(ScanProgress(fraction: 0, message: "Preparing a \(depth.title.lowercased()) scan…"))
        let crontab = await Self.readCrontab()
        let scanner = makeScanner(crontab: crontab)
        let report = try await ProtectionMac.runBlocking { flag in
            try scanner.scan(depth: depth, progress: progress, isCancelled: { flag.isCancelled })
        }
        state.update { $0.malwareReport = report }
        let summary = report.threatCount == 0
            ? "\(depth.title) malware scan: no threats"
            : "\(depth.title) malware scan: \(CountFormat.items(report.threatCount, singular: "threat"))"
        await ProtectionMac.record(ActivityEntry(module: .protection, kind: .malwareScan, count: report.threatCount, summary: summary))
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
        checkupReview.removeItems(withIDs: Set(outcome.removedItemIDs))
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

    func makeScanner(crontab: String?) -> ProtectionMalwareScanner {
        ProtectionMalwareScanner(space: ProtectionPathSpace(home: NSHomeDirectory()), probe: probe, crontab: crontab)
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
    var appleStatus: ProtectionAppleStatus?
}
