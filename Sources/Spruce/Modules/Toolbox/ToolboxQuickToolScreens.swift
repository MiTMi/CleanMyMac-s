import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Free Up RAM / Flush DNS

/// Intro → running → result for the two one-step maintenance tools.
struct ToolboxTaskScreen: View {
    var kind: ToolboxLocalTool
    @Bindable var task: ToolboxTaskModel
    var onBack: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ToolboxToolFrame(onBack: onBack) {
            ZStack {
                phaseContent
                    .id(phaseKey)
                    .transition(.prismPhase(reduceMotion: reduceMotion))
            }
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: phaseKey)
        }
    }

    private var phaseKey: String {
        switch task.phase {
        case .idle: return "idle"
        case .running: return "running"
        case .done: return "done"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch task.phase {
        case .idle:
            ModuleIdleView(module: .toolbox,
                           title: copy.title,
                           subtitle: copy.subtitle,
                           features: copy.features,
                           actionTitle: copy.actionTitle,
                           actionSubtitle: "Needs your password",
                           accessory: kind == .freeRAM ? AnyView(ToolboxMemoryMeter()) : nil,
                           action: { task.run(engine: model.performance, monitor: model.monitor) })
        case .running:
            ScanningView(module: .toolbox, progress: task.progress, title: copy.runningTitle, showsBytes: false)
        case .done(let result):
            DoneView(module: .toolbox, outcome: outcome(for: result), headline: headline(for: result)) {
                task.reset()
            }
        }
    }

    private struct Copy {
        var title: String
        var subtitle: String
        var features: [IdleFeature]
        var actionTitle: String
        var runningTitle: String
    }

    private var copy: Copy {
        switch kind {
        case .flushDNS:
            return Copy(
                title: "Flush DNS Cache",
                subtitle: "Forget cached website addresses so they're looked up fresh.",
                features: [
                    IdleFeature(symbol: "network", title: "Fixes stale lookups",
                                detail: "Helps when sites won't load or still point to an old address after a network or DNS change."),
                    IdleFeature(symbol: "wifi", title: "Your connection stays up",
                                detail: "Nothing is disconnected. Addresses are simply fetched again the next time they're needed."),
                    IdleFeature(symbol: "lock.shield", title: "Asks for your password",
                                detail: "Clearing the system resolver needs administrator rights. Nothing stays installed."),
                ],
                actionTitle: "Flush",
                runningTitle: "Flushing…")
        default:
            return Copy(
                title: "Free Up RAM",
                subtitle: "Ask macOS to drop cached memory it can rebuild later.",
                features: [
                    IdleFeature(symbol: "memorychip", title: "Drops cached memory",
                                detail: "Runs the system's purge command. Open apps and documents are not affected."),
                    IdleFeature(symbol: "info.circle", title: "Rarely needed",
                                detail: "macOS manages memory well on its own. Try this when the Mac feels sluggish after heavy work."),
                    IdleFeature(symbol: "lock.shield", title: "Asks for your password",
                                detail: "The command needs administrator rights. Nothing stays installed."),
                ],
                actionTitle: "Free Up",
                runningTitle: "Freeing up memory…")
        }
    }

    private func outcome(for result: PerformanceTaskRunResult) -> RunOutcome {
        var summary = result.detail
        if kind == .freeRAM, let before = task.memoryBefore, let after = task.memoryAfter {
            summary += (summary.isEmpty ? "" : " ") + "Memory in use: \(ByteFormat.string(before)) → \(ByteFormat.string(after))."
        }
        if result.status == .done {
            return RunOutcome(module: .toolbox, processedCount: 1, removedItemIDs: [kind.toolID], summary: summary)
        }
        return RunOutcome(module: .toolbox,
                          failures: [ItemFailure(itemID: kind.toolID, title: kind.title, reason: result.detail)],
                          summary: result.status == .skipped ? "Nothing was changed." : "")
    }

    private func headline(for result: PerformanceTaskRunResult) -> String {
        switch result.status {
        case .done: return kind == .freeRAM ? "Memory freed up" : "DNS cache cleared"
        case .skipped: return "Not run"
        case .failed: return "Couldn't finish"
        }
    }
}

/// Live memory use, shown on the Free Up RAM intro.
struct ToolboxMemoryMeter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let memory = model.monitor.memory
        let pressure = model.monitor.snapshot.memoryPressure
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Memory in use")
                    .font(SpruceFont.caption.weight(.semibold))
                    .foregroundStyle(PrismInk(contrast).secondary)
                Spacer()
                Text(memory.total > 0 ? "\(ByteFormat.string(memory.used)) of \(ByteFormat.string(memory.total))" : "Measuring…")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.primary)
            }
            PrismLinearProgress(value: memory.total > 0 ? memory.usedFraction : nil, module: .toolbox, height: 6)
            HStack(spacing: Spacing.xs) {
                Circle().fill(color(pressure)).frame(width: 7, height: 7)
                Text("Memory pressure: \(label(pressure))")
                    .font(SpruceFont.caption)
                    .foregroundStyle(PrismInk(contrast).tertiary)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: 360)
        .prismSurface(radius: Radius.row)
    }

    private func label(_ pressure: SystemSnapshot.MemoryPressure) -> String {
        switch pressure {
        case .normal: return "normal"
        case .warning: return "elevated"
        case .critical: return "critical"
        }
    }

    private func color(_ pressure: SystemSnapshot.MemoryPressure) -> Color {
        switch pressure {
        case .normal: return StatusColor.success
        case .warning: return StatusColor.warning
        case .critical: return StatusColor.danger
        }
    }
}

// MARK: - Empty Trash

/// Measures the Trash, previews what's in it, and erases it after confirmation.
struct ToolboxEmptyTrashScreen: View {
    @Bindable var trash: ToolboxTrashModel
    var onBack: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ToolboxToolFrame(onBack: onBack) {
            ZStack {
                phaseContent
                    .id(phaseKey)
                    .transition(.prismPhase(reduceMotion: reduceMotion))
            }
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: phaseKey)
        }
        .onAppear { trash.refreshIfIdle() }
        .confirmationDialog("Empty the Trash?", isPresented: $trash.confirming, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { trash.empty(monitor: model.monitor) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(CountFormat.items(trash.summary.itemCount)) (\(ByteFormat.string(trash.summary.bytes))) will be erased permanently. This can't be undone.")
        }
    }

    private var phaseKey: String {
        switch trash.phase {
        case .measuring: return "measuring"
        case .ready: return trash.summary.needsAccess ? "access" : (trash.summary.itemCount == 0 ? "empty" : "ready")
        case .emptying: return "emptying"
        case .done: return "done"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch trash.phase {
        case .measuring:
            ScanningView(module: .toolbox, progress: ScanProgress(fraction: nil, message: "Measuring the Trash…"),
                         title: "Measuring…", showsBytes: false)
        case .ready:
            if trash.summary.needsAccess {
                ToolboxTrashAccessView {
                    model.refreshPermissions()
                    trash.refresh()
                }
            } else if trash.summary.itemCount == 0 {
                EmptyStateView(module: .toolbox, title: "The Trash is empty", message: "There's nothing to erase.",
                               actionTitle: "Check Again", action: { trash.refresh() })
            } else {
                ToolboxTrashReadyView(summary: trash.summary, isBusy: model.monitor.isEmptyingTrash) {
                    trash.confirming = true
                }
            }
        case .emptying:
            ScanningView(module: .toolbox, progress: ScanProgress(fraction: nil, message: "Erasing the items in the Trash…"),
                         title: "Emptying…", showsBytes: false)
        case .done(let outcome):
            DoneView(module: .toolbox, outcome: outcome,
                     headline: outcome.processedCount == 0 && outcome.failures.isEmpty ? "The Trash was already empty" : nil) {
                trash.acknowledge()
            }
        }
    }
}

struct ToolboxTrashReadyView: View {
    var summary: ToolboxTrashSummary
    var isBusy: Bool
    var onEmpty: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: Spacing.topInset + Spacing.xl)
            HeroLens(module: .toolbox, size: 110, glyph: "trash.fill", parallax: false)
                .frame(height: 110 * 1.25)
            VStack(spacing: Spacing.xxs) {
                PrismMetricText(text: ByteFormat.string(summary.bytes), font: SpruceFont.metricXL,
                                unitFont: .system(size: 20, weight: .medium))
                Text(countLine)
                    .font(SpruceFont.headline)
                    .foregroundStyle(PrismInk(contrast).secondary)
            }
            largestList
            HStack(spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StatusColor.warning)
                Text("Emptying erases these items for good. Put back anything you still need first.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                PrismTextButton(title: "Open in Finder", symbol: "arrow.up.right", module: .toolbox) {
                    NSWorkspace.shared.open(ToolboxTrash.url)
                }
            }
            Spacer(minLength: Spacing.l)
            ActionOrb(title: "Empty", subtitle: ByteFormat.string(summary.bytes), module: .toolbox,
                      isBusy: isBusy, isEnabled: !isBusy, diameter: 96, isReady: true, action: onEmpty)
                .padding(.bottom, Spacing.orbBottom)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.contentInset)
    }

    private var countLine: String {
        var line = "in \(CountFormat.items(summary.itemCount))"
        if summary.fileCount > summary.itemCount {
            line += " · \(CountFormat.items(summary.fileCount, singular: "file")) inside"
        }
        return line
    }

    private var largestList: some View {
        GlassCard(padding: Spacing.s, radius: Radius.container) {
            VStack(spacing: 0) {
                ForEach(summary.largest) { entry in
                    HStack(spacing: Spacing.m) {
                        ItemIcon(url: URL(fileURLWithPath: entry.path), symbol: entry.isDirectory ? "folder" : "doc", size: 22)
                        Text(entry.name)
                            .font(SpruceFont.body)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Spacing.m)
                        SizeBadge(bytes: entry.bytes)
                    }
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 5)
                }
                if summary.itemCount > summary.largest.count {
                    Text("and \(CountFormat.items(summary.itemCount - summary.largest.count, singular: "more item", plural: "more items"))")
                        .font(SpruceFont.caption)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, 5)
                }
            }
        }
        .frame(maxWidth: 520)
    }
}

struct ToolboxTrashAccessView: View {
    var onCheckAgain: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.m) {
            HeroLens(module: .toolbox, size: 120, mood: .limited, parallax: false)
            Text("Spruce can't see inside the Trash")
                .font(SpruceFont.title)
                .foregroundStyle(Ink.primary)
            Text("macOS keeps the Trash private unless Spruce has Full Disk Access. Allow it in System Settings, then check again.")
                .font(SpruceFont.body)
                .foregroundStyle(PrismInk(contrast).secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.s) {
                CapsuleButton(title: "Allow Full Disk Access", symbol: "lock.open", prominent: true) {
                    Permissions.openFullDiskAccessSettings()
                }
                CapsuleButton(title: "Check Again", symbol: "arrow.clockwise", action: onCheckAgain)
            }
            .padding(.top, Spacing.s)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
