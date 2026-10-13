import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// Design system "Prism" — original tokens (see docs/research/09-design.md, Part B).
//
// CONTRACT: module code uses `module.palette`, `Ink`, `StatusColor`, `SpruceFont`,
// `Spacing`, `Radius`, `Motion`. The design-system owner may refine values and add
// members, but must not remove or rename existing ones.

extension Color {
    /// Creates a color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Linear sRGB mix of two colours (`fraction` 0 → self, 1 → `other`). Works on
    /// macOS 14 (SwiftUI's `Color.mix(with:by:)` is macOS 15+).
    func prismMix(_ other: Color, _ fraction: Double) -> Color {
        let t = min(max(fraction, 0), 1)
        let a = PrismRGBA(self)
        let b = PrismRGBA(other)
        return Color(.sRGB,
                     red: a.r + (b.r - a.r) * t,
                     green: a.g + (b.g - a.g) * t,
                     blue: a.b + (b.b - a.b) * t,
                     opacity: a.a + (b.a - a.a) * t)
    }
}

/// sRGB components of a SwiftUI colour (via AppKit).
struct PrismRGBA {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        r = Double(ns.redComponent)
        g = Double(ns.greenComponent)
        b = Double(ns.blueComponent)
        a = Double(ns.alphaComponent)
    }
}

/// Per-module colour identity.
struct ModulePalette {
    var canvasTop: Color
    var canvasBottom: Color
    var accent: Color
    var accentText: Color
    var accent2: Color
    var glow: Color
    var orbFill: Color
    /// SF Symbol used for the module's hero and rail.
    var symbol: String

    var canvasGradient: LinearGradient {
        LinearGradient(colors: [canvasTop, canvasBottom], startPoint: .top, endPoint: .bottom)
    }

    var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Fill of the rounded-square category badge (B.8.7): accent → glow, top to bottom.
    var badgeGradient: LinearGradient {
        LinearGradient(colors: [accent, glow], startPoint: .top, endPoint: .bottom)
    }

    /// Hero glyph gradient: white → accent2 (B.10.2 layer 4).
    var glyphGradient: LinearGradient {
        LinearGradient(colors: [Color.white, accent2], startPoint: .top, endPoint: .bottom)
    }

    /// Lens body (B.10.2 layer 2): accent2 → accent → canvasBottom, lit from the top-left.
    func lensBody(diameter: CGFloat) -> RadialGradient {
        RadialGradient(colors: [accent2.opacity(0.9), accent, canvasBottom.opacity(0.95)],
                       center: UnitPoint(x: 0.35, y: 0.30), startRadius: 0, endRadius: diameter * 0.75)
    }

    /// Progress arc gradient spanning exactly the drawn sweep: tail accent2 → head accent.
    func ringGradient(fraction: Double) -> AngularGradient {
        AngularGradient(gradient: Gradient(colors: [accent2, accent]), center: .center,
                        startAngle: .degrees(0), endAngle: .degrees(max(1, 360 * fraction)))
    }

    /// Opaque surface used instead of materials under Reduce Transparency (B.6):
    /// canvasBottom mixed 20 % with white.
    var solidSurface: Color { canvasBottom.prismMix(.white, 0.20) }
}

extension ModuleID {
    var palette: ModulePalette {
        switch self {
        case .checkup:
            return ModulePalette(canvasTop: Color(hex: 0x0E0B26), canvasBottom: Color(hex: 0x2A1F66), accent: Color(hex: 0x8C7BFF),
                                 accentText: Color(hex: 0xA99CFF), accent2: Color(hex: 0x45D9F5), glow: Color(hex: 0x6F5CFF),
                                 orbFill: Color(hex: 0x6556C2), symbol: "sparkles")
        case .cleanup:
            return ModulePalette(canvasTop: Color(hex: 0x051A17), canvasBottom: Color(hex: 0x0C4A3B), accent: Color(hex: 0x3BE8A9),
                                 accentText: Color(hex: 0x3BE8A9), accent2: Color(hex: 0xC2F261), glow: Color(hex: 0x1FCB8A),
                                 orbFill: Color(hex: 0x1D8464), symbol: "bubbles.and.sparkles")
        case .protection:
            return ModulePalette(canvasTop: Color(hex: 0x1E0710), canvasBottom: Color(hex: 0x5A1428), accent: Color(hex: 0xFF6177),
                                 accentText: Color(hex: 0xFF8193), accent2: Color(hex: 0xFFB08A), glow: Color(hex: 0xF23D5C),
                                 orbFill: Color(hex: 0xBD4257), symbol: "shield.lefthalf.filled")
        case .performance:
            return ModulePalette(canvasTop: Color(hex: 0x1F1003), canvasBottom: Color(hex: 0x5C2E06), accent: Color(hex: 0xFFAC33),
                                 accentText: Color(hex: 0xFFAC33), accent2: Color(hex: 0xFFE066), glow: Color(hex: 0xFF8A00),
                                 orbFill: Color(hex: 0xA5671A), symbol: "bolt.fill")
        case .applications:
            return ModulePalette(canvasTop: Color(hex: 0x070F2B), canvasBottom: Color(hex: 0x15306E), accent: Color(hex: 0x5C88FF),
                                 accentText: Color(hex: 0x86A6FF), accent2: Color(hex: 0x7FE6FF), glow: Color(hex: 0x3D6BFF),
                                 orbFill: Color(hex: 0x4065C5), symbol: "square.grid.2x2.fill")
        case .clutter:
            return ModulePalette(canvasTop: Color(hex: 0x03191F), canvasBottom: Color(hex: 0x0A4552), accent: Color(hex: 0x2ED6EE),
                                 accentText: Color(hex: 0x2ED6EE), accent2: Color(hex: 0x7CF5D4), glow: Color(hex: 0x00B8D9),
                                 orbFill: Color(hex: 0x187F90), symbol: "square.stack.3d.up.fill")
        case .spaceMap:
            return ModulePalette(canvasTop: Color(hex: 0x130A26), canvasBottom: Color(hex: 0x3B1F6E), accent: Color(hex: 0xB98CFF),
                                 accentText: Color(hex: 0xC9A6FF), accent2: Color(hex: 0xFF8AD8), glow: Color(hex: 0x9B5CFF),
                                 orbFill: Color(hex: 0x8760C5), symbol: "circle.hexagongrid.fill")
        case .cloudStorage:
            return ModulePalette(canvasTop: Color(hex: 0x06142A), canvasBottom: Color(hex: 0x173E70), accent: Color(hex: 0x66BFFF),
                                 accentText: Color(hex: 0x66BFFF), accent2: Color(hex: 0xE4F3FF), glow: Color(hex: 0x3FA6FF),
                                 orbFill: Color(hex: 0x3B78B0), symbol: "icloud.fill")
        case .toolbox:
            return ModulePalette(canvasTop: Color(hex: 0x10121F), canvasBottom: Color(hex: 0x2C3152), accent: Color(hex: 0xA4ADE6),
                                 accentText: Color(hex: 0xA4ADE6), accent2: Color(hex: 0xE1E5FF), glow: Color(hex: 0x7F8BD6),
                                 orbFill: Color(hex: 0x6A719F), symbol: "wrench.and.screwdriver.fill")
        case .activity:
            return ModulePalette(canvasTop: Color(hex: 0x0D1A08), canvasBottom: Color(hex: 0x2E4A12), accent: Color(hex: 0xBEEB6B),
                                 accentText: Color(hex: 0xBEEB6B), accent2: Color(hex: 0x7EE0B0), glow: Color(hex: 0x9BD63A),
                                 orbFill: Color(hex: 0x5E7F2F), symbol: "chart.line.uptrend.xyaxis")
        }
    }
}

/// Text colours on the dark canvas.
enum Ink {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.66)
    static let disabled = Color.white.opacity(0.32)
    static let onBright = Color(hex: 0x0B0B14)
    static let hairline = Color.white.opacity(0.10)
    static let highlight = Color.white.opacity(0.18)
    static let subtleFill = Color.white.opacity(0.06)
    static let controlFill = Color.white.opacity(0.10)
    static let selectedFill = Color.white.opacity(0.14)
    /// Scrim behind sheets (B.3.1).
    static let scrim = Color(hex: 0x05050A, opacity: 0.55)
}

/// Contrast-aware ink (B.14 "Increase Contrast": hairlines 30 %, secondary 88 %).
/// Components read `@Environment(\.colorSchemeContrast)` and build one of these.
struct PrismInk {
    var increased: Bool

    init(_ contrast: ColorSchemeContrast) {
        increased = contrast == .increased
    }

    var primary: Color { Ink.primary }
    var secondary: Color { increased ? Color.white.opacity(0.88) : Ink.secondary }
    var tertiary: Color { increased ? Color.white.opacity(0.80) : Ink.tertiary }
    var hairline: Color { increased ? Color.white.opacity(0.30) : Ink.hairline }
    var highlight: Color { increased ? Color.white.opacity(0.34) : Ink.highlight }
    var subtleFill: Color { increased ? Color.white.opacity(0.10) : Ink.subtleFill }
    var controlFill: Color { increased ? Color.white.opacity(0.18) : Ink.controlFill }
    var selectedFill: Color { increased ? Color.white.opacity(0.22) : Ink.selectedFill }
    /// Unchecked checkbox stroke (B.8.8: 1.5 pt white 40 %).
    var checkboxStroke: Color { increased ? Color.white.opacity(0.78) : Color.white.opacity(0.42) }
    /// Glows are disabled under Increase Contrast.
    var glowScale: Double { increased ? 0 : 1 }
}

enum StatusColor {
    static let success = Color(hex: 0x34D399)
    static let warning = Color(hex: 0xFBBF24)
    static let danger = Color(hex: 0xFF5A5F)
    static let info = Color(hex: 0x60A5FA)

    static func of(_ status: TileStatus) -> Color {
        switch status {
        case .clear: return success
        case .attention: return warning
        case .critical: return danger
        case .info: return info
        case .unavailable: return Ink.disabled
        }
    }

    static func of(_ safety: SafetyLevel) -> Color {
        switch safety {
        case .safe: return success
        case .review: return warning
        case .risky: return danger
        }
    }
}

enum SpruceFont {
    /// Giant thin numerals (hero metrics).
    static func numeral(_ size: CGFloat) -> Font { .system(size: size, weight: .thin, design: .rounded).monospacedDigit() }
    /// Module hero titles (B.4 `display`: light; apply `.tracking(-0.4)` at 40 pt).
    static func display(_ size: CGFloat = 40) -> Font { .system(size: size, weight: .light) }
    /// Pane and sheet titles.
    static let title = Font.system(size: 20, weight: .semibold)
    /// Row / tile headlines.
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let mono = Font.system(size: 11, design: .monospaced)

    // B.4 additions.
    /// Flow headlines ("6.2 GB ready to clean", "Scanning…").
    static let flowHeadline = Font.system(size: 26, weight: .semibold)
    /// The result number on module result screens.
    static let metricXL = Font.system(size: 56, weight: .thin, design: .rounded).monospacedDigit()
    /// Tile metrics.
    static let metricL = Font.system(size: 34, weight: .light, design: .rounded).monospacedDigit()
    /// Inline stats, monitor tiles.
    static let metricS = Font.system(size: 22, weight: .regular, design: .rounded).monospacedDigit()
    /// Unit next to a metric ("GB").
    static let unit = Font.system(size: 13, weight: .medium)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// Section headers / eyebrows: use with `.textCase(.uppercase)` and `.tracking(0.8)`.
    static let overline = Font.system(size: 10, weight: .semibold)
    static let button = Font.system(size: 13, weight: .semibold)
    static let orbLabel = Font.system(size: 15, weight: .semibold)
    static let orbDetail = Font.system(size: 11, weight: .medium).monospacedDigit()
    /// Captions with numbers (sizes in rows).
    static let captionDigits = Font.system(size: 11).monospacedDigit()
}

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48

    // B.5 additions (4 pt grid: 2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64 · 80).
    static let l2: CGFloat = 20
    static let xxl2: CGFloat = 40
    static let huge: CGFloat = 64
    static let giant: CGFloat = 80
    /// Horizontal padding of module content.
    static let contentInset: CGFloat = 40
    /// Content starts this far below the window top (traffic lights).
    static let topInset: CGFloat = 28
    /// Clearance between the orb disc and the window's bottom edge.
    static let orbBottom: CGFloat = 28
    /// Maximum readable content width.
    static let readableWidth: CGFloat = 1000
}

enum Radius {
    static let small: CGFloat = 6
    static let control: CGFloat = 8
    static let card: CGFloat = 18
    static let panel: CGFloat = 18
    static let sheet: CGFloat = 26

    // B.5 additions.
    /// Rows, list containers, monitor tiles.
    static let row: CGFloat = 12
    /// Large list panes.
    static let container: CGFloat = 16
    /// Rounded-square category badges.
    static let badge: CGFloat = 9
    /// Checkbox corner.
    static let checkbox: CGFloat = 5
}

enum Motion {
    static let quick = Animation.easeOut(duration: 0.15)
    static let standard = Animation.snappy(duration: 0.25)
    static let canvas = Animation.smooth(duration: 0.7)
    static let slow = Animation.easeInOut(duration: 1.2)

    // B.7 additions.
    /// Press-down scale.
    static let instant = Animation.easeOut(duration: 0.08)
    /// Hero transform, orb state morph, tile reveal.
    static let emphasized = Animation.spring(duration: 0.45, bounce: 0.18)
    /// Canvas re-tint between modules.
    static let scene = Animation.smooth(duration: 0.7)
    /// Completion burst / count-up envelope.
    static let celebrate = Animation.easeOut(duration: 1.2)
    /// Metric count-up.
    static let countUp = Animation.easeOut(duration: 0.9)
    /// Progress ring interpolation to each new value.
    static let progress = Animation.linear(duration: 0.3)
    /// Cross-fade used for every transform under Reduce Motion.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// `animation`, or a 0.2 s cross-fade when Reduce Motion is on (B.7 mapping).
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }
}

/// Ambient-motion policy: the system Reduce Motion setting *or* the app's own
/// "Reduce ambient motion" preference stops canvas drift, particles and breathing.
enum PrismAmbient {
    static func isReduced(_ accessibilityReduceMotion: Bool) -> Bool {
        accessibilityReduceMotion || SettingsStore.shared.settings.reduceAmbientMotion
    }
}

/// Transitions between module phases (B.13.10).
extension AnyTransition {
    /// Fade + 8 pt rise; a plain fade under Reduce Motion.
    static func prismPhase(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }
}
