import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// Building blocks for the menu bar monitor (09-design §B.9): graphite canvas,
// compact frosted cards, sparklines, gauges and process rows.

// MARK: - Theme

enum MonitorTheme {
    static let width: CGFloat = 360
    static let graphiteTop = Color(hex: 0x121318)
    static let graphiteBottom = Color(hex: 0x1E2130)

    // Each card borrows the accent of the module it relates to.
    static let storageTint = ModuleID.cleanup.palette.accent
    static let memoryTint = ModuleID.performance.palette.accent
    static let wiredTint = ModuleID.protection.palette.accent
    static let compressedTint = ModuleID.spaceMap.palette.accent
    static let cpuTint = ModuleID.checkup.palette.accent
    static let networkTint = ModuleID.cloudStorage.palette.accent
    static let networkUpTint = ModuleID.spaceMap.palette.accent2
    static let powerTint = ModuleID.activity.palette.accent
    static let devicesTint = ModuleID.applications.palette.accentText
    static let protectionTint = ModuleID.protection.palette.accentText

    static func color(for status: MonitorHealthStatus) -> Color {
        switch status {
        case .good: return StatusColor.success
        case .attention: return StatusColor.warning
        case .critical: return StatusColor.danger
        }
    }

    /// Status dot / ring colour for the app's Mac Health report, matching the sidebar pill
    /// (Excellent and Good are fine, Fair and Needs Attention amber, Critical red). A
    /// critical suggestion (a threat, a failing or full disk…) turns it red whatever the score.
    static func status(for report: ActivityHealthReport) -> MonitorHealthStatus {
        guard report.isRated else { return .good }
        if report.recommendations.contains(where: { $0.severity == .critical }) { return .critical }
        switch report.level {
        case .excellent, .good: return .good
        case .fair, .requiresAttention: return .attention
        case .critical: return .critical
        }
    }

    static func color(for pressure: SystemSnapshot.MemoryPressure) -> Color {
        switch pressure {
        case .normal: return StatusColor.success
        case .warning: return StatusColor.warning
        case .critical: return StatusColor.danger
        }
    }
}

/// Graphite gradient with one static bloom in the health colour (no animation, to
/// keep the monitor's own CPU use negligible).
@MainActor
struct MonitorBackdrop: View {
    var status: MonitorHealthStatus

    var body: some View {
        ZStack {
            LinearGradient(colors: [MonitorTheme.graphiteTop, MonitorTheme.graphiteBottom],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [MonitorTheme.color(for: status).opacity(0.25), .clear],
                           center: .top, startRadius: 0, endRadius: 240)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card

/// Compact frosted card: overline title with a tinted symbol, an optional trailing
/// accessory, then the content.
@MainActor
struct MonitorCard<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let accessory: Accessory
    let content: Content

    init(title: String, symbol: String, tint: Color,
         @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(SpruceFont.overline)
                    .tracking(0.8)
                    .foregroundStyle(Ink.tertiary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                accessory
            }
            content
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .prismSurface(radius: Radius.row)
        .accessibilityElement(children: .contain)
    }
}

extension MonitorCard where Accessory == EmptyView {
    init(title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

/// Bell button that switches one alert type on or off.
@MainActor
struct MonitorAlertToggle: View {
    var isOn: Bool
    /// Plural noun, e.g. "Low-disk alerts".
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "bell.fill" : "bell.slash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn ? Ink.secondary : Ink.disabled)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PrismPressStyle(pressedScale: 0.9))
        .help(isOn ? "\(label) are on — click to turn them off" : "\(label) are off — click to turn them on")
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Notes

/// A short-lived result line under a card action ("Freed 1.2 GB of memory").
struct MonitorNote: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var isError: Bool

    static func success(_ text: String) -> MonitorNote { MonitorNote(text: text, isError: false) }
    static func failure(_ text: String) -> MonitorNote { MonitorNote(text: text, isError: true) }
}

@MainActor
struct MonitorNoteView: View {
    var note: MonitorNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: note.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(note.isError ? StatusColor.warning : StatusColor.success)
            Text(note.text)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

/// Muted single line shown before the first reading arrives.
@MainActor
struct MonitorPlaceholderLine: View {
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text).font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
        }
    }
}

// MARK: - Bars & gauges

struct MonitorBarSegment: Identifiable {
    var id: String
    var fraction: Double
    var color: Color
}

/// Rounded track with one or more coloured segments laid end to end.
@MainActor
struct MonitorBar: View {
    var segments: [MonitorBarSegment]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: geo.size.width * CGFloat(min(max(segment.fraction, 0), 1)))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .animation(Motion.standard, value: segments.map(\.fraction))
        .accessibilityHidden(true)
    }
}

/// Upper half circle, drawn from the left end over the top to the right end so it
/// can be trimmed like a gauge.
struct MonitorArcShape: Shape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = max(0, min(rect.width / 2, rect.height) - inset)
        let center = CGPoint(x: rect.midX, y: rect.maxY - inset)
        let steps = 48
        for step in 0...steps {
            let angle = Double.pi + Double.pi * Double(step) / Double(steps)
            let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                                y: center.y + radius * CGFloat(sin(angle)))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Semicircular memory gauge: arc = used fraction, coloured by pressure.
@MainActor
struct MonitorPressureGauge: View {
    var fraction: Double
    var color: Color

    var body: some View {
        let value = CGFloat(min(max(fraction, 0), 1))
        ZStack(alignment: .bottom) {
            MonitorArcShape(inset: 3)
                .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            MonitorArcShape(inset: 3)
                .trim(from: 0, to: value)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Text(MonitorFormat.percent(fraction))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
        }
        .frame(width: 66, height: 38)
        .animation(Motion.standard, value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Memory used")
        .accessibilityValue(MonitorFormat.percent(fraction))
    }
}

/// Mac Health score ring with a sweep on open (B.9: 0.9 s).
@MainActor
struct MonitorHealthRing: View {
    var score: Int
    var isRated: Bool
    var status: MonitorHealthStatus
    /// Band name for VoiceOver ("Good").
    var label: String

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = MonitorTheme.color(for: status)
        let target = isRated ? CGFloat(min(max(score, 0), 100)) / 100 : 0
        ZStack {
            Circle()
                .inset(by: 2.5)
                .stroke(Color.white.opacity(0.10), lineWidth: 5)
            Circle()
                .inset(by: 2.5)
                .trim(from: 0, to: appeared ? target : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 4)
            Text(isRated ? "\(score)" : "–")
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
        }
        .frame(width: 46, height: 46)
        .animation(reduceMotion ? nil : Motion.standard, value: target)
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.countUp) { appeared = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Mac Health score")
        .accessibilityValue(isRated ? "\(score) of 100, \(label)" : "Not rated yet")
    }
}

// MARK: - Sparkline

/// Right-aligned line chart of the last `capacity` samples. Points flagged in
/// `highlights` are re-stroked in `highlightColor` (CPU spikes). Redraws without
/// animation so new samples just shift in.
@MainActor
struct MonitorSparkline: View {
    var values: [Double]
    /// The value drawn at the top edge.
    var ceiling: Double
    var color: Color
    var filled: Bool = true
    var lineWidth: CGFloat = 1.5
    var highlights: [Bool] = []
    var highlightColor: Color = StatusColor.danger
    var capacity: Int = MonitorSampling.historyLength

    var body: some View {
        // Copy everything the renderer needs so the closure captures no view state.
        let values = self.values
        let ceiling = self.ceiling
        let color = self.color
        let filled = self.filled
        let lineWidth = self.lineWidth
        let highlights = self.highlights
        let highlightColor = self.highlightColor
        let capacity = self.capacity
        return Canvas { context, size in
            guard values.count > 1, size.width > 0, size.height > 0 else { return }
            let points = MonitorSparkline.points(values: values, ceiling: ceiling, capacity: capacity,
                                                 size: size, inset: lineWidth)
            var line = Path()
            line.addLines(points)
            if filled, let first = points.first, let last = points.last {
                var area = line
                area.addLine(to: CGPoint(x: last.x, y: size.height))
                area.addLine(to: CGPoint(x: first.x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.34), color.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            }
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(line, with: .color(color), style: style)
            if highlights.count == points.count {
                var spikes = Path()
                for index in 1..<points.count where highlights[index] && highlights[index - 1] {
                    spikes.move(to: points[index - 1])
                    spikes.addLine(to: points[index])
                }
                context.stroke(spikes, with: .color(highlightColor), style: style)
            }
        }
        .accessibilityHidden(true)
    }

    nonisolated static func points(values: [Double], ceiling: Double, capacity: Int, size: CGSize,
                                   inset: CGFloat) -> [CGPoint] {
        let top = ceiling > 0 ? ceiling : 1
        let step = size.width / CGFloat(max(capacity - 1, 1))
        let usable = max(1, size.height - inset * 2)
        let count = values.count
        return values.enumerated().map { index, value in
            let fraction = CGFloat(min(max(value / top, 0), 1))
            return CGPoint(x: size.width - CGFloat(count - 1 - index) * step,
                           y: size.height - inset - fraction * usable)
        }
    }
}

/// One thin bar per logical CPU.
@MainActor
struct MonitorCoreStrip: View {
    var loads: [Double]
    var color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(loads.enumerated()), id: \.offset) { item in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color.opacity(0.85))
                        .frame(height: max(1.5, 14 * CGFloat(min(max(item.element, 0), 1))))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Process rows

/// App icons by pid (main thread only; small, self-pruning cache).
@MainActor
enum MonitorAppIconCache {
    private static var icons: [Int32: NSImage] = [:]
    private static var misses: Set<Int32> = []

    static func icon(for pid: Int32) -> NSImage? {
        if let icon = icons[pid] { return icon }
        if misses.contains(pid) { return nil }
        if icons.count + misses.count > 400 {
            icons.removeAll()
            misses.removeAll()
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.bundleURL != nil, let icon = app.icon {
            icons[pid] = icon
            return icon
        }
        misses.insert(pid)
        return nil
    }
}

@MainActor
struct MonitorAppIcon: View {
    var pid: Int32

    var body: some View {
        if let icon = MonitorAppIconCache.icon(for: pid) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.subtleFill))
        }
    }
}

/// "Safari ③ ……… 2.1 GB"
@MainActor
struct MonitorProcessRow: View {
    var process: MonitorProcessUsage
    var value: String
    var valueColor: Color = Ink.secondary

    var body: some View {
        HStack(spacing: Spacing.s) {
            MonitorAppIcon(pid: process.pid)
            Text(process.name)
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.primary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            if process.processCount > 1 {
                Text("\(process.processCount)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Ink.subtleFill))
                    .help("\(process.processCount) processes")
            }
            Spacer(minLength: 6)
            Text(value)
                .font(SpruceFont.captionDigits.weight(.medium))
                .foregroundStyle(valueColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(process.name), \(value)")
    }
}

/// Small coloured dot + label + value, used in legends.
@MainActor
struct MonitorLegendItem: View {
    var color: Color
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(Ink.tertiary)
            Text(value).foregroundStyle(Ink.secondary)
        }
        .font(SpruceFont.captionDigits)
        .lineLimit(1)
    }
}
