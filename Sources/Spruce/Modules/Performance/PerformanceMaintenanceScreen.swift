import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Maintenance tasks: checklist on the left, the focused task's details on the right,
/// and the Run orb. Rows show live state while a run is in progress.
struct PerformanceMaintenanceScreen: View {
    @Bindable var screen: PerformanceScreenModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            phaseContent
                .id(phaseKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: phaseKey)
    }

    private var phaseKey: String {
        switch screen.maintenancePhase {
        case .loading: return "loading"
        case .ready, .running: return "list"
        case .done: return "done"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch screen.maintenancePhase {
        case .loading:
            ScanningView(module: .performance, progress: ScanProgress(fraction: nil, message: "Checking what your Mac needs…"),
                         title: "Checking…", showsBytes: false)
        case .ready, .running:
            PerformanceMaintenanceList(screen: screen)
        case .done:
            if let outcome = screen.lastOutcome {
                DoneView(module: .performance, outcome: outcome, headline: doneHeadline(outcome)) {
                    screen.acknowledgeDone()
                }
            } else {
                PerformanceMaintenanceList(screen: screen)
            }
        }
    }

    private func doneHeadline(_ outcome: RunOutcome) -> String? {
        if outcome.freedBytes > 0 { return nil }      // DoneView counts up the freed bytes
        return outcome.failures.isEmpty ? "Maintenance complete" : nil
    }
}

// MARK: - List + detail

struct PerformanceMaintenanceList: View {
    @Bindable var screen: PerformanceScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: "Maintenance", subtitle: subtitle, backTitle: "Performance", onBack: { screen.goHub() },
                         module: .performance, trailing: AnyView(trailingControls))
            HStack(alignment: .top, spacing: Spacing.m) {
                taskList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PerformanceTaskDetailPane(screen: screen)
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
            }
            footer
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var subtitle: String {
        if screen.isRunning { return screen.runProgress.message }
        let due = screen.routineDueStates.count
        let total = screen.availableStates.count
        if due == 0 { return "\(CountFormat.items(total, singular: "task")) · routine care is up to date" }
        return "\(CountFormat.items(total, singular: "task")) · \(due) due"
    }

    private var trailingControls: some View {
        HStack(spacing: Spacing.s) {
            Menu {
                Button("Select Recommended") { screen.selectTasks(.recommended) }
                Button("Select All") { screen.selectTasks(.all) }
                Button("Deselect All") { screen.selectTasks(.none) }
            } label: {
                HStack(spacing: 4) {
                    Text("Select")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(SpruceFont.callout.weight(.medium))
                .foregroundStyle(Ink.primary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(screen.isRunning)
            PrismIconButton(symbol: "arrow.clockwise", help: "Check again") { screen.refreshTasks() }
                .disabled(screen.isRunning || screen.isAssessing)
        }
    }

    private var taskList: some View {
        GlassCard(padding: Spacing.s) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    let available = screen.availableStates
                    ForEach(available) { state in
                        PerformanceTaskRow(screen: screen, state: state)
                    }
                    let unavailable = screen.taskStates.filter { !$0.assessment.isAvailable }
                    if !unavailable.isEmpty {
                        SectionHeader(title: "Not available right now")
                            .padding(.horizontal, Spacing.s)
                            .padding(.top, Spacing.m)
                        ForEach(unavailable) { state in
                            PerformanceTaskRow(screen: screen, state: state)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var footer: some View {
        let count = screen.selectedTasks.count
        let needsAdmin = screen.selectedTasks.contains { PerformanceTaskCatalog.definition($0).needsAdmin }
        return ZStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 0 ? "No tasks selected" : "\(CountFormat.items(count, singular: "task")) selected")
                        .font(SpruceFont.bodyStrong)
                        .foregroundStyle(Ink.primary)
                    if needsAdmin && !screen.isRunning {
                        Label("You'll be asked for your password once", systemImage: "lock")
                            .font(SpruceFont.caption)
                            .foregroundStyle(PrismInk(contrast).tertiary)
                    }
                }
                Spacer()
            }
            if screen.isRunning {
                ActionOrb(title: "Stop", subtitle: nil, module: .performance, progress: screen.runProgress.fraction,
                          isBusy: true, diameter: 84) { screen.stopRun() }
            } else {
                ActionOrb(title: "Run", subtitle: count == 0 ? nil : CountFormat.items(count, singular: "task"),
                          module: .performance, isEnabled: count > 0, diameter: 84, isReady: count > 0) {
                    screen.runSelected()
                }
            }
        }
        .frame(height: 96)
        .padding(.bottom, Spacing.m)
    }
}

// MARK: - Row

struct PerformanceTaskRow: View {
    @Bindable var screen: PerformanceScreenModel
    var state: PerformanceTaskState

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let available = state.assessment.isAvailable
        let focused = screen.focusedTaskID == state.id
        HStack(spacing: Spacing.m) {
            SpruceCheckbox(isOn: screen.selectedTasks.contains(state.id), module: .performance, label: state.definition.title) {
                screen.toggleTask(state.id)
            }
            .disabled(!available || screen.isRunning)
            PrismCategoryBadge(symbol: state.definition.symbol, module: .performance, size: 32, isDimmed: !available)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s) {
                    Text(state.definition.title)
                        .font(SpruceFont.bodyStrong)
                        .foregroundStyle(available ? Ink.primary : ink.tertiary)
                        .lineLimit(1)
                    if state.assessment.isRecommended {
                        PrismChip(text: "Recommended", color: ModuleID.performance.palette.accentText)
                    }
                    if state.definition.needsAdmin {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ink.tertiary)
                            .help("Needs your administrator password")
                    }
                }
                Text(detailLine)
                    .font(SpruceFont.caption)
                    .foregroundStyle(detailColor(ink))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s)
            trailing(ink)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(focused ? Ink.selectedFill : (hovering ? Ink.subtleFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { screen.focusedTaskID = state.id }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(focused ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var rowState: PerformanceTaskRowState { screen.rowState(for: state.id) }

    private var detailLine: String {
        if case .finished(let result) = rowState { return result.detail }
        if case .running = rowState { return state.definition.needsAdmin ? "Running as administrator…" : "Running…" }
        return state.assessment.reason
    }

    private func detailColor(_ ink: PrismInk) -> Color {
        if case .finished(let result) = rowState {
            switch result.status {
            case .done: return StatusColor.success
            case .skipped: return ink.secondary
            case .failed: return StatusColor.warning
            }
        }
        return ink.secondary
    }

    @ViewBuilder
    private func trailing(_ ink: PrismInk) -> some View {
        switch rowState {
        case .queued:
            Text("Waiting")
                .font(SpruceFont.caption)
                .foregroundStyle(ink.tertiary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .finished(let result):
            Image(systemName: Self.symbol(for: result.status))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.color(for: result.status))
                .help(result.detail)
        case .idle:
            if let lastRun = state.lastRun {
                Text(DurationFormat.relative(lastRun))
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .help("Last run \(lastRun.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

    static func symbol(for status: PerformanceTaskRunStatus) -> String {
        switch status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    static func color(for status: PerformanceTaskRunStatus) -> Color {
        switch status {
        case .done: return StatusColor.success
        case .skipped: return Ink.secondary
        case .failed: return StatusColor.warning
        }
    }
}

// MARK: - Detail pane

/// What the focused task does, when to run it, what it needs and how it went last time.
struct PerformanceTaskDetailPane: View {
    @Bindable var screen: PerformanceScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GlassCard(padding: Spacing.l) {
            if let state = screen.focusedState {
                ScrollView {
                    details(state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            } else {
                Text("Select a task to see what it does.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func details(_ state: PerformanceTaskState) -> some View {
        let ink = PrismInk(contrast)
        let def = state.definition
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                PrismCategoryBadge(symbol: def.symbol, module: .performance, size: 44, isDimmed: !state.assessment.isAvailable)
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.title)
                        .font(SpruceFont.headline)
                        .foregroundStyle(Ink.primary)
                    Text(def.impact.label)
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                }
            }
            Text(def.summary)
                .font(SpruceFont.body)
                .foregroundStyle(ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            section("When to run it") {
                bullets(def.whenToRun, ink: ink)
            }
            if let side = def.sideEffects {
                section("Good to know") {
                    Text(side)
                        .font(SpruceFont.callout)
                        .foregroundStyle(ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !def.requirements.isEmpty {
                section("Needs") {
                    bullets(def.requirements, ink: ink)
                }
            }
            section(state.assessment.isAvailable ? "Right now" : "Unavailable") {
                Text(state.assessment.reason)
                    .font(SpruceFont.callout)
                    .foregroundStyle(state.assessment.isRecommended ? ModuleID.performance.palette.accentText : ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            section("Last run") {
                Text(state.lastRun.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never run by Spruce")
                    .font(SpruceFont.callout)
                    .foregroundStyle(ink.secondary)
            }
            if let result = screen.lastResults[state.id] {
                section("Last result") {
                    Label {
                        Text(result.detail)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: PerformanceTaskRow.symbol(for: result.status))
                            .foregroundStyle(PerformanceTaskRow.color(for: result.status))
                    }
                    .font(SpruceFont.callout)
                    .foregroundStyle(ink.secondary)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: title)
            content()
        }
    }

    private func bullets(_ lines: [String], ink: PrismInk) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(ink.tertiary)
                    Text(line)
                        .foregroundStyle(ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(SpruceFont.callout)
            }
        }
    }
}
