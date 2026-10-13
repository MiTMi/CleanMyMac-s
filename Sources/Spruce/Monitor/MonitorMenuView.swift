import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Menu bar popover (`MenuBarExtra`, `.window` style): a Mac Health header (the app's own
/// score, with the live issues as detail lines), cards in Mac Health's monitor order —
/// Protection, Storage, Memory, Battery/UPS, CPU, Network, Devices — one suggestion card,
/// quick actions and a footer.
///
/// CONTRACT: keep `MonitorMenuView` and `MonitorMenuLabel`.
@MainActor
struct MonitorMenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let monitor = model.monitor
        let advice = ActivityAdviceStore.shared
        let report = MonitorHealthSource.report(model)
        let status = MonitorTheme.status(for: report)
        let suggestion = MonitorSuggestion.pick(report: report, advice: advice.state,
                                                weeklyReminder: model.settings.settings.weeklyCleanupReminder)
        VStack(spacing: 0) {
            MonitorHeader(report: report, status: status, monitor: monitor, openApp: { openMainWindow(nil) })
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.m)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.s) {
                    MonitorCardStack(monitor: monitor, settings: model.settings,
                                     protection: protectionSummary(report),
                                     onProtection: { handle($0) },
                                     openModule: { openMainWindow($0) })
                    if let suggestion {
                        MonitorSuggestionCard(suggestion: suggestion,
                                              onAction: { perform(suggestion.action) },
                                              onSnooze: { advice.snooze(suggestion) },
                                              onDismiss: { advice.dismiss(suggestion) })
                            .transition(.opacity)
                    }
                }
                .animation(Motion.standard, value: suggestion?.id)
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
            MonitorQuickActions(checkupLine: Self.checkupLine(report),
                                onCheckup: { openMainWindow(.checkup, tool: "checkup.scan") },
                                onTools: { openMainWindow(.toolbox) })
            Rectangle().fill(Ink.hairline).frame(height: 1)
            MonitorFooter()
        }
        .frame(width: MonitorTheme.width)
        .background(MonitorBackdrop(status: status))
        .preferredColorScheme(.dark)
        .onAppear {
            model.refreshPermissions()
            monitor.start()
            monitor.refresh()
        }
    }

    /// The cards scroll once they would make the panel taller than the screen allows.
    private var scrollHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        let limit = max(260, min(620, screen - 250))
        return contentHeight > 0 ? min(contentHeight, limit) : limit
    }

    private func protectionSummary(_ report: ActivityHealthReport) -> MonitorProtectionSummary {
        MonitorProtectionSummary(realtimeEnabled: model.settings.settings.realtimeProtection,
                                 hasFullDiskAccess: model.hasFullDiskAccess,
                                 unresolvedThreats: report.unresolvedThreats,
                                 lastScan: model.history.history.lastDate(of: .malwareScan))
    }

    private func handle(_ action: MonitorProtectionSummary.Action) {
        switch action {
        case .scan, .review:
            openMainWindow(.protection, tool: "protection.malware")
        case .turnOn:
            // Protection follows this setting (ProtectionEngine starts its watcher).
            model.settings.settings.realtimeProtection = true
        case .allowAccess:
            Permissions.openFullDiskAccessSettings()
        }
    }

    private func perform(_ action: ActivityRecommendationAction) {
        switch action {
        case .open(let module, let tool):
            openMainWindow(module, tool: tool)
        case .grantFullDiskAccess:
            Permissions.openFullDiskAccessSettings()
        case .none:
            break
        }
    }

    /// "Checked 3 d ago", "Checked today", "No Checkup yet".
    static func checkupLine(_ report: ActivityHealthReport) -> String {
        guard let days = report.daysSinceCheckup else { return "No Checkup yet" }
        switch days {
        case ..<1: return "Checked today"
        case 1: return "Checked yesterday"
        default: return "Checked \(days) d ago"
        }
    }

    /// Brings the main window forward, optionally on a module and one of its tools.
    private func openMainWindow(_ module: ModuleID?, tool: String? = nil) {
        if let module { model.open(module, tool: tool) }
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// The one Mac Health score (`AppModel.healthReport`, the same the sidebar pill and
/// Activity show). Reading `clockHour` re-evaluates it hourly, so day counts (since the
/// last Checkup or scan) stay current even when nothing else changes.
@MainActor
enum MonitorHealthSource {
    static func report(_ model: AppModel) -> ActivityHealthReport {
        _ = model.monitor.clockHour
        return model.healthReport
    }
}

private struct MonitorContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Header

/// Ring and band from Mac Health, the device line, then the live system issues (disk,
/// memory, heat…) as detail lines.
@MainActor
struct MonitorHeader: View {
    var report: ActivityHealthReport
    var status: MonitorHealthStatus
    var monitor: SystemMonitor
    var openApp: () -> Void

    var body: some View {
        let issues = monitor.health.issues
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                MonitorHealthRing(score: report.score, isRated: report.isRated, status: status,
                                  label: report.level.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.isRated ? "Health \u{00B7} \(report.level.title)" : "Checking your Mac\u{2026}")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Text(deviceLine)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(report.isRated ? "Mac Health \(report.score) \u{00B7} \(report.level.blurb)" : "")
                Spacer(minLength: 4)
                CapsuleButton(title: "Open", symbol: "macwindow", action: openApp)
                    .help("Open Spruce")
                    .accessibilityLabel("Open Spruce")
            }
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(issues.prefix(3))) { issue in
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
        return "\(monitor.computerName) \u{00B7} up \(MonitorFormat.uptime(uptime))"
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

/// Mac Health's monitors in their usual order: Protection, Storage, Memory, Battery (or
/// UPS; absent on a Mac mini without one), CPU, Network, Devices (accessories and drives).
@MainActor
struct MonitorCardStack: View {
    var monitor: SystemMonitor
    var settings: SettingsStore
    var protection: MonitorProtectionSummary
    var onProtection: (MonitorProtectionSummary.Action) -> Void
    var openModule: (ModuleID) -> Void

    var body: some View {
        VStack(spacing: Spacing.s) {
            MonitorProtectionCard(summary: protection, onAction: onProtection)
            MonitorStorageCard(monitor: monitor, settings: settings, onCleanUp: { openModule(.cleanup) })
            MonitorMemoryCard(monitor: monitor, settings: settings)
            if let power = monitor.power {
                MonitorPowerCard(power: power)
            }
            MonitorCPUCard(monitor: monitor)
            MonitorNetworkCard(monitor: monitor)
            if !monitor.devices.isEmpty || !monitor.volumes.isEmpty {
                MonitorDevicesCard(monitor: monitor)
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
                Label("Settings\u{2026}", systemImage: "gearshape")
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

/// The status item: a light leaf glyph, plus a coloured dot while Mac Health is Fair or
/// Needs Attention (amber) or something is critical (red) — the sidebar pill's colours.
@MainActor
struct MonitorMenuLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The same Mac Health score as the header, the sidebar pill and Activity.
        let report = MonitorHealthSource.report(model)
        Image(nsImage: MonitorStatusIcon.image(for: MonitorTheme.status(for: report)))
            .accessibilityLabel("Spruce")
            .accessibilityValue(report.isRated ? "Mac Health \(report.level.title), \(report.score)" : "Checking your Mac")
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
