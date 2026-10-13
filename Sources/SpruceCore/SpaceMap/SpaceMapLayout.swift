import Foundation

// MARK: - Geometry

/// A circle in layout coordinates (y grows downwards in view space).
public struct SpaceMapCircle: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var r: Double

    public init(x: Double, y: Double, r: Double) {
        self.x = x
        self.y = y
        self.r = r
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        let dx = px - x
        let dy = py - y
        return dx * dx + dy * dy <= r * r
    }

    /// True when the two discs overlap by more than `tolerance`.
    public func overlaps(_ other: SpaceMapCircle, tolerance: Double = 1e-6) -> Bool {
        let dx = other.x - x
        let dy = other.y - y
        let distance = (dx * dx + dy * dy).squareRoot()
        return distance + tolerance < r + other.r
    }

    /// True when `other` lies inside this circle (within `tolerance`).
    public func encloses(_ other: SpaceMapCircle, tolerance: Double = 1e-6) -> Bool {
        let dx = other.x - x
        let dy = other.y - y
        return (dx * dx + dy * dy).squareRoot() + other.r <= r + tolerance
    }

    public var area: Double { Double.pi * r * r }
}

// MARK: - Circle packing

/// Area-proportional circle packing (front-chain sibling packing, as popularised by
/// d3-hierarchy, plus a minimal enclosing circle). Pure geometry.
public enum SpaceMapPack {

    /// Packs circles of the given radii (in the given order; pass them largest first so
    /// the biggest sits in the middle) tangent to each other around the origin. Returns
    /// the positioned circles in input order and their enclosing circle, which is
    /// centred on the origin.
    public static func siblings(radii input: [Double]) -> (circles: [SpaceMapCircle], enclosing: SpaceMapCircle) {
        let n = input.count
        guard n > 0 else { return ([], SpaceMapCircle(x: 0, y: 0, r: 0)) }
        var chain = FrontChain(radii: input.map { max($0, 0) })
        chain.xs[0] = 0
        chain.ys[0] = 0
        if n == 1 {
            let only = SpaceMapCircle(x: 0, y: 0, r: chain.rs[0])
            return ([only], only)
        }
        chain.xs[0] = -chain.rs[1]
        chain.xs[1] = chain.rs[0]
        chain.ys[1] = 0
        if n == 2 {
            let circles = chain.circles
            return (circles, SpaceMapCircle(x: 0, y: 0, r: chain.rs[0] + chain.rs[1]))
        }
        chain.place(1, 0, 2)
        var a = 0
        var b = 1
        let c0 = 2
        chain.next[a] = b; chain.prev[b] = a
        chain.next[b] = c0; chain.prev[c0] = b
        chain.next[c0] = a; chain.prev[a] = c0

        var i = 3
        var retries = 0
        let retryLimit = n * n * 8 + 64
        while i < n {
            chain.place(a, b, i)
            let c = i
            var j = chain.next[b]
            var k = chain.prev[a]
            var sj = chain.rs[b]
            var sk = chain.rs[a]
            var restart = false
            repeat {
                if sj <= sk {
                    if chain.intersects(j, c) {
                        b = j
                        chain.next[a] = b
                        chain.prev[b] = a
                        restart = true
                        break
                    }
                    sj += chain.rs[j]
                    j = chain.next[j]
                } else {
                    if chain.intersects(k, c) {
                        a = k
                        chain.next[a] = b
                        chain.prev[b] = a
                        restart = true
                        break
                    }
                    sk += chain.rs[k]
                    k = chain.prev[k]
                }
            } while j != chain.next[k]

            if restart {
                retries += 1
                if retries <= retryLimit { continue }
                // Degenerate input: park the circle outside everything placed so far.
                chain.parkOutside(c, placedCount: c)
                i += 1
                continue
            }

            // Insert c between a and b.
            chain.prev[c] = a
            chain.next[c] = b
            chain.next[a] = c
            chain.prev[b] = c
            b = c

            // Choose the pair closest to the centre for the next placement.
            var best = chain.score(a)
            var cursor = chain.next[c]
            while cursor != b {
                let s = chain.score(cursor)
                if s < best {
                    a = cursor
                    best = s
                }
                cursor = chain.next[cursor]
            }
            b = chain.next[a]
            i += 1
        }

        let circles = chain.circles
        let enclosingCircle = enclose(circles)
        let shifted = circles.map { SpaceMapCircle(x: $0.x - enclosingCircle.x, y: $0.y - enclosingCircle.y, r: $0.r) }
        return (shifted, SpaceMapCircle(x: 0, y: 0, r: enclosingCircle.r))
    }

    /// Smallest circle enclosing all `circles` (Welzl-style move-to-front with a
    /// deterministic shuffle).
    public static func enclose(_ input: [SpaceMapCircle]) -> SpaceMapCircle {
        guard !input.isEmpty else { return SpaceMapCircle(x: 0, y: 0, r: 0) }
        var circles = input
        var random = SpaceMapLCG()
        var m = circles.count
        while m > 0 {
            let index = Int(random.next() * Double(m))
            m -= 1
            circles.swapAt(m, min(index, m))
        }
        var basis: [SpaceMapCircle] = []
        var current: SpaceMapCircle?
        var i = 0
        var steps = 0
        let stepLimit = circles.count * circles.count * 64 + 256
        while i < circles.count && steps < stepLimit {
            steps += 1
            let p = circles[i]
            if let e = current, enclosesWeak(e, p) {
                i += 1
            } else if let extended = extendBasis(basis, p) {
                basis = extended
                current = encloseBasis(basis)
                i = 0
            } else {
                break
            }
        }
        if let current, input.allSatisfy({ current.encloses($0, tolerance: max(current.r, 1) * 1e-6) }) {
            return current
        }
        return boundingCircle(input)
    }

    /// Packs `values` (e.g. byte counts) so each disc's area is proportional to its value,
    /// scaled to fit a `width` × `height` box with `inset` points of margin. `gap` is the
    /// spacing between discs relative to the largest radius.
    public static func layout(values: [Double], width: Double, height: Double,
                              gap: Double = 0.025, inset: Double = 8) -> [SpaceMapCircle] {
        guard !values.isEmpty, width > 0, height > 0 else { return [] }
        let largest = values.max() ?? 0
        let radii: [Double]
        if largest <= 0 {
            radii = values.map { _ in 1 }
        } else {
            let floor = largest * 1e-4
            radii = values.map { (max($0, floor) / largest).squareRoot() }
        }
        let packed = siblings(radii: radii.map { $0 + gap })
        let available = max(1, min(width, height) / 2 - inset)
        let scale = packed.enclosing.r > 0 ? available / packed.enclosing.r : 1
        let cx = width / 2
        let cy = height / 2
        return zip(packed.circles, radii).map { circle, radius in
            SpaceMapCircle(x: cx + circle.x * scale, y: cy + circle.y * scale, r: radius * scale)
        }
    }

    /// Index of the disc under a point (the smallest one if several overlap).
    public static func hitTest(_ circles: [SpaceMapCircle], x: Double, y: Double) -> Int? {
        var best: Int?
        for (index, circle) in circles.enumerated() where circle.contains(x: x, y: y) {
            if let current = best, circles[current].r <= circle.r { continue }
            best = index
        }
        return best
    }

    // MARK: Internals

    private struct FrontChain {
        var xs: [Double]
        var ys: [Double]
        var rs: [Double]
        var next: [Int]
        var prev: [Int]

        init(radii: [Double]) {
            rs = radii
            xs = Array(repeating: 0, count: radii.count)
            ys = Array(repeating: 0, count: radii.count)
            next = Array(repeating: -1, count: radii.count)
            prev = Array(repeating: -1, count: radii.count)
        }

        var circles: [SpaceMapCircle] {
            rs.indices.map { SpaceMapCircle(x: xs[$0], y: ys[$0], r: rs[$0]) }
        }

        /// Places c tangent to both a and b.
        mutating func place(_ b: Int, _ a: Int, _ c: Int) {
            let dx = xs[b] - xs[a]
            let dy = ys[b] - ys[a]
            let d2 = dx * dx + dy * dy
            if d2 > 0 {
                var a2 = rs[a] + rs[c]
                a2 *= a2
                var b2 = rs[b] + rs[c]
                b2 *= b2
                if a2 > b2 {
                    let x = (d2 + b2 - a2) / (2 * d2)
                    let y = max(0, b2 / d2 - x * x).squareRoot()
                    xs[c] = xs[b] - x * dx - y * dy
                    ys[c] = ys[b] - x * dy + y * dx
                } else {
                    let x = (d2 + a2 - b2) / (2 * d2)
                    let y = max(0, a2 / d2 - x * x).squareRoot()
                    xs[c] = xs[a] + x * dx - y * dy
                    ys[c] = ys[a] + x * dy + y * dx
                }
            } else {
                xs[c] = xs[a] + rs[c]
                ys[c] = ys[a]
            }
        }

        func intersects(_ a: Int, _ b: Int) -> Bool {
            let dr = rs[a] + rs[b] - 1e-6
            let dx = xs[b] - xs[a]
            let dy = ys[b] - ys[a]
            return dr > 0 && dr * dr > dx * dx + dy * dy
        }

        /// Squared distance of the radius-weighted midpoint of (a, next(a)) to the origin.
        func score(_ a: Int) -> Double {
            let b = next[a]
            let ab = rs[a] + rs[b]
            guard ab > 0 else { return xs[a] * xs[a] + ys[a] * ys[a] }
            let dx = (xs[a] * rs[b] + xs[b] * rs[a]) / ab
            let dy = (ys[a] * rs[b] + ys[b] * rs[a]) / ab
            return dx * dx + dy * dy
        }

        /// Fallback for degenerate inputs: to the right of every placed circle.
        mutating func parkOutside(_ c: Int, placedCount: Int) {
            var maxX = 0.0
            for index in 0..<placedCount { maxX = max(maxX, xs[index] + rs[index]) }
            xs[c] = maxX + rs[c]
            ys[c] = 0
        }
    }

    private static func enclosesWeak(_ a: SpaceMapCircle, _ b: SpaceMapCircle) -> Bool {
        let dr = a.r - b.r + max(a.r, b.r, 1) * 1e-9
        let dx = b.x - a.x
        let dy = b.y - a.y
        return dr > 0 && dr * dr > dx * dx + dy * dy
    }

    private static func enclosesNot(_ a: SpaceMapCircle, _ b: SpaceMapCircle) -> Bool {
        let dr = a.r - b.r
        let dx = b.x - a.x
        let dy = b.y - a.y
        return dr < 0 || dr * dr < dx * dx + dy * dy
    }

    private static func enclosesWeakAll(_ a: SpaceMapCircle, _ basis: [SpaceMapCircle]) -> Bool {
        basis.allSatisfy { enclosesWeak(a, $0) }
    }

    private static func extendBasis(_ basis: [SpaceMapCircle], _ p: SpaceMapCircle) -> [SpaceMapCircle]? {
        if enclosesWeakAll(p, basis) { return [p] }
        for i in basis.indices {
            if enclosesNot(p, basis[i]), let pair = encloseBasis2(basis[i], p), enclosesWeakAll(pair, basis) {
                return [basis[i], p]
            }
        }
        if basis.count >= 2 {
            for i in 0..<(basis.count - 1) {
                for j in (i + 1)..<basis.count {
                    guard let ij = encloseBasis2(basis[i], basis[j]),
                          let ip = encloseBasis2(basis[i], p),
                          let jp = encloseBasis2(basis[j], p),
                          let triple = encloseBasis3(basis[i], basis[j], p) else { continue }
                    if enclosesNot(ij, p) && enclosesNot(ip, basis[j]) && enclosesNot(jp, basis[i])
                        && enclosesWeakAll(triple, basis) {
                        return [basis[i], basis[j], p]
                    }
                }
            }
        }
        return nil
    }

    private static func encloseBasis(_ basis: [SpaceMapCircle]) -> SpaceMapCircle? {
        switch basis.count {
        case 1: return basis[0]
        case 2: return encloseBasis2(basis[0], basis[1])
        case 3: return encloseBasis3(basis[0], basis[1], basis[2])
        default: return nil
        }
    }

    private static func encloseBasis2(_ a: SpaceMapCircle, _ b: SpaceMapCircle) -> SpaceMapCircle? {
        let x21 = b.x - a.x
        let y21 = b.y - a.y
        let r21 = b.r - a.r
        let l = (x21 * x21 + y21 * y21).squareRoot()
        guard l > 0 else { return a.r >= b.r ? a : b }
        return SpaceMapCircle(x: (a.x + b.x + x21 / l * r21) / 2,
                              y: (a.y + b.y + y21 / l * r21) / 2,
                              r: (l + a.r + b.r) / 2)
    }

    private static func encloseBasis3(_ a: SpaceMapCircle, _ b: SpaceMapCircle, _ c: SpaceMapCircle) -> SpaceMapCircle? {
        let x1 = a.x, y1 = a.y, r1 = a.r
        let x2 = b.x, y2 = b.y, r2 = b.r
        let x3 = c.x, y3 = c.y, r3 = c.r
        let a2 = x1 - x2
        let a3 = x1 - x3
        let b2 = y1 - y2
        let b3 = y1 - y3
        let c2 = r2 - r1
        let c3 = r3 - r1
        let d1 = x1 * x1 + y1 * y1 - r1 * r1
        let d2 = d1 - x2 * x2 - y2 * y2 + r2 * r2
        let d3 = d1 - x3 * x3 - y3 * y3 + r3 * r3
        let ab = a3 * b2 - a2 * b3
        guard ab != 0 else { return nil }
        let xa = (b2 * d3 - b3 * d2) / (ab * 2) - x1
        let xb = (b3 * c2 - b2 * c3) / ab
        let ya = (a3 * d2 - a2 * d3) / (ab * 2) - y1
        let yb = (a2 * c3 - a3 * c2) / ab
        let qa = xb * xb + yb * yb - 1
        let qb = 2 * (r1 + xa * xb + ya * yb)
        let qc = xa * xa + ya * ya - r1 * r1
        let r: Double
        if abs(qa) > 1e-6 {
            r = -(qb + max(0, qb * qb - 4 * qa * qc).squareRoot()) / (2 * qa)
        } else {
            guard qb != 0 else { return nil }
            r = -(qc / qb)
        }
        guard r.isFinite else { return nil }
        return SpaceMapCircle(x: x1 + xa + xb * r, y: y1 + ya + yb * r, r: r)
    }

    /// Simple (not minimal) enclosing circle, used only if the exact method fails.
    private static func boundingCircle(_ circles: [SpaceMapCircle]) -> SpaceMapCircle {
        let cx = circles.reduce(0) { $0 + $1.x } / Double(circles.count)
        let cy = circles.reduce(0) { $0 + $1.y } / Double(circles.count)
        let r = circles.reduce(0) { result, circle in
            let dx = circle.x - cx
            let dy = circle.y - cy
            return max(result, (dx * dx + dy * dy).squareRoot() + circle.r)
        }
        return SpaceMapCircle(x: cx, y: cy, r: r)
    }
}

/// Deterministic linear congruential generator (so layouts never jump between renders).
struct SpaceMapLCG {
    private var state: UInt64 = 1

    mutating func next() -> Double {
        state = (1_664_525 &* state &+ 1_013_904_223) & 0xFFFF_FFFF
        return Double(state) / 4_294_967_296
    }
}

// MARK: - Sunburst

/// One arc of the ring view.
public struct SpaceMapRingSegment: Identifiable, Sendable {
    public let id: Int
    /// The item drawn, or nil for a segment that folds a parent's tiny children.
    public let node: SpaceMapNode?
    /// The node whose children this ring shows.
    public let parent: SpaceMapNode
    /// 1 = innermost ring.
    public let depth: Int
    /// Radians, 0 at 12 o'clock, growing clockwise.
    public let startAngle: Double
    public let endAngle: Double
    public let innerRadius: Double
    public let outerRadius: Double
    public let bytes: Int64
    /// Number of children folded into a `node == nil` segment.
    public let foldedCount: Int
    /// The children folded into a `node == nil` segment (empty otherwise).
    public let folded: [SpaceMapNode]
    /// Position among its siblings (largest = 0).
    public let rank: Int

    public var span: Double { endAngle - startAngle }
    public var midAngle: Double { (startAngle + endAngle) / 2 }
}

/// Sunburst (partition) layout: the focused folder in the middle, each ring one level
/// deeper, every arc's angle proportional to its size.
public enum SpaceMapSunburst {

    public static func layout(focus: SpaceMapNode, maxDepth: Int = 4, holeRadius: Double, outerRadius: Double,
                              minAngle: Double = 0.012) -> [SpaceMapRingSegment] {
        guard maxDepth > 0, outerRadius > holeRadius else { return [] }
        let ring = (outerRadius - holeRadius) / Double(maxDepth)
        var segments: [SpaceMapRingSegment] = []

        func visit(_ node: SpaceMapNode, depth: Int, start: Double, span: Double) {
            guard depth <= maxDepth, span > 0 else { return }
            let childrenTotal = node.children.reduce(Int64(0)) { $0 + $1.size }
            let total = Double(max(node.size, childrenTotal))
            guard total > 0 else { return }
            let inner = holeRadius + Double(depth - 1) * ring
            let outer = inner + ring
            var angle = start
            var foldedBytes: Int64 = 0
            var folded: [SpaceMapNode] = []
            for (rank, child) in node.children.enumerated() where child.size > 0 {
                let childSpan = span * Double(child.size) / total
                if childSpan < minAngle {
                    foldedBytes += child.size
                    folded.append(child)
                    continue
                }
                segments.append(SpaceMapRingSegment(id: segments.count, node: child, parent: node, depth: depth,
                                                    startAngle: angle, endAngle: angle + childSpan,
                                                    innerRadius: inner, outerRadius: outer, bytes: child.size,
                                                    foldedCount: 0, folded: [], rank: rank))
                if child.isFolder {
                    visit(child, depth: depth + 1, start: angle, span: childSpan)
                }
                angle += childSpan
            }
            if !folded.isEmpty {
                let foldedSpan = span * Double(foldedBytes) / total
                if foldedSpan >= minAngle / 2 {
                    segments.append(SpaceMapRingSegment(id: segments.count, node: nil, parent: node, depth: depth,
                                                        startAngle: angle, endAngle: angle + foldedSpan,
                                                        innerRadius: inner, outerRadius: outer, bytes: foldedBytes,
                                                        foldedCount: folded.count, folded: folded,
                                                        rank: node.children.count))
                }
            }
        }

        visit(focus, depth: 1, start: 0, span: 2 * Double.pi)
        return segments
    }

    /// Clockwise angle from 12 o'clock for an offset from the centre (y grows downwards).
    public static func angle(dx: Double, dy: Double) -> Double {
        let raw = atan2(dx, -dy)
        return raw < 0 ? raw + 2 * Double.pi : raw
    }

    /// Index of the segment under an offset from the centre.
    public static func hitTest(_ segments: [SpaceMapRingSegment], dx: Double, dy: Double) -> Int? {
        let radius = (dx * dx + dy * dy).squareRoot()
        let theta = angle(dx: dx, dy: dy)
        return segments.firstIndex { segment in
            radius >= segment.innerRadius && radius < segment.outerRadius
                && theta >= segment.startAngle && theta < segment.endAngle
        }
    }

    /// Point on a circle for a sunburst angle.
    public static func point(angle: Double, radius: Double, cx: Double, cy: Double) -> (x: Double, y: Double) {
        (cx + radius * sin(angle), cy - radius * cos(angle))
    }
}
