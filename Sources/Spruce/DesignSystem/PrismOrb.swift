import SpruceCore
import SwiftUI

// Internals of `ActionOrb` and `ProgressRing` (B.8.4, B.8.5, B.13.6).

/// Visual state of the orb.
enum PrismOrbPhase: Equatable {
    case idle
    case busy
    case ready
    case done
    case disabled
}

/// The orb's drawing: glow, track, progress ring, glass disc and labels. Layout size
/// is the disc diameter; glow and ring overflow it.
struct PrismOrbFace: View {
    var title: String
    var subtitle: String?
    var palette: ModulePalette
    var diameter: CGFloat
    var phase: PrismOrbPhase
    var isEnabled: Bool
    var progress: Double?
    var hovering: Bool
    var focused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let scale = diameter / 96
        let ink = PrismInk(contrast)
        let track = diameter + 16 * scale
        ZStack {
            PrismOrbGlow(color: phase == .done ? StatusColor.success : palette.glow,
                         diameter: diameter * 1.5,
                         opacity: glowOpacity * ink.glowScale,
                         breathing: phase == .idle && !PrismAmbient.isReduced(reduceMotion))
            Circle()
                .strokeBorder(trackColor(ink), lineWidth: (phase == .ready ? 2 : 1.5) * scale)
                .frame(width: track, height: track)
            ring(track: track, scale: scale)
            disc(scale: scale)
            labels(scale: scale)
            if focused {
                Circle()
                    .strokeBorder(palette.accentText, lineWidth: 2)
                    .shadow(color: palette.accentText.opacity(0.35), radius: 4)
                    .frame(width: track + 8, height: track + 8)
            }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
        .brightness(hovering ? 0.06 : 0)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.adaptive(Motion.emphasized, reduceMotion: reduceMotion), value: phase)
        .contentShape(Circle())
    }

    private var glowOpacity: Double {
        switch phase {
        case .idle: return hovering ? 0.70 : 0.60
        case .busy: return 0.55
        case .ready: return hovering ? 0.75 : 0.65
        case .done: return 0.60
        case .disabled: return 0
        }
    }

    private func trackColor(_ ink: PrismInk) -> Color {
        switch phase {
        case .idle: return Color.white.opacity(hovering ? 0.22 : 0.14)
        case .busy: return Color.white.opacity(0.10)
        case .ready: return palette.accent.opacity(hovering ? 0.55 : 0.40)
        case .done: return StatusColor.success.opacity(0.6)
        case .disabled: return Color.white.opacity(ink.increased ? 0.2 : 0.08)
        }
    }

    @ViewBuilder
    private func ring(track: CGFloat, scale: CGFloat) -> some View {
        if phase == .busy {
            Group {
                if let progress {
                    PrismProgressArc(fraction: progress, palette: palette, lineWidth: 3 * scale, showsHead: true)
                } else {
                    PrismSpinnerArc(palette: palette, lineWidth: 3 * scale)
                }
            }
            .frame(width: track, height: track)
        } else if phase == .done {
            Circle()
                .strokeBorder(StatusColor.success, lineWidth: 3 * scale)
                .frame(width: track, height: track)
        }
    }

    private func disc(scale: CGFloat) -> some View {
        ZStack {
            Circle().fill(palette.orbFill.opacity(phase == .busy ? 0.85 : 1))
            // Light pooling from below (glassy depth).
            Circle().fill(RadialGradient(colors: [palette.accent.opacity(0.38), .clear],
                                         center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: diameter * 0.62))
            if phase == .done {
                Circle().fill(StatusColor.success.opacity(0.30))
            }
            if phase == .busy && !reduceMotion {
                PrismOrbShimmer()
            }
            // Specular cap.
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: diameter * 0.70, height: diameter * 0.42)
                .offset(y: -diameter * 0.22)
            Circle()
                .strokeBorder(phase == .ready ? palette.accentText : Color.white.opacity(0.25),
                              lineWidth: phase == .ready ? 2 * scale : 1)
        }
        .clipShape(Circle())
        .frame(width: diameter, height: diameter)
        .shadow(color: palette.glow.opacity(phase == .disabled ? 0 : 0.45), radius: 14 * scale, y: 6 * scale)
        .opacity(phase == .disabled ? 0.35 : 1)
    }

    private func labels(scale: CGFloat) -> some View {
        VStack(spacing: 2 * scale) {
            if phase == .done {
                PrismOrbCheck(size: 30 * scale)
            } else {
                Text(title)
                    .font(.system(size: 15 * scale, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11 * scale, weight: .medium).monospacedDigit())
                    .opacity(0.82)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.4))
        .padding(.horizontal, diameter * 0.12)
        .frame(width: diameter, height: diameter)
    }
}

/// Breathing glow behind the orb (radial gradient, so no per-frame blur).
struct PrismOrbGlow: View {
    var color: Color
    var diameter: CGFloat
    var opacity: Double
    var breathing: Bool

    var body: some View {
        let glow = Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.35), .clear],
                                 center: .center, startRadius: 0, endRadius: diameter * 0.65))
            .frame(width: diameter * 1.3, height: diameter * 1.3)
            .allowsHitTesting(false)
        if breathing {
            // 40 % ↔ 60 % over 1.8 s half-cycles (B.8.4 idle).
            glow.phaseAnimator([false, true]) { view, phase in
                view.opacity(phase ? 1 : 0.67)
            } animation: { _ in
                .easeInOut(duration: 1.8)
            }
        } else {
            glow
        }
    }
}

/// Slow rotating highlight across the disc while busy.
private struct PrismOrbShimmer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = (t / 2.4).truncatingRemainder(dividingBy: 1) * 360
            Circle()
                .fill(AngularGradient(gradient: Gradient(colors: [.clear, Color.white.opacity(0.16), .clear, .clear]),
                                      center: .center, angle: .degrees(0)))
                .rotationEffect(.degrees(angle))
        }
        .allowsHitTesting(false)
    }
}

/// Check glyph that draws itself (0.4 s) when it appears.
private struct PrismOrbCheck: View {
    var size: CGFloat
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PrismCheckmarkShape()
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(Color.white, style: StrokeStyle(lineWidth: max(2, size * 0.11), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .onAppear {
                if reduceMotion {
                    drawn = true
                } else {
                    withAnimation(.easeOut(duration: 0.4)) { drawn = true }
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Arcs

/// Determinate arc (0...1) with an angular gradient (tail accent2 → head accent) and a
/// glowing head dot. Interpolates linearly (0.3 s) to each new value.
struct PrismProgressArc: View {
    var fraction: Double
    var palette: ModulePalette
    var lineWidth: CGFloat
    var showsHead: Bool = true

    var body: some View {
        let f = min(max(fraction, 0), 1)
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: max(0.004, f))
                    .stroke(palette.ringGradient(fraction: f), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if showsHead && f > 0.01 {
                    Circle()
                        .fill(Color.white)
                        .frame(width: lineWidth * 1.2, height: lineWidth * 1.2)
                        .shadow(color: palette.accent, radius: lineWidth * 1.3)
                        .offset(y: -(d / 2 - lineWidth / 2))
                        .rotationEffect(.degrees(360 * f))
                }
            }
            .frame(width: d, height: d)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .animation(Motion.progress, value: f)
    }
}

/// Indeterminate 90° arc spinning at 1 rev / 1.2 s (kept under Reduce Motion: it
/// carries information).
struct PrismSpinnerArc: View {
    var palette: ModulePalette
    var lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = (t / 1.2).truncatingRemainder(dividingBy: 1) * 360
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: 0.25)
                .stroke(AngularGradient(gradient: Gradient(colors: [palette.accent.opacity(0), palette.accent]),
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(90)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
    }
}
