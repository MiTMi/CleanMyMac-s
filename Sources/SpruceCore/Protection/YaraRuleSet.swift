import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// Spruce's built-in YARA engine (no third-party code). It runs Apple's XProtect rules and
// Spruce's own feed rules. What it understands:
//
// * Rules: `import`, `private`, `global`, tags, meta (text, number, true/false), comments.
// * Strings: text with ascii, wide, nocase, fullword, private and xor[(a-b)]; hex with
//   `??`, nibble wildcards (`4?`, `?4`), `~` (not), jumps (`[n]`, `[n-m]`, `[n-]`, `[-]`)
//   and nested alternatives.
// * Conditions: and/or/not, comparisons, arithmetic and bitwise operators, `filesize`
//   (with KB/MB), `$a`, `$a at …`, `$a in (…..…)`, `#a`, `#a in (…)`, `@a[i]`, `!a[i]`,
//   `all/any/none/N/N% of <strings or rules> [at/in]`, `for … of … : (…)`,
//   `for … i in (…..…) / (a, b, …) : (…)`, `uint8/16/32[be]`, `int8/16/32[be]`,
//   `hash.md5/sha1/sha256/crc32/checksum32(offset, size)` or `(text)`, `defined`,
//   `contains`/`startswith`/… on texts, references to other rules (also before they appear).
//
// Anything else — regular expressions, base64 strings, other modules (pe, macho, math…),
// `entrypoint`, `include` — skips only the rules that use it (and rules that refer to
// those), each with a reason in `skipped`. A syntax error skips the rule it is in.
//
// How a scan works: every string gets a literal "atom" of up to 4 bytes (all case variants
// for nocase text), one Aho–Corasick pass over the data finds candidates, and bounded
// backtracking verifies each one around its atom. Strings without an atom, and xor strings,
// are scanned linearly up to `YaraScanLimits.linearScanBytes`. Hex strings split at
// unbounded or long jumps are matched piece by piece and joined like YARA's chained strings.
// `YaraScanLimits` caps matches per string and the work per candidate, per string and per
// scan, so no rule file or input can hang a scan; results then carry a note.
//
// Differences from YARA worth knowing: `#a` stops counting at `maxMatchesPerString`
// (YARA: 1,000,000; later pieces of split hex strings keep `maxMatchesPerChainPiece`);
// `!a` of a pattern with jumps is its shortest match from that offset;
// `0 of …` means none of them; references to rules defined later are allowed;
// wildcard rule sets may name at most 1,000 rules.

/// A meta value of a rule.
public enum YaraMetaValue: Sendable, Hashable, CustomStringConvertible {
    case text(String)
    case integer(Int64)
    case boolean(Bool)

    public var description: String {
        switch self {
        case .text(let text): return text
        case .integer(let number): return String(number)
        case .boolean(let value): return value ? "true" : "false"
        }
    }
}

/// One `key = value` line of a rule's meta section.
public struct YaraMeta: Sendable, Hashable {
    public let key: String
    public let value: YaraMetaValue

    public init(key: String, value: YaraMetaValue) {
        self.key = key
        self.value = value
    }
}

/// A rule that loaded.
public struct YaraRuleInfo: Sendable, Hashable {
    public let name: String
    public let tags: [String]
    public let meta: [YaraMeta]
    /// Private rules only help other rules; they never appear in results.
    public let isPrivate: Bool
    /// Global rules must hold for any rule of the file to match.
    public let isGlobal: Bool
    /// Line of the rule in its file.
    public let line: Int

    public init(name: String, tags: [String] = [], meta: [YaraMeta] = [], isPrivate: Bool = false,
                isGlobal: Bool = false, line: Int = 0) {
        self.name = name
        self.tags = tags
        self.meta = meta
        self.isPrivate = isPrivate
        self.isGlobal = isGlobal
        self.line = line
    }

    /// The first `description` meta value, if any.
    public var description: String? { YaraRuleInfo.text("description", in: meta) }

    static func text(_ key: String, in meta: [YaraMeta]) -> String? {
        for entry in meta where entry.key == key {
            if case .text(let text) = entry.value { return text }
        }
        return nil
    }
}

/// A rule that was not loaded, and why.
public struct YaraSkippedRule: Sendable, Hashable {
    /// Empty when the problem came before the rule's name.
    public let name: String
    public let line: Int
    public let reason: String

    public init(name: String, line: Int, reason: String) {
        self.name = name
        self.line = line
        self.reason = reason
    }
}

/// A rule that matched a file.
public struct YaraRuleMatch: Sendable, Hashable {
    public let name: String
    public let tags: [String]
    public let meta: [YaraMeta]
    /// Where the rule came from (the `origin` given to `YaraRuleSet`).
    public let origin: String

    public init(name: String, tags: [String], meta: [YaraMeta], origin: String) {
        self.name = name
        self.tags = tags
        self.meta = meta
        self.origin = origin
    }

    /// The rule's `description` meta value, if any.
    public var description: String? { YaraRuleInfo.text("description", in: meta) }

    /// A meta value by key.
    public func meta(_ key: String) -> YaraMetaValue? { meta.first { $0.key == key }?.value }
}

/// Bounds that keep a scan fast whatever the rules or the file look like.
public struct YaraScanLimits: Sendable, Hashable {
    /// Matches kept per string; later ones are not counted (`#a` stops growing).
    public var maxMatchesPerString: Int
    /// Backtracking steps for verifying one candidate.
    public var maxStepsPerCandidate: Int
    /// Work one string may use in a scan before it stops looking (so it can't starve others).
    public var maxStepsPerString: Int
    /// Work budget for one scan (string verification and condition evaluation each).
    public var maxTotalSteps: Int
    /// Strings without a usable atom (and XOR strings) are looked for in this many bytes.
    public var linearScanBytes: Int
    /// Longest `for … in (a..b)` loop that runs.
    public var maxLoopIterations: Int
    /// Matches kept for a later piece of a hex string split at a long jump (`{ … [-] … }`):
    /// a piece only counts after the earlier ones, so its first matches alone may all come
    /// too early. A scan keeps at most four times this many such matches in all.
    public var maxMatchesPerChainPiece: Int

    public init(maxMatchesPerString: Int = 1_000, maxStepsPerCandidate: Int = 100_000,
                maxStepsPerString: Int = 5_000_000, maxTotalSteps: Int = 50_000_000, linearScanBytes: Int = 16 << 20,
                maxLoopIterations: Int = 1_000_000, maxMatchesPerChainPiece: Int = 100_000) {
        self.maxMatchesPerString = maxMatchesPerString
        self.maxStepsPerCandidate = maxStepsPerCandidate
        self.maxStepsPerString = maxStepsPerString
        self.maxTotalSteps = maxTotalSteps
        self.linearScanBytes = linearScanBytes
        self.maxLoopIterations = maxLoopIterations
        self.maxMatchesPerChainPiece = maxMatchesPerChainPiece
    }

    public static let standard = YaraScanLimits()
}

/// The outcome of one scan.
public struct YaraScanResult: Sendable, Hashable {
    /// Non-private rules that matched, in file order.
    public let matches: [YaraRuleMatch]
    /// Bytes searched for strings.
    public let bytesScanned: Int
    /// Size used for `filesize`.
    public let fileSize: Int
    /// Plain notes when a limit cut the scan short (results may then miss matches).
    public let notes: [String]
}

/// A compiled YARA rule file. Immutable and safe to share between threads.
public struct YaraRuleSet: Sendable {
    /// Label copied into every match, e.g. "Apple XProtect" or "Spruce threat feed".
    public let origin: String
    /// Rules that loaded (private ones included), in file order.
    public let rules: [YaraRuleInfo]
    /// Rules that didn't load, with the reason, in file order.
    public let skipped: [YaraSkippedRule]
    /// Modules the file imports.
    public let imports: [String]
    /// File-level notes (ignored includes, unsupported imports).
    public let warnings: [String]
    /// Loaded rules that can be reported (not private).
    public let activeRuleCount: Int

    private let program: YaraProgram

    /// Compiles `source`. Never fails: unreadable or unsupported rules end up in `skipped`.
    public init(source: String, origin: String) {
        self.origin = origin
        let program = YaraCompiler.compile(YaraParser.parse(source))
        self.program = program
        rules = program.rules.filter(\.isLoaded).map(\.info)
        skipped = program.skipped
        imports = program.imports
        warnings = program.warnings
        activeRuleCount = rules.filter { !$0.isPrivate }.count
    }

    /// Compiles rule file bytes (invalid UTF-8 is replaced, so it can only break the rules it is in).
    public init(data: Data, origin: String) {
        self.init(source: String(decoding: data, as: UTF8.self), origin: origin)
    }

    /// A rule set with no rules.
    public static let empty = YaraRuleSet(source: "", origin: "")

    public var isEmpty: Bool { activeRuleCount == 0 }

    /// Scans a buffer. `fileSize` is the real size of the file when `data` is only its start
    /// (it drives `filesize`; strings are only searched in `data`).
    public func scan(_ data: Data, fileSize: Int? = nil) -> [YaraRuleMatch] {
        scanDetailed(data, fileSize: fileSize).matches
    }

    /// Like `scan`, with the scan's notes and sizes.
    public func scanDetailed(_ data: Data, fileSize: Int? = nil, limits: YaraScanLimits = .standard) -> YaraScanResult {
        let size = max(fileSize ?? data.count, data.count)
        guard activeRuleCount > 0 else {
            return YaraScanResult(matches: [], bytesScanned: data.count, fileSize: size, notes: [])
        }
        return data.withUnsafeBytes { raw in
            run(raw.bindMemory(to: UInt8.self), fileSize: size, limits: limits)
        }
    }

    /// Scans the first `maxBytes` of a regular file (symlinks are not followed). `filesize`
    /// is the file's real size; strings past `maxBytes` are not seen, `uint32(…)` reads past
    /// them are undefined, and hashes of ranges past them are undefined (so whole-file hash
    /// rules only match when the whole file fits in `maxBytes`). Returns no matches when
    /// the file can't be read.
    public func scanFile(atPath path: String, maxBytes: Int) -> [YaraRuleMatch] {
        scanFileDetailed(atPath: path, maxBytes: maxBytes)?.matches ?? []
    }

    /// Like `scanFile`, or nil when the file isn't a readable regular file.
    public func scanFileDetailed(atPath path: String, maxBytes: Int, limits: YaraScanLimits = .standard) -> YaraScanResult? {
        guard let (data, size) = Self.readPrefix(ofFile: path, maxBytes: maxBytes) else { return nil }
        return scanDetailed(data, fileSize: size, limits: limits)
    }

    /// Reads up to `maxBytes` of a regular file without following symlinks or blocking on
    /// special files, for scanning the same bytes with several rule sets
    /// (`scan(data, fileSize: fileSize)`). Nil when the file can't be read.
    public static func readPrefix(ofFile path: String, maxBytes: Int) -> (data: Data, fileSize: Int)? {
        read(path, maxBytes: maxBytes)
    }

    // MARK: Scanning

    private func run(_ bytes: UnsafeBufferPointer<UInt8>, fileSize: Int, limits: YaraScanLimits) -> YaraScanResult {
        let search = YaraSearch(program: program, data: bytes, limits: limits)
        let matches = search.run()
        let evaluator = YaraEvaluator(program: program, data: bytes, fileSize: Int64(fileSize), matches: matches,
                                      limits: limits)
        var results: [YaraRuleMatch] = []
        // Rules run dependencies first, so a rule reference is answered from the memo;
        // then global rules gate everything.
        for index in program.order { _ = evaluator.ruleMatches(index) }
        let globalsHold = program.order.allSatisfy { !program.rules[$0].info.isGlobal || evaluator.ruleMatches($0) }
        if globalsHold {
            for (index, rule) in program.rules.enumerated()
            where rule.isLoaded && !rule.info.isPrivate && evaluator.ruleMatches(index) {
                results.append(YaraRuleMatch(name: rule.info.name, tags: rule.info.tags, meta: rule.info.meta, origin: origin))
            }
        }
        return YaraScanResult(matches: results, bytesScanned: bytes.count, fileSize: fileSize,
                              notes: search.notes + evaluator.notes)
    }

    private static func read(_ path: String, maxBytes: Int) -> (Data, Int)? {
        var info = stat()
        guard lstat(path, &info) == 0, isRegular(info) else { return nil }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard fstat(fd, &info) == 0, isRegular(info) else { return nil }
        let size = Int(info.st_size)
        let wanted = max(0, min(size, maxBytes))
        var data = Data(count: wanted)
        var done = 0
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            while done < wanted {
                let count = pread(fd, base + done, wanted - done, off_t(done))
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if count == 0 { break }
                done += count
            }
            return true
        }
        guard ok else { return nil }
        if done < wanted { data.removeSubrange(done..<wanted) }
        return (data, max(size, done))
    }

    private static func isRegular(_ info: stat) -> Bool {
        UInt32(info.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG)
    }
}
