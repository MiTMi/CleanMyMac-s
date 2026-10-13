import Foundation

// VirusTotal hash lookups (API v3), the pure part: URLs, response parsing, verdicts and the
// public-API rate limit. The macOS layer does the request with the user's own API key
// (kept in the Keychain) and only ever sends a file's SHA-256 — files are never uploaded.

/// Addresses and limits of the VirusTotal API.
public enum VirusTotalAPI {
    /// Header that carries the user's API key.
    public static let keyHeader = "x-apikey"
    /// Answers bigger than this are not read (a file report is a few hundred KB at most).
    public static let maxResponseBytes = 4 << 20

    /// `GET` address of the file report for a SHA-256, nil for anything that isn't one.
    public static func fileReportURL(sha256: String) -> URL? {
        guard let hash = normalizedSHA256(sha256) else { return nil }
        return URL(string: "https://www.virustotal.com/api/v3/files/\(hash)")
    }

    /// The file's page on virustotal.com ("Open in VirusTotal").
    public static func guiURL(sha256: String) -> URL? {
        guard let hash = normalizedSHA256(sha256) else { return nil }
        return URL(string: "https://www.virustotal.com/gui/file/\(hash)")
    }

    /// Lowercase hex of a well-formed SHA-256, nil otherwise.
    public static func normalizedSHA256(_ text: String) -> String? {
        let hash = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hash.utf8.count == 64, hash.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }) else {
            return nil
        }
        return hash
    }

    /// The key as typed, trimmed, or nil when it can't be an API key (VirusTotal keys are 64
    /// hex characters; anything with spaces or control characters is refused).
    public static func normalizedKey(_ text: String) -> String? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...128).contains(key.utf8.count),
              key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else { return nil }
        return key
    }

    /// Reads the answer to a file report request.
    public static func parse(statusCode: Int, body: Data, sha256: String) -> VirusTotalLookupResult {
        switch statusCode {
        case 200:
            guard body.count <= maxResponseBytes,
                  let envelope = try? JSONDecoder().decode(VirusTotalEnvelope.self, from: body),
                  let data = envelope.data else {
                return .failed("VirusTotal sent an answer Spruce couldn't read.")
            }
            let attributes = data.attributes
            let hash = normalizedSHA256(sha256) ?? sha256.lowercased()
            if let reported = attributes?.sha256 ?? data.id, normalizedSHA256(reported) != nil,
               normalizedSHA256(reported) != hash {
                return .failed("VirusTotal answered about a different file.")
            }
            let stats = attributes?.lastAnalysisStats ?? VirusTotalAnalysisStats()
            let report = VirusTotalFileReport(
                sha256: hash,
                stats: stats,
                threatLabel: attributes?.popularThreatClassification?.suggestedThreatLabel.flatMap(nonEmpty),
                meaningfulName: attributes?.meaningfulName.flatMap(nonEmpty),
                lastAnalysisDate: attributes?.lastAnalysisDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                typeDescription: attributes?.typeDescription.flatMap(nonEmpty),
                reputation: attributes?.reputation)
            return .found(report)
        case 404:
            return .notFound
        case 401, 403:
            return .invalidKey
        case 429:
            return .rateLimited
        case 400:
            return .failed("VirusTotal didn't accept the request.")
        case 500...599:
            return .failed("VirusTotal isn't answering right now. Try again later.")
        default:
            let code = (try? JSONDecoder().decode(VirusTotalErrorEnvelope.self, from: body))?.error?.code
            return .failed("VirusTotal answered with an error (\(code ?? "HTTP \(statusCode)")).")
        }
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Engine counts from `last_analysis_stats`.
public struct VirusTotalAnalysisStats: Codable, Sendable, Hashable {
    public var malicious: Int
    public var suspicious: Int
    public var undetected: Int
    public var harmless: Int
    public var timeout: Int
    public var confirmedTimeout: Int
    public var failure: Int
    public var typeUnsupported: Int

    public init(malicious: Int = 0, suspicious: Int = 0, undetected: Int = 0, harmless: Int = 0, timeout: Int = 0,
                confirmedTimeout: Int = 0, failure: Int = 0, typeUnsupported: Int = 0) {
        self.malicious = malicious
        self.suspicious = suspicious
        self.undetected = undetected
        self.harmless = harmless
        self.timeout = timeout
        self.confirmedTimeout = confirmedTimeout
        self.failure = failure
        self.typeUnsupported = typeUnsupported
    }

    /// Engines that gave a verdict (what virustotal.com shows as "… / N").
    public var engines: Int { malicious + suspicious + undetected + harmless }

    private enum CodingKeys: String, CodingKey {
        case malicious, suspicious, undetected, harmless, timeout, failure
        case confirmedTimeout = "confirmed-timeout"
        case typeUnsupported = "type-unsupported"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) -> Int { max(0, (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil ?? 0) }
        malicious = count(.malicious)
        suspicious = count(.suspicious)
        undetected = count(.undetected)
        harmless = count(.harmless)
        timeout = count(.timeout)
        confirmedTimeout = count(.confirmedTimeout)
        failure = count(.failure)
        typeUnsupported = count(.typeUnsupported)
    }
}

/// What VirusTotal knows about one file.
public struct VirusTotalFileReport: Codable, Sendable, Hashable {
    public var sha256: String
    public var stats: VirusTotalAnalysisStats
    /// `popular_threat_classification.suggested_threat_label` ("trojan.adload/macos").
    public var threatLabel: String?
    /// `meaningful_name`: the file name VirusTotal sees most.
    public var meaningfulName: String?
    public var lastAnalysisDate: Date?
    /// `type_description` ("Mach-O", "Shell script").
    public var typeDescription: String?
    /// Community reputation (negative = flagged by users).
    public var reputation: Int?

    public init(sha256: String, stats: VirusTotalAnalysisStats, threatLabel: String? = nil, meaningfulName: String? = nil,
                lastAnalysisDate: Date? = nil, typeDescription: String? = nil, reputation: Int? = nil) {
        self.sha256 = sha256
        self.stats = stats
        self.threatLabel = threatLabel
        self.meaningfulName = meaningfulName
        self.lastAnalysisDate = lastAnalysisDate
        self.typeDescription = typeDescription
        self.reputation = reputation
    }
}

/// The outcome of one lookup.
public enum VirusTotalLookupResult: Sendable, Hashable {
    /// VirusTotal knows the file.
    case found(VirusTotalFileReport)
    /// 404: VirusTotal has never seen this file.
    case notFound
    /// 401 / 403: the API key is wrong, disabled or not allowed to do this.
    case invalidKey
    /// 429: the key's quota is used up for now.
    case rateLimited
    /// Anything else (network trouble, server errors, unreadable answers), with a plain message.
    case failed(String)

    /// The verdict to keep on a finding; nil for errors.
    public func verdict(checked: Date = Date(), sha256: String) -> VirusTotalVerdict? {
        switch self {
        case .found(let report): return VirusTotalVerdict(report: report, checked: checked)
        case .notFound: return VirusTotalVerdict.notFound(sha256: sha256, checked: checked)
        case .invalidKey, .rateLimited, .failed: return nil
        }
    }

    /// Plain text for errors (nil for answers).
    public var errorMessage: String? {
        switch self {
        case .found, .notFound: return nil
        case .invalidKey: return "VirusTotal didn't accept your API key. Check it in Settings › Protection."
        case .rateLimited: return "Your VirusTotal key has reached its limit for now. Spruce will try again later."
        case .failed(let message): return message
        }
    }
}

/// What a VirusTotal answer means for the user, kept on a finding.
public struct VirusTotalVerdict: Codable, Sendable, Hashable {
    public enum Level: String, Codable, Sendable {
        /// 3 or more engines call it malicious.
        case flagged
        /// 1–2 engines call it malicious, or some call it suspicious.
        case someFlags
        /// Engines looked at it and none flags it.
        case clean
        /// VirusTotal has never seen the file, or has no engine results yet.
        case unknown
    }

    /// Engines calling a file malicious from which it counts as flagged.
    public static let flaggedThreshold = 3
    /// Every VirusTotal line among a finding's reasons starts with this.
    public static let reasonPrefix = "VirusTotal: "

    public var sha256: String
    public var level: Level
    /// False when VirusTotal has never seen the file (404).
    public var isKnown: Bool
    public var malicious: Int
    public var suspicious: Int
    /// Engines that gave a verdict.
    public var engines: Int
    /// The label most engines agree on ("trojan.adload/macos").
    public var threatLabel: String?
    public var fileName: String?
    public var lastAnalysisDate: Date?
    /// When Spruce asked.
    public var checked: Date

    public init(sha256: String, level: Level, isKnown: Bool, malicious: Int, suspicious: Int, engines: Int,
                threatLabel: String? = nil, fileName: String? = nil, lastAnalysisDate: Date? = nil, checked: Date) {
        self.sha256 = sha256
        self.level = level
        self.isKnown = isKnown
        self.malicious = malicious
        self.suspicious = suspicious
        self.engines = engines
        self.threatLabel = threatLabel
        self.fileName = fileName
        self.lastAnalysisDate = lastAnalysisDate
        self.checked = checked
    }

    public init(report: VirusTotalFileReport, checked: Date = Date()) {
        let stats = report.stats
        let level: Level
        if stats.malicious >= Self.flaggedThreshold {
            level = .flagged
        } else if stats.malicious > 0 || stats.suspicious > 0 {
            level = .someFlags
        } else if stats.engines > 0 {
            level = .clean
        } else {
            level = .unknown
        }
        self.init(sha256: report.sha256, level: level, isKnown: true, malicious: stats.malicious,
                  suspicious: stats.suspicious, engines: stats.engines, threatLabel: report.threatLabel,
                  fileName: report.meaningfulName, lastAnalysisDate: report.lastAnalysisDate, checked: checked)
    }

    /// The answer for a file VirusTotal has never seen.
    public static func notFound(sha256: String, checked: Date = Date()) -> VirusTotalVerdict {
        VirusTotalVerdict(sha256: VirusTotalAPI.normalizedSHA256(sha256) ?? sha256, level: .unknown, isKnown: false,
                          malicious: 0, suspicious: 0, engines: 0, checked: checked)
    }

    /// Short headline ("Flagged by 45 of 70 engines").
    public var title: String {
        switch level {
        case .flagged: return "Flagged by \(malicious) of \(engines) engines"
        case .someFlags: return "Some engines flag this"
        case .clean: return "No engine flags this"
        case .unknown: return isKnown ? "No results yet" : "Not known to VirusTotal"
        }
    }

    /// One or two plain sentences for the inspector.
    public var detail: String {
        let label = threatLabel.map { " Most call it \($0)." } ?? ""
        switch level {
        case .flagged:
            return "\(malicious) of \(engines) security engines on VirusTotal flag this file as malicious.\(label)"
        case .someFlags:
            var parts: [String] = []
            if malicious > 0 { parts.append("\(malicious) of \(engines) engines \(malicious == 1 ? "calls" : "call") it malicious") }
            if suspicious > 0 {
                parts.append("\(CountFormat.items(suspicious, singular: "engine")) \(suspicious == 1 ? "calls" : "call") it suspicious")
            }
            return parts.joined(separator: " and ") + ". A few detections can be false alarms.\(label)"
        case .clean:
            return "None of the \(engines) security engines on VirusTotal flag this file."
        case .unknown:
            return isKnown
                ? "VirusTotal knows this file but has no engine results for it yet."
                : "VirusTotal has never seen this file. That's common for apps you built or got recently, and isn't a sign either way."
        }
    }

    /// The line added to a finding's reasons.
    public var reason: String { Self.reasonPrefix + title.lowercasedFirst }

    /// The file's page on virustotal.com.
    public var link: URL? { VirusTotalAPI.guiURL(sha256: sha256) }

    /// True while the answer is recent enough to reuse instead of asking again.
    public func isFresh(now: Date = Date(), maxAge: TimeInterval = 7 * 86_400) -> Bool {
        let age = now.timeIntervalSince(checked)
        return age >= 0 && age < maxAge
    }

    /// Compact JSON for `ScanItem.metadata` (`ProtectionMetaKey.virusTotal`).
    public var metadataValue: String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Reads `metadataValue` back (nil for missing or unreadable values).
    public init?(metadataValue: String?) {
        guard let metadataValue, let data = metadataValue.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let verdict = try? decoder.decode(VirusTotalVerdict.self, from: data) else { return nil }
        self = verdict
    }
}

/// The public API's limits (4 lookups a minute, 500 a day), enforced before asking.
public struct VirusTotalRateLimit: Sendable, Hashable {
    public var perMinute: Int
    public var perDay: Int

    public init(perMinute: Int = 4, perDay: Int = 500) {
        self.perMinute = max(1, perMinute)
        self.perDay = max(1, perDay)
    }

    /// The free public API.
    public static let publicAPI = VirusTotalRateLimit()

    public enum Decision: Sendable, Hashable {
        case allowed
        /// This minute's lookups are used up; the next one may go at `until`.
        case wait(until: Date)
        /// Today's lookups are used up; the next one may go at `until`.
        case dailyLimitReached(until: Date)

        public var isAllowed: Bool { self == .allowed }

        /// When the next lookup may go (nil when it may go now).
        public var nextAttempt: Date? {
            switch self {
            case .allowed: return nil
            case .wait(let until), .dailyLimitReached(let until): return until
            }
        }
    }

    /// Whether a lookup may go at `now`, given when earlier lookups went (any order) and an
    /// optional pause the server asked for (a 429 answer). Times after `now` (the clock was
    /// set back) count as `now`, so they can't block lookups for long.
    public func decision(history: [Date], now: Date, blockedUntil: Date? = nil) -> Decision {
        let times = clamped(history, now: now)
        let day = times.filter { now.timeIntervalSince($0) < 86_400 }.sorted()
        if day.count >= perDay {
            return .dailyLimitReached(until: day[day.count - perDay].addingTimeInterval(86_400))
        }
        let minute = day.filter { now.timeIntervalSince($0) < 60 }
        var until: Date?
        if minute.count >= perMinute {
            until = minute[minute.count - perMinute].addingTimeInterval(60)
        }
        if let blockedUntil, blockedUntil > now, blockedUntil.timeIntervalSince(now) <= 86_400 {
            until = max(until ?? blockedUntil, blockedUntil)
        }
        if let until { return .wait(until: until) }
        return .allowed
    }

    /// The history worth keeping: the last day's lookups, oldest first.
    public func pruned(_ history: [Date], now: Date) -> [Date] {
        clamped(history, now: now).filter { now.timeIntervalSince($0) < 86_400 }.sorted()
    }

    /// Lookups left today.
    public func remainingToday(history: [Date], now: Date) -> Int {
        max(0, perDay - pruned(history, now: now).count)
    }

    private func clamped(_ history: [Date], now: Date) -> [Date] {
        history.map { min($0, now) }
    }
}

// MARK: - Wire format

private struct VirusTotalEnvelope: Decodable {
    var data: VirusTotalObject?
}

private struct VirusTotalObject: Decodable {
    var id: String?
    var type: String?
    var attributes: VirusTotalFileAttributes?
}

private struct VirusTotalFileAttributes: Decodable {
    var sha256: String?
    var lastAnalysisStats: VirusTotalAnalysisStats?
    var popularThreatClassification: VirusTotalThreatClassification?
    var meaningfulName: String?
    var lastAnalysisDate: Int64?
    var typeDescription: String?
    var reputation: Int?

    private enum CodingKeys: String, CodingKey {
        case sha256, reputation
        case lastAnalysisStats = "last_analysis_stats"
        case popularThreatClassification = "popular_threat_classification"
        case meaningfulName = "meaningful_name"
        case lastAnalysisDate = "last_analysis_date"
        case typeDescription = "type_description"
    }

    init(from decoder: Decoder) throws {
        // Every field is optional and a field of an unexpected type is skipped, so a
        // changed detail in VirusTotal's answer can't hide the verdict.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sha256 = (try? c.decodeIfPresent(String.self, forKey: .sha256)) ?? nil
        lastAnalysisStats = (try? c.decodeIfPresent(VirusTotalAnalysisStats.self, forKey: .lastAnalysisStats)) ?? nil
        popularThreatClassification = (try? c.decodeIfPresent(VirusTotalThreatClassification.self,
                                                              forKey: .popularThreatClassification)) ?? nil
        meaningfulName = (try? c.decodeIfPresent(String.self, forKey: .meaningfulName)) ?? nil
        if let seconds = (try? c.decodeIfPresent(Int64.self, forKey: .lastAnalysisDate)) ?? nil {
            lastAnalysisDate = seconds
        } else if let seconds = (try? c.decodeIfPresent(Double.self, forKey: .lastAnalysisDate)) ?? nil, seconds.isFinite,
                  abs(seconds) < 1e12 {
            lastAnalysisDate = Int64(seconds)
        }
        typeDescription = (try? c.decodeIfPresent(String.self, forKey: .typeDescription)) ?? nil
        reputation = (try? c.decodeIfPresent(Int.self, forKey: .reputation)) ?? nil
    }
}

private struct VirusTotalThreatClassification: Decodable {
    var suggestedThreatLabel: String?

    private enum CodingKeys: String, CodingKey {
        case suggestedThreatLabel = "suggested_threat_label"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestedThreatLabel = (try? c.decodeIfPresent(String.self, forKey: .suggestedThreatLabel)) ?? nil
    }
}

private struct VirusTotalErrorEnvelope: Decodable {
    struct Detail: Decodable {
        var code: String?
        var message: String?
    }

    var error: Detail?
}

private extension String {
    /// "Flagged by…" → "flagged by…" (for a line that follows "VirusTotal: ").
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
