import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Animated change of focus on the bubble map.
struct SpaceMapZoomTransition: Identifiable {
    enum Kind {
        /// Between a folder (`parent` map) and a descendant whose branch is drawn as `pivot`
        /// in the parent map. `inward` = zooming in.
        case zoom(parent: SpaceMapBubbleMap, child: SpaceMapBubbleMap, pivot: SpaceMapCircle, inward: Bool)
        /// Unrelated folders (history jumps across branches): cross-fade.
        case fade(from: SpaceMapBubbleMap, to: SpaceMapBubbleMap)
    }

    let id = UUID()
    let kind: Kind
    let start: Date
    let duration: Double

    /// Eased 0...1, or nil once finished.
    func progress(at date: Date) -> Double? {
        let raw = date.timeIntervalSince(start) / duration
        guard raw < 1 else { return nil }
        let t = max(0, raw)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

/// Maps layout coordinates to view coordinates: `anchor` lands on `target`, scaled.
struct SpaceMapViewTransform {
    var anchor: CGPoint = .zero
    var target: CGPoint = .zero
    var scale: CGFloat = 1

    static let identity = SpaceMapViewTransform()

    func apply(_ circle: SpaceMapCircle) -> (center: CGPoint, radius: CGFloat) {
        (CGPoint(x: target.x + scale * (CGFloat(circle.x) - anchor.x),
                 y: target.y + scale * (CGFloat(circle.y) - anchor.y)),
         CGFloat(circle.r) * scale)
    }
}

/// The interactive bubble map of the focused folder, drawn in a `Canvas`: largest bubble
/// in the middle, area ∝ bytes, colours by type and rank, labels on big bubbles, a packed
/// preview of each big folder's contents, hover card, click a folder to zoom in (the
/// bubble grows to fill the view), click empty space to zoom out.
struct SpaceMapBubbleCanvas: View {
    let screen: SpaceMapScreenModel
    let focus: SpaceMapNode

    @State private var transition: SpaceMapZoomTransition?
    @State private var hoverPoint: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let badgeRadius: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let map = screen.bubbleMap(for: focus, width: Double(size.width), height: Double(size.height))
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: nil, paused: transition == nil)) { timeline in
                    Canvas { context, _ in
                        render(map, size: size, now: timeline.date, context: &context)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    handleHover(phase, map: map)
                }
                .gesture(SpatialTapGesture().onEnded { value in
                    handleTap(at: value.location, map: map)
                })
                .contextMenu {
                    if let node = screen.hovered {
                        SpaceMapNodeMenu(screen: screen, node: node)
                    } else if focus.parent != nil {
                        Button("Enclosing Folder") { screen.zoomOut() }
                    }
                }
                hoverCard(map: map, size: size)
            }
            .onChange(of: focus) { oldFocus, newFocus in
                startTransition(from: oldFocus, to: newFocus, size: size)
            }
        }
        .task(id: transition?.id) {
            guard let current = transition else { return }
            try? await Task.sleep(nanoseconds: UInt64((current.duration + 0.05) * 1_000_000_000))
            if transition?.id == current.id { transition = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bubble map of \(focus.name), \(ByteFormat.string(focus.size))")
        .accessibilityHint("Use the list beside the map to browse and select items.")
    }

    // MARK: Hover card

    @ViewBuilder
    private func hoverCard(map: SpaceMapBubbleMap, size: CGSize) -> some View {
        if transition == nil, let point = hoverPoint, let subject = hoverSubject(map: map) {
            let origin = SpaceMapHoverCard.origin(near: point, in: size)
            SpaceMapHoverCard(screen: screen, subject: subject, total: focus.size)
                .offset(x: origin.x, y: origin.y)
                .transition(.opacity)
        }
    }

    private func hoverSubject(map: SpaceMapBubbleMap) -> SpaceMapHoverSubject? {
        if screen.hoveringSmaller, let bubble = map.bubbles.last, case .smaller(let group) = bubble.content {
            return .smaller(group)
        }
        if let node = screen.hovered, map.bubbles.contains(where: { $0.node === node }) {
            return .node(node)
        }
        return nil
    }

    // MARK: Interaction

    private func handleHover(_ phase: HoverPhase, map: SpaceMapBubbleMap) {
        switch phase {
        case .active(let location):
            hoverPoint = location
            guard transition == nil else { return }
            let bubble = map.bubble(atX: Double(location.x), y: Double(location.y))
            switch bubble?.content {
            case .node(let node):
                if screen.hovered !== node { screen.hovered = node }
                if screen.hoveringSmaller { screen.hoveringSmaller = false }
            case .smaller:
                if screen.hovered != nil { screen.hovered = nil }
                if !screen.hoveringSmaller { screen.hoveringSmaller = true }
            case nil:
                if screen.hovered != nil { screen.hovered = nil }
                if screen.hoveringSmaller { screen.hoveringSmaller = false }
            }
        case .ended:
            hoverPoint = nil
            if screen.hovered != nil { screen.hovered = nil }
            if screen.hoveringSmaller { screen.hoveringSmaller = false }
        }
    }

    private func handleTap(at location: CGPoint, map: SpaceMapBubbleMap) {
        guard transition == nil else { return }
        guard let bubble = map.bubble(atX: Double(location.x), y: Double(location.y)) else {
            screen.zoomOut()
            return
        }
        switch bubble.content {
        case .smaller:
            screen.showsSmallerItems = true
            screen.highlighted = nil
        case .node(let node):
            let (center, radius) = SpaceMapViewTransform.identity.apply(bubble.circle)
            if showsBadge(for: node, radius: radius, interactive: true),
               distance(location, badgeCenter(center: center, radius: radius)) <= Self.badgeRadius + 4 {
                screen.toggle(node)
            } else if node.canZoom {
                screen.zoom(into: node)
            } else if node.isReal && node.parent != nil && (screen.isSelectable(node) || screen.isSelected(node)) {
                screen.toggle(node)
                screen.highlighted = node
            } else {
                screen.highlighted = node
            }
        }
    }

    private func startTransition(from oldFocus: SpaceMapNode, to newFocus: SpaceMapNode, size: CGSize) {
        guard !reduceMotion, size.width > 20, size.height > 20, oldFocus !== newFocus else {
            transition = nil
            return
        }
        let width = Double(size.width)
        let height = Double(size.height)
        let duration = 0.5
        if newFocus.isDescendant(of: oldFocus), let branch = oldFocus.childOnPath(to: newFocus) {
            let parentMap = screen.bubbleMap(for: oldFocus, width: width, height: height)
            let childMap = screen.bubbleMap(for: newFocus, width: width, height: height)
            if let pivot = parentMap.bubbles.first(where: { $0.node === branch })?.circle {
                transition = SpaceMapZoomTransition(kind: .zoom(parent: parentMap, child: childMap, pivot: pivot, inward: true),
                                                    start: Date(), duration: duration)
                return
            }
            transition = SpaceMapZoomTransition(kind: .fade(from: parentMap, to: childMap), start: Date(), duration: 0.3)
        } else if oldFocus.isDescendant(of: newFocus), let branch = newFocus.childOnPath(to: oldFocus) {
            let parentMap = screen.bubbleMap(for: newFocus, width: width, height: height)
            let childMap = screen.bubbleMap(for: oldFocus, width: width, height: height)
            if let pivot = parentMap.bubbles.first(where: { $0.node === branch })?.circle {
                transition = SpaceMapZoomTransition(kind: .zoom(parent: parentMap, child: childMap, pivot: pivot, inward: false),
                                                    start: Date(), duration: duration)
                return
            }
            transition = SpaceMapZoomTransition(kind: .fade(from: childMap, to: parentMap), start: Date(), duration: 0.3)
        } else {
            let from = screen.bubbleMap(for: oldFocus, width: width, height: height)
            let to = screen.bubbleMap(for: newFocus, width: width, height: height)
            transition = SpaceMapZoomTransition(kind: .fade(from: from, to: to), start: Date(), duration: 0.3)
        }
    }

    // MARK: Rendering

    private func render(_ map: SpaceMapBubbleMap, size: CGSize, now: Date, context: inout GraphicsContext) {
        guard let transition, let progress = transition.progress(at: now) else {
            draw(map, transform: .identity, alpha: 1, labelAlpha: 1, interactive: true, context: &context)
            return
        }
        switch transition.kind {
        case let .zoom(parent, child, pivot, inward):
            let t = CGFloat(inward ? progress : 1 - progress)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let fittedRadius = max(1, min(size.width, size.height) / 2 - 8)
            let p = CGPoint(x: pivot.x, y: pivot.y)
            let k = fittedRadius / max(CGFloat(pivot.r), 0.5)
            let scale = 1 + (k - 1) * t
            let moving = CGPoint(x: p.x + (center.x - p.x) * t, y: p.y + (center.y - p.y) * t)
            let parentTransform = SpaceMapViewTransform(anchor: p, target: moving, scale: scale)
            let childTransform = SpaceMapViewTransform(anchor: center, target: moving, scale: scale * CGFloat(pivot.r) / fittedRadius)
            draw(parent, transform: parentTransform, alpha: Double(1 - t), labelAlpha: Double(max(0, 1 - 3 * t)),
                 interactive: false, context: &context)
            draw(child, transform: childTransform, alpha: Double(min(1, t * 1.4)), labelAlpha: Double(max(0, 3 * t - 2)),
                 interactive: false, context: &context)
        case let .fade(from, to):
            draw(from, transform: .identity, alpha: 1 - progress, labelAlpha: 1 - progress, interactive: false, context: &context)
            draw(to, transform: .identity, alpha: progress, labelAlpha: progress, interactive: false, context: &context)
        }
    }

    private func draw(_ map: SpaceMapBubbleMap, transform: SpaceMapViewTransform, alpha: Double, labelAlpha: Double,
                      interactive: Bool, context: inout GraphicsContext) {
        guard alpha > 0.01 else { return }
        for bubble in map.bubbles {
            let (center, radius) = transform.apply(bubble.circle)
            guard radius > 0.5 else { continue }
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            guard rect.intersects(CGRect(x: -4000, y: -4000, width: 12000, height: 12000)) else { continue }
            switch bubble.content {
            case .node(let node):
                drawNode(node, bubble: bubble, center: center, radius: radius, transform: transform, alpha: alpha,
                         labelAlpha: labelAlpha, interactive: interactive, context: &context)
            case .smaller(let group):
                drawSmaller(group, center: center, radius: radius, alpha: alpha, labelAlpha: labelAlpha,
                            interactive: interactive, context: &context)
            }
        }
    }

    private func drawNode(_ node: SpaceMapNode, bubble: SpaceMapBubble, center: CGPoint, radius: CGFloat,
                          transform: SpaceMapViewTransform, alpha: Double, labelAlpha: Double, interactive: Bool,
                          context: inout GraphicsContext) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = Path(ellipseIn: rect)
        let base = SpaceMapStyle.color(for: node, rank: bubble.rank)
        let hovered = interactive && screen.hovered === node
        let selected = interactive && (screen.isSelected(node) || screen.isCovered(node))
        let highlighted = interactive && screen.highlighted === node

        if node.kind == .system {
            context.fill(path, with: .color(SpaceMapStyle.system.opacity(0.6 * alpha)))
            drawHatch(in: rect, clip: path, alpha: alpha, context: &context)
        } else {
            let gradient = Gradient(colors: [
                base.prismMix(.white, 0.28).opacity(0.95 * alpha),
                base.opacity(0.80 * alpha),
                base.prismMix(.black, 0.30).opacity(0.72 * alpha),
            ])
            context.fill(path, with: .radialGradient(gradient,
                                                     center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4),
                                                     startRadius: 0, endRadius: radius * 1.6))
        }

        for inner in bubble.inner {
            let (innerCenter, innerRadius) = transform.apply(inner.circle)
            guard innerRadius > 1.5 else { continue }
            let innerPath = Path(ellipseIn: CGRect(x: innerCenter.x - innerRadius, y: innerCenter.y - innerRadius,
                                                   width: innerRadius * 2, height: innerRadius * 2))
            context.fill(innerPath, with: .color(Color.white.opacity(0.12 * alpha)))
            context.stroke(innerPath, with: .color(Color.white.opacity(0.18 * alpha)), lineWidth: 0.75)
        }

        if hovered {
            context.fill(path, with: .color(Color.white.opacity(0.10 * alpha)))
        }
        if selected {
            context.fill(path, with: .color(SpaceMapStyle.selection.opacity(0.22 * alpha)))
            var glow = context
            glow.addFilter(.shadow(color: SpaceMapStyle.selection.opacity(0.85 * alpha), radius: 8))
            glow.stroke(path, with: .color(SpaceMapStyle.selection.opacity(alpha)), lineWidth: 3)
        }
        if node.kind == .smallFiles {
            context.stroke(path, with: .color(Color.white.opacity(0.45 * alpha)),
                           style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
        } else if node.isUnreadable {
            context.stroke(path, with: .color(SpaceMapStyle.unreadable.opacity(0.9 * alpha)), lineWidth: 1.5)
        } else {
            context.stroke(path, with: .color(Color.white.opacity((hovered ? 0.85 : 0.22) * alpha)),
                           lineWidth: hovered ? 2 : 1)
        }
        if highlighted {
            let ring = Path(ellipseIn: rect.insetBy(dx: -4, dy: -4))
            context.stroke(ring, with: .color(Color.white.opacity(0.8 * alpha)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }

        let type = SpaceMapFileType.of(node)
        let symbol = node.isUnreadable ? "lock.fill" : type.symbol
        drawLabels(title: node.name, detail: ByteFormat.string(node.size), symbol: symbol, center: center,
                   radius: radius, hasInner: !bubble.inner.isEmpty, alpha: labelAlpha, context: &context)

        if showsBadge(for: node, radius: radius, interactive: interactive) {
            drawBadge(at: badgeCenter(center: center, radius: radius), checked: screen.isSelected(node),
                      alpha: alpha, context: &context)
        }
    }

    private func drawSmaller(_ group: SpaceMapSmallerGroup, center: CGPoint, radius: CGFloat, alpha: Double,
                             labelAlpha: Double, interactive: Bool, context: inout GraphicsContext) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = Path(ellipseIn: rect)
        let hovered = interactive && screen.hoveringSmaller
        context.fill(path, with: .color(Color.white.opacity((hovered ? 0.16 : 0.08) * alpha)))
        context.stroke(path, with: .color(Color.white.opacity((hovered ? 0.7 : 0.4) * alpha)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
        if interactive && screen.showsSmallerItems {
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                           with: .color(ModuleID.spaceMap.palette.accentText.opacity(alpha)), lineWidth: 2)
        }
        drawLabels(title: group.title, detail: ByteFormat.string(group.bytes), symbol: "ellipsis", center: center,
                   radius: radius, hasInner: false, alpha: labelAlpha, context: &context)
    }

    private func drawHatch(in rect: CGRect, clip: Path, alpha: Double, context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.clip(to: clip)
            var lines = Path()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                lines.move(to: CGPoint(x: x, y: rect.maxY))
                lines.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += 7
            }
            layer.stroke(lines, with: .color(Color.white.opacity(0.14 * alpha)), lineWidth: 1.5)
        }
    }

    private func drawLabels(title: String, detail: String, symbol: String, center: CGPoint, radius: CGFloat,
                            hasInner: Bool, alpha: Double, context: inout GraphicsContext) {
        guard alpha > 0.02 else { return }
        if radius >= 30 {
            let titleSize = min(15, max(10, radius / 5.5))
            let detailSize = max(9, titleSize - 1.5)
            let maxWidth = radius * (hasInner ? 1.3 : 1.55)
            let titleString = fitted(title, size: titleSize, maxWidth: maxWidth, context: context)
            let showSymbol = radius >= 60 && !hasInner
            let symbolSize = min(26, radius / 4.2)
            let blockHeight = titleSize * 1.3 + detailSize * 1.3 + (showSymbol ? symbolSize + 6 : 0)
            var y = hasInner ? center.y + radius * 0.52 - blockHeight / 2 : center.y - blockHeight / 2
            if hasInner {
                let width = min(maxWidth + 16, radius * 1.5)
                let plate = CGRect(x: center.x - width / 2, y: y - 4, width: width, height: blockHeight + 8)
                context.fill(Path(roundedRect: plate, cornerRadius: min(10, plate.height / 2)),
                             with: .color(Color.black.opacity(0.38 * alpha)))
            }
            if showSymbol {
                context.draw(Text(Image(systemName: symbol)).font(.system(size: symbolSize, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.9 * alpha)),
                             at: CGPoint(x: center.x, y: y + symbolSize / 2), anchor: .center)
                y += symbolSize + 6
            }
            context.draw(Text(titleString).font(.system(size: titleSize, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(alpha)),
                         at: CGPoint(x: center.x, y: y + titleSize * 0.65), anchor: .center)
            y += titleSize * 1.3
            context.draw(Text(detail).font(.system(size: detailSize, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.78 * alpha)),
                         at: CGPoint(x: center.x, y: y + detailSize * 0.65), anchor: .center)
        } else if radius >= 13 {
            context.draw(Text(Image(systemName: symbol)).font(.system(size: radius * 0.8, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75 * alpha)),
                         at: center, anchor: .center)
        }
    }

    /// Truncates with "…" so the label fits `maxWidth`.
    private func fitted(_ string: String, size: CGFloat, maxWidth: CGFloat, context: GraphicsContext) -> String {
        let font = Font.system(size: size, weight: .semibold)
        let estimate = max(3, Int(maxWidth / (size * 0.56)))
        var candidate = string.count > estimate ? String(string.prefix(estimate - 1)) + "…" : string
        for _ in 0..<6 {
            let width = context.resolve(Text(candidate).font(font))
                .measure(in: CGSize(width: 10_000, height: 200)).width
            if width <= maxWidth || candidate.count <= 2 { break }
            let ratio = Double(maxWidth / max(width, 1))
            let keep = max(1, Int(Double(candidate.count - 1) * ratio) - 1)
            candidate = String(string.prefix(keep)) + "…"
        }
        return candidate
    }

    private func showsBadge(for node: SpaceMapNode, radius: CGFloat, interactive: Bool) -> Bool {
        guard interactive, node.isReal, node.parent != nil, radius >= 22 else { return false }
        if screen.isSelected(node) { return true }
        return screen.hovered === node && screen.isSelectable(node) && !screen.isCovered(node)
    }

    private func badgeCenter(center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * 0.52, y: center.y - radius * 0.52)
    }

    private func drawBadge(at point: CGPoint, checked: Bool, alpha: Double, context: inout GraphicsContext) {
        let r = Self.badgeRadius
        let disc = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        if checked {
            context.fill(disc, with: .color(SpaceMapStyle.selection.opacity(alpha)))
            var check = Path()
            check.move(to: CGPoint(x: point.x - 4, y: point.y + 0.5))
            check.addLine(to: CGPoint(x: point.x - 1.2, y: point.y + 3.4))
            check.addLine(to: CGPoint(x: point.x + 4.2, y: point.y - 3))
            context.stroke(check, with: .color(Color.white.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        } else {
            context.fill(disc, with: .color(Color.black.opacity(0.45 * alpha)))
            context.stroke(disc, with: .color(Color.white.opacity(0.85 * alpha)), lineWidth: 1.5)
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
