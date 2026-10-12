import SpruceCore
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
    /// Module hero titles.
    static func display(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let mono = Font.system(size: 11, design: .monospaced)
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
}

enum Radius {
    static let small: CGFloat = 6
    static let control: CGFloat = 8
    static let card: CGFloat = 14
    static let panel: CGFloat = 18
    static let sheet: CGFloat = 22
}

enum Motion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let canvas = Animation.easeInOut(duration: 0.7)
    static let slow = Animation.easeInOut(duration: 1.2)
}
