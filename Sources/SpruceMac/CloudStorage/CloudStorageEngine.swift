import AppKit
import Foundation
import SpruceCore

/// What a Free Up Locally or Download action did.
public struct CloudStorageActionResult: Sendable {
    public var outcome: RunOutcome
    /// Re-measured versions of the records that changed.
    public var updatedRecords: [CloudStorageFileRecord]
    /// The engine's reports after applying the changes.
    public var reports: [CloudStorageProviderReport]

    public init(outcome: RunOutcome, updatedRecords: [CloudStorageFileRecord], reports: [CloudStorageProviderReport]) {
        self.outcome = outcome
        self.updatedRecords = updatedRecords
        self.reports = reports
    }
}

/// Finds locally stored cloud files (iCloud Drive, File Provider apps such as Google
/// Drive, OneDrive, Dropbox and Box, and legacy sync folders) and frees local copies.
///
/// Spruce never signs in to a cloud account and never deletes anything from the cloud:
/// "Free Up Locally" asks macOS to drop the downloaded copy, leaving an online-only
/// placeholder in Finder that downloads again on open. Scans run on threads that are
/// forbidden from downloading online-only files.
///
/// CONTRACT: keep `public init()`. The rest of the API is owned by this module.
public final class CloudStorageEngine: @unchecked Sendable {
    public init() {}

    /// Downloaded files at or above this size count as "large".
    public let largeFileThreshold: Int64 = 100_000_000

    private let lock = NSLock()
    private var storedReports: [CloudStorageProviderReport] = []
    private var storedScanDate: Date?
    private var storedTools: CloudStorageToolAvailability?
    private var storedPolicy = CloudStorageEvictionPolicy()

    // MARK: State

    /// Reports from the last scan, updated in place by actions. Survives navigation.
    public var lastReports: [CloudStorageProviderReport] {
        lock.lock()
        defer { lock.unlock() }
        return storedReports
    }

    public var lastScanDate: Date? {
        lock.lock()
        defer { lock.unlock() }
        return storedScanDate
    }

    /// Rules for which local copies are suggested.
    public var policy: CloudStorageEvictionPolicy {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedPolicy
        }
        set {
            lock.lock()
            storedPolicy = newValue
            lock.unlock()
        }
    }

    /// Forgets the last scan (New Scan).
    public func forgetResults() {
        lock.lock()
        storedReports = []
        storedScanDate = nil
        lock.unlock()
    }

    /// Drops listed files that are on the ignore list from the stored results, out of
    /// the lists and the totals as a new scan would, and returns the reports. Call it
    /// after adding to the ignore list ("Ignore from Now On") or when a scan that began
    /// before such a change finishes.
    @discardableResult
    public func dropIgnored(_ settings: SpruceSettings) -> [CloudStorageProviderReport] {
        lock.lock()
        defer { lock.unlock() }
        let threshold = largeFileThreshold
        storedReports = storedReports.map { $0.removingIgnored(settings, largeThreshold: threshold) }
        return storedReports
    }

    // MARK: Providers

    /// Cloud folders on this Mac, iCloud Drive first. Runs off the main thread with
    /// downloads disabled, so an online-only app container can never stall it.
    public func detectProviders(home: String = NSHomeDirectory()) async -> [CloudStorageProvider] {
        await CloudStorageThreadRunner.run { CloudStorageDiscovery.discover(home: home) }
    }

    /// Whether a downloaded file is suggested, allowed or blocked.
    public func eligibility(for record: CloudStorageFileRecord, in provider: CloudStorageProvider,
                            now: Date = Date()) -> CloudStorageEligibility {
        policy.eligibility(for: record, mechanism: provider.mechanism, now: now)
    }

    /// Optional command-line helpers available on this Mac (detected once).
    public func toolAvailability() async -> CloudStorageToolAvailability {
        if let cached = cachedTools { return cached }
        let detected = await CloudStorageTools.detect()
        storeTools(detected)
        return detected
    }

    private var cachedTools: CloudStorageToolAvailability? {
        lock.lock()
        defer { lock.unlock() }
        return storedTools
    }

    private func storeTools(_ tools: CloudStorageToolAvailability) {
        lock.lock()
        storedTools = tools
        lock.unlock()
    }

    // MARK: Scan

    /// Measures each provider's local and cloud-only content and lists the largest
    /// files. Nothing is downloaded. Throws `SpruceError.cancelled` when cancelled.
    ///
    /// - Parameter replacingAll: true for a full scan (the results replace the previous
    ///   ones); false to refresh just these providers inside the previous results.
    public func scan(_ providers: [CloudStorageProvider], settings: SpruceSettings, replacingAll: Bool = true,
                     progress: @escaping CloudStorageScanTickHandler) async throws -> [CloudStorageProviderReport] {
        let flag = CloudStorageCancelFlag()
        let options = scanOptions(settings)
        let ignoredIDs = Set(settings.ignoredItemIDs)
        let threshold = largeFileThreshold

        let reports: [CloudStorageProviderReport] = await withTaskCancellationHandler {
            await withTaskGroup(of: (Int, CloudStorageProviderReport).self) { group in
                for (index, provider) in providers.enumerated() {
                    group.addTask {
                        let report = await CloudStorageThreadRunner.run {
                            CloudStorageEngine.scanOne(provider, options: options, ignoredIDs: ignoredIDs,
                                                       threshold: threshold, flag: flag, progress: progress)
                        }
                        return (index, report)
                    }
                }
                var results: [(Int, CloudStorageProviderReport)] = []
                for await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
        } onCancel: {
            flag.cancel()
        }

        if flag.isCancelled || Task.isCancelled { throw SpruceError.cancelled }
        store(reports, replacingAll: replacingAll)
        return reports
    }

    private func store(_ reports: [CloudStorageProviderReport], replacingAll: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if replacingAll {
            storedReports = reports
        } else {
            for report in reports {
                if let index = storedReports.firstIndex(where: { $0.id == report.id }) {
                    storedReports[index] = report
                } else {
                    storedReports.append(report)
                }
            }
        }
        storedScanDate = Date()
    }

    private func scanOptions(_ settings: SpruceSettings) -> CloudStorageScanOptions {
        var ignored: (@Sendable (String) -> Bool)?
        if !settings.ignoredPaths.isEmpty {
            ignored = { path in settings.isIgnored(path: path) }
        }
        return CloudStorageScanOptions(largeFileThreshold: largeFileThreshold, listMinimumSize: 1_000_000,
                                       localListLimit: 300, cloudListLimit: 100, isIgnored: ignored)
    }

    /// Runs on a no-download thread: walk, then read sync state for the listed files.
    private static func scanOne(_ provider: CloudStorageProvider, options: CloudStorageScanOptions,
                                ignoredIDs: Set<String>, threshold: Int64, flag: CloudStorageCancelFlag,
                                progress: @escaping CloudStorageScanTickHandler) -> CloudStorageProviderReport {
        var report = CloudStorageScanner.scan(provider, options: options, isCancelled: { flag.isCancelled },
                                              progress: progress)
        if !ignoredIDs.isEmpty {
            report = report.removing(where: { ignoredIDs.contains($0.id) }, largeThreshold: threshold)
        }
        guard !flag.isCancelled else { return report }

        let originals = report.largestLocal + report.largestCloudOnly
        let enrichedLocal = CloudStorageMetadata.enrich(report.largestLocal, mechanism: provider.mechanism)
        let enrichedCloud = CloudStorageMetadata.enrich(report.largestCloudOnly, mechanism: provider.mechanism)
        report.largestLocal = enrichedLocal
        report.largestCloudOnly = enrichedCloud
        // iCloud's own download status can reclassify a file; keep lists and totals in step.
        let flipped = (enrichedLocal + enrichedCloud).filter { record in
            originals.first(where: { $0.path == record.path }).map { $0.isCloudOnly != record.isCloudOnly } ?? false
        }
        if !flipped.isEmpty {
            var restored = report
            restored.largestLocal = report.largestLocal.map { record in
                flipped.contains(where: { $0.path == record.path }) ? (originals.first { $0.path == record.path } ?? record) : record
            }
            restored.largestCloudOnly = report.largestCloudOnly.map { record in
                flipped.contains(where: { $0.path == record.path }) ? (originals.first { $0.path == record.path } ?? record) : record
            }
            report = restored.applying(flipped, largeThreshold: threshold)
        }
        return report
    }

    // MARK: Free up locally

    /// Removes the downloaded copies of `records` from this Mac. The files stay in the
    /// cloud. Each item is re-checked first (still inside a scanned cloud folder, same
    /// file, uploaded, no conflicts, not on the ignore list), then evicted with the
    /// first method that works — `evictUbiquitousItem`, then `brctl evict` (iCloud) or
    /// `fileproviderctl evict` (File Provider, where the tool still has that verb) —
    /// and finally re-measured to confirm the space really came back.
    public func freeUpLocally(_ records: [CloudStorageFileRecord], settings: SpruceSettings,
                              progress: @escaping ProgressHandler) async -> CloudStorageActionResult {
        let tools = await toolAvailability()
        let providers = lastReports.map(\.provider)
        let policy = self.policy
        var failures: [ItemFailure] = []
        var doneIDs: [String] = []
        var freedBytes: Int64 = 0
        var updated: [CloudStorageFileRecord] = []
        var pending: [(before: CloudStorageFileRecord, provider: CloudStorageProvider)] = []
        let total = max(records.count, 1)

        func fail(_ record: CloudStorageFileRecord, _ reason: String) {
            failures.append(ItemFailure(itemID: record.id, title: record.name, reason: reason))
            OperationLog.shared.record(module: .cloudStorage, action: "evict", result: "skipped",
                                       detail: "\(record.path) — \(reason)")
        }

        for (index, record) in records.enumerated() {
            if Task.isCancelled { break }
            progress(ScanProgress(fraction: Double(index) / Double(total) * 0.8,
                                  message: "Removing the local copy of \(record.name)…",
                                  current: record.path.abbreviatingHome, bytesFound: freedBytes))

            guard let provider = providers.first(where: { $0.contains(record.path) }) else {
                fail(record, "Not inside a scanned cloud folder")
                continue
            }
            guard provider.mechanism.canFreeUpLocally else {
                fail(record, "\(provider.name) keeps every file on this Mac; switch it to online-only files in its app")
                continue
            }
            if settings.isIgnored(path: record.path) || settings.ignoredItemIDs.contains(record.id) {
                fail(record, "On the ignore list")
                continue
            }
            let snapshot = record
            guard var current = await CloudStorageThreadRunner.run({ CloudStorageScanner.remeasure(snapshot) }) else {
                fail(record, "Moved or deleted since the scan")
                continue
            }
            if record.inode != 0 && current.inode != record.inode {
                fail(record, "Changed since the scan; skipped")
                continue
            }
            if current.isCloudOnly || current.localBytes == 0 {
                current.status = CloudStorageSyncStatus(download: .notDownloaded)
                updated.append(current)
                doneIDs.append(record.id)
                continue
            }
            let path = record.path
            current.status = await CloudStorageThreadRunner.run { CloudStorageMetadata.status(at: path) }
            current.lastUsed = record.lastUsed
            if case .blocked(let reason) = policy.eligibility(for: current, mechanism: provider.mechanism) {
                fail(record, reason)
                continue
            }

            var errors: [String] = []
            var accepted = false
            for strategy in CloudStorageEvictionPlanner.strategies(for: provider.mechanism, tools: tools) {
                switch strategy {
                case .fileManager:
                    let evictError: String? = await CloudStorageThreadRunner.run(allowMaterialization: true) {
                        do {
                            try FileManager.default.evictUbiquitousItem(at: URL(fileURLWithPath: path))
                            return nil
                        } catch {
                            return error.cloudStorageMessage
                        }
                    }
                    if let evictError { errors.append(evictError) } else { accepted = true }
                case .brctl:
                    if let toolError = await CloudStorageTools.run(CloudStorageTools.brctlPath, verb: "evict", path: path) {
                        errors.append(toolError)
                    } else {
                        accepted = true
                    }
                case .fileProviderCtl:
                    if let toolError = await CloudStorageTools.run(CloudStorageTools.fileProviderCtlPath, verb: "evict", path: path) {
                        errors.append(toolError)
                    } else {
                        accepted = true
                    }
                }
                if accepted { break }
            }
            if accepted {
                pending.append((current, provider))
            } else {
                var reason = CloudStorageText.manualAdvice(for: provider.kind)
                if let last = errors.last, !last.isEmpty { reason += " (\(last))" }
                fail(record, reason)
            }
        }

        // Confirm: eviction can finish a moment after the request returns.
        if !pending.isEmpty {
            progress(ScanProgress(fraction: 0.85, message: "Checking that the space came back…", bytesFound: freedBytes))
        }
        var remaining = pending
        let deadline = Date().addingTimeInterval(min(15, 3 + Double(pending.count) * 0.25))
        while !remaining.isEmpty {
            let befores = remaining.map { $0.before }
            let measured = await CloudStorageThreadRunner.run { befores.map { CloudStorageScanner.remeasure($0) } }
            var stillLocal: [(before: CloudStorageFileRecord, provider: CloudStorageProvider)] = []
            for (entry, measuredAfter) in zip(remaining, measured) {
                guard var after = measuredAfter else {
                    fail(entry.before, "Disappeared while its local copy was being removed")
                    continue
                }
                if CloudStorageEvictionPlanner.isFreed(before: entry.before, after: after) {
                    let freed = max(0, entry.before.localBytes - after.localBytes)
                    freedBytes += freed
                    doneIDs.append(entry.before.id)
                    after.status = CloudStorageSyncStatus(download: .notDownloaded, isUploaded: true)
                    updated.append(after)
                    OperationLog.shared.record(module: .cloudStorage, action: "evict", result: "ok", bytes: freed,
                                               detail: entry.before.path)
                } else {
                    stillLocal.append(entry)
                }
            }
            remaining = stillLocal
            if remaining.isEmpty || Date() >= deadline || Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        for entry in remaining {
            fail(entry.before, "macOS accepted the request, but the file is still on this Mac. " +
                 CloudStorageText.manualAdvice(for: entry.provider.kind))
        }

        let reports = apply(updated)
        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: freedBytes))
        let outcome = RunOutcome(
            module: .cloudStorage,
            freedBytes: freedBytes,
            processedCount: doneIDs.count,
            removedItemIDs: doneIDs,
            failures: failures,
            summary: CloudStorageText.freeUpSummary(freedCount: doneIDs.count, freedBytes: freedBytes,
                                                    failedCount: failures.count)
        )
        return CloudStorageActionResult(outcome: outcome, updatedRecords: updated, reports: reports)
    }

    // MARK: Download

    /// Asks macOS to download online-only files (they stay in sync afterwards).
    /// Downloads continue in the background; use `refresh(_:)` to follow them.
    public func download(_ records: [CloudStorageFileRecord], progress: @escaping ProgressHandler) async -> CloudStorageActionResult {
        let tools = await toolAvailability()
        let providers = lastReports.map(\.provider)
        var failures: [ItemFailure] = []
        var requestedIDs: [String] = []
        var updated: [CloudStorageFileRecord] = []
        let total = max(records.count, 1)

        for (index, record) in records.enumerated() {
            if Task.isCancelled { break }
            progress(ScanProgress(fraction: Double(index) / Double(total), message: "Requesting \(record.name)…",
                                  current: record.path.abbreviatingHome))
            guard let provider = providers.first(where: { $0.contains(record.path) }) else {
                failures.append(ItemFailure(itemID: record.id, title: record.name, reason: "Not inside a scanned cloud folder"))
                continue
            }
            let snapshot = record
            guard var current = await CloudStorageThreadRunner.run({ CloudStorageScanner.remeasure(snapshot) }) else {
                failures.append(ItemFailure(itemID: record.id, title: record.name, reason: "Moved or deleted since the scan"))
                continue
            }
            current.lastUsed = record.lastUsed
            if !current.isCloudOnly {
                current.status = CloudStorageSyncStatus(download: .current)
                updated.append(current)
                continue
            }
            let path = record.path
            var downloadError: String? = await CloudStorageThreadRunner.run(allowMaterialization: true) {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))
                    return nil
                } catch {
                    return error.cloudStorageMessage
                }
            }
            if downloadError != nil {
                switch provider.mechanism {
                case .iCloud where tools.brctl:
                    downloadError = await CloudStorageTools.run(CloudStorageTools.brctlPath, verb: "download", path: path)
                case .fileProvider where tools.fileProviderCtlMaterialize:
                    downloadError = await CloudStorageTools.run(CloudStorageTools.fileProviderCtlPath, verb: "materialize", path: path)
                case .fileProvider:
                    // Reading the first byte makes the provider fetch the whole file.
                    // Runs in its own process so a slow download never blocks Spruce.
                    if !current.isPackage {
                        Task.detached(priority: .utility) {
                            _ = await Shell.run("/usr/bin/head", ["-c", "1", path], timeout: 3_600)
                        }
                        downloadError = nil
                    }
                default:
                    break
                }
            }
            if let downloadError {
                failures.append(ItemFailure(itemID: record.id, title: record.name,
                                            reason: "Couldn't start the download: \(downloadError)"))
                OperationLog.shared.record(module: .cloudStorage, action: "download", result: "error",
                                           detail: "\(path) — \(downloadError)")
            } else {
                current.status.downloadRequested = true
                updated.append(current)
                requestedIDs.append(record.id)
                OperationLog.shared.record(module: .cloudStorage, action: "download", result: "requested",
                                           bytes: current.logicalSize, detail: path)
            }
        }

        let reports = apply(updated)
        progress(ScanProgress(fraction: 1, message: "Done"))
        let outcome = RunOutcome(
            module: .cloudStorage,
            processedCount: requestedIDs.count,
            removedItemIDs: requestedIDs,
            failures: failures,
            summary: CloudStorageText.downloadSummary(requested: requestedIDs.count, failed: failures.count)
        )
        return CloudStorageActionResult(outcome: outcome, updatedRecords: updated, reports: reports)
    }

    /// Re-measures records (e.g. downloads in progress) and updates the reports.
    /// A requested download is finished once the file has a local copy again.
    public func refresh(_ records: [CloudStorageFileRecord]) async -> CloudStorageActionResult {
        let snapshot = records
        let measured: [CloudStorageFileRecord] = await CloudStorageThreadRunner.run {
            snapshot.compactMap { record -> CloudStorageFileRecord? in
                guard var current = CloudStorageScanner.remeasure(record) else { return nil }
                current.lastUsed = record.lastUsed
                current.status = CloudStorageMetadata.status(at: record.path, keepingRequest: record.status)
                if !current.isCloudOnly { current.status.downloadRequested = false }
                return current
            }
        }
        let reports = apply(measured)
        let finished = measured.filter { !$0.isCloudOnly }
        let outcome = RunOutcome(module: .cloudStorage, processedCount: finished.count,
                                 removedItemIDs: finished.map(\.id),
                                 summary: "\(CountFormat.items(finished.count, singular: "file")) on this Mac")
        return CloudStorageActionResult(outcome: outcome, updatedRecords: measured, reports: reports)
    }

    /// Applies re-measured records to the stored reports and returns them.
    private func apply(_ updates: [CloudStorageFileRecord]) -> [CloudStorageProviderReport] {
        lock.lock()
        defer { lock.unlock() }
        guard !updates.isEmpty else { return storedReports }
        storedReports = storedReports.map { report in
            let mine = updates.filter { report.provider.contains($0.path) }
            return mine.isEmpty ? report : report.applying(mine, largeThreshold: largeFileThreshold)
        }
        return storedReports
    }

    // MARK: Quick Look

    /// Whether a listed item can be previewed without downloading anything: it still
    /// exists and every byte of it (every file inside a package) is on this Mac. Checked
    /// right before previewing, on a thread that can't download, because macOS may have
    /// removed the local copy since the scan and Quick Look would fetch it again.
    public func previewAvailability(of record: CloudStorageFileRecord,
                                    in provider: CloudStorageProvider) async -> CloudStorageAvailability {
        let path = record.path
        let mechanism = provider.mechanism
        return await CloudStorageThreadRunner.run { () -> CloudStorageAvailability in
            let availability = CloudStorageScanner.availability(at: path)
            guard availability == .local, mechanism != .syncFolder else { return availability }
            // The provider's own word wins when it says the copy isn't here.
            return CloudStorageMetadata.status(at: path).download == .notDownloaded ? .cloud : .local
        }
    }

    // MARK: Finder

    /// Selects the files in Finder (online-only files are shown, never downloaded).
    @MainActor
    public func reveal(_ paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Opens a provider's folder in Finder.
    @MainActor
    public func openInFinder(_ provider: CloudStorageProvider) {
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: provider.rootPath, isDirectory: true))
    }
}
