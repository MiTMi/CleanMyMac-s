import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Sunburst view of the focused folder: the folder in the middle, four rings of
/// descendants, every arc's angle proportional to its size. Click an arc to zoom into
/// it, the middle to zoom out.
///
/// The layout is cached by the screen model and the pointer position lives in
/// `SpaceMapPointer`, read only by the hover card: moving the mouse redraws the rings
/// only when the arc under the pointer changes.
struct SpaceMapRingsCanvas: View {
    let screen: SpaceMapScreenModel
    let focus: SpaceMapNode

    @State private var pointer = SpaceMapPointer()
    @State private var hoveredSegment: Int?

    private static let maxDepth = 4

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = max(40, min(size.width, size.height) / 2 - 10)
            let hole = outer * 0.26
            let segments = screen.ringSegments(for: focus, holeRadius: Double(hole), outerRadius: Double(outer),
                                               maxDepth: Self.maxDepth)
            let state = SpaceMapDrawState(screen)
            let hovered = hoveredSegment
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawRings(segments, center: center, hole: hole, hovered: hovered, state: state, context: &context)
                }
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    handleHover(phase, segments: segments, center: center)
                }
                .gesture(SpatialTapGesture().onEnded { value in
                    handleTap(at: value.location, segments: segments, center: center, hole: hole)
                })
                .contextMenu {
                    if let node = hoveredNode(segments) {
                        SpaceMapNodeMenu(screen: screen, node: node)
                    } else if focus.parent != nil {
                        Button("Enclosing Folder") { screen.zoomOut() }
                    }
                }
                centerLabel(center: center, hole: hole)
                SpaceMapPointerCard(pointer: pointer, screen: screen, subject: hoverSubject(segments), total: focus.size,
                                    bounds: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ring map of \(focus.name), \(ByteFormat.string(focus.size))")
        .accessibilityHint("Use the list beside the map to browse and select items.")
    }

    // MARK: Overlays

    private func centerLabel(center: CGPoint, hole: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(focus.name)
                .font(SpruceFont.bodyStrong)
                .foregroundStyle(Ink.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(ByteFormat.string(focus.size))
                .font(SpruceFont.callout.monospacedDigit())
                .foregroundStyle(ModuleID.spaceMap.palette.accentText)
            if focus.parent != nil {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(width: hole * 1.6)
        .position(center)
        .allowsHitTesting(false)
    }

    /// What the hover card shows: the arc's item, or the children a folded arc stands for.
    private func hoverSubject(_ segments: [SpaceMapRingSegment]) -> SpaceMapHoverSubject? {
        guard let index = hoveredSegment, index < segments.count else { return nil }
        let segment = segments[index]
        if let node = segment.node { return .node(node) }
        return .smaller(SpaceMapSmallerGroup(nodes: segment.folded))
    }

    private func hoveredNode(_ segments: [SpaceMapRingSegment]) -> SpaceMapNode? {
        guard let index = hoveredSegment, index < segments.count else { return nil }
        return segments[index].node
    }

    // MARK: Interaction

    private func handleHover(_ phase: HoverPhase, segments: [SpaceMapRingSegment], center: CGPoint) {
        switch phase {
        case .active(let location):
            pointer.location = location
            let index = SpaceMapSunburst.hitTest(segments, dx: Double(location.x - center.x), dy: Double(location.y - center.y))
            if hoveredSegment != index { hoveredSegment = index }
            let node = index.flatMap { segments[$0].node }
            if screen.hovered !== node { screen.hovered = node }
        case .ended:
            pointer.location = nil
            hoveredSegment = nil
            if screen.hovered != nil { screen.hovered = nil }
        }
    }

    private func handleTap(at location: CGPoint, segments: [SpaceMapRingSegment], center: CGPoint, hole: CGFloat) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        if (dx * dx + dy * dy).squareRoot() < hole {
            screen.zoomOut()
            return
        }
        guard let index = SpaceMapSunburst.hitTest(segments, dx: Double(dx), dy: Double(dy)) else { return }
        let segment = segments[index]
        hoveredSegment = nil
        guard let node = segment.node else {
            // A folded arc: open its folder and list the small items.
            if segment.parent !== focus { screen.zoom(into: segment.parent) }
            screen.showsSmallerItems = true
            return
        }
        if node.canZoom {
            screen.zoom(into: node)
        } else if node.isReal && node.parent != nil && (screen.isSelectable(node) || screen.isSelected(node)) {
            screen.toggle(node)
            screen.highlighted = node
        } else {
            screen.highlighted = node
        }
    }

    // MARK: Drawing

    private func drawRings(_ segments: [SpaceMapRingSegment], center: CGPoint, hole: CGFloat, hovered hoveredIndex: Int?,
                           state: SpaceMapDrawState, context: inout GraphicsContext) {
        let holePath = Path(ellipseIn: CGRect(x: center.x - hole + 3, y: center.y - hole + 3,
                                              width: (hole - 3) * 2, height: (hole - 3) * 2))
        context.fill(holePath, with: .color(Color.white.opacity(0.06)))
        context.stroke(holePath, with: .color(Color.white.opacity(0.14)), lineWidth: 1)

        // Colour of each depth-1 branch, inherited (lighter) by its descendants.
        var branchRank: [ObjectIdentifier: Int] = [:]
        for segment in segments {
            guard let node = segment.node else { continue }
            if segment.depth == 1 {
                branchRank[node.id] = segment.rank
            } else if let parentRank = branchRank[segment.parent.id] {
                branchRank[node.id] = parentRank
            }
        }

        for (index, segment) in segments.enumerated() {
            let path = arcPath(segment, center: center)
            let hovered = hoveredIndex == index
            if let node = segment.node {
                let rank = branchRank[node.id] ?? segment.rank
                let base = node.kind == .system ? SpaceMapStyle.system
                    : SpaceMapStyle.color(for: node, rank: rank, depth: segment.depth)
                context.fill(path, with: .color(base.opacity(hovered ? 1 : 0.82)))
                if screen.isSelected(node) || screen.isCovered(node) {
                    context.fill(path, with: .color(SpaceMapStyle.selection.opacity(0.55)))
                }
                if state.highlighted === node || state.hovered === node {
                    context.stroke(path, with: .color(Color.white.opacity(0.9)), lineWidth: 2)
                } else {
                    context.stroke(path, with: .color(Color.black.opacity(0.35)), lineWidth: 0.8)
                }
                if segment.depth == 1 {
                    drawArcLabel(segment, node: node, center: center, context: &context)
                }
            } else {
                context.fill(path, with: .color(SpaceMapStyle.smaller.opacity(hovered ? 1.4 : 1)))
                context.stroke(path, with: .color(Color.white.opacity(0.25)),
                               style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }
        }
    }

    private func arcPath(_ segment: SpaceMapRingSegment, center: CGPoint) -> Path {
        let gap = 0.6
        let inner = segment.innerRadius + gap
        let outer = segment.outerRadius - gap
        let steps = max(2, Int(segment.span / 0.03))
        var path = Path()
        for step in 0...steps {
            let angle = segment.startAngle + segment.span * Double(step) / Double(steps)
            let point = SpaceMapSunburst.point(angle: angle, radius: outer, cx: Double(center.x), cy: Double(center.y))
            if step == 0 {
                path.move(to: CGPoint(x: point.x, y: point.y))
            } else {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let angle = segment.startAngle + segment.span * Double(step) / Double(steps)
            let point = SpaceMapSunburst.point(angle: angle, radius: inner, cx: Double(center.x), cy: Double(center.y))
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        path.closeSubpath()
        return path
    }

    /// Names on first-ring arcs that are long enough to hold them.
    private func drawArcLabel(_ segment: SpaceMapRingSegment, node: SpaceMapNode, center: CGPoint,
                              context: inout GraphicsContext) {
        let radius = (segment.innerRadius + segment.outerRadius) / 2
        let arcLength = segment.span * radius
        guard arcLength > 54, segment.outerRadius - segment.innerRadius > 16 else { return }
        let point = SpaceMapSunburst.point(angle: segment.midAngle, radius: radius, cx: Double(center.x), cy: Double(center.y))
        let maxChars = max(3, Int(min(arcLength, (segment.outerRadius - segment.innerRadius) * 2.2) / 6.5))
        let name = node.name.count > maxChars ? String(node.name.prefix(maxChars - 1)) + "…" : node.name
        context.draw(Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.white),
                     at: CGPoint(x: point.x, y: point.y), anchor: .center)
    }
}
