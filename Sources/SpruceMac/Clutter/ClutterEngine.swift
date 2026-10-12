import Foundation
import SpruceCore

/// Large & old files, duplicates, similar images and downloads.
///
/// CONTRACT (used by AppModel and Checkup — keep these signatures):
/// * `public init()`
/// * `CheckupContributor` conformance (`checkupScan`, `checkupRun`)
/// * `GroupScanner` conformance (`scan`, `perform`) for the module's main review list
///
/// One walk of `settings.clutterLocations` (default `~`; external volumes allowed) feeds
/// every tool: `FileWalker` with `descendIntoPackages: false`, skipping `~/Library`,
/// hidden folders, media libraries and cloud placeholders. "Last opened" comes from
/// Spotlight's `kMDItemLastUsedDate` with the access time as fallback, similar images
/// are compared with 64-pixel ImageIO thumbnails, and everything leaves the disk through
/// `FileRemover.dispose` — always to the Trash, and never every copy of a duplicate set
/// unless the caller explicitly allows it.
public final class ClutterEngine: CheckupContributor, GroupScanner, @unchecked Sendable {
    public let module: ModuleID = .clutter

    private let lock = NSLock()
    private var reviewStorage: [ScanGroup] = []
    private var report: ClutterScanReport?
    private var checkupDuplicates: [ClutterDuplicateGroup] = []
    private var board = ClutterStageBoard()

    /// Files hashed or fingerprinted at the same time.
    private let concurrency = 4

    public init() {}

    // MARK: State

    public var checkupReview: [ScanGroup] {
        get { locked { reviewStorage } }
        set { locked { reviewStorage = newValue } }
    }

    /// The last module scan's results (nil before the first scan).
    public var lastReport: ClutterScanReport? {
        locked { report }
    }

    /// Stage checklist of the running (or last) scan.
    public var stageBoard: ClutterStageBoard {
        locked { board }
    }

    /// Forgets the module scan results (e.g. "New Scan").
    public func discardReport() {
        locked { report = nil }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: GroupScanner

    /// Scans every tool over the configured locations and returns one combined review
    /// list (each file once), filtered by the ignore list.
    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        let report = try await scanAll(progress: progress)
        let settings = await currentSettings()
        let scanSettings = ClutterScanSettings(settings)
        return settings.filteringIgnored(ClutterItems.reviewGroups(for: report, settings: scanSettings))
    }

    /// Removes the items (to the Trash), keeping at least one copy of every duplicate set
    /// or similar cluster.
    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        await remove(items, allowRemovingAllCopies: false, progress: progress)
    }

    // MARK: Per-tool scans

    /// Large & Old Files over `locations` (default: Settings › Clutter locations).
    public func scanLargeOld(locations: [String]? = nil,
                             progress: @escaping ProgressHandler) async throws -> [ClutterLargeOldItem] {
        try await scanAll(locations: locations, tools: [.largeOld], progress: progress).largeOld
    }

    /// Duplicate files over `locations`.
    public func scanDuplicates(locations: [String]? = nil,
                               progress: @escaping ProgressHandler) async throws -> [ClutterDuplicateGroup] {
        try await scanAll(locations: locations, tools: [.duplicates], progress: progress).duplicates
    }

    /// Similar images over `locations` (Photos libraries are never looked into).
    public func scanSimilarImages(locations: [String]? = nil,
                                  progress: @escaping ProgressHandler) async throws -> [ClutterSimilarCluster] {
        try await scanAll(locations: locations, tools: [.similarImages], progress: progress).similar
    }

    /// The contents of `~/Downloads`, categorized.
    public func scanDownloads(progress: @escaping ProgressHandler) async throws -> [ClutterDownloadItem] {
        try await scanAll(locations: [], tools: [.downloads], progress: progress).downloads
    }

    /// Runs the requested tools with a single walk and remembers the report.
    public func scanAll(locations: [String]? = nil, tools: Set<ClutterTool> = Set(ClutterTool.allCases),
                        progress: @escaping ProgressHandler) async throws -> ClutterScanReport {
        let settings = await currentSettings()
        let chosen = (locations ?? settings.clutterLocations).filter { ClutterLocations.exists($0) }
        var stages: [ClutterScanStage] = []
        let walking = tools.contains(.largeOld) || tools.contains(.duplicates) || tools.contains(.similarImages)
        if walking { stages.append(.indexing) }
        for tool in ClutterTool.allCases where tools.contains(tool) {
            stages.append(ClutterScanStage(rawValue: tool.rawValue) ?? .indexing)
        }
        let board = ClutterStageBoard(stages: stages)
        locked { self.board = board }
        if walking && chosen.isEmpty && !tools.contains(.downloads) {
            throw SpruceError.notFound("None of the chosen locations is available. Choose another location.")
        }

        let flag = ClutterCancelFlag()
        let builder = ClutterReportBuilder(settings: settings, tools: tools, locations: chosen, board: board,
                                           concurrency: concurrency, progress: progress,
                                           shouldContinue: { !flag.isCancelled && !Task.isCancelled })
        let result = await withTaskCancellationHandler {
            await ClutterBackground.run { builder.build() }
        } onCancel: {
            flag.cancel()
        }
        if flag.isCancelled || Task.isCancelled { throw SpruceError.cancelled }
        locked { report = result }
        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: result.distinctBytes))
        return result
    }

    // MARK: Removal

    /// Moves the items to the Trash through `FileRemover`.
    ///
    /// - Parameter allowRemovingAllCopies: when false, one member of every duplicate set
    ///   or similar cluster always survives (the smart-selection keeper is held back).
    public func remove(_ items: [ScanItem], allowRemovingAllCopies: Bool,
                       progress: @escaping ProgressHandler) async -> RunOutcome {
        let settings = await currentSettings()
        let (sets, keepers, sizes) = locked { () -> ([String: [String]], [String: String], [String: Int64]) in
            var sets = report?.setMembers ?? [:]
            var keepers = report?.preferredKeepers ?? [:]
            var sizes: [String: Int64] = [:]
            for (path, file) in report?.filesByPath ?? [:] { sizes[path] = file.logicalSize }
            for group in checkupDuplicates {
                sets[group.id] = group.files.map(\.path)
                keepers[group.id] = group.keeperPath
                for file in group.files { sizes[file.path] = file.logicalSize }
            }
            return (sets, keepers, sizes)
        }
        // Trash only: Clutter lists personal files, never regenerable junk.
        let trashable = items.map { item -> ScanItem in
            var copy = item
            copy.deletion = .trash
            return copy
        }
        let plan = ClutterRemovalPlanner.plan(trashable, sets: sets, preferredKeepers: keepers,
                                              allowRemovingAllCopies: allowRemovingAllCopies) { path in
            guard let entry = FileWalker.entry(at: path) else { return false }
            if let size = sizes[path], !entry.isDirectory { return entry.logicalSize == size }
            return true
        }
        var outcome = await FileRemover.shared.dispose(plan.items, module: module, settings: settings,
                                                       progress: progress)
        outcome.failures.append(contentsOf: plan.heldBack)
        let removed = Set(outcome.removedItemIDs)
        outcome.summary = Self.summary(removedCount: removed.count, freed: outcome.freedBytes,
                                       failures: outcome.failures.count)
        locked {
            report?.remove(paths: removed)
            reviewStorage.removeItems(withIDs: removed)
            checkupDuplicates = checkupDuplicates.compactMap { group in
                let remaining = group.files.filter { !removed.contains($0.path) }
                guard remaining.count > 1 else { return nil }
                return ClutterSmartSelection().makeGroup(hash: group.hash, files: remaining)
            }
        }
        return outcome
    }

    static func summary(removedCount: Int, freed: Int64, failures: Int) -> String {
        if removedCount == 0 {
            return failures > 0 ? "Nothing was moved to the Trash" : "Nothing was removed"
        }
        var text = "Moved \(CountFormat.items(removedCount)) to the Trash · \(ByteFormat.string(freed))"
        if failures > 0 { text += " · \(CountFormat.items(failures)) skipped" }
        return text
    }

    // MARK: CheckupContributor

    /// Duplicate files in `~/Downloads` (redundant copies pre-selected) and installers
    /// downloaded over a month ago (review only).
    public func checkupScan(progress: @escaping ProgressHandler) async throws -> CheckupTile {
        let settings = await currentSettings()
        let paths = ClutterPaths()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: paths.downloads, isDirectory: &isDirectory), isDirectory.boolValue else {
            locked {
                reviewStorage = []
                checkupDuplicates = []
            }
            return CheckupTile(module: module, headline: "No clutter", detail: "There's no Downloads folder to check.",
                               status: .clear)
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: paths.downloads)
        } catch {
            locked {
                reviewStorage = []
                checkupDuplicates = []
            }
            return CheckupTile.unavailable(module, reason: "Allow Spruce to access your Downloads folder to check it.")
        }

        let flag = ClutterCancelFlag()
        let scanSettings = ClutterScanSettings(settings)
        let concurrency = self.concurrency
        let shouldContinue: @Sendable () -> Bool = { !flag.isCancelled && !Task.isCancelled }
        let result = await withTaskCancellationHandler {
            await ClutterBackground.run { () -> (groups: [ClutterDuplicateGroup], downloads: [ClutterDownloadItem]) in
                progress(ScanProgress(fraction: nil, message: "Looking for duplicate downloads…"))
                let walker = ClutterWalker(paths: paths, settings: scanSettings, isPlaceholder: { ClutterFileMetadata.isPlaceholder($0) })
                let walked = walker.walk(locations: [paths.downloads], shouldContinue: shouldContinue)
                let files = walked.files.filter { !settings.isIgnored(path: $0.path) && !settings.ignoredItemIDs.contains($0.path) }
                let finder = ClutterDuplicateFinder(paths: paths, concurrency: concurrency)
                let found = finder.findDuplicates(in: files, minimumSize: 1, progress: { fraction, current in
                    progress(ScanProgress(fraction: fraction * 0.8, message: "Comparing downloads…",
                                          current: current.abbreviatingHome))
                }, shouldContinue: shouldContinue)
                let selection = ClutterSmartSelection(paths: paths)
                let groups = found.map { group in
                    selection.makeGroup(hash: group.hash, files: group.files.map(ClutterFileMetadata.enriched))
                }
                progress(ScanProgress(fraction: 0.9, message: "Checking installers…"))
                let top = walker.listDownloads(shouldContinue: shouldContinue)
                    .filter { !settings.isIgnored(path: $0.path) && !settings.ignoredItemIDs.contains($0.path) }
                var metadata: [String: ClutterDownloadMetadata] = [:]
                for file in top where ClutterDownloadsAnalyzer.category(for: file) == .installers {
                    metadata[file.path] = ClutterFileMetadata.downloadMetadata(file.path)
                }
                let downloads = ClutterDownloadsAnalyzer.items(from: top.map(ClutterFileMetadata.enriched),
                                                               metadata: metadata,
                                                               installedAppNames: ClutterFileMetadata.installedAppNames())
                return (groups, downloads)
            }
        } onCancel: {
            flag.cancel()
        }
        if flag.isCancelled || Task.isCancelled { throw SpruceError.cancelled }

        let review = settings.filteringIgnored(
            ClutterCheckupPlanner.review(duplicates: result.groups, downloads: result.downloads, paths: paths,
                                         settings: scanSettings))
        locked {
            reviewStorage = review
            checkupDuplicates = result.groups
        }
        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: review.selectedSize))
        return ClutterCheckupPlanner.tile(for: review)
    }

    /// Moves the selected items of the Checkup review to the Trash.
    public func checkupRun(progress: @escaping ProgressHandler) async throws -> RunOutcome {
        let selected = checkupReview.selectedItems
        guard !selected.isEmpty else {
            return RunOutcome(module: module, summary: "Nothing selected")
        }
        return await remove(selected, allowRemovingAllCopies: false, progress: progress)
    }

    // MARK: Helpers

    private func currentSettings() async -> SpruceSettings {
        await MainActor.run { SettingsStore.shared.settings }
    }
}

// MARK: - Report builder

/// The blocking part of a scan: walk, enrich, run each tool. Runs on a Dispatch queue.
struct ClutterReportBuilder {
    var settings: SpruceSettings
    var tools: Set<ClutterTool>
    var locations: [String]
    var board: ClutterStageBoard
    var concurrency: Int
    var progress: ProgressHandler
    var shouldContinue: @Sendable () -> Bool

    private var paths: ClutterPaths { ClutterPaths() }

    func build() -> ClutterScanReport {
        let scanSettings = ClutterScanSettings(settings)
        let throttle = ClutterProgressThrottle()
        // Running total of distinct bytes found (read from progress callbacks on other threads).
        let found = ClutterAtomicCounter()
        var counted = Set<String>()
        func tally(_ files: [ClutterFile]) {
            for file in files where counted.insert(file.path).inserted { found.add(file.size) }
        }
        func emit(_ message: String, current: String? = nil, force: Bool = false) {
            guard throttle.shouldEmit(force: force) else { return }
            progress(ScanProgress(fraction: board.fraction, message: message, current: current?.abbreviatingHome,
                                  bytesFound: found.current))
        }

        var report = ClutterScanReport(locations: locations, scannedTools: tools)
        var files: [ClutterFile] = []

        // 1. Walk.
        if board.stages.contains(.indexing) {
            board.set(.indexing, .running(nil))
            emit("Finding files…", force: true)
            let walker = ClutterWalker(paths: paths, settings: scanSettings, isPlaceholder: { ClutterFileMetadata.isPlaceholder($0) })
            let walked = walker.walk(locations: locations, shouldContinue: shouldContinue) { examined, current in
                let message = "Looked at \(CountFormat.items(examined, singular: "file"))…"
                if throttle.shouldEmit() {
                    progress(ScanProgress(fraction: board.fraction, message: message, current: current.abbreviatingHome,
                                          bytesFound: found.current))
                }
            }
            files = walked.files.filter { !isIgnored($0.path) }
            report.filesExamined = walked.examined
            report.skippedPlaceholders = walked.skippedPlaceholders
            report.wasStopped = walked.stopped
            board.set(.indexing, .done(CountFormat.items(walked.examined, singular: "file")))
            guard shouldContinue() else { return report }
        }

        // 2. Large & Old Files.
        if tools.contains(.largeOld) {
            board.set(.largeOld, .running(nil))
            emit("Checking when files were last opened…", force: true)
            let floor = min(scanSettings.largeFileThreshold, scanSettings.oldMinimumSize)
            var candidates: [ClutterFile] = []
            for (index, file) in files.enumerated() where file.size >= floor {
                if index % 64 == 0 && !shouldContinue() { return report }
                candidates.append(ClutterFileMetadata.enriched(file))
            }
            report.largeOld = ClutterLargeOldFilter.items(from: candidates, settings: scanSettings)
            tally(report.largeOld.map(\.file))
            board.set(.largeOld, .done(ByteFormat.string(report.largeOld.reduce(0) { $0 + $1.file.size })))
            emit("Found large and old files", force: true)
            guard shouldContinue() else { return report }
        }

        // 3. Duplicates.
        if tools.contains(.duplicates) {
            board.set(.duplicates, .running(0))
            emit("Comparing files…", force: true)
            let finder = ClutterDuplicateFinder(paths: paths, concurrency: concurrency)
            let groups = finder.findDuplicates(in: files, minimumSize: scanSettings.duplicateMinimumSize,
                                               progress: { fraction, current in
                board.set(.duplicates, .running(fraction))
                if throttle.shouldEmit() {
                    progress(ScanProgress(fraction: board.fraction, message: "Comparing files…",
                                          current: current.abbreviatingHome, bytesFound: found.current))
                }
            }, shouldContinue: shouldContinue)
            guard shouldContinue() else { return report }
            let selection = ClutterSmartSelection(paths: paths)
            report.duplicates = groups.map { group in
                selection.makeGroup(hash: group.hash, files: group.files.map(ClutterFileMetadata.enriched))
            }
            .sorted { $0.reclaimableBytes != $1.reclaimableBytes ? $0.reclaimableBytes > $1.reclaimableBytes : $0.hash < $1.hash }
            tally(report.duplicates.flatMap(\.copies))
            let copies = report.duplicates.reduce(0) { $0 + $1.copies.count }
            board.set(.duplicates, .done(copies == 0 ? "None" : CountFormat.items(copies, singular: "copy", plural: "copies")))
            emit("Found duplicates", force: true)
        }

        // 4. Similar images.
        if tools.contains(.similarImages) {
            board.set(.similarImages, .running(0))
            emit("Comparing pictures…", force: true)
            // Exact copies are already in Duplicates: compare only one file per set.
            let redundant = Set(report.duplicates.flatMap { $0.copies.map(\.path) })
            let images = files.filter {
                ClutterKindClassifier.isSimilarImageCandidate($0.path) && !$0.isPackage
                    && $0.logicalSize >= scanSettings.similarImageMinimumSize && !redundant.contains($0.path)
            }
            let total = Double(max(images.count, 1))
            let done = ClutterAtomicCounter()
            let prints = ClutterParallel.map(images, concurrency: concurrency, shouldContinue: shouldContinue) { _, file in
                let value = ClutterThumbnailFingerprinter.fingerprint(path: file.path)
                let finished = done.add(1)
                if finished % 8 == 0 {
                    board.set(.similarImages, .running(Double(finished) / total * 0.9))
                    if throttle.shouldEmit() {
                        progress(ScanProgress(fraction: board.fraction, message: "Comparing pictures…",
                                              current: file.path.abbreviatingHome, bytesFound: found.current))
                    }
                }
                return value
            }
            guard shouldContinue() else { return report }
            let clusters = ClutterSimilarClusterer().clusters(files: images, prints: prints.compactMap { $0 },
                                                              shouldContinue: shouldContinue)
            report.similar = clusters.map { cluster in
                var copy = cluster
                copy.files = cluster.files.map(ClutterFileMetadata.enriched)
                return copy
            }
            tally(report.similar.flatMap(\.others))
            let imageCount = report.similar.reduce(0) { $0 + $1.files.count }
            board.set(.similarImages, .done(imageCount == 0 ? "None" : CountFormat.items(imageCount, singular: "image")))
            emit("Found similar images", force: true)
            guard shouldContinue() else { return report }
        }

        // 5. Downloads.
        if tools.contains(.downloads) {
            board.set(.downloads, .running(nil))
            emit("Sorting your downloads…", force: true)
            let walker = ClutterWalker(paths: paths, settings: scanSettings, isPlaceholder: { ClutterFileMetadata.isPlaceholder($0) })
            let top = walker.listDownloads(shouldContinue: shouldContinue).filter { !isIgnored($0.path) }
            var metadata: [String: ClutterDownloadMetadata] = [:]
            var enriched: [ClutterFile] = []
            for file in top {
                guard shouldContinue() else { return report }
                metadata[file.path] = ClutterFileMetadata.downloadMetadata(file.path)
                enriched.append(ClutterFileMetadata.enriched(file))
            }
            report.downloads = ClutterDownloadsAnalyzer.items(from: enriched, metadata: metadata,
                                                              installedAppNames: ClutterFileMetadata.installedAppNames())
            tally(report.downloads.map(\.file))
            board.set(.downloads, .done(ByteFormat.string(report.downloads.reduce(0) { $0 + $1.file.size })))
        }
        emit("Done", force: true)
        return report
    }

    private func isIgnored(_ path: String) -> Bool {
        settings.ignoredItemIDs.contains(path) || settings.isIgnored(path: path)
    }
}
