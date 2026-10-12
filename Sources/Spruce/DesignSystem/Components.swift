import AppKit
import SpruceCore
import SwiftUI

// CONTRACT: these component names and their existing initializer parameters are used
// throughout the modules. The design-system owner may restyle them and add new
// parameters *with default values*, but must not remove or rename existing ones.

// MARK: - Canvas

/// Full-bleed, module-tinted animated background.
struct LivingCanvas: View {
    var module: ModuleID
    /// 1.0 idle, >1 while scanning/celebrating, <1 on results.
    var intensity: Double = 1

    var body: some View {
        let p = module.palette
        ZStack {
            p.canvasGradient
            RadialGradient(colors: [p.glow.opacity(0.45 * intensity), .clear], center: .init(x: 0.5, y: 0.85),
                           startRadius: 10, endRadius: 520)
            RadialGradient(colors: [p.accent2.opacity(0.14 * intensity), .clear], center: .init(x: 0.85, y: 0.1),
                           startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
        .animation(Motion.canvas, value: module)
    }
}

// MARK: - Primary action

/// The large circular primary action ("Scan", "Run", "Remove"…).
struct ActionOrb: View {
    var title: String
    var subtitle: String? = nil
    var module: ModuleID
    /// When non-nil, shows a progress ring around the orb (0...1).
    var progress: Double? = nil
    var isBusy: Bool = false
    var isEnabled: Bool = true
    var diameter: CGFloat = 96
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        let p = module.palette
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(p.orbFill)
                    .overlay(Circle().strokeBorder(Ink.highlight, lineWidth: 1))
                    .shadow(color: p.glow.opacity(hovering ? 0.75 : 0.5), radius: hovering ? 28 : 20)
                if isBusy || progress != nil {
                    ProgressRing(progress: progress, module: module, lineWidth: 4)
                        .padding(-8)
                }
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .padding(8)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(hovering && isEnabled ? 1.04 : 1)
            .animation(Motion.quick, value: hovering)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(subtitle.map { "\(title), \($0)" } ?? title))
    }
}

/// Circular progress indicator. `nil` progress spins indeterminately.
struct ProgressRing: View {
    var progress: Double?
    var module: ModuleID
    var lineWidth: CGFloat = 6

    @State private var spin = false

    var body: some View {
        let p = module.palette
        ZStack {
            Circle().stroke(Ink.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.map { max(0.02, $0) } ?? 0.25)
                .stroke(AngularGradient(colors: [p.accent, p.accent2], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(progress == nil && spin ? 360 : 0))
                .animation(progress == nil ? .linear(duration: 1.2).repeatForever(autoreverses: false) : Motion.standard,
                           value: progress == nil ? (spin ? 1 : 0) : (progress ?? 0))
        }
        .onAppear { spin = true }
    }
}

// MARK: - Hero

/// Procedural hero artwork for a module ("glass lens" with the module symbol).
struct HeroLens: View {
    var module: ModuleID
    var size: CGFloat = 220
    var isAnimating: Bool = false

    @State private var pulse = false

    var body: some View {
        let p = module.palette
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [p.glow.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: size * 0.7))
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(isAnimating && pulse ? 1.08 : 1)
            Circle()
                .fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.05)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                .frame(width: size, height: size)
            Image(systemName: p.symbol)
                .font(.system(size: size * 0.36, weight: .light))
                .foregroundStyle(p.accentGradient)
                .shadow(color: p.glow.opacity(0.8), radius: 18)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

struct GlassCard<Content: View>: View {
    var padding: CGFloat = Spacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.hairline))
    }
}

// MARK: - Controls

/// Rounded-square checkbox with tri-state support.
struct SpruceCheckbox: View {
    var state: SelectionState
    var module: ModuleID
    var action: () -> Void

    init(isOn: Bool, module: ModuleID, action: @escaping () -> Void) {
        self.state = isOn ? .all : .none
        self.module = module
        self.action = action
    }

    init(state: SelectionState, module: ModuleID, action: @escaping () -> Void) {
        self.state = state
        self.module = module
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(state == .none ? Color.clear : module.palette.accent)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(state == .none ? Ink.tertiary : Color.clear, lineWidth: 1.2))
                if state != .none {
                    Image(systemName: state == .all ? "checkmark" : "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Ink.onBright)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(state == .all ? "checked" : state == .some ? "mixed" : "unchecked"))
    }
}

/// Small capsule showing a byte count.
struct SizeBadge: View {
    var bytes: Int64
    var emphasized: Bool = false

    var body: some View {
        Text(ByteFormat.string(bytes))
            .font(.system(size: 11, weight: emphasized ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(emphasized ? Ink.primary : Ink.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Ink.controlFill, in: Capsule())
    }
}

struct StatusPill: View {
    var text: String
    var status: TileStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(StatusColor.of(status)).frame(width: 7, height: 7)
            Text(text).font(SpruceFont.caption.weight(.medium)).foregroundStyle(Ink.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Ink.subtleFill, in: Capsule())
    }
}

/// Secondary capsule button used inside tiles and toolbars ("Review", "Back", …).
struct CapsuleButton: View {
    var title: String
    var symbol: String? = nil
    var prominent: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Ink.onBright : Ink.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Ink.controlFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Ink.tertiary)
            Spacer()
            if let trailing {
                Text(trailing).font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
            }
        }
    }
}

/// File/app icon for a URL, or an SF Symbol fallback.
struct ItemIcon: View {
    var url: URL?
    var symbol: String?
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: symbol ?? "doc")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Ink.secondary)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Header with back button used on review/detail screens.
struct ScreenHeader: View {
    var title: String
    var subtitle: String? = nil
    var backTitle: String? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            if let onBack {
                CapsuleButton(title: backTitle ?? "Back", symbol: "chevron.left", action: onBack)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SpruceFont.title).foregroundStyle(Ink.primary)
                if let subtitle {
                    Text(subtitle).font(SpruceFont.callout).foregroundStyle(Ink.secondary)
                }
            }
            Spacer()
        }
    }
}
