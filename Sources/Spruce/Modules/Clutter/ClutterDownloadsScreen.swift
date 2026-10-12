import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Downloads: the top level of ~/Downloads by kind and by source (app or website), with
/// hints such as "app already installed" and "already unpacked". Only unfinished
/// downloads nobody touched for a day are selected for the user.
struct ClutterDownloadsScreen: View {
    @Bindable var screen: ClutterScreenModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ClutterToolHeader(screen: screen, tool: .downloads, subtitle: subtitle) {
                PrismSearchField(text: $screen.downloadsSearch, prompt: "Search names or sources", width: 210)
                sortMenu
            }
            if (screen.report?.downloads ?? []).isEmpty {
                ClutterEmptyPane(title: "Downloads is empty",
                                 message: "There's nothing in your Downloads folder to sort through.",
                                 symbol: "arrow.down.circle")
                    .clutterPane()
            } else {
                HStack(alignment: .top, spacing: Spacing.m) {
                    ClutterDownloadsSidebar(screen: screen)
                        .frame(width: 250)
                        .frame(maxHeight: .infinity)
                        .clutterPane()
                    ClutterDownloadsList(screen: screen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clutterPane()
                }
            }
            ClutterToolFooter(screen: screen, tool: .downloads)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var subtitle: String {
        let summary = screen.summary(for: .downloads)
        guard !summary.isEmpty else { return "~/Downloads" }
        return "\(summary.headline) · \(summary.detail) in ~/Downloads"
    }

    private var sortMenu: some View {
        ClutterMenuButton(title: "Sort: \(screen.downloadsSort.rawValue)", symbol: "arrow.up.arrow.down") {
            ForEach(ClutterDownloadsSort.allCases, id: \.self) { sort in
                Button {
                    screen.downloadsSort = sort
                } label: {
                    if screen.downloadsSort == sort {
                        Label(sortTitle(sort), systemImage: "checkmark")
                    } else {
                        Text(sortTitle(sort))
                    }
                }
            }
        }
    }

    private func sortTitle(_ sort: ClutterDownloadsSort) -> String {
        switch sort {
        case .size: return "Size (Largest First)"
        case .date: return "Date Downloaded (Oldest First)"
        case .name: return "Name"
        }
    }
}

/// Facets: everything, the selection, kinds and sources.
struct ClutterDownloadsSidebar: View {
    @Bindable var screen: ClutterScreenModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                facet(.all, title: "All Downloads", symbol: "tray.full")
                facet(.selected, title: "Selected", symbol: "checkmark.circle", alwaysShow: true)
                section("By Kind")
                ForEach(ClutterDownloadCategory.allCases, id: \.self) { category in
                    facet(.category(category), title: category.title, symbol: category.symbol)
                }
                let sources = screen.downloadSources
                if !sources.isEmpty {
                    section("By Source")
                    ForEach(sources) { source in
                        ClutterFacetRow(title: source.label, symbol: sourceSymbol(source.label), count: source.count,
                                        bytes: source.bytes, isSelected: screen.downloadsFacet == .source(source.label)) {
                            screen.downloadsFacet = .source(source.label)
                        }
                    }
                }
            }
            .padding(Spacing.s)
        }
        .scrollIndicators(.automatic)
    }

    private func section(_ title: String) -> some View {
        SectionHeader(title: title)
            .padding(.horizontal, Spacing.s)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.xxs)
    }

    @ViewBuilder
    private func facet(_ facet: ClutterDownloadsFacet, title: String, symbol: String, alwaysShow: Bool = false) -> some View {
        let stats = screen.downloadStats(facet)
        if stats.count > 0 || alwaysShow || screen.downloadsFacet == facet {
            ClutterFacetRow(title: title, symbol: symbol, count: stats.count, bytes: stats.bytes,
                            isSelected: screen.downloadsFacet == facet) {
                screen.downloadsFacet = facet
            }
        }
    }

    private func sourceSymbol(_ label: String) -> String {
        switch label.lowercased() {
        case "unknown source": return "questionmark.circle"
        case "airdrop": return "airplayaudio"
        case "mail": return "envelope"
        case "messages": return "message"
        default: return label.contains(".") ? "globe" : "app.dashed"
        }
    }
}

/// The filtered, sorted downloads with a select-all bar.
struct ClutterDownloadsList: View {
    @Bindable var screen: ClutterScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let items = screen.visibleDownloads
        let paths = items.map(\.file.path)
        let now = Date()
        let settings = screen.scanSettings
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                SpruceCheckbox(state: screen.selectionState(of: paths), module: .clutter, label: "Select all shown") {
                    screen.setSelected(paths, screen.selectionState(of: paths) != .all)
                }
                .disabled(paths.isEmpty)
                Text(facetTitle)
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text("\(CountFormat.items(items.count)) · \(ByteFormat.string(items.reduce(0) { $0 + $1.file.size }))")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(PrismInk(contrast).tertiary)
                Spacer()
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            if case .category(let category) = screen.downloadsFacet {
                Text(category.detail)
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.m)
                    .padding(.bottom, Spacing.s)
            }
            Divider().overlay(Ink.hairline)
            if items.isEmpty {
                ClutterEmptyPane(title: screen.downloadsSearch.isEmpty ? "Nothing here" : "No matches",
                                 message: screen.downloadsSearch.isEmpty
                                    ? "No downloads match this filter."
                                    : "No download matches “\(screen.downloadsSearch)”.",
                                 symbol: screen.downloadsSearch.isEmpty ? "tray" : "magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            ClutterFileRow(screen: screen, file: item.file, subtitle: subtitle(for: item, now: now),
                                           chips: chips(for: item, settings: settings, now: now),
                                           dateText: nil)
                        }
                    }
                    .padding(Spacing.xs)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private var facetTitle: String {
        switch screen.downloadsFacet {
        case .all: return "All Downloads"
        case .selected: return "Selected"
        case .category(let category): return category.title
        case .source(let label): return label
        }
    }

    private func subtitle(for item: ClutterDownloadItem, now: Date) -> String {
        var parts = ["Downloaded \(DurationFormat.relative(item.referenceDate, now: now))"]
        if let app = item.sourceApp { parts.append("with \(app)") }
        if let host = item.sourceHost { parts.append("from \(host)") }
        if let opened = item.file.lastOpened {
            parts.append("opened \(DurationFormat.relative(opened, now: now))")
        }
        return parts.joined(separator: " · ")
    }

    private func chips(for item: ClutterDownloadItem, settings: ClutterScanSettings, now: Date) -> [ClutterRowChip] {
        var chips: [ClutterRowChip] = []
        if ClutterDownloadsAnalyzer.isStaleIncomplete(item, settings: settings, now: now) {
            chips.append(ClutterRowChip(text: "Unfinished", symbol: "exclamationmark.arrow.circlepath", color: StatusColor.warning))
        } else if item.category == .incomplete {
            chips.append(ClutterRowChip(text: "Downloading?", symbol: "arrow.down", color: StatusColor.info))
        }
        if item.installerAlreadyUsed {
            chips.append(ClutterRowChip(text: "App installed", symbol: "checkmark.circle", color: StatusColor.success))
        } else if ClutterDownloadsAnalyzer.isOldInstaller(item, settings: settings, now: now) {
            chips.append(ClutterRowChip(text: "Old installer", symbol: "shippingbox", color: StatusColor.warning))
        }
        if item.archiveAlreadyExtracted {
            chips.append(ClutterRowChip(text: "Already unpacked", symbol: "archivebox", color: StatusColor.success))
        }
        if item.file.lastOpened == nil && !item.file.isFolder && item.category != .incomplete {
            chips.append(ClutterRowChip(text: "Never opened", symbol: "eye.slash", color: Color.white.opacity(0.55)))
        }
        return chips
    }
}
