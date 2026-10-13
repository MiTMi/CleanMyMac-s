import Foundation

// Parsed (not yet resolved) form of YARA rules. `YaraParser` produces it, `YaraCompiler`
// checks it and turns it into a `YaraProgram`.

struct YaraParsedFile: Sendable {
    var imports: [String] = []
    var includes: [String] = []
    var rules: [YaraParsedRule] = []
    /// Rules (or stray text) the parser could not read.
    var failures: [YaraSkippedRule] = []
}

struct YaraParsedRule: Sendable {
    var name: String
    var line: Int
    var isPrivate: Bool
    var isGlobal: Bool
    var tags: [String]
    var meta: [YaraMeta]
    var strings: [YaraParsedString]
    var condition: YaraSyntaxExpr
}

struct YaraParsedString: Sendable {
    /// Name without the `$`; empty for an anonymous string.
    var name: String
    var line: Int
    var value: YaraRawStringValue
    var modifiers: YaraStringModifiers
}

struct YaraStringModifiers: Sendable, Hashable {
    var ascii = false
    var wide = false
    var nocase = false
    var fullword = false
    var isPrivate = false
    /// Single-byte XOR keys to try (`xor` alone is 0…255, which includes the plain text).
    var xor: ClosedRange<Int>?
    var base64 = false
}

enum YaraUnaryOperator: Sendable {
    case negate
    case bitNot
}

enum YaraBinaryOperator: Sendable {
    case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual
    case add, subtract, multiply, divide, remainder
    case bitAnd, bitOr, bitXor, shiftLeft, shiftRight
    case contains, icontains, startswith, istartswith, endswith, iendswith, iequals
}

/// Where a string (or a set of strings) has to match.
enum YaraSyntaxAnchor: Sendable {
    case anywhere
    case at(YaraSyntaxExpr)
    case within(YaraSyntaxExpr, YaraSyntaxExpr)
}

enum YaraSyntaxQuantifier: Sendable {
    case all
    case any
    case none
    case count(YaraSyntaxExpr)
    case percent(YaraSyntaxExpr)
}

enum YaraSyntaxSetItem: Sendable {
    /// `$name` or, with `wildcard`, `$prefix*`.
    case string(String, wildcard: Bool)
    /// `RuleName` or, with `wildcard`, `Prefix*`.
    case rule(String, wildcard: Bool)
}

enum YaraSyntaxSet: Sendable {
    case them
    case items([YaraSyntaxSetItem])
}

enum YaraSyntaxIterable: Sendable {
    case range(YaraSyntaxExpr, YaraSyntaxExpr)
    case list([YaraSyntaxExpr])
    /// Iterating a module array or dictionary.
    case unsupported(String)
}

indirect enum YaraSyntaxExpr: Sendable {
    case boolean(Bool)
    case integer(Int64)
    case float(Double)
    case text([UInt8])
    case filesize
    case entrypoint
    /// A rule name or a loop variable.
    case identifier(String)
    /// `uint32(0)`, `hash.sha1(0, filesize)`, `pe.exports("x")`…
    case call([String], [YaraSyntaxExpr])
    /// `pe.number_of_sections`, `pe.sections[0].name`… (only modules have these).
    case moduleValue([String])
    case stringMatch(String, YaraSyntaxAnchor)
    case stringCount(String, YaraSyntaxAnchor)
    case stringOffset(String, YaraSyntaxExpr?)
    case stringLength(String, YaraSyntaxExpr?)
    case unary(YaraUnaryOperator, YaraSyntaxExpr)
    case binary(YaraBinaryOperator, YaraSyntaxExpr, YaraSyntaxExpr)
    case and([YaraSyntaxExpr])
    case or([YaraSyntaxExpr])
    case not(YaraSyntaxExpr)
    case defined(YaraSyntaxExpr)
    case of(YaraSyntaxQuantifier, YaraSyntaxSet, YaraSyntaxAnchor)
    case forOf(YaraSyntaxQuantifier, YaraSyntaxSet, YaraSyntaxExpr)
    case forIn(YaraSyntaxQuantifier, [String], YaraSyntaxIterable, YaraSyntaxExpr)
    /// Something Spruce reads but can't evaluate (the text says what).
    case unsupported(String)

    /// Direct sub-expressions (for iterative depth checks).
    var children: [YaraSyntaxExpr] {
        func anchor(_ a: YaraSyntaxAnchor) -> [YaraSyntaxExpr] {
            switch a {
            case .anywhere: return []
            case .at(let e): return [e]
            case .within(let lo, let hi): return [lo, hi]
            }
        }
        func quantifier(_ q: YaraSyntaxQuantifier) -> [YaraSyntaxExpr] {
            switch q {
            case .all, .any, .none: return []
            case .count(let e), .percent(let e): return [e]
            }
        }
        switch self {
        case .boolean, .integer, .float, .text, .filesize, .entrypoint, .identifier, .moduleValue, .unsupported:
            return []
        case .call(_, let args): return args
        case .stringMatch(_, let a), .stringCount(_, let a): return anchor(a)
        case .stringOffset(_, let index), .stringLength(_, let index): return index.map { [$0] } ?? []
        case .unary(_, let e), .not(let e), .defined(let e): return [e]
        case .binary(_, let l, let r): return [l, r]
        case .and(let items), .or(let items): return items
        case .of(let q, _, let a): return quantifier(q) + anchor(a)
        case .forOf(let q, _, let body): return quantifier(q) + [body]
        case .forIn(let q, _, let iterable, let body):
            var out = quantifier(q)
            switch iterable {
            case .range(let lo, let hi): out += [lo, hi]
            case .list(let items): out += items
            case .unsupported: break
            }
            return out + [body]
        }
    }

    /// Nesting depth, computed without recursion so hostile input can't exhaust the stack.
    var depth: Int {
        var deepest = 0
        var stack: [(YaraSyntaxExpr, Int)] = [(self, 1)]
        while let (expr, level) = stack.popLast() {
            deepest = max(deepest, level)
            for child in expr.children { stack.append((child, level + 1)) }
        }
        return deepest
    }
}
