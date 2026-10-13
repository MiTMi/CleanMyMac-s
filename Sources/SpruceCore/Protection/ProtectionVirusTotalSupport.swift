import Foundation

// What the macOS layer needs around VirusTotal lookups, kept here so it can be tested:
// answers remembered per SHA-256, the lookups counted against the public API's limits,
// which findings are worth an automatic lookup, and how an answer is shown on a review
// row. Only a file's SHA-256 is ever sent; files are never uploaded.

/// Answers Spruce already has, by SHA-256, so a file isn't looked up again for a while.
public struct VirusTotalVerdictCache: Codable, Sendable, Equatable {
    /// Oldest answers are dropped beyond this.
    public static let maxEntries = 5_000
    /// Answers about files VirusTotal knows are reused for a week…
    public static let knownMaxAge: TimeInterval = 7 * 86_400
    /// …and "not known to VirusTotal" for a day (someone may upload the file meanwhile).
    public static let unknownMaxAge: TimeInterval = 86_400

    public var verdicts: [String: VirusTotalVerdict]

    public init(verdicts: [String: VirusTotalVerdict] = [:]) {
        self.verdicts = verdicts
    }

    private enum CodingKeys: String, CodingKey {
        case verdicts
    }

    /// Decodes leniently: an unreadable file is an empty cache.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verdicts = (try? c.decodeIfPresent([String: VirusTotalVerdict].self, forKey: .verdicts)) ?? [:]
    }

    /// How long an answer may be reused.
    public static func maxAge(of verdict: VirusTotalVerdict) -> TimeInterval {
        verdict.isKnown ? knownMaxAge : unknownMaxAge
    }

    /// A recent enough answer for `sha256`, if any.
    public func fresh(for sha256: String, now: Date = Date()) -> VirusTotalVerdict? {
        guard let hash = VirusTotalAPI.normalizedSHA256(sha256), let verdict = verdicts[hash],
              verdict.isFresh(now: now, maxAge: Self.maxAge(of: verdict)) else { return nil }
        return verdict
    }

    /// Keeps an answer (and drops stale ones).
    public mutating func store(_ verdict: VirusTotalVerdict, now: Date = Date()) {
        guard let hash = VirusTotalAPI.normalizedSHA256(verdict.sha256) else { return }
        verdicts[hash] = verdict
        prune(now: now)
    }

    /// Drops stale answers and the oldest ones beyond `maxEntries`.
    public mutating func prune(now: Date = Date()) {
        verdicts = verdicts.filter { $0.value.isFresh(now: now, maxAge: Self.maxAge(of: $0.value)) }
        if verdicts.count > Self.maxEntries {
            let keep = verdicts.sorted { $0.value.checked > $1.value.checked }.prefix(Self.maxEntries)
            verdicts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }
}

/// The lookups counted against the API key's limits, kept between launches.
public struct VirusTotalQuota: Codable, Sendable, Equatable {
    /// When lookups went (the last day's).
    public var lookups: [Date]
    /// A pause VirusTotal asked for (a 429 answer).
    public var blockedUntil: Date?
    /// 429 answers in a row; each one doubles the pause (1 minute up to an hour).
    public var consecutiveRateLimits: Int

    public init(lookups: [Date] = [], blockedUntil: Date? = nil, consecutiveRateLimits: Int = 0) {
        self.lookups = lookups
        self.blockedUntil = blockedUntil
        self.consecutiveRateLimits = consecutiveRateLimits
    }

    private enum CodingKeys: String, CodingKey {
        case lookups, blockedUntil, consecutiveRateLimits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lookups = (try? c.decodeIfPresent([Date].self, forKey: .lookups)) ?? []
        blockedUntil = (try? c.decodeIfPresent(Date.self, forKey: .blockedUntil)) ?? nil
        consecutiveRateLimits = max(0, (try? c.decodeIfPresent(Int.self, forKey: .consecutiveRateLimits)) ?? nil ?? 0)
    }

    /// Whether a lookup may go now.
    public func decision(_ limit: VirusTotalRateLimit = .publicAPI, now: Date = Date()) -> VirusTotalRateLimit.Decision {
        limit.decision(history: lookups, now: now, blockedUntil: blockedUntil)
    }

    /// Counts a lookup that is about to go (VirusTotal counts every request, found or not).
    public mutating func record(_ limit: VirusTotalRateLimit = .publicAPI, now: Date = Date()) {
        lookups = limit.pruned(lookups + [now], now: now)
    }

    /// VirusTotal answered 429: pause, longer each time it happens in a row.
    public mutating func pause(now: Date = Date()) {
        consecutiveRateLimits = min(consecutiveRateLimits + 1, 16)
        let seconds = min(3_600, 60 * pow(2, Double(consecutiveRateLimits - 1)))
        blockedUntil = now.addingTimeInterval(seconds)
    }

    /// Any other answer ends a run of 429s.
    public mutating func recordAnswer() {
        consecutiveRateLimits = 0
        blockedUntil = nil
    }

    public func remainingToday(_ limit: VirusTotalRateLimit = .publicAPI, now: Date = Date()) -> Int {
        limit.remainingToday(history: lookups, now: now)
    }
}

/// How a lookup of one file went, as the Protection screens show it.
public enum VirusTotalLookupOutcome: Sendable, Equatable {
    /// VirusTotal answered (including "not known to VirusTotal").
    case verdict(VirusTotalVerdict)
    /// No API key is saved.
    case noKey
    /// VirusTotal refused the key.
    case invalidKey
    /// The key's limit is used up for now; the next lookup may go at `until` (when known).
    case rateLimited(until: Date?)
    /// The key's 500 lookups a day are used up.
    case dailyLimitReached(until: Date)
    /// The item has no file Spruce can fingerprint (a folder, a cron job, an online-only file…).
    case noFile(String)
    /// Network trouble or an answer Spruce couldn't read.
    case failed(String)

    public var verdict: VirusTotalVerdict? {
        if case .verdict(let verdict) = self { return verdict }
        return nil
    }

    /// The outcome of a parsed answer.
    public init(_ result: VirusTotalLookupResult, sha256: String, checked: Date = Date()) {
        switch result {
        case .found, .notFound:
            if let verdict = result.verdict(checked: checked, sha256: sha256) {
                self = .verdict(verdict)
            } else {
                self = .failed("VirusTotal sent an answer Spruce couldn't read.")
            }
        case .invalidKey: self = .invalidKey
        case .rateLimited: self = .rateLimited(until: nil)
        case .failed(let message): self = .failed(message)
        }
    }

    /// Plain text for anything but an answer.
    public var message: String? {
        switch self {
        case .verdict: return nil
        case .noKey: return "Add your VirusTotal API key in Settings › Protection to check files."
        case .invalidKey: return VirusTotalLookupResult.invalidKey.errorMessage
        case .rateLimited(let until):
            if let until { return "VirusTotal allows 4 lookups a minute. Spruce will try again at \(Self.time(until))." }
            return VirusTotalLookupResult.rateLimited.errorMessage
        case .dailyLimitReached(let until):
            return "Your VirusTotal key has used its 500 lookups for today. More are available after \(Self.time(until))."
        case .noFile(let reason): return reason
        case .failed(let message): return message
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDate(date, inSameDayAs: Date()) ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// What checking an API key found.
public enum VirusTotalKeyCheck: Sendable, Equatable {
    /// VirusTotal accepted the key.
    case valid
    /// VirusTotal accepted the key, but its limit is used up right now.
    case quotaReached
    /// VirusTotal refused the key.
    case invalid
    /// The text can't be an API key.
    case malformed
    /// VirusTotal couldn't be asked (network trouble…).
    case failed(String)
    /// Saved without asking VirusTotal (the user chose to save it while offline).
    case notChecked

    /// The key works, or the user chose to keep it unchecked (saving it makes sense).
    public var isUsable: Bool { self == .valid || self == .quotaReached || self == .notChecked }

    public var message: String {
        switch self {
        case .valid: return "VirusTotal accepted your key."
        case .quotaReached: return "VirusTotal accepted your key, but it has reached its limit for now."
        case .invalid: return "VirusTotal didn't accept this key. Copy it again from your VirusTotal account."
        case .malformed: return "That doesn't look like a VirusTotal API key. It's a long string of letters and digits."
        case .failed(let message): return message
        case .notChecked: return "Your key is saved. Spruce will check it with the first lookup."
        }
    }
}

/// Which findings are looked up automatically after a scan.
public enum VirusTotalCandidates {
    /// At most this many automatic lookups per scan (a free key allows 500 a day).
    public static let maxAutomaticPerScan = 40

    /// A file anyone can use to check a key: the EICAR test file, which VirusTotal knows.
    public static let keyCheckSHA256 = "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"

    /// True for heuristic and rule-based findings with a program file or hash that weren't
    /// looked up recently. Catalog matches are already known threats, so they aren't spent
    /// lookups on.
    public static func isAutomaticCandidate(_ finding: ProtectionThreatFinding, now: Date = Date()) -> Bool {
        guard finding.evidence == .heuristic || finding.evidence == .ruleMatch else { return false }
        guard finding.programPath != nil || finding.sha256.flatMap(VirusTotalAPI.normalizedSHA256) != nil else { return false }
        if let verdict = finding.virusTotal, verdict.isFresh(now: now, maxAge: VirusTotalVerdictCache.maxAge(of: verdict)) {
            return false
        }
        return true
    }

    /// The findings to look up after a scan: rule matches first, then the most severe, one per
    /// file, at most `limit`.
    public static func automatic(_ findings: [ProtectionThreatFinding], now: Date = Date(),
                                 limit: Int = maxAutomaticPerScan) -> [ProtectionThreatFinding] {
        let ordered = findings.filter { isAutomaticCandidate($0, now: now) }.sorted {
            ($0.evidence == .ruleMatch ? 1 : 0, $0.severity, $0.score, $1.name)
                > ($1.evidence == .ruleMatch ? 1 : 0, $1.severity, $1.score, $0.name)
        }
        var seen: Set<String> = []
        var picked: [ProtectionThreatFinding] = []
        for finding in ordered where picked.count < max(0, limit) {
            let key = finding.sha256.flatMap(VirusTotalAPI.normalizedSHA256) ?? finding.programPath ?? finding.id
            if seen.insert(key).inserted { picked.append(finding) }
        }
        return picked
    }
}

// MARK: - Review rows

public extension ScanItem {
    /// The VirusTotal answer recorded on a malware review row.
    var virusTotalVerdict: VirusTotalVerdict? {
        VirusTotalVerdict(metadataValue: metadata[ProtectionMetaKey.virusTotal])
    }

    /// The SHA-256 recorded on a malware review row.
    var protectionSHA256: String? {
        metadata[ProtectionMetaKey.sha256].flatMap(VirusTotalAPI.normalizedSHA256)
    }

    /// The file "Check with VirusTotal" fingerprints: the program behind the row, else the
    /// row's own file for single-file rows. Nil for rows without one (cron jobs, browser
    /// policies); the macOS layer still checks that the path is a regular, local file.
    var protectionLookupPath: String? {
        guard metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.malwareTool else { return nil }
        if let program = metadata[ProtectionMetaKey.program], !program.isEmpty { return program }
        guard let url, url.isFileURL else { return nil }
        let kind = ProtectionItemKind(rawValue: metadata[ProtectionMetaKey.kind] ?? "") ?? .file
        return kind == .cronJob ? nil : url.path
    }

    /// Records a VirusTotal answer on a malware review row, the way
    /// `ProtectionThreatFinding.applyVirusTotal` does on a finding: the answer, its reason
    /// line (replacing an older one) and High severity when enough engines flag the file.
    /// Selection and safety stay as they were.
    mutating func applyVirusTotal(_ verdict: VirusTotalVerdict) {
        guard metadata[ProtectionMetaKey.tool] == ProtectionMetaKey.malwareTool else { return }
        if let value = verdict.metadataValue { metadata[ProtectionMetaKey.virusTotal] = value }
        if protectionSHA256 == nil { metadata[ProtectionMetaKey.sha256] = verdict.sha256 }
        var reasons = (metadata[ProtectionMetaKey.reasons] ?? note ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        reasons.removeAll { $0.hasPrefix(VirusTotalVerdict.reasonPrefix) }
        if verdict.level == .flagged {
            reasons.insert(verdict.reason, at: min(1, reasons.count))
            let current = Int(metadata[ProtectionMetaKey.severity] ?? "").flatMap(ThreatSeverity.init(rawValue:)) ?? .medium
            metadata[ProtectionMetaKey.severity] = String(max(current, .high).rawValue)
        } else {
            reasons.append(verdict.reason)
        }
        metadata[ProtectionMetaKey.reasons] = reasons.joined(separator: "\n")
        if let first = reasons.first { note = first }
    }
}

public extension ProtectionMalwareReport {
    /// Records a VirusTotal answer on the findings with id `itemID` or with the answer's file
    /// hash. Returns true when a finding took it.
    @discardableResult
    mutating func applyVirusTotal(_ verdict: VirusTotalVerdict, itemID: String? = nil) -> Bool {
        let hash = VirusTotalAPI.normalizedSHA256(verdict.sha256)
        var applied = false
        for index in findings.indices {
            let finding = findings[index]
            let sameFile = hash != nil && finding.sha256.flatMap(VirusTotalAPI.normalizedSHA256) == hash
            guard finding.id == itemID || sameFile else { continue }
            findings[index].applyVirusTotal(verdict)
            applied = true
        }
        return applied
    }
}

public extension Array where Element == ScanGroup {
    /// Records a VirusTotal answer on the malware rows with id `itemID` or with the answer's
    /// file hash, in these groups and their sub-groups. Returns true when a row changed.
    @discardableResult
    mutating func applyVirusTotal(_ verdict: VirusTotalVerdict, itemID: String?) -> Bool {
        let hash = VirusTotalAPI.normalizedSHA256(verdict.sha256)
        var answers: [String: VirusTotalVerdict] = [:]
        for group in self {
            for item in group.allItems where item.id == itemID || (hash != nil && item.protectionSHA256 == hash) {
                answers[item.id] = verdict
            }
        }
        return applyVirusTotal(answers)
    }

    /// Records VirusTotal answers (by item id) on the malware rows of these groups and their
    /// sub-groups. Returns true when a row changed.
    @discardableResult
    mutating func applyVirusTotal(_ verdictsByItemID: [String: VirusTotalVerdict]) -> Bool {
        guard !verdictsByItemID.isEmpty else { return false }
        var changed = false
        for index in indices {
            for itemIndex in self[index].items.indices {
                let item = self[index].items[itemIndex]
                guard let verdict = verdictsByItemID[item.id], item.virusTotalVerdict != verdict else { continue }
                self[index].items[itemIndex].applyVirusTotal(verdict)
                changed = changed || self[index].items[itemIndex] != item
            }
            if self[index].children.applyVirusTotal(verdictsByItemID) { changed = true }
        }
        return changed
    }
}
