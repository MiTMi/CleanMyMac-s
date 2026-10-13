import Foundation

// String search for one scan: a single Aho–Corasick pass over the data finds atom
// candidates, which are verified by bounded backtracking around the atom. Segments without
// an atom (and XOR strings) are scanned linearly up to a byte limit. Every step counts
// against per-candidate and per-scan budgets, so hostile rules or files can't hang a scan.

/// Where a string (or segment) matched: `start..<end` in the scanned bytes.
struct YaraSpan: Sendable, Hashable {
    var start: Int
    var end: Int
}

// MARK: - Aho–Corasick

/// Multi-pattern automaton over short atoms. Shallow states (the root and its children,
/// where the scan spends most of its time) get full 256-entry rows; deeper states keep
/// sparse transitions and fall back along failure links, so memory stays small however
/// many atoms a rule file has.
struct YaraAtomAutomaton: Sendable {
    private var fail: [Int32] = [0]
    private var childStart: [Int32] = [0]
    private var childCount: [Int32] = [0]
    private var childBytes: [UInt8] = []
    private var childTargets: [Int32] = []
    private var denseRow: [Int32] = [0]
    private var dense: [Int32] = [Int32](repeating: 0, count: 256)
    private var outputStart: [Int32] = [0]
    private var outputCount: [Int32] = [0]
    private var outputs: [Int32] = []
    private(set) var patternCount = 0

    init() {}

    /// Builds the automaton; a hit reports the pattern's index in `patterns`.
    init(patterns: [[UInt8]]) {
        // Trie as first-child / next-sibling lists (small, whatever the number of atoms).
        var firstChild: [Int32] = [-1]
        var nextSibling: [Int32] = [-1]
        var label: [UInt8] = [0]
        var depth: [Int32] = [0]
        var found: [[Int32]] = [[]]
        func childOf(_ node: Int, _ byte: UInt8) -> Int? {
            var child = Int(firstChild[node])
            while child >= 0 {
                if label[child] == byte { return child }
                child = Int(nextSibling[child])
            }
            return nil
        }
        for (index, pattern) in patterns.enumerated() where !pattern.isEmpty {
            var node = 0
            for byte in pattern {
                if let next = childOf(node, byte) {
                    node = next
                } else {
                    let next = label.count
                    label.append(byte)
                    depth.append(depth[node] + 1)
                    found.append([])
                    firstChild.append(-1)
                    nextSibling.append(firstChild[node])
                    firstChild[node] = Int32(next)
                    node = next
                }
            }
            found[node].append(Int32(index))
            patternCount += 1
        }
        let count = label.count
        func children(_ node: Int) -> [(UInt8, Int)] {
            var out: [(UInt8, Int)] = []
            var child = Int(firstChild[node])
            while child >= 0 {
                out.append((label[child], child))
                child = Int(nextSibling[child])
            }
            return out.sorted { $0.0 < $1.0 }
        }

        // Failure links, breadth first.
        var fail = [Int32](repeating: 0, count: count)
        var queue = children(0).map(\.1)
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            for (byte, child) in children(node) {
                queue.append(child)
                var back = Int(fail[node])
                while true {
                    if let next = childOf(back, byte) {
                        fail[child] = Int32(next)
                        break
                    }
                    if back == 0 { break }
                    back = Int(fail[back])
                }
                found[child] += found[Int(fail[child])]
            }
        }
        self.fail = fail

        childStart = []
        childCount = []
        childStart.reserveCapacity(count)
        childCount.reserveCapacity(count)
        outputStart = []
        outputCount = []
        for node in 0..<count {
            let list = children(node)
            childStart.append(Int32(childBytes.count))
            childCount.append(Int32(list.count))
            for (byte, child) in list {
                childBytes.append(byte)
                childTargets.append(Int32(child))
            }
            outputStart.append(Int32(outputs.count))
            outputCount.append(Int32(found[node].count))
            outputs += found[node]
        }

        // Full rows for the root and depth-1 states.
        denseRow = [Int32](repeating: -1, count: count)
        dense = []
        var rootRow = [Int32](repeating: 0, count: 256)
        for (byte, child) in children(0) { rootRow[Int(byte)] = Int32(child) }
        denseRow[0] = 0
        dense += rootRow
        for node in 1..<max(1, count) where depth[node] == 1 {
            denseRow[node] = Int32(dense.count / 256)
            var row = rootRow
            for (byte, child) in children(node) { row[Int(byte)] = Int32(child) }
            dense += row
        }
    }

    private func child(of node: Int, _ byte: UInt8) -> Int32? {
        let start = Int(childStart[node])
        for index in start..<start + Int(childCount[node]) where childBytes[index] == byte {
            return childTargets[index]
        }
        return nil
    }

    /// Calls `hit(endIndex, pattern)` for every atom occurrence (`endIndex` is its last byte).
    func scan(_ data: UnsafeBufferPointer<UInt8>, _ hit: (Int, Int) -> Void) {
        guard patternCount > 0, !data.isEmpty else { return }
        denseRow.withUnsafeBufferPointer { denseRow in
            dense.withUnsafeBufferPointer { dense in
                outputCount.withUnsafeBufferPointer { outputCount in
                    var state = 0
                    for index in 0..<data.count {
                        let byte = data[index]
                        var node = state
                        while true {
                            let row = Int(denseRow[node])
                            if row >= 0 {
                                state = Int(dense[row &* 256 &+ Int(byte)])
                                break
                            }
                            if let next = child(of: node, byte) {
                                state = Int(next)
                                break
                            }
                            node = Int(fail[node])
                        }
                        let hits = Int(outputCount[state])
                        if hits > 0 {
                            let first = Int(outputStart[state])
                            for k in first..<first + hits { hit(index, Int(outputs[k])) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Backtracking

/// Matches pattern elements forwards or backwards with a step budget.
final class YaraWalker {
    let data: UnsafeBufferPointer<UInt8>
    var steps: Int
    private(set) var exhausted = false

    init(data: UnsafeBufferPointer<UInt8>, steps: Int) {
        self.data = data
        self.steps = steps
    }

    /// Calls `found` with each position where `elements[index...]` can end when matched from
    /// `position` in direction `direction` (+1 forwards, -1 backwards), shortest jumps first,
    /// until `found` returns true. Returns true when stopped (by `found` or the budget).
    @discardableResult
    func walk(_ elements: [YaraPatternElement], _ index: Int, _ position: Int, _ direction: Int,
              _ found: (Int) -> Bool) -> Bool {
        if steps <= 0 {
            exhausted = true
            return true
        }
        steps -= 1
        if index == elements.count { return found(position) }
        switch elements[index] {
        case .run(let bytes):
            guard let next = Self.matchRun(bytes, data, position, direction) else { return false }
            steps -= bytes.count >> 4
            return walk(elements, index + 1, next, direction, found)
        case .jump(let low, let high):
            let room = direction > 0 ? data.count - position : position
            guard low <= room else { return false }
            for length in low...min(high, room) {
                if walk(elements, index + 1, position + direction * length, direction, found) { return true }
            }
            return false
        case .alternatives(let branches):
            for branch in branches {
                let stopped = walk(branch, 0, position, direction) { next in
                    self.walk(elements, index + 1, next, direction, found)
                }
                if stopped { return true }
            }
            return false
        }
    }

    /// Matches a run of bytes; backwards runs are stored reversed. Returns the new position.
    @inline(__always)
    static func matchRun(_ bytes: [YaraPatternByte], _ data: UnsafeBufferPointer<UInt8>, _ position: Int,
                         _ direction: Int) -> Int? {
        let count = bytes.count
        if direction > 0 {
            guard position >= 0, position + count <= data.count else { return nil }
            for k in 0..<count where !bytes[k].matches(data[position + k]) { return nil }
            return position + count
        }
        guard position - count >= 0, position <= data.count else { return nil }
        for k in 0..<count where !bytes[k].matches(data[position - 1 - k]) { return nil }
        return position - count
    }
}

// MARK: - Search

/// Finds every string of a program in one buffer.
final class YaraSearch {
    private let program: YaraProgram
    private let data: UnsafeBufferPointer<UInt8>
    private let limits: YaraScanLimits
    private var hits: [[YaraSpan]]
    private var seen: [Set<Int>]
    /// Segments that stopped collecting matches (enough found, or out of work).
    private var full: [Bool]
    private var stepsLeft: Int
    private var segmentSteps: [Int]
    private(set) var notes: [String] = []

    init(program: YaraProgram, data: UnsafeBufferPointer<UInt8>, limits: YaraScanLimits) {
        self.program = program
        self.data = data
        self.limits = limits
        hits = Array(repeating: [], count: program.segments.count)
        seen = Array(repeating: [], count: program.segments.count)
        full = Array(repeating: false, count: program.segments.count)
        stepsLeft = max(0, limits.maxTotalSteps)
        segmentSteps = Array(repeating: max(0, limits.maxStepsPerString), count: program.segments.count)
    }

    private func note(_ text: String) {
        if !notes.contains(text) { notes.append(text) }
    }

    /// Counts work against the scan and the segment; a segment out of work stops (with a note)
    /// so one pathological string can't starve the others.
    private func charge(_ segment: Int, _ steps: Int) {
        stepsLeft -= steps
        segmentSteps[segment] -= steps
        if segmentSteps[segment] <= 0, !full[segment] {
            full[segment] = true
            note("A string needed too much work to finish; some of its matches may be missing.")
        }
    }

    /// Match spans of every string (empty for strings no loaded rule uses).
    func run() -> [[YaraSpan]] {
        let atomPlans = program.atomPlans
        let atomLengths = program.atomLengths
        let atomSegments = program.atomSegments
        program.automaton.scan(data) { end, atom in
            guard !full[Int(atomSegments[atom])] else { return }
            verify(Int(atomPlans[atom]), at: end - Int(atomLengths[atom]) + 1)
        }
        for plan in program.linearPlans { scanLinearly(plan) }
        for segment in program.xorSegments { scanXor(segment) }
        if stepsLeft <= 0 { note("The scan stopped matching strings early because it reached its work limit.") }
        return program.strings.map { $0.isNeeded ? assemble($0) : [] }
    }

    // MARK: Verification

    private func verify(_ planIndex: Int, at position: Int) {
        let plan = program.plans[planIndex]
        let segment = plan.segment
        guard !full[segment], position >= 0, stepsLeft > 0 else { return }

        // Fast path: a single run forwards and at most one run backwards (most strings).
        if plan.forward.count == 1, case .run(let forward) = plan.forward[0] {
            var backward: [YaraPatternByte]?
            if plan.backward.isEmpty {
                backward = []
            } else if plan.backward.count == 1, case .run(let run) = plan.backward[0] {
                backward = run
            }
            if let backward {
                if let end = YaraWalker.matchRun(forward, data, position, 1),
                   let start = backward.isEmpty ? position : YaraWalker.matchRun(backward, data, position, -1) {
                    record(segment, YaraSpan(start: start, end: end))
                }
                charge(segment, 1 + (forward.count + backward.count) >> 4)
                return
            }
        }

        let budget = min(limits.maxStepsPerCandidate, stepsLeft, segmentSteps[segment])
        let walker = YaraWalker(data: data, steps: budget)
        defer { charge(segment, max(1, budget - walker.steps)) }
        var end: Int?
        walker.walk(plan.forward, 0, position, 1) { found in
            end = found
            return true
        }
        guard let end, !walker.exhausted else { return }
        if plan.backward.isEmpty {
            record(segment, YaraSpan(start: position, end: end))
            return
        }
        var starts: [Int] = []
        let cap = limits.maxMatchesPerString
        walker.walk(plan.backward, 0, position, -1) { start in
            starts.append(start)
            return starts.count >= cap
        }
        for start in starts { record(segment, YaraSpan(start: start, end: end)) }
    }

    private func record(_ segment: Int, _ span: YaraSpan) {
        guard !full[segment] else { return }
        let info = program.segments[segment]
        if info.fullword, !isFullword(span, wide: info.wide) { return }
        guard seen[segment].insert(span.start).inserted else { return }
        hits[segment].append(span)
        if hits[segment].count >= limits.maxMatchesPerString {
            full[segment] = true
            note("A string matched more than \(limits.maxMatchesPerString) times; later matches were not counted.")
        }
    }

    private func isFullword(_ span: YaraSpan, wide: Bool) -> Bool {
        let isWord = YaraTextPattern.isAlphanumeric
        if wide {
            if span.start >= 2, isWord(data[span.start - 2]), data[span.start - 1] == 0 { return false }
            if span.end + 1 < data.count, isWord(data[span.end]), data[span.end + 1] == 0 { return false }
        } else {
            if span.start > 0, isWord(data[span.start - 1]) { return false }
            if span.end < data.count, isWord(data[span.end]) { return false }
        }
        return true
    }

    // MARK: Linear scans

    private var linearLimit: Int {
        if data.count > limits.linearScanBytes {
            note("Some strings were only looked for in the first \(ByteFormat.string(Int64(limits.linearScanBytes))).")
        }
        return min(data.count, max(0, limits.linearScanBytes))
    }

    private func scanLinearly(_ planIndex: Int) {
        let plan = program.plans[planIndex]
        let limit = linearLimit
        var first: YaraPatternByte?
        if case .run(let bytes)? = plan.forward.first, let byte = bytes.first, byte.mask != 0 { first = byte }
        for position in 0..<limit {
            if full[plan.segment] || stepsLeft <= 0 { break }
            if let first, !first.matches(data[position]) { continue }
            verify(planIndex, at: position)
        }
        charge(plan.segment, limit >> 4)
    }

    private func scanXor(_ segment: Int) {
        guard case .xor(let bytes, let keys) = program.segments[segment].kind, !bytes.isEmpty,
              bytes.count <= data.count else { return }
        let limit = min(data.count - bytes.count + 1, linearLimit)
        let count = bytes.count
        let head = bytes[0]
        bytes.withUnsafeBufferPointer { pattern in
            for position in 0..<limit {
                if full[segment] || stepsLeft <= 0 { break }
                let key = data[position] ^ head
                guard keys.contains(Int(key)) else { continue }
                var k = 1
                while k < count, data[position + k] ^ key == pattern[k] { k += 1 }
                if k == count { record(segment, YaraSpan(start: position, end: position + count)) }
            }
        }
        charge(segment, limit >> 4)
    }

    // MARK: Strings

    private func assemble(_ string: YaraProgramString) -> [YaraSpan] {
        var spans: [YaraSpan] = []
        for chain in string.chains {
            if chain.segments.count == 1 {
                spans += hits[chain.segments[0]]
            } else {
                spans += chained(chain)
            }
        }
        spans.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        var out: [YaraSpan] = []
        out.reserveCapacity(min(spans.count, limits.maxMatchesPerString))
        for span in spans where out.last?.start != span.start {
            out.append(span)
            if out.count >= limits.maxMatchesPerString { break }
        }
        return out
    }

    /// Joins segment matches whose distances fit the gaps (like YARA's chained strings).
    private func chained(_ chain: YaraProgramChain) -> [YaraSpan] {
        guard let last = chain.segments.last else { return [] }
        var next = hits[last].sorted { $0.start < $1.start }
        for level in stride(from: chain.segments.count - 2, through: 0, by: -1) {
            let gap = chain.gaps[level]
            var current: [YaraSpan] = []
            for hit in hits[chain.segments[level]].sorted(by: { $0.start < $1.start }) {
                let low = hit.end + gap.min
                let high = gap.max.map { hit.end + $0 } ?? Int.max
                var lo = 0
                var hi = next.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if next[mid].start < low { lo = mid + 1 } else { hi = mid }
                }
                if lo < next.count, next[lo].start <= high {
                    current.append(YaraSpan(start: hit.start, end: next[lo].end))
                }
            }
            next = current
            if next.isEmpty { break }
        }
        return next
    }
}
