import AppKit
import SpruceCore
import SwiftUI

// Additional Prism controls (all original). Modules may use these freely; they
// follow the same tokens as the contract components in Components.swift.

// MARK: - Button styles

/// Press-down scale (0.97, `instant`) with a spring release; no scale under Reduce Motion.
struct PrismPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(configuration.isPressed ? Motion.instant : Motion.standard, value: configuration.isPressed)
    }
}

/// Visual role of a capsule button (B.8.8).
enum PrismCapsuleRole {
    /// Frost capsule with a white label.
    case secondary
    /// White capsule with a dark label (primary action inside tiles and sheets).
    case primary
    /// Danger-filled capsule for irreversible actions.
    case destructive
}

struct PrismCapsuleButtonStyle: ButtonStyle {
    var role: PrismCapsuleRole
    var large: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PrismCapsuleBody(configuration: configuration, role: role, large: large)
    }
}

private struct PrismCapsuleBody: View {
    var configuration: ButtonStyleConfiguration
    var role: PrismCapsuleRole
    var large: Bool

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(SpruceFont.button)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, large ? 20 : 14)
            .frame(minHeight: large ? 34 : 28)
            .background { background }
            .contentShape(Capsule())
            .brightness(hovering && isEnabled ? 0.04 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(pressed ? Motion.instant : Motion.quick, value: pressed)
            .animation(Motion.quick, value: hovering)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch role {
        case .secondary: return Ink.primary
        case .primary: return Ink.onBright
        case .destructive: return Color.white
        }
    }

    @ViewBuilder
    private var background: some View {
        switch role {
        case .secondary:
            Color.clear.prismGlassCapsule(highlighted: hovering && isEnabled)
        case .primary:
            Capsule().fill(Color.white)
        case .destructive:
            Capsule().fill(StatusColor.danger)
                .overlay(Capsule().strokeBorder(Color.white.opacity(reduceTransparency ? 0.4 : 0.18), lineWidth: 1))
        }
    }
}

// MARK: - Text button (tertiary, B.8.8)

/// Text-only button in the module's `accentText` (links such as "Change in Settings").
struct PrismTextButton: View {
    var title: String
    var symbol: String? = nil
    var module: ModuleID? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            }
            .font(SpruceFont.body.weight(.medium))
            .foregroundStyle(module?.palette.accentText ?? Ink.primary)
            .underline(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismPressStyle())
        .onHover { hovering = $0 }
        .prismLinkPointer()
    }
}

/// Small circular icon button used for row hover actions.
struct PrismIconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Ink.primary : Ink.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovering ? Ink.selectedFill : Ink.controlFill))
                .contentShape(Circle())
        }
        .buttonStyle(PrismPressStyle(pressedScale: 0.92))
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Badges & chips

/// 32 pt rounded-square category badge: module accent → glow gradient, white glyph.
struct PrismCategoryBadge: View {
    var symbol: String
    var module: ModuleID
    var size: CGFloat = 32
    var isDimmed: Bool = false

    var body: some View {
        let p = module.palette
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(p.badgeGradient)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.05)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 1, y: 1)
            )
            .frame(width: size, height: size)
            .saturation(isDimmed ? 0.2 : 1)
            .opacity(isDimmed ? 0.5 : 1)
            .accessibilityHidden(true)
    }
}

/// Status-tinted chip (B.8.8): colour @ 16 % fill, 1 pt rim @ 30 %, white label.
struct PrismChip: View {
    var text: String
    var color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            }
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.primary.opacity(0.92))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
        .fixedSize()
    }
}

/// "Review" / "Risky" marker for non-safe items.
struct PrismSafetyBadge: View {
    var safety: SafetyLevel

    var body: some View {
        switch safety {
        case .safe:
            EmptyView()
        case .review:
            PrismChip(text: "Review", color: StatusColor.warning, symbol: "eye")
                .help(safety.label)
                .accessibilityLabel(safety.label)
        case .risky:
            PrismChip(text: "Risky", color: StatusColor.danger, symbol: "exclamationmark.triangle.fill")
                .help(safety.label)
                .accessibilityLabel(safety.label)
        }
    }
}

/// Small stat chip for completion screens ("Cleaned · 6.2 GB").
struct PrismStatChip: View {
    var symbol: String
    var value: String
    var label: String
    var tint: Color

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(SpruceFont.bodyStrong.monospacedDigit()).foregroundStyle(Ink.primary)
                Text(label).font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .prismSurface(radius: Radius.row)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Search field (B.8.1: 200 × 28, r 8, fill.control)

struct PrismSearchField: View {
    @Binding var text: String
    var prompt: String = "Search"
    var width: CGFloat = 200

    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ink.tertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(SpruceFont.body)
                .foregroundStyle(Ink.primary)
                .focused($focused)
                .onExitCommand { text = ""; focused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ink.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 28)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(ink.controlFill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(focused ? Color.white.opacity(0.35) : ink.hairline, lineWidth: 1)
        )
        .animation(Motion.quick, value: focused)
    }
}

// MARK: - Linear progress (B.8.5)

/// 4 pt inline progress bar (Monitor, Updater). `nil` shows an indeterminate sweep
/// (a static half bar under Reduce Motion).
struct PrismLinearProgress: View {
    var value: Double?
    var module: ModuleID
    var height: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = module.palette
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                if let value {
                    Capsule()
                        .fill(LinearGradient(colors: [p.accent2, p.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                        .animation(Motion.progress, value: value)
                } else if reduceMotion {
                    Capsule().fill(p.accent.opacity(0.7)).frame(width: geo.size.width * 0.5)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let phase = (t / 1.4).truncatingRemainder(dividingBy: 1)
                        Capsule()
                            .fill(LinearGradient(colors: [p.accent.opacity(0), p.accent, p.accent.opacity(0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.35)
                            .offset(x: geo.size.width * (CGFloat(phase) * 1.35 - 0.35))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(value.map { PrismMetric.percentText($0) } ?? "In progress")
    }
}

// MARK: - Checkmark (drawn)

/// Checkmark path that can be drawn with `.trim(from:to:)`.
struct PrismCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.26))
        return path
    }
}

// MARK: - Scan checklist (B.8.5 / B.16 Checkup scanning)

/// One row of a multi-part scan checklist (e.g. Checkup's five modules).
struct PrismScanStep: Identifiable, Equatable {
    enum State: Equatable {
        case waiting
        case running
        /// Finished, with a short result ("2.4 GB", "No threats").
        case done(String)
        case skipped(String)
        case failed(String)
    }

    var id: String
    var title: String
    var symbol: String
    var state: State
    /// Tints the step's icon; nil uses the screen's module.
    var module: ModuleID?

    init(id: String, title: String, symbol: String, state: State = .waiting, module: ModuleID? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.state = state
        self.module = module
    }
}

/// Grid of scan steps: glyph · name · status (waiting → spinner → ✓ + result).
struct PrismScanChecklist: View {
    var steps: [PrismScanStep]
    var module: ModuleID

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: Spacing.m)], spacing: Spacing.s) {
            ForEach(steps) { step in
                PrismScanStepRow(step: step, module: step.module ?? module)
            }
        }
        .frame(maxWidth: 760)
    }
}

private struct PrismScanStepRow: View {
    var step: PrismScanStep
    var module: ModuleID

    var body: some View {
        let p = module.palette
        HStack(spacing: Spacing.s) {
            statusIcon(p)
                .frame(width: 18, height: 18)
            Image(systemName: step.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isWaiting ? Ink.tertiary : p.accentText)
                .frame(width: 18)
            Text(step.title)
                .font(SpruceFont.body.weight(.medium))
                .foregroundStyle(isWaiting ? Ink.secondary : Ink.primary)
                .lineLimit(1)
            Spacer(minLength: Spacing.s)
            Text(statusText)
                .font(SpruceFont.captionDigits)
                .foregroundStyle(Ink.tertiary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 8)
        .prismSurface(radius: Radius.row)
        .animation(Motion.standard, value: step.state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.title), \(statusText)")
    }

    private var isWaiting: Bool { step.state == .waiting }

    private var statusText: String {
        switch step.state {
        case .waiting: return "Waiting"
        case .running: return "Checking…"
        case .done(let result): return result
        case .skipped(let reason): return reason
        case .failed(let reason): return reason
        }
    }

    @ViewBuilder
    private func statusIcon(_ p: ModulePalette) -> some View {
        switch step.state {
        case .waiting:
            Circle().strokeBorder(Ink.disabled, lineWidth: 1.5).frame(width: 12, height: 12)
        case .running:
            ProgressRing(progress: nil, module: module, lineWidth: 2).frame(width: 14, height: 14)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(StatusColor.success)
                .symbolEffect(.bounce, value: step.state)
        case .skipped:
            Image(systemName: "minus.circle").font(.system(size: 14)).foregroundStyle(Ink.disabled)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14)).foregroundStyle(StatusColor.warning)
        }
    }
}

// MARK: - Sheet card (B.8.9)

/// Centred confirmation card: title, summary, optional content, Cancel (Esc) and a
/// primary action (Return). Present it inside `.sheet` or as an overlay.
struct PrismSheetCard<Content: View>: View {
    var title: String
    var message: String? = nil
    var primaryTitle: String
    var primaryRole: PrismCapsuleRole = .primary
    var cancelTitle: String = "Cancel"
    var isPrimaryEnabled: Bool = true
    var onCancel: () -> Void
    var onPrimary: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(title).font(SpruceFont.title).foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).font(SpruceFont.body).foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            HStack(spacing: Spacing.s) {
                Spacer()
                Button(cancelTitle, action: onCancel)
                    .buttonStyle(PrismCapsuleButtonStyle(role: .secondary, large: true))
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(PrismCapsuleButtonStyle(role: primaryRole, large: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isPrimaryEnabled)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
        .background(PrismSheetBackground())
    }
}

extension PrismSheetCard where Content == EmptyView {
    init(title: String, message: String? = nil, primaryTitle: String, primaryRole: PrismCapsuleRole = .primary,
         cancelTitle: String = "Cancel", isPrimaryEnabled: Bool = true,
         onCancel: @escaping () -> Void, onPrimary: @escaping () -> Void) {
        self.init(title: title, message: message, primaryTitle: primaryTitle, primaryRole: primaryRole,
                  cancelTitle: cancelTitle, isPrimaryEnabled: isPrimaryEnabled, onCancel: onCancel, onPrimary: onPrimary,
                  content: { EmptyView() })
    }
}

private struct PrismSheetBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(Color(white: 0.13))
            } else {
                shape.fill(.regularMaterial)
                shape.fill(Color.white.opacity(0.06))
            }
            shape.strokeBorder(Ink.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Toast (B.8.11)

/// Bottom glass capsule with a message and an optional action ("Undo").
/// The host decides placement and auto-dismissal (5 s recommended).
struct PrismToast: View {
    var message: String
    var symbol: String = "checkmark.circle.fill"
    var tint: Color = StatusColor.success
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(message).font(SpruceFont.callout.weight(.medium)).foregroundStyle(Ink.primary).lineLimit(1)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(SpruceFont.callout.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .underline()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .prismGlassCapsule()
        .accessibilityElement(children: .combine)
    }
}
