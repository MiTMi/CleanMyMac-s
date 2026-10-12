import AppKit
import CoreGraphics
import Observation
import SpruceCore
import SwiftUI

// Internals of `LivingCanvas` (B.3.3, B.13.3): MeshGradient aurora on macOS 15,
// drifting radial blooms on macOS 14, a cached procedural grain overlay, and the
// shared canvas "energy" that flow screens raise or lower.

// MARK: - Shared canvas intensity

/// The window canvas's ambient intensity `k`, shared app-wide so that flow screens
/// (scanning, results, completion) can brighten or calm the single `LivingCanvas`
/// drawn behind everything. Use `.prismCanvasIntensity(_:)` rather than mutating
/// this directly; the most recently appeared requester wins.
@MainActor
@Observable
final class PrismCanvasState {
    static let shared = PrismCanvasState()

    private(set) var intensity: Double = PrismCanvasMath.Intensity.idle

    @ObservationIgnored private var requests: [(id: UUID, value: Double)] = []

    func request(_ id: UUID, _ value: Double) {
        if let index = requests.firstIndex(where: { $0.id == id }) {
            requests[index].value = value
        } else {
            requests.append((id: id, value: value))
        }
        recompute()
    }

    func release(_ id: UUID) {
        requests.removeAll { $0.id == id }
        recompute()
    }

    private func recompute() {
        let value = requests.last?.value ?? PrismCanvasMath.Intensity.idle
        if value != intensity { intensity = value }
    }
}

private struct PrismCanvasIntensityModifier: ViewModifier {
    var value: Double
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { PrismCanvasState.shared.request(token, value) }
            .onChange(of: value) { _, newValue in PrismCanvasState.shared.request(token, newValue) }
            .onDisappear { PrismCanvasState.shared.release(token) }
    }
}

extension View {
    /// While this view is on screen the window canvas uses intensity `k`
    /// (1 idle · 1.35 scanning · 0.8 results · 1.6 celebrating).
    func prismCanvasIntensity(_ k: Double) -> some View {
        modifier(PrismCanvasIntensityModifier(value: k))
    }
}

// MARK: - Canvas field

/// One module's full canvas. Animatable over `k` so intensity changes ease smoothly.
struct PrismCanvasField: View, Animatable {
    var palette: ModulePalette
    var k: Double
    /// Static frame (Reduce Motion / reduced ambient motion).
    var still: Bool
    /// Timeline paused (app inactive); keeps the last frame instead of snapping.
    var paused: Bool

    nonisolated var animatableData: Double {
        get { k }
        set { k = newValue }
    }

    var body: some View {
        ZStack {
            palette.canvasGradient
            if #available(macOS 15, *) {
                PrismMeshLayer(colors: Self.meshColors(palette, k: k), still: still, paused: paused)
            } else {
                PrismBloomLayer(palette: palette, k: k, still: still, paused: paused)
            }
        }
    }

    /// 3×3 mesh colours (B.3.3 recipe), derived from the palette tokens only.
    static func meshColors(_ p: ModulePalette, k: Double) -> [Color] {
        let mid = p.canvasTop.prismMix(p.canvasBottom, 0.45)
        let mid2 = p.canvasTop.prismMix(p.canvasBottom, 0.55)
        return [
            p.canvasTop, p.canvasTop, p.canvasTop.prismMix(p.accent2, 0.14),
            mid, mid.prismMix(p.accent, min(1, 0.30 * k)), mid2,
            p.canvasBottom, p.canvasBottom.prismMix(p.glow, min(1, 0.55 * k)), p.canvasBottom,
        ]
    }
}

@available(macOS 15, *)
private struct PrismMeshLayer: View {
    var colors: [Color]
    var still: Bool
    var paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: paused || still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: PrismCanvasMath.meshPoints(t), colors: colors)
        }
    }
}

/// macOS 14 fallback: three radial blooms drifting on slow Lissajous loops plus a
/// gentle 8 s breathe, at ≤ 20 fps.
private struct PrismBloomLayer: View {
    var palette: ModulePalette
    var k: Double
    var still: Bool
    var paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused || still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            let breathe = still ? 1 : 0.93 + 0.07 * sin(t / 8 * 2 * .pi)
            let c0 = PrismCanvasMath.bloomCenter(0, t)
            let c1 = PrismCanvasMath.bloomCenter(1, t)
            let c2 = PrismCanvasMath.bloomCenter(2, t)
            ZStack {
                EllipticalGradient(colors: [palette.glow.opacity(min(1, 0.46 * k * breathe)), .clear],
                                   center: UnitPoint(x: c0.x, y: c0.y), startRadiusFraction: 0, endRadiusFraction: 0.62)
                EllipticalGradient(colors: [palette.accent.opacity(min(1, 0.22 * k)), .clear],
                                   center: UnitPoint(x: c1.x, y: c1.y), startRadiusFraction: 0, endRadiusFraction: 0.48)
                EllipticalGradient(colors: [palette.accent2.opacity(min(1, 0.16 * k * breathe)), .clear],
                                   center: UnitPoint(x: c2.x, y: c2.y), startRadiusFraction: 0, endRadiusFraction: 0.42)
            }
        }
    }
}

// MARK: - Grain

/// Procedural monochrome grain, generated once and tiled (kills gradient banding).
@MainActor
enum PrismGrain {
    static let image: CGImage? = make(size: 160)

    private static func make(size: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let raw = context.data else { return nil }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * size)
        var rng = PrismXorShift(seed: 0x51_7C_E5_A1)
        for y in 0..<size {
            for x in 0..<size {
                // Triangular distribution around mid-grey: soft, film-like grain.
                let v = (rng.unit() + rng.unit()) * 0.5
                pixels[y * context.bytesPerRow + x] = UInt8(max(0, min(255, v * 255)))
            }
        }
        return context.makeImage()
    }
}

/// Grain overlay (~3 % visible strength). Omitted under Reduce Transparency and
/// Increase Contrast (B.13.4).
struct PrismGrainOverlay: View {
    var strength: Double = 0.07

    var body: some View {
        if let image = PrismGrain.image {
            Image(decorative: image, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(strength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
