import Foundation

// YARA regular-expression strings (`$a = /https?:\/\/[a-z0-9\-\.]+\/curl\//`).
//
// The syntax is YARA's (RE2-like, byte oriented): literals and escapes (`\xHH`, `\n`, `\t`,
// `\r`, `\f`, `\a`, `\v`, escaped punctuation), `.`, classes `[a-z0-9\-]` / `[^\/]`, `\w \W
// \s \S \d \D`, anchors `^ $ \b \B`, groups `( … )` and `(?: … )`, alternation `|`, and the
// quantifiers `* + ? {n} {n,} {,m} {n,m}` with lazy `?` forms. Flags `i` (nocase) and `s`
// (dot matches newline); the `nocase`, `ascii`, `wide`, `fullword` and `private` modifiers.
//
// Matching is bounded backtracking with a step budget, like hex strings. As in YARA, a
// match never extends more than `YaraRegex.scanLimit` bytes from where it starts, so `.*`
// can't run through a whole file. A literal stretch of the expression ("http", "${") feeds
// the shared Aho–Corasick pass; expressions without one are tried at every position whose
// byte can start a match.

/// A set of byte values, one bit each.
struct YaraByteSet: Sendable, Hashable {
    private var w0: UInt64 = 0
    private var w1: UInt64 = 0
    private var w2: UInt64 = 0
    private var w3: UInt64 = 0

    init() {}

    init(_ bytes: [UInt8]) {
        for byte in bytes { insert(byte) }
    }

    static let all: YaraByteSet = YaraByteSet().inverted()

    @inline(__always)
    func contains(_ byte: UInt8) -> Bool {
        let bit = UInt64(1) << UInt64(byte & 63)
        switch byte >> 6 {
        case 0: return w0 & bit != 0
        case 1: return w1 & bit != 0
        case 2: return w2 & bit != 0
        default: return w3 & bit != 0
        }
    }

    mutating func insert(_ byte: UInt8) {
        let bit = UInt64(1) << UInt64(byte & 63)
        switch byte >> 6 {
        case 0: w0 |= bit
        case 1: w1 |= bit
        case 2: w2 |= bit
        default: w3 |= bit
        }
    }

    mutating func insert(_ range: ClosedRange<UInt8>) {
        for byte in range { insert(byte) }
    }

    mutating func formUnion(_ other: YaraByteSet) {
        w0 |= other.w0
        w1 |= other.w1
        w2 |= other.w2
        w3 |= other.w3
    }

    func inverted() -> YaraByteSet {
        var out = YaraByteSet()
        out.w0 = ~w0
        out.w1 = ~w1
        out.w2 = ~w2
        out.w3 = ~w3
        return out
    }

    var count: Int { w0.nonzeroBitCount + w1.nonzeroBitCount + w2.nonzeroBitCount + w3.nonzeroBitCount }

    var isEmpty: Bool { w0 | w1 | w2 | w3 == 0 }

    /// The values in the set, in order.
    var members: [UInt8] { (0...255).compactMap { contains(UInt8($0)) ? UInt8($0) : nil } }

    /// The same set with the other case of every ASCII letter added.
    func addingOtherCase() -> YaraByteSet {
        var out = self
        for byte in UInt8(ascii: "A")...UInt8(ascii: "Z") where contains(byte) || contains(byte | 0x20) {
            out.insert(byte)
            out.insert(byte | 0x20)
        }
        return out
    }

    /// The set as one pattern byte when it is a single value, or one letter in both cases
    /// (so it can be part of an atom); nil otherwise.
    var literalByte: YaraPatternByte? {
        switch count {
        case 1:
            return members.first.map(YaraPatternByte.exact)
        case 2:
            let values = members
            let lower = values[1]
            if values[0] | 0x20 == lower, YaraTextPattern.isLetter(lower), lower == values[0] + 0x20 {
                return YaraPatternByte(value: lower, mask: 0xFF, mode: .caseless)
            }
            return nil
        default:
            return nil
        }
    }

    static let word: YaraByteSet = {
        var set = YaraByteSet()
        set.insert(UInt8(ascii: "a")...UInt8(ascii: "z"))
        set.insert(UInt8(ascii: "A")...UInt8(ascii: "Z"))
        set.insert(UInt8(ascii: "0")...UInt8(ascii: "9"))
        set.insert(UInt8(ascii: "_"))
        return set
    }()

    static let digit: YaraByteSet = {
        var set = YaraByteSet()
        set.insert(UInt8(ascii: "0")...UInt8(ascii: "9"))
        return set
    }()

    static let space = YaraByteSet([0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D])
}

/// A compiled regular expression node.
indirect enum YaraRegexNode: Sendable, Hashable {
    /// Matches nothing (zero width).
    case empty
    /// Consecutive single-unit matches.
    case run([YaraByteSet])
    case sequence([YaraRegexNode])
    case alternation([YaraRegexNode])
    /// A one-unit set repeated (`[a-z]{3,7}`, `.*`): matched without recursion.
    case repeatSet(YaraByteSet, min: Int, max: Int, greedy: Bool)
    /// Any other node repeated (`( … ){5,}`).
    case repeatNode(YaraRegexNode, min: Int, max: Int, greedy: Bool)
    /// `^`: the start of the scanned data.
    case start
    /// `$`: the end of the scanned data.
    case end
    /// `\b` (true) or `\B` (false).
    case wordBoundary(Bool)
}

// MARK: - Parser

enum YaraRegexParser {
    /// Most nodes one expression may have (real rules use a handful).
    static let maxNodes = 512
    /// Deepest group nesting.
    static let maxNesting = 16

    /// Parses a regular expression body (between the slashes, escapes kept as written).
    static func parse(_ body: [UInt8], caseless: Bool, dotAll: Bool) throws -> YaraRegexNode {
        var parser = Parser(bytes: body, caseless: caseless, dotAll: dotAll)
        let node = try parser.parseAlternation(depth: 0)
        if parser.index < body.count {
            throw YaraCompileIssue(reason: "the regular expression has an unmatched )")
        }
        return node
    }

    private struct Parser {
        let bytes: [UInt8]
        let caseless: Bool
        let dotAll: Bool
        var index = 0
        var nodes = 0

        init(bytes: [UInt8], caseless: Bool, dotAll: Bool) {
            self.bytes = bytes
            self.caseless = caseless
            self.dotAll = dotAll
        }

        func peek(_ offset: Int = 0) -> UInt8? {
            index + offset < bytes.count ? bytes[index + offset] : nil
        }

        mutating func count() throws {
            nodes += 1
            if nodes > maxNodes { throw YaraCompileIssue(reason: "the regular expression is too complex") }
        }

        mutating func parseAlternation(depth: Int) throws -> YaraRegexNode {
            var branches = [try parseSequence(depth: depth)]
            while peek() == UInt8(ascii: "|") {
                index += 1
                branches.append(try parseSequence(depth: depth))
            }
            return branches.count == 1 ? branches[0] : .alternation(branches)
        }

        mutating func parseSequence(depth: Int) throws -> YaraRegexNode {
            var items: [YaraRegexNode] = []
            while let c = peek(), c != UInt8(ascii: "|"), c != UInt8(ascii: ")") {
                var atom = try parseAtom(depth: depth)
                atom = try parseQuantifiers(atom)
                items.append(atom)
            }
            return Self.simplify(items)
        }

        /// Flattens nested sequences and merges neighbouring runs.
        static func simplify(_ items: [YaraRegexNode]) -> YaraRegexNode {
            var out: [YaraRegexNode] = []
            func add(_ node: YaraRegexNode) {
                switch node {
                case .empty:
                    break
                case .sequence(let inner):
                    inner.forEach(add)
                case .run(let sets):
                    if case .run(let previous)? = out.last {
                        out[out.count - 1] = .run(previous + sets)
                    } else {
                        out.append(node)
                    }
                default:
                    out.append(node)
                }
            }
            items.forEach(add)
            switch out.count {
            case 0: return .empty
            case 1: return out[0]
            default: return .sequence(out)
            }
        }

        func literal(_ byte: UInt8) -> YaraRegexNode {
            var set = YaraByteSet([byte])
            if caseless { set = set.addingOtherCase() }
            return .run([set])
        }

        mutating func parseAtom(depth: Int) throws -> YaraRegexNode {
            guard let c = peek() else { throw YaraCompileIssue(reason: "the regular expression ends too early") }
            try count()
            switch c {
            case UInt8(ascii: "("):
                guard depth < maxNesting else {
                    throw YaraCompileIssue(reason: "the regular expression nests groups too deeply")
                }
                index += 1
                if peek() == UInt8(ascii: "?"), peek(1) == UInt8(ascii: ":") { index += 2 }
                let inner = try parseAlternation(depth: depth + 1)
                guard peek() == UInt8(ascii: ")") else {
                    throw YaraCompileIssue(reason: "the regular expression has an unclosed (")
                }
                index += 1
                return inner
            case UInt8(ascii: "["):
                index += 1
                return .run([try parseClass()])
            case UInt8(ascii: "."):
                index += 1
                if dotAll { return .run([.all]) }
                var set = YaraByteSet([0x0A])
                set = set.inverted()
                return .run([set])
            case UInt8(ascii: "^"):
                index += 1
                return .start
            case UInt8(ascii: "$"):
                index += 1
                return .end
            case UInt8(ascii: "\\"):
                index += 1
                return try parseEscape()
            case UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "?"):
                throw YaraCompileIssue(reason: "the regular expression repeats nothing")
            default:
                index += 1
                return literal(c)
            }
        }

        mutating func parseEscape() throws -> YaraRegexNode {
            guard let c = peek() else { throw YaraCompileIssue(reason: "the regular expression ends with \\") }
            index += 1
            switch c {
            case UInt8(ascii: "b"): return .wordBoundary(true)
            case UInt8(ascii: "B"): return .wordBoundary(false)
            default:
                index -= 1
                let set = try parseEscapedSet()
                return .run([set])
            }
        }

        /// An escape that stands for bytes (outside or inside a class), `\` already read.
        mutating func parseEscapedSet() throws -> YaraByteSet {
            guard let c = peek() else { throw YaraCompileIssue(reason: "the regular expression ends with \\") }
            index += 1
            var set: YaraByteSet
            switch c {
            case UInt8(ascii: "w"): return .word
            case UInt8(ascii: "W"): return YaraByteSet.word.inverted()
            case UInt8(ascii: "s"): return .space
            case UInt8(ascii: "S"): return YaraByteSet.space.inverted()
            case UInt8(ascii: "d"): return .digit
            case UInt8(ascii: "D"): return YaraByteSet.digit.inverted()
            case UInt8(ascii: "n"): set = YaraByteSet([0x0A])
            case UInt8(ascii: "t"): set = YaraByteSet([0x09])
            case UInt8(ascii: "r"): set = YaraByteSet([0x0D])
            case UInt8(ascii: "f"): set = YaraByteSet([0x0C])
            case UInt8(ascii: "a"): set = YaraByteSet([0x07])
            case UInt8(ascii: "v"): set = YaraByteSet([0x0B])
            case UInt8(ascii: "x"):
                guard let high = peek(), let low = peek(1), YaraLexer.isHexDigit(high), YaraLexer.isHexDigit(low) else {
                    throw YaraCompileIssue(reason: "the regular expression has a malformed \\x escape")
                }
                index += 2
                let value = UInt8(String(decoding: [high, low], as: UTF8.self), radix: 16) ?? 0
                set = YaraByteSet([value])
            default:
                if YaraTextPattern.isAlphanumeric(c) {
                    throw YaraCompileIssue(reason: "the regular expression uses \\\(Character(UnicodeScalar(c))), which Spruce doesn't support")
                }
                set = YaraByteSet([c])
            }
            return caseless ? set.addingOtherCase() : set
        }

        /// A character class, `[` already read.
        mutating func parseClass() throws -> YaraByteSet {
            var negate = false
            if peek() == UInt8(ascii: "^") {
                negate = true
                index += 1
            }
            var set = YaraByteSet()
            var first = true
            while true {
                guard let c = peek() else { throw YaraCompileIssue(reason: "the regular expression has an unclosed [") }
                if c == UInt8(ascii: "]"), !first {
                    index += 1
                    break
                }
                first = false
                // One member: a byte (possibly the start of a range) or a whole escape class.
                var low: UInt8?
                if c == UInt8(ascii: "\\") {
                    index += 1
                    let escaped = try parseClassEscape()
                    if escaped.count == 1, let only = escaped.members.first {
                        low = only
                    } else {
                        set.formUnion(escaped)
                        continue
                    }
                } else {
                    index += 1
                    low = c
                }
                guard let start = low else { continue }
                if peek() == UInt8(ascii: "-"), let next = peek(1), next != UInt8(ascii: "]") {
                    index += 1
                    var high: UInt8
                    if next == UInt8(ascii: "\\") {
                        index += 1
                        let escaped = try parseClassEscape()
                        guard escaped.count == 1, let only = escaped.members.first else {
                            throw YaraCompileIssue(reason: "the regular expression has a malformed range in [ ]")
                        }
                        high = only
                    } else {
                        index += 1
                        high = next
                    }
                    guard start <= high else {
                        throw YaraCompileIssue(reason: "the regular expression has a backwards range in [ ]")
                    }
                    set.insert(start...high)
                } else {
                    set.insert(start)
                }
            }
            if caseless { set = set.addingOtherCase() }
            if negate { set = set.inverted() }
            if set.isEmpty { throw YaraCompileIssue(reason: "the regular expression has a class that matches nothing") }
            return set
        }

        /// An escape inside a class (no case folding yet; the class folds as a whole).
        mutating func parseClassEscape() throws -> YaraByteSet {
            guard let c = peek() else { throw YaraCompileIssue(reason: "the regular expression has an unclosed [") }
            switch c {
            case UInt8(ascii: "b"):
                index += 1
                return YaraByteSet([0x08])
            default:
                // Parse without case folding: the whole class is folded afterwards.
                var plain = Parser(bytes: bytes, caseless: false, dotAll: dotAll)
                plain.index = index
                let set = try plain.parseEscapedSet()
                index = plain.index
                return set
            }
        }

        /// Quantifiers after an atom (`*`, `+`, `?`, `{n,m}`, each optionally lazy).
        mutating func parseQuantifiers(_ atom: YaraRegexNode) throws -> YaraRegexNode {
            var node = atom
            while let c = peek() {
                var low = 0
                var high: Int?
                switch c {
                case UInt8(ascii: "*"):
                    index += 1
                case UInt8(ascii: "+"):
                    index += 1
                    low = 1
                case UInt8(ascii: "?"):
                    index += 1
                    high = 1
                case UInt8(ascii: "{"):
                    guard let bounds = try parseBraces() else { return node }
                    (low, high) = bounds
                default:
                    return node
                }
                var greedy = true
                if peek() == UInt8(ascii: "?") {
                    index += 1
                    greedy = false
                }
                node = try Self.repeated(node, low, high, greedy)
            }
            return node
        }

        /// `{n}`, `{n,}`, `{,m}` or `{n,m}`; nil (and nothing read) when the brace is a literal.
        mutating func parseBraces() throws -> (Int, Int?)? {
            var cursor = index + 1
            func number() -> Int? {
                let start = cursor
                while cursor < bytes.count, YaraLexer.isDigit(bytes[cursor]) { cursor += 1 }
                guard cursor > start, cursor - start <= 6 else { return nil }
                return Int(String(decoding: bytes[start..<cursor], as: UTF8.self))
            }
            let low = number()
            var high: Int?
            var hasComma = false
            if cursor < bytes.count, bytes[cursor] == UInt8(ascii: ",") {
                hasComma = true
                cursor += 1
                high = number()
            }
            guard cursor < bytes.count, bytes[cursor] == UInt8(ascii: "}") else { return nil }
            if low == nil, high == nil { return nil }
            index = cursor + 1
            let min = low ?? 0
            let max = hasComma ? high : min
            if let max, max < min {
                throw YaraCompileIssue(reason: "the regular expression has a backwards repeat count")
            }
            return (min, max)
        }

        static func repeated(_ node: YaraRegexNode, _ low: Int, _ high: Int?, _ greedy: Bool) throws -> YaraRegexNode {
            switch node {
            case .empty, .start, .end, .wordBoundary:
                throw YaraCompileIssue(reason: "the regular expression repeats something that has no width")
            default:
                break
            }
            guard low <= YaraRegex.scanLimit else {
                throw YaraCompileIssue(reason: "the regular expression repeats more than \(YaraRegex.scanLimit) times")
            }
            let max = min(high ?? YaraRegex.scanLimit, YaraRegex.scanLimit)
            if low == 1, max == 1 { return node }
            if case .run(let sets) = node, sets.count == 1 {
                // Small fixed counts become plain runs ("[a-z]{1}", "\d{4}") so they can join atoms.
                if low == max, low <= 8 { return .run(Array(repeating: sets[0], count: low)) }
                return .repeatSet(sets[0], min: low, max: max, greedy: greedy)
            }
            guard low <= YaraRegex.maxGroupRepeats else {
                throw YaraCompileIssue(reason: "the regular expression repeats a group more than \(YaraRegex.maxGroupRepeats) times")
            }
            return .repeatNode(node, min: low, max: max, greedy: greedy)
        }
    }
}

// MARK: - Compiled expression

/// A regular expression ready to match, with what the search needs to find candidates.
struct YaraRegex: Sendable, Hashable {
    /// Furthest a match may extend from its start, in characters (YARA's RE_SCAN_LIMIT).
    static let scanLimit = 4_096
    /// Most iterations of a repeated group in one match.
    static let maxGroupRepeats = 64
    /// Most start positions tried around one atom.
    static let maxLeadWindow = 256

    /// A literal stretch every match contains, at a bounded distance from the match start.
    struct Atom: Sendable, Hashable {
        var bytes: [YaraPatternByte]
        /// Bytes between the match start and the atom (smallest and largest).
        var leadMin: Int
        var leadMax: Int
    }

    var root: YaraRegexNode
    /// Each character is followed by a zero byte (UTF-16LE text).
    var wide: Bool
    /// Bytes a match can start with.
    var firstBytes: YaraByteSet
    /// Starts with `^`, so it can only match at offset 0.
    var anchoredAtStart: Bool
    var atom: Atom?
    /// Bytes every match must contain somewhere (the rarest required character), so starts
    /// with none of them within reach can be skipped without trying; nil when unhelpful.
    var required: YaraByteSet?

    init(root: YaraRegexNode, wide: Bool) throws {
        self.root = root
        self.wide = wide
        let first = Self.first(root)
        if first.nullable {
            throw YaraCompileIssue(reason: "the regular expression can match nothing at all")
        }
        firstBytes = first.set
        let items = Self.items(root)
        if case .start? = items.first { anchoredAtStart = true } else { anchoredAtStart = false }
        atom = Self.chooseAtom(items, wide: wide)
        required = Self.requiredSet(items)
    }

    /// The smallest set of a character every match consumes (top-level runs and repeats with
    /// a minimum of one), or nil when every such set allows most bytes.
    static func requiredSet(_ items: [YaraRegexNode]) -> YaraByteSet? {
        var best: YaraByteSet?
        func consider(_ set: YaraByteSet) {
            if best == nil || set.count <= best!.count { best = set }
        }
        for item in items {
            switch item {
            case .run(let sets): sets.forEach(consider)
            case .repeatSet(let set, let low, _, _) where low >= 1: consider(set)
            default: break
            }
        }
        guard let best, best.count <= 128 else { return nil }
        return best
    }

    // MARK: Analysis

    static func items(_ node: YaraRegexNode) -> [YaraRegexNode] {
        if case .sequence(let items) = node { return items }
        return [node]
    }

    /// Bytes a match can start with, and whether the node can match without consuming any.
    static func first(_ node: YaraRegexNode) -> (set: YaraByteSet, nullable: Bool) {
        switch node {
        case .empty, .start, .end, .wordBoundary:
            return (YaraByteSet(), true)
        case .run(let sets):
            return (sets.first ?? YaraByteSet(), sets.isEmpty)
        case .sequence(let items):
            var set = YaraByteSet()
            for item in items {
                let part = first(item)
                set.formUnion(part.set)
                if !part.nullable { return (set, false) }
            }
            return (set, true)
        case .alternation(let branches):
            var set = YaraByteSet()
            var nullable = false
            for branch in branches {
                let part = first(branch)
                set.formUnion(part.set)
                nullable = nullable || part.nullable
            }
            return (set, nullable)
        case .repeatSet(let set, let low, _, _):
            return (set, low == 0)
        case .repeatNode(let inner, let low, _, _):
            let part = first(inner)
            return (part.set, low == 0 || part.nullable)
        }
    }

    /// Smallest and largest number of characters a node consumes (nil = no bound).
    static func length(_ node: YaraRegexNode) -> (min: Int, max: Int?) {
        switch node {
        case .empty, .start, .end, .wordBoundary:
            return (0, 0)
        case .run(let sets):
            return (sets.count, sets.count)
        case .sequence(let items):
            var low = 0
            var high: Int? = 0
            for item in items {
                let part = length(item)
                low += part.min
                if let h = high, let p = part.max { high = h + p } else { high = nil }
            }
            return (low, high)
        case .alternation(let branches):
            let parts = branches.map(length)
            let low = parts.map(\.min).min() ?? 0
            let high: Int? = parts.contains { $0.max == nil } ? nil : parts.compactMap(\.max).max() ?? 0
            return (low, high)
        case .repeatSet(_, let low, let high, _):
            return (low, high)
        case .repeatNode(let inner, let low, let high, _):
            let part = length(inner)
            return (low * part.min, part.max.map { $0 * min(high, maxGroupRepeats) })
        }
    }

    /// Picks the best literal stretch at a bounded distance from the start, looking into
    /// groups and into the first iteration of repeated groups.
    static func chooseAtom(_ items: [YaraRegexNode], wide: Bool) -> Atom? {
        let unit = wide ? 2 : 1
        let maxUnits = wide ? 2 : YaraAtoms.maxLength
        var best: (score: Int, atom: Atom)?

        func consider(_ literals: [YaraPatternByte], prefixMin: Int, prefixMax: Int) {
            let length = min(maxUnits, literals.count)
            guard length >= 1, length * unit >= 2 else { return }
            for start in 0...(literals.count - length) {
                let window = Array(literals[start..<start + length])
                let bytes = wide ? window.flatMap { [$0, .exact(0)] } : window
                let leadMin = (prefixMin + start) * unit
                let leadMax = (prefixMax + start) * unit
                guard leadMax - leadMin <= maxLeadWindow else { continue }
                guard YaraAtoms.expand(bytes).count <= YaraAtoms.maxVariants else { continue }
                // Short leads are cheaper to verify, so they win ties.
                let value = YaraAtoms.score(bytes[...]) * 4 - min(leadMax - leadMin, 64)
                if best == nil || value > best!.score {
                    best = (value, Atom(bytes: bytes, leadMin: leadMin, leadMax: leadMax))
                }
            }
        }

        /// Walks a sequence starting `prefixMin...prefixMax` characters after the match start.
        func walk(_ items: [YaraRegexNode], prefixMin: Int, prefixMax: Int?, depth: Int) {
            var low = prefixMin
            var high = prefixMax
            for item in items {
                guard let currentHigh = high else { return }
                switch item {
                case .run(let sets):
                    var k = 0
                    while k < sets.count {
                        guard sets[k].literalByte != nil else {
                            k += 1
                            continue
                        }
                        var literals: [YaraPatternByte] = []
                        var j = k
                        while j < sets.count, let byte = sets[j].literalByte {
                            literals.append(byte)
                            j += 1
                        }
                        consider(literals, prefixMin: low + k, prefixMax: currentHigh + k)
                        k = j
                    }
                case .sequence(let inner) where depth < 8:
                    walk(inner, prefixMin: low, prefixMax: currentHigh, depth: depth + 1)
                case .repeatNode(let inner, let count, _, _) where count >= 1 && depth < 8:
                    // Every match contains the first iteration, right here.
                    walk(Self.items(inner), prefixMin: low, prefixMax: currentHigh, depth: depth + 1)
                default:
                    break
                }
                let part = length(item)
                low += part.min
                if let p = part.max { high = currentHigh + p } else { high = nil }
            }
        }

        walk(items, prefixMin: 0, prefixMax: 0, depth: 0)
        return best?.atom
    }
}

// MARK: - Matching

/// Matches a regular expression at a given start, with a step budget.
final class YaraRegexMatcher {
    let data: UnsafeBufferPointer<UInt8>
    let wide: Bool
    var steps: Int
    private(set) var exhausted = false
    private var depth = 0
    private var limit = 0
    private let unit: Int

    /// Deepest recursion allowed (keeps matching well within a background thread's stack).
    static let maxDepth = 300

    init(data: UnsafeBufferPointer<UInt8>, wide: Bool, steps: Int) {
        self.data = data
        self.wide = wide
        self.steps = steps
        unit = wide ? 2 : 1
    }

    /// End of the first match starting at `start` (greedy and lazy preferences respected),
    /// or nil when there is none or the budget ran out.
    func match(_ node: YaraRegexNode, at start: Int) -> Int? {
        guard start >= 0, start <= data.count, !exhausted else { return nil }
        let room = YaraRegex.scanLimit * unit
        limit = start > data.count - room ? data.count : start + room
        var end: Int?
        _ = m(node, start) { found in
            end = found
            return true
        }
        return exhausted ? nil : end
    }

    @inline(__always)
    private func unitMatches(_ set: YaraByteSet, _ position: Int) -> Bool {
        guard position >= 0, position + unit <= limit, set.contains(data[position]) else { return false }
        return !wide || data[position + 1] == 0
    }

    private func isWordUnit(at position: Int) -> Bool {
        guard position >= 0, position + unit <= data.count, YaraByteSet.word.contains(data[position]) else { return false }
        return !wide || data[position + 1] == 0
    }

    private func isWordUnit(endingAt position: Int) -> Bool {
        isWordUnit(at: position - unit)
    }

    /// Calls `found` with each end position of `node` from `position`, in preference order,
    /// until it returns true. Returns true when stopped (by `found` or the budget).
    private func m(_ node: YaraRegexNode, _ position: Int, _ found: (Int) -> Bool) -> Bool {
        if steps <= 0 || depth >= Self.maxDepth {
            exhausted = true
            return true
        }
        steps -= 1
        depth += 1
        defer { depth -= 1 }
        switch node {
        case .empty:
            return found(position)
        case .run(let sets):
            var next = position
            for set in sets {
                guard unitMatches(set, next) else { return false }
                next += unit
            }
            steps -= sets.count >> 4
            return found(next)
        case .sequence(let items):
            return sequence(items, 0, position, found)
        case .alternation(let branches):
            for branch in branches where m(branch, position, found) { return true }
            return false
        case .repeatSet(let set, let low, let high, let greedy):
            var count = 0
            var next = position
            while count < high, unitMatches(set, next) {
                count += 1
                next += unit
            }
            steps -= count >> 4
            guard count >= low else { return false }
            if greedy {
                var c = count
                while c >= low {
                    if found(position + c * unit) { return true }
                    c -= 1
                }
            } else {
                for c in low...count where found(position + c * unit) { return true }
            }
            return false
        case .repeatNode(let inner, let low, let high, let greedy):
            return repeatNode(inner, low, high, greedy, 0, position, found)
        case .start:
            return position == 0 ? found(position) : false
        case .end:
            return position == data.count ? found(position) : false
        case .wordBoundary(let wanted):
            let boundary = isWordUnit(endingAt: position) != isWordUnit(at: position)
            return boundary == wanted ? found(position) : false
        }
    }

    private func sequence(_ items: [YaraRegexNode], _ index: Int, _ position: Int, _ found: (Int) -> Bool) -> Bool {
        if index == items.count { return found(position) }
        return m(items[index], position) { next in
            self.sequence(items, index + 1, next, found)
        }
    }

    private func repeatNode(_ node: YaraRegexNode, _ low: Int, _ high: Int, _ greedy: Bool, _ count: Int,
                            _ position: Int, _ found: (Int) -> Bool) -> Bool {
        if steps <= 0 {
            exhausted = true
            return true
        }
        steps -= 1
        let canStop = count >= low
        if !greedy, canStop, found(position) { return true }
        if count < high, count < YaraRegex.maxGroupRepeats {
            let stopped = m(node, position) { next in
                // An iteration that consumed nothing can't make progress once enough were seen.
                if next == position, canStop { return false }
                return self.repeatNode(node, low, high, greedy, count + 1, next, found)
            }
            if stopped { return true }
        }
        if greedy, canStop, found(position) { return true }
        return false
    }
}
