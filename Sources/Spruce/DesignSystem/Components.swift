import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// CONTRACT: these component names and their existing initializer parameters are used
// throughout the modules. The design-system owner may restyle them and add new
// parameters *with default values*, but must not remove or rename existing ones.

// MARK: - Canvas

/// Full-bleed, module-tinted animated background.
///
/// macOS 15: a drifting 3×3 MeshGradient aurora (B.3.3). macOS 14: three drifting
/// radial blooms. Both get a 3 % procedural grain. The drift pauses while the app is
/// inactive and is static under Reduce Motion (or Settings › Reduce ambient motion).
/// Effective intensity = `intensity` × the shared value set by flow screens through
/// `.prismCanvasIntensity(_:)` (scanning brightens, results calm, completion flares).
struct LivingCanvas: View {
    var module: ModuleID
    /// 1.0 idle, >1 while scanning/celebrating, <1 on results.
    var intensity: Double = 1
    /// Set false to force a static canvas (e.g. behind sheets or in previews).
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let k = max(0, intensity * PrismCanvasState.shared.intensity)
        let still = !animated || PrismAmbient.isReduced(reduceMotion)
        ZStack {
            PrismCanvasField(palette: module.palette, k: k, still: still, paused: activeState == .inactive)
                .id(module)
                .transition(.opacity)
        }
        .animation(Motion.scene, value: module)
        .animation(.easeInOut(duration: 1.0), value: k)
        .overlay {
            if !reduceTransparency && contrast != .increased {
                PrismGrainOverlay()
            }
        }
        .compositingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Primary action

/// The large circular primary action ("Scan", "Run", "Remove"…).
///
/// States (B.8.4): idle (breathing glow), busy (progress ring / spinner + shimmer),
/// ready (`isReady`: accent rim, for a selection to act on), done (`isDone`: success
/// tint + drawn check), disabled. Keyboard: focusable; Return/Space activate it when
/// focused; Esc triggers a busy orb (Stop); `isDefaultAction` makes Return trigger
/// it from anywhere in the window (only for non-destructive actions such as Scan).
struct ActionOrb: View {
    var title: String
    var subtitle: String? = nil
    var module: ModuleID
    /// When non-nil, shows a progress ring around the orb (0...1).
    var progress: Double? = nil
    var isBusy: Bool = false
    var isEnabled: Bool = true
    var diameter: CGFloat = 96
    /// Results look: accent rim and accent track around the disc.
    var isReady: Bool = false
    /// Completion look: success tint and a drawn check instead of the title.
    var isDone: Bool = false
    /// Return triggers the orb from anywhere in the window. Never use for destructive actions.
    var isDefaultAction: Bool = false
    var action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            PrismOrbFace(title: title, subtitle: subtitle, palette: module.palette, diameter: diameter,
                         phase: phase, isEnabled: isEnabled, progress: progress,
                         hovering: hovering && isEnabled, focused: focused)
        }
        .buttonStyle(PrismPressStyle(pressedScale: 0.96))
        .disabled(!isEnabled)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) { activate() }
        .onKeyPress(.space) { activate() }
        .onHover { hovering = $0 }
        .prismKeyboardShortcut(shortcut)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityValue(Text(accessibilityValueText))
    }

    private var phase: PrismOrbPhase {
        if isDone { return .done }
        if isBusy || progress != nil { return .busy }
        if !isEnabled { return .disabled }
        if isReady { return .ready }
        return .idle
    }

    private var shortcut: KeyboardShortcut? {
        guard isEnabled else { return nil }
        if isBusy { return .cancelAction }
        if isDefaultAction && !isDone { return .defaultAction }
        return nil
    }

    private func activate() -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        action()
        return .handled
    }

    private var accessibilityText: String {
        if isDone { return [title, subtitle].compactMap { $0 }.joined(separator: ", ") }
        if isBusy || progress != nil { return title }
        if let subtitle { return "\(title) \(module.title), \(subtitle)" }
        return "\(title) \(module.title)"
    }

    private var accessibilityValueText: String {
        if let progress { return PrismMetric.percentText(progress) }
        if isBusy { return "In progress" }
        if !isEnabled { return "Unavailable" }
        return ""
    }
}

/// Circular progress indicator. `nil` progress spins indeterminately.
struct ProgressRing: View {
    var progress: Double?
    var module: ModuleID
    var lineWidth: CGFloat = 6
    /// Glowing dot at the head of a determinate arc.
    var showsHead: Bool = true

    var body: some View {
        let p = module.palette
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            if let progress {
                PrismProgressArc(fraction: progress, palette: p, lineWidth: lineWidth, showsHead: showsHead)
            } else {
                PrismSpinnerArc(palette: p, lineWidth: lineWidth)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(progress.map { PrismMetric.percentText($0) } ?? "In progress")
    }
}

// MARK: - Hero

/// Procedural hero artwork for a module ("glass lens" with the module symbol).
///
/// A 7-layer lens (bloom, body, frosted core, glyph, specular, rim, orbit) plus a
/// distinctive per-module motif (Cleanup bubbles, Protection facets, Performance
/// gauge arcs, Applications tiles, Clutter cards, Space Map orbiting dots, Cloud
/// Storage cloud layers, Toolbox gear ring, Activity bars, Checkup sparkle burst).
/// `isAnimating` adds orbit rings, motif motion and a breathing scale; hovering tilts
/// it up to 6°. Reduce Motion freezes everything except the static composition.
/// The view occupies `size × 1.4` square.
struct HeroLens: View {
    var module: ModuleID
    var size: CGFloat = 220
    var isAnimating: Bool = false
    var mood: PrismLensMood = .standard
    /// Badge symbol shown on the rim (defaults to the mood's badge).
    var badge: String? = nil
    /// Overrides the inner SF Symbol (defaults to the module symbol).
    var glyph: String? = nil
    var parallax: Bool = true

    @State private var clockStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let p = module.palette
        let reduced = PrismAmbient.isReduced(reduceMotion)
        let inactive = activeState == .inactive
        let animate = isAnimating && !reduced && !inactive
        let ink = PrismInk(contrast)
        let side = size * 1.4
        ZStack {
            PrismLensBloom(color: p.glow, size: size,
                           opacity: min(1, 0.35 * mood.glow * (isAnimating ? 1.25 : 1)) * ink.glowScale,
                           breathing: !reduced && !inactive)
            PrismLensMotifLayer(module: module, layer: .back, size: size, animating: animate,
                                scanning: isAnimating, start: clockStart)
            PrismLensBody(palette: p, size: size, reduceTransparency: reduceTransparency)
            PrismLensMotifLayer(module: module, layer: .inside, size: size, animating: animate,
                                scanning: false, start: clockStart)
                .mask { Circle().frame(width: size * 0.7, height: size * 0.7) }
            glyphView(p, ink: ink)
            PrismLensSpecular(palette: p, size: size, reduceTransparency: reduceTransparency)
            PrismLensMotifLayer(module: module, layer: .front, size: size, animating: animate,
                                scanning: isAnimating, start: clockStart)
            if let symbol = badge ?? mood.defaultBadge {
                PrismLensBadge(symbol: symbol, color: mood.badgeColor(p), size: size)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: side, height: side)
        .saturation(mood == .limited ? 0.6 : 1)
        .modifier(PrismBreathing(isActive: animate))
        .prismParallax(enabled: parallax)
        .frame(width: side, height: side)
        .onChange(of: isAnimating) { _, nowAnimating in
            if nowAnimating { clockStart = Date() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(module.title) illustration"))
        .accessibilityAddTraits(.isImage)
    }

    private func glyphView(_ p: ModulePalette, ink: PrismInk) -> some View {
        Image(systemName: glyph ?? p.symbol)
            .font(.system(size: size * 0.36, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(p.glyphGradient)
            .shadow(color: p.glow.opacity(0.5 * ink.glowScale), radius: 10)
    }
}

// MARK: - Surfaces

/// Frosted glass surface: material + white 7 % + hairline rim + top highlight
/// (opaque under Reduce Transparency, stronger rims under Increase Contrast).
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Spacing.l
    var radius: CGFloat = Radius.card
    /// Optional tint wash (e.g. a module accent or status colour).
    var tint: Color? = nil
    /// Brighter surface (hover).
    var isHighlighted: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .prismSurface(radius: radius, tint: tint, highlighted: isHighlighted)
    }
}

// MARK: - Controls

/// Rounded-square checkbox with tri-state support.
struct SpruceCheckbox: View {
    var state: SelectionState
    var module: ModuleID
    /// VoiceOver label (e.g. the item's name).
    var label: String?
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isOn: Bool, module: ModuleID, label: String? = nil, action: @escaping () -> Void) {
        self.state = isOn ? .all : .none
        self.module = module
        self.label = label
        self.action = action
    }

    init(state: SelectionState, module: ModuleID, label: String? = nil, action: @escaping () -> Void) {
        self.state = state
        self.module = module
        self.label = label
        self.action = action
    }

    var body: some View {
        let ink = PrismInk(contrast)
        let accent = module.palette.accent
        let isOn = state != SelectionState.none
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.checkbox, style: .continuous)
                    .fill(isOn ? accent : (hovering ? ink.subtleFill : Color.clear))
                RoundedRectangle(cornerRadius: Radius.checkbox, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : (hovering ? Color.white.opacity(0.72) : ink.checkboxStroke), lineWidth: 1.5)
                PrismCheckmarkShape()
                    .trim(from: 0, to: state == SelectionState.all ? 1 : 0)
                    .stroke(Ink.onBright, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(2)
                Capsule()
                    .fill(Ink.onBright)
                    .frame(width: 8, height: 2)
                    .scaleEffect(x: state == SelectionState.some ? 1 : 0.2)
                    .opacity(state == SelectionState.some ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            // 28 pt hit area without changing the 16 pt layout.
            .padding(6)
            .contentShape(Rectangle())
            .padding(-6)
        }
        .buttonStyle(PrismPressStyle(pressedScale: 0.9))
        .opacity(isEnabled ? 1 : 0.4)
        .animation(reduceMotion ? nil : Motion.quick, value: state)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(label ?? "Select"))
        .accessibilityValue(Text(state == SelectionState.all ? "checked" : state == SelectionState.some ? "mixed" : "unchecked"))
    }
}

/// Small capsule showing a byte count. Sizes ≥ 1 GB use the module's `accentText`
/// when a module is given.
struct SizeBadge: View {
    var bytes: Int64
    var emphasized: Bool = false
    var module: ModuleID? = nil

    var body: some View {
        Text(ByteFormat.string(bytes))
            .font(.system(size: 11, weight: emphasized ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(textColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Ink.controlFill))
            .fixedSize()
    }

    private var textColor: Color {
        if let module, bytes >= 1_000_000_000 { return module.palette.accentText }
        return emphasized ? Ink.primary : Ink.secondary
    }
}

/// Status chip: status colour @ 16 % fill, 1 pt rim @ 30 %, dot (or symbol) + label.
struct StatusPill: View {
    var text: String
    var status: TileStatus
    var symbol: String? = nil

    var body: some View {
        let color = StatusColor.of(status)
        let muted = status == .unavailable
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text)
                .font(SpruceFont.caption.weight(.semibold))
                .foregroundStyle(muted ? Ink.secondary : Ink.primary.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(muted ? Ink.subtleFill : color.opacity(0.16)))
        .overlay(Capsule().strokeBorder(muted ? Ink.hairline : color.opacity(0.30), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Secondary capsule button used inside tiles and toolbars ("Review", "Back", …).
/// `prominent` = white primary capsule; `destructive` = danger capsule.
struct CapsuleButton: View {
    var title: String
    var symbol: String? = nil
    var prominent: Bool = false
    var destructive: Bool = false
    /// 34 pt tall instead of 28.
    var large: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(title)
            }
        }
        .buttonStyle(PrismCapsuleButtonStyle(role: destructive ? .destructive : (prominent ? .primary : .secondary), large: large))
    }
}

/// Overline section header ("MODULES", "COULDN'T COMPLETE").
struct SectionHeader: View {
    var title: String
    var trailing: String? = nil
    var symbol: String? = nil

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.tertiary)
            }
            Text(title.uppercased())
                .font(SpruceFont.overline)
                .tracking(0.8)
                .foregroundStyle(ink.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing).font(SpruceFont.captionDigits).foregroundStyle(ink.tertiary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// File/app icon for a URL, or an SF Symbol fallback in a soft rounded square.
struct ItemIcon: View {
    var url: URL?
    var symbol: String?
    var size: CGFloat = 22
    /// Tints the symbol fallback with the module's accent.
    var module: ModuleID? = nil

    var body: some View {
        Group {
            if let url, let image = PrismIconCache.icon(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: symbol ?? "doc")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(module?.palette.accentText ?? Ink.secondary)
                    .padding(size * 0.18)
                    .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Ink.controlFill))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Caches Finder icons by path (icon lookup is comparatively slow in long lists).
@MainActor
enum PrismIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 800
        return cache
    }()

    static func icon(for url: URL) -> NSImage? {
        let path = url.path
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

/// Header with back button used on review/detail screens.
struct ScreenHeader: View {
    var title: String
    var subtitle: String? = nil
    var backTitle: String? = nil
    var onBack: (() -> Void)? = nil
    /// Shows a small hero lens of the module next to the title.
    var module: ModuleID? = nil
    /// Optional trailing accessory (search field, menu…).
    var trailing: AnyView? = nil

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(alignment: .center, spacing: Spacing.m) {
            if let onBack {
                PrismBackButton(title: backTitle ?? "Back", action: onBack)
                    .padding(.trailing, Spacing.s)
            }
            if let module {
                HeroLens(module: module, size: 40, parallax: false)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SpruceFont.title)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(SpruceFont.callout.monospacedDigit())
                        .foregroundStyle(ink.secondary)
                        .lineLimit(2)
                        .contentTransition(.numericText())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.m)
            if let trailing {
                trailing
            }
        }
        .frame(minHeight: 44)
    }
}

/// Plain "‹ Back" text button (B.8.1 top bar): secondary → primary on hover. ⌘[.
struct PrismBackButton: View {
    var title: String
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(hovering ? Ink.primary : ink.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(hovering ? ink.subtleFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismPressStyle())
        .keyboardShortcut("[", modifiers: .command)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help("\(title) (⌘[)")
        .prismLinkPointer()
    }
}
