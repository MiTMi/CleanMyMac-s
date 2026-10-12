import SpruceCore
import SwiftUI

// Internals of `HeroLens` (B.10.2): the procedural "glass lens" and one distinctive,
// original motif per module, drawn with Canvas. Motifs come in three layers so they
// can sit behind the lens, inside its frosted core, or in front of it.

/// Emotional state of a hero lens (B.8.3 / B.8.10).
enum PrismLensMood: Equatable {
    /// Normal intro/scanning look.
    case standard
    /// Calm glow with a ✓ badge (nothing found, all good).
    case clean
    /// Desaturated with a lock badge (missing permission).
    case limited
    /// Warning badge (error, threats).
    case warning

    /// Glow multiplier `k` for the bloom.
    var glow: Double {
        switch self {
        case .standard: return 1
        case .clean: return 0.6
        case .limited: return 0.5
        case .warning: return 0.85
        }
    }

    var defaultBadge: String? {
        switch self {
        case .standard: return nil
        case .clean: return "checkmark"
        case .limited: return "lock.fill"
        case .warning: return "exclamationmark"
        }
    }

    func badgeColor(_ palette: ModulePalette) -> Color {
        switch self {
        case .standard: return palette.accent
        case .clean: return StatusColor.success
        case .limited: return StatusColor.warning
        case .warning: return StatusColor.danger
        }
    }
}

// MARK: - Static lens layers

/// Soft bloom behind the lens (radial gradient, no blur, cheap to animate).
struct PrismLensBloom: View {
    var color: Color
    var size: CGFloat
    var opacity: Double
    var breathing: Bool

    var body: some View {
        let bloom = Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.45), .clear],
                                 center: .center, startRadius: 0, endRadius: size * 0.8))
            .frame(width: size * 1.6, height: size * 1.6)
            .allowsHitTesting(false)
        if breathing {
            bloom.phaseAnimator([false, true]) { view, phase in
                view.opacity(phase ? 1 : 0.82)
            } animation: { _ in
                .easeInOut(duration: 4)
            }
        } else {
            bloom
        }
    }
}

/// Gentle scale breathing while a lens is "working".
struct PrismBreathing: ViewModifier {
    var isActive: Bool
    var amount: CGFloat = 0.025

    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([false, true]) { view, phase in
                view.scaleEffect(phase ? 1 + amount : 1)
            } animation: { _ in
                .easeInOut(duration: 1.6)
            }
        } else {
            content
        }
    }
}

/// Lens core: body gradient, frosted core, specular highlight and rim (layers 2, 3, 5, 6).
struct PrismLensBody: View {
    var palette: ModulePalette
    var size: CGFloat
    var reduceTransparency: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.lensBody(diameter: size))
                .frame(width: size, height: size)
            Group {
                if reduceTransparency {
                    Circle().fill(palette.solidSurface)
                } else {
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.08)))
                }
            }
            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .frame(width: size * 0.70, height: size * 0.70)
        }
    }
}

struct PrismLensSpecular: View {
    var palette: ModulePalette
    var size: CGFloat
    var reduceTransparency: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.45), Color.white.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.55, height: size * 0.13)
                .blur(radius: reduceTransparency ? 0 : 2)
                .rotationEffect(.degrees(-20))
                .offset(x: -size * 0.13, y: -size * 0.33)
            Circle()
                .strokeBorder(
                    AngularGradient(colors: [Color.white.opacity(0.55), .clear, palette.accent.opacity(0.6), .clear, Color.white.opacity(0.55)],
                                    center: .center, startAngle: .degrees(-135), endAngle: .degrees(225)),
                    lineWidth: 1.5)
                .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
    }
}

struct PrismLensBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat

    var body: some View {
        let d = max(22, size * 0.2)
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: max(1.5, d * 0.07)))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: d * 0.46, weight: .bold))
                    .foregroundStyle(color == StatusColor.warning ? Ink.onBright : Color.white)
            )
            .frame(width: d, height: d)
            .shadow(color: color.opacity(0.5), radius: 6)
            .offset(x: size * 0.354, y: size * 0.354)
    }
}

// MARK: - Animated motif layers

enum PrismLensLayer {
    case back, inside, front
}

/// One Canvas layer of a lens motif. Time-driven while `animating` (≤ 30 fps), a
/// static composition otherwise.
struct PrismLensMotifLayer: View {
    var module: ModuleID
    var layer: PrismLensLayer
    var size: CGFloat
    var animating: Bool
    var scanning: Bool
    var start: Date

    var body: some View {
        let palette = module.palette
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animating)) { timeline in
            let t = animating ? max(0, timeline.date.timeIntervalSince(start)) : 0
            Canvas { context, canvasSize in
                let geometry = PrismLensGeometry(canvas: canvasSize, lensDiameter: size)
                PrismLensMotif.draw(module: module, layer: layer, context: &context, geometry: geometry,
                                    palette: palette, t: t, animating: animating)
                if scanning {
                    PrismLensMotif.drawOrbits(module: module, layer: layer, context: &context, geometry: geometry,
                                              palette: palette, t: t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PrismLensGeometry {
    var center: CGPoint
    /// Lens radius.
    var r: CGFloat
    /// Lens diameter.
    var size: CGFloat

    init(canvas: CGSize, lensDiameter: CGFloat) {
        center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        size = lensDiameter
        r = lensDiameter / 2
    }

    /// Point at `degrees` (0 = right, 90 = down) and distance `radius` from the centre.
    func point(_ degrees: Double, _ radius: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)
    }

    func circle(_ c: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Polyline arc between two angles (degrees, increasing = clockwise on screen).
    func arc(radius: CGFloat, from start: Double, to end: Double, segments: Int = 64) -> Path {
        var path = Path()
        let steps = max(2, segments)
        for i in 0...steps {
            let d = start + (end - start) * Double(i) / Double(steps)
            let p = point(d, radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

enum PrismLensMotif {
    static func draw(module: ModuleID, layer: PrismLensLayer, context: inout GraphicsContext,
                     geometry g: PrismLensGeometry, palette p: ModulePalette, t: Double, animating: Bool) {
        switch module {
        case .checkup: sparkleBurst(layer, &context, g, p, t)
        case .cleanup: bubbles(layer, &context, g, p, t)
        case .protection: shieldFacets(layer, &context, g, p, t, animating)
        case .performance: gaugeArcs(layer, &context, g, p, t, animating)
        case .applications: gridTiles(layer, &context, g, p, t)
        case .clutter: stackedCards(layer, &context, g, p, t)
        case .spaceMap: orbitingDots(layer, &context, g, p, t)
        case .cloudStorage: cloudLayers(layer, &context, g, p, t)
        case .toolbox: gearRing(layer, &context, g, p, t)
        case .activity: activityBars(layer, &context, g, p, t, animating)
        }
    }

    // MARK: Orbits (layer 7, scanning only)

    /// Tilted elliptical orbits (Checkup: three, one per pillar) with a travelling dot.
    /// The far half is drawn behind the lens and the near half in front.
    static func drawOrbits(module: ModuleID, layer: PrismLensLayer, context: inout GraphicsContext,
                           geometry g: PrismLensGeometry, palette p: ModulePalette, t: Double) {
        guard layer != .inside else { return }
        let tilts: [Double] = module == .checkup ? [-18, 42, 102] : [-18]
        let a = g.size * 0.625
        let b = g.size * 0.225
        for (index, tilt) in tilts.enumerated() {
            let phi = tilt * .pi / 180
            func pt(_ theta: Double) -> CGPoint {
                let x = Double(a) * cos(theta)
                let y = Double(b) * sin(theta)
                return CGPoint(x: g.center.x + CGFloat(x * cos(phi) - y * sin(phi)),
                               y: g.center.y + CGFloat(x * sin(phi) + y * cos(phi)))
            }
            // Near half: sin θ ≥ 0 (θ in 0...π); far half: θ in π...2π.
            let range: (Double, Double) = layer == .front ? (0, .pi) : (.pi, 2 * .pi)
            var path = Path()
            for i in 0...48 {
                let theta = range.0 + (range.1 - range.0) * Double(i) / 48
                if i == 0 { path.move(to: pt(theta)) } else { path.addLine(to: pt(theta)) }
            }
            context.stroke(path, with: .color(Color.white.opacity(layer == .front ? 0.22 : 0.12)), lineWidth: 1)

            let theta = (t / 6 * 2 * .pi + Double(index) * 2.1).truncatingRemainder(dividingBy: 2 * .pi)
            let isNear = sin(theta) >= 0
            if (layer == .front) == isNear {
                let dot = pt(theta)
                let d: CGFloat = isNear ? 6 : 4.5
                context.fill(g.circle(dot, d * 1.4), with: .color(p.accent2.opacity(isNear ? 0.25 : 0.12)))
                context.fill(g.circle(dot, d / 2), with: .color(p.accent2.opacity(isNear ? 1 : 0.55)))
            }
        }
    }

    // MARK: Checkup — sparkle burst

    private static func sparkleBurst(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                     _ p: ModulePalette, _ t: Double) {
        switch layer {
        case .back:
            for i in 0..<12 {
                let angle = Double(i) * 30 + 15
                let twinkle = 0.75 + 0.25 * sin(t * 1.3 + Double(i) * 1.7)
                let length = g.r * CGFloat(0.16 + 0.10 * PrismNoise.unit(i, 21)) * CGFloat(twinkle)
                let from = g.point(angle, g.r * 1.04)
                let to = g.point(angle, g.r * 1.04 + length)
                var ray = Path()
                ray.move(to: from)
                ray.addLine(to: to)
                ctx.stroke(ray, with: .linearGradient(Gradient(colors: [p.accent2.opacity(0.55 * twinkle), p.accent2.opacity(0)]),
                                                      startPoint: from, endPoint: to),
                           style: StrokeStyle(lineWidth: max(1, g.r * 0.018), lineCap: .round))
            }
        case .front:
            let stars: [(Double, CGFloat, CGFloat)] = [(-48, 1.20, 0.17), (205, 1.24, 0.10), (132, 1.14, 0.07), (18, 1.30, 0.06)]
            for (i, star) in stars.enumerated() {
                let twinkle = 0.7 + 0.3 * sin(t * 2.1 + Double(i) * 2.3)
                let c = g.point(star.0, g.r * star.1)
                let s = g.r * star.2 * CGFloat(0.85 + 0.15 * twinkle)
                ctx.fill(g.circle(c, s * 0.9), with: .color(p.accent2.opacity(0.18 * twinkle)))
                ctx.fill(PrismPaths.sparkle(in: CGRect(x: c.x - s, y: c.y - s, width: s * 2, height: s * 2)),
                         with: .color(Color.white.opacity(0.92 * twinkle)))
            }
        case .inside:
            break
        }
    }

    // MARK: Cleanup — rising bubbles + lagoon waterline

    private static func bubbles(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                _ p: ModulePalette, _ t: Double) {
        switch layer {
        case .inside:
            let core = g.r * 0.7
            let level = g.center.y + core * 0.28
            var water = Path()
            water.move(to: CGPoint(x: g.center.x - core, y: g.center.y + core))
            let steps = 32
            for i in 0...steps {
                let x = -1 + 2 * Double(i) / Double(steps)
                let y = level + CGFloat(sin(x * 3.2 + t * 1.6) * 0.045 + sin(x * 6.1 - t * 2.3) * 0.02) * core
                water.addLine(to: CGPoint(x: g.center.x + CGFloat(x) * core, y: y))
            }
            water.addLine(to: CGPoint(x: g.center.x + core, y: g.center.y + core))
            water.closeSubpath()
            ctx.fill(water, with: .linearGradient(Gradient(colors: [p.accent.opacity(0.32), p.glow.opacity(0.10)]),
                                                  startPoint: CGPoint(x: g.center.x, y: level),
                                                  endPoint: CGPoint(x: g.center.x, y: g.center.y + core)))
        case .front:
            for i in 0..<9 {
                let x0 = PrismNoise.value(i, 31, in: -1.0...1.0)
                let radius = g.r * CGFloat(PrismNoise.value(i, 32, in: 0.05...0.15))
                let speed = PrismNoise.value(i, 33, in: 0.10...0.22)
                let life = (PrismNoise.unit(i, 34) + t * speed).truncatingRemainder(dividingBy: 1)
                let y = g.center.y + g.r * CGFloat(0.95 - 2.15 * life)
                let x = g.center.x + g.r * CGFloat(x0 * 1.05 + sin(t * 1.4 + Double(i)) * 0.05)
                let alpha = sin(life * .pi)
                let c = CGPoint(x: x, y: y)
                ctx.opacity = alpha
                ctx.fill(g.circle(c, radius), with: .color(Color.white.opacity(0.07)))
                ctx.stroke(g.circle(c, radius), with: .color(Color.white.opacity(0.45)), lineWidth: max(0.8, radius * 0.08))
                ctx.fill(g.circle(CGPoint(x: c.x - radius * 0.35, y: c.y - radius * 0.35), radius * 0.22),
                         with: .color(Color.white.opacity(0.75)))
                ctx.opacity = 1
            }
        case .back:
            break
        }
    }

    // MARK: Protection — faceted shield crown

    private static func shieldFacets(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                     _ p: ModulePalette, _ t: Double, _ animating: Bool) {
        switch layer {
        case .back:
            let count = 8
            let sweep = animating ? (t * 0.5).truncatingRemainder(dividingBy: 1) * Double(count) : -10
            for i in 0..<count {
                let a0 = Double(i) * 45 + 3 - 90
                let a1 = a0 + 39
                let mid = (a0 + a1) / 2
                var facet = Path()
                facet.move(to: g.point(a0, g.r * 1.05))
                facet.addLine(to: g.point(mid, g.r * 1.27))
                facet.addLine(to: g.point(a1, g.r * 1.05))
                facet.addLine(to: g.point(mid, g.r * 1.10))
                facet.closeSubpath()
                var distance = abs(Double(i) - sweep)
                distance = min(distance, Double(count) - distance)
                let lit = max(0, 1 - distance / 1.5)
                let base = i % 2 == 0 ? p.accent : p.accent2
                ctx.fill(facet, with: .color(base.opacity(0.22 + 0.4 * lit)))
                ctx.stroke(facet, with: .color(Color.white.opacity(0.18 + 0.3 * lit)), lineWidth: 0.8)
            }
        case .inside:
            let core = g.r * 0.7
            for i in 0..<6 {
                let a0 = Double(i) * 60 - 90
                var tri = Path()
                tri.move(to: g.center)
                tri.addLine(to: g.point(a0, core))
                tri.addLine(to: g.point(a0 + 60, core))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(Color.white.opacity(i % 2 == 0 ? 0.05 : 0.0)))
            }
        case .front:
            break
        }
    }

    // MARK: Performance — gauge arcs

    private static func gaugeArcs(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                  _ p: ModulePalette, _ t: Double, _ animating: Bool) {
        switch layer {
        case .back:
            let radii: [CGFloat] = [1.09, 1.18, 1.27]
            let base: [Double] = [0.62, 0.45, 0.78]
            let width = max(1.5, g.r * 0.03)
            for (i, radius) in radii.enumerated() {
                let rr = g.r * radius
                ctx.stroke(g.arc(radius: rr, from: 135, to: 405), with: .color(Color.white.opacity(0.10)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
                let wobble = animating ? sin(t * (0.9 + Double(i) * 0.35) + Double(i)) * 0.18 : 0
                let fraction = min(0.98, max(0.08, base[i] + wobble))
                let end = 135 + 270 * fraction
                let gradient = Gradient(colors: [p.accent2, p.accent])
                ctx.stroke(g.arc(radius: rr, from: 135, to: end),
                           with: .linearGradient(gradient, startPoint: g.point(135, rr), endPoint: g.point(end, rr)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
                if i == radii.count - 1 {
                    let tip = g.point(end, rr)
                    ctx.fill(g.circle(tip, width * 1.8), with: .color(p.accent.opacity(0.3)))
                    ctx.fill(g.circle(tip, width * 0.8), with: .color(Color.white))
                }
            }
            for i in 0...27 {
                let angle = 135 + Double(i) * 10
                let major = i % 9 == 0
                var tick = Path()
                tick.move(to: g.point(angle, g.r * 1.34))
                tick.addLine(to: g.point(angle, g.r * (major ? 1.41 : 1.37)))
                ctx.stroke(tick, with: .color(Color.white.opacity(major ? 0.35 : 0.18)), lineWidth: major ? 1.4 : 0.8)
            }
        case .inside, .front:
            break
        }
    }

    // MARK: Applications — floating app tiles

    private static func gridTiles(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                  _ p: ModulePalette, _ t: Double) {
        switch layer {
        case .back, .front:
            // Upper tiles sit behind the lens, lower tiles in front.
            let tiles: [(angle: Double, tilt: Double)] = layer == .back ? [(-135, -12), (-45, 10)] : [(135, 9), (45, -11)]
            for (i, tile) in tiles.enumerated() {
                let seed = layer == .back ? i : i + 2
                let bob = sin(t * 0.8 + Double(seed) * 1.6) * Double(g.r) * 0.035
                var c = g.point(tile.angle, g.r * 1.13)
                c.y += CGFloat(bob)
                let s = g.r * 0.30
                var tctx = ctx
                tctx.translateBy(x: c.x, y: c.y)
                tctx.rotate(by: .degrees(tile.tilt + sin(t * 0.6 + Double(seed)) * 3))
                let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
                let shape = Path(roundedRect: rect, cornerRadius: s * 0.26, style: .continuous)
                tctx.fill(shape, with: .linearGradient(Gradient(colors: [p.accent.opacity(0.95), p.glow.opacity(0.85)]),
                                                       startPoint: CGPoint(x: 0, y: -s / 2), endPoint: CGPoint(x: 0, y: s / 2)))
                tctx.stroke(shape, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
                let inner = CGRect(x: -s * 0.2, y: -s * 0.2, width: s * 0.4, height: s * 0.4)
                tctx.fill(Path(roundedRect: inner, cornerRadius: s * 0.1, style: .continuous), with: .color(Color.white.opacity(0.4)))
            }
        case .inside:
            let core = g.r * 0.7
            let cell = core * 0.36
            for row in -1...1 {
                for col in -1...1 {
                    let rect = CGRect(x: g.center.x + CGFloat(col) * cell * 1.25 - cell / 2,
                                      y: g.center.y + CGFloat(row) * cell * 1.25 - cell / 2, width: cell, height: cell)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.25, style: .continuous),
                             with: .color(Color.white.opacity(0.05)))
                }
            }
        }
    }

    // MARK: Clutter — fanned stacked cards

    private static func stackedCards(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                     _ p: ModulePalette, _ t: Double) {
        guard layer == .back else { return }
        let angles: [Double] = [-17, -7, 6]
        let breathe = sin(t * 0.9) * 3
        for (i, angle) in angles.enumerated() {
            var cctx = ctx
            cctx.translateBy(x: g.center.x - g.r * 0.22 + CGFloat(i) * g.r * 0.1, y: g.center.y - g.r * 0.18)
            cctx.rotate(by: .degrees(angle + breathe * Double(i - 1)))
            let w = g.r * 1.0
            let h = g.r * 1.28
            let rect = CGRect(x: -w / 2, y: -h / 2 - g.r * 0.28, width: w, height: h)
            let card = Path(roundedRect: rect, cornerRadius: g.r * 0.12, style: .continuous)
            cctx.fill(card, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.16 + 0.03 * Double(i)), p.accent.opacity(0.10)]),
                                                  startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            cctx.stroke(card, with: .color(Color.white.opacity(0.24)), lineWidth: 1)
            for line in 0..<3 {
                let lw = w * (line == 0 ? 0.55 : 0.7 - CGFloat(line) * 0.12)
                let lr = CGRect(x: rect.minX + w * 0.12, y: rect.minY + h * 0.1 + CGFloat(line) * h * 0.07, width: lw, height: max(1.5, h * 0.025))
                cctx.fill(Path(roundedRect: lr, cornerRadius: lr.height / 2), with: .color(Color.white.opacity(0.22)))
            }
        }
    }

    // MARK: Space Map — orbiting dots and packed circles

    private static func orbitingDots(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                     _ p: ModulePalette, _ t: Double) {
        switch layer {
        case .back:
            ctx.stroke(g.circle(g.center, g.r * 1.25), with: .color(Color.white.opacity(0.13)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            ctx.stroke(g.circle(g.center, g.r * 1.09), with: .color(Color.white.opacity(0.07)), lineWidth: 1)
        case .front:
            for i in 0..<6 {
                let speed = 360.0 / PrismNoise.value(i, 41, in: 28...46)
                let angle = PrismNoise.value(i, 42, in: 0...360) + t * speed
                let ring = i % 2 == 0 ? 1.25 : 1.09
                let c = g.point(angle, g.r * CGFloat(ring))
                let s = g.r * CGFloat(PrismNoise.value(i, 43, in: 0.04...0.11))
                let color = i % 3 == 0 ? p.accent2 : p.accent
                ctx.fill(g.circle(c, s * 1.8), with: .color(color.opacity(0.18)))
                ctx.fill(g.circle(c, s), with: .color(color))
                ctx.fill(g.circle(CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.3), s * 0.35), with: .color(Color.white.opacity(0.6)))
            }
        case .inside:
            let core = g.r * 0.7
            let packs: [(CGFloat, CGFloat, CGFloat)] = [(-0.30, -0.25, 0.34), (0.32, -0.18, 0.26), (0.05, 0.36, 0.30), (-0.42, 0.30, 0.16), (0.48, 0.30, 0.13)]
            for pack in packs {
                let c = CGPoint(x: g.center.x + pack.0 * core, y: g.center.y + pack.1 * core)
                ctx.fill(g.circle(c, pack.2 * core), with: .color(Color.white.opacity(0.05)))
                ctx.stroke(g.circle(c, pack.2 * core), with: .color(Color.white.opacity(0.10)), lineWidth: 0.8)
            }
        }
    }

    // MARK: Cloud Storage — drifting cloud layers

    /// Cloud silhouette as separate components (a base pill and three puffs).
    private static func cloudParts(center c: CGPoint, width w: CGFloat) -> [Path] {
        let h = w * 0.36
        return [
            Path(roundedRect: CGRect(x: c.x - w / 2, y: c.y, width: w, height: h * 0.55), cornerRadius: h * 0.27, style: .continuous),
            Path(ellipseIn: CGRect(x: c.x - w * 0.42, y: c.y - h * 0.25, width: w * 0.42, height: w * 0.40)),
            Path(ellipseIn: CGRect(x: c.x - w * 0.12, y: c.y - h * 0.62, width: w * 0.5, height: w * 0.475)),
            Path(ellipseIn: CGRect(x: c.x + w * 0.16, y: c.y - h * 0.18, width: w * 0.34, height: w * 0.32)),
        ]
    }

    /// Fills the union of the cloud parts with one uniform opacity (parts are drawn
    /// opaque into a layer that is composited at `opacity`, so overlaps don't darken).
    private static func fillCloud(_ ctx: inout GraphicsContext, center: CGPoint, width: CGFloat,
                                  shading: GraphicsContext.Shading, opacity: Double) {
        let parts = cloudParts(center: center, width: width)
        let previous = ctx.opacity
        ctx.opacity = opacity
        ctx.drawLayer { layer in
            for part in parts { layer.fill(part, with: shading) }
        }
        ctx.opacity = previous
    }

    private static func cloudLayers(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                    _ p: ModulePalette, _ t: Double) {
        switch layer {
        case .back:
            let drift = CGFloat(sin(t * 0.35)) * g.r * 0.06
            fillCloud(&ctx, center: CGPoint(x: g.center.x + g.r * 0.95 + drift, y: g.center.y - g.r * 0.95), width: g.r * 0.62,
                      shading: .color(Color.white), opacity: 0.12)
        case .inside:
            let core = g.r * 0.7
            for i in 0..<2 {
                let speed = i == 0 ? 0.05 : 0.08
                let travel = (t * speed + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let x = g.center.x + core * CGFloat(-1.4 + 2.8 * travel)
                let y = g.center.y + core * (i == 0 ? 0.42 : 0.62)
                fillCloud(&ctx, center: CGPoint(x: x, y: y), width: core * (i == 0 ? 1.1 : 1.4),
                          shading: .color(Color.white), opacity: i == 0 ? 0.10 : 0.16)
            }
        case .front:
            let drift = CGFloat(sin(t * 0.5 + 1)) * g.r * 0.05
            let c = CGPoint(x: g.center.x - g.r * 0.62 + drift, y: g.center.y + g.r * 0.78)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color.white, p.accent2.opacity(0.6)]),
                startPoint: CGPoint(x: c.x, y: c.y - g.r * 0.3), endPoint: CGPoint(x: c.x, y: c.y + g.r * 0.2))
            fillCloud(&ctx, center: c, width: g.r * 0.95, shading: shading, opacity: 0.3)
        }
    }

    // MARK: Toolbox — rotating gear ring

    private static func gearRing(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                 _ p: ModulePalette, _ t: Double) {
        switch layer {
        case .back:
            let rotation = t * 6
            ctx.stroke(g.circle(g.center, g.r * 1.07), with: .color(Color.white.opacity(0.14)), lineWidth: max(1, g.r * 0.02))
            for i in 0..<16 {
                let angle = Double(i) * 22.5 + rotation
                var tctx = ctx
                let c = g.point(angle, g.r * 1.13)
                tctx.translateBy(x: c.x, y: c.y)
                tctx.rotate(by: .degrees(angle + 90))
                let w = g.r * 0.12
                let h = g.r * 0.11
                let tooth = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: w * 0.25, style: .continuous)
                tctx.fill(tooth, with: .color(p.accent.opacity(0.16)))
                tctx.stroke(tooth, with: .color(Color.white.opacity(0.2)), lineWidth: 0.8)
            }
        case .inside:
            let core = g.r * 0.7
            for i in -2...2 {
                let offset = CGFloat(i) * core * 0.36
                var v = Path()
                v.move(to: CGPoint(x: g.center.x + offset, y: g.center.y - core))
                v.addLine(to: CGPoint(x: g.center.x + offset, y: g.center.y + core))
                var h = Path()
                h.move(to: CGPoint(x: g.center.x - core, y: g.center.y + offset))
                h.addLine(to: CGPoint(x: g.center.x + core, y: g.center.y + offset))
                ctx.stroke(v, with: .color(Color.white.opacity(0.05)), lineWidth: 0.7)
                ctx.stroke(h, with: .color(Color.white.opacity(0.05)), lineWidth: 0.7)
            }
        case .front:
            break
        }
    }

    // MARK: Activity — live bars and pulse rings

    private static func activityBars(_ layer: PrismLensLayer, _ ctx: inout GraphicsContext, _ g: PrismLensGeometry,
                                     _ p: ModulePalette, _ t: Double, _ animating: Bool) {
        switch layer {
        case .back:
            if animating {
                for i in 0..<2 {
                    let life = (t * 0.45 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    let radius = g.r * CGFloat(1.02 + 0.32 * life)
                    ctx.stroke(g.circle(g.center, radius), with: .color(p.accent.opacity(0.35 * (1 - life))), lineWidth: 1.5)
                }
            } else {
                ctx.stroke(g.circle(g.center, g.r * 1.12), with: .color(Color.white.opacity(0.09)), lineWidth: 1)
            }
        case .inside:
            let core = g.r * 0.7
            let heights: [Double] = [0.30, 0.52, 0.40, 0.70, 0.48, 0.62, 0.36]
            let barWidth = core * 0.17
            let gap = core * 0.08
            let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            let baseline = g.center.y + core * 0.85
            for (i, h0) in heights.enumerated() {
                let h = animating ? h0 + sin(t * 2.2 + Double(i) * 0.9) * 0.14 : h0
                let height = core * CGFloat(max(0.12, h))
                let x = g.center.x - total / 2 + CGFloat(i) * (barWidth + gap)
                let rect = CGRect(x: x, y: baseline - height, width: barWidth, height: height)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth * 0.35, style: .continuous),
                         with: .linearGradient(Gradient(colors: [p.accent.opacity(0.45), p.accent2.opacity(0.12)]),
                                               startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }
        case .front:
            break
        }
    }
}
