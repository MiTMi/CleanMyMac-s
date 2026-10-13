import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Usage bar

/// Two-tone bar: downloaded to this Mac (solid accent) versus stored only in the
/// cloud (hatched, translucent).
struct CloudStorageUsageBar: View {
    let stats: CloudStorageStats
    var height: CGFloat = 10

    var body: some View {
        let palette = ModuleID.cloudStorage.palette
        GeometryReader { geo in
            let localWidth = Self.localWidth(stats: stats, total: geo.size.width, minimum: height)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                CloudStorageHatch(color: palette.accent2.opacity(0.28), spacing: 6)
                    .clipShape(Capsule())
                    .opacity(stats.cloudOnlyBytes > 0 ? 1 : 0)
                Capsule()
                    .fill(LinearGradient(colors: [palette.accent, palette.glow], startPoint: .leading, endPoint: .trailing))
                    .frame(width: localWidth)
                    .animation(Motion.standard, value: stats.localBytes)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Downloaded to this Mac")
        .accessibilityValue(CloudStorageText.localLine(stats))
    }

    /// Width of the downloaded segment; any downloaded content stays visible.
    static func localWidth(stats: CloudStorageStats, total: CGFloat, minimum: CGFloat) -> CGFloat {
        guard stats.localBytes > 0, total > 0 else { return 0 }
        let proportional = total * CGFloat(stats.localFraction)
        return min(total, max(minimum, proportional))
    }
}

/// Diagonal hatching used for cloud-only space.
struct CloudStorageHatch: View {
    let color: Color
    var spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
        .background(color.opacity(0.35))
    }
}

/// Legend dot + label + value.
struct CloudStorageLegend: View {
    let title: String
    let value: String
    let hatched: Bool

    var body: some View {
        let palette = ModuleID.cloudStorage.palette
        HStack(spacing: 6) {
            Group {
                if hatched {
                    CloudStorageHatch(color: palette.accent2.opacity(0.5), spacing: 3)
                } else {
                    palette.accent
                }
            }
            .frame(width: 10, height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(title)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
            Text(value)
                .font(SpruceFont.captionDigits.weight(.semibold))
                .foregroundStyle(Ink.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sidebar

/// The scanned providers, each with its local share.
struct CloudStorageProviderSidebar: View {
    @Bindable var screen: CloudStorageScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Cloud folders", trailing: CountFormat.grouped(screen.reports.count))
                .padding(.horizontal, Spacing.s)
                .padding(.top, Spacing.s)
            ScrollView {
                VStack(spacing: Spacing.xs) {
                    ForEach(screen.reports) { report in
                        CloudStorageSidebarRow(report: report,
                                               isSelected: screen.selectedReport?.id == report.id,
                                               isRescanning: screen.rescanning.contains(report.id),
                                               selectedCount: report.largestLocal.filter { screen.isSelected($0) }.count) {
                            screen.selectedReportID = report.id
                        }
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.bottom, Spacing.s)
            }
            .scrollIndicators(.automatic)
            Spacer(minLength: 0)
            totals
        }
        .prismSurface(radius: Radius.container)
    }

    private var totals: some View {
        let overview = screen.overview
        return VStack(alignment: .leading, spacing: 4) {
            Text("ALL CLOUD FOLDERS")
                .font(SpruceFont.overline)
                .tracking(0.8)
                .foregroundStyle(Ink.tertiary)
            CloudStorageUsageBar(stats: overview.stats, height: 6)
            Text(CloudStorageText.localLine(overview.stats))
                .font(SpruceFont.captionDigits)
                .foregroundStyle(Ink.secondary)
        }
        .padding(Spacing.m)
    }
}

struct CloudStorageSidebarRow: View {
    let report: CloudStorageProviderReport
    let isSelected: Bool
    let isRescanning: Bool
    let selectedCount: Int
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        let provider = report.provider
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Spacing.s) {
                    PrismCategoryBadge(symbol: provider.kind.symbol, module: .cloudStorage, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(provider.name)
                            .font(SpruceFont.bodyStrong)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                        Text(provider.account ?? provider.locationLine)
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if isRescanning {
                        ProgressView().controlSize(.small)
                    } else if selectedCount > 0 {
                        Text(CountFormat.grouped(selectedCount))
                            .font(SpruceFont.captionDigits.weight(.semibold))
                            .foregroundStyle(Ink.onBright)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(ModuleID.cloudStorage.palette.accentText))
                            .help("\(CountFormat.items(selectedCount, singular: "file")) selected")
                    }
                }
                CloudStorageUsageBar(stats: report.stats, height: 5)
                Text(rowLine)
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            .padding(Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(isSelected ? Ink.selectedFill : (hovering ? Ink.subtleFill : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(PrismPressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityLabel("\(provider.displayName), \(rowLine)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowLine: String {
        if report.accessDenied { return "No access" }
        return "\(ByteFormat.string(report.stats.localBytes)) on this Mac"
    }
}

// MARK: - File row

/// One file in the results list.
struct CloudStorageFileRow: View {
    let record: CloudStorageFileRecord
    let provider: CloudStorageProvider
    let eligibility: CloudStorageEligibility
    let isSelected: Bool
    let isDownloading: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void
    let onFreeUp: () -> Void
    let onDownload: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            leadingControl
                .frame(width: 20)
            ItemIcon(url: record.isCloudOnly ? nil : record.url,
                     symbol: CloudStorageFileKind.symbol(for: record), size: 28, module: .cloudStorage)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(SpruceFont.body.weight(.medium))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailLine)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.s)
            statusChip
            if hovering {
                hoverActions
                    .transition(.opacity)
            }
            sizeColumn
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(hovering ? Ink.subtleFill : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .onTapGesture(count: 2) { onReveal() }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var leadingControl: some View {
        if record.isCloudOnly {
            Image(systemName: isDownloading ? "arrow.down.circle" : "icloud")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.tertiary)
                .help(isDownloading ? "Downloading" : "Stored only in the cloud")
        } else if eligibility.canSelect {
            SpruceCheckbox(isOn: isSelected, module: .cloudStorage, label: record.name, action: onToggle)
        } else {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
                .help(eligibility.reason ?? "Can't be freed right now")
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if record.isCloudOnly {
            if isDownloading {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Downloading")
                        .font(SpruceFont.caption.weight(.medium))
                        .foregroundStyle(Ink.secondary)
                }
            }
        } else {
            switch eligibility {
            case .recommended:
                PrismChip(text: "Suggested", color: StatusColor.success, symbol: "checkmark")
                    .help("Synced and not changed or opened recently")
            case .review(let reason):
                PrismChip(text: "Review", color: StatusColor.warning, symbol: "eye")
                    .help(reason)
            case .blocked(let reason):
                PrismChip(text: shortBlockedText(reason), color: StatusColor.danger, symbol: "exclamationmark")
                    .help(reason)
            }
        }
    }

    private func shortBlockedText(_ reason: String) -> String {
        if record.status.hasConflicts { return "Conflict" }
        if record.status.isUploading || record.status.isUploaded == false { return "Uploading" }
        if record.status.isDownloading || isDownloading { return "Downloading" }
        if provider.mechanism == .syncFolder { return "Always local" }
        return "Locked"
    }

    @ViewBuilder
    private var hoverActions: some View {
        HStack(spacing: 2) {
            PrismIconButton(symbol: "magnifyingglass", help: "Show in Finder", action: onReveal)
            if record.isCloudOnly {
                if !isDownloading {
                    PrismIconButton(symbol: "arrow.down.circle", help: "Download to this Mac", action: onDownload)
                }
            } else if eligibility.canSelect {
                PrismIconButton(symbol: "icloud.and.arrow.up", help: "Free up this file's local copy", action: onFreeUp)
            }
        }
    }

    private var sizeColumn: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(ByteFormat.string(record.isCloudOnly ? record.cloudBytes : record.localBytes))
                .font(SpruceFont.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Ink.primary)
            Text(record.isCloudOnly ? "in the cloud" : "on this Mac")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Show in Finder", action: onReveal)
        if record.isCloudOnly {
            Button("Download to This Mac", action: onDownload)
                .disabled(isDownloading)
        } else {
            Button(isSelected ? "Deselect" : "Select", action: onToggle)
                .disabled(!eligibility.canSelect)
            Button("Free Up Locally…", action: onFreeUp)
                .disabled(!eligibility.canSelect)
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.path, forType: .string)
        }
    }

    private var detailLine: String {
        var parts = [((record.relativePath(in: provider) as NSString).deletingLastPathComponent)]
        if parts[0].isEmpty { parts[0] = provider.name }
        if record.isPackage { parts.append(CountFormat.items(record.fileCount, singular: "file")) }
        if let lastUsed = record.lastUsed {
            parts.append("opened \(DurationFormat.relative(lastUsed))")
        } else {
            parts.append("changed \(DurationFormat.relative(record.modified))")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        let size = ByteFormat.string(record.isCloudOnly ? record.cloudBytes : record.localBytes)
        let place = record.isCloudOnly ? "only in the cloud" : "on this Mac"
        var text = "\(record.name), \(size) \(place)"
        if !record.isCloudOnly {
            text += isSelected ? ", selected" : ""
            if let reason = eligibility.reason { text += ", \(reason)" }
        }
        return text
    }
}

/// SF Symbol for a file by its extension (used where reading the real icon could
/// touch an online-only file).
enum CloudStorageFileKind {
    static func symbol(for record: CloudStorageFileRecord) -> String {
        if record.isPackage { return "shippingbox" }
        let ext = (record.name as NSString).pathExtension.lowercased()
        switch ext {
        case "mov", "mp4", "m4v", "avi", "mkv", "webm", "mts", "braw", "r3d": return "film"
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd", "webp":
            return "photo"
        case "mp3", "m4a", "wav", "aif", "aiff", "flac", "caf", "aac", "ogg", "als": return "waveform"
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "iso", "pkg": return "doc.zipper"
        case "pdf": return "doc.richtext"
        case "key", "ppt", "pptx": return "play.rectangle"
        case "numbers", "xls", "xlsx", "csv": return "tablecells"
        default: return "doc"
        }
    }
}

// MARK: - Notices

/// An inline message card with an optional action.
struct CloudStorageNotice: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                Text(message)
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s)
            if let actionTitle, let action {
                CapsuleButton(title: actionTitle, action: action)
            }
        }
        .padding(Spacing.m)
        .prismSurface(radius: Radius.row, tint: tint)
    }
}
