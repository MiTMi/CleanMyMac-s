import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Live list of the apps and processes using the most CPU or memory, with Quit / Force Quit.
struct PerformanceConsumersScreen: View {
    @Bindable var screen: PerformanceScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: "Heavy Consumers", subtitle: "What's using your Mac's processor and memory right now",
                         backTitle: "Performance", onBack: { screen.goHub() }, module: .performance,
                         trailing: AnyView(sortPicker))
            memorySummary
            list
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Updates every 3 seconds. CPU is per core, so a busy app can show more than 100%. Apps are asked to quit normally first, so they can save your work.")
                .font(SpruceFont.caption)
                .foregroundStyle(PrismInk(contrast).tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
        .padding(.bottom, Spacing.m)
        .task(id: screen.consumerSort) {
            while !Task.isCancelled {
                await screen.refreshConsumers()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private var sortPicker: some View {
        Picker("Sort by", selection: $screen.consumerSort) {
            ForEach(PerformanceConsumerSort.allCases) { sort in
                Text(sort.title).tag(sort)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 180)
    }

    @ViewBuilder
    private var memorySummary: some View {
        if let memory = screen.memory {
            HStack(spacing: Spacing.s) {
                PrismStatChip(symbol: "memorychip", value: "\(ByteFormat.string(memory.used)) of \(ByteFormat.string(memory.total))",
                              label: "Memory used", tint: ModuleID.performance.palette.accentText)
                PrismStatChip(symbol: "gauge.with.dots.needle.33percent", value: memory.pressureTitle, label: "Memory pressure",
                              tint: pressureColor(memory.pressureLevel))
                PrismStatChip(symbol: "arrow.left.arrow.right", value: ByteFormat.string(memory.swapUsed), label: "Swap used",
                              tint: memory.swapUsed > 2_000_000_000 ? StatusColor.warning : PrismInk(contrast).secondary)
                PrismStatChip(symbol: "archivebox", value: ByteFormat.string(memory.compressed), label: "Compressed",
                              tint: PrismInk(contrast).secondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func pressureColor(_ level: Int) -> Color {
        switch level {
        case 4: return StatusColor.danger
        case 2: return StatusColor.warning
        default: return StatusColor.success
        }
    }

    @ViewBuilder
    private var list: some View {
        if screen.consumers.isEmpty {
            VStack(spacing: Spacing.m) {
                ProgressView()
                Text("Measuring…")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
            }
        } else {
            let maxCPU = max(100, screen.consumers.map(\.cpu).max() ?? 100)
            let maxMemory = max(1, screen.consumers.map(\.memoryBytes).max() ?? 1)
            GlassCard(padding: Spacing.s) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(screen.consumers) { consumer in
                            PerformanceConsumerRow(consumer: consumer,
                                                   totalMemory: screen.memory?.total ?? 0,
                                                   maxCPU: maxCPU,
                                                   maxMemory: maxMemory,
                                                   sort: screen.consumerSort,
                                                   isQuitting: screen.quittingIDs.contains(consumer.id),
                                                   onQuit: { screen.quit(consumer, force: false) },
                                                   onForceQuit: { screen.requestForceQuit(consumer) })
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .scrollIndicators(.automatic)
            }
        }
    }
}

// MARK: - Row

struct PerformanceConsumerRow: View {
    var consumer: PerformanceConsumer
    var totalMemory: Int64
    var maxCPU: Double
    var maxMemory: Int64
    var sort: PerformanceConsumerSort
    var isQuitting: Bool
    var onQuit: () -> Void
    var onForceQuit: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let heavy = PerformanceConsumerAggregator.isHeavy(consumer, totalMemory: totalMemory)
        HStack(spacing: Spacing.m) {
            ItemIcon(url: consumer.appPath.map { URL(fileURLWithPath: $0) }, symbol: "gearshape", size: 26, module: .performance)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s) {
                    Text(consumer.name)
                        .font(SpruceFont.body.weight(.medium))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    if heavy.cpu { PrismChip(text: "Busy CPU", color: StatusColor.warning) }
                    if heavy.memory { PrismChip(text: "High memory", color: StatusColor.warning) }
                }
                Text(caption)
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            metric(String(format: "%.0f%%", consumer.cpu), label: "CPU", fraction: consumer.cpu / maxCPU, emphasized: sort == .cpu)
            metric(ByteFormat.string(consumer.memoryBytes), label: "Memory",
                   fraction: Double(consumer.memoryBytes) / Double(maxMemory), emphasized: sort == .memory)
            actions(ink)
                .frame(width: 190, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hovering ? Ink.subtleFill : Color.clear))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var caption: String {
        var parts: [String] = []
        parts.append(consumer.processCount > 1 ? "\(consumer.processCount) processes" : "Process \(consumer.primaryPID)")
        if !consumer.ownedByUser { parts.append("system") }
        return parts.joined(separator: " · ")
    }

    private func metric(_ value: String, label: String, fraction: Double, emphasized: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(value)
                .font(SpruceFont.captionDigits.weight(emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? Ink.primary : PrismInk(contrast).secondary)
            PrismLinearProgress(value: min(max(fraction, 0), 1), module: .performance, height: 3)
                .frame(width: 72)
        }
        .frame(width: 84, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label) \(value)"))
    }

    @ViewBuilder
    private func actions(_ ink: PrismInk) -> some View {
        if isQuitting {
            ProgressView().controlSize(.small)
        } else if let reason = consumer.protectedReason {
            Text(reason)
                .font(SpruceFont.caption)
                .foregroundStyle(ink.tertiary)
                .lineLimit(1)
        } else {
            HStack(spacing: Spacing.xs) {
                CapsuleButton(title: "Quit", action: onQuit)
                CapsuleButton(title: "Force Quit", destructive: true, action: onForceQuit)
            }
        }
    }
}
