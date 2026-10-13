import Foundation

// Lexer for YARA rule source. Works on the UTF-8 bytes of the file; text strings keep their
// raw bytes. String values (text, hex, regular expression) are read on request by the
// parser because their syntax differs from the rest of the language.

/// A problem in YARA source. The parser turns it into a skipped rule and carries on.
struct YaraSyntaxError: Error, Sendable {
    let message: String
    let line: Int
}

/// One token of YARA source.
enum YaraToken: Equatable, Sendable {
    /// A name or keyword (`rule`, `and`, `uint32`, `Macho`…).
    case identifier(String)
    /// `$name`; empty for an anonymous `$`.
    case stringID(String)
    /// `$name*` (the prefix before the star; empty for `$*`).
    case stringWildcard(String)
    /// `#name` (match count); empty inside `for … of` bodies.
    case stringCount(String)
    /// `@name` (match offset).
    case stringOffset(String)
    /// `!name` (match length).
    case stringLength(String)
    case integer(Int64)
    case float(Double)
    /// A quoted text string with escapes resolved.
    case text([UInt8])
    /// Operators and punctuation.
    case symbol(String)
    case end
}

struct YaraLexeme: Sendable {
    var token: YaraToken
    var line: Int
    /// True when no other token comes before this one on its line (used to resync after errors).
    var startsLine: Bool
}

/// The value of a string definition.
enum YaraRawStringValue: Sendable, Equatable {
    case text([UInt8])
    /// Contents between the braces, comments removed.
    case hex(String)
    /// Between the slashes (escapes kept as written), and the flags after the closing slash.
    case regex([UInt8], flags: String)
}

struct YaraLexer: Sendable {
    private let source: [UInt8]
    private(set) var position = 0
    private(set) var line = 1
    private var lastTokenLine = 0

    init(_ text: String) {
        var bytes = Array(text.utf8)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        source = bytes
    }

    var isAtEnd: Bool { position >= source.count }

    // MARK: Tokens

    mutating func next() throws -> YaraLexeme {
        try skipTrivia()
        let tokenLine = line
        let startsLine = tokenLine != lastTokenLine
        lastTokenLine = tokenLine
        guard position < source.count else {
            return YaraLexeme(token: .end, line: tokenLine, startsLine: true)
        }
        let c = source[position]
        let token: YaraToken
        if Self.isIdentifierStart(c) {
            token = .identifier(readIdentifier())
        } else if Self.isDigit(c) {
            token = try readNumber()
        } else {
            switch c {
            case YaraChar.quote:
                position += 1
                token = .text(try readText())
            case YaraChar.dollar:
                position += 1
                let name = readIdentifier()
                if peek() == YaraChar.star {
                    position += 1
                    token = .stringWildcard(name)
                } else {
                    token = .stringID(name)
                }
            case YaraChar.hash:
                position += 1
                token = .stringCount(readIdentifier())
            case YaraChar.at:
                position += 1
                token = .stringOffset(readIdentifier())
            case YaraChar.bang:
                if peek(1) == YaraChar.equals {
                    position += 2
                    token = .symbol("!=")
                } else {
                    position += 1
                    token = .stringLength(readIdentifier())
                }
            default:
                token = try readSymbol()
            }
        }
        return YaraLexeme(token: token, line: tokenLine, startsLine: startsLine)
    }

    /// Reads the value after `=` in a strings section.
    mutating func readStringValue() throws -> YaraRawStringValue {
        try skipTrivia()
        lastTokenLine = line
        guard position < source.count else { throw YaraSyntaxError(message: "the string has no value", line: line) }
        switch source[position] {
        case YaraChar.quote:
            position += 1
            return .text(try readText())
        case YaraChar.openBrace:
            return .hex(try readHexBody())
        case YaraChar.slash:
            let regex = try readRegex()
            return .regex(regex.body, flags: regex.flags)
        default:
            throw YaraSyntaxError(message: "expected a text, hex or regular expression string", line: line)
        }
    }

    /// Reads the regular expression after `matches` in a condition.
    mutating func readRegexLiteral() throws -> String {
        try skipTrivia()
        lastTokenLine = line
        guard position < source.count, source[position] == YaraChar.slash else {
            throw YaraSyntaxError(message: "expected a regular expression after matches", line: line)
        }
        return String(decoding: try readRegex().body, as: UTF8.self)
    }

    // MARK: Pieces

    private func peek(_ offset: Int = 0) -> UInt8? {
        let index = position + offset
        return index < source.count ? source[index] : nil
    }

    private mutating func skipTrivia() throws {
        while position < source.count {
            let c = source[position]
            if c == YaraChar.newline {
                line += 1
                position += 1
            } else if c == YaraChar.space || c == YaraChar.tab || c == YaraChar.cr || c == 0x0B || c == 0x0C {
                position += 1
            } else if c == YaraChar.slash, peek(1) == YaraChar.slash {
                while position < source.count, source[position] != YaraChar.newline { position += 1 }
            } else if c == YaraChar.slash, peek(1) == YaraChar.star {
                try skipBlockComment()
            } else {
                return
            }
        }
    }

    private mutating func skipBlockComment() throws {
        let startLine = line
        position += 2
        while position < source.count {
            if source[position] == YaraChar.star, peek(1) == YaraChar.slash {
                position += 2
                return
            }
            if source[position] == YaraChar.newline { line += 1 }
            position += 1
        }
        throw YaraSyntaxError(message: "a /* comment never ends", line: startLine)
    }

    private mutating func readIdentifier() -> String {
        let start = position
        while position < source.count, Self.isIdentifierCharacter(source[position]) { position += 1 }
        return String(decoding: source[start..<position], as: UTF8.self)
    }

    private mutating func readDigits(_ accept: (UInt8) -> Bool) -> String {
        let start = position
        while position < source.count, accept(source[position]) { position += 1 }
        return String(decoding: source[start..<position], as: UTF8.self)
    }

    private mutating func readNumber() throws -> YaraToken {
        let badNumber = YaraSyntaxError(message: "malformed number", line: line)
        var value: Int64
        if source[position] == YaraChar.zero, let x = peek(1), x == YaraChar.lowerX || x == YaraChar.upperX {
            position += 2
            let digits = readDigits(Self.isHexDigit)
            guard let parsed = UInt64(digits, radix: 16) else { throw badNumber }
            value = Int64(bitPattern: parsed)
        } else if source[position] == YaraChar.zero, peek(1) == YaraChar.lowerO {
            position += 2
            let digits = readDigits { $0 >= YaraChar.zero && $0 <= YaraChar.zero + 7 }
            guard let parsed = Int64(digits, radix: 8) else { throw badNumber }
            value = parsed
        } else {
            let digits = readDigits(Self.isDigit)
            if peek() == YaraChar.dot, let after = peek(1), Self.isDigit(after) {
                position += 1
                let fraction = readDigits(Self.isDigit)
                guard let double = Double(digits + "." + fraction) else { throw badNumber }
                if let next = peek(), Self.isIdentifierCharacter(next) { throw badNumber }
                return .float(double)
            }
            guard let parsed = Int64(digits) else { throw badNumber }
            value = parsed
            if let suffix = peek(), suffix == YaraChar.upperK || suffix == YaraChar.upperM, peek(1) == YaraChar.upperB,
               !(peek(2).map(Self.isIdentifierCharacter) ?? false) {
                position += 2
                let (product, overflow) = value.multipliedReportingOverflow(by: suffix == YaraChar.upperK ? 1024 : 1_048_576)
                guard !overflow else { throw badNumber }
                value = product
            }
        }
        if let next = peek(), Self.isIdentifierCharacter(next) {
            while position < source.count, Self.isIdentifierCharacter(source[position]) { position += 1 }
            throw badNumber
        }
        return .integer(value)
    }

    private mutating func readText() throws -> [UInt8] {
        let startLine = line
        var out: [UInt8] = []
        while position < source.count {
            let c = source[position]
            if c == YaraChar.quote {
                position += 1
                return out
            }
            if c == YaraChar.newline { break }
            position += 1
            guard c == YaraChar.backslash else {
                out.append(c)
                continue
            }
            guard position < source.count else { break }
            let escape = source[position]
            position += 1
            switch escape {
            case YaraChar.lowerN: out.append(0x0A)
            case YaraChar.lowerT: out.append(0x09)
            case YaraChar.lowerR: out.append(0x0D)
            case YaraChar.quote: out.append(YaraChar.quote)
            case YaraChar.backslash: out.append(YaraChar.backslash)
            case YaraChar.lowerX:
                guard position + 1 < source.count,
                      let byte = UInt8(String(decoding: source[position...position + 1], as: UTF8.self), radix: 16) else {
                    throw YaraSyntaxError(message: "\\x needs two hex digits", line: line)
                }
                position += 2
                out.append(byte)
            default:
                throw YaraSyntaxError(message: "unknown escape sequence in a text string", line: line)
            }
        }
        throw YaraSyntaxError(message: "a text string never ends", line: startLine)
    }

    /// Reads `{ … }` and returns what is between the braces with comments removed.
    private mutating func readHexBody() throws -> String {
        let startLine = line
        position += 1
        var out: [UInt8] = []
        while position < source.count {
            let c = source[position]
            if c == YaraChar.closeBrace {
                position += 1
                return String(decoding: out, as: UTF8.self)
            }
            if c == YaraChar.slash, peek(1) == YaraChar.slash {
                while position < source.count, source[position] != YaraChar.newline { position += 1 }
                continue
            }
            if c == YaraChar.slash, peek(1) == YaraChar.star {
                try skipBlockComment()
                out.append(YaraChar.space)
                continue
            }
            if c == YaraChar.newline { line += 1 }
            guard Self.isHexBodyCharacter(c) else {
                throw YaraSyntaxError(message: "unexpected character in a hex string", line: line)
            }
            out.append(c)
            position += 1
        }
        throw YaraSyntaxError(message: "a hex string never ends", line: startLine)
    }

    private mutating func readRegex() throws -> (body: [UInt8], flags: String) {
        let startLine = line
        position += 1
        var out: [UInt8] = []
        while position < source.count {
            let c = source[position]
            if c == YaraChar.newline { break }
            position += 1
            if c == YaraChar.backslash, position < source.count {
                out.append(c)
                out.append(source[position])
                position += 1
                continue
            }
            if c == YaraChar.slash {
                let flagsStart = position
                while position < source.count, Self.isIdentifierCharacter(source[position]) { position += 1 }
                return (out, String(decoding: source[flagsStart..<position], as: UTF8.self))
            }
            out.append(c)
        }
        throw YaraSyntaxError(message: "a regular expression never ends", line: startLine)
    }

    private static let twoCharacterSymbols: Set<String> = ["==", "!=", "<=", ">=", "<<", ">>", ".."]
    private static let oneCharacterSymbols = Set("()[]{},:=<>+-*\\%&|^~./".utf8)

    private mutating func readSymbol() throws -> YaraToken {
        let c = source[position]
        if position + 1 < source.count {
            let pair = String(decoding: source[position...position + 1], as: UTF8.self)
            if Self.twoCharacterSymbols.contains(pair) {
                position += 2
                return .symbol(pair)
            }
        }
        position += 1
        if Self.oneCharacterSymbols.contains(c) { return .symbol(String(UnicodeScalar(c))) }
        let shown = c < 0x80 && c >= 0x20 ? String(UnicodeScalar(c)) : String(format: "0x%02X", c)
        throw YaraSyntaxError(message: "unexpected character \(shown)", line: line)
    }

    // MARK: Character classes

    static func isDigit(_ c: UInt8) -> Bool { c >= YaraChar.zero && c <= YaraChar.zero + 9 }

    static func isHexDigit(_ c: UInt8) -> Bool {
        isDigit(c) || (c >= YaraChar.lowerA && c <= YaraChar.lowerA + 5) || (c >= YaraChar.upperA && c <= YaraChar.upperA + 5)
    }

    static func isIdentifierStart(_ c: UInt8) -> Bool {
        (c >= YaraChar.lowerA && c <= YaraChar.lowerA + 25) || (c >= YaraChar.upperA && c <= YaraChar.upperA + 25) || c == YaraChar.underscore
    }

    static func isIdentifierCharacter(_ c: UInt8) -> Bool { isIdentifierStart(c) || isDigit(c) }

    private static func isHexBodyCharacter(_ c: UInt8) -> Bool {
        if isHexDigit(c) { return true }
        switch c {
        case YaraChar.question, YaraChar.space, YaraChar.tab, YaraChar.cr, YaraChar.newline, 0x0B, 0x0C,
             YaraChar.openBracket, YaraChar.closeBracket, YaraChar.minus, YaraChar.openParen, YaraChar.closeParen, YaraChar.pipe, YaraChar.tilde:
            return true
        default:
            return false
        }
    }
}

/// ASCII byte constants used by the YARA lexer and hex parser.
enum YaraChar {
    static let tab = UInt8(ascii: "\t")
    static let newline = UInt8(ascii: "\n")
    static let cr = UInt8(ascii: "\r")
    static let space = UInt8(ascii: " ")
    static let bang = UInt8(ascii: "!")
    static let quote = UInt8(ascii: "\"")
    static let hash = UInt8(ascii: "#")
    static let dollar = UInt8(ascii: "$")
    static let openParen = UInt8(ascii: "(")
    static let closeParen = UInt8(ascii: ")")
    static let star = UInt8(ascii: "*")
    static let minus = UInt8(ascii: "-")
    static let dot = UInt8(ascii: ".")
    static let slash = UInt8(ascii: "/")
    static let zero = UInt8(ascii: "0")
    static let equals = UInt8(ascii: "=")
    static let question = UInt8(ascii: "?")
    static let at = UInt8(ascii: "@")
    static let upperA = UInt8(ascii: "A")
    static let upperB = UInt8(ascii: "B")
    static let upperK = UInt8(ascii: "K")
    static let upperM = UInt8(ascii: "M")
    static let upperX = UInt8(ascii: "X")
    static let openBracket = UInt8(ascii: "[")
    static let backslash = UInt8(ascii: "\\")
    static let closeBracket = UInt8(ascii: "]")
    static let underscore = UInt8(ascii: "_")
    static let lowerA = UInt8(ascii: "a")
    static let lowerN = UInt8(ascii: "n")
    static let lowerO = UInt8(ascii: "o")
    static let lowerR = UInt8(ascii: "r")
    static let lowerT = UInt8(ascii: "t")
    static let lowerX = UInt8(ascii: "x")
    static let openBrace = UInt8(ascii: "{")
    static let pipe = UInt8(ascii: "|")
    static let closeBrace = UInt8(ascii: "}")
    static let tilde = UInt8(ascii: "~")
}
