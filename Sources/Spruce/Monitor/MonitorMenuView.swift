import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Menu bar popover (`MenuBarExtra`, `.window` style): a live health header, cards
/// for Storage, Memory, CPU, Network, Battery/UPS and Devices, and a footer.
///
/// CONTRACT: keep `MonitorMenuView` and `MonitorMenuLabel`.
@MainActor
struct MonitorMenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let monitor = model.monitor
        VStack(spacing: 0) {
            MonitorHeader(monitor: monitor, openApp: { openMainWindow(nil) })
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.m)
            ScrollView(.vertical, showsIndicators: false) {
                MonitorCardStack(monitor: monitor, settings: model.settings, openModule: { openMainWindow($0) })
                    .padding(.horizontal, Spacing.m)
                    .padding(.bottom, Spacing.m)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: MonitorContentHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .frame(height: scrollHeight)
            .onPreferenceChange(MonitorContentHeightKey.self) { height in
                Task { @MainActor in
                    if abs(contentHeight - height) > 0.5 { contentHeight = height }
                }
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
            MonitorFooter()
        }
        .frame(width: MonitorTheme.width)
        .background(MonitorBackdrop(status: monitor.health.isRated ? monitor.health.status : .good))
        .preferredColorScheme(.dark)
        .onAppear {
            monitor.start()
            monitor.refresh()
        }
    }

    /// The cards scroll once they would make the panel taller than the screen allows.
    private var scrollHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        let limit = max(260, min(620, screen - 200))
        return contentHeight > 0 ? min(contentHeight, limit) : limit
    }

    /// Brings the main window forward, optionally on a module.
    private func openMainWindow(_ module: ModuleID?) {
        if let module { model.open(module) }
        openWindow(id: "main")
        NSApp.activate()
    }
}

private struct MonitorContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Header

@MainActor
struct MonitorHeader: View {
    var monitor: SystemMonitor
    var openApp: () -> Void

    var body: some View {
        let health = monitor.health
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                MonitorHealthRing(health: health)
                VStack(alignment: .leading, spacing: 2) {
                    Text(health.headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(deviceLine)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                CapsuleButton(title: "Open", symbol: "macwindow", action: openApp)
                    .help("Open Spruce")
                    .accessibilityLabel("Open Spruce")
            }
            if !health.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(health.issues.prefix(3))) { issue in
                        MonitorIssueRow(issue: issue)
                    }
                }
                .padding(.leading, 2)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var deviceLine: String {
        let uptime = monitor.snapshot.uptime
        guard uptime > 0 else { return monitor.computerName }
        return "\(monitor.computerName) · up \(MonitorFormat.uptime(uptime))"
    }
}

@MainActor
struct MonitorIssueRow: View {
    var issue: MonitorIssue

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: issue.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MonitorTheme.color(for: issue.severity))
                .frame(width: 14)
            Text(issue.title)
                .font(SpruceFont.caption.weight(.semibold))
                .foregroundStyle(Ink.primary.opacity(0.9))
                .lineLimit(1)
                .layoutPriority(1)
            Text(issue.detail)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cards

@MainActor
struct MonitorCardStack: View {
    var monitor: SystemMonitor
    var settings: SettingsStore
    var openModule: (ModuleID) -> Void

    var body: some View {
        VStack(spacing: Spacing.s) {
            MonitorStorageCard(monitor: monitor, settings: settings, onCleanUp: { openModule(.cleanup) })
            MonitorMemoryCard(monitor: monitor, settings: settings)
            MonitorCPUCard(monitor: monitor)
            MonitorNetworkCard(monitor: monitor)
            if let power = monitor.power {
                MonitorPowerCard(power: power)
            }
            if !monitor.devices.isEmpty {
                MonitorDevicesCard(devices: monitor.devices)
            }
        }
    }
}

// MARK: - Footer

@MainActor
struct MonitorFooter: View {
    var body: some View {
        HStack(spacing: Spacing.m) {
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
                    .font(SpruceFont.caption.weight(.medium))
                    .foregroundStyle(Ink.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Spruce", systemImage: "power")
                    .font(SpruceFont.caption.weight(.medium))
                    .foregroundStyle(Ink.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 10)
    }
}

// MARK: - Status item

/// The status item: a light leaf glyph, plus a coloured dot while the Mac needs
/// attention (amber) or something is critical (red).
@MainActor
struct MonitorMenuLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let health = model.monitor.health
        let status = health.isRated ? health.status : .good
        Image(nsImage: MonitorStatusIcon.image(for: status))
            .accessibilityLabel("Spruce")
            .accessibilityValue(health.headline)
    }
}

/// Renders the menu bar image. Without an issue it is a template image (the
/// system tints it for light/dark menu bars); with one, the glyph is drawn in the
/// label colour with a status dot in its top-right corner.
@MainActor
enum MonitorStatusIcon {
    private static var cache: [MonitorHealthStatus: NSImage] = [:]

    static func image(for status: MonitorHealthStatus) -> NSImage {
        if let cached = cache[status] { return cached }
        let image = render(status)
        cache[status] = image
        return image
    }

    private static func render(_ status: MonitorHealthStatus) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .light)
        let glyph = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Spruce")?
            .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 16, height: 16))
        let dotColor: NSColor?
        switch status {
        case .good: dotColor = nil
        case .attention: dotColor = .systemOrange
        case .critical: dotColor = .systemRed
        }
        let glyphSize = glyph.size
        let size = NSSize(width: ceil(glyphSize.width) + 4, height: max(ceil(glyphSize.height), 16))
        let tinted = dotColor == nil ? glyph : (glyph.withSymbolConfiguration(
            configuration.applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))) ?? glyph)
        let image = NSImage(size: size, flipped: false) { rect in
            let glyphRect = NSRect(x: 0, y: (rect.height - glyphSize.height) / 2,
                                   width: glyphSize.width, height: glyphSize.height)
            tinted.draw(in: glyphRect)
            if let dotColor {
                let diameter: CGFloat = 6
                let dot = NSRect(x: rect.width - diameter, y: rect.height - diameter - 1, width: diameter, height: diameter)
                dotColor.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = dotColor == nil
        image.accessibilityDescription = "Spruce"
        return image
    }
}
