import Foundation
import Observation
import SpruceCore

// Detection sources of the malware scan beyond the built-in catalog, as the Protection
// screens and Settings use them: Apple's XProtect rules (offline), Spruce's threat list
// (downloaded at most once a day, can be turned off) and VirusTotal lookups (the user's own
// key, SHA-256 only, files are never uploaded). `detection` holds what the screens show.

extension ProtectionEngine {
    /// How long a scan waits for a due threat list check before it goes ahead with the
    /// cached copy (the download carries on in the background).
    static let threatListScanWait: TimeInterval = 2.5

    static let noFileReason = "This item has no single file to check, such as a folder or a scheduled job."
    static let unreadableFileReason = "Spruce couldn't read this file to fingerprint it. "
        + "Online-only files and files over 100 MB aren't checked."

    // MARK: Status

    /// Re-reads what the screens show about each source: Apple's XProtect rules (compiled
    /// again only when macOS changed them), the threat list and whether a VirusTotal key is
    /// saved. Cheap after the first call; call it when Protection or Settings appear.
    public func refreshDetectionStatus() async {
        let library = self.library
        let fallbackVersion = lastAppleStatus?.xprotectVersion
        let (apple, list) = await Task.detached(priority: .utility) { () -> (ProtectionAppleRulesStatus, ProtectionThreatListSnapshot) in
            var status = library.appleRules.load().status
            if status.version == nil { status.version = fallbackVersion }
            return (status, library.currentThreatList())
        }.value
        let enabled = library.isThreatListEnabled
        await MainActor.run { [detection] in
            detection.appleRules = apple
            Self.show(list, enabled: enabled, in: detection)
        }
        await publishVirusTotalState()
    }

    // MARK: Threat list

    /// Settings › Protection › Check Now: downloads the threat list now, whatever the date
    /// of the last check (only while Download threat list is on). Never throws; the result
    /// says what happened, and the cached copy stays in use when the download fails.
    public func checkThreatListNow() async -> ProtectionThreatFeedCheckResult {
        let settings = await ProtectionMac.settings()
        library.isThreatListEnabled = settings.threatFeedEnabled
        await MainActor.run { [detection] in detection.isCheckingThreatList = true }
        let result = await feedUpdater.check(force: true)
        await publishThreatList(result)
        return result
    }

    /// Checks the threat list before a scan when a check is due. The scan waits at most
    /// `threatListScanWait`: a slow download carries on in the background and this scan uses
    /// the cached copy (or the built-in catalog).
    func refreshThreatListIfDue() async {
        guard library.isThreatListEnabled, library.feedCache.loadStatus().isCheckDue() else { return }
        let engine = self
        let check = Task.detached(priority: .utility) { () -> ProtectionThreatFeedCheckResult in
            await MainActor.run { [detection = engine.detection] in detection.isCheckingThreatList = true }
            let result = await engine.feedUpdater.check(force: false)
            await engine.publishThreatList(result)
            return result
        }
        await Self.wait(for: check, upTo: Self.threatListScanWait)
    }

    func publishThreatList(_ result: ProtectionThreatFeedCheckResult) async {
        let list = library.currentThreatList()
        let enabled = library.isThreatListEnabled
        await MainActor.run { [detection] in
            detection.isCheckingThreatList = false
            detection.lastThreatListCheck = result
            Self.show(list, enabled: enabled, in: detection)
            detection.threatList = result.status
        }
    }

    /// Follows Settings › Protection › Download threat list (main thread, for the app's
    /// lifetime). Turning it off keeps the cached copy on disk but stops using it.
    func followDetectionSettings() {
        let enabled = withObservationTracking {
            SettingsStore.shared.settings.threatFeedEnabled
        } onChange: { [weak self] in
            guard let engine = self else { return }
            DispatchQueue.main.async { engine.followDetectionSettings() }
        }
        library.isThreatListEnabled = enabled
        guard detection.isThreatListEnabled != enabled else { return }
        detection.isThreatListEnabled = enabled
        let sources = library
        let screen = detection
        Task.detached(priority: .utility) {
            let list = sources.currentThreatList()
            let current = sources.isThreatListEnabled
            await MainActor.run { Self.show(list, enabled: current, in: screen) }
        }
    }

    /// Main thread.
    private static func show(_ list: ProtectionThreatListSnapshot, enabled: Bool, in detection: ProtectionDetectionState) {
        detection.isThreatListEnabled = enabled
        detection.threatList = list.status
        detection.threatListIndicatorsInUse = enabled ? list.indicatorCount : 0
        detection.threatListRulesInUse = enabled ? list.ruleSources.reduce(0) { $0 + $1.activeRuleCount } : 0
    }

    // MARK: VirusTotal key

    /// Checks `key` with VirusTotal (one lookup of the EICAR test file's hash; nothing about
    /// the Mac is sent) and saves it in the Keychain when VirusTotal accepts it. With
    /// `validate: false` it is saved unchecked (`.notChecked`, for saving while offline).
    /// The key is stored nowhere but the Keychain.
    public func saveVirusTotalKey(_ key: String, validate: Bool = true) async -> VirusTotalKeyCheck {
        guard let normalized = VirusTotalAPI.normalizedKey(key) else { return .malformed }
        let check: VirusTotalKeyCheck
        if validate {
            check = await virusTotal.validate(key: normalized)
        } else {
            check = .notChecked
        }
        guard check.isUsable else { return check }
        do {
            try await virusTotal.setKey(normalized)
        } catch {
            return .failed((error as? ProtectionVirusTotalKeychain.Failure)?.description
                ?? "Spruce couldn't save the key in your keychain.")
        }
        await MainActor.run { [detection] in
            detection.virusTotalNotice = nil
            detection.virusTotalProblems = [:]
        }
        await publishVirusTotalState()
        return check
    }

    /// Removes the key from the Keychain and stops automatic lookups. Answers already
    /// received stay on the results.
    public func removeVirusTotalKey() async {
        cancelAutomaticLookups()
        await virusTotal.removeKey()
        await MainActor.run { [detection] in
            detection.virusTotalPending = []
            detection.virusTotalNotice = nil
        }
        await publishVirusTotalState()
    }

    /// Checks a key with VirusTotal without saving it; nil checks the saved key.
    public func validateVirusTotalKey(_ key: String? = nil) async -> VirusTotalKeyCheck {
        if let key { return await virusTotal.validate(key: key) }
        return await virusTotal.validateSavedKey() ?? .failed(VirusTotalLookupOutcome.noKey.message ?? "No key is saved.")
    }

    /// Re-reads whether a key is saved and how many lookups are left today.
    func publishVirusTotalState() async {
        let hasKey = await virusTotal.keyExists()
        let left = await virusTotal.remainingToday()
        await MainActor.run { [detection] in
            detection.hasVirusTotalKey = hasKey
            detection.virusTotalLookupsLeftToday = left
            if !hasKey { detection.virusTotalNotice = nil }
        }
    }

    // MARK: VirusTotal lookups

    /// "Check with VirusTotal" for a malware row: fingerprints the program behind it on this
    /// Mac (SHA-256) and looks the hash up; the file itself never leaves the Mac. A fresh
    /// remembered answer is used unless `refresh`. Waits about a minute at most for a free
    /// lookup under the API limits. The answer is recorded on the engine's results, in
    /// `detection` and announced with `virusTotalNotification`.
    public func checkWithVirusTotal(_ item: ScanItem, refresh: Bool = false) async -> VirusTotalLookupOutcome {
        guard item.metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.malwareTool else { return .noFile(Self.noFileReason) }
        return await lookUp(itemID: item.id, sha256: item.protectionSHA256, program: item.protectionLookupPath,
                            priority: .manual, useCache: !refresh)
    }

    /// "Check with VirusTotal" for a finding.
    public func checkWithVirusTotal(_ finding: ProtectionThreatFinding, refresh: Bool = false) async -> VirusTotalLookupOutcome {
        await checkWithVirusTotal(finding.scanItem, refresh: refresh)
    }

    /// The answer Spruce already has for a malware row, without asking VirusTotal: recorded
    /// on the row, arrived since, or remembered for the row's file hash (a week; a day for
    /// files VirusTotal doesn't know). For a quick look from a view, read
    /// `detection.verdict(for:)` instead.
    public func cachedVirusTotalVerdict(for item: ScanItem) async -> VirusTotalVerdict? {
        let known = await MainActor.run { [detection] in detection.verdict(for: item) }
        if let known { return known }
        guard let hash = item.protectionSHA256, let remembered = await virusTotal.cachedVerdict(for: hash) else { return nil }
        await MainActor.run { [detection] in
            detection.virusTotalBySHA256[remembered.sha256] = remembered
        }
        return remembered
    }

    /// The row's page on virustotal.com ("Open in VirusTotal"). Fingerprints the file on this
    /// Mac when the row has no hash yet; nothing is sent until the user opens the link.
    public func virusTotalPage(for item: ScanItem) async -> URL? {
        if let hash = item.protectionSHA256 ?? item.virusTotalVerdict?.sha256 { return VirusTotalAPI.guiURL(sha256: hash) }
        guard let path = item.protectionLookupPath, let hash = await fingerprint(path) else { return nil }
        return VirusTotalAPI.guiURL(sha256: hash)
    }

    /// Looks up the report's heuristic and rule-based findings in the background, one at a
    /// time within the API limits, when a key is saved (`VirusTotalCandidates.automatic`:
    /// at most 40 a scan, files checked recently are skipped). The next scan cancels it.
    func startAutomaticLookups(for report: ProtectionMalwareReport) {
        let candidates = VirusTotalCandidates.automatic(report.findings)
        guard !candidates.isEmpty else { return }
        let engine = self
        let task = Task.detached(priority: .utility) {
            guard await engine.virusTotal.keyExists() else { return }
            let ids = candidates.map(\.id)
            await MainActor.run { [detection = engine.detection] in detection.virusTotalPending.formUnion(ids) }
            var done = 0
            for finding in candidates {
                if Task.isCancelled { break }
                let outcome = await engine.lookUp(itemID: finding.id, sha256: finding.sha256, program: finding.programPath,
                                                  priority: .automatic)
                done += 1
                if case .noKey = outcome { break }
                if case .invalidKey = outcome { break }
                if case .dailyLimitReached = outcome { break }
            }
            let waiting = Array(ids.dropFirst(done))
            if !waiting.isEmpty {
                await MainActor.run { [detection = engine.detection] in detection.virusTotalPending.subtract(waiting) }
            }
        }
        automaticLookups.update { current in
            current?.cancel()
            current = task
        }
    }

    func cancelAutomaticLookups() {
        automaticLookups.update { current in
            current?.cancel()
            current = nil
        }
    }

    /// Puts answers Spruce already has (fresh ones, by file hash) on a new report, so a
    /// rescan shows them at once without asking VirusTotal again.
    func withRememberedVirusTotalAnswers(_ report: ProtectionMalwareReport) async -> ProtectionMalwareReport {
        let hashes = Set(report.findings.compactMap { $0.sha256.flatMap(VirusTotalAPI.normalizedSHA256) })
        guard !hashes.isEmpty else { return report }
        let answers = await virusTotal.cachedVerdicts(for: Array(hashes))
        guard !answers.isEmpty else { return report }
        var copy = report
        for verdict in answers.values { copy.applyVirusTotal(verdict) }
        var byItem: [String: VirusTotalVerdict] = [:]
        for finding in copy.findings {
            if let verdict = finding.virusTotal { byItem[finding.id] = verdict }
        }
        let known = byItem
        await MainActor.run { [detection] in
            for (id, verdict) in known {
                detection.virusTotalByItemID[id] = verdict
                detection.virusTotalBySHA256[verdict.sha256] = verdict
            }
            detection.virusTotalRevision += 1
        }
        return copy
    }

    /// One row's lookup: the file hash (computed on this Mac when the scan didn't have one),
    /// then a remembered answer or VirusTotal, then the answer recorded everywhere.
    func lookUp(itemID: String, sha256: String?, program: String?, priority: ProtectionVirusTotalClient.Priority,
                useCache: Bool = true) async -> VirusTotalLookupOutcome {
        await MainActor.run { [detection] in _ = detection.virusTotalPending.insert(itemID) }
        var hash = sha256.flatMap(VirusTotalAPI.normalizedSHA256)
        if hash == nil, let program { hash = await fingerprint(program) }
        let outcome: VirusTotalLookupOutcome
        if let hash {
            outcome = await virusTotal.lookup(sha256: hash, priority: priority, useCache: useCache)
        } else {
            outcome = .noFile(program == nil ? Self.noFileReason : Self.unreadableFileReason)
        }
        await publish(outcome, itemID: itemID, stopped: Task.isCancelled)
        return outcome
    }

    /// SHA-256 of a regular, local file, computed on this Mac. Online-only files are never
    /// downloaded and files over `maxFingerprintBytes` are skipped.
    func fingerprint(_ path: String) async -> String? {
        let probe = self.probe
        let limit = Self.maxFingerprintBytes
        let hash = try? await ProtectionMac.runBlocking(qos: .utility) { _ -> String? in
            guard let entry = FileWalker.entry(at: path), entry.isRegularFile, entry.logicalSize > 0,
                  entry.logicalSize <= limit, !probe.isCloudOnly(entry) else { return nil }
            return probe.sha256(of: path)
        }
        return hash
    }

    /// Records an outcome: an answer goes on the engine's results (reports and Checkup rows of
    /// the same row or file), into `detection` and out as `virusTotalNotification`; a problem
    /// is kept for the row (not when the lookup was stopped by a new scan).
    private func publish(_ outcome: VirusTotalLookupOutcome, itemID: String, stopped: Bool) async {
        if let verdict = outcome.verdict {
            state.update { current in
                current.malwareReport?.applyVirusTotal(verdict, itemID: itemID)
                current.automaticReport?.applyVirusTotal(verdict, itemID: itemID)
                current.checkupReview.applyVirusTotal(verdict, itemID: itemID)
            }
        }
        let left = await virusTotal.remainingToday()
        let engine = self
        await MainActor.run { [detection] in
            detection.virusTotalPending.remove(itemID)
            detection.virusTotalLookupsLeftToday = left
            if let verdict = outcome.verdict {
                detection.virusTotalByItemID[itemID] = verdict
                detection.virusTotalBySHA256[verdict.sha256] = verdict
                detection.virusTotalProblems[itemID] = nil
                detection.virusTotalNotice = nil
                detection.virusTotalRevision += 1
                NotificationCenter.default.post(name: ProtectionEngine.virusTotalNotification, object: engine,
                                                userInfo: [ProtectionEngine.virusTotalItemKey: itemID,
                                                           ProtectionEngine.virusTotalVerdictKey: verdict])
            } else if !stopped, let message = outcome.message {
                detection.virusTotalProblems[itemID] = message
                switch outcome {
                case .noKey, .invalidKey, .dailyLimitReached:
                    detection.virusTotalNotice = message
                default:
                    break
                }
            }
        }
    }

    // MARK: Helpers

    /// Waits for `task` at most `seconds`; the task keeps running when time is up.
    static func wait<T: Sendable>(for task: Task<T, Never>, upTo seconds: TimeInterval) async {
        let gate = ProtectionLocked(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finish: @Sendable () -> Void = {
                var first = false
                gate.update { done in
                    if !done {
                        done = true
                        first = true
                    }
                }
                if first { continuation.resume() }
            }
            Task.detached {
                _ = await task.value
                finish()
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { finish() }
        }
    }
}
