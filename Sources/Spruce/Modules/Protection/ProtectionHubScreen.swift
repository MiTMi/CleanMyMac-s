import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Protection landing: the three tools as cards, plus real-time protection and the state
/// of macOS's own protection layers.
struct ProtectionHubScreen: View {
    @Bindable var screen: ProtectionScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                HStack(alignment: .top, spacing: Spacing.l) {
                    ForEach(ProtectionTool.allCases) { tool in
                        ProtectionToolCard(screen: screen, tool: tool, flow: screen.flow(for: tool))
                    }
                }
                HStack(alignment: .top, spacing: Spacing.l) {
                    ProtectionRealtimeCard(screen: screen)
                    ProtectionAppleStatusCard(screen: screen)
                }
            }
            .frame(maxWidth: Spacing.readableWidth)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.topInset + Spacing.l)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            HeroLens(module: .protection, size: 84, mood: headerMood, parallax: false)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Protection")
                    .font(SpruceFont.display(34))
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(ModuleID.protection.tagline)
                    .font(SpruceFont.body)
                    .foregroundStyle(PrismInk(contrast).secondary)
                Text(statusLine)
                    .font(SpruceFont.callout.weight(.medium))
                    .foregroundStyle(statusColor)
                    .padding(.top, Spacing.xxs)
            }
            Spacer(minLength: 0)
        }
    }

    private var threatCount: Int {
        screen.malware.phase == .results ? screen.malware.groups.allItems.count : 0
    }

    private var headerMood: PrismLensMood {
        threatCount > 0 ? .warning : .standard
    }

    private var statusLine: String {
        if threatCount > 0 {
            return "\(CountFormat.items(threatCount, singular: "threat")) waiting for you in Malware Removal."
        }
        if let report = screen.malwareReport {
            let result = report.threatCount == 0 ? "no threats found" : "\(CountFormat.items(report.threatCount, singular: "threat")) found"
            return "Last malware scan \(DurationFormat.relative(report.date)): \(result)."
        }
        return "No malware scan yet. A regular check keeps your Mac in shape."
    }

    private var statusColor: Color {
        if threatCount > 0 { return StatusColor.danger }
        if screen.malwareReport?.threatCount == 0 { return StatusColor.success }
        return PrismInk(contrast).tertiary
    }
}

// MARK: - Tool card

/// One tool on the hub: what it does, where it stands, and a button to open it.
struct ProtectionToolCard: View {
    @Bindable var screen: ProtectionScreenModel
    var tool: ProtectionTool
    @Bindable var flow: ScanFlowModel

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button {
            screen.open(tool)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top) {
                    PrismCategoryBadge(symbol: tool.symbol, module: .protection, size: 44)
                    Spacer(minLength: Spacing.s)
                    StatusPill(text: status.text, status: status.tile, symbol: status.symbol)
                }
                Text(tool.title)
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                Text(tool.tagline)
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .font(SpruceFont.callout.weight(.semibold))
                .foregroundStyle(ModuleID.protection.palette.accentText)
            }
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .padding(Spacing.l)
            .prismSurface(radius: Radius.card, highlighted: hovering)
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PrismPressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityLabel("\(tool.title). \(status.text)")
        .accessibilityHint(tool.tagline)
    }

    private var actionTitle: String {
        switch flow.phase {
        case .results: return "Review"
        case .scanning: return "Scanning…"
        case .running: return "Working…"
        default: return "Open"
        }
    }

    private var status: ProtectionCardStatus {
        switch flow.phase {
        case .scanning:
            return ProtectionCardStatus(text: "Scanning", tile: .info, symbol: "magnifyingglass")
        case .running:
            return ProtectionCardStatus(text: "Working", tile: .info, symbol: "hourglass")
        case .failed:
            return ProtectionCardStatus(text: "Couldn't finish", tile: .attention, symbol: "exclamationmark.triangle.fill")
        case .results:
            return resultsStatus
        case .idle, .done:
            return idleStatus
        }
    }

    private var resultsStatus: ProtectionCardStatus {
        let items = flow.groups.allItems
        switch tool {
        case .malware:
            if items.isEmpty {
                return ProtectionCardStatus(text: "No threats", tile: .clear, symbol: "checkmark.shield.fill")
            }
            let known = items.contains { $0.safety == .safe }
            return ProtectionCardStatus(text: CountFormat.items(items.count, singular: "threat"),
                                        tile: known ? .critical : .attention, symbol: "exclamationmark.shield.fill")
        case .privacy:
            if items.isEmpty {
                return ProtectionCardStatus(text: "Nothing found", tile: .clear, symbol: "checkmark")
            }
            return ProtectionCardStatus(text: ByteFormat.string(flow.totalSize), tile: .attention)
        case .permissions:
            if screen.permissionsReport?.needsFullDiskAccess == true {
                return ProtectionCardStatus(text: "Needs access", tile: .unavailable, symbol: "lock.fill")
            }
            let apps = Set(items.compactMap { $0.metadata[ProtectionPermissionMetaKey.client] }).count
            return ProtectionCardStatus(text: CountFormat.items(apps, singular: "app"), tile: .info)
        }
    }

    private var idleStatus: ProtectionCardStatus {
        switch tool {
        case .malware:
            guard let report = screen.malwareReport else {
                return ProtectionCardStatus(text: "Not scanned yet", tile: .info)
            }
            if report.threatCount == 0 {
                return ProtectionCardStatus(text: "Clear \(DurationFormat.relative(report.date))", tile: .clear,
                                            symbol: "checkmark.shield.fill")
            }
            return ProtectionCardStatus(text: "Checked \(DurationFormat.relative(report.date))", tile: .attention)
        case .privacy:
            return ProtectionCardStatus(text: "Ready", tile: .info)
        case .permissions:
            if screen.hasFullDiskAccess {
                return ProtectionCardStatus(text: "Ready", tile: .info)
            }
            return ProtectionCardStatus(text: "Needs access", tile: .unavailable, symbol: "lock.fill")
        }
    }
}

/// The status chip of a tool card.
struct ProtectionCardStatus {
    var text: String
    var tile: TileStatus
    var symbol: String? = nil
}

// MARK: - Real-time protection

/// Toggle and recent alerts of real-time protection.
struct ProtectionRealtimeCard: View {
    @Bindable var screen: ProtectionScreenModel
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let enabled = model.settings.settings.realtimeProtection
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: enabled ? "dot.radiowaves.left.and.right" : "pause.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(enabled ? StatusColor.success : ink.tertiary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Real-time protection")
                            .font(SpruceFont.headline)
                            .foregroundStyle(Ink.primary)
                        Text(enabled ? "Watching startup folders for new items" : "Off. New startup items aren't checked.")
                            .font(SpruceFont.caption)
                            .foregroundStyle(ink.secondary)
                    }
                    Spacer(minLength: Spacing.s)
                    Toggle("Real-time protection", isOn: Binding(
                        get: { model.settings.settings.realtimeProtection },
                        set: { model.settings.settings.realtimeProtection = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(ModuleID.protection.palette.accent)
                }
                Text("Spruce checks every new launch agent and daemon as it appears and alerts you, without removing anything on its own.")
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if enabled && !model.settings.settings.notifyThreats {
                    Label("Threat notifications are off in Settings.", systemImage: "bell.slash")
                        .font(SpruceFont.caption)
                        .foregroundStyle(StatusColor.warning)
                }
                eventsList
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var eventsList: some View {
        let events = Array(screen.realtimeEvents.prefix(3))
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(title: "Recently added")
                ForEach(events) { event in
                    ProtectionRealtimeEventRow(event: event) {
                        screen.startScan(.malware)
                    }
                }
            }
        }
    }
}

/// One startup item noticed by real-time protection.
struct ProtectionRealtimeEventRow: View {
    var event: ProtectionRealtimeEvent
    var onScan: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.s) {
            Image(systemName: event.isThreat ? "exclamationmark.shield.fill" : "bolt.horizontal.circle")
                .foregroundStyle(event.isThreat ? StatusColor.danger : ink.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.name)
                    .font(SpruceFont.callout.weight(.medium))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(event.location) · \(DurationFormat.relative(event.date))")
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            if event.isThreat {
                PrismTextButton(title: "Scan", module: .protection, action: onScan)
            }
            PrismIconButton(symbol: "magnifyingglass", help: "Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: event.path)])
            }
        }
        .help(event.notificationBody)
    }
}

// MARK: - macOS protection

/// XProtect, Gatekeeper, SIP, FileVault and firewall, read-only.
struct ProtectionAppleStatusCard: View {
    @Bindable var screen: ProtectionScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ink.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built-in macOS protection")
                            .font(SpruceFont.headline)
                            .foregroundStyle(Ink.primary)
                        Text(summary)
                            .font(SpruceFont.caption)
                            .foregroundStyle(ink.secondary)
                    }
                    Spacer(minLength: Spacing.s)
                    if screen.isReadingAppleStatus {
                        ProgressView().controlSize(.small)
                    } else {
                        PrismIconButton(symbol: "arrow.clockwise", help: "Check again") { screen.refreshAppleStatus() }
                    }
                }
                VStack(spacing: Spacing.xs) {
                    ProtectionStatusRow(title: "XProtect", value: xprotectText, state: screen.appleStatus?.xprotectVersion != nil)
                    ProtectionStatusRow(title: "Gatekeeper", value: onOff(screen.appleStatus?.gatekeeperEnabled),
                                        state: screen.appleStatus?.gatekeeperEnabled)
                    ProtectionStatusRow(title: "System Integrity Protection", value: onOff(screen.appleStatus?.sipEnabled),
                                        state: screen.appleStatus?.sipEnabled)
                    ProtectionStatusRow(title: "FileVault", value: onOff(screen.appleStatus?.fileVaultOn),
                                        state: screen.appleStatus?.fileVaultOn)
                    ProtectionStatusRow(title: "Firewall", value: onOff(screen.appleStatus?.firewallEnabled),
                                        state: screen.appleStatus?.firewallEnabled)
                }
                Text("Spruce works alongside these and never changes them.")
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var summary: String {
        guard let status = screen.appleStatus else { return "Checking…" }
        let off = status.disabledLayers
        if off.isEmpty { return "Everything that can be checked is on." }
        return "Off: " + off.joined(separator: ", ")
    }

    private var xprotectText: String {
        guard let status = screen.appleStatus else { return "—" }
        guard let version = status.xprotectVersion else { return "Unknown" }
        if let updated = status.xprotectUpdated {
            return "Version \(version) · updated \(DurationFormat.relative(updated))"
        }
        return "Version \(version)"
    }

    private func onOff(_ value: Bool?) -> String {
        guard screen.appleStatus != nil else { return "—" }
        switch value {
        case true?: return "On"
        case false?: return "Off"
        case nil: return "Unknown"
        }
    }
}

/// "Gatekeeper ········ On" with a status dot.
struct ProtectionStatusRow: View {
    var title: String
    var value: String
    /// true = good, false = off, nil = unknown.
    var state: Bool?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.s) {
            Circle()
                .fill(dotColor(ink))
                .frame(width: 7, height: 7)
            Text(title)
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.primary)
            Spacer(minLength: Spacing.s)
            Text(value)
                .font(SpruceFont.callout.monospacedDigit())
                .foregroundStyle(state == false ? StatusColor.warning : ink.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func dotColor(_ ink: PrismInk) -> Color {
        switch state {
        case true?: return StatusColor.success
        case false?: return StatusColor.warning
        case nil: return ink.tertiary
        }
    }
}
