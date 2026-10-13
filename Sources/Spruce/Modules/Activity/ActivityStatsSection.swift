import Charts
import SpruceCore
import SpruceMac
import SwiftUI

/// Month stepper, stat tiles (selected month vs the one before) and the six-month chart.
struct ActivityStatsSection: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedMonth: Date?

    private let calendar = ActivityMonthly.calendar()

    var body: some View {
        let history = model.history.history
        // Seven months so the oldest visible month still has a "previous" month.
        let all = ActivityMonthly.months(history, count: 7, now: Date(), calendar: calendar)
        let visible = Array(all.dropFirst())
        let index = selectedIndex(in: visible)
        let current = visible[index]
        let previous = all[index]          // `all` is offset by one
        VStack(alignment: .leading, spacing: Spacing.m) {
            header(visible: visible, index: index)
            if history.entries.isEmpty {
                ActivityEmptyStatsCard()
            } else {
                ActivityStatGrid(current: current, previous: previous, history: history, calendar: calendar)
                ActivityMonthlyChart(months: visible, selected: current.start, calendar: calendar) { start in
                    selectedMonth = start
                }
            }
        }
    }

    private func selectedIndex(in months: [ActivityMonthStats]) -> Int {
        if let selectedMonth, let i = months.firstIndex(where: { $0.start == selectedMonth }) { return i }
        return max(0, months.count - 1)
    }

    private func header(visible: [ActivityMonthStats], index: Int) -> some View {
        HStack(spacing: Spacing.s) {
            SectionHeader(title: "Monthly Summary")
            Spacer(minLength: Spacing.m)
            PrismIconButton(symbol: "chevron.left", help: "Previous month") {
                selectedMonth = visible[max(0, index - 1)].start
            }
            .disabled(index == 0)
            Text(ActivityMonthly.title(visible[index].start, calendar: calendar))
                .font(SpruceFont.bodyStrong.monospacedDigit())
                .foregroundStyle(Ink.primary)
                .frame(minWidth: 130)
                .contentTransition(.numericText())
            PrismIconButton(symbol: "chevron.right", help: "Next month") {
                selectedMonth = visible[min(visible.count - 1, index + 1)].start
            }
            .disabled(index >= visible.count - 1)
        }
    }
}

// MARK: - Tiles

struct ActivityStatGrid: View {
    var current: ActivityMonthStats
    var previous: ActivityMonthStats
    var history: ActivityHistory
    var calendar: Calendar

    var body: some View {
        let previousName = ActivityMonthly.title(previous.start, calendar: calendar)
        let unresolved = ActivityHealth.unresolvedThreats(in: history)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.m, alignment: .top), count: 3),
                  alignment: .leading, spacing: Spacing.m) {
            ActivityStatTile(title: "Space freed", symbol: "arrow.down.circle", tint: ModuleID.cleanup.palette.accentText,
                             value: ByteFormat.string(current.bytesFreed),
                             caption: "\(previousName): \(ByteFormat.string(previous.bytesFreed))",
                             delta: ActivityDelta.percent(current: Double(current.bytesFreed), previous: Double(previous.bytesFreed)))
            ActivityStatTile(title: "Cloud space freed", symbol: "icloud", tint: ModuleID.cloudStorage.palette.accentText,
                             value: ByteFormat.string(current.cloudFreed),
                             caption: "\(previousName): \(ByteFormat.string(previous.cloudFreed))",
                             delta: ActivityDelta.percent(current: Double(current.cloudFreed), previous: Double(previous.cloudFreed)))
            ActivityStatTile(title: "Threats", symbol: "shield.lefthalf.filled", tint: ModuleID.protection.palette.accentText,
                             value: "\(CountFormat.grouped(current.threatsFound)) found",
                             caption: threatCaption(unresolved: unresolved),
                             captionColor: unresolved > 0 ? StatusColor.danger : nil,
                             delta: ActivityDelta.absolute(current: current.threatsFound, previous: previous.threatsFound),
                             deltaIsPercent: false, higherIsBetter: false)
            ActivityStatTile(title: "Items scanned", symbol: "magnifyingglass", tint: ModuleID.clutter.palette.accentText,
                             value: CountFormat.grouped(current.itemsScanned),
                             caption: "found across \(CountFormat.items(current.scans, singular: "scan"))",
                             delta: ActivityDelta.percent(current: Double(current.itemsScanned), previous: Double(previous.itemsScanned)))
            ActivityTimeSavedTile(current: current, previous: previous, history: history, calendar: calendar)
            ActivityStatTile(title: "Apps & upkeep", symbol: "square.grid.2x2", tint: ModuleID.applications.palette.accentText,
                             value: CountFormat.items(current.uninstalls, singular: "uninstall"),
                             caption: "\(CountFormat.items(current.appsUpdated, singular: "app")) updated · \(CountFormat.items(current.tasksRun, singular: "task")) run",
                             delta: ActivityDelta.absolute(current: current.uninstalls + current.appsUpdated + current.tasksRun,
                                                           previous: previous.uninstalls + previous.appsUpdated + previous.tasksRun),
                             deltaIsPercent: false)
        }
    }

    private func threatCaption(unresolved: Int) -> String {
        var parts = ["\(CountFormat.grouped(current.threatsRemoved)) removed",
                     CountFormat.items(current.malwareScans, singular: "scan")]
        if unresolved > 0 { parts.append("\(unresolved) unresolved") }
        return parts.joined(separator: " · ")
    }
}

struct ActivityStatTile<Accessory: View>: View {
    var title: String
    var symbol: String
    var tint: Color
    var value: String
    var caption: String
    var captionColor: Color? = nil
    var delta: ActivityDelta
    var deltaIsPercent: Bool = true
    var higherIsBetter: Bool = true
    @ViewBuilder var accessory: Accessory

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(SpruceFont.overline)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(PrismInk(contrast).tertiary)
                Spacer(minLength: Spacing.xs)
                accessory
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(value)
                    .font(SpruceFont.metricS)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                if let label = delta.label(percent: deltaIsPercent) {
                    Text(label)
                        .font(SpruceFont.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ActivityStyle.color(delta, higherIsBetter: higherIsBetter))
                        .help("Compared with the month before")
                }
            }
            Text(caption)
                .font(SpruceFont.caption)
                .foregroundStyle(captionColor ?? PrismInk(contrast).secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .prismSurface(radius: Radius.card)
        .accessibilityElement(children: .combine)
    }
}

extension ActivityStatTile where Accessory == EmptyView {
    init(title: String, symbol: String, tint: Color, value: String, caption: String, captionColor: Color? = nil,
         delta: ActivityDelta, deltaIsPercent: Bool = true, higherIsBetter: Bool = true) {
        self.init(title: title, symbol: symbol, tint: tint, value: value, caption: caption, captionColor: captionColor,
                  delta: delta, deltaIsPercent: deltaIsPercent, higherIsBetter: higherIsBetter, accessory: { EmptyView() })
    }
}

/// Time-saved tile with a "How we estimate" popover listing the constants applied.
struct ActivityTimeSavedTile: View {
    var current: ActivityMonthStats
    var previous: ActivityMonthStats
    var history: ActivityHistory
    var calendar: Calendar

    @State private var showsExplanation = false

    var body: some View {
        ActivityStatTile(title: "Time saved", symbol: "clock", tint: ModuleID.activity.palette.accentText,
                         value: ActivityTimeSaved.formatted(current.timeSaved),
                         caption: "Estimated from what you ran this month",
                         delta: ActivityDelta.percent(current: current.timeSaved, previous: previous.timeSaved)) {
            Button {
                showsExplanation.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.secondary)
            }
            .buttonStyle(.plain)
            .help("How we estimate")
            .accessibilityLabel("How the time-saved estimate works")
            .popover(isPresented: $showsExplanation, arrowEdge: .bottom) {
                ActivityTimeSavedExplanation(estimate: estimate())
            }
        }
    }

    private func estimate() -> ActivityTimeSaved.Estimate {
        let end = calendar.date(byAdding: .month, value: 1, to: current.start) ?? current.start
        let entries = history.entries.filter { $0.date >= current.start && $0.date < end }
        return ActivityTimeSaved.estimate(entries, calendar: calendar)
    }
}

struct ActivityTimeSavedExplanation: View {
    var estimate: ActivityTimeSaved.Estimate

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("How we estimate")
                .font(SpruceFont.headline)
            Text("Each action is credited with the time doing it by hand usually takes. No day counts for more than \(DurationFormat.short(ActivityTimeSaved.dailyCap)).")
                .font(SpruceFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if estimate.lines.isEmpty {
                Text("Nothing counted yet this month.")
                    .font(SpruceFont.callout)
            } else {
                ForEach(estimate.lines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.explanation)
                            .font(SpruceFont.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Spacing.m)
                        Text(DurationFormat.short(line.seconds))
                            .font(SpruceFont.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if estimate.wasCapped {
                    Text("Busy days were capped, so the total is \(ActivityTimeSaved.formatted(estimate.total)) rather than \(ActivityTimeSaved.formatted(estimate.uncapped)).")
                        .font(SpruceFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.l)
        .frame(width: 380)
    }
}

/// Shown before anything has been recorded.
struct ActivityEmptyStatsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GlassCard(padding: Spacing.xl) {
            HStack(spacing: Spacing.l) {
                PrismCategoryBadge(symbol: "chart.bar.xaxis", module: .activity, size: 48)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Your progress will appear here")
                        .font(SpruceFont.headline)
                        .foregroundStyle(Ink.primary)
                    Text("Space freed, threats handled and time saved are tallied month by month, on this Mac only.")
                        .font(SpruceFont.callout)
                        .foregroundStyle(PrismInk(contrast).secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.m)
                CapsuleButton(title: "Run Checkup", symbol: "sparkles", prominent: true) {
                    model.open(.checkup, tool: "checkup.scan")
                }
            }
        }
    }
}

// MARK: - Chart

struct ActivityMonthlyChart: View {
    var months: [ActivityMonthStats]
    var selected: Date
    var calendar: Calendar
    var onSelect: (Date) -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = ModuleID.activity.palette
        let total = months.reduce(Int64(0)) { $0 + $1.bytesFreed }
        let peak = Double(months.map(\.bytesFreed).max() ?? 0)
        GlassCard(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Space freed by month")
                        .font(SpruceFont.headline)
                        .foregroundStyle(Ink.primary)
                    Spacer()
                    Text("Last 6 months · \(ByteFormat.string(total))")
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                }
                Chart(months) { month in
                    BarMark(x: .value("Month", label(month)),
                            y: .value("Space freed", Double(month.bytesFreed)))
                        .foregroundStyle(month.start == selected
                                         ? AnyShapeStyle(palette.accentGradient)
                                         : AnyShapeStyle(palette.accent.opacity(0.32)))
                        .cornerRadius(6)
                        .annotation(position: .top, alignment: .center) {
                            if month.bytesFreed > 0 {
                                Text(ByteFormat.string(month.bytesFreed))
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(month.start == selected ? Ink.primary : PrismInk(contrast).tertiary)
                            }
                        }
                }
                .chartYScale(domain: 0...max(peak * 1.15, 1_000_000))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(Ink.hairline)
                        AxisValueLabel {
                            if let bytes = value.as(Double.self) {
                                Text(ByteFormat.string(Int64(bytes)))
                                    .font(SpruceFont.captionDigits)
                                    .foregroundStyle(PrismInk(contrast).tertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(SpruceFont.caption)
                                    .foregroundStyle(PrismInk(contrast).secondary)
                            }
                        }
                    }
                }
                .frame(height: 190)
                .accessibilityLabel("Space freed in each of the last six months")

                HStack(spacing: Spacing.xs) {
                    ForEach(months) { month in
                        ActivityMonthChip(title: label(month), isSelected: month.start == selected) {
                            onSelect(month.start)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func label(_ month: ActivityMonthStats) -> String {
        ActivityMonthly.shortName(month.start, calendar: calendar)
    }
}

/// Small selectable month capsule under the chart.
struct ActivityMonthChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SpruceFont.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Ink.primary : Ink.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Ink.selectedFill : (hovering ? Ink.subtleFill : Color.clear)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
