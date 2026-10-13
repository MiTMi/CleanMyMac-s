import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Storage

/// Startup-disk availability and condition (SMART, life left, temperature), Trash size
/// with Empty Trash, and Clean Up.
@MainActor
struct MonitorStorageCard: View {
    var monitor: SystemMonitor
    var settings: SettingsStore
    var onCleanUp: () -> Void

    @State private var confirmingEmpty = false
    @State private var note: MonitorNote?

    var body: some View {
        let snap = monitor.snapshot
        let status = diskStatus(snap)
        let tint = status == .good ? MonitorTheme.storageTint : MonitorTheme.color(for: status)
        MonitorCard(title: "Storage", symbol: "internaldrive", tint: tint) {
            MonitorAlertToggle(isOn: settings.settings.notifyLowDisk, label: "Low-disk alerts") {
                settings.settings.notifyLowDisk.toggle()
            }
        } content: {
            if snap.diskTotal > 0 {
                capacity(snap, tint: tint)
            } else {
                MonitorPlaceholderLine(text: "Reading the startup disk…")
            }
            if let health = monitor.diskHealth, health.hasDetails {
                MonitorDiskHealthLine(health: health, inCelsius: settings.settings.temperatureUnitCelsius)
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
            trashRow
            if let note {
                MonitorNoteView(note: note)
            }
        }
        .animation(Motion.standard, value: confirmingEmpty)
        .animation(Motion.standard, value: note)
    }

    private func diskStatus(_ snap: SystemSnapshot) -> MonitorHealthStatus {
        if monitor.diskHealth?.isFailing == true { return .critical }
        guard snap.diskTotal > 0 else { return .good }
        if MonitorDiskMath.isCritical(available: snap.diskAvailable, total: snap.diskTotal) { return .critical }
        let percent = MonitorDiskMath.freePercent(available: snap.diskAvailable, total: snap.diskTotal)
        return percent < Double(settings.settings.lowDiskThresholdPercent) ? .attention : .good
    }

    @ViewBuilder
    private func capacity(_ snap: SystemSnapshot, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            PrismMetricText(text: ByteFormat.string(snap.diskAvailable), font: SpruceFont.metricS,
                            unitFont: SpruceFont.caption.weight(.semibold))
                .fixedSize()
            Text("available")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
            Spacer(minLength: 4)
            Text("of \(ByteFormat.string(snap.diskTotal))")
                .font(SpruceFont.captionDigits)
                .foregroundStyle(Ink.tertiary)
        }
        MonitorBar(segments: [MonitorBarSegment(id: "used", fraction: snap.diskUsedFraction, color: tint)])
            .accessibilityElement()
            .accessibilityLabel("Startup disk")
            .accessibilityValue("\(ByteFormat.string(snap.diskAvailable)) available of \(ByteFormat.string(snap.diskTotal))")
        if snap.diskPurgeable > 0 {
            Text("Includes \(ByteFormat.string(snap.diskPurgeable)) of purgeable space macOS frees on demand")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var trashRow: some View {
        switch monitor.trash {
        case .measuring:
            HStack(spacing: Spacing.s) {
                MonitorPlaceholderLine(text: "Measuring the Trash…")
                Spacer(minLength: 4)
                cleanUpButton
            }
        case .needsAccess:
            HStack(spacing: Spacing.s) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(StatusColor.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trash size needs Full Disk Access")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                    PrismTextButton(title: "Grant access", symbol: "arrow.up.forward") {
                        Permissions.openFullDiskAccessSettings()
                    }
                }
                Spacer(minLength: 4)
                cleanUpButton
            }
        case .measured(let bytes):
            if confirmingEmpty {
                HStack(spacing: Spacing.s) {
                    Text("Erase \(ByteFormat.string(bytes)) for good?")
                        .font(SpruceFont.caption.weight(.semibold))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    CapsuleButton(title: "Cancel") { confirmingEmpty = false }
                    CapsuleButton(title: "Empty", destructive: true) { emptyTrash() }
                }
            } else {
                HStack(spacing: Spacing.s) {
                    Image(systemName: bytes > 0 ? "trash.fill" : "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Trash")
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.tertiary)
                        Text(bytes > 0 ? ByteFormat.string(bytes) : "Empty")
                            .font(SpruceFont.bodyStrong.monospacedDigit())
                            .foregroundStyle(Ink.primary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 4)
                    if monitor.isEmptyingTrash {
                        ProgressView().controlSize(.small)
                    } else {
                        CapsuleButton(title: "Empty Trash") { confirmingEmpty = true }
                            .disabled(bytes == 0)
                            .help("Permanently erase everything in the Trash")
                    }
                    cleanUpButton
                }
            }
        }
    }

    private var cleanUpButton: some View {
        CapsuleButton(title: "Clean Up", prominent: true, action: onCleanUp)
            .help("Open Cleanup in Spruce")
    }

    private func emptyTrash() {
        confirmingEmpty = false
        Task {
            let outcome = await monitor.emptyTrash()
            let result: MonitorNote
            if let failure = outcome.failures.first {
                let count = outcome.failures.count
                result = .failure(count == 1 ? "\u{201C}\(failure.title)\u{201D} couldn't be removed: \(failure.reason)"
                                             : "\(count) items couldn't be removed. \(failure.reason)")
                SpruceSound.play(.error, force: true)
            } else if outcome.freedBytes > 0 {
                result = .success("Freed \(ByteFormat.string(outcome.freedBytes)) from the Trash")
                SpruceSound.play(.cleanComplete, force: true)
            } else {
                result = .success("The Trash is empty")
            }
            show(result)
        }
    }

    private func show(_ value: MonitorNote) {
        note = value
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if note?.id == value.id { note = nil }
        }
    }
}

/// "Disk health: Healthy · 98% life left · 38 °C", or a red warning when SMART reports
/// the startup disk as failing.
@MainActor
struct MonitorDiskHealthLine: View {
    var health: MonitorDiskHealth
    var inCelsius: Bool

    var body: some View {
        let failing = health.isFailing
        let verified = health.condition == .verified
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: failing ? "exclamationmark.triangle.fill" : (verified ? "checkmark.seal.fill" : "thermometer.medium"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(failing ? StatusColor.danger : (verified ? StatusColor.success : Ink.tertiary))
            Text(failing ? "The startup disk reports it is failing. Back up your data now."
                         : "Disk health: \(health.summary(inCelsius: inCelsius))")
                .font(failing ? SpruceFont.caption.weight(.semibold) : SpruceFont.caption)
                .foregroundStyle(failing ? StatusColor.danger : Ink.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help("Condition reported by the startup disk (SMART)")
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Memory

/// Pressure gauge, used / total, swap, the App · Wired · Compressed split, Free Up
/// and the three apps using the most memory.
@MainActor
struct MonitorMemoryCard: View {
    var monitor: SystemMonitor
    var settings: SettingsStore

    @State private var note: MonitorNote?

    var body: some View {
        let snap = monitor.snapshot
        let memory = monitor.memory
        let pressureColor = MonitorTheme.color(for: snap.memoryPressure)
        let tint = snap.memoryPressure == .normal ? MonitorTheme.memoryTint : pressureColor
        MonitorCard(title: "Memory", symbol: "memorychip", tint: tint) {
            MonitorAlertToggle(isOn: settings.settings.notifyHighMemory, label: "Memory pressure alerts") {
                settings.settings.notifyHighMemory.toggle()
            }
        } content: {
            if memory.total > 0 {
                summary(snap: snap, memory: memory, pressureColor: pressureColor)
                MonitorBar(segments: [
                    MonitorBarSegment(id: "app", fraction: fraction(memory.app, of: memory.total), color: MonitorTheme.memoryTint),
                    MonitorBarSegment(id: "wired", fraction: fraction(memory.wired, of: memory.total), color: MonitorTheme.wiredTint),
                    MonitorBarSegment(id: "compressed", fraction: fraction(memory.compressed, of: memory.total),
                                      color: MonitorTheme.compressedTint),
                ])
                HStack(spacing: Spacing.s) {
                    MonitorLegendItem(color: MonitorTheme.memoryTint, label: "App", value: ByteFormat.string(memory.app))
                    MonitorLegendItem(color: MonitorTheme.wiredTint, label: "Wired", value: ByteFormat.string(memory.wired))
                    MonitorLegendItem(color: MonitorTheme.compressedTint, label: "Compressed",
                                      value: ByteFormat.string(memory.compressed))
                }
                topApps
            } else {
                MonitorPlaceholderLine(text: "Reading memory…")
            }
            if let note {
                MonitorNoteView(note: note)
            }
        }
        .animation(Motion.standard, value: note)
    }

    @ViewBuilder
    private func summary(snap: SystemSnapshot, memory: MonitorMemoryBreakdown, pressureColor: Color) -> some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            MonitorPressureGauge(fraction: memory.usedFraction, color: pressureColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(MonitorFormat.pressure(snap.memoryPressure))
                    .font(SpruceFont.metricS)
                    .foregroundStyle(Ink.primary)
                Text("\(ByteFormat.string(memory.used)) of \(ByteFormat.string(memory.total)) used")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                Text(memory.swapUsed > 0 ? "Swap \(ByteFormat.string(memory.swapUsed))" : "No swap in use")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(memory.swapUsed > memory.total / 2 ? StatusColor.warning : Ink.tertiary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Memory pressure \(MonitorFormat.pressure(snap.memoryPressure))")
            Spacer(minLength: 4)
            if monitor.isFreeingMemory {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Freeing…")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.secondary)
                }
            } else {
                CapsuleButton(title: "Free Up") { freeUp() }
                    .help("Ask macOS to purge inactive memory (asks for your administrator password)")
            }
        }
    }

    @ViewBuilder
    private var topApps: some View {
        let top = Array(monitor.topByMemory.prefix(3))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(top) { process in
                    MonitorProcessRow(process: process, value: ByteFormat.string(process.memory))
                }
            }
            .padding(.top, 2)
        }
    }

    private func fraction(_ part: Int64, of total: Int64) -> Double {
        total > 0 ? Double(part) / Double(total) : 0
    }

    private func freeUp() {
        Task {
            let result = await monitor.freeUpMemory()
            switch result {
            case .freed(let bytes):
                show(bytes > 0 ? .success("Freed \(ByteFormat.string(bytes)) of memory")
                               : .success("Memory was already in good shape"))
                SpruceSound.play(.cleanComplete, force: true)
            case .cancelled:
                break
            case .failed(let message):
                show(.failure(message))
                SpruceSound.play(.error, force: true)
            }
        }
    }

    private func show(_ value: MonitorNote) {
        note = value
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if note?.id == value.id { note = nil }
        }
    }
}
