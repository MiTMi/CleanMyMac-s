import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Results: scanned providers on the left; the selected provider's local-versus-cloud
/// usage, an explanation of Free Up Locally and its largest files on the right; the
/// Free Up Locally orb in the footer.
struct CloudStorageResultsScreen: View {
    @Bindable var screen: CloudStorageScreenModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: "Cloud Storage", subtitle: subtitle, backTitle: "New Scan",
                         onBack: { screen.newScan() }, module: .cloudStorage,
                         trailing: AnyView(CloudStorageHeaderStats(overview: screen.overview)))
            HStack(alignment: .top, spacing: Spacing.m) {
                CloudStorageProviderSidebar(screen: screen)
                    .frame(width: 236)
                    .frame(maxHeight: .infinity)
                if let report = screen.selectedReport {
                    CloudStorageProviderPanel(screen: screen, report: report)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView(module: .cloudStorage, title: "No cloud folders scanned",
                                   message: "Start a new scan to measure your cloud folders.", symbol: "icloud",
                                   mood: .standard, actionTitle: "New Scan", action: { screen.newScan() })
                }
            }
            ResultsFooter(module: .cloudStorage, selectedBytes: screen.selectedBytes,
                          selectedCount: screen.selectedRecords.count, actionTitle: "Free Up Locally",
                          isEnabled: !screen.isBusy, totalBytes: screen.freeableListedBytes,
                          totalCount: screen.freeableListedCount, action: { screen.requestFreeUp() })
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var subtitle: String {
        let overview = screen.overview
        let folders = CountFormat.items(overview.providerCount, singular: "cloud folder")
        return "\(CloudStorageText.localLine(overview.stats)) · \(folders)"
    }
}

/// Header chips: downloaded versus cloud-only totals.
struct CloudStorageHeaderStats: View {
    let overview: CloudStorageOverview

    var body: some View {
        let palette = ModuleID.cloudStorage.palette
        HStack(spacing: Spacing.s) {
            PrismStatChip(symbol: "internaldrive.fill", value: ByteFormat.string(overview.stats.localBytes),
                          label: "On this Mac", tint: palette.accentText)
            PrismStatChip(symbol: "icloud.fill", value: ByteFormat.string(overview.stats.cloudOnlyBytes),
                          label: "Only in the cloud", tint: palette.accent2)
        }
    }
}

// MARK: - Provider panel

/// Everything about one provider.
struct CloudStorageProviderPanel: View {
    @Bindable var screen: CloudStorageScreenModel
    let report: CloudStorageProviderReport

    var body: some View {
        VStack(spacing: Spacing.m) {
            CloudStorageUsageCard(screen: screen, report: report)
            notices
            CloudStorageFileList(screen: screen, report: report)
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var notices: some View {
        let provider = report.provider
        if report.accessDenied {
            CloudStorageNotice(
                symbol: "lock.fill", tint: StatusColor.warning, title: "macOS didn't allow Spruce to read \(provider.name)",
                message: "Allow access when macOS asks, or turn on Full Disk Access for Spruce in System Settings › Privacy & Security, then scan again.",
                actionTitle: "Open Settings", action: { Permissions.openFullDiskAccessSettings() })
        } else if provider.mechanism == .syncFolder {
            CloudStorageNotice(
                symbol: "arrow.triangle.2.circlepath", tint: StatusColor.info, title: "This folder is always kept on this Mac",
                message: "\(provider.name)'s older sync folder stores every file locally, so there's nothing to free from here. In the \(provider.name) app, switch to online-only (streaming) files to save space.")
        } else if report.stats.unreadableFolderCount > 0 {
            CloudStorageNotice(
                symbol: "exclamationmark.lock", tint: StatusColor.warning, title: "Some folders couldn't be read",
                message: "\(CountFormat.items(report.stats.unreadableFolderCount, singular: "folder")) were skipped because macOS denied access. Totals may be lower than in Finder.",
                actionTitle: "Open Settings", action: { Permissions.openFullDiskAccessSettings() })
        } else if !report.isComplete {
            CloudStorageNotice(symbol: "pause.circle", tint: StatusColor.info, title: "Partial results",
                               message: "The scan was stopped before it finished. Scan again for complete totals.",
                               actionTitle: "Rescan", action: { screen.rescan(report) })
        }
    }
}

/// Local-versus-cloud summary with the eviction explanation.
struct CloudStorageUsageCard: View {
    @Bindable var screen: CloudStorageScreenModel
    let report: CloudStorageProviderReport

    @State private var showsExplanation = false

    var body: some View {
        let provider = report.provider
        let stats = report.stats
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .center, spacing: Spacing.m) {
                PrismCategoryBadge(symbol: provider.kind.symbol, module: .cloudStorage, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(SpruceFont.headline)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Text(provider.locationLine)
                        .font(SpruceFont.caption.monospacedDigit())
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: Spacing.s)
                CapsuleButton(title: "Open in Finder", symbol: "folder") { screen.openInFinder(provider) }
                if screen.rescanning.contains(report.id) {
                    ProgressView().controlSize(.small).frame(width: 28)
                } else {
                    PrismIconButton(symbol: "arrow.clockwise", help: "Scan \(provider.name) again") {
                        screen.rescan(report)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xl) {
                metric(ByteFormat.string(stats.localBytes), "on this Mac", color: Ink.primary)
                metric(ByteFormat.string(stats.cloudOnlyBytes), "only in the cloud", color: Ink.secondary)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(CountFormat.items(stats.localFileCount, singular: "file")) downloaded")
                    Text("\(CountFormat.items(stats.cloudOnlyFileCount, singular: "file")) online-only")
                    if stats.largeLocalCount > 0 {
                        Text("\(CountFormat.grouped(stats.largeLocalCount)) over \(ByteFormat.string(screen.engine.largeFileThreshold)) · \(ByteFormat.string(stats.largeLocalBytes))")
                    }
                }
                .font(SpruceFont.captionDigits)
                .foregroundStyle(Ink.tertiary)
            }
            CloudStorageUsageBar(stats: stats, height: 10)
            HStack(spacing: Spacing.l) {
                CloudStorageLegend(title: "Downloaded", value: PrismMetric.percentText(stats.localFraction), hatched: false)
                CloudStorageLegend(title: "Online-only", value: PrismMetric.percentText(stats.cloudBytes > 0 ? 1 - stats.localFraction : 0),
                                   hatched: true)
                if let unlisted = CloudStorageText.unlistedLine(stats) {
                    Text(unlisted)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .help("Online-only folders are never opened during a scan, so nothing is downloaded.")
                }
                Spacer(minLength: 0)
            }
            if provider.mechanism.canFreeUpLocally {
                explanation(provider)
            }
        }
        .padding(Spacing.l)
        .prismSurface(radius: Radius.container)
    }

    private func metric(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PrismMetricText(text: value, font: SpruceFont.metricS, color: color)
            Text(label)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    /// One-line summary of Free Up Locally, with the full explanation in a popover.
    private func explanation(_ provider: CloudStorageProvider) -> some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ModuleID.cloudStorage.palette.accentText)
            Text("Free Up Locally removes only the copy on this Mac. Files stay in \(provider.name) and download again when opened.")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                showsExplanation.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }
            .buttonStyle(.plain)
            .help("How Free Up Locally works")
            .accessibilityLabel("How Free Up Locally works")
            .popover(isPresented: $showsExplanation, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("How Free Up Locally works")
                        .font(SpruceFont.headline)
                    Text(CloudStorageText.evictionExplanation(providerName: provider.name))
                        .font(SpruceFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Files that are still uploading, have sync conflicts or belong to a folder the app keeps fully on this Mac are never freed. Suggested files are synced and haven't been changed in the last \(CountFormat.items(screen.engine.policy.recentModificationDays, singular: "day")) or opened in the last \(CountFormat.items(screen.engine.policy.recentUseDays, singular: "day")).")
                        .font(SpruceFont.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.l)
                .frame(width: 340)
            }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.subtleFill))
    }
}

// MARK: - File list

/// "On This Mac" / "Only in the Cloud" lists with selection, search and actions.
struct CloudStorageFileList: View {
    @Bindable var screen: CloudStorageScreenModel
    let report: CloudStorageProviderReport

    var body: some View {
        let records = screen.visibleRecords(for: report)
        VStack(spacing: 0) {
            toolbar(records)
            Divider().overlay(Ink.hairline)
            if records.isEmpty {
                emptyList
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(records) { record in
                            row(record)
                        }
                    }
                    .padding(Spacing.s)
                }
                .scrollIndicators(.automatic)
            }
        }
        .prismSurface(radius: Radius.container)
    }

    private func toolbar(_ records: [CloudStorageFileRecord]) -> some View {
        let provider = report.provider
        return HStack(spacing: Spacing.m) {
            if screen.listMode == .downloaded {
                SpruceCheckbox(state: screen.selectionState(of: records, provider: provider), module: .cloudStorage,
                               label: "Select all shown") {
                    let state = screen.selectionState(of: records, provider: provider)
                    screen.setSelected(records, provider: provider, state != .all)
                }
                .disabled(!provider.mechanism.canFreeUpLocally || records.isEmpty)
            }
            Picker("List", selection: $screen.listMode) {
                ForEach(CloudStorageListMode.allCases) { mode in
                    Text("\(mode.title) · \(CountFormat.grouped(count(for: mode)))").tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: Spacing.s)
            if screen.listMode == .downloaded && provider.mechanism.canFreeUpLocally {
                PrismTextButton(title: "Select Suggested", symbol: "sparkles", module: .cloudStorage) {
                    screen.selectSuggested(in: report)
                }
                .help("Select files that are synced and haven't been changed or opened recently")
            }
            if screen.listMode == .cloudOnly {
                let downloadable = records.filter { !screen.isDownloading($0) }
                PrismTextButton(title: "Download All Shown", symbol: "arrow.down.circle", module: .cloudStorage) {
                    screen.download(downloadable)
                }
                .disabled(downloadable.isEmpty)
                .help("Download these files to this Mac; they stay in sync afterwards")
            }
            PrismSearchField(text: $screen.search, prompt: "Search", width: 150)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    private func count(for mode: CloudStorageListMode) -> Int {
        mode == .downloaded ? report.largestLocal.count : report.largestCloudOnly.count
    }

    private func row(_ record: CloudStorageFileRecord) -> some View {
        let provider = report.provider
        return CloudStorageFileRow(
            record: record,
            provider: provider,
            eligibility: screen.eligibility(record, provider),
            isSelected: screen.isSelected(record),
            isDownloading: screen.isDownloading(record),
            onToggle: { screen.toggle(record, provider: provider) },
            onReveal: { screen.reveal([record]) },
            onFreeUp: { screen.requestFreeUp(record, provider: provider) },
            onDownload: { screen.download([record]) },
            onQuickLook: { screen.quickLook(record, provider: provider) },
            onIgnore: { screen.requestIgnore(record) }
        )
    }

    private var emptyText: (title: String, message: String) {
        if !screen.search.trimmingCharacters(in: .whitespaces).isEmpty {
            return ("No matching files", "Nothing in this list matches “\(screen.search)”.")
        }
        if screen.listMode == .downloaded {
            if report.stats.localBytes > 0 {
                return ("Only small files are downloaded",
                        "Files under 1 MB aren't listed. \(ByteFormat.string(report.stats.localBytes)) of small files are on this Mac.")
            }
            return ("Nothing is downloaded",
                    "Every file in \(report.provider.name) is stored only in the cloud. Nothing takes up space here.")
        }
        return ("Everything is downloaded", "No online-only files over 1 MB were found in \(report.provider.name).")
    }

    private var emptyList: some View {
        let text = emptyText
        return VStack(spacing: Spacing.s) {
            Spacer(minLength: Spacing.l)
            Image(systemName: screen.listMode == .downloaded ? "checkmark.icloud" : "internaldrive")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ModuleID.cloudStorage.palette.accentText)
            Text(text.title)
                .font(SpruceFont.headline)
                .foregroundStyle(Ink.primary)
            Text(text.message)
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.l)
    }
}
