import Foundation

// MARK: - "N smaller items"

/// The tail of a folder's children that is too small (or too numerous) to draw
/// individually; shown as one "N smaller items" bubble and one expandable list row.
public struct SpaceMapSmallerGroup: Sendable {
    public let nodes: [SpaceMapNode]
    public let bytes: Int64

    public init(nodes: [SpaceMapNode]) {
        self.nodes = nodes
        self.bytes = nodes.reduce(0) { $0 + $1.size }
    }

    public var count: Int { nodes.count }
    public var title: String { "\(CountFormat.grouped(count)) smaller items" }
}

/// Children split into the ones drawn individually and the folded tail.
public struct SpaceMapGrouped: Sendable {
    public let visible: [SpaceMapNode]
    public let smaller: SpaceMapSmallerGroup?

    public init(visible: [SpaceMapNode], smaller: SpaceMapSmallerGroup?) {
        self.visible = visible
        self.smaller = smaller
    }
}

public enum SpaceMapGrouping {
    /// Keeps the first `limit` children whose share of the total is at least `minShare`
    /// (the largest child is always kept); the rest become the smaller-items group. A
    /// single leftover is shown on its own instead of as a group of one. `children` must
    /// be sorted largest first (as `SpaceMapNode.children` always is).
    public static func group(_ children: [SpaceMapNode], limit: Int = 24, minShare: Double = 0.003) -> SpaceMapGrouped {
        guard !children.isEmpty else { return SpaceMapGrouped(visible: [], smaller: nil) }
        let total = children.reduce(Int64(0)) { $0 + $1.size }
        var cut = 0
        while cut < children.count && cut < max(1, limit) {
            let child = children[cut]
            if cut > 0 {
                if total > 0 && Double(child.size) / Double(total) < minShare { break }
                if total > 0 && child.size == 0 { break }
            }
            cut += 1
        }
        if children.count - cut == 1 { cut += 1 }
        let visible = Array(children[..<cut])
        let rest = Array(children[cut...])
        return SpaceMapGrouped(visible: visible, smaller: rest.isEmpty ? nil : SpaceMapSmallerGroup(nodes: rest))
    }
}

// MARK: - Bubble map

/// One bubble of the map for the focused folder.
public struct SpaceMapBubble: Identifiable, Sendable {
    public enum Content: Sendable {
        case node(SpaceMapNode)
        case smaller(SpaceMapSmallerGroup)
    }

    public let id: Int
    public let content: Content
    public let circle: SpaceMapCircle
    /// Position in size order (0 = largest).
    public let rank: Int
    /// Preview of the bubble's own largest children, packed inside it.
    public let inner: [SpaceMapInnerBubble]

    public var node: SpaceMapNode? {
        if case .node(let node) = content { return node }
        return nil
    }

    public var bytes: Int64 {
        switch content {
        case .node(let node): return node.size
        case .smaller(let group): return group.bytes
        }
    }
}

public struct SpaceMapInnerBubble: Sendable {
    public let node: SpaceMapNode
    public let circle: SpaceMapCircle
}

/// A laid-out bubble map.
public struct SpaceMapBubbleMap: Sendable {
    public let focus: SpaceMapNode
    public let bubbles: [SpaceMapBubble]
    public let width: Double
    public let height: Double

    /// Bubble under a point.
    public func bubble(atX x: Double, y: Double) -> SpaceMapBubble? {
        guard let index = SpaceMapPack.hitTest(bubbles.map(\.circle), x: x, y: y) else { return nil }
        return bubbles[index]
    }

    /// The bubble showing `node` (or the smaller-items bubble that contains it).
    public func bubble(for node: SpaceMapNode) -> SpaceMapBubble? {
        for bubble in bubbles {
            switch bubble.content {
            case .node(let shown) where shown === node: return bubble
            case .smaller(let group) where group.nodes.contains(where: { $0 === node }): return bubble
            default: continue
            }
        }
        return nil
    }
}

public enum SpaceMapBubbleMapBuilder {
    /// Packs the focused folder's top children (plus one smaller-items bubble) into the
    /// canvas, largest in the middle, area proportional to bytes. Folders drawn with a
    /// radius of at least `innerThreshold` get a packed preview of their own children.
    public static func build(focus: SpaceMapNode, width: Double, height: Double, limit: Int = 24,
                             minShare: Double = 0.003, innerThreshold: Double = 56,
                             innerLimit: Int = 12) -> SpaceMapBubbleMap {
        let grouped = SpaceMapGrouping.group(focus.children, limit: limit, minShare: minShare)
        var contents: [SpaceMapBubble.Content] = grouped.visible.map { .node($0) }
        if let smaller = grouped.smaller { contents.append(.smaller(smaller)) }
        let values = contents.map { content -> Double in
            switch content {
            case .node(let node): return Double(node.size)
            case .smaller(let group): return Double(group.bytes)
            }
        }
        let circles = SpaceMapPack.layout(values: values, width: width, height: height)
        var bubbles: [SpaceMapBubble] = []
        bubbles.reserveCapacity(circles.count)
        for (index, circle) in circles.enumerated() {
            let content = contents[index]
            var inner: [SpaceMapInnerBubble] = []
            if case .node(let node) = content, node.isFolder, circle.r >= innerThreshold, !node.children.isEmpty {
                inner = innerBubbles(of: node, in: circle, limit: innerLimit)
            }
            bubbles.append(SpaceMapBubble(id: index, content: content, circle: circle, rank: index, inner: inner))
        }
        return SpaceMapBubbleMap(focus: focus, bubbles: bubbles, width: width, height: height)
    }

    static func innerBubbles(of node: SpaceMapNode, in circle: SpaceMapCircle, limit: Int) -> [SpaceMapInnerBubble] {
        let shown = SpaceMapGrouping.group(node.children, limit: limit, minShare: 0.02).visible.filter { $0.size > 0 }
        guard !shown.isEmpty else { return [] }
        let radii = shown.map { Double($0.size).squareRoot() }
        let largest = radii.max() ?? 1
        let packed = SpaceMapPack.siblings(radii: radii.map { $0 / largest + 0.04 })
        guard packed.enclosing.r > 0 else { return [] }
        let scale = circle.r * 0.8 / packed.enclosing.r
        return zip(shown, zip(packed.circles, radii)).map { child, pair in
            SpaceMapInnerBubble(node: child, circle: SpaceMapCircle(x: circle.x + pair.0.x * scale,
                                                                    y: circle.y + pair.0.y * scale,
                                                                    r: pair.1 / largest * scale))
        }
    }
}

// MARK: - Breadcrumbs

public enum SpaceMapCrumb: Sendable {
    case node(SpaceMapNode)
    /// Middle levels folded into "…" (deepest last).
    case collapsed([SpaceMapNode])
}

public enum SpaceMapBreadcrumbs {
    /// Root → `node`, folding middle levels when there are more than `maxVisible` items
    /// (the root and the deepest levels stay visible).
    public static func trail(to node: SpaceMapNode, maxVisible: Int = 5) -> [SpaceMapCrumb] {
        let chain = node.ancestry
        guard maxVisible >= 3, chain.count > maxVisible else { return chain.map { .node($0) } }
        let tailCount = maxVisible - 2
        let middle = Array(chain[1..<(chain.count - tailCount)])
        return [.node(chain[0]), .collapsed(middle)] + chain.suffix(tailCount).map { .node($0) }
    }
}

// MARK: - Selection

public enum SpaceMapSelection {
    /// Selected real items without the ones already covered by a selected ancestor
    /// (each node once, in the given order).
    public static func topmost(_ nodes: [SpaceMapNode]) -> [SpaceMapNode] {
        let selected = Set(nodes.map(\.id))
        var seen = Set<ObjectIdentifier>()
        var result: [SpaceMapNode] = []
        for node in nodes where node.isReal && !seen.contains(node.id) {
            seen.insert(node.id)
            var covered = false
            var ancestor = node.parent
            while let current = ancestor {
                if selected.contains(current.id) {
                    covered = true
                    break
                }
                ancestor = current.parent
            }
            if !covered { result.append(node) }
        }
        return result
    }

    public static func totalBytes(_ nodes: [SpaceMapNode]) -> Int64 {
        topmost(nodes).reduce(0) { $0 + $1.size }
    }

    public static func totalFiles(_ nodes: [SpaceMapNode]) -> Int {
        topmost(nodes).reduce(0) { $0 + max(1, $1.fileCount) }
    }

    /// Ids of every strict ancestor of a selected node (for tri-state checkboxes).
    public static func ancestorIDs(of nodes: [SpaceMapNode]) -> Set<ObjectIdentifier> {
        var ids = Set<ObjectIdentifier>()
        for node in nodes {
            var ancestor = node.parent
            while let current = ancestor, ids.insert(current.id).inserted {
                ancestor = current.parent
            }
        }
        return ids
    }
}

// MARK: - Navigation history

/// Back/forward stacks of focused folders. Entries that left the tree (removed or
/// replaced by a rescan) are skipped.
public struct SpaceMapHistory {
    public private(set) var backStack: [SpaceMapNode] = []
    public private(set) var forwardStack: [SpaceMapNode] = []

    public init() {}

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// Call before moving the focus away from `current` by a direct navigation.
    public mutating func leave(_ current: SpaceMapNode) {
        if backStack.last !== current { backStack.append(current) }
        forwardStack.removeAll()
        if backStack.count > 200 { backStack.removeFirst(backStack.count - 200) }
    }

    public mutating func goBack(from current: SpaceMapNode, root: SpaceMapNode) -> SpaceMapNode? {
        while let candidate = backStack.popLast() {
            if candidate !== current && candidate.isAttached(to: root) {
                forwardStack.append(current)
                return candidate
            }
        }
        return nil
    }

    public mutating func goForward(from current: SpaceMapNode, root: SpaceMapNode) -> SpaceMapNode? {
        while let candidate = forwardStack.popLast() {
            if candidate !== current && candidate.isAttached(to: root) {
                backStack.append(current)
                return candidate
            }
        }
        return nil
    }

    public mutating func reset() {
        backStack.removeAll()
        forwardStack.removeAll()
    }
}
