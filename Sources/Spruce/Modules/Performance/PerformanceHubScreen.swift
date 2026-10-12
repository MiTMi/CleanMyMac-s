import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Performance landing: header plus one card per tool with its live summary.
struct PerformanceHubScreen: View {
    @Bindable var screen: PerformanceScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.l, alignment: .top),
                                    GridItem(.flexible(), spacing: Spacing.l, alignment: .top)],
                          alignment: .leading, spacing: Spacing.l) {
                    PerformanceMaintenanceCard(screen: screen)
                    PerformanceConsumersCard(screen: screen)
                    PerformanceStartupCard(screen: screen, tool: .loginItems)
                    PerformanceStartupCard(screen: screen, tool: .backgroundItems)
                }
            }
            .frame(maxWidth: Spacing.readableWidth)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.topInset + Spacing.l)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .task {
            // Keep the consumers card fresh while the hub is visible.
            while !Task.isCancelled {
                await screen.refreshConsumers()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            HeroLens(module: .performance, size: 84, mood: headerMood, parallax: false)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Performance")
                    .font(SpruceFont.display(34))
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(ModuleID.performance.tagline)
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

    private var brokenCount: Int { screen.inventory?.items.filter(\.isBroken).count ?? 0 }

    private var headerMood: PrismLensMood {
        brokenCount > 0 ? .warning : (screen.routineDueStates.isEmpty && screen.lastAssessed != nil ? .clean : .standard)
    }

    private var statusLine: String {
        if screen.lastAssessed == nil { return "Checking what your Mac needs…" }
        let due = screen.routineDueStates.count
        var parts: [String] = []
        parts.append(due == 0 ? "Routine maintenance is up to date" : "\(CountFormat.items(due, singular: "routine task")) due")
        if brokenCount > 0 { parts.append("\(CountFormat.items(brokenCount, singular: "broken startup item")) to review") }
        return parts.joined(separator: " · ") + "."
    }

    private var statusColor: Color {
        if brokenCount > 0 { return StatusColor.warning }
        if screen.lastAssessed != nil && screen.routineDueStates.isEmpty { return StatusColor.success }
        return PrismInk(contrast).tertiary
    }
}

// MARK: - Card shell

/// Shared layout of a hub card: badge, title, status pill, body and actions.
struct PerformanceHubCard<Content: View, Actions: View>: View {
    var tool: PerformanceTool
    var status: (text: String, tile: TileStatus)?
    var onOpen: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GlassCard(isHighlighted: hovering) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top) {
                    PrismCategoryBadge(symbol: tool.symbol, module: .performance, size: 44)
                    Spacer(minLength: Spacing.s)
                    if let status {
                        StatusPill(text: status.text, status: status.tile)
                    }
                }
                Text(tool.title)
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: Spacing.s) {
                    actions
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(tool.title))
    }
}

// MARK: - Maintenance card

struct PerformanceMaintenanceCard: View {
    @Bindable var screen: PerformanceScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let due = screen.routineDueStates
        let suggestions = screen.recommendedStates.filter { !$0.assessment.preselect }
        PerformanceHubCard(tool: .maintenance, status: status(due: due.count), onOpen: { screen.open(.maintenance) }) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if screen.lastAssessed == nil {
                    Text("Checking which tasks are due…")
                        .font(SpruceFont.callout)
                        .foregroundStyle(PrismInk(contrast).secondary)
                } else if due.isEmpty {
                    Text("Nothing routine is due. The full list has tasks for specific problems, like slow search or wrong file icons.")
                        .font(SpruceFont.callout)
                        .foregroundStyle(PrismInk(contrast).secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(due.prefix(4)) { state in
                        Label(state.definition.title, systemImage: state.definition.symbol)
                            .font(SpruceFont.callout)
                            .foregroundStyle(Ink.primary.opacity(0.9))
                    }
                }
                if !suggestions.isEmpty {
                    Text("Also worth a look: " + suggestions.map(\.definition.title).joined(separator: ", "))
                        .font(SpruceFont.caption)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                        .lineLimit(2)
                        .padding(.top, Spacing.xxs)
                }
            }
        } actions: {
            if !due.isEmpty {
                CapsuleButton(title: due.count == 1 ? "Run 1 Task" : "Run \(due.count) Tasks", symbol: "play.fill",
                              prominent: true) { screen.runRoutineTasks() }
                    .disabled(screen.isRunning)
            }
            CapsuleButton(title: due.isEmpty ? "View All Tasks" : "Review") { screen.open(.maintenance) }
        }
    }

    private func status(due: Int) -> (text: String, tile: TileStatus)? {
        if screen.isRunning { return ("Running", .info) }
        guard screen.lastAssessed != nil else { return nil }
        return due == 0 ? ("Up to date", .clear) : ("\(due) due", .attention)
    }
}

// MARK: - Login / background items card

struct PerformanceStartupCard: View {
    @Bindable var screen: PerformanceScreenModel
    var tool: PerformanceTool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let items = tool == .loginItems ? (screen.inventory?.loginItems ?? []) : (screen.inventory?.backgroundItems ?? [])
        PerformanceHubCard(tool: tool, status: status(items), onOpen: { screen.open(tool) }) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if screen.inventory == nil {
                    Text("Looking for what starts with your Mac…")
                        .font(SpruceFont.callout)
                        .foregroundStyle(PrismInk(contrast).secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(items.count)")
                            .font(SpruceFont.metricL)
                            .foregroundStyle(Ink.primary)
                        Text(subtitle(items))
                            .font(SpruceFont.callout)
                            .foregroundStyle(PrismInk(contrast).secondary)
                    }
                    iconCluster(items)
                }
            }
        } actions: {
            CapsuleButton(title: "Review") { screen.open(tool) }
        }
    }

    private func subtitle(_ items: [PerformanceStartupItem]) -> String {
        let enabled = items.filter { $0.isEnabled }.count
        if tool == .loginItems {
            return items.count == 1 ? "item opens when you log in" : "items, \(enabled) open when you log in"
        }
        return items.count == 1 ? "agent or daemon" : "agents and daemons, \(enabled) switched on"
    }

    private func status(_ items: [PerformanceStartupItem]) -> (text: String, tile: TileStatus)? {
        guard screen.inventory != nil else { return nil }
        let broken = items.filter(\.isBroken).count
        if broken > 0 { return ("\(broken) broken", .critical) }
        if tool == .loginItems && screen.inventory?.loginItemsAccess == .denied { return ("Needs access", .attention) }
        return nil
    }

    @ViewBuilder
    private func iconCluster(_ items: [PerformanceStartupItem]) -> some View {
        let paths = Array(Set(items.compactMap(\.appPath))).sorted().prefix(7)
        if !paths.isEmpty {
            HStack(spacing: -6) {
                ForEach(Array(paths), id: \.self) { path in
                    ItemIcon(url: URL(fileURLWithPath: path), symbol: "app", size: 26)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
            }
        }
    }
}

// MARK: - Consumers card

struct PerformanceConsumersCard: View {
    @Bindable var screen: PerformanceScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        PerformanceHubCard(tool: .consumers, status: status, onOpen: { screen.open(.consumers) }) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let memory = screen.memory {
                    Text("Memory \(ByteFormat.string(memory.used)) of \(ByteFormat.string(memory.total)) · pressure \(memory.pressureTitle.lowercased())")
                        .font(SpruceFont.caption)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                }
                if screen.consumers.isEmpty {
                    Text("Measuring what's using your Mac…")
                        .font(SpruceFont.callout)
                        .foregroundStyle(PrismInk(contrast).secondary)
                } else {
                    ForEach(screen.consumers.prefix(3)) { consumer in
                        HStack(spacing: Spacing.s) {
                            ItemIcon(url: consumer.appPath.map { URL(fileURLWithPath: $0) }, symbol: "gearshape", size: 20,
                                     module: .performance)
                            Text(consumer.name)
                                .font(SpruceFont.callout)
                                .foregroundStyle(Ink.primary.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: Spacing.s)
                            Text(String(format: "%.0f%% CPU", consumer.cpu))
                                .font(SpruceFont.captionDigits)
                                .foregroundStyle(PrismInk(contrast).secondary)
                        }
                    }
                }
            }
        } actions: {
            CapsuleButton(title: "Open") { screen.open(.consumers) }
        }
    }

    private var status: (text: String, tile: TileStatus)? {
        guard let memory = screen.memory else { return nil }
        switch memory.pressureLevel {
        case 4: return ("Memory critical", .critical)
        case 2: return ("Memory elevated", .attention)
        default: return nil
        }
    }
}
