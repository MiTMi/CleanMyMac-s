import Foundation
import SpruceCore

/// VirusTotal file lookups with the user's own API key (API v3, `GET /api/v3/files/{sha256}`).
///
/// * Only a file's SHA-256 is sent, in the address; files are never uploaded. The key goes in
///   the `x-apikey` header and lives in the Keychain (`ProtectionVirusTotalKeychain`); it is
///   kept in memory once read and never logged.
/// * The public API's limits (4 lookups a minute, 500 a day) are enforced before asking. The
///   lookups are counted in user defaults (`VirusTotalQuota`), so the count survives relaunches;
///   a 429 answer pauses lookups (1 minute, doubling up to an hour).
/// * Manual lookups go before automatic ones. Automatic lookups wait for a free slot as long
///   as their task isn't cancelled; manual ones wait about a minute at most.
/// * Answers are remembered per hash (`VirusTotalVerdictCache`, a week, or a day for files
///   VirusTotal doesn't know) in Application Support, so a file isn't looked up twice.
actor ProtectionVirusTotalClient {
    enum Priority: Sendable {
        /// After a scan.
        case automatic
        /// "Check with VirusTotal".
        case manual
    }

    static let timeout: TimeInterval = 20
    /// A manual lookup waits at most this long for a free slot.
    static let manualWait: TimeInterval = 65
    static let quotaDefaultsKey = "app.spruce.virustotal.quota"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Spruce/1.0 (Macintosh)", "Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    static var defaultCacheURL: URL {
        SprucePaths.applicationSupport.appendingPathComponent("VirusTotal", isDirectory: true)
            .appendingPathComponent("verdicts.json")
    }

    static let unreachable = "Spruce couldn't reach VirusTotal. Check your internet connection and try again."

    private let limit = VirusTotalRateLimit.publicAPI
    private let cacheStore: JSONFileStore<VirusTotalVerdictCache>
    private var cache: VirusTotalVerdictCache
    private var quota: VirusTotalQuota
    /// The key once read from the Keychain (`keyLoaded`); nil when none is saved.
    private var key: String?
    private var keyLoaded = false
    /// Manual lookups waiting for a slot (automatic ones let them go first).
    private var manualWaiting = 0

    init(cacheURL: URL = ProtectionVirusTotalClient.defaultCacheURL) {
        let store = JSONFileStore<VirusTotalVerdictCache>(url: cacheURL, prettyPrinted: false)
        var loaded = store.load() ?? VirusTotalVerdictCache()
        loaded.prune()
        cacheStore = store
        cache = loaded
        quota = Self.loadQuota()
    }

    // MARK: Key

    /// True when a key is saved (doesn't read the key itself).
    func keyExists() -> Bool {
        if keyLoaded { return key != nil }
        return ProtectionVirusTotalKeychain.exists()
    }

    /// Saves a key in the Keychain. A different key starts a fresh lookup count.
    func setKey(_ newKey: String) throws {
        try ProtectionVirusTotalKeychain.save(newKey)
        if currentKey() != newKey {
            quota = VirusTotalQuota()
            saveQuota()
        }
        key = newKey
        keyLoaded = true
    }

    /// Removes the key from the Keychain (remembered answers stay; they hold no secret).
    func removeKey() {
        ProtectionVirusTotalKeychain.delete()
        key = nil
        keyLoaded = true
    }

    private func currentKey() -> String? {
        if !keyLoaded {
            key = ProtectionVirusTotalKeychain.load()
            keyLoaded = true
        }
        return key
    }

    // MARK: Answers and limits

    /// A remembered answer for `sha256` that is still fresh.
    func cachedVerdict(for sha256: String) -> VirusTotalVerdict? {
        cache.fresh(for: sha256)
    }

    /// Fresh remembered answers for several hashes, by hash.
    func cachedVerdicts(for hashes: [String]) -> [String: VirusTotalVerdict] {
        var found: [String: VirusTotalVerdict] = [:]
        for hash in hashes {
            if let verdict = cache.fresh(for: hash) { found[verdict.sha256] = verdict }
        }
        return found
    }

    /// Lookups left today under the public API's limit.
    func remainingToday() -> Int {
        quota.remainingToday(limit)
    }

    /// When the next lookup may go (nil: now).
    func nextAllowed() -> Date? {
        quota.decision(limit).nextAttempt
    }

    // MARK: Lookups

    /// Looks up one SHA-256: a remembered answer when there is a fresh one (unless
    /// `useCache` is false), otherwise VirusTotal once a slot under the limits is free.
    func lookup(sha256: String, priority: Priority, useCache: Bool = true) async -> VirusTotalLookupOutcome {
        guard let hash = VirusTotalAPI.normalizedSHA256(sha256) else {
            return .noFile("Spruce couldn't fingerprint this file.")
        }
        if useCache, let fresh = cache.fresh(for: hash) { return .verdict(fresh) }
        if priority == .manual { manualWaiting += 1 }
        let outcome = await perform(hash: hash, priority: priority, useCache: useCache, started: Date())
        if priority == .manual { manualWaiting -= 1 }
        return outcome
    }

    private func perform(hash: String, priority: Priority, useCache: Bool, started: Date) async -> VirusTotalLookupOutcome {
        while true {
            if Task.isCancelled { return .failed("The lookup was stopped.") }
            // Another lookup may have answered for the same file while this one waited (a
            // forced lookup only takes an answer that arrived after it started).
            if let fresh = cache.fresh(for: hash), useCache || fresh.checked >= started { return .verdict(fresh) }
            guard let key = currentKey() else { return .noKey }
            let now = Date()
            switch quota.decision(limit, now: now) {
            case .dailyLimitReached(let until):
                return .dailyLimitReached(until: until)
            case .wait(let until):
                if priority == .manual, until.timeIntervalSince(started) > Self.manualWait {
                    return .rateLimited(until: until)
                }
                await Self.sleep(until: until)
                continue
            case .allowed:
                if priority == .automatic, manualWaiting > 0 {
                    await Self.sleep(seconds: 0.5)
                    continue
                }
            }

            quota.record(limit, now: now)
            saveQuota()
            let result = await Self.request(sha256: hash, key: key)
            switch result {
            case .found, .notFound:
                quota.recordAnswer()
                saveQuota()
                let outcome = VirusTotalLookupOutcome(result, sha256: hash)
                if let verdict = outcome.verdict {
                    cache.store(verdict)
                    try? cacheStore.save(cache)
                }
                return outcome
            case .rateLimited:
                quota.pause()
                saveQuota()
                if priority == .manual { return .rateLimited(until: quota.blockedUntil) }
                continue
            case .invalidKey:
                return .invalidKey
            case .failed(let message):
                return .failed(message)
            }
        }
    }

    /// Checks a key with one lookup of the EICAR test file's hash: 200 or 404 means
    /// VirusTotal accepted the key, 401/403 that it didn't. A key other than the saved one
    /// has its own limits, so only the saved key waits for a slot.
    func validate(key candidate: String) async -> VirusTotalKeyCheck {
        guard let candidateKey = VirusTotalAPI.normalizedKey(candidate) else { return .malformed }
        let isSaved = currentKey() == candidateKey
        if isSaved {
            let started = Date()
            waiting: while true {
                if Task.isCancelled { return .failed("The check was stopped.") }
                switch quota.decision(limit) {
                case .allowed:
                    break waiting
                case .dailyLimitReached:
                    return .quotaReached
                case .wait(let until):
                    if until.timeIntervalSince(started) > Self.manualWait { return .quotaReached }
                    await Self.sleep(until: until)
                }
            }
            quota.record(limit)
            saveQuota()
        }
        let result = await Self.request(sha256: VirusTotalCandidates.keyCheckSHA256, key: candidateKey)
        switch result {
        case .found, .notFound:
            if isSaved {
                quota.recordAnswer()
                saveQuota()
            }
            return .valid
        case .invalidKey:
            return .invalid
        case .rateLimited:
            if isSaved {
                quota.pause()
                saveQuota()
            }
            return .quotaReached
        case .failed(let message):
            return .failed(message)
        }
    }

    /// Checks the saved key; nil when no key is saved.
    func validateSavedKey() async -> VirusTotalKeyCheck? {
        guard let saved = currentKey() else { return nil }
        return await validate(key: saved)
    }

    // MARK: Network

    /// One `GET /files/{sha256}`. The only data sent are the hash (in the address) and the key.
    static func request(sha256: String, key: String) async -> VirusTotalLookupResult {
        guard let url = VirusTotalAPI.fileReportURL(sha256: sha256) else { return .failed("Spruce couldn't fingerprint this file.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: VirusTotalAPI.keyHeader)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed(unreachable) }
            guard data.count <= VirusTotalAPI.maxResponseBytes else {
                return .failed("VirusTotal sent an answer Spruce couldn't read.")
            }
            return VirusTotalAPI.parse(statusCode: http.statusCode, body: data, sha256: sha256)
        } catch {
            return .failed(unreachable)
        }
    }

    // MARK: Private

    private static func sleep(until date: Date) async {
        await sleep(seconds: date.timeIntervalSinceNow)
    }

    private static func sleep(seconds: TimeInterval) async {
        let clamped = min(max(seconds, 0.25), 3_600)
        try? await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
    }

    private static func loadQuota() -> VirusTotalQuota {
        guard let data = UserDefaults.standard.data(forKey: quotaDefaultsKey),
              let quota = try? JSONDecoder().decode(VirusTotalQuota.self, from: data) else { return VirusTotalQuota() }
        return quota
    }

    private func saveQuota() {
        guard let data = try? JSONEncoder().encode(quota) else { return }
        UserDefaults.standard.set(data, forKey: Self.quotaDefaultsKey)
    }
}
