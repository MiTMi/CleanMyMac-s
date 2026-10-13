import Foundation

// Turns parsed rules into a `YaraProgram`: resolves names, compiles strings, and skips
// (with a reason) every rule Spruce can't evaluate — plus every rule that refers to one.
// Nothing here fails the whole file.

struct YaraProgramChain: Sendable {
    var segments: [Int]
    var gaps: [YaraGap]
}

struct YaraProgramString: Sendable {
    var name: String
    var rule: Int
    var chains: [YaraProgramChain]
    /// False for strings no loaded rule's condition uses (they are never searched).
    var isNeeded: Bool
}

struct YaraProgramRule: Sendable {
    var info: YaraRuleInfo
    var condition: YaraExpr
    var isLoaded: Bool
}

struct YaraProgram: Sendable {
    /// Every parsed rule in file order; skipped ones have `isLoaded == false`.
    var rules: [YaraProgramRule] = []
    /// Loaded rules, each after the rules it refers to.
    var order: [Int] = []
    var strings: [YaraProgramString] = []
    var segments: [YaraSegment] = []
    /// Per segment: true when it is a later piece of a split hex string (`{ … [-] … }`)
    /// somewhere, so it keeps more matches (`YaraScanLimits.maxMatchesPerChainPiece`).
    var isChainTail: [Bool] = []
    var plans: [YaraMatchPlan] = []
    var automaton = YaraAtomAutomaton()
    /// Per atom: the plan that verifies it, its length and its segment.
    var atomPlans: [Int32] = []
    var atomLengths: [Int32] = []
    var atomSegments: [Int32] = []
    var linearPlans: [Int] = []
    var xorSegments: [Int] = []
    var variableSlots = 1
    var skipped: [YaraSkippedRule] = []
    var imports: [String] = []
    var warnings: [String] = []
}

enum YaraCompiler {
    /// Deepest condition accepted (keeps evaluation well within a background thread's stack).
    static let maxConditionDepth = 48
    /// Size caps that keep a huge or hostile rule file from using too much memory or time.
    static let maxRules = 50_000
    static let maxStrings = 100_000
    static let maxDependencies = 500_000
    /// Most rules one wildcard set (`any of (Prefix*)`) may name.
    static let maxWildcardRules = 1_000
    /// Longest text value in a condition (real rules compare hashes and short names).
    static let maxConditionText = 4_096

    static let modules: Set<String> = [
        "pe", "elf", "macho", "math", "dotnet", "cuckoo", "magic", "time", "console", "string", "dex", "lnk",
        "hash", "tests", "vt",
    ]

    static let hashFunctions: [String: YaraHashFunction] = [
        "md5": .md5, "sha1": .sha1, "sha256": .sha256, "crc32": .crc32, "checksum32": .checksum32,
    ]

    static let integerReads: [String: YaraIntegerRead] = {
        var table: [String: YaraIntegerRead] = [:]
        for width in [1, 2, 4] {
            for signed in [false, true] {
                for bigEndian in [false, true] {
                    let name = (signed ? "int" : "uint") + String(width * 8) + (bigEndian ? "be" : "")
                    table[name] = YaraIntegerRead(width: width, signed: signed, bigEndian: bigEndian)
                }
            }
        }
        return table
    }()

    // MARK: Program

    static func compile(_ file: YaraParsedFile) -> YaraProgram {
        var program = YaraProgram()
        program.imports = file.imports
        program.skipped = file.failures
        for include in file.includes {
            program.warnings.append("Ignored include \"\(include)\": Spruce reads each rule file on its own.")
        }
        for module in file.imports where module != "hash" {
            program.warnings.append(modules.contains(module)
                ? "Spruce doesn't support the \(module) module; rules that use it are skipped."
                : "Unknown module \"\(module)\"; rules that use it are skipped.")
        }

        var ruleIndex: [String: Int] = [:]
        for (index, rule) in file.rules.enumerated() where ruleIndex[rule.name] == nil {
            ruleIndex[rule.name] = index
        }
        let sortedNames = ruleIndex.map { (name: $0.key, index: $0.value) }.sorted { $0.name < $1.name }
        let unavailable = Set(file.failures.map(\.name).filter { !$0.isEmpty && ruleIndex[$0] == nil })

        var loaded = [Bool](repeating: false, count: file.rules.count)
        var reasons = [String?](repeating: nil, count: file.rules.count)
        var dependencies = [Set<Int>](repeating: [], count: file.rules.count)
        var usedStrings = [Set<Int>](repeating: [], count: file.rules.count)
        var compiledStrings: [(name: String, rule: Int, chains: [YaraChain])] = []
        var dependencyCount = 0

        for (index, rule) in file.rules.enumerated() {
            program.rules.append(YaraProgramRule(
                info: YaraRuleInfo(name: rule.name, tags: rule.tags, meta: rule.meta, isPrivate: rule.isPrivate,
                                   isGlobal: rule.isGlobal, line: rule.line),
                condition: .constant(.boolean(false)), isLoaded: false))
            guard ruleIndex[rule.name] == index else {
                reasons[index] = "Another rule with this name comes earlier in the file"
                continue
            }
            guard index < maxRules else {
                reasons[index] = "The rule file has more than \(maxRules) rules"
                continue
            }
            guard compiledStrings.count + rule.strings.count <= maxStrings else {
                reasons[index] = "The rule file has more than \(maxStrings) strings"
                continue
            }
            do {
                let strings = try compileStrings(rule)
                guard rule.condition.depth <= maxConditionDepth else {
                    throw YaraCompileIssue(reason: "The condition is too complex")
                }
                var scope = Scope(rule: index, ruleIndex: ruleIndex, sortedNames: sortedNames, unavailable: unavailable)
                let firstString = compiledStrings.count
                for (offset, string) in strings.enumerated() { scope.strings.append((string.name, firstString + offset)) }
                let condition = try resolve(rule.condition, &scope)
                guard dependencyCount + scope.dependencies.count <= maxDependencies else {
                    throw YaraCompileIssue(reason: "The rule file has too many references between rules")
                }
                for string in strings { compiledStrings.append((string.name, index, string.chains)) }
                dependencyCount += scope.dependencies.count
                program.rules[index].condition = condition
                program.variableSlots = max(program.variableSlots, scope.slots)
                dependencies[index] = scope.dependencies
                usedStrings[index] = scope.usedStrings
                loaded[index] = true
            } catch let issue as YaraCompileIssue {
                reasons[index] = issue.reason
            } catch {
                reasons[index] = "The rule couldn't be read"
            }
        }

        // Rules that use a skipped rule are skipped too (worklist over reverse edges).
        var dependents = [[Int]](repeating: [], count: file.rules.count)
        for index in loaded.indices where loaded[index] {
            for dependency in dependencies[index] { dependents[dependency].append(index) }
        }
        var pending = loaded.indices.filter { !loaded[$0] }
        while let skippedIndex = pending.popLast() {
            for dependent in dependents[skippedIndex] where loaded[dependent] {
                loaded[dependent] = false
                reasons[dependent] = "Uses rule \(file.rules[skippedIndex].name), which was skipped"
                pending.append(dependent)
            }
        }

        // Order rules so each comes after the ones it uses; rules in a loop never get a turn.
        var waiting = [Int](repeating: 0, count: file.rules.count)
        for index in loaded.indices where loaded[index] { waiting[index] = dependencies[index].count }
        var ready = loaded.indices.filter { loaded[$0] && waiting[$0] == 0 }
        var head = 0
        while head < ready.count {
            let index = ready[head]
            head += 1
            program.order.append(index)
            for dependent in dependents[index] where loaded[dependent] {
                waiting[dependent] -= 1
                if waiting[dependent] == 0 { ready.append(dependent) }
            }
        }
        // Left over: rules on a loop, and rules that use them. Peel off the rules no other
        // left-over rule uses; what remains is the loops themselves.
        let ordered = Set(program.order)
        let unordered = loaded.indices.filter { loaded[$0] && !ordered.contains($0) }
        let leftOver = Set(unordered)
        var usedBy = [Int: Int]()
        for index in unordered {
            usedBy[index] = dependents[index].filter { leftOver.contains($0) }.count
        }
        var peel = unordered.filter { usedBy[$0] == 0 }
        var peeled = Set<Int>()
        while let index = peel.popLast() {
            peeled.insert(index)
            for dependency in dependencies[index] where leftOver.contains(dependency) && !peeled.contains(dependency) {
                usedBy[dependency, default: 0] -= 1
                if usedBy[dependency] == 0 { peel.append(dependency) }
            }
        }
        for index in unordered {
            if peeled.contains(index), let blocked = dependencies[index].sorted().first(where: { leftOver.contains($0) }) {
                reasons[index] = "Uses rule \(file.rules[blocked].name), which was skipped"
            } else {
                reasons[index] = "Refers to itself through other rules"
            }
            loaded[index] = false
        }

        for index in file.rules.indices {
            program.rules[index].isLoaded = loaded[index]
            if !loaded[index] {
                program.rules[index].condition = .constant(.boolean(false))
                program.skipped.append(YaraSkippedRule(name: file.rules[index].name, line: file.rules[index].line,
                                                       reason: reasons[index] ?? "The rule couldn't be loaded"))
            }
        }
        program.skipped.sort { ($0.line, $0.name) < ($1.line, $1.name) }

        var needed = Set<Int>()
        for index in loaded.indices where loaded[index] { needed.formUnion(usedStrings[index]) }
        buildMatchers(&program, strings: compiledStrings, needed: needed)
        return program
    }

    /// Dedupes segments, picks atoms and builds the automaton for the strings in use.
    private static func buildMatchers(_ program: inout YaraProgram, strings: [(name: String, rule: Int, chains: [YaraChain])],
                                      needed: Set<Int>) {
        var segmentIDs: [YaraSegment: Int] = [:]
        for (index, string) in strings.enumerated() {
            let isNeeded = needed.contains(index)
            var chains: [YaraProgramChain] = []
            if isNeeded {
                for chain in string.chains {
                    let ids = chain.segments.map { segment -> Int in
                        if let id = segmentIDs[segment] { return id }
                        let id = program.segments.count
                        segmentIDs[segment] = id
                        program.segments.append(segment)
                        program.isChainTail.append(false)
                        return id
                    }
                    for id in ids.dropFirst() { program.isChainTail[id] = true }
                    chains.append(YaraProgramChain(segments: ids, gaps: chain.gaps))
                }
            }
            program.strings.append(YaraProgramString(name: string.name, rule: string.rule, chains: chains,
                                                     isNeeded: isNeeded))
        }

        struct AtomKey: Hashable {
            var bytes: [UInt8]
            var plan: Int
        }
        var atoms: [[UInt8]] = []
        var seenAtoms = Set<AtomKey>()
        for (id, segment) in program.segments.enumerated() {
            switch segment.kind {
            case .xor:
                program.xorSegments.append(id)
            case .regex(let regex):
                let planIndex = program.plans.count
                if let atom = regex.atom {
                    program.plans.append(YaraMatchPlan(segment: id, forward: [], backward: [], regex: regex,
                                                       regexLead: atom.leadMin...atom.leadMax))
                    for bytes in YaraAtoms.expand(atom.bytes)
                    where seenAtoms.insert(AtomKey(bytes: bytes, plan: planIndex)).inserted {
                        atoms.append(bytes)
                        program.atomPlans.append(Int32(planIndex))
                        program.atomSegments.append(Int32(id))
                        program.atomLengths.append(Int32(bytes.count))
                    }
                } else {
                    program.plans.append(YaraMatchPlan(segment: id, forward: [], backward: [], regex: regex))
                    program.linearPlans.append(planIndex)
                }
            case .pattern(let elements):
                let planIndex = program.plans.count
                if let choice = YaraAtoms.choose(elements) {
                    program.plans.append(YaraMatchPlan(segment: id, forward: choice.forward, backward: choice.backward))
                    for atom in choice.atoms where seenAtoms.insert(AtomKey(bytes: atom, plan: planIndex)).inserted {
                        atoms.append(atom)
                        program.atomPlans.append(Int32(planIndex))
                        program.atomSegments.append(Int32(id))
                        program.atomLengths.append(Int32(atom.count))
                    }
                } else {
                    program.plans.append(YaraMatchPlan(segment: id, forward: elements, backward: []))
                    program.linearPlans.append(planIndex)
                }
            }
        }
        program.automaton = YaraAtomAutomaton(patterns: atoms)
    }

    // MARK: Strings

    private static func displayName(_ name: String) -> String { name.isEmpty ? "$" : "$" + name }

    private static func compileStrings(_ rule: YaraParsedRule) throws -> [(name: String, chains: [YaraChain])] {
        var seen = Set<String>()
        var out: [(name: String, chains: [YaraChain])] = []
        for string in rule.strings {
            let shown = displayName(string.name)
            if !string.name.isEmpty, !seen.insert(string.name).inserted {
                throw YaraCompileIssue(reason: "Defines \(shown) twice")
            }
            let modifiers = string.modifiers
            switch string.value {
            case .regex(let body, let flags):
                if modifiers.base64 {
                    throw YaraCompileIssue(reason: "Uses a base64 string (\(shown)), which Spruce can't scan for")
                }
                if modifiers.xor != nil {
                    throw YaraCompileIssue(reason: "\(shown) combines xor with a regular expression, which YARA doesn't allow")
                }
                if let unknown = flags.first(where: { $0 != "i" && $0 != "s" }) {
                    throw YaraCompileIssue(reason: "\(shown) uses the regular expression flag \(unknown), which Spruce doesn't know")
                }
                do {
                    let root = try YaraRegexParser.parse(body, caseless: modifiers.nocase || flags.contains("i"),
                                                         dotAll: flags.contains("s"))
                    var forms: [Bool] = []
                    if modifiers.ascii || !modifiers.wide { forms.append(false) }
                    if modifiers.wide { forms.append(true) }
                    let chains = try forms.map { wide in
                        YaraChain(segments: [YaraSegment(kind: .regex(try YaraRegex(root: root, wide: wide)),
                                                         fullword: modifiers.fullword, wide: wide)], gaps: [])
                    }
                    out.append((string.name, chains))
                } catch let issue as YaraCompileIssue {
                    throw YaraCompileIssue(reason: "In \(shown), " + issue.reason)
                }
            case .hex(let body):
                if modifiers.ascii || modifiers.wide || modifiers.nocase || modifiers.fullword || modifiers.xor != nil
                    || modifiers.base64 {
                    throw YaraCompileIssue(reason: "Hex string \(shown) only takes the private modifier")
                }
                do {
                    let (segments, gaps) = try YaraHexParser.compile(body)
                    let chain = YaraChain(segments: segments.map { YaraSegment(kind: .pattern($0), fullword: false, wide: false) },
                                          gaps: gaps)
                    out.append((string.name, [chain]))
                } catch let issue as YaraCompileIssue {
                    throw YaraCompileIssue(reason: "In \(shown), " + issue.reason)
                }
            case .text(let bytes):
                if bytes.isEmpty { throw YaraCompileIssue(reason: "\(shown) is empty") }
                if modifiers.base64 {
                    throw YaraCompileIssue(reason: "Uses a base64 string (\(shown)), which Spruce can't scan for")
                }
                if modifiers.xor != nil, modifiers.nocase {
                    throw YaraCompileIssue(reason: "\(shown) combines xor and nocase, which YARA doesn't allow")
                }
                out.append((string.name, YaraTextPattern.chains(bytes, modifiers: modifiers)))
            }
        }
        return out
    }

    // MARK: Conditions

    private struct Scope {
        let rule: Int
        let ruleIndex: [String: Int]
        /// Rule names (first definition only) in sorted order, for wildcard sets.
        let sortedNames: [(name: String, index: Int)]
        let unavailable: Set<String>
        /// The rule's strings: name (empty for anonymous) and program index.
        var strings: [(name: String, index: Int)] = []
        var variables: [String] = []
        var slots = 1
        var forOfDepth = 0
        var dependencies = Set<Int>()
        var usedStrings = Set<Int>()

        init(rule: Int, ruleIndex: [String: Int], sortedNames: [(name: String, index: Int)], unavailable: Set<String>) {
            self.rule = rule
            self.ruleIndex = ruleIndex
            self.sortedNames = sortedNames
            self.unavailable = unavailable
        }

        /// Rules (other than this one) whose names start with `prefix`, at most `limit + 1`.
        func rules(withPrefix prefix: String, limit: Int) -> [Int] {
            var low = 0
            var high = sortedNames.count
            while low < high {
                let mid = (low + high) / 2
                if sortedNames[mid].name < prefix { low = mid + 1 } else { high = mid }
            }
            var out: [Int] = []
            var position = low
            while position < sortedNames.count, sortedNames[position].name.hasPrefix(prefix), out.count <= limit {
                if sortedNames[position].index != rule { out.append(sortedNames[position].index) }
                position += 1
            }
            return out.sorted()
        }
    }

    private static func moduleIssue(_ path: [String]) -> YaraCompileIssue {
        if path.first == "hash", path.count > 1 {
            return YaraCompileIssue(reason: "Uses hash.\(path[1]), which Spruce doesn't support")
        }
        return YaraCompileIssue(reason: "Uses the \(path[0]) module, which Spruce doesn't support")
    }

    private static func resolve(_ expr: YaraSyntaxExpr, _ scope: inout Scope) throws -> YaraExpr {
        switch expr {
        case .boolean(let value): return .constant(.boolean(value))
        case .integer(let value): return .constant(.integer(value))
        case .float(let value): return .constant(.float(value))
        case .text(let bytes):
            guard bytes.count <= maxConditionText else {
                throw YaraCompileIssue(reason: "A text in the condition is longer than \(maxConditionText) bytes")
            }
            return .constant(.text(bytes))
        case .filesize: return .filesize
        case .entrypoint:
            throw YaraCompileIssue(reason: "Uses entrypoint, which Spruce doesn't support")
        case .identifier(let name):
            if let slot = scope.variables.lastIndex(of: name) { return .variable(slot) }
            return .rule(try ruleReference(name, &scope))
        case .call(let path, let arguments):
            if path.count == 1, let read = integerReads[path[0]] {
                guard arguments.count == 1 else {
                    throw YaraCompileIssue(reason: "\(path[0]) takes one argument")
                }
                return .readInteger(read, try resolve(arguments[0], &scope))
            }
            if path.count == 2, path[0] == "hash", let function = hashFunctions[path[1]] {
                switch arguments.count {
                case 1: return .hashText(function, try resolve(arguments[0], &scope))
                case 2: return .hashRange(function, try resolve(arguments[0], &scope), try resolve(arguments[1], &scope))
                default: throw YaraCompileIssue(reason: "hash.\(path[1]) takes an offset and a size, or a text")
                }
            }
            if modules.contains(path[0]) { throw moduleIssue(path) }
            throw YaraCompileIssue(reason: "Uses an unknown function \(path.joined(separator: "."))")
        case .moduleValue(let path):
            if modules.contains(path[0]) { throw moduleIssue(path) }
            throw YaraCompileIssue(reason: "Uses an unknown identifier \(path.joined(separator: "."))")
        case .stringMatch(let name, let anchor):
            return .stringMatch(try stringReference(name, &scope), try resolve(anchor, &scope))
        case .stringCount(let name, let anchor):
            return .stringCount(try stringReference(name, &scope), try resolve(anchor, &scope))
        case .stringOffset(let name, let index):
            let ref = try stringReference(name, &scope)
            return .stringOffset(ref, try index.map { try resolve($0, &scope) } ?? .constant(.integer(1)))
        case .stringLength(let name, let index):
            let ref = try stringReference(name, &scope)
            return .stringLength(ref, try index.map { try resolve($0, &scope) } ?? .constant(.integer(1)))
        case .unary(let op, let operand):
            return .unary(op, try resolve(operand, &scope))
        case .binary(let op, let lhs, let rhs):
            return .binary(op, try resolve(lhs, &scope), try resolve(rhs, &scope))
        case .and(let items):
            var flat: [YaraExpr] = []
            for item in items {
                let resolved = try resolve(item, &scope)
                if case .and(let inner) = resolved { flat += inner } else { flat.append(resolved) }
            }
            return .and(flat)
        case .or(let items):
            var flat: [YaraExpr] = []
            for item in items {
                let resolved = try resolve(item, &scope)
                if case .or(let inner) = resolved { flat += inner } else { flat.append(resolved) }
            }
            return .or(flat)
        case .not(let operand):
            return .not(try resolve(operand, &scope))
        case .defined(let operand):
            return .defined(try resolve(operand, &scope))
        case .of(let quantifier, let set, let anchor):
            let q = try resolve(quantifier, &scope)
            switch try resolve(set, &scope) {
            case .strings(let indices):
                return .ofStrings(q, indices, try resolve(anchor, &scope))
            case .rules(let indices):
                guard case .anywhere = anchor else {
                    throw YaraCompileIssue(reason: "A set of rules can't have at or in")
                }
                return .ofRules(q, indices)
            }
        case .forOf(let quantifier, let set, let body):
            let q = try resolve(quantifier, &scope)
            guard case .strings(let indices) = try resolve(set, &scope) else {
                throw YaraCompileIssue(reason: "for … of needs a set of strings")
            }
            scope.forOfDepth += 1
            defer { scope.forOfDepth -= 1 }
            return .forOf(q, indices, try resolve(body, &scope))
        case .forIn(let quantifier, let names, let iterable, let body):
            let q = try resolve(quantifier, &scope)
            guard names.count == 1 else {
                throw YaraCompileIssue(reason: "Loops over module dictionaries, which Spruce doesn't support")
            }
            let resolvedIterable: YaraIterable
            switch iterable {
            case .range(let low, let high):
                resolvedIterable = .range(try resolve(low, &scope), try resolve(high, &scope))
            case .list(let items):
                resolvedIterable = .list(try items.map { try resolve($0, &scope) })
            case .unsupported(let name):
                if modules.contains(name) { throw moduleIssue([name]) }
                throw YaraCompileIssue(reason: "Loops over \(name), which Spruce doesn't support")
            }
            let slot = scope.variables.count
            scope.variables.append(names[0])
            scope.slots = max(scope.slots, scope.variables.count)
            defer { scope.variables.removeLast() }
            return .forIn(q, slot, resolvedIterable, try resolve(body, &scope))
        case .unsupported(let what):
            throw YaraCompileIssue(reason: "Uses \(what), which Spruce doesn't support")
        }
    }

    private static func resolve(_ anchor: YaraSyntaxAnchor, _ scope: inout Scope) throws -> YaraAnchor {
        switch anchor {
        case .anywhere: return .anywhere
        case .at(let offset): return .at(try resolve(offset, &scope))
        case .within(let low, let high): return .within(try resolve(low, &scope), try resolve(high, &scope))
        }
    }

    private static func resolve(_ quantifier: YaraSyntaxQuantifier, _ scope: inout Scope) throws -> YaraQuantifier {
        switch quantifier {
        case .all: return .all
        case .any: return .any
        case .none: return .none
        case .count(let expr): return .atLeast(try resolve(expr, &scope))
        case .percent(let expr):
            // As in YARA; a percentage worked out while scanning is capped at 100.
            if case .integer(let value) = expr, !(1...100).contains(value) {
                throw YaraCompileIssue(reason: "A percentage must be between 1 and 100")
            }
            return .percent(try resolve(expr, &scope))
        }
    }

    private enum ResolvedSet {
        case strings([Int])
        case rules([Int])
    }

    private static func resolve(_ set: YaraSyntaxSet, _ scope: inout Scope) throws -> ResolvedSet {
        func add(_ index: Int, to list: inout [Int]) {
            if !list.contains(index) { list.append(index) }
        }
        switch set {
        case .them:
            guard !scope.strings.isEmpty else { throw YaraCompileIssue(reason: "Uses them, but the rule has no strings") }
            let all = scope.strings.map(\.index)
            scope.usedStrings.formUnion(all)
            return .strings(all)
        case .items(let items):
            var strings: [Int] = []
            var rules: [Int] = []
            for item in items {
                switch item {
                case .string(let name, let wildcard):
                    if wildcard {
                        let matching = scope.strings.filter { name.isEmpty || (!$0.name.isEmpty && $0.name.hasPrefix(name)) }
                        guard !matching.isEmpty else {
                            throw YaraCompileIssue(reason: "$\(name)* doesn't match any string")
                        }
                        for string in matching { add(string.index, to: &strings) }
                    } else {
                        guard !name.isEmpty, let string = scope.strings.first(where: { $0.name == name }) else {
                            throw YaraCompileIssue(reason: "Uses \(displayName(name)), which isn't defined")
                        }
                        add(string.index, to: &strings)
                    }
                case .rule(let name, let wildcard):
                    if wildcard {
                        let matching = scope.rules(withPrefix: name, limit: maxWildcardRules)
                        guard !matching.isEmpty else { throw YaraCompileIssue(reason: "\(name)* doesn't match any rule") }
                        guard matching.count <= maxWildcardRules else {
                            throw YaraCompileIssue(reason: "\(name)* matches more than \(maxWildcardRules) rules")
                        }
                        for index in matching {
                            scope.dependencies.insert(index)
                            add(index, to: &rules)
                        }
                    } else {
                        add(try ruleReference(name, &scope), to: &rules)
                    }
                }
            }
            if !strings.isEmpty, !rules.isEmpty {
                throw YaraCompileIssue(reason: "A set can't mix strings and rules")
            }
            if rules.isEmpty {
                scope.usedStrings.formUnion(strings)
                return .strings(strings)
            }
            return .rules(rules)
        }
    }

    private static func ruleReference(_ name: String, _ scope: inout Scope) throws -> Int {
        if let index = scope.ruleIndex[name] {
            guard index != scope.rule else { throw YaraCompileIssue(reason: "Refers to itself") }
            scope.dependencies.insert(index)
            return index
        }
        if scope.unavailable.contains(name) {
            throw YaraCompileIssue(reason: "Uses rule \(name), which was skipped")
        }
        if modules.contains(name) { throw moduleIssue([name]) }
        throw YaraCompileIssue(reason: "Uses an unknown identifier \(name)")
    }

    private static func stringReference(_ name: String, _ scope: inout Scope) throws -> YaraStringRef {
        if name.isEmpty {
            guard scope.forOfDepth > 0 else {
                throw YaraCompileIssue(reason: "Uses an anonymous string outside a for … of loop")
            }
            return .current
        }
        guard let string = scope.strings.first(where: { $0.name == name }) else {
            throw YaraCompileIssue(reason: "Uses $\(name), which isn't defined")
        }
        scope.usedStrings.insert(string.index)
        return .string(string.index)
    }
}
