import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - CPU

/// Total load with a 60-sample sparkline (spikes in red), per-core bars, load
/// average and the three busiest apps.
@MainActor
struct MonitorCPUCard: View {
    var monitor: SystemMonitor

    var body: some View {
        let load = monitor.cpuLoad
        let history = monitor.cpuHistory.elements
        let thermal = monitor.snapshot.thermalState
        MonitorCard(title: "CPU", symbol: "cpu", tint: MonitorTheme.cpuTint) {
            MonitorAlertToggle(isOn: monitor.notifyHighCPU, label: "Busy-app alerts") {
                monitor.notifyHighCPU.toggle()
            }
        } content: {
            if history.isEmpty {
                MonitorPlaceholderLine(text: "Measuring CPU load…")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(MonitorFormat.percent(load.total))
                        .font(SpruceFont.metricS)
                        .foregroundStyle(Ink.primary)
                        .contentTransition(.numericText())
                    Text("user \(MonitorFormat.percent(load.user)) · system \(MonitorFormat.percent(load.system))")
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    MonitorThermalBadge(state: thermal)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("CPU load \(MonitorFormat.percent(load.total))")
                MonitorSparkline(values: history, ceiling: 1, color: MonitorTheme.cpuTint,
                                 highlights: MonitorCPUMath.spikeMask(history))
                    .frame(height: 34)
                if load.perCore.count > 1 {
                    MonitorCoreStrip(loads: load.perCore, color: MonitorTheme.cpuTint)
                }
                Text(detailLine)
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                topApps
            }
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let oneMinute = monitor.loadAverage.first {
            parts.append("Load " + String(format: "%.2f", oneMinute))
        }
        if monitor.coreCount > 0 { parts.append("\(monitor.coreCount) cores") }
        parts.append("Last 2 min")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var topApps: some View {
        let top = Array(monitor.topByCPU.prefix(3))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(top) { process in
                    MonitorProcessRow(process: process, value: MonitorFormat.cpuPercent(process.cpuPercent),
                                      valueColor: process.cpuPercent >= 80 ? StatusColor.warning : Ink.secondary)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// "Cool" / "Warm" / "Hot" from `ProcessInfo.thermalState`.
@MainActor
struct MonitorThermalBadge: View {
    var state: String

    var body: some View {
        let color: Color = {
            switch state {
            case "critical": return StatusColor.danger
            case "serious": return StatusColor.warning
            case "fair": return StatusColor.info
            default: return StatusColor.success
            }
        }()
        HStack(spacing: 4) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 9, weight: .semibold))
            Text(MonitorFormat.thermal(state))
                .font(SpruceFont.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .help("Thermal state reported by macOS")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thermal state \(MonitorFormat.thermal(state))")
    }
}

// MARK: - Network

/// Live ↓/↑ throughput with a dual sparkline and totals for this session.
@MainActor
struct MonitorNetworkCard: View {
    var monitor: SystemMonitor

    var body: some View {
        let snap = monitor.snapshot
        let down = monitor.downHistory.elements
        let up = monitor.upHistory.elements
        let ceiling = max(down.max() ?? 0, up.max() ?? 0, 20_000) * 1.1
        MonitorCard(title: "Network", symbol: "network", tint: MonitorTheme.networkTint) {
            if down.isEmpty {
                MonitorPlaceholderLine(text: "Measuring throughput…")
            } else {
                HStack(spacing: Spacing.l) {
                    rate(symbol: "arrow.down", value: snap.networkDownBytesPerSec, color: MonitorTheme.networkTint,
                         label: "Download")
                    rate(symbol: "arrow.up", value: snap.networkUpBytesPerSec, color: MonitorTheme.networkUpTint,
                         label: "Upload")
                    Spacer(minLength: 0)
                }
                ZStack {
                    MonitorSparkline(values: down, ceiling: ceiling, color: MonitorTheme.networkTint)
                    MonitorSparkline(values: up, ceiling: ceiling, color: MonitorTheme.networkUpTint, filled: false,
                                     lineWidth: 1.2)
                }
                .frame(height: 30)
                Text("This session: \(ByteFormat.string(Int64(clamping: monitor.sessionDownloaded))) down · \(ByteFormat.string(Int64(clamping: monitor.sessionUploaded))) up")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func rate(symbol: String, value: Double, color: Color, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
            Text(MonitorFormat.rate(value))
                .font(SpruceFont.bodyStrong.monospacedDigit())
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(MonitorFormat.rate(value))")
    }
}

// MARK: - Battery / UPS

/// Shown only when the Mac has a battery, or a UPS is attached (Mac mini).
@MainActor
struct MonitorPowerCard: View {
    var power: MonitorPowerInfo

    var body: some View {
        let level = power.level ?? 0
        let tint = tintColor(level)
        MonitorCard(title: power.title, symbol: symbol(level), tint: tint) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(power.level.map { MonitorFormat.percent($0) } ?? "—")
                    .font(SpruceFont.metricS)
                    .foregroundStyle(Ink.primary)
                    .contentTransition(.numericText())
                Text(power.statusText)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if power.level != nil {
                MonitorBar(segments: [MonitorBarSegment(id: "charge", fraction: level, color: tint)])
            }
            if let details = detailLine {
                HStack(spacing: 6) {
                    Text(details)
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                    if power.needsService {
                        StatusPill(text: "Service recommended", status: .attention)
                    }
                }
            }
        }
    }

    private var detailLine: String? {
        var parts: [String] = []
        if let health = power.health { parts.append("Health \(MonitorFormat.percent(health))") }
        if let cycles = power.cycleCount { parts.append("\(CountFormat.grouped(cycles)) cycles") }
        if power.kind == .ups { parts.append(power.name) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func tintColor(_ level: Double) -> Color {
        guard !power.onExternalPower, power.level != nil else { return MonitorTheme.powerTint }
        if level <= 0.1 { return StatusColor.danger }
        if level <= 0.2 { return StatusColor.warning }
        return MonitorTheme.powerTint
    }

    private func symbol(_ level: Double) -> String {
        if power.kind == .ups { return "bolt.fill" }
        if power.isCharging { return "battery.100percent.bolt" }
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Devices

/// Accessories that report a battery level (low battery, < 20 %, first and in red), then
/// mounted external drives with free space and Eject (Eject All when there are several).
@MainActor
struct MonitorDevicesCard: View {
    var monitor: SystemMonitor

    @State private var note: MonitorNote?
    @State private var ejectingAll = false
    private let visibleLimit = 3

    var body: some View {
        let devices = monitor.devices
        let volumes = monitor.volumes
        let lowCount = devices.filter(\.isLowBattery).count
        MonitorCard(title: "Devices", symbol: devices.isEmpty ? "externaldrive" : "dot.radiowaves.left.and.right",
                    tint: lowCount > 0 ? StatusColor.danger : MonitorTheme.devicesTint) {
            if volumes.count > 1 {
                ejectAllButton
            }
        } content: {
            if !devices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(devices.prefix(visibleLimit))) { device in
                        MonitorDeviceRow(device: device)
                    }
                }
                if devices.count > visibleLimit {
                    Text("+\(devices.count - visibleLimit) more")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                }
            }
            if !devices.isEmpty && !volumes.isEmpty {
                Rectangle().fill(Ink.hairline).frame(height: 1)
            }
            if !volumes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(volumes) { volume in
                        MonitorVolumeRow(volume: volume,
                                         isEjecting: ejectingAll || monitor.ejectingVolumes.contains(volume.id)) {
                            eject(volume)
                        }
                    }
                }
            }
            if let note {
                MonitorNoteView(note: note)
            }
        }
        .animation(Motion.standard, value: note)
        .animation(Motion.standard, value: volumes.map(\.id))
    }

    private var ejectAllButton: some View {
        Button {
            ejectAll()
        } label: {
            Label("Eject All", systemImage: "eject")
                .font(SpruceFont.caption.weight(.medium))
                .foregroundStyle(ejectingAll ? Ink.disabled : Ink.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(PrismPressStyle(pressedScale: 0.95))
        .disabled(ejectingAll)
        .help("Eject every external drive")
    }

    private func eject(_ volume: MonitorVolume) {
        Task {
            switch await monitor.eject(volume) {
            case .ejected:
                show(.success("Ejected \u{201C}\(volume.name)\u{201D}. It's safe to unplug."))
            case .failed(let message):
                show(.failure(message))
                SpruceSound.play(.error, force: true)
            }
        }
    }

    private func ejectAll() {
        ejectingAll = true
        Task {
            let count = monitor.volumes.count
            let failures = await monitor.ejectAll()
            ejectingAll = false
            if let first = failures.first {
                show(.failure(failures.count == 1 ? first : "\(failures.count) drives couldn't be ejected. \(first)"))
                SpruceSound.play(.error, force: true)
            } else {
                show(.success(count == 1 ? "Ejected 1 drive. It's safe to unplug." : "Ejected \(count) drives. They're safe to unplug."))
            }
        }
    }

    private func show(_ value: MonitorNote) {
        note = value
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if note?.id == value.id { note = nil }
        }
    }
}

/// "Backup ……… 312 GB free of 1 TB  ⏏" with a thin used-space bar.
@MainActor
struct MonitorVolumeRow: View {
    var volume: MonitorVolume
    var isEjecting: Bool
    var onEject: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: volume.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Ink.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(volume.name)
                        .font(SpruceFont.callout)
                        .foregroundStyle(Ink.primary.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(volume.capacityText)
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                }
                MonitorBar(segments: [MonitorBarSegment(id: "used", fraction: volume.usedFraction,
                                                        color: MonitorTheme.storageTint)], height: 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(volume.name), \(volume.capacityText)")
            if isEjecting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
            } else {
                Button(action: onEject) {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PrismPressStyle(pressedScale: 0.9))
                .help("Eject \u{201C}\(volume.name)\u{201D}")
                .accessibilityLabel("Eject \(volume.name)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

@MainActor
struct MonitorDeviceRow: View {
    var device: MonitorDevice

    var body: some View {
        let color = device.isLowBattery ? StatusColor.danger : MonitorTheme.devicesTint
        HStack(spacing: Spacing.s) {
            Image(systemName: device.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Ink.secondary)
                .frame(width: 18)
            Text(device.name)
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.primary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if let percent = device.batteryPercent {
                MonitorBar(segments: [MonitorBarSegment(id: "battery", fraction: Double(percent) / 100, color: color)],
                           height: 4)
                    .frame(width: 34)
                Text("\(percent)%")
                    .font(SpruceFont.captionDigits.weight(.medium))
                    .foregroundStyle(device.isLowBattery ? StatusColor.danger : Ink.secondary)
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.batteryPercent.map { "\(device.name), battery \($0) percent" } ?? device.name)
    }
}
