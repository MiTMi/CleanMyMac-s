import Foundation

// Spruce's downloadable threat list: feed.json (families and indicators in the catalog's own
// kinds) and rules.yara (extra YARA rules), published in this project's GitHub repository
// (ThreatFeed/). The macOS layer downloads them over HTTPS at most once a day; this file
// reads and checks them. Everything downloaded can only add detections: built-in families
// win on id clashes, indicators the catalog already has are dropped, over-broad patterns
// are refused, and downloaded indicators are ignored for Apple-signed files. Nothing is
// ever removed without the user confirming.

/// A checked copy of feed.json.
public struct ProtectionThreatFeed: Sendable, Equatable {
    /// The feed format this version of Spruce reads.
    public static let supportedFormat = 1
    public static let feedURL = URL(string: "https://raw.githubusercontent.com/MiTMi/CleanMyMac-s/main/ThreatFeed/feed.json")!
    public static let rulesURL = URL(string: "https://raw.githubusercontent.com/MiTMi/CleanMyMac-s/main/ThreatFeed/rules.yara")!
    /// Bigger downloads are refused.
    public static let maxFeedBytes = 5 << 20
    public static let maxRulesBytes = 2 << 20
    public static let maxFamilies = 2_000
    public static let maxIndicators = 20_000
    /// The list is checked at most this often.
    public static let checkInterval: TimeInterval = 86_400

    public let format: Int
    /// Grows with every published change.
    public let version: Int
    /// The feed's "updated" date.
    public let updated: Date?
    /// New families (built-in ids are never redefined).
    public let families: [ProtectionThreatFamily]
    /// Accepted indicators, normalized, tagged `.threatList`.
    public let indicators: [ProtectionIndicator]
    /// Why entries were left out, in plain words (for diagnostics and feed maintainers).
    public let rejected: [String]
    /// Indicators left out because the catalog (or the feed itself) already has them.
    public let duplicateCount: Int

    public init(format: Int = ProtectionThreatFeed.supportedFormat, version: Int, updated: Date? = nil,
                families: [ProtectionThreatFamily] = [], indicators: [ProtectionIndicator] = [],
                rejected: [String] = [], duplicateCount: Int = 0) {
        self.format = format
        self.version = version
        self.updated = updated
        self.families = families
        self.indicators = indicators
        self.rejected = rejected
        self.duplicateCount = duplicateCount
    }

    /// No downloaded data.
    public static let empty = ProtectionThreatFeed(version: 0)

    public var isEmpty: Bool { families.isEmpty && indicators.isEmpty }

    /// True for addresses Spruce may download the list from (HTTPS only).
    public static func isAllowedDownloadURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty
    }

    /// Whether a freshly downloaded feed should replace the cached one: never go back to an
    /// older version (a stale mirror or cache).
    public static func shouldReplace(cachedVersion: Int?, with downloaded: ProtectionThreatFeed) -> Bool {
        downloaded.version >= (cachedVersion ?? 0)
    }

    // MARK: Reading

    /// Reads and checks feed.json. Throws when the file as a whole can't be used (too big,
    /// not a feed, a newer format, too many entries); single bad entries are left out and
    /// explained in `rejected`. `base` is the catalog the feed adds to.
    public static func parse(_ data: Data, base: ProtectionThreatCatalog = .standard) throws -> ProtectionThreatFeed {
        guard data.count <= maxFeedBytes else { throw ProtectionThreatFeedError.tooLarge(bytes: data.count, limit: maxFeedBytes) }
        let raw: RawFeed
        do {
            raw = try JSONDecoder().decode(RawFeed.self, from: data)
        } catch {
            throw ProtectionThreatFeedError.unreadable("It isn't a JSON object.")
        }
        if let field = raw.malformedField {
            throw ProtectionThreatFeedError.unreadable("Its \"\(field)\" field has the wrong type.")
        }
        guard let format = raw.format else { throw ProtectionThreatFeedError.unreadable("It has no \"format\" number.") }
        guard format <= supportedFormat, format >= 1 else { throw ProtectionThreatFeedError.unsupportedFormat(format) }
        guard let version = raw.version, version >= 1 else {
            throw ProtectionThreatFeedError.unreadable("It has no \"version\" number of 1 or more.")
        }
        let rawFamilies = raw.families ?? []
        let rawIndicators = raw.indicators ?? []
        guard rawFamilies.count <= maxFamilies else { throw ProtectionThreatFeedError.tooManyFamilies(rawFamilies.count) }
        guard rawIndicators.count <= maxIndicators else { throw ProtectionThreatFeedError.tooManyIndicators(rawIndicators.count) }

        var rejected: [String] = []
        var updated: Date?
        if let text = raw.updated {
            updated = parseDate(text)
            if updated == nil { rejected.append("The \"updated\" date \"\(text.prefix(40))\" isn't an ISO date (YYYY-MM-DD); it was ignored.") }
        }

        // Families.
        var families: [ProtectionThreatFamily] = []
        var feedFamilyIDs: Set<String> = []
        for (index, entry) in rawFamilies.enumerated() {
            let position = "Family \(index + 1)"
            guard let family = entry.value else {
                rejected.append("\(position) isn't a valid entry (id, name, category and severity must be text).")
                continue
            }
            switch ProtectionThreatFeedValidator.family(family) {
            case .failure(let problem):
                rejected.append("\(position)\(family.id.map { " (\"\(clip($0))\")" } ?? ""): \(problem.text)")
            case .success(let checked):
                if base.family(id: checked.id) != nil {
                    rejected.append("\(position) (\"\(checked.id)\"): a built-in family has this id; the built-in one is kept.")
                } else if !feedFamilyIDs.insert(checked.id).inserted {
                    rejected.append("\(position) (\"\(checked.id)\"): this id is used twice; the first one is kept.")
                } else {
                    families.append(checked)
                }
            }
        }

        // Indicators.
        var indicators: [ProtectionIndicator] = []
        var seen = Set(base.indicators.map(\.dedupeKey))
        var duplicates = 0
        for (index, entry) in rawIndicators.enumerated() {
            let position = "Indicator \(index + 1)"
            guard let rawIndicator = entry.value else {
                rejected.append("\(position) isn't a valid entry (kind, pattern and family must be text).")
                continue
            }
            let label = "\(position)\(rawIndicator.kind.map { " (\($0) \"\(clip(rawIndicator.pattern ?? ""))\")" } ?? "")"
            switch ProtectionThreatFeedValidator.indicator(rawIndicator) {
            case .failure(let problem):
                rejected.append("\(label): \(problem.text)")
            case .success(let indicator):
                guard feedFamilyIDs.contains(indicator.familyID) || base.family(id: indicator.familyID) != nil else {
                    rejected.append("\(label): the family \"\(clip(indicator.familyID))\" isn't defined.")
                    continue
                }
                if seen.insert(indicator.dedupeKey).inserted {
                    indicators.append(indicator)
                } else {
                    duplicates += 1
                }
            }
        }
        return ProtectionThreatFeed(format: format, version: version, updated: updated, families: families,
                                    indicators: indicators, rejected: rejected, duplicateCount: duplicates)
    }

    /// Compiles a downloaded rules.yara (bad rules are skipped by the engine, never the file).
    public static func rules(from data: Data) throws -> YaraRuleSet {
        guard data.count <= maxRulesBytes else { throw ProtectionThreatFeedError.tooLarge(bytes: data.count, limit: maxRulesBytes) }
        return YaraRuleSet(data: data, origin: ProtectionRuleSource.threatListName)
    }

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: trimmed) { return date }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: trimmed) { return date }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        day.timeZone = TimeZone(identifier: "UTC")
        return trimmed.count == 10 ? day.date(from: trimmed) : nil
    }

    static func clip(_ text: String, _ limit: Int = 80) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}

/// Why a downloaded file can't be used at all.
public enum ProtectionThreatFeedError: Error, Sendable, Equatable, CustomStringConvertible {
    case tooLarge(bytes: Int, limit: Int)
    case unreadable(String)
    /// The feed needs a newer version of Spruce.
    case unsupportedFormat(Int)
    case tooManyFamilies(Int)
    case tooManyIndicators(Int)

    public var description: String {
        switch self {
        case .tooLarge(let bytes, let limit):
            return "The download is too big (\(ByteFormat.string(Int64(bytes))), at most \(ByteFormat.string(Int64(limit))))."
        case .unreadable(let detail):
            return "The threat list couldn't be read. \(detail)"
        case .unsupportedFormat(let format):
            return "The threat list uses format \(format), which needs a newer version of Spruce."
        case .tooManyFamilies(let count):
            return "The threat list has \(CountFormat.grouped(count)) families (at most \(CountFormat.grouped(ProtectionThreatFeed.maxFamilies)))."
        case .tooManyIndicators(let count):
            return "The threat list has \(CountFormat.grouped(count)) indicators (at most \(CountFormat.grouped(ProtectionThreatFeed.maxIndicators)))."
        }
    }
}

/// What the macOS layer remembers about the threat list between launches (next to its
/// cached feed.json and rules.yara).
public struct ProtectionThreatFeedStatus: Codable, Sendable, Equatable {
    /// Last check, successful or not.
    public var lastChecked: Date?
    /// Last time a new copy was stored.
    public var lastUpdated: Date?
    public var version: Int?
    /// The feed's own "updated" date.
    public var published: Date?
    public var familyCount: Int = 0
    public var indicatorCount: Int = 0
    public var ruleCount: Int = 0
    public var skippedRuleCount: Int = 0
    public var rejectedCount: Int = 0
    /// Plain text of the last failure (cleared by a successful check).
    public var lastError: String?
    /// HTTP validators for conditional requests.
    public var feedETag: String?
    public var rulesETag: String?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case lastChecked, lastUpdated, version, published, familyCount, indicatorCount, ruleCount, skippedRuleCount,
             rejectedCount, lastError, feedETag, rulesETag
    }

    /// Decodes leniently: missing or unreadable fields keep their defaults.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ current: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil ?? current }
        lastChecked = v(.lastChecked, lastChecked)
        lastUpdated = v(.lastUpdated, lastUpdated)
        version = v(.version, version)
        published = v(.published, published)
        familyCount = v(.familyCount, familyCount)
        indicatorCount = v(.indicatorCount, indicatorCount)
        ruleCount = v(.ruleCount, ruleCount)
        skippedRuleCount = v(.skippedRuleCount, skippedRuleCount)
        rejectedCount = v(.rejectedCount, rejectedCount)
        lastError = v(.lastError, lastError)
        feedETag = v(.feedETag, feedETag)
        rulesETag = v(.rulesETag, rulesETag)
    }

    /// True when the list should be checked again: never checked, a day has passed, or the
    /// clock was set back.
    public func isCheckDue(now: Date = Date(), interval: TimeInterval = ProtectionThreatFeed.checkInterval) -> Bool {
        guard let lastChecked else { return true }
        let elapsed = now.timeIntervalSince(lastChecked)
        return elapsed < 0 || elapsed >= interval
    }

    /// Records a stored copy of the list.
    public mutating func recordUpdate(feed: ProtectionThreatFeed, rules: ProtectionRuleSource?, at date: Date = Date()) {
        lastChecked = date
        lastUpdated = date
        lastError = nil
        version = feed.version
        published = feed.updated
        familyCount = feed.families.count
        indicatorCount = feed.indicators.count
        rejectedCount = feed.rejected.count
        ruleCount = rules?.activeRuleCount ?? 0
        skippedRuleCount = (rules?.rules.skipped.count ?? 0) + (rules?.disabledRules.count ?? 0)
    }

    /// Records a check that found nothing new (or failed: pass the message).
    public mutating func recordCheck(at date: Date = Date(), error: String? = nil) {
        lastChecked = date
        lastError = error
    }

    /// One line for Settings ("Version 3 · 42 indicators · 2 rules"), or "Not downloaded yet".
    public var summary: String {
        guard let version else { return "Not downloaded yet" }
        var parts = ["Version \(version)"]
        parts.append(CountFormat.items(indicatorCount, singular: "indicator"))
        if ruleCount > 0 { parts.append(CountFormat.items(ruleCount, singular: "rule")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Validation

/// The checks every downloaded entry must pass. Public so tools and tests can use them.
public enum ProtectionThreatFeedValidator {
    public struct Problem: Error, Sendable, Equatable {
        public let text: String
        init(_ text: String) { self.text = text }
    }

    /// The SHA-256 of an empty file: it would match every empty file.
    public static let emptyFileSHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// Developer teams of widely used apps the list may never flag (Adobe, Google,
    /// Microsoft, Mozilla).
    public static let protectedTeamIDs: Set<String> = [ProtectionThreatCatalog.adobeTeamID, "EQHXZ8M8AV", "UBF8T346G9", "43AQ936H96"]

    static let summaryFallback = "Listed in Spruce's downloaded threat list."

    // MARK: Families

    static func family(_ raw: RawFamily) -> Result<ProtectionThreatFamily, Problem> {
        guard let id = raw.id?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return .failure(Problem("it has no id.")) }
        guard id.utf8.count <= 64, let first = id.unicodeScalars.first, isLowerAlnum(first),
              id.unicodeScalars.allSatisfy({ isLowerAlnum($0) || $0 == "." || $0 == "-" || $0 == "_" }) else {
            return .failure(Problem("the id may only use lowercase letters, digits, dots, dashes and underscores (at most 64)."))
        }
        guard let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 80,
              !hasControlCharacters(name) else {
            return .failure(Problem("it needs a name of 1 to 80 characters."))
        }
        guard let categoryText = raw.category, let category = ProtectionRuleClassifier.category(named: categoryText) else {
            let known = ThreatCategory.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure(Problem("the category \"\(ProtectionThreatFeed.clip(raw.category ?? ""))\" isn't one of \(known)."))
        }
        guard let severityText = raw.severity, let severity = ProtectionRuleClassifier.severity(named: severityText) else {
            return .failure(Problem("the severity \"\(ProtectionThreatFeed.clip(raw.severity ?? ""))\" isn't low, medium, high or critical."))
        }
        var summary = raw.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard summary.count <= 300, !hasControlCharacters(summary) else {
            return .failure(Problem("the summary is longer than 300 characters."))
        }
        if summary.isEmpty { summary = summaryFallback }
        return .success(ProtectionThreatFamily(id: id, name: name, category: category, severity: severity, summary: summary))
    }

    // MARK: Indicators

    static func indicator(_ raw: RawIndicator) -> Result<ProtectionIndicator, Problem> {
        guard let kindText = raw.kind, let kind = ProtectionIndicator.Kind(rawValue: kindText) else {
            let known = ProtectionIndicator.Kind.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure(Problem("the kind \"\(ProtectionThreatFeed.clip(raw.kind ?? ""))\" isn't one of \(known)."))
        }
        guard let rawPattern = raw.pattern else { return .failure(Problem("it has no pattern.")) }
        guard let family = raw.family?.trimmingCharacters(in: .whitespaces), !family.isEmpty else {
            return .failure(Problem("it names no family."))
        }
        switch normalizedPattern(rawPattern, kind: kind) {
        case .failure(let problem): return .failure(problem)
        case .success(let pattern):
            return .success(ProtectionIndicator(kind, pattern, family: family.lowercased(),
                                                executableOnly: raw.executableOnly ?? false, origin: .threatList))
        }
    }

    /// The pattern in the catalog's form (lowercase hashes, uppercase team IDs), or why it
    /// is refused.
    public static func normalizedPattern(_ pattern: String, kind: ProtectionIndicator.Kind) -> Result<String, Problem> {
        guard !pattern.isEmpty else { return .failure(Problem("the pattern is empty.")) }
        guard !hasControlCharacters(pattern) else { return .failure(Problem("the pattern has control characters.")) }
        if pattern != pattern.trimmingCharacters(in: .whitespacesAndNewlines) {
            return .failure(Problem("the pattern starts or ends with spaces."))
        }
        switch kind {
        case .sha256:
            guard let hash = VirusTotalAPI.normalizedSHA256(pattern) else {
                return .failure(Problem("a SHA-256 is 64 hexadecimal characters."))
            }
            guard hash != emptyFileSHA256 else { return .failure(Problem("this is the SHA-256 of an empty file.")) }
            return .success(hash)
        case .teamID:
            let team = pattern.uppercased()
            guard team.utf8.count == 10, team.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) }) else {
                return .failure(Problem("a Team ID is 10 letters and digits."))
            }
            guard !protectedTeamIDs.contains(team) else {
                return .failure(Problem("this Team ID belongs to a widely used developer."))
            }
            return .success(team)
        case .path, .pathRegex, .launchLabel, .bundleID, .bundleName:
            let problem: Problem?
            switch kind {
            case .path: problem = pathProblem(pattern)
            case .pathRegex: problem = regexProblem(pattern)
            case .bundleName: problem = bundleNameProblem(pattern)
            default: problem = identifierProblem(pattern, kind: kind)
            }
            if let problem { return .failure(problem) }
            return .success(pattern)
        }
    }

    // MARK: Paths

    static func pathProblem(_ pattern: String) -> Problem? {
        guard pattern.count <= 512 else { return Problem("the path is longer than 512 characters.") }
        let body: Substring
        if pattern.hasPrefix("~/") {
            body = pattern.dropFirst(2)
        } else if pattern.hasPrefix("/") {
            body = pattern.dropFirst(1)
        } else {
            return Problem("a path starts with / or ~/.")
        }
        let components = body.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: { $0.isEmpty }) { return Problem("the path has an empty name (// or a trailing /).") }
        if components.contains(where: { $0 == "." || $0 == ".." }) { return Problem("the path may not use . or .. ") }
        let concrete = components.prefix { !ProtectionGlob.isPattern(String($0)) }.count
        guard concrete >= 2 else {
            return Problem("too broad: a path needs at least two names before any wildcard (\"~\" doesn't count).")
        }
        for component in components where ProtectionGlob.isPattern(String(component)) {
            if component.filter({ $0 != "*" && $0 != "?" }).count < 3 {
                return Problem("too broad: every name with a wildcard needs at least three other characters.")
            }
        }
        if let canary = canaryPaths.first(where: { ProtectionGlob.matches(pattern, $0) }) {
            return Problem("too broad: it would match \(canary).")
        }
        return nil
    }

    static func regexProblem(_ pattern: String) -> Problem? {
        guard pattern.count <= 512 else { return Problem("the expression is longer than 512 characters.") }
        guard pattern.hasPrefix("^/") || pattern.hasPrefix("^~/") else {
            return Problem("a path expression starts with ^/ or ^~/.")
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return Problem("it isn't a valid regular expression.")
        }
        if hasTopLevelAlternation(pattern) { return Problem("| may only be used inside parentheses.") }
        if pattern.range(of: #"\\[1-9]|\\k<"#, options: .regularExpression) != nil {
            return Problem("back-references aren't allowed.")
        }
        if pattern.range(of: #"\((?:[^()\\]|\\.)*[*+}](?:[^()\\]|\\.)*\)[*+{]"#, options: .regularExpression) != nil {
            return Problem("a repeated group may not repeat inside (it could take very long to check).")
        }
        guard literalComponentCount(regexAfterCaret: pattern.dropFirst()) >= 2 else {
            return Problem("too broad: the expression needs at least two literal names before any pattern (\"~\" doesn't count).")
        }
        for canary in canaryPaths {
            let range = NSRange(canary.startIndex..<canary.endIndex, in: canary)
            if regex.firstMatch(in: canary, options: [], range: range) != nil {
                return Problem("too broad: it would match \(canary).")
            }
        }
        return nil
    }

    /// Counts the complete literal path names at the start of a regular expression
    /// ("/Library/Application Support/\.[0-9]+" → 2). A name only counts when it ends with a
    /// literal "/" (or the expression ends right after it).
    static func literalComponentCount(regexAfterCaret: Substring) -> Int {
        var scalars = Array(regexAfterCaret.unicodeScalars)
        if scalars.first == "~" { scalars.removeFirst() }
        guard scalars.first == "/" else { return 0 }
        scalars.removeFirst()
        var literal = ""
        var reachedEnd = true
        var index = 0
        let metacharacters: Set<Unicode.Scalar> = [".", "[", "]", "(", ")", "{", "}", "*", "+", "?", "|", "^", "$"]
        let quantifiers: Set<Unicode.Scalar> = ["*", "+", "?", "{"]
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\\" {
                guard index + 1 < scalars.count else { reachedEnd = false; break }
                let next = scalars[index + 1]
                if CharacterSet.alphanumerics.contains(next) { reachedEnd = false; break }   // \d, \w, \s…
                literal.unicodeScalars.append(next)
                index += 2
                continue
            }
            if scalar == "$", index == scalars.count - 1 { break }
            if metacharacters.contains(scalar) {
                // A quantifier makes the character before it optional.
                if quantifiers.contains(scalar), !literal.isEmpty { literal.removeLast() }
                reachedEnd = false
                break
            }
            literal.unicodeScalars.append(scalar)
            index += 1
        }
        var parts = literal.split(separator: "/", omittingEmptySubsequences: false)
        if !reachedEnd { parts.removeLast() }          // the last name isn't complete
        return parts.prefix { !$0.isEmpty }.count
    }

    static func hasTopLevelAlternation(_ pattern: String) -> Bool {
        var depth = 0
        var inClass = false
        var escaped = false
        for scalar in pattern.unicodeScalars {
            if escaped { escaped = false; continue }
            switch scalar {
            case "\\": escaped = true
            case "[" where !inClass: inClass = true
            case "]" where inClass: inClass = false
            case "(" where !inClass: depth += 1
            case ")" where !inClass: depth = max(0, depth - 1)
            case "|" where !inClass && depth == 0: return true
            default: break
            }
        }
        return false
    }

    // MARK: Names

    static func identifierProblem(_ pattern: String, kind: ProtectionIndicator.Kind) -> Problem? {
        guard pattern.count <= 255 else { return Problem("the name is longer than 255 characters.") }
        guard !pattern.contains("/"), !pattern.contains(" ") else { return Problem("the name may not contain / or spaces.") }
        let components = pattern.split(separator: ".", omittingEmptySubsequences: false)
        if components.contains(where: { $0.isEmpty }) { return Problem("the name has an empty part (..).") }
        let concrete = components.prefix { !ProtectionGlob.isPattern(String($0)) }.count
        guard concrete >= 2 else {
            return Problem("too broad: the name needs at least two dot-separated parts before any wildcard.")
        }
        let canaries = kind == .launchLabel ? canaryLabels : canaryBundleIDs
        if let canary = canaries.first(where: { ProtectionGlob.matches(pattern, $0) }) {
            return Problem("too broad: it would match \(canary).")
        }
        return nil
    }

    static func bundleNameProblem(_ pattern: String) -> Problem? {
        guard pattern.count <= 255 else { return Problem("the name is longer than 255 characters.") }
        guard !pattern.contains("/") else { return Problem("a bundle name may not contain /.") }
        let leading = pattern.prefix { $0 != "*" && $0 != "?" }
        guard leading.count >= 4 else {
            return Problem("too broad: a bundle name needs at least four characters before any wildcard.")
        }
        if let canary = canaryBundleNames.first(where: { ProtectionGlob.matches(pattern, $0) }) {
            return Problem("too broad: it would match \(canary).")
        }
        return nil
    }

    // MARK: Helpers

    private static func isLowerAlnum(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
    }

    private static func hasControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    // MARK: Canaries

    /// Ordinary locations no downloaded path pattern may match.
    public static let canaryPaths: [String] = [
        "~", "~/Library", "~/Library/LaunchAgents", "~/Library/LaunchAgents/com.example.agent.plist",
        "~/Library/LaunchAgents/com.google.keystone.agent.plist", "~/Library/LaunchAgents/homebrew.mxcl.redis.plist",
        "/Library/LaunchAgents", "/Library/LaunchAgents/com.example.agent.plist", "/Library/LaunchDaemons",
        "/Library/LaunchDaemons/com.example.helper.plist", "/Library/LaunchDaemons/com.docker.vmnetd.plist",
        "/Library/PrivilegedHelperTools", "/Library/PrivilegedHelperTools/com.example.helper",
        "~/Library/Application Support", "~/Library/Application Support/Example",
        "~/Library/Application Support/com.example.app", "~/Library/Application Support/Google",
        "~/Library/Application Support/Google/Chrome", "/Library/Application Support", "/Library/Application Support/Example",
        "~/Library/Preferences", "~/Library/Preferences/com.example.app.plist", "~/Library/Caches",
        "~/Library/Caches/com.example.app", "~/Library/Containers", "~/Library/Containers/com.example.app",
        "~/Library/Group Containers", "~/Library/Logs", "~/Library/Logs/example.log", "~/Library/Mail", "~/Library/Safari",
        "~/Library/Keychains", "~/Library/Mobile Documents", "~/Library/CloudStorage", "/Applications",
        "/Applications/Example.app", "/Applications/Safari.app", "/Applications/Google Chrome.app",
        "/Applications/Utilities", "/Applications/Utilities/Terminal.app", "~/Applications", "~/Applications/Example.app",
        "~/Documents", "~/Documents/example.pdf", "~/Desktop", "~/Desktop/example.txt", "~/Downloads",
        "~/Downloads/example.dmg", "~/Downloads/example.zip", "~/Downloads/Install Example.pkg", "~/Pictures", "~/Movies",
        "~/Music", "~/Public", "~/.Trash", "~/.ssh", "~/.ssh/id_ed25519", "~/.zshrc", "~/.bash_profile", "~/.config",
        "~/.local", "~/.local/bin", "~/.local/bin/example", "/Users", "/Users/Shared", "/Users/Shared/example",
        "/tmp", "/tmp/example", "/private/tmp", "/private/tmp/example", "/var/tmp", "/var/tmp/example",
        "/private/var/tmp", "/private/var/tmp/example", "/var/folders", "/private/var/folders", "/usr", "/usr/bin",
        "/usr/bin/python3", "/usr/local", "/usr/local/bin", "/usr/local/bin/example", "/opt/homebrew",
        "/opt/homebrew/bin/example", "/System", "/System/Library", "/System/Library/CoreServices/Finder.app",
        "/System/Applications/Mail.app", "/bin", "/bin/zsh", "/sbin", "/etc", "/etc/hosts", "/private/etc/hosts",
        "/Library", "/Library/Extensions", "/Library/Internet Plug-Ins", "/Library/Frameworks", "/Volumes", "/cores",
    ]

    /// Ordinary startup job names no downloaded label pattern may match.
    public static let canaryLabels: [String] = [
        "com.apple.example", "com.apple.Safari.SafeBrowsing", "com.apple.mdworker.shared", "com.google.keystone.agent",
        "com.google.keystone.daemon", "com.google.GoogleUpdater.wake", "com.microsoft.update.agent",
        "com.microsoft.autoupdate.helper", "com.adobe.ARMDC.Communicator", "com.adobe.AdobeCreativeCloud",
        "com.docker.vmnetd", "com.dropbox.DropboxMacUpdate.agent", "us.zoom.ZoomDaemon", "us.zoom.updater",
        "homebrew.mxcl.redis", "homebrew.mxcl.postgresql@16", "com.example.agent", "com.example.helper",
        "com.example.app", "com.example.updater", "org.example.daemon", "com.oracle.java.Java-Updater",
        "com.spotify.webhelper", "com.valvesoftware.steamclean", "com.openssh.ssh-agent",
    ]

    /// Ordinary bundle identifiers no downloaded pattern may match.
    public static let canaryBundleIDs: [String] = [
        "com.apple.Safari", "com.apple.finder", "com.apple.Terminal", "com.apple.example", "com.google.Chrome",
        "com.google.Chrome.helper", "com.microsoft.Word", "com.microsoft.VSCode", "org.mozilla.firefox",
        "com.example.app", "com.example.helper", "com.example.installer", "com.tinyspeck.slackmacgap", "us.zoom.xos",
        "com.spotify.client", "com.adobe.Reader", "com.docker.docker", "com.github.Electron", "com.electron.example",
        "org.example.app", "net.example.app", "io.example.app",
    ]

    /// Ordinary bundle names no downloaded pattern may match.
    public static let canaryBundleNames: [String] = [
        "Safari.app", "Google Chrome.app", "Firefox.app", "Example.app", "Example Helper.app", "Example Helper (Renderer).app",
        "Install.app", "Installer.app", "Install Example.app", "Setup.app", "Update.app", "Updater.app", "Player.app",
        "Helper.app", "Uninstall.app", "Uninstaller.app", "Install macOS Sequoia.app", "Xcode.app", "Microsoft Word.app",
        "zoom.us.app", "Slack.app", "Example.safariextz", "Example.appex", "Example.plugin", "Example.bundle",
        "Example.kext", "Example.framework", "Example.prefPane",
    ]
}

// MARK: - Wire format

/// An array element that may fail to decode on its own without failing the array.
struct ProtectionLenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct RawFeed: Decodable {
    var format: Int?
    var version: Int?
    var updated: String?
    var families: [ProtectionLenient<RawFamily>]?
    var indicators: [ProtectionLenient<RawIndicator>]?
    /// The first top-level field that is present with the wrong type.
    var malformedField: String?

    private enum CodingKeys: String, CodingKey {
        case format, version, updated, families, indicators
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var malformed: String?
        func field<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            do {
                return try c.decodeIfPresent(type, forKey: key)
            } catch {
                if malformed == nil { malformed = key.stringValue }
                return nil
            }
        }
        format = field(Int.self, .format)
        version = field(Int.self, .version)
        updated = field(String.self, .updated)
        families = field([ProtectionLenient<RawFamily>].self, .families)
        indicators = field([ProtectionLenient<RawIndicator>].self, .indicators)
        malformedField = malformed
    }
}

struct RawFamily: Decodable {
    var id: String?
    var name: String?
    var category: String?
    var severity: String?
    var summary: String?
}

struct RawIndicator: Decodable {
    var kind: String?
    var pattern: String?
    var family: String?
    var executableOnly: Bool?
}
