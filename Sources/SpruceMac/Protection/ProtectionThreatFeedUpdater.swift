import Foundation
import SpruceCore

/// Downloads Spruce's threat list: feed.json and rules.yara from the project's public GitHub
/// repository (`ProtectionThreatFeed.feedURL` / `rulesURL`).
///
/// * HTTPS only (the final address after redirects too), 20-second timeout, at most
///   `ProtectionThreatFeed.maxFeedBytes` / `maxRulesBytes` per file (the download stops as
///   soon as it grows past that).
/// * Conditional requests (`If-None-Match` with the cached files' ETags), no cookies, no
///   URL cache and a generic User-Agent: nothing about the Mac or its files is sent.
/// * At most one check a day (`ProtectionThreatFeedStatus.isCheckDue`) unless the user
///   presses Check Now; only while Settings › Protection › Download threat list is on.
/// * Never throws into a scan: problems end up in the result and the stored status, and the
///   cached copy (or the built-in catalog) stays in use. Concurrent checks share one run.
actor ProtectionThreatFeedUpdater {
    static let timeout: TimeInterval = 20

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Spruce/1.0 (Macintosh; threat list)"]
        return URLSession(configuration: configuration)
    }()

    static let unreachable = "Spruce couldn't reach the threat list. It keeps using the copy it has and tries again later."

    private let library: ProtectionDetectionLibrary
    private var running: Task<ProtectionThreatFeedCheckResult, Never>?

    init(library: ProtectionDetectionLibrary) {
        self.library = library
    }

    /// Checks the list when a check is due (always when `force`), stores what changed and
    /// hands the new copy to the library.
    func check(force: Bool) async -> ProtectionThreatFeedCheckResult {
        if let running { return await running.value }
        let library = self.library
        let status = library.feedCache.loadStatus()
        guard library.isThreatListEnabled else { return ProtectionThreatFeedCheckResult(outcome: .turnedOff, status: status) }
        guard force || status.isCheckDue() else { return ProtectionThreatFeedCheckResult(outcome: .notDue, status: status) }
        let task = Task.detached(priority: .utility) { await Self.run(library: library) }
        running = task
        let result = await task.value
        running = nil
        return result
    }

    private static func run(library: ProtectionDetectionLibrary) async -> ProtectionThreatFeedCheckResult {
        let cache = library.feedCache
        let etags = cache.conditionalETags(for: cache.loadStatus())
        async let feed = download(ProtectionThreatFeed.feedURL, etag: etags.feed, maxBytes: ProtectionThreatFeed.maxFeedBytes)
        async let rules = download(ProtectionThreatFeed.rulesURL, etag: etags.rules, maxBytes: ProtectionThreatFeed.maxRulesBytes)
        let feedDownload = await feed
        let rulesDownload = await rules
        let applied = cache.apply(feed: feedDownload, rules: rulesDownload)
        library.replaceThreatList(applied.snapshot)
        return applied.result
    }

    /// One file. 200 → its bytes and ETag, 304 → not modified, anything else → a plain
    /// message for the status.
    static func download(_ url: URL, etag: String?, maxBytes: Int) async -> ProtectionDownload {
        guard ProtectionThreatFeed.isAllowedDownloadURL(url) else { return .failed(unreachable) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        if let etag, !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                bytes.task.cancel()
                return .failed(unreachable)
            }
            // Redirects are followed by URLSession; only an HTTPS answer is read.
            if let final = http.url, !ProtectionThreatFeed.isAllowedDownloadURL(final) {
                bytes.task.cancel()
                return .failed(unreachable)
            }
            switch http.statusCode {
            case 304:
                bytes.task.cancel()
                return .notModified
            case 200:
                let expected = http.expectedContentLength
                if expected > Int64(maxBytes) {
                    bytes.task.cancel()
                    return .failed(ProtectionThreatFeedError.tooLarge(bytes: Int(clamping: expected), limit: maxBytes).description)
                }
                var data = Data()
                if expected > 0 { data.reserveCapacity(Int(expected)) }
                for try await byte in bytes {
                    data.append(byte)
                    if data.count > maxBytes {
                        bytes.task.cancel()
                        return .failed(ProtectionThreatFeedError.tooLarge(bytes: data.count, limit: maxBytes).description)
                    }
                }
                return .downloaded(data, etag: http.value(forHTTPHeaderField: "ETag"))
            default:
                bytes.task.cancel()
                return .failed("The threat list server answered with an error (HTTP \(http.statusCode)). "
                    + "Spruce keeps using the copy it has.")
            }
        } catch {
            return .failed(unreachable)
        }
    }
}
