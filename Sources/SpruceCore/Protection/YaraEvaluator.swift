import Foundation

// Resolved conditions and their evaluation, following YARA's semantics: values can be
// undefined (an out-of-range `uint32`, a missing `@a[5]`, a division by zero); undefined is
// false in a boolean context, `not undefined` stays undefined, and `and`/`or` treat an
// undefined operand as false.

enum YaraValue: Sendable, Hashable {
    case undefined
    case integer(Int64)
    case float(Double)
    case text([UInt8])
    case boolean(Bool)

    /// Boolean meaning; nil when undefined.
    var truth: Bool? {
        switch self {
        case .undefined: return nil
        case .integer(let value): return value != 0
        case .float(let value): return value != 0
        case .text(let bytes): return !bytes.isEmpty
        case .boolean(let value): return value
        }
    }

    var integer: Int64? {
        switch self {
        case .integer(let value): return value
        case .boolean(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .float(let value): return value
        default: return integer.map(Double.init)
        }
    }
}

/// `uint8` … `int32be`.
struct YaraIntegerRead: Sendable, Hashable {
    var width: Int
    var signed: Bool
    var bigEndian: Bool
}

enum YaraHashFunction: String, Sendable, Hashable {
    case md5, sha1, sha256, crc32, checksum32
}

enum YaraStringRef: Sendable, Hashable {
    /// A string by its index in the program.
    case string(Int)
    /// The string a `for … of` loop is looking at (`$`, `#`, `@`, `!`).
    case current
}

enum YaraAnchor: Sendable {
    case anywhere
    case at(YaraExpr)
    case within(YaraExpr, YaraExpr)
}

enum YaraQuantifier: Sendable {
    case all
    case any
    case none
    case atLeast(YaraExpr)
    case percent(YaraExpr)
}

enum YaraIterable: Sendable {
    case range(YaraExpr, YaraExpr)
    case list([YaraExpr])
}

indirect enum YaraExpr: Sendable {
    case constant(YaraValue)
    case filesize
    case rule(Int)
    case variable(Int)
    case stringMatch(YaraStringRef, YaraAnchor)
    case stringCount(YaraStringRef, YaraAnchor)
    case stringOffset(YaraStringRef, YaraExpr)
    case stringLength(YaraStringRef, YaraExpr)
    case readInteger(YaraIntegerRead, YaraExpr)
    case hashRange(YaraHashFunction, YaraExpr, YaraExpr)
    case hashText(YaraHashFunction, YaraExpr)
    case unary(YaraUnaryOperator, YaraExpr)
    case binary(YaraBinaryOperator, YaraExpr, YaraExpr)
    case and([YaraExpr])
    case or([YaraExpr])
    case not(YaraExpr)
    case defined(YaraExpr)
    case ofStrings(YaraQuantifier, [Int], YaraAnchor)
    case ofRules(YaraQuantifier, [Int])
    case forOf(YaraQuantifier, [Int], YaraExpr)
    case forIn(YaraQuantifier, Int, YaraIterable, YaraExpr)
}

/// Evaluates the conditions of one program against one scan's string matches.
final class YaraEvaluator {
    private let program: YaraProgram
    private let data: UnsafeBufferPointer<UInt8>
    private let fileSize: Int64
    private let matches: [[YaraSpan]]
    private let limits: YaraScanLimits
    /// 0 = not evaluated, 1 = true, 2 = false, 3 = in progress.
    private var ruleState: [UInt8]
    private var variables: [YaraValue]
    private var currentStrings: [Int] = []
    private var hashCache: [HashKey: YaraValue] = [:]
    /// Bytes hashed so far (each distinct range counts in full).
    private var hashedBytes = 0
    private var budget: Int
    private(set) var notes: [String] = []

    private struct HashKey: Hashable {
        var function: YaraHashFunction
        var start: Int
        var end: Int
    }

    init(program: YaraProgram, data: UnsafeBufferPointer<UInt8>, fileSize: Int64, matches: [[YaraSpan]],
         limits: YaraScanLimits) {
        self.program = program
        self.data = data
        self.fileSize = fileSize
        self.matches = matches
        self.limits = limits
        ruleState = Array(repeating: 0, count: program.rules.count)
        variables = Array(repeating: .undefined, count: program.variableSlots)
        budget = max(0, limits.maxTotalSteps)
    }

    private func note(_ text: String) {
        if !notes.contains(text) { notes.append(text) }
    }

    /// Takes `steps` off the budget; false (with a note) once it is used up.
    private func charge(_ steps: Int) -> Bool {
        budget -= steps
        if budget < 0 {
            note("Some conditions were not finished because the scan reached its work limit.")
            return false
        }
        return true
    }

    /// Whether a loaded rule's condition holds (memoised). A rule first reached from inside
    /// another rule's loop runs with its own loop state.
    func ruleMatches(_ index: Int) -> Bool {
        switch ruleState[index] {
        case 1: return true
        case 2, 3: return false
        default:
            ruleState[index] = 3
            let savedVariables = variables
            let savedStrings = currentStrings
            currentStrings = []
            let result = truth(program.rules[index].condition) == true
            variables = savedVariables
            currentStrings = savedStrings
            ruleState[index] = result ? 1 : 2
            return result
        }
    }

    private func truth(_ expr: YaraExpr) -> Bool? { evaluate(expr).truth }

    func evaluate(_ expr: YaraExpr) -> YaraValue {
        budget -= 1
        if budget < 0 {
            note("Some conditions were not finished because the scan reached its work limit.")
            return .undefined
        }
        switch expr {
        case .constant(let value):
            return value
        case .filesize:
            return .integer(fileSize)
        case .rule(let index):
            return .boolean(ruleMatches(index))
        case .variable(let slot):
            return variables[slot]
        case .stringMatch(let ref, let anchor):
            return stringMatch(spans(ref), anchor)
        case .stringCount(let ref, let anchor):
            return stringCount(spans(ref), anchor)
        case .stringOffset(let ref, let index):
            return stringProperty(spans(ref), index) { .integer(Int64($0.start)) }
        case .stringLength(let ref, let index):
            return stringProperty(spans(ref), index) { .integer(Int64($0.end - $0.start)) }
        case .readInteger(let read, let offset):
            return readInteger(read, at: evaluate(offset))
        case .hashRange(let function, let offset, let size):
            return hashRange(function, evaluate(offset), evaluate(size))
        case .hashText(let function, let text):
            guard case .text(let bytes) = evaluate(text) else { return .undefined }
            return bytes.withUnsafeBytes { YaraEvaluator.digest(function, $0) }
        case .unary(let op, let operand):
            return unary(op, evaluate(operand))
        case .binary(let op, let lhs, let rhs):
            return binary(op, evaluate(lhs), evaluate(rhs))
        case .and(let items):
            for item in items where truth(item) != true { return .boolean(false) }
            return .boolean(true)
        case .or(let items):
            for item in items where truth(item) == true { return .boolean(true) }
            return .boolean(false)
        case .not(let operand):
            guard let value = truth(operand) else { return .undefined }
            return .boolean(!value)
        case .defined(let operand):
            return .boolean(evaluate(operand) != .undefined)
        case .ofStrings(let quantifier, let set, let anchor):
            // Each string is work, even when checking it calls nothing else.
            guard charge(set.count) else { return .undefined }
            var count = 0
            for index in set where stringMatch(matches[index], anchor) == .boolean(true) { count += 1 }
            return quantify(quantifier, count, set.count)
        case .ofRules(let quantifier, let rules):
            guard charge(rules.count) else { return .undefined }
            var count = 0
            for index in rules where ruleMatches(index) { count += 1 }
            return quantify(quantifier, count, rules.count)
        case .forOf(let quantifier, let set, let body):
            return loop(quantifier, count: set.count) { index in
                currentStrings.append(set[index])
                defer { currentStrings.removeLast() }
                return truth(body) == true
            }
        case .forIn(let quantifier, let slot, let iterable, let body):
            return forIn(quantifier, slot, iterable, body)
        }
    }

    // MARK: Strings

    private func spans(_ ref: YaraStringRef) -> [YaraSpan] {
        switch ref {
        case .string(let index): return matches[index]
        case .current: return currentStrings.last.map { matches[$0] } ?? []
        }
    }

    /// Index of the first span starting at or after `offset`.
    private func lowerBound(_ spans: [YaraSpan], _ offset: Int64) -> Int {
        var low = 0
        var high = spans.count
        while low < high {
            let mid = (low + high) / 2
            if Int64(spans[mid].start) < offset { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func stringMatch(_ spans: [YaraSpan], _ anchor: YaraAnchor) -> YaraValue {
        switch anchor {
        case .anywhere:
            return .boolean(!spans.isEmpty)
        case .at(let offsetExpr):
            guard let offset = evaluate(offsetExpr).integer else { return .boolean(false) }
            let index = lowerBound(spans, offset)
            return .boolean(index < spans.count && Int64(spans[index].start) == offset)
        case .within(let lowExpr, let highExpr):
            guard let low = evaluate(lowExpr).integer, let high = evaluate(highExpr).integer else {
                return .boolean(false)
            }
            let index = lowerBound(spans, low)
            return .boolean(index < spans.count && Int64(spans[index].start) <= high)
        }
    }

    private func stringCount(_ spans: [YaraSpan], _ anchor: YaraAnchor) -> YaraValue {
        switch anchor {
        case .anywhere, .at:
            return .integer(Int64(spans.count))
        case .within(let lowExpr, let highExpr):
            guard let low = evaluate(lowExpr).integer, let high = evaluate(highExpr).integer else { return .undefined }
            guard high >= low, high < Int64.max else { return .integer(0) }
            return .integer(Int64(max(0, lowerBound(spans, high + 1) - lowerBound(spans, low))))
        }
    }

    private func stringProperty(_ spans: [YaraSpan], _ indexExpr: YaraExpr, _ value: (YaraSpan) -> YaraValue) -> YaraValue {
        guard let index = evaluate(indexExpr).integer, index >= 1, index <= Int64(spans.count) else { return .undefined }
        return value(spans[Int(index) - 1])
    }

    // MARK: Data

    private func readInteger(_ read: YaraIntegerRead, at offsetValue: YaraValue) -> YaraValue {
        guard let offset = offsetValue.integer, offset >= 0, offset <= Int64(data.count - read.width) else {
            return .undefined
        }
        let start = Int(offset)
        var raw: UInt64 = 0
        for k in 0..<read.width {
            let byte = UInt64(data[start + k])
            if read.bigEndian {
                raw = raw << 8 | byte
            } else {
                raw |= byte << UInt64(8 * k)
            }
        }
        if read.signed {
            let shift = UInt64(64 - 8 * read.width)
            return .integer(Int64(bitPattern: raw << shift) >> Int64(shift))
        }
        return .integer(Int64(bitPattern: raw))
    }

    /// Like YARA's hash module: a range running past the end of the file is cut at the end.
    /// When only part of the file was read, a range past what was read is undefined.
    private func hashRange(_ function: YaraHashFunction, _ offsetValue: YaraValue, _ sizeValue: YaraValue) -> YaraValue {
        guard let offset = offsetValue.integer, let size = sizeValue.integer, offset >= 0, size >= 0,
              offset < Int64(data.count) else { return .undefined }
        var end = offset.addingReportingOverflow(size).overflow ? Int64.max : offset + size
        if end > Int64(data.count) {
            if Int64(data.count) < fileSize { return .undefined }
            end = Int64(data.count)
        }
        let key = HashKey(function: function, start: Int(offset), end: Int(end))
        if let cached = hashCache[key] { return cached }
        // Every distinct range is hashed in full, so the bytes hashed are capped (a few
        // whole-file hashes fit easily); a rule hashing range after range stops here.
        let length = Int(end - offset)
        hashedBytes += length
        guard hashedBytes <= max(4 * data.count, 1 << 20) else {
            note("A rule hashed too much of the file; it was stopped.")
            return .undefined
        }
        guard charge(max(1, length >> 2)) else { return .undefined }
        let value = YaraEvaluator.digest(function, UnsafeRawBufferPointer(rebasing: UnsafeRawBufferPointer(data)[key.start..<key.end]))
        hashCache[key] = value
        return value
    }

    static func digest(_ function: YaraHashFunction, _ bytes: UnsafeRawBufferPointer) -> YaraValue {
        switch function {
        case .md5: return .text(Array(ClutterHex.string(YaraDigest.md5(bytes)).utf8))
        case .sha1: return .text(Array(ClutterHex.string(YaraDigest.sha1(bytes)).utf8))
        case .sha256: return .text(Array(ClutterHex.string(YaraDigest.sha256(bytes)).utf8))
        case .crc32: return .integer(Int64(YaraDigest.crc32(bytes)))
        case .checksum32: return .integer(Int64(YaraDigest.checksum32(bytes)))
        }
    }

    // MARK: Operators

    private func unary(_ op: YaraUnaryOperator, _ value: YaraValue) -> YaraValue {
        switch (op, value) {
        case (.negate, .float(let number)): return .float(-number)
        case (.negate, _):
            guard let number = value.integer else { return .undefined }
            return .integer(0 &- number)
        case (.bitNot, _):
            guard case .integer(let number) = value else { return .undefined }
            return .integer(~number)
        }
    }

    private func binary(_ op: YaraBinaryOperator, _ lhs: YaraValue, _ rhs: YaraValue) -> YaraValue {
        if lhs == .undefined || rhs == .undefined { return .undefined }
        switch op {
        case .equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual:
            return compare(op, lhs, rhs)
        case .add, .subtract, .multiply, .divide, .remainder:
            return arithmetic(op, lhs, rhs)
        case .bitAnd, .bitOr, .bitXor, .shiftLeft, .shiftRight:
            guard let a = lhs.integer, let b = rhs.integer else { return .undefined }
            switch op {
            case .bitAnd: return .integer(a & b)
            case .bitOr: return .integer(a | b)
            case .bitXor: return .integer(a ^ b)
            case .shiftLeft:
                guard b >= 0 else { return .undefined }
                return .integer(b < 64 ? a << b : 0)
            default:
                guard b >= 0 else { return .undefined }
                return .integer(b < 64 ? a >> b : 0)
            }
        case .contains, .icontains, .startswith, .istartswith, .endswith, .iendswith, .iequals:
            guard case .text(let a) = lhs, case .text(let b) = rhs else { return .undefined }
            // `contains` compares at every position.
            let cost = op == .contains || op == .icontains ? a.count &* max(1, b.count) : a.count &+ b.count
            guard charge(cost >> 4) else { return .undefined }
            return .boolean(Self.textOperation(op, a, b))
        }
    }

    private func compare(_ op: YaraBinaryOperator, _ lhs: YaraValue, _ rhs: YaraValue) -> YaraValue {
        let order: Int
        if case .text(let a) = lhs, case .text(let b) = rhs {
            order = a.lexicographicallyPrecedes(b) ? -1 : (a == b ? 0 : 1)
        } else if case .float = lhs, let b = rhs.double, let a = lhs.double {
            order = a < b ? -1 : (a == b ? 0 : 1)
        } else if case .float = rhs, let a = lhs.double, let b = rhs.double {
            order = a < b ? -1 : (a == b ? 0 : 1)
        } else if let a = lhs.integer, let b = rhs.integer {
            order = a < b ? -1 : (a == b ? 0 : 1)
        } else {
            return .undefined
        }
        switch op {
        case .equal: return .boolean(order == 0)
        case .notEqual: return .boolean(order != 0)
        case .less: return .boolean(order < 0)
        case .lessOrEqual: return .boolean(order <= 0)
        case .greater: return .boolean(order > 0)
        default: return .boolean(order >= 0)
        }
    }

    private func arithmetic(_ op: YaraBinaryOperator, _ lhs: YaraValue, _ rhs: YaraValue) -> YaraValue {
        if case .float = lhs, let a = lhs.double, let b = rhs.double { return floatArithmetic(op, a, b) }
        if case .float = rhs, let a = lhs.double, let b = rhs.double { return floatArithmetic(op, a, b) }
        guard let a = lhs.integer, let b = rhs.integer else { return .undefined }
        switch op {
        case .add: return .integer(a &+ b)
        case .subtract: return .integer(a &- b)
        case .multiply: return .integer(a &* b)
        case .divide:
            let (quotient, overflow) = a.dividedReportingOverflow(by: b)
            return b == 0 || overflow ? .undefined : .integer(quotient)
        default:
            let (remainder, overflow) = a.remainderReportingOverflow(dividingBy: b)
            return b == 0 || overflow ? .undefined : .integer(remainder)
        }
    }

    private func floatArithmetic(_ op: YaraBinaryOperator, _ a: Double, _ b: Double) -> YaraValue {
        switch op {
        case .add: return .float(a + b)
        case .subtract: return .float(a - b)
        case .multiply: return .float(a * b)
        case .divide: return b == 0 ? .undefined : .float(a / b)
        default: return .undefined
        }
    }

    static func textOperation(_ op: YaraBinaryOperator, _ a: [UInt8], _ b: [UInt8]) -> Bool {
        let fold: ([UInt8]) -> [UInt8] = { $0.map { YaraTextPattern.isLetter($0) ? $0 | 0x20 : $0 } }
        switch op {
        case .contains: return contains(a, b)
        case .icontains: return contains(fold(a), fold(b))
        case .startswith: return a.starts(with: b)
        case .istartswith: return fold(a).starts(with: fold(b))
        case .endswith: return a.count >= b.count && Array(a.suffix(b.count)) == b
        case .iendswith: return a.count >= b.count && fold(Array(a.suffix(b.count))) == fold(b)
        default: return fold(a) == fold(b)
        }
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
            if haystack[start..<start + needle.count].elementsEqual(needle) { return true }
        }
        return false
    }

    // MARK: Quantifiers and loops

    /// `n of …` means at least n; `0 of …` (like `none of …`) means no match at all.
    private func quantify(_ quantifier: YaraQuantifier, _ count: Int, _ total: Int) -> YaraValue {
        switch quantifier {
        case .all: return .boolean(count == total)
        case .any: return .boolean(count > 0)
        case .none: return .boolean(count == 0)
        case .atLeast(let expr):
            guard let needed = evaluate(expr).integer else { return .undefined }
            return .boolean(needed <= 0 ? count == 0 : Int64(count) >= needed)
        case .percent(let expr):
            guard let percent = evaluate(expr).integer else { return .undefined }
            if percent <= 0 { return .boolean(count == 0) }
            // Capped at 100%, so a huge percentage can't overflow.
            return .boolean(Int64(count) * 100 >= min(percent, 100) * Int64(total))
        }
    }

    /// Runs `body` for `count` items, stopping early once the outcome is known.
    private func loop(_ quantifier: YaraQuantifier, count: Int, _ body: (Int) -> Bool) -> YaraValue {
        var trues = 0
        for index in 0..<count {
            if budget < 0 { return .undefined }
            if body(index) {
                trues += 1
                if case .any = quantifier { return .boolean(true) }
                if case .none = quantifier { return .boolean(false) }
            } else if case .all = quantifier {
                return .boolean(false)
            }
        }
        return quantify(quantifier, trues, count)
    }

    private func forIn(_ quantifier: YaraQuantifier, _ slot: Int, _ iterable: YaraIterable, _ body: YaraExpr) -> YaraValue {
        switch iterable {
        case .range(let lowExpr, let highExpr):
            guard let low = evaluate(lowExpr).integer, let high = evaluate(highExpr).integer else { return .undefined }
            let (span, overflow) = high.subtractingReportingOverflow(low)
            let count = high < low ? 0 : (overflow ? Int64.max : span + 1)
            guard count <= Int64(limits.maxLoopIterations) else {
                note("A loop in a rule was too long to run (more than \(limits.maxLoopIterations) steps).")
                return .undefined
            }
            return loop(quantifier, count: Int(count)) { index in
                variables[slot] = .integer(low + Int64(index))
                return truth(body) == true
            }
        case .list(let items):
            let values = items.map(evaluate)
            return loop(quantifier, count: values.count) { index in
                variables[slot] = values[index]
                return truth(body) == true
            }
        }
    }
}
