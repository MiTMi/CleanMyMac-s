import AppKit
import SpruceCore
import SwiftUI

// Reusable visual effects for Prism: frosted surfaces, hover parallax, particles,
// count-up numbers, throttled status text, focus rings.

// MARK: - Surfaces (B.6, B.13.8)

private struct PrismSurfaceModifier: ViewModifier {
    var radius: CGFloat
    var tint: Color?
    var isHighlighted: Bool
    var isSelected: Bool
    var selectionColor: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let ink = PrismInk(contrast)
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        shape.fill(Color(white: 0.15))
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                    shape.fill(Color.white.opacity(isHighlighted ? 0.10 : 0.07))
                    if let tint {
                        shape.fill(tint.opacity(reduceTransparency ? 0.16 : 0.10))
                    }
                }
            }
            .overlay {
                ZStack {
                    shape.strokeBorder(ink.hairline, lineWidth: 1)
                    // 1 pt inner top highlight (elev.card).
                    shape.strokeBorder(LinearGradient(colors: [ink.highlight, .clear], startPoint: .top, endPoint: .center),
                                       lineWidth: 1)
                    if isSelected {
                        shape.strokeBorder(selectionColor ?? ink.highlight, lineWidth: ink.increased ? 2 : 1.2)
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Frosted content surface (tiles, list containers): material + white 7 % +
    /// hairline rim + top highlight; an opaque fill under Reduce Transparency.
    func prismSurface(radius: CGFloat = Radius.card, tint: Color? = nil, highlighted: Bool = false,
                      selected: Bool = false, selectionColor: Color? = nil) -> some View {
        modifier(PrismSurfaceModifier(radius: radius, tint: tint, isHighlighted: highlighted,
                                      isSelected: selected, selectionColor: selectionColor))
    }

    /// Frost capsule for secondary controls (B.8.8 "glass capsule").
    func prismGlassCapsule(highlighted: Bool = false) -> some View {
        modifier(PrismGlassCapsuleModifier(isHighlighted: highlighted))
    }
}

private struct PrismGlassCapsuleModifier: ViewModifier {
    var isHighlighted: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let ink = PrismInk(contrast)
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        Capsule().fill(Color(white: 0.22))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                    Capsule().fill(isHighlighted ? Color.white.opacity(0.16) : ink.controlFill)
                }
            }
            .overlay(Capsule().strokeBorder(isHighlighted ? ink.highlight : ink.hairline, lineWidth: 1))
    }
}

// MARK: - Focus ring (B.3.1 focus.ring)

extension View {
    /// `accentText` 2 pt ring + soft outer glow, shown while `isFocused`.
    func prismFocusRing<S: InsettableShape>(_ isFocused: Bool, color: Color, shape: S) -> some View {
        overlay {
            if isFocused {
                shape.inset(by: -3)
                    .strokeBorder(color, lineWidth: 2)
                    .shadow(color: color.opacity(0.35), radius: 4)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Link pointer on macOS 15+ for link-like text buttons (no-op on 14).
    @ViewBuilder
    func prismLinkPointer() -> some View {
        if #available(macOS 15, *) {
            self.pointerStyle(.link)
        } else {
            self
        }
    }

    /// Applies a keyboard shortcut only when one is given.
    @ViewBuilder
    func prismKeyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            self.keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}

// MARK: - Hover parallax (B.8.3, ≤ 6°)

private struct PrismParallaxModifier: ViewModifier {
    var maxDegrees: Double
    var isEnabled: Bool
    @State private var tilt = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .rotation3DEffect(.degrees(-Double(tilt.height) * maxDegrees * 2), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(Double(tilt.width) * maxDegrees * 2), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    guard isEnabled, !reduceMotion, geo.size.width > 0, geo.size.height > 0 else { return }
                    switch phase {
                    case .active(let point):
                        withAnimation(.spring(duration: 0.3)) {
                            tilt = CGSize(width: min(max(point.x / geo.size.width - 0.5, -0.5), 0.5),
                                          height: min(max(point.y / geo.size.height - 0.5, -0.5), 0.5))
                        }
                    case .ended:
                        withAnimation(.spring(duration: 0.5)) { tilt = .zero }
                    }
                }
        }
    }
}

extension View {
    /// Tilts the view up to `maxDegrees` toward the pointer while hovering.
    /// Disabled under Reduce Motion.
    func prismParallax(maxDegrees: Double = 6, enabled: Bool = true) -> some View {
        modifier(PrismParallaxModifier(maxDegrees: maxDegrees, isEnabled: enabled))
    }
}

// MARK: - Scan dust (B.13.5)

/// Inward-drifting "collected dust" particles around the hero while scanning.
/// 48 motes at ≤ 30 fps; nothing is drawn under Reduce Motion.
struct PrismScanDust: View {
    var color: Color
    var secondary: Color
    var isActive: Bool = true
    var count: Int = 48

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        if !PrismAmbient.isReduced(reduceMotion) {
            let motes = (0..<count).map { PrismMote.seeded($0) }
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || activeState == .inactive)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let half = min(size.width, size.height) / 2
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for mote in motes {
                        let p = mote.position(at: t)
                        let s = CGFloat(mote.size * p.scale)
                        let point = CGPoint(x: center.x + CGFloat(p.x) * half, y: center.y + CGFloat(p.y) * half)
                        context.opacity = p.opacity
                        context.fill(Path(ellipseIn: CGRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s)),
                                     with: .color(mote.usesSecondary ? secondary : color))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Completion burst (B.7 "Completion")

/// One-shot particle burst (28–40 motes, 0.9 s, outward with gravity). Plays once
/// when it appears; renders nothing under Reduce Motion.
struct PrismBurst: View {
    var color: Color
    var secondary: Color
    var count: Int = 34

    @State private var start = Date()
    @State private var running = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            let motes = (0..<count).map { PrismBurstMote.seeded($0, count: count) }
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !running)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    let alpha = PrismBurstMote.opacity(at: t)
                    guard alpha > 0 else { return }
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for mote in motes {
                        let o = mote.offset(at: t)
                        let s = CGFloat(mote.size * (1 - min(t, 0.9) * 0.4))
                        let p = CGPoint(x: center.x + CGFloat(o.x), y: center.y + CGFloat(o.y))
                        context.opacity = alpha
                        let rect = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
                        if mote.usesSecondary {
                            context.fill(Path(ellipseIn: rect), with: .color(secondary))
                        } else {
                            context.fill(PrismPaths.sparkle(in: rect.insetBy(dx: -s * 0.6, dy: -s * 0.6)), with: .color(color))
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                start = Date()
                running = true
            }
            .task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { running = false }
            }
        }
    }
}

/// Four-point sparkle star.
struct PrismSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        PrismPaths.sparkle(in: rect)
    }
}

/// Plain (actor-independent) path builders shared by shapes and Canvas drawing.
enum PrismPaths {
    /// Four-point sparkle star filling `rect`.
    static func sparkle(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        let pinch: CGFloat = 0.18
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - ry))
        path.addQuadCurve(to: CGPoint(x: c.x + rx, y: c.y), control: CGPoint(x: c.x + rx * pinch, y: c.y - ry * pinch))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + ry), control: CGPoint(x: c.x + rx * pinch, y: c.y + ry * pinch))
        path.addQuadCurve(to: CGPoint(x: c.x - rx, y: c.y), control: CGPoint(x: c.x - rx * pinch, y: c.y + ry * pinch))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - ry), control: CGPoint(x: c.x - rx * pinch, y: c.y - ry * pinch))
        path.closeSubpath()
        return path
    }
}

// MARK: - Numbers (B.13.9)

/// A byte count that interpolates while animating (count-up) with monospaced digits.
struct PrismCountingBytes: View, Animatable {
    var value: Double
    var font: Font = SpruceFont.metricXL
    var unitFont: Font = SpruceFont.unit
    var color: Color = Ink.primary

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let parts = PrismMetric.split(ByteFormat.string(Int64(max(0, value).rounded())))
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.value).font(font).foregroundStyle(color)
            if !parts.unit.isEmpty {
                Text(parts.unit).font(unitFont).foregroundStyle(Ink.secondary)
            }
        }
    }
}

/// A value + unit metric ("6.2" big, "GB" small). Non-numeric strings render whole.
struct PrismMetricText: View {
    var text: String
    var font: Font = SpruceFont.metricL
    var unitFont: Font = SpruceFont.unit
    var color: Color = Ink.primary

    var body: some View {
        let parts = PrismMetric.split(text)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.value)
                .font(font)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if !parts.unit.isEmpty {
                Text(parts.unit).font(unitFont).foregroundStyle(Ink.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Throttled status text (≤ 10 Hz, B.7 "Scanning")

/// Shows a fast-changing string (e.g. the path being scanned) at most 10 times per
/// second, always settling on the latest value.
struct PrismThrottledText: View {
    var value: String?
    var interval: Double = 0.1

    @State private var shown: String?
    @State private var lastUpdate = Date.distantPast
    @State private var pending: Task<Void, Never>?

    var body: some View {
        Text(shown ?? " ")
            .onAppear {
                shown = value
                lastUpdate = Date()
            }
            .onChange(of: value) { _, newValue in schedule(newValue) }
            .onDisappear { pending?.cancel() }
    }

    private func schedule(_ newValue: String?) {
        let now = Date()
        if now.timeIntervalSince(lastUpdate) >= interval {
            pending?.cancel()
            shown = newValue
            lastUpdate = now
            return
        }
        pending?.cancel()
        let delay = UInt64(max(0.01, interval - now.timeIntervalSince(lastUpdate)) * 1_000_000_000)
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            shown = newValue
            lastUpdate = Date()
        }
    }
}
