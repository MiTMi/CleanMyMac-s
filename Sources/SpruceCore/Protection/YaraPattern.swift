import Foundation

// Compiled form of YARA strings. Every string becomes one or more "chains" (one per
// ascii/wide form); a chain is a list of segments joined by large or unbounded jumps, and a
// segment is a list of elements matched by bounded backtracking. Each segment gets a short
// literal "atom" that the Aho–Corasick pass looks for; candidates are then verified around it.

/// One byte of a pattern.
struct YaraPatternByte: Sendable, Hashable {
    enum Mode: UInt8, Sendable, Hashable {
        /// `byte & mask == value` (exact bytes, `??`, `4?`, `?4`).
        case masked
        /// `byte & mask != value` (`~4A`, `~?4`).
        case negated
        /// ASCII letter in either case; `value` is the lowercase letter.
        case caseless
    }

    var value: UInt8
    var mask: UInt8
    var mode: Mode

    static func exact(_ value: UInt8) -> YaraPatternByte { YaraPatternByte(value: value, mask: 0xFF, mode: .masked) }

    @inline(__always)
    func matches(_ byte: UInt8) -> Bool {
        switch mode {
        case .masked: return byte & mask == value
        case .negated: return byte & mask != value
        case .caseless: return byte | 0x20 == value
        }
    }

    /// Fully specified, so usable in an atom.
    var isLiteral: Bool { mode == .caseless || (mode == .masked && mask == 0xFF) }
}

enum YaraPatternElement: Sendable, Hashable {
    /// Consecutive bytes (wildcards included).
    case run([YaraPatternByte])
    /// A bounded jump `[min-max]`.
    case jump(Int, Int)
    /// `( a | b | … )`.
    case alternatives([[YaraPatternElement]])

    /// The same elements in reverse order, for matching backwards from an atom.
    static func reversed(_ elements: [YaraPatternElement]) -> [YaraPatternElement] {
        elements.reversed().map { element in
            switch element {
            case .run(let bytes): return .run(bytes.reversed())
            case .jump: return element
            case .alternatives(let branches): return .alternatives(branches.map(reversed))
            }
        }
    }
}

/// Distance between two segments of a chain (from the end of one to the start of the next).
struct YaraGap: Sendable, Hashable {
    var min: Int
    /// nil = unbounded (`[-]`, `[n-]`).
    var max: Int?
}

/// A piece of a string matched on its own.
struct YaraSegment: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case pattern([YaraPatternElement])
        /// Text tried with every single-byte XOR key in the range.
        case xor([UInt8], ClosedRange<Int>)
        /// A regular expression (`YaraRegex`).
        case regex(YaraRegex)
    }

    var kind: Kind
    /// Text strings with `fullword` must not touch letters or digits on either side.
    var fullword: Bool
    /// The `wide` form (decides how `fullword` looks at neighbours).
    var wide: Bool
}

/// One way a string can match: its segments, joined by gaps.
struct YaraChain: Sendable, Hashable {
    var segments: [YaraSegment]
    var gaps: [YaraGap]
}

/// How to verify a segment around an atom found at a given position.
struct YaraMatchPlan: Sendable {
    var segment: Int
    /// Elements matched forwards from the atom's first byte.
    var forward: [YaraPatternElement]
    /// Elements before the atom, reversed, matched backwards from the atom's first byte.
    var backward: [YaraPatternElement]
    /// For a regular expression: the expression, matched forwards from each possible start.
    var regex: YaraRegex? = nil
    /// For a regular expression: how many bytes before the atom a match may start.
    var regexLead: ClosedRange<Int> = 0...0
}

/// Problem with a rule found while compiling it (the rule is skipped with this reason).
struct YaraCompileIssue: Error, Sendable {
    let reason: String
}

// MARK: - Hex strings

enum YaraHexParser {
    /// Jumps longer than this (and unbounded ones) split a hex string into chained segments.
    static let chainThreshold = 256
    /// Most jumps and alternatives one hex string may contain.
    static let maxComplexity = 64
    static let maxNesting = 8

    enum Node: Sendable {
        case byte(YaraPatternByte)
        case jump(Int, Int?)
        case group([[Node]])
    }

    /// Parses the text between a hex string's braces into chains-ready segments.
    static func compile(_ body: String) throws -> (segments: [[YaraPatternElement]], gaps: [YaraGap]) {
        var reader = Reader(bytes: Array(body.utf8))
        var complexity = 0
        let nodes = try parseSequence(&reader, depth: 0, complexity: &complexity)
        reader.skipSpace()
        if reader.index < reader.bytes.count {
            throw YaraCompileIssue(reason: "a hex string has an unmatched | or )")
        }
        if complexity > maxComplexity {
            throw YaraCompileIssue(reason: "a hex string has too many jumps and alternatives")
        }
        let merged = mergeJumps(nodes)
        try validate(merged, inGroup: false)

        var segments: [[YaraPatternElement]] = []
        var gaps: [YaraGap] = []
        var pending: [Node] = []
        for node in merged {
            if case .jump(let low, let high) = node, high == nil || high! > chainThreshold {
                segments.append(elements(pending))
                pending = []
                gaps.append(YaraGap(min: low, max: high))
            } else {
                pending.append(node)
            }
        }
        segments.append(elements(pending))
        return (segments, gaps)
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        mutating func skipSpace() {
            while index < bytes.count, bytes[index] == YaraChar.space || bytes[index] == YaraChar.tab
                || bytes[index] == YaraChar.newline || bytes[index] == YaraChar.cr || bytes[index] == 0x0B
                || bytes[index] == 0x0C {
                index += 1
            }
        }

        func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }
    }

    private static func parseSequence(_ reader: inout Reader, depth: Int, complexity: inout Int) throws -> [Node] {
        var nodes: [Node] = []
        while true {
            reader.skipSpace()
            guard let c = reader.peek(), c != YaraChar.pipe, c != YaraChar.closeParen else { break }
            if nodes.count > 100_000 { throw YaraCompileIssue(reason: "a hex string is too long") }
            switch c {
            case YaraChar.openParen:
                guard depth < maxNesting else { throw YaraCompileIssue(reason: "a hex string nests alternatives too deeply") }
                reader.index += 1
                complexity += 1
                var branches: [[Node]] = []
                while true {
                    branches.append(try parseSequence(&reader, depth: depth + 1, complexity: &complexity))
                    reader.skipSpace()
                    guard let delimiter = reader.peek() else {
                        throw YaraCompileIssue(reason: "a hex string has an unclosed (")
                    }
                    reader.index += 1
                    if delimiter == YaraChar.closeParen { break }
                }
                nodes.append(.group(branches))
            case YaraChar.openBracket:
                reader.index += 1
                complexity += 1
                nodes.append(try parseJump(&reader))
            case YaraChar.tilde:
                reader.index += 1
                var byte = try parseByte(&reader)
                guard byte.mask != 0 else { throw YaraCompileIssue(reason: "~?? can never match") }
                byte.mode = .negated
                nodes.append(.byte(byte))
            default:
                nodes.append(.byte(try parseByte(&reader)))
            }
        }
        return nodes
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        if c == YaraChar.question { return nil }
        if c >= YaraChar.zero, c <= YaraChar.zero + 9 { return c - YaraChar.zero }
        if c >= YaraChar.lowerA, c <= YaraChar.lowerA + 5 { return c - YaraChar.lowerA + 10 }
        if c >= YaraChar.upperA, c <= YaraChar.upperA + 5 { return c - YaraChar.upperA + 10 }
        return nil
    }

    private static func parseByte(_ reader: inout Reader) throws -> YaraPatternByte {
        guard reader.index + 1 < reader.bytes.count else {
            throw YaraCompileIssue(reason: "a hex string has an incomplete byte")
        }
        let high = reader.bytes[reader.index]
        let low = reader.bytes[reader.index + 1]
        let valid: (UInt8) -> Bool = { $0 == YaraChar.question || YaraLexer.isHexDigit($0) }
        guard valid(high), valid(low) else {
            throw YaraCompileIssue(reason: "a hex string has an invalid byte")
        }
        reader.index += 2
        var value: UInt8 = 0
        var mask: UInt8 = 0
        if let h = nibble(high) {
            value |= h << 4
            mask |= 0xF0
        }
        if let l = nibble(low) {
            value |= l
            mask |= 0x0F
        }
        return YaraPatternByte(value: value, mask: mask, mode: .masked)
    }

    private static func parseJump(_ reader: inout Reader) throws -> Node {
        func number(_ reader: inout Reader) throws -> Int? {
            reader.skipSpace()
            let start = reader.index
            while let c = reader.peek(), YaraLexer.isDigit(c) { reader.index += 1 }
            guard reader.index > start else { return nil }
            guard let value = Int(String(decoding: reader.bytes[start..<reader.index], as: UTF8.self)),
                  value <= Int(Int32.max) else {
                throw YaraCompileIssue(reason: "a jump in a hex string is too large")
            }
            return value
        }
        let bad = YaraCompileIssue(reason: "a hex string has a malformed jump")
        let low = try number(&reader)
        reader.skipSpace()
        var node: Node
        if reader.peek() == YaraChar.minus {
            reader.index += 1
            let high = try number(&reader)
            if low == nil, high != nil { throw bad }
            if let low, let high, low > high { throw YaraCompileIssue(reason: "a jump in a hex string is backwards") }
            node = .jump(low ?? 0, high)
        } else {
            guard let low else { throw bad }
            node = .jump(low, low)
        }
        reader.skipSpace()
        guard reader.peek() == YaraChar.closeBracket else { throw bad }
        reader.index += 1
        return node
    }

    /// Combines consecutive jumps (`[2][3]` → `[5]`) at every level.
    private static func mergeJumps(_ nodes: [Node]) -> [Node] {
        var out: [Node] = []
        for node in nodes {
            switch node {
            case .jump(let low, let high):
                if case .jump(let previousLow, let previousHigh)? = out.last {
                    out[out.count - 1] = .jump(previousLow + low, previousHigh.flatMap { p in high.map { p + $0 } })
                } else {
                    out.append(node)
                }
            case .group(let branches):
                out.append(.group(branches.map(mergeJumps)))
            case .byte:
                out.append(node)
            }
        }
        return out
    }

    private static func validate(_ nodes: [Node], inGroup: Bool) throws {
        guard let first = nodes.first, let last = nodes.last else {
            throw YaraCompileIssue(reason: inGroup ? "a hex string has an empty alternative" : "a hex string is empty")
        }
        if case .jump = first { throw YaraCompileIssue(reason: "a hex string can't start with a jump") }
        if case .jump = last { throw YaraCompileIssue(reason: "a hex string can't end with a jump") }
        for node in nodes {
            switch node {
            case .jump(_, let high):
                if inGroup, high == nil {
                    throw YaraCompileIssue(reason: "unbounded jumps aren't allowed inside alternatives")
                }
                if inGroup, let high, high > chainThreshold {
                    throw YaraCompileIssue(reason: "jumps inside alternatives must be \(chainThreshold) bytes or shorter")
                }
            case .group(let branches):
                for branch in branches { try validate(branch, inGroup: true) }
            case .byte:
                break
            }
        }
    }

    private static func elements(_ nodes: [Node]) -> [YaraPatternElement] {
        var out: [YaraPatternElement] = []
        var run: [YaraPatternByte] = []
        func flush() {
            if !run.isEmpty {
                out.append(.run(run))
                run = []
            }
        }
        for node in nodes {
            switch node {
            case .byte(let byte):
                run.append(byte)
            case .jump(let low, let high):
                flush()
                out.append(.jump(low, high ?? low))
            case .group(let branches):
                flush()
                out.append(.alternatives(branches.map(elements)))
            }
        }
        flush()
        return out
    }
}

// MARK: - Text strings

enum YaraTextPattern {
    /// The chains for a text string with its modifiers (one per ascii/wide form).
    static func chains(_ text: [UInt8], modifiers: YaraStringModifiers) -> [YaraChain] {
        var forms: [Bool] = []
        if modifiers.ascii || !modifiers.wide { forms.append(false) }
        if modifiers.wide { forms.append(true) }
        return forms.map { wide in
            let bytes = wide ? text.flatMap { [$0, 0] } : text
            let kind: YaraSegment.Kind
            if let keys = modifiers.xor {
                kind = .xor(bytes, keys)
            } else {
                kind = .pattern([.run(bytes.map { byte in
                    modifiers.nocase && isLetter(byte)
                        ? YaraPatternByte(value: byte | 0x20, mask: 0xFF, mode: .caseless)
                        : .exact(byte)
                })])
            }
            return YaraChain(segments: [YaraSegment(kind: kind, fullword: modifiers.fullword, wide: wide)], gaps: [])
        }
    }

    static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= YaraChar.lowerA && byte <= YaraChar.lowerA + 25) || (byte >= YaraChar.upperA && byte <= YaraChar.upperA + 25)
    }

    static func isAlphanumeric(_ byte: UInt8) -> Bool { isLetter(byte) || YaraLexer.isDigit(byte) }
}

// MARK: - Atoms

enum YaraAtoms {
    /// Longest atom (like YARA, four bytes keep the automaton small).
    static let maxLength = 4
    /// Most atoms one segment may add (case variants and alternative prefixes).
    static let maxVariants = 64

    struct Choice {
        var atoms: [[UInt8]]
        var forward: [YaraPatternElement]
        var backward: [YaraPatternElement]
    }

    /// Picks the best literal run of a segment, or nil when it has none (linear scan).
    static func choose(_ elements: [YaraPatternElement]) -> Choice? {
        var best: (score: Int, element: Int, start: Int, length: Int)?
        for (index, element) in elements.enumerated() {
            guard case .run(let bytes) = element else { continue }
            var i = 0
            while i < bytes.count {
                guard bytes[i].isLiteral else {
                    i += 1
                    continue
                }
                var j = i
                while j < bytes.count, bytes[j].isLiteral { j += 1 }
                let length = min(maxLength, j - i)
                for start in i...(j - length) {
                    let value = score(bytes[start..<start + length])
                    if best == nil || value > best!.score { best = (value, index, start, length) }
                }
                i = j
            }
        }
        if let best, case .run(let bytes) = elements[best.element] {
            let atoms = expand(Array(bytes[best.start..<best.start + best.length]))
            if atoms.count <= maxVariants {
                var forward: [YaraPatternElement] = [.run(Array(bytes[best.start...]))]
                forward += elements[(best.element + 1)...]
                var before = Array(elements[..<best.element])
                if best.start > 0 { before.append(.run(Array(bytes[..<best.start]))) }
                return Choice(atoms: atoms, forward: forward, backward: YaraPatternElement.reversed(before))
            }
        }
        // A segment that starts with alternatives can use each branch's literal prefix.
        if case .alternatives(let branches)? = elements.first, let prefixes = literalPrefixes(branches) {
            var atoms: [[UInt8]] = []
            for prefix in prefixes { atoms += expand(prefix) }
            if atoms.count <= maxVariants {
                return Choice(atoms: atoms, forward: elements, backward: [])
            }
        }
        return nil
    }

    /// Higher is better: rare bytes beat common ones (00, FF, spaces, NOPs), variety beats repeats.
    static func score(_ bytes: ArraySlice<YaraPatternByte>) -> Int {
        var total = 0
        var distinct = Set<UInt8>()
        for byte in bytes {
            distinct.insert(byte.value)
            if byte.mode == .caseless {
                total += 16
                continue
            }
            switch byte.value {
            case 0x00, 0xFF: total += 4
            case 0x01, 0x0A, 0x0D, 0x20, 0x90, 0xCC: total += 10
            default: total += 20
            }
        }
        if distinct.count == 1, bytes.count > 1 { total /= 2 }
        return total + distinct.count * 2
    }

    /// Every case combination of an atom's caseless letters.
    static func expand(_ bytes: [YaraPatternByte]) -> [[UInt8]] {
        var out: [[UInt8]] = [[]]
        for byte in bytes {
            if byte.mode == .caseless {
                out = out.flatMap { [$0 + [byte.value], $0 + [byte.value & ~0x20]] }
            } else {
                out = out.map { $0 + [byte.value] }
            }
            if out.count > maxVariants { return out }
        }
        return out
    }

    private static func literalPrefixes(_ branches: [[YaraPatternElement]]) -> [[YaraPatternByte]]? {
        var out: [[YaraPatternByte]] = []
        for branch in branches {
            guard let first = branch.first else { return nil }
            switch first {
            case .run(let bytes):
                let prefix = bytes.prefix(while: \.isLiteral).prefix(maxLength)
                guard !prefix.isEmpty else { return nil }
                out.append(Array(prefix))
            case .alternatives(let inner):
                guard let prefixes = literalPrefixes(inner) else { return nil }
                out += prefixes
            case .jump:
                return nil
            }
            if out.count > maxVariants { return nil }
        }
        return out
    }
}
