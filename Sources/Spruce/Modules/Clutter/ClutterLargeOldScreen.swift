import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Large & Old Files: facets (All, Large, Not opened recently, Selected, by kind, size
/// and last use) on the left; a sortable, searchable file list on the right. Nothing is
/// selected for the user: these are their own files.
struct ClutterLargeOldScreen: View {
    @Bindable var screen: ClutterScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.m) {
            ClutterToolHeader(screen: screen, tool: .largeOld, subtitle: subtitle) {
                PrismSearchField(text: $screen.largeOldQuery.search, prompt: "Search files", width: 200)
                sortMenu
            }
            if (screen.report?.largeOld ?? []).isEmpty {
                ClutterEmptyPane(title: "No large or old files",
                                 message: "Nothing here is bigger than \(ByteFormat.string(screen.scanSettings.largeFileThreshold)) or untouched for \(screen.scanSettings.oldFileDays) days. You can change both in Settings.")
                    .clutterPane()
            } else {
                HStack(alignment: .top, spacing: Spacing.m) {
                    ClutterLargeOldSidebar(screen: screen)
                        .frame(width: 250)
                        .frame(maxHeight: .infinity)
                        .clutterPane()
                    ClutterLargeOldList(screen: screen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clutterPane()
                }
            }
            ClutterToolFooter(screen: screen, tool: .largeOld)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var subtitle: String {
        let items = screen.report?.largeOld ?? []
        let bytes = items.reduce(Int64(0)) { $0 + $1.file.size }
        return "\(CountFormat.items(items.count, singular: "file")) · \(ByteFormat.string(bytes)) · larger than \(ByteFormat.string(screen.scanSettings.largeFileThreshold)) or not opened for \(screen.scanSettings.oldFileDays) days"
    }

    private var sortMenu: some View {
        ClutterMenuButton(title: "Sort: \(screen.largeOldQuery.sort.rawValue)", symbol: "arrow.up.arrow.down") {
            ForEach(ClutterLargeOldQuery.Sort.allCases, id: \.self) { sort in
                Button {
                    screen.setLargeOldSort(sort)
                } label: {
                    if screen.largeOldQuery.sort == sort {
                        Label(sort.rawValue, systemImage: "checkmark")
                    } else {
                        Text(sort.rawValue)
                    }
                }
            }
            Divider()
            Button(screen.largeOldQuery.ascending ? "Reverse Order (Descending)" : "Reverse Order (Ascending)") {
                screen.largeOldQuery.ascending.toggle()
            }
        }
    }
}

/// Facets of the Large & Old list with counts and sizes.
struct ClutterLargeOldSidebar: View {
    @Bindable var screen: ClutterScreenModel

    var body: some View {
        let now = Date()
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                facet(.scope(.all), title: "All Files", symbol: "tray.full", now: now)
                facet(.scope(.large), title: "Large", symbol: "arrow.up.left.and.arrow.down.right", now: now)
                facet(.scope(.old), title: "Not Opened Recently", symbol: "clock", now: now)
                facet(.scope(.selected), title: "Selected", symbol: "checkmark.circle", now: now, alwaysShow: true)

                section("By Kind")
                ForEach(ClutterKind.allCases, id: \.self) { kind in
                    facet(.kind(kind), title: kind.title, symbol: kind.symbol, now: now)
                }
                section("By Size")
                ForEach(ClutterSizeBucket.allCases, id: \.self) { bucket in
                    facet(.size(bucket), title: bucket.title, symbol: "internaldrive", now: now)
                }
                section("By Last Use")
                ForEach(ClutterAgeBucket.allCases, id: \.self) { bucket in
                    facet(.age(bucket), title: bucket.title, symbol: "calendar", now: now)
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
    private func facet(_ facet: ClutterLargeOldFacet, title: String, symbol: String, now: Date,
                       alwaysShow: Bool = false) -> some View {
        let stats = screen.largeOldStats(facet, now: now)
        if stats.count > 0 || alwaysShow || screen.largeOldFacet == facet {
            ClutterFacetRow(title: title, symbol: symbol, count: stats.count, bytes: stats.bytes,
                            isSelected: screen.largeOldFacet == facet) {
                screen.selectLargeOldFacet(facet)
            }
        }
    }
}

/// The filtered, sorted Large & Old rows with a select-all bar.
struct ClutterLargeOldList: View {
    @Bindable var screen: ClutterScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let items = screen.visibleLargeOld
        let paths = items.map(\.file.path)
        let now = Date()
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                SpruceCheckbox(state: screen.selectionState(of: paths), module: .clutter, label: "Select all shown") {
                    screen.setSelected(paths, screen.selectionState(of: paths) != .all)
                }
                .disabled(paths.isEmpty)
                Text(facetTitle)
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                Text("\(CountFormat.items(items.count, singular: "file")) · \(ByteFormat.string(items.reduce(0) { $0 + $1.file.size }))")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(PrismInk(contrast).tertiary)
                Spacer()
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            Divider().overlay(Ink.hairline)
            if items.isEmpty {
                ClutterEmptyPane(title: screen.largeOldQuery.search.isEmpty ? "Nothing here" : "No matches",
                                 message: screen.largeOldQuery.search.isEmpty
                                    ? "No files match this filter."
                                    : "No file matches “\(screen.largeOldQuery.search)”.",
                                 symbol: screen.largeOldQuery.search.isEmpty ? "tray" : "magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            ClutterFileRow(screen: screen, file: item.file, chips: chips(for: item, now: now),
                                           dateText: dateText(for: item.file, now: now))
                        }
                    }
                    .padding(Spacing.xs)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private var facetTitle: String {
        switch screen.largeOldFacet {
        case .scope(.all): return "All Files"
        case .scope(.large): return "Large"
        case .scope(.old): return "Not Opened Recently"
        case .scope(.selected): return "Selected"
        case .kind(let kind): return kind.title
        case .size(let bucket): return bucket.title
        case .age(let bucket): return bucket.title
        }
    }

    private func chips(for item: ClutterLargeOldItem, now: Date) -> [ClutterRowChip] {
        var chips: [ClutterRowChip] = []
        if item.reason.isLarge {
            chips.append(ClutterRowChip(text: "Large", symbol: "arrow.up.left.and.arrow.down.right",
                                        color: ModuleID.clutter.palette.accent))
        }
        if item.reason.isOld {
            let age = DurationFormat.relative(item.file.effectiveLastUse, now: now)
            let label = age.hasSuffix(" ago") ? "Unused for " + String(age.dropLast(4)) : "Unused"
            chips.append(ClutterRowChip(text: label, symbol: "clock", color: StatusColor.warning))
        }
        if item.file.isCloud { chips.append(.cloud) }
        return chips
    }

    private func dateText(for file: ClutterFile, now: Date) -> String {
        if let opened = file.lastOpened {
            return "Opened \(DurationFormat.relative(opened, now: now))"
        }
        return "Changed \(DurationFormat.relative(file.modified, now: now))"
    }
}
