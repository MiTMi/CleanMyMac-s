import Foundation

// Recursive-descent parser for YARA rule files. A syntax error only costs the rule it is
// in: the parser records it and resumes at the next line that starts a rule (or an import).

struct YaraParser {
    /// Deepest nesting of parentheses, `not` and unary operators accepted in a condition.
    static let maxNesting = 32

    static let keywords: Set<String> = [
        "all", "and", "any", "ascii", "at", "base64", "base64wide", "condition", "contains", "defined",
        "endswith", "entrypoint", "false", "filesize", "for", "fullword", "global", "icontains", "iendswith",
        "iequals", "import", "in", "include", "istartswith", "matches", "meta", "nocase", "none", "not", "of",
        "or", "private", "rule", "startswith", "strings", "them", "true", "wide", "xor",
    ]

    private var lexer: YaraLexer
    private var current: YaraLexeme
    private var nesting = 0
    /// True while reading a `for` quantifier, where `of` belongs to the loop (`for 2 of them`).
    private var readingForQuantifier = false

    private init(source: String) {
        lexer = YaraLexer(source)
        current = YaraLexeme(token: .symbol(""), line: 1, startsLine: false)
    }

    // MARK: File

    static func parse(_ source: String) -> YaraParsedFile {
        var parser = YaraParser(source: source)
        var file = YaraParsedFile()
        do {
            try parser.advance()
        } catch let error as YaraSyntaxError {
            file.failures.append(YaraSkippedRule(name: "", line: error.line, reason: Self.describe(error)))
            parser.recover(skipCurrent: true)
        } catch {}

        while parser.current.token != .end {
            var ruleName: String?
            let line = parser.current.line
            do {
                switch parser.current.token {
                case .identifier("import"), .identifier("include"):
                    let isImport = parser.current.token == .identifier("import")
                    try parser.advance()
                    guard case .text(let bytes) = parser.current.token else {
                        throw parser.error(isImport ? "expected a module name after import" : "expected a file name after include")
                    }
                    let name = String(decoding: bytes, as: UTF8.self)
                    if isImport { file.imports.append(name) } else { file.includes.append(name) }
                    try parser.advance()
                case .identifier("rule"), .identifier("private"), .identifier("global"):
                    let rule = try parser.parseRule(name: &ruleName)
                    file.rules.append(rule)
                    ruleName = nil
                    try parser.advance()
                default:
                    throw parser.error("expected a rule")
                }
            } catch let error as YaraSyntaxError {
                file.failures.append(YaraSkippedRule(name: ruleName ?? "", line: ruleName == nil ? error.line : line,
                                                     reason: Self.describe(error)))
                parser.recover(skipCurrent: false)
            } catch {
                parser.recover(skipCurrent: true)
            }
        }
        return file
    }

    static func describe(_ error: YaraSyntaxError) -> String {
        "Syntax error on line \(error.line): \(error.message)"
    }

    // MARK: Token helpers

    private mutating func advance() throws {
        do {
            current = try lexer.next()
        } catch {
            // Leave a token that is never a resync point so recovery moves past the problem.
            current = YaraLexeme(token: .symbol(""), line: lexer.line, startsLine: false)
            throw error
        }
    }

    private func error(_ message: String) -> YaraSyntaxError {
        YaraSyntaxError(message: message, line: current.line)
    }

    private var isResyncPoint: Bool {
        guard current.startsLine, case .identifier(let word) = current.token else { return false }
        return word == "rule" || word == "private" || word == "global" || word == "import" || word == "include"
    }

    /// Skips ahead to the next line that starts a rule, an import or an include.
    private mutating func recover(skipCurrent: Bool) {
        if !skipCurrent, isResyncPoint || current.token == .end { return }
        while true {
            do {
                current = try lexer.next()
            } catch {
                if lexer.isAtEnd {
                    current = YaraLexeme(token: .end, line: lexer.line, startsLine: true)
                    return
                }
                continue
            }
            if current.token == .end || isResyncPoint { return }
        }
    }

    private func isKeyword(_ word: String) -> Bool { current.token == .identifier(word) }
    private func isSymbol(_ symbol: String) -> Bool { current.token == .symbol(symbol) }

    private mutating func expectKeyword(_ word: String) throws {
        guard isKeyword(word) else { throw error("expected \(word)") }
        try advance()
    }

    private mutating func expectSymbol(_ symbol: String) throws {
        guard isSymbol(symbol) else { throw error("expected \(symbol)") }
        try advance()
    }

    /// True when the token after the current one is the keyword `word`.
    private func nextIsKeyword(_ word: String) -> Bool {
        var copy = lexer
        guard let lexeme = try? copy.next() else { return false }
        return lexeme.token == .identifier(word)
    }

    private mutating func enter() throws {
        nesting += 1
        if nesting > Self.maxNesting { throw error("the condition is nested too deeply") }
    }

    // MARK: Rule

    /// Parses a rule up to (not past) its closing brace.
    private mutating func parseRule(name outName: inout String?) throws -> YaraParsedRule {
        let line = current.line
        var isPrivate = false
        var isGlobal = false
        while case .identifier(let word) = current.token, word == "private" || word == "global" {
            if word == "private" { isPrivate = true } else { isGlobal = true }
            try advance()
        }
        try expectKeyword("rule")
        guard case .identifier(let name) = current.token, !Self.keywords.contains(name) else {
            throw error("expected a rule name")
        }
        outName = name
        try advance()

        var tags: [String] = []
        if isSymbol(":") {
            try advance()
            while case .identifier(let tag) = current.token, !Self.keywords.contains(tag) {
                tags.append(tag)
                try advance()
            }
            if tags.isEmpty { throw error("expected a tag after :") }
        }
        try expectSymbol("{")

        var meta: [YaraMeta] = []
        if isKeyword("meta") {
            try advance()
            try expectSymbol(":")
            meta = try parseMeta()
        }
        var strings: [YaraParsedString] = []
        if isKeyword("strings") {
            try advance()
            guard isSymbol(":") else { throw error("expected :") }
            strings = try parseStrings()
        }
        try expectKeyword("condition")
        try expectSymbol(":")
        nesting = 0
        let condition = try parseExpression()
        guard isSymbol("}") else { throw error("expected } at the end of the rule") }
        return YaraParsedRule(name: name, line: line, isPrivate: isPrivate, isGlobal: isGlobal, tags: tags,
                              meta: meta, strings: strings, condition: condition)
    }

    private mutating func parseMeta() throws -> [YaraMeta] {
        var meta: [YaraMeta] = []
        while case .identifier(let key) = current.token, key != "strings", key != "condition" {
            try advance()
            try expectSymbol("=")
            let value: YaraMetaValue
            switch current.token {
            case .text(let bytes):
                value = .text(String(decoding: bytes, as: UTF8.self))
            case .integer(let number):
                value = .integer(number)
            case .symbol("-"):
                try advance()
                guard case .integer(let number) = current.token else { throw error("expected a number after -") }
                value = .integer(0 &- number)
            case .identifier("true"):
                value = .boolean(true)
            case .identifier("false"):
                value = .boolean(false)
            default:
                throw error("expected a text, number or true/false value for \(key)")
            }
            meta.append(YaraMeta(key: key, value: value))
            try advance()
        }
        return meta
    }

    /// Parses string definitions; the current token is the `:` after `strings`.
    private mutating func parseStrings() throws -> [YaraParsedString] {
        try advance()
        var strings: [YaraParsedString] = []
        while case .stringID(let name) = current.token {
            let line = current.line
            try advance()
            guard isSymbol("=") else { throw error("expected = after the string name") }
            let value: YaraRawStringValue
            do {
                value = try lexer.readStringValue()
            } catch {
                current = YaraLexeme(token: .symbol(""), line: lexer.line, startsLine: false)
                throw error
            }
            try advance()
            strings.append(YaraParsedString(name: name, line: line, value: value, modifiers: try parseModifiers()))
        }
        if strings.isEmpty { throw error("expected a string definition") }
        return strings
    }

    private mutating func parseModifiers() throws -> YaraStringModifiers {
        var modifiers = YaraStringModifiers()
        while case .identifier(let word) = current.token {
            switch word {
            case "ascii": modifiers.ascii = true
            case "wide": modifiers.wide = true
            case "nocase": modifiers.nocase = true
            case "fullword": modifiers.fullword = true
            case "private": modifiers.isPrivate = true
            case "xor":
                try advance()
                modifiers.xor = 0...255
                if isSymbol("(") {
                    try advance()
                    let low = try parseByteValue()
                    var high = low
                    if isSymbol("-") {
                        try advance()
                        high = try parseByteValue()
                    }
                    guard low <= high else { throw error("the xor range is backwards") }
                    try expectSymbol(")")
                    modifiers.xor = low...high
                }
                continue
            case "base64", "base64wide":
                modifiers.base64 = true
                try advance()
                if isSymbol("(") {
                    try advance()
                    guard case .text = current.token else { throw error("expected a base64 alphabet") }
                    try advance()
                    try expectSymbol(")")
                }
                continue
            default:
                return modifiers
            }
            try advance()
        }
        return modifiers
    }

    private mutating func parseByteValue() throws -> Int {
        guard case .integer(let value) = current.token, (0...255).contains(value) else {
            throw error("expected a number from 0 to 255")
        }
        try advance()
        return Int(value)
    }

    // MARK: Expressions

    private mutating func parseExpression() throws -> YaraSyntaxExpr {
        try enter()
        defer { nesting -= 1 }
        var items = [try parseAnd()]
        while isKeyword("or") {
            try advance()
            items.append(try parseAnd())
        }
        return items.count == 1 ? items[0] : .or(items)
    }

    private mutating func parseAnd() throws -> YaraSyntaxExpr {
        var items = [try parseNot()]
        while isKeyword("and") {
            try advance()
            items.append(try parseNot())
        }
        return items.count == 1 ? items[0] : .and(items)
    }

    private mutating func parseNot() throws -> YaraSyntaxExpr {
        if isKeyword("not") || isKeyword("defined") {
            let isNot = isKeyword("not")
            try advance()
            try enter()
            defer { nesting -= 1 }
            let operand = try parseNot()
            return isNot ? .not(operand) : .defined(operand)
        }
        return try parseBinary(1)
    }

    /// Precedence levels, loosest first (as in YARA's grammar).
    private func binaryOperator() -> (YaraBinaryOperator?, Int)? {
        switch current.token {
        case .symbol("=="): return (.equal, 1)
        case .symbol("!="): return (.notEqual, 1)
        case .identifier("contains"): return (.contains, 1)
        case .identifier("icontains"): return (.icontains, 1)
        case .identifier("startswith"): return (.startswith, 1)
        case .identifier("istartswith"): return (.istartswith, 1)
        case .identifier("endswith"): return (.endswith, 1)
        case .identifier("iendswith"): return (.iendswith, 1)
        case .identifier("iequals"): return (.iequals, 1)
        case .identifier("matches"): return (nil, 1)
        case .symbol("<"): return (.less, 2)
        case .symbol("<="): return (.lessOrEqual, 2)
        case .symbol(">"): return (.greater, 2)
        case .symbol(">="): return (.greaterOrEqual, 2)
        case .symbol("|"): return (.bitOr, 3)
        case .symbol("^"): return (.bitXor, 4)
        case .symbol("&"): return (.bitAnd, 5)
        case .symbol("<<"): return (.shiftLeft, 6)
        case .symbol(">>"): return (.shiftRight, 6)
        case .symbol("+"): return (.add, 7)
        case .symbol("-"): return (.subtract, 7)
        case .symbol("*"): return (.multiply, 8)
        case .symbol("\\"): return (.divide, 8)
        case .symbol("%"): return (.remainder, 8)
        default: return nil
        }
    }

    /// Precedence climbing over the binary operators at `minLevel` or tighter. In a `for`
    /// quantifier (`isQuantifier`) a `%` at this level ends the expression (`for 50% i in …`).
    private mutating func parseBinary(_ minLevel: Int, isQuantifier: Bool = false) throws -> YaraSyntaxExpr {
        var lhs = try parseUnary()
        var chain = 0
        while let found = binaryOperator(), found.1 >= minLevel {
            let (op, level) = found
            // "50% of them": the percent sign belongs to the quantifier.
            if op == .remainder, isQuantifier || nextIsKeyword("of") { break }
            chain += 1
            if chain > 64 { throw error("the expression is too long") }
            guard let op else {
                // `matches` takes a regular expression, which Spruce doesn't evaluate.
                do {
                    _ = try lexer.readRegexLiteral()
                } catch {
                    current = YaraLexeme(token: .symbol(""), line: lexer.line, startsLine: false)
                    throw error
                }
                try advance()
                lhs = .unsupported("regular expressions (matches)")
                continue
            }
            try advance()
            let rhs = try parseBinary(level + 1)
            lhs = .binary(op, lhs, rhs)
        }
        return lhs
    }

    private mutating func parseUnary() throws -> YaraSyntaxExpr {
        if isSymbol("-") || isSymbol("~") {
            let op: YaraUnaryOperator = isSymbol("-") ? .negate : .bitNot
            try advance()
            try enter()
            defer { nesting -= 1 }
            return .unary(op, try parseUnary())
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> YaraSyntaxExpr {
        switch current.token {
        case .symbol("("):
            try advance()
            let inner = try parseExpression()
            try expectSymbol(")")
            return try quantified(inner)
        case .integer(let value):
            try advance()
            return try quantified(.integer(value))
        case .float(let value):
            try advance()
            return .float(value)
        case .text(let bytes):
            try advance()
            return .text(bytes)
        case .stringID(let name):
            try advance()
            return .stringMatch(name, try parseAnchor(allowAt: true))
        case .stringWildcard:
            throw error("string wildcards can only be used in a set, like ($a*)")
        case .stringCount(let name):
            try advance()
            return .stringCount(name, try parseAnchor(allowAt: false))
        case .stringOffset(let name), .stringLength(let name):
            let isOffset: Bool
            if case .stringOffset = current.token { isOffset = true } else { isOffset = false }
            try advance()
            var index: YaraSyntaxExpr?
            if isSymbol("[") {
                try advance()
                index = try parseExpression()
                try expectSymbol("]")
            }
            return isOffset ? .stringOffset(name, index) : .stringLength(name, index)
        case .identifier(let word):
            switch word {
            case "true", "false":
                try advance()
                return .boolean(word == "true")
            case "filesize":
                try advance()
                return .filesize
            case "entrypoint":
                try advance()
                return .entrypoint
            case "all", "any", "none":
                try advance()
                return try parseOf(word == "all" ? .all : word == "any" ? .any : .none)
            case "for":
                return try parseFor()
            default:
                if Self.keywords.contains(word) { throw error("unexpected \(word)") }
                return try parseIdentifier(word)
            }
        default:
            throw error("expected an expression")
        }
    }

    /// `expr of …` / `expr% of …` after a number or parenthesised expression.
    private mutating func quantified(_ expr: YaraSyntaxExpr) throws -> YaraSyntaxExpr {
        if readingForQuantifier { return expr }
        if isKeyword("of") { return try parseOf(.count(expr)) }
        if isSymbol("%"), nextIsKeyword("of") {
            try advance()
            return try parseOf(.percent(expr))
        }
        return expr
    }

    private mutating func parseAnchor(allowAt: Bool) throws -> YaraSyntaxAnchor {
        if allowAt, isKeyword("at") {
            try advance()
            return .at(try parseBinary(3))
        }
        if isKeyword("in") {
            try advance()
            let (low, high) = try parseRange()
            return .within(low, high)
        }
        return .anywhere
    }

    private mutating func parseRange() throws -> (YaraSyntaxExpr, YaraSyntaxExpr) {
        try expectSymbol("(")
        let low = try parseBinary(3)
        try expectSymbol("..")
        let high = try parseBinary(3)
        try expectSymbol(")")
        return (low, high)
    }

    private mutating func parseOf(_ quantifier: YaraSyntaxQuantifier) throws -> YaraSyntaxExpr {
        try expectKeyword("of")
        let set = try parseSet()
        return .of(quantifier, set, try parseAnchor(allowAt: true))
    }

    private mutating func parseSet() throws -> YaraSyntaxSet {
        if isKeyword("them") {
            try advance()
            return .them
        }
        try expectSymbol("(")
        var items: [YaraSyntaxSetItem] = []
        while true {
            switch current.token {
            case .stringID(let name):
                items.append(.string(name, wildcard: false))
                try advance()
            case .stringWildcard(let prefix):
                items.append(.string(prefix, wildcard: true))
                try advance()
            case .identifier(let name) where !Self.keywords.contains(name):
                try advance()
                if isSymbol("*") {
                    try advance()
                    items.append(.rule(name, wildcard: true))
                } else {
                    items.append(.rule(name, wildcard: false))
                }
            default:
                throw error("expected a string or rule name in the set")
            }
            guard isSymbol(",") else { break }
            try advance()
        }
        try expectSymbol(")")
        return .items(items)
    }

    private mutating func parseFor() throws -> YaraSyntaxExpr {
        try advance()
        let quantifier: YaraSyntaxQuantifier
        if isKeyword("all") || isKeyword("any") || isKeyword("none") {
            quantifier = isKeyword("all") ? .all : isKeyword("any") ? .any : .none
            try advance()
        } else {
            readingForQuantifier = true
            defer { readingForQuantifier = false }
            let count = try parseBinary(3, isQuantifier: true)
            readingForQuantifier = false
            if isSymbol("%") {
                try advance()
                quantifier = .percent(count)
            } else {
                quantifier = .count(count)
            }
        }
        if isKeyword("of") {
            try advance()
            let set = try parseSet()
            try expectSymbol(":")
            return .forOf(quantifier, set, try parseBody())
        }
        var variables: [String] = []
        while true {
            guard case .identifier(let name) = current.token, !Self.keywords.contains(name) else {
                throw error("expected a loop variable")
            }
            variables.append(name)
            try advance()
            guard isSymbol(",") else { break }
            try advance()
        }
        try expectKeyword("in")
        let iterable = try parseIterable()
        try expectSymbol(":")
        return .forIn(quantifier, variables, iterable, try parseBody())
    }

    private mutating func parseIterable() throws -> YaraSyntaxIterable {
        if isSymbol("(") {
            try advance()
            let first = try parseExpression()
            if isSymbol("..") {
                try advance()
                let last = try parseExpression()
                try expectSymbol(")")
                return .range(first, last)
            }
            var items = [first]
            while isSymbol(",") {
                try advance()
                items.append(try parseExpression())
            }
            try expectSymbol(")")
            return .list(items)
        }
        if case .identifier(let word) = current.token, !Self.keywords.contains(word) {
            _ = try parseIdentifier(word)
            return .unsupported(word)
        }
        throw error("expected a range or a list to loop over")
    }

    private mutating func parseBody() throws -> YaraSyntaxExpr {
        try expectSymbol("(")
        let body = try parseExpression()
        try expectSymbol(")")
        return body
    }

    /// A rule name, loop variable, function call or module value.
    private mutating func parseIdentifier(_ first: String) throws -> YaraSyntaxExpr {
        try advance()
        var path = [first]
        var arguments: [YaraSyntaxExpr]?
        var isComplex = false
        while true {
            if isSymbol(".") {
                if arguments != nil { isComplex = true }
                try advance()
                guard case .identifier(let name) = current.token else { throw error("expected a name after .") }
                path.append(name)
                try advance()
            } else if isSymbol("(") {
                if arguments != nil { isComplex = true }
                try advance()
                var list: [YaraSyntaxExpr] = []
                if !isSymbol(")") {
                    list.append(try parseExpression())
                    while isSymbol(",") {
                        try advance()
                        list.append(try parseExpression())
                    }
                }
                try expectSymbol(")")
                arguments = list
            } else if isSymbol("[") {
                isComplex = true
                try advance()
                _ = try parseExpression()
                try expectSymbol("]")
            } else {
                break
            }
        }
        if isComplex { return .moduleValue(path) }
        if let arguments { return .call(path, arguments) }
        return path.count == 1 ? .identifier(first) : .moduleValue(path)
    }
}
