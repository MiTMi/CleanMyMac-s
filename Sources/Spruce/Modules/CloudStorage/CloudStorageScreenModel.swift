import AppKit
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

/// Where the Cloud Storage journey is.
enum CloudStoragePhase: Equatable {
    case providers
    case scanning
    case results
    case freeingUp
    case done
    case failed(String)
}

/// Which list the results panel shows for the selected provider.
enum CloudStorageListMode: String, CaseIterable, Identifiable {
    case downloaded
    case cloudOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloaded: return "On This Mac"
        case .cloudOnly: return "Online-Only"
        }
    }

    var symbol: String {
        switch self {
        case .downloaded: return "internaldrive"
        case .cloudOnly: return "icloud"
        }
    }
}

/// The selected files of one provider.
struct CloudStorageSelectionGroup: Identifiable {
    let provider: CloudStorageProvider
    let count: Int
    let bytes: Int64

    var id: String { provider.id }
}

/// State of the Cloud Storage module: detected providers, the scan, per-provider
/// results, the Free Up Locally selection, downloads in progress and completion.
/// One instance per engine, so results survive navigation.
@MainActor
@Observable
final class CloudStorageScreenModel {
    private static var instances: [ObjectIdentifier: CloudStorageScreenModel] = [:]

    static func shared(for engine: CloudStorageEngine) -> CloudStorageScreenModel {
        let key = ObjectIdentifier(engine)
        if let existing = instances[key] { return existing }
        let model = CloudStorageScreenModel(engine: engine)
        instances[key] = model
        return model
    }

    let engine: CloudStorageEngine

    private(set) var phase: CloudStoragePhase = .providers
    private(set) var providers: [CloudStorageProvider] = []
    /// False until the first look for cloud folders has finished.
    private(set) var providersLoaded = false
    private(set) var isDetecting = false
    private(set) var excludedProviderIDs: Set<String> = []
    private(set) var reports: [CloudStorageProviderReport] = []
    var selectedReportID: String?
    /// Paths chosen for Free Up Locally (across all providers).
    private(set) var selection: Set<String> = []
    var listMode: CloudStorageListMode = .downloaded
    var search = ""

    // Scanning
    private(set) var scanningProviders: [CloudStorageProvider] = []
    private(set) var ticks: [String: CloudStorageScanTick] = [:]
    private(set) var scanStarted = Date()
    /// Providers being re-scanned individually from the results screen.
    private(set) var rescanning: Set<String> = []

    // Actions
    var confirmShown = false
    /// A single file chosen from a row's "Free Up Locally…" (leaves the selection alone).
    private(set) var singleTarget: CloudStorageFileRecord?
    private(set) var workProgress = ScanProgress(message: "")
    private(set) var outcome: RunOutcome?
    private(set) var downloadingPaths: Set<String> = []
    var toast: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var scanAfterDetecting = false
    private static let excludedKey = "cloudStorage.excludedProviders"

    private init(engine: CloudStorageEngine) {
        self.engine = engine
        excludedProviderIDs = Set(UserDefaults.standard.stringArray(forKey: Self.excludedKey) ?? [])
        if !engine.lastReports.isEmpty {
            reports = engine.lastReports
            selectedReportID = reports.first?.id
            selectRecommended()
            phase = .results
        }
    }

    // MARK: Derived

    var includedProviders: [CloudStorageProvider] {
        providers.filter { !excludedProviderIDs.contains($0.id) }
    }

    var selectedReport: CloudStorageProviderReport? {
        reports.first { $0.id == selectedReportID } ?? reports.first
    }

    var overview: CloudStorageOverview { CloudStorageOverview(reports: reports) }

    var isBusy: Bool { phase == .scanning || phase == .freeingUp }

    /// Every listed downloaded file, with its provider.
    private var allLocalRecords: [(record: CloudStorageFileRecord, provider: CloudStorageProvider)] {
        reports.flatMap { report in
            report.largestLocal.map { (record: $0, provider: report.provider) }
        }
    }

    var selectedRecords: [CloudStorageFileRecord] {
        allLocalRecords.filter { selection.contains($0.record.path) }.map { $0.record }
    }

    var selectedBytes: Int64 { selectedRecords.reduce(Int64(0)) { $0 + $1.localBytes } }

    /// Listed downloaded files that can be freed (the footer's "of N found").
    var freeableListedBytes: Int64 {
        allLocalRecords.filter { eligibility($0.record, $0.provider).canSelect }.reduce(Int64(0)) { $0 + $1.record.localBytes }
    }

    var freeableListedCount: Int {
        allLocalRecords.filter { eligibility($0.record, $0.provider).canSelect }.count
    }

    /// What the confirmation sheet will free: one row's file, or the selection.
    var freeUpTargets: [CloudStorageFileRecord] {
        if let singleTarget { return [singleTarget] }
        return selectedRecords
    }

    /// Bytes and counts per provider of `freeUpTargets`, for the confirmation sheet.
    var selectionByProvider: [CloudStorageSelectionGroup] {
        let targets = Set(freeUpTargets.map(\.path))
        return reports.compactMap { report in
            let chosen = report.largestLocal.filter { targets.contains($0.path) }
            guard !chosen.isEmpty else { return nil }
            return CloudStorageSelectionGroup(provider: report.provider, count: chosen.count,
                                              bytes: chosen.reduce(Int64(0)) { $0 + $1.localBytes })
        }
    }

    func eligibility(_ record: CloudStorageFileRecord, _ provider: CloudStorageProvider) -> CloudStorageEligibility {
        var record = record
        if downloadingPaths.contains(record.path) { record.status.downloadRequested = true }
        return engine.eligibility(for: record, in: provider)
    }

    /// Rows for the selected provider and list mode, filtered by the search text.
    func visibleRecords(for report: CloudStorageProviderReport) -> [CloudStorageFileRecord] {
        let records = listMode == .downloaded ? report.largestLocal : report.largestCloudOnly
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return records }
        return records.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    func selectionState(of records: [CloudStorageFileRecord], provider: CloudStorageProvider) -> SelectionState {
        let selectable = records.filter { eligibility($0, provider).canSelect }
        guard !selectable.isEmpty else { return .none }
        let chosen = selectable.filter { selection.contains($0.path) }.count
        if chosen == 0 { return .none }
        return chosen == selectable.count ? .all : .some
    }

    func scanStep(for provider: CloudStorageProvider) -> PrismScanStep {
        let tick = ticks[provider.id]
        let state: PrismScanStep.State
        if let tick, tick.finished {
            state = .done(ByteFormat.string(tick.localBytes) + " here")
        } else if tick != nil || phase == .scanning {
            state = .running
        } else {
            state = .waiting
        }
        return PrismScanStep(id: provider.id, title: provider.name, symbol: provider.kind.symbol, state: state,
                             runningLabel: tick.map { "\(CountFormat.items($0.filesSeen, singular: "file"))…" })
    }

    /// Live progress for the scanning screen.
    var scanProgress: ScanProgress {
        let all = Array(ticks.values)
        let finished = all.filter(\.finished).count
        let files = all.reduce(0) { $0 + $1.filesSeen }
        let local = all.reduce(Int64(0)) { $0 + $1.localBytes }
        let current = all.filter { !$0.finished }.compactMap(\.currentPath).first
        let count = max(scanningProviders.count, 1)
        let fraction = scanningProviders.isEmpty ? nil : Double(finished) / Double(count)
        let message = files == 0
            ? "Looking inside your cloud folders…"
            : "\(CountFormat.items(files, singular: "file")) checked · nothing is downloaded"
        return ScanProgress(fraction: fraction, message: message, current: current?.abbreviatingHome, bytesFound: local)
    }

    // MARK: Providers

    /// Looks for cloud folders again (off the main thread), optionally scanning after.
    func refreshProviders(thenScan: Bool = false) {
        if thenScan { scanAfterDetecting = true }
        guard !isDetecting else { return }
        isDetecting = true
        let engine = self.engine
        Task { [weak self] in
            let found = await engine.detectProviders()
            guard let self else { return }
            self.providers = found
            self.providersLoaded = true
            self.isDetecting = false
            let scan = self.scanAfterDetecting
            self.scanAfterDetecting = false
            if scan && self.phase == .providers && !self.includedProviders.isEmpty {
                self.startScan()
            }
        }
    }

    func isIncluded(_ provider: CloudStorageProvider) -> Bool {
        !excludedProviderIDs.contains(provider.id)
    }

    func toggleProvider(_ provider: CloudStorageProvider) {
        if excludedProviderIDs.contains(provider.id) {
            excludedProviderIDs.remove(provider.id)
        } else {
            excludedProviderIDs.insert(provider.id)
        }
        UserDefaults.standard.set(Array(excludedProviderIDs).sorted(), forKey: Self.excludedKey)
    }

    // MARK: Scan

    func startScan() {
        let targets = includedProviders
        guard !targets.isEmpty, !isBusy else { return }
        task?.cancel()
        stopPolling()
        scanningProviders = targets
        ticks = [:]
        scanStarted = Date()
        outcome = nil
        phase = .scanning
        SpruceSound.play(.scanStart)
        let engine = self.engine
        let settings = SettingsStore.shared.settings
        task = Task { [weak self] in
            do {
                let result = try await engine.scan(targets, settings: settings, progress: { tick in
                    Task { @MainActor [weak self] in self?.receive(tick) }
                })
                guard let self, !Task.isCancelled else { return }
                self.reports = result
                if !result.contains(where: { $0.id == self.selectedReportID }) {
                    self.selectedReportID = result.first(where: { $0.stats.localBytes > 0 })?.id ?? result.first?.id
                }
                self.selection = []
                self.downloadingPaths = []
                self.selectRecommended()
                self.listMode = .downloaded
                self.phase = .results
                if Date().timeIntervalSince(self.scanStarted) > 1.5 { SpruceSound.play(.scanComplete) }
                let overview = self.overview
                HistoryStore.shared.record(ActivityEntry(
                    module: .cloudStorage, kind: .scan, bytes: overview.freeableBytes, count: overview.stats.localFileCount,
                    summary: "\(ByteFormat.string(overview.stats.localBytes)) of cloud files on this Mac"))
            } catch {
                guard let self else { return }
                if (error as? SpruceError) == .cancelled {
                    self.phase = self.reports.isEmpty ? .providers : .results
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func receive(_ tick: CloudStorageScanTick) {
        guard phase == .scanning || rescanning.contains(tick.providerID) else { return }
        ticks[tick.providerID] = tick
    }

    func cancelScan() {
        task?.cancel()
        task = nil
        phase = reports.isEmpty ? .providers : .results
    }

    /// Re-scans one provider in place (results stay on screen).
    func rescan(_ report: CloudStorageProviderReport) {
        let id = report.id
        guard !rescanning.contains(id), !isBusy else { return }
        rescanning.insert(id)
        let provider = report.provider
        let engine = self.engine
        let settings = SettingsStore.shared.settings
        Task { [weak self] in
            let result = try? await engine.scan([provider], settings: settings, replacingAll: false, progress: { _ in })
            guard let self else { return }
            self.rescanning.remove(id)
            guard let fresh = result?.first else { return }
            if let index = self.reports.firstIndex(where: { $0.id == id }) {
                self.reports[index] = fresh
            }
            let paths = Set((fresh.largestLocal + fresh.largestCloudOnly).map(\.path))
            self.selection = self.selection.filter { !report.provider.contains($0) || paths.contains($0) }
            self.showToast("\(provider.name) is up to date")
        }
    }

    /// Back to the provider cards for a fresh scan.
    func newScan() {
        task?.cancel()
        stopPolling()
        engine.forgetResults()
        reports = []
        selection = []
        downloadingPaths = []
        outcome = nil
        search = ""
        refreshProviders()
        phase = .providers
    }

    func retry() {
        if includedProviders.isEmpty {
            phase = .providers
            refreshProviders(thenScan: true)
        } else {
            startScan()
        }
    }

    /// The `cloudStorage` tool id: show the module, scanning right away when idle.
    func openFromTool() {
        switch phase {
        case .providers:
            refreshProviders(thenScan: true)
        case .done:
            showResults()
        default:
            break
        }
    }

    // MARK: Selection

    func isSelected(_ record: CloudStorageFileRecord) -> Bool { selection.contains(record.path) }

    func toggle(_ record: CloudStorageFileRecord, provider: CloudStorageProvider) {
        if selection.contains(record.path) {
            selection.remove(record.path)
        } else if eligibility(record, provider).canSelect {
            selection.insert(record.path)
        }
    }

    func setSelected(_ records: [CloudStorageFileRecord], provider: CloudStorageProvider, _ selected: Bool) {
        for record in records {
            if selected {
                if eligibility(record, provider).canSelect { selection.insert(record.path) }
            } else {
                selection.remove(record.path)
            }
        }
    }

    /// Selects every suggested file (synced, untouched for a while) in every provider.
    func selectRecommended() {
        for report in reports {
            for record in report.largestLocal where eligibility(record, report.provider).isRecommended {
                selection.insert(record.path)
            }
        }
    }

    /// Selects only the suggested files of one provider, replacing its current choice.
    func selectSuggested(in report: CloudStorageProviderReport) {
        for record in report.largestLocal {
            if eligibility(record, report.provider).isRecommended {
                selection.insert(record.path)
            } else {
                selection.remove(record.path)
            }
        }
    }

    // MARK: Free up locally

    func requestFreeUp() {
        guard !selectedRecords.isEmpty, !isBusy else { return }
        singleTarget = nil
        confirmShown = true
    }

    func requestFreeUp(_ record: CloudStorageFileRecord, provider: CloudStorageProvider) {
        guard eligibility(record, provider).canSelect, !isBusy else { return }
        singleTarget = record
        confirmShown = true
    }

    func cancelFreeUp() {
        confirmShown = false
        singleTarget = nil
    }

    func confirmFreeUp() {
        let targets = freeUpTargets
        confirmShown = false
        singleTarget = nil
        guard !targets.isEmpty else { return }
        task?.cancel()
        workProgress = ScanProgress(fraction: 0, message: "Preparing…")
        phase = .freeingUp
        let engine = self.engine
        let settings = SettingsStore.shared.settings
        task = Task { [weak self] in
            let result = await engine.freeUpLocally(targets, settings: settings, progress: { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.phase == .freeingUp else { return }
                    self.workProgress = progress
                }
            })
            guard let self else { return }
            self.reports = result.reports
            self.selection.subtract(result.outcome.removedItemIDs)
            self.outcome = result.outcome
            self.phase = .done
            if result.outcome.processedCount > 0 {
                HistoryStore.shared.record(result.outcome, kind: .cloudFreed)
            }
        }
    }

    func showResults() {
        outcome = nil
        phase = reports.isEmpty ? .providers : .results
    }

    // MARK: Download

    func download(_ records: [CloudStorageFileRecord]) {
        let targets = records.filter { $0.isCloudOnly && !downloadingPaths.contains($0.path) }
        guard !targets.isEmpty else { return }
        downloadingPaths.formUnion(targets.map(\.path))
        let engine = self.engine
        Task { [weak self] in
            let result = await engine.download(targets, progress: { _ in })
            guard let self else { return }
            self.reports = result.reports
            let requested = Set(result.outcome.removedItemIDs)
            self.downloadingPaths = self.downloadingPaths.filter { path in
                requested.contains(path) || !targets.contains { $0.path == path }
            }
            if let failure = result.outcome.failures.first {
                self.showToast("\(failure.title): \(failure.reason)")
            } else {
                self.showToast(result.outcome.summary)
            }
            self.startPolling()
        }
    }

    func isDownloading(_ record: CloudStorageFileRecord) -> Bool {
        downloadingPaths.contains(record.path) || record.status.downloadRequested || record.status.isDownloading
    }

    /// Follows requested downloads until they land (or 15 minutes pass).
    private func startPolling() {
        guard pollTask == nil else { return }
        let engine = self.engine
        pollTask = Task { [weak self] in
            let started = Date()
            while !Task.isCancelled, Date().timeIntervalSince(started) < 900 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let watching = self.reports.flatMap { $0.largestCloudOnly + $0.largestLocal }
                    .filter { self.downloadingPaths.contains($0.path) }
                if watching.isEmpty { break }
                let result = await engine.refresh(watching)
                guard !Task.isCancelled else { return }
                self.reports = result.reports
                let landed = Set(result.updatedRecords.filter { !$0.isCloudOnly }.map(\.path))
                let missing = Set(watching.map(\.path)).subtracting(result.updatedRecords.map(\.path))
                self.downloadingPaths.subtract(landed.union(missing))
                if !landed.isEmpty {
                    self.showToast("\(CountFormat.items(landed.count, singular: "file")) downloaded")
                }
            }
            self?.pollTask = nil
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Finder

    func reveal(_ records: [CloudStorageFileRecord]) {
        engine.reveal(records.map(\.path))
    }

    func openInFinder(_ provider: CloudStorageProvider) {
        engine.openInFinder(provider)
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(Motion.standard) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(Motion.standard) { self.toast = nil }
        }
    }
}
