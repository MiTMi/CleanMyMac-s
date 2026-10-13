import Accessibility
import AppKit
import Observation
import QuickLook
import SpruceCore
import SpruceMac
import SwiftUI

// Standard screens for the module journey. CONTRACT: keep names and existing
// parameters; restyling and new defaulted parameters are fine.

/// A feature bullet on a module's idle screen.
struct IdleFeature: Identifiable {
    var id: String { title }
    var symbol: String
    var title: String
    var detail: String
}

// MARK: - Idle

/// Idle/intro screen (B.16): hero lens on the left, display title + tagline + feature
/// rows on the right, and the primary orb centred 76 pt above the bottom edge.
struct ModuleIdleView: View {
    var module: ModuleID
    var title: String? = nil
    var subtitle: String? = nil
    var features: [IdleFeature] = []
    var actionTitle: String = "Scan"
    var actionSubtitle: String? = nil
    var isEnabled: Bool = true
    var notice: String? = nil
    /// Title of a link shown next to the notice (e.g. "Grant Access"); needs `onNoticeAction`.
    var noticeActionTitle: String? = nil
    /// Return triggers the orb (keep true for Scan-like, non-destructive actions).
    var actionIsDefault: Bool = true
    var lensMood: PrismLensMood = .standard
    /// Optional control shown under the features (e.g. a scan-mode or location picker).
    var accessory: AnyView? = nil
    var action: () -> Void
    var onNoticeAction: (() -> Void)? = nil

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geo in
            let layout = PrismIdleLayout(size: geo.size, hasFeatures: !features.isEmpty)
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.topInset)
                HStack(alignment: .center, spacing: layout.gap) {
                    HeroLens(module: module, size: layout.lens, mood: lensMood)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                    textColumn
                        .frame(width: layout.textWidth, alignment: .leading)
                }
                .frame(maxWidth: Spacing.readableWidth)
                .padding(.horizontal, Spacing.contentInset)
                Spacer(minLength: Spacing.l)
                ActionOrb(title: actionTitle, subtitle: actionSubtitle, module: module, isEnabled: isEnabled,
                          isDefaultAction: actionIsDefault, action: action)
                    .padding(.bottom, Spacing.orbBottom)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(Motion.adaptive(Motion.emphasized, reduceMotion: reduceMotion)) { appeared = true }
        }
    }

    private var textColumn: some View {
        let ink = PrismInk(contrast)
        return VStack(alignment: .leading, spacing: Spacing.l) {
            Text(title ?? module.title)
                .font(SpruceFont.display())
                .tracking(-0.4)
                .foregroundStyle(Ink.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle ?? module.tagline)
                .font(.system(size: 15))
                .foregroundStyle(ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !features.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        PrismIdleFeatureRow(feature: feature, module: module)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : 8)
                            .animation(Motion.adaptive(Motion.emphasized, reduceMotion: reduceMotion)
                                .delay(0.1 + Double(index) * 0.06), value: appeared)
                    }
                }
                .padding(.top, Spacing.xs)
            }
            if let accessory {
                accessory
            }
            if let notice {
                PrismNoticeRow(text: notice, module: module, actionTitle: noticeActionTitle, action: onNoticeAction)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
    }
}

/// Lens and column sizes for the idle layout at a given content size.
private struct PrismIdleLayout {
    var lens: CGFloat
    var textWidth: CGFloat
    var gap: CGFloat

    init(size: CGSize, hasFeatures: Bool) {
        gap = size.width > 900 ? Spacing.xxl2 : Spacing.xxl
        let inner = max(0, size.width - Spacing.contentInset * 2)
        textWidth = min(420, max(280, inner * 0.46))
        let byWidth = (inner - textWidth - gap) / 1.4
        // Leave room for the top inset, the orb (96 + 28) and breathing space.
        let byHeight = (size.height - Spacing.topInset - 96 - Spacing.orbBottom - 72) / 1.4
        lens = min(300, max(140, min(byWidth, byHeight)))
    }
}

private struct PrismIdleFeatureRow: View {
    var feature: IdleFeature
    var module: ModuleID
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(alignment: .center, spacing: Spacing.m) {
            PrismCategoryBadge(symbol: feature.symbol, module: module, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                Text(feature.detail)
                    .font(SpruceFont.callout)
                    .foregroundStyle(ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Warning notice with an optional link action (e.g. missing Full Disk Access).
private struct PrismNoticeRow: View {
    var text: String
    var module: ModuleID
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: "info.circle.fill").foregroundStyle(StatusColor.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    PrismTextButton(title: actionTitle, symbol: "arrow.up.right", module: module, action: action)
                }
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .prismSurface(radius: Radius.row, tint: StatusColor.warning)
    }
}

// MARK: - Scanning

/// Scanning/running screen with live progress: animated lens with orbit rings and
/// inward-drifting dust, status line, throttled current path, running total, an
/// optional checklist (`steps`, e.g. Checkup's modules) and the Stop orb.
struct ScanningView: View {
    var module: ModuleID
    var progress: ScanProgress
    var title: String = "Scanning…"
    var stopTitle: String = "Stop"
    var onStop: (() -> Void)? = nil
    /// Multi-part checklist shown under the status (B.16 Checkup scanning).
    var steps: [PrismScanStep] = []
    /// Show the running "found so far" total.
    var showsBytes: Bool = true

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geo in
            let lens = lensSize(for: geo.size)
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.topInset)
                ZStack {
                    PrismScanDust(color: module.palette.accent2, secondary: Color.white)
                        .frame(width: lens * 2, height: lens * 2)
                    HeroLens(module: module, size: lens, isAnimating: true, parallax: false)
                }
                .frame(height: lens * 1.4)
                statusBlock
                    .padding(.top, Spacing.m)
                if !steps.isEmpty {
                    PrismScanChecklist(steps: steps, module: module)
                        .padding(.top, Spacing.l)
                        .padding(.horizontal, Spacing.contentInset)
                }
                Spacer(minLength: Spacing.l)
                bottomControl
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .prismCanvasIntensity(PrismCanvasMath.Intensity.scanning)
        .accessibilityElement(children: .contain)
    }

    private func lensSize(for size: CGSize) -> CGFloat {
        let stepsHeight: CGFloat = steps.isEmpty ? 0 : CGFloat((steps.count + 2) / 3) * 44 + Spacing.l
        let fixed = Spacing.topInset + 150 + stepsHeight + 170
        return min(220, max(110, (size.height - fixed) / 1.4))
    }

    private var statusBlock: some View {
        let ink = PrismInk(contrast)
        return VStack(spacing: Spacing.s) {
            Text(title)
                .font(SpruceFont.flowHeadline)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
            Text(progress.message.isEmpty ? " " : progress.message)
                .font(SpruceFont.body)
                .foregroundStyle(ink.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: progress.message)
            PrismThrottledText(value: progress.current)
                .font(SpruceFont.mono)
                .foregroundStyle(ink.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
                .accessibilityHidden(true)
            if showsBytes && progress.bytesFound > 0 {
                Text(ByteFormat.string(progress.bytesFound))
                    .font(SpruceFont.numeral(40))
                    .foregroundStyle(module.palette.accentText)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: progress.bytesFound)
                    .accessibilityLabel("\(ByteFormat.string(progress.bytesFound)) found so far")
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.contentInset)
    }

    @ViewBuilder
    private var bottomControl: some View {
        if let onStop {
            ActionOrb(title: stopTitle, subtitle: progress.fraction.map { "\(Int(($0 * 100).rounded()))%" },
                      module: module, progress: progress.fraction, isBusy: true, action: onStop)
                .padding(.bottom, Spacing.orbBottom)
        } else {
            ProgressRing(progress: progress.fraction, module: module, lineWidth: 5)
                .frame(width: 64, height: 64)
                .padding(.bottom, 44)
        }
    }
}

// MARK: - Review

private enum PrismGroupSort: String, CaseIterable {
    case size = "Size"
    case name = "Name"
}

private enum PrismItemSort: String, CaseIterable {
    case size = "Size"
    case name = "Name"
    case date = "Date"
}

private struct PrismReviewRow: Identifiable {
    enum Kind { case header, group }
    var id: String
    var group: ScanGroup
    var depth: Int
    var kind: Kind
}

/// Two-pane review list for grouped scan results with checkboxes (B.8.7).
/// Left: categories (nested groups appear as section headers) with tri-state
/// checkboxes, badges and sizes. Right: the focused group's description, safety
/// chip, selection menu, search, sort and item rows.
struct ReviewSplitView: View {
    var module: ModuleID
    @Binding var groups: [ScanGroup]
    var emptyTitle: String = "Nothing found"
    var emptyMessage: String = "Your Mac is spotless here."
    /// Called when the user chooses "Ignore" on an item (nil hides the action).
    var onIgnore: ((ScanItem) -> Void)? = nil
    /// Show the search field above the item list.
    var showsSearch: Bool = true

    @State private var selectedGroupID: String?
    @State private var groupSort: PrismGroupSort = .size
    @State private var itemSort: PrismItemSort = .size
    @State private var search = ""
    /// The row File › Quick Look / Reveal in Finder / Copy Path / Ignore act on.
    @State private var rowFocus = PrismReviewRowFocus()
    /// File › Quick Look (rows keep their own preview for the hover button).
    @State private var menuPreviewURL: URL?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if groups.allItems.isEmpty {
            EmptyStateView(module: module, title: emptyTitle, message: emptyMessage)
        } else {
            GeometryReader { geo in
                HStack(spacing: Spacing.m) {
                    categoryPane
                        .frame(width: min(340, max(250, geo.size.width * 0.36)))
                    itemPane
                }
            }
            .prismCanvasIntensity(PrismCanvasMath.Intensity.results)
        }
    }

    // MARK: Rows

    private var rows: [PrismReviewRow] {
        var out: [PrismReviewRow] = []
        func walk(_ list: [ScanGroup], depth: Int) {
            for group in sortedGroups(list) {
                if group.children.isEmpty {
                    out.append(PrismReviewRow(id: group.id, group: group, depth: depth, kind: .group))
                } else {
                    out.append(PrismReviewRow(id: "header:" + group.id, group: group, depth: depth, kind: .header))
                    if !group.items.isEmpty {
                        let own = ScanGroup(id: group.id, title: group.title, detail: group.detail, symbol: group.symbol,
                                            safety: group.safety, items: group.items)
                        out.append(PrismReviewRow(id: group.id, group: own, depth: depth + 1, kind: .group))
                    }
                    walk(group.children, depth: depth + 1)
                }
            }
        }
        walk(groups, depth: 0)
        return out
    }

    private func sortedGroups(_ list: [ScanGroup]) -> [ScanGroup] {
        switch groupSort {
        case .size: return list.sorted { $0.totalSize > $1.totalSize }
        case .name: return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private func currentGroup(in rows: [PrismReviewRow]) -> ScanGroup? {
        let groupRows = rows.filter { $0.kind == .group }
        return groupRows.first { $0.id == selectedGroupID }?.group ?? groupRows.first?.group
    }

    private var allSelectableSelected: Bool {
        let items = groups.allItems.filter { $0.safety != .risky }
        return !items.isEmpty && items.allSatisfy(\.isSelected)
    }

    // MARK: Category pane

    private var categoryPane: some View {
        let ink = PrismInk(contrast)
        let rows = self.rows
        let current = currentGroup(in: rows)
        return VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                let allOn = allSelectableSelected
                Button(allOn ? "Deselect All" : "Select All") { selectAll(!allOn) }
                    .buttonStyle(PrismCapsuleButtonStyle(role: .secondary))
                Spacer(minLength: Spacing.s)
                PrismSortMenu(title: "Sort", selection: $groupSort)
            }
            .padding(Spacing.m)
            Rectangle().fill(ink.hairline).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        switch row.kind {
                        case .header:
                            PrismCategoryHeaderRow(group: row.group, depth: row.depth, module: module) {
                                setSelection(groupID: row.group.id, selected: row.group.selectionState == SelectionState.none, includeChildren: true)
                            }
                        case .group:
                            PrismCategoryRow(group: row.group, depth: row.depth, module: module,
                                             isCurrent: row.id == current?.id,
                                             onToggle: {
                                                 setSelection(groupID: row.group.id, selected: row.group.selectionState == SelectionState.none,
                                                              includeChildren: false)
                                             },
                                             onSelect: {
                                                 selectedGroupID = row.id
                                                 search = ""
                                             })
                        }
                    }
                }
                .padding(Spacing.s)
            }
        }
        .prismSurface(radius: Radius.container)
    }

    // MARK: Item pane

    @ViewBuilder
    private var itemPane: some View {
        let ink = PrismInk(contrast)
        if let group = currentGroup(in: rows) {
            let items = sortedFiltered(group.items)
            VStack(spacing: 0) {
                itemHeader(group, ink: ink)
                itemToolbar(group, ink: ink)
                Rectangle().fill(ink.hairline).frame(height: 1)
                if items.isEmpty {
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .light)).foregroundStyle(ink.tertiary)
                        Text(search.isEmpty ? "No items in this group" : "No matches for “\(search)”")
                            .font(SpruceFont.body).foregroundStyle(ink.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                ItemRow(item: item, module: module,
                                        onToggle: {
                                            rowFocus.focus(item.id)
                                            toggle(item)
                                        },
                                        onIgnore: onIgnore,
                                        onHover: { inside in
                                            if inside { rowFocus.focus(item.id) }
                                        })
                                Rectangle().fill(ink.hairline).frame(height: 1).padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            .prismSurface(radius: Radius.container)
            .modifier(PrismReviewRowsPublisher(focus: rowFocus, items: items, onIgnore: onIgnore,
                                               onQuickLook: { menuPreviewURL = $0 }))
            .quickLookPreview($menuPreviewURL)
            .id(group.id)
            .transition(.opacity)
        } else {
            Color.clear
        }
    }

    private func itemHeader(_ group: ScanGroup, ink: PrismInk) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            PrismCategoryBadge(symbol: group.symbol, module: module, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.s) {
                    Text(group.title).font(SpruceFont.title).foregroundStyle(Ink.primary).lineLimit(1)
                    PrismSafetyBadge(safety: group.safety)
                }
                if !group.detail.isEmpty {
                    Text(group.detail)
                        .font(SpruceFont.callout)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding([.horizontal, .top], Spacing.l)
        .padding(.bottom, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private func itemToolbar(_ group: ScanGroup, ink: PrismInk) -> some View {
        HStack(spacing: Spacing.s) {
            Menu {
                Button("Select All") { setSelection(groupID: group.id, selected: true, includeChildren: false) }
                Button("Deselect All") { setSelection(groupID: group.id, selected: false, includeChildren: false) }
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
            Text("\(CountFormat.grouped(group.selectedCount)) of \(CountFormat.items(group.totalCount)) selected · \(ByteFormat.string(group.selectedSize))")
                .font(SpruceFont.captionDigits)
                .foregroundStyle(ink.tertiary)
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: Spacing.s)
            if showsSearch {
                PrismSearchField(text: $search, prompt: "Search", width: 170)
            }
            PrismSortMenu(title: "Sort", selection: $itemSort)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    // MARK: Logic

    private func sortedFiltered(_ items: [ScanItem]) -> [ScanItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? items : items.filter {
            $0.title.localizedCaseInsensitiveContains(query) || ($0.subtitle ?? "").localizedCaseInsensitiveContains(query)
        }
        switch itemSort {
        case .size:
            return filtered.sorted { $0.size > $1.size }
        case .name:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .date:
            return filtered.sorted {
                ($0.lastUsed ?? $0.modified ?? .distantPast) < ($1.lastUsed ?? $1.modified ?? .distantPast)
            }
        }
    }

    private func toggle(_ item: ScanItem) {
        groups.setSelected(!item.isSelected, itemID: item.id)
    }

    private func selectAll(_ selected: Bool) {
        for index in groups.indices { groups[index].setAllSelected(selected) }
    }

    /// Selects/deselects a group. `includeChildren` = the whole subtree (section
    /// headers); otherwise only the group's own items. Risky items are never bulk-selected.
    private func setSelection(groupID: String, selected: Bool, includeChildren: Bool) {
        func apply(_ list: inout [ScanGroup]) -> Bool {
            for index in list.indices {
                if list[index].id == groupID {
                    if includeChildren || list[index].children.isEmpty {
                        list[index].setAllSelected(selected)
                    } else {
                        for j in list[index].items.indices {
                            list[index].items[j].isSelected = selected && list[index].items[j].safety != .risky
                        }
                    }
                    return true
                }
                if apply(&list[index].children) { return true }
            }
            return false
        }
        _ = apply(&groups)
    }
}

/// Compact "Sort: Size ▾" menu.
private struct PrismSortMenu<Option: Hashable & RawRepresentable & CaseIterable>: View where Option.RawValue == String,
    Option.AllCases: RandomAccessCollection {
    var title: String
    @Binding var selection: Option

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(Array(Option.allCases), id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text("\(title): \(selection.rawValue)")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(SpruceFont.callout.weight(.medium))
            .foregroundStyle(Ink.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(title) by \(selection.rawValue)")
    }
}

/// The review row the pointer last rested on (or that was last clicked). A reference
/// type the review list never reads, so hovering re-renders only the modifier below,
/// not the list.
@Observable
final class PrismReviewRowFocus {
    private(set) var itemID: String?

    func focus(_ id: String) {
        if itemID != id { itemID = id }
    }
}

/// Publishes the focused review row to the File menu (Quick Look ⌘Y, Reveal in Finder,
/// Copy Path, Ignore) with `.focusedSceneValue(\.spruceRows, …)`. Only this modifier
/// reads the focus, so a new focused row doesn't rebuild the rows it wraps.
private struct PrismReviewRowsPublisher: ViewModifier {
    var focus: PrismReviewRowFocus
    /// The rows on screen; a focused row that is filtered out or gone publishes nothing.
    var items: [ScanItem]
    var onIgnore: ((ScanItem) -> Void)?
    var onQuickLook: (URL) -> Void

    func body(content: Content) -> some View {
        content.focusedSceneValue(\.spruceRows, actions)
    }

    private var actions: SpruceRowActions {
        guard let id = focus.itemID, let item = items.first(where: { $0.id == id }) else {
            return SpruceRowActions(urls: [])
        }
        var quickLook: (() -> Void)?
        if let url = item.url {
            let open = onQuickLook
            quickLook = { open(url) }
        }
        var ignore: (() -> Void)?
        if let onIgnore {
            ignore = { onIgnore(item) }
        }
        return SpruceRowActions(itemID: item.id, urls: item.url.map { [$0] } ?? [], quickLook: quickLook, ignore: ignore)
    }
}

private struct PrismCategoryHeaderRow: View {
    var group: ScanGroup
    var depth: Int
    var module: ModuleID
    var onToggle: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.s) {
            SpruceCheckbox(state: group.selectionState, module: module, label: group.title, action: onToggle)
            Text(group.title.uppercased())
                .font(SpruceFont.overline)
                .tracking(0.8)
                .foregroundStyle(ink.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(ByteFormat.string(group.totalSize))
                .font(SpruceFont.captionDigits)
                .foregroundStyle(ink.tertiary)
        }
        .padding(.leading, Spacing.s + CGFloat(depth) * 14)
        .padding(.trailing, Spacing.s)
        .padding(.top, Spacing.s)
        .padding(.bottom, 2)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct PrismCategoryRow: View {
    var group: ScanGroup
    var depth: Int
    var module: ModuleID
    var isCurrent: Bool
    var onToggle: () -> Void
    var onSelect: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let p = module.palette
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        HStack(spacing: Spacing.s) {
            SpruceCheckbox(state: group.selectionState, module: module, label: group.title, action: onToggle)
            PrismCategoryBadge(symbol: group.symbol, module: module, size: 30, isDimmed: group.isEmpty)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary).lineLimit(1)
                Text(CountFormat.items(group.totalCount)).font(SpruceFont.caption).foregroundStyle(ink.tertiary)
            }
            Spacer(minLength: 4)
            if group.safety != .safe {
                Circle().fill(StatusColor.of(group.safety)).frame(width: 6, height: 6)
                    .help(group.safety.label)
            }
            Text(ByteFormat.string(group.totalSize))
                .font(SpruceFont.captionDigits)
                .foregroundStyle(ink.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isCurrent ? Ink.primary : ink.tertiary)
        }
        .padding(.leading, Spacing.s + CGFloat(depth) * 14)
        .padding(.trailing, Spacing.s)
        .frame(minHeight: 52)
        .background(shape.fill(isCurrent ? ink.selectedFill : (hovering ? ink.subtleFill : Color.clear)))
        .overlay {
            if isCurrent {
                if ink.increased {
                    shape.strokeBorder(p.accentText, lineWidth: 2)
                } else {
                    shape.strokeBorder(LinearGradient(colors: [p.accent.opacity(0.7), p.accent.opacity(0)],
                                                      startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                }
            }
        }
        .opacity(group.isEmpty ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.title), \(ByteFormat.string(group.totalSize)), \(CountFormat.items(group.totalCount))")
        .accessibilityValue(selectionText)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: "Toggle selection") { onToggle() }
    }

    private var selectionText: String {
        switch group.selectionState {
        case .all: return "all selected"
        case .some: return "partly selected"
        case SelectionState.none: return "not selected"
        }
    }
}

/// One selectable result row (44 pt): checkbox · Finder icon · name + path ·
/// safety badge · hover actions (Reveal, Quick Look, Ignore) · size. Hovering
/// reveals the item's note. Selecting a risky item asks for confirmation.
struct ItemRow: View {
    var item: ScanItem
    var module: ModuleID
    var onToggle: () -> Void
    var onIgnore: ((ScanItem) -> Void)? = nil
    /// Ask before selecting a `.risky` item (safety rule 3).
    var confirmsRisky: Bool = true
    /// Told when the pointer enters (true) or leaves (false) the row.
    var onHover: ((Bool) -> Void)? = nil

    @State private var hovering = false
    @State private var confirmRisky = false
    @State private var previewURL: URL?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.m) {
            SpruceCheckbox(isOn: item.isSelected, module: module, label: item.title, action: requestToggle)
            ItemIcon(url: item.url, symbol: item.symbol, size: 24, module: module)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(SpruceFont.body)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    PrismSafetyBadge(safety: item.safety)
                }
                secondaryLine(ink)
            }
            Spacer(minLength: Spacing.s)
            if hovering {
                hoverActions
                    .transition(.opacity)
            } else if let date = item.lastUsed ?? item.modified {
                Text(DurationFormat.relative(date))
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            Text(sizeText)
                .font(SpruceFont.callout.monospacedDigit())
                .foregroundStyle(ink.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(Rectangle().fill(hovering ? ink.subtleFill : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: requestToggle)
        .onHover { inside in
            hovering = inside
            onHover?(inside)
        }
        .animation(Motion.quick, value: hovering)
        .contextMenu { contextMenuItems }
        .help(helpText)
        .quickLookPreview($previewURL)
        .confirmationDialog("Select “\(item.title)”?", isPresented: $confirmRisky, titleVisibility: .visible) {
            Button("Select Anyway", role: .destructive) { onToggle() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(item.note.map { "\($0)\n\n\(SafetyLevel.risky.label)." } ?? "\(SafetyLevel.risky.label). Only select it if you're sure you no longer need it.")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(item.isSelected ? "selected" : "not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { requestToggle() }
        .accessibilityAction(named: "Reveal in Finder") { reveal() }
        .accessibilityAction(named: "Ignore") { onIgnore?(item) }
    }

    @ViewBuilder
    private func secondaryLine(_ ink: PrismInk) -> some View {
        if hovering, let note = item.note, !note.isEmpty {
            Text(note)
                .font(SpruceFont.caption)
                .foregroundStyle(ink.secondary)
                .lineLimit(1)
                .transition(.opacity)
        } else if let subtitle = item.subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(SpruceFont.mono)
                .foregroundStyle(ink.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .transition(.opacity)
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            if item.url != nil {
                PrismIconButton(symbol: "magnifyingglass", help: "Reveal in Finder") { reveal() }
                PrismIconButton(symbol: "eye", help: "Quick Look") { previewURL = item.url }
            }
            if let onIgnore {
                PrismIconButton(symbol: "eye.slash", help: "Ignore from now on") { onIgnore(item) }
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let url = item.url {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Quick Look") { previewURL = url }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        }
        if let onIgnore {
            Divider()
            Button("Ignore") { onIgnore(item) }
        }
    }

    private var sizeText: String {
        if item.size == 0 && item.url == nil { return "" }
        return ByteFormat.string(item.size)
    }

    private var helpText: String {
        var parts: [String] = []
        if let note = item.note, !note.isEmpty { parts.append(note) }
        if item.safety != .safe { parts.append(item.safety.label) }
        if let url = item.url { parts.append(url.path.abbreviatingHome) }
        return parts.isEmpty ? item.safety.label : parts.joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        var parts = [item.title]
        if !sizeText.isEmpty { parts.append(sizeText) }
        if item.safety != .safe { parts.append(item.safety.label) }
        if let note = item.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    private func requestToggle() {
        if confirmsRisky && item.safety == .risky && !item.isSelected {
            confirmRisky = true
        } else {
            onToggle()
        }
    }

    private func reveal() {
        if let url = item.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

// MARK: - Results footer

/// Footer with the selection total and the primary orb on results screens.
struct ResultsFooter: View {
    var module: ModuleID
    var selectedBytes: Int64
    var selectedCount: Int
    var actionTitle: String = "Remove"
    var isEnabled: Bool = true
    /// Total found, shown as "of 7.9 GB found".
    var totalBytes: Int64? = nil
    /// Total item count, shown as "214 of 1,032 items selected".
    var totalCount: Int? = nil
    /// Set false for selections without a meaningful size (login items, updates…).
    var showsBytes: Bool = true
    var action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(alignment: .center, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SELECTED")
                    .font(SpruceFont.overline)
                    .tracking(0.8)
                    .foregroundStyle(ink.tertiary)
                if showsBytes {
                    PrismMetricText(text: ByteFormat.string(selectedBytes), font: SpruceFont.numeral(28))
                        .animation(.snappy(duration: 0.25), value: selectedBytes)
                }
                Text(countLine)
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(ink.tertiary)
                    .contentTransition(.numericText())
                if showsBytes, let totalBytes {
                    Text("of \(ByteFormat.string(totalBytes)) found")
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(ink.tertiary)
                }
            }
            .frame(width: 200, alignment: .leading)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            ActionOrb(title: actionTitle, subtitle: orbDetail, module: module,
                      isEnabled: isEnabled && selectedCount > 0, diameter: 84, isReady: true, action: action)
            Spacer(minLength: 0)
            Color.clear.frame(width: 200, height: 1)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.l)
        .prismCanvasIntensity(PrismCanvasMath.Intensity.results)
    }

    private var countLine: String {
        if let totalCount {
            return "\(CountFormat.grouped(selectedCount)) of \(CountFormat.items(totalCount)) selected"
        }
        return "\(CountFormat.items(selectedCount)) selected"
    }

    private var orbDetail: String {
        if selectedCount == 0 { return "Nothing selected" }
        if showsBytes && selectedBytes > 0 { return ByteFormat.string(selectedBytes) }
        return CountFormat.items(selectedCount)
    }
}

// MARK: - Done

/// Completion screen: calm lens, one-shot particle burst, freed-bytes count-up,
/// stat chips, what went to the Trash (Open Trash / Put Back All), failures,
/// completion sound and a VoiceOver announcement.
struct DoneView: View {
    var module: ModuleID
    var outcome: RunOutcome
    var headline: String? = nil
    var doneTitle: String = "Done"
    /// Play the completion sound (honours Settings › Play sounds).
    var playsSound: Bool = true
    /// The flow whose run `outcome` is: Put Back All then goes through
    /// `ScanFlowModel.putBack()`, so the flow keeps the result. Without one, the Trash
    /// card puts the run back through `TrashLedger` itself.
    var flow: ScanFlowModel? = nil
    /// When set, Put Back All asks first with this message (e.g. for removed threats).
    var putBackConfirmation: String? = nil
    var onDone: () -> Void

    @State private var shownBytes: Double = 0
    @State private var celebrating = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let p = module.palette
        let succeeded = outcome.failures.isEmpty
        VStack(spacing: Spacing.l) {
            Spacer(minLength: Spacing.topInset)
            ZStack {
                if succeeded || outcome.processedCount > 0 {
                    PrismBurst(color: Color.white, secondary: p.accent2)
                        .frame(width: 440, height: 440)
                }
                HeroLens(module: module, size: 160, mood: succeeded ? .clean : .warning, parallax: false)
            }
            .frame(height: 160 * 1.4)
            headlineView
            if !outcome.summary.isEmpty {
                Text(outcome.summary)
                    .font(SpruceFont.body)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            statChips
            if DoneTrashCard.applies(to: outcome) {
                DoneTrashCard(module: module, outcome: outcome, flow: flow, confirmation: putBackConfirmation)
            }
            if !outcome.failures.isEmpty {
                failuresCard
            }
            Spacer(minLength: Spacing.l)
            ActionOrb(title: doneTitle, module: module, diameter: 84, isDone: celebrating && !reduceMotion,
                      isDefaultAction: true, action: onDone)
                .padding(.bottom, Spacing.orbBottom)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.contentInset)
        .prismCanvasIntensity(celebrating && !reduceMotion ? PrismCanvasMath.Intensity.celebrate : PrismCanvasMath.Intensity.idle)
        .onAppear(perform: celebrate)
        .task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                withAnimation(Motion.slow) { celebrating = false }
            }
        }
    }

    @ViewBuilder
    private var headlineView: some View {
        if let headline {
            Text(headline)
                .font(SpruceFont.display(30))
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        } else if outcome.freedBytes > 0 {
            VStack(spacing: 0) {
                PrismCountingBytes(value: shownBytes, font: SpruceFont.metricXL, unitFont: .system(size: 20, weight: .medium))
                Text(freedCaption)
                    .font(SpruceFont.headline)
                    .foregroundStyle(PrismInk(contrast).secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ByteFormat.string(outcome.freedBytes)) \(freedCaption)")
            .accessibilityAddTraits(.isHeader)
        } else {
            Text(outcome.failures.isEmpty ? "All done" : "Finished, with a few exceptions")
                .font(SpruceFont.display(30))
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// True when everything the run freed went to the Trash (it comes back once the
    /// Trash is emptied).
    private var allMovedToTrash: Bool {
        outcome.trashedBytes > 0 && outcome.trashedBytes >= outcome.freedBytes
    }

    private var freedCaption: String {
        allMovedToTrash ? "moved to the Trash" : "freed up"
    }

    @ViewBuilder
    private var statChips: some View {
        let p = module.palette
        let chips = HStack(spacing: Spacing.s) {
            if outcome.freedBytes > 0 {
                PrismStatChip(symbol: allMovedToTrash ? "trash.circle.fill" : "arrow.down.circle.fill",
                              value: ByteFormat.string(outcome.freedBytes),
                              label: allMovedToTrash ? "In the Trash" : "Freed", tint: p.accentText)
            }
            if outcome.processedCount > 0 {
                PrismStatChip(symbol: "checkmark.circle.fill", value: CountFormat.grouped(outcome.processedCount),
                              label: outcome.processedCount == 1 ? "Item handled" : "Items handled", tint: StatusColor.success)
            }
            if !outcome.failures.isEmpty {
                PrismStatChip(symbol: "exclamationmark.triangle.fill", value: CountFormat.grouped(outcome.failures.count),
                              label: "Couldn't complete", tint: StatusColor.warning)
            }
        }
        if outcome.freedBytes > 0 || outcome.processedCount > 0 || !outcome.failures.isEmpty {
            chips
        }
    }

    private var failuresCard: some View {
        let ink = PrismInk(contrast)
        return GlassCard(radius: Radius.container) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Couldn't complete", trailing: CountFormat.items(outcome.failures.count))
                ForEach(Array(outcome.failures.prefix(6).enumerated()), id: \.offset) { _, failure in
                    HStack(alignment: .top, spacing: Spacing.m) {
                        Text(failure.title).font(SpruceFont.callout).foregroundStyle(Ink.primary).lineLimit(1)
                        Spacer(minLength: Spacing.s)
                        Text(failure.reason).font(SpruceFont.caption).foregroundStyle(ink.tertiary)
                            .lineLimit(2).multilineTextAlignment(.trailing)
                    }
                }
                if outcome.failures.count > 6 {
                    Text("and \(CountFormat.items(outcome.failures.count - 6, singular: "more item", plural: "more items"))")
                        .font(SpruceFont.caption).foregroundStyle(ink.tertiary)
                }
            }
        }
        .frame(maxWidth: 560)
    }

    private func celebrate() {
        let target = Double(max(0, outcome.freedBytes))
        if reduceMotion {
            shownBytes = target
        } else {
            withAnimation(Motion.countUp) { shownBytes = target }
        }
        if playsSound {
            if outcome.failures.isEmpty {
                SpruceSound.play(.cleanComplete)
            } else if outcome.processedCount > 0 || outcome.freedBytes > 0 {
                SpruceSound.play(.attention)
            } else {
                SpruceSound.play(.error)
            }
        }
        var announcement: String
        if let headline {
            announcement = headline
        } else if outcome.freedBytes > 0 {
            announcement = "Done. \(ByteFormat.string(outcome.freedBytes)) \(freedCaption)."
        } else {
            announcement = "Done."
        }
        if !outcome.failures.isEmpty {
            announcement += " \(CountFormat.items(outcome.failures.count)) couldn't be completed."
        }
        AccessibilityNotification.Announcement(announcement).post()
    }
}

/// What a run moved to the Trash: "3 items (1.2 GB) are in the Trash. Empty it to get
/// the space back." with Open Trash and Put Back All (`RunOutcome.trashedCount` /
/// `trashedBytes` / `trashRunIDs`, `TrashLedger`). Put Back restores only items still
/// in the Trash whose original place is free; items moved as administrator stay.
private struct DoneTrashCard: View {
    var module: ModuleID
    var outcome: RunOutcome
    var flow: ScanFlowModel?
    var confirmation: String?

    @State private var localRestorable: Int?
    @State private var localResult: TrashPutBackResult?
    @State private var localWorking = false
    @State private var confirming = false
    @Environment(\.colorSchemeContrast) private var contrast

    static func applies(to outcome: RunOutcome) -> Bool {
        outcome.trashedCount > 0 || outcome.trashedBytes > 0 || !outcome.trashRunIDs.isEmpty
    }

    /// The flow, when it holds this very run (its Put Back state then applies).
    private var activeFlow: ScanFlowModel? {
        guard let flow, flow.phase == .done, let runIDs = flow.outcome?.trashRunIDs,
              !runIDs.isEmpty, runIDs == outcome.trashRunIDs else { return nil }
        return flow
    }

    private var restorable: Int {
        if let activeFlow { return activeFlow.restorableCount }
        return localRestorable ?? 0
    }

    private var result: TrashPutBackResult? {
        if let activeFlow { return activeFlow.putBackResult }
        return localResult
    }

    private var working: Bool {
        if let activeFlow { return activeFlow.isPuttingBack }
        return localWorking
    }

    var body: some View {
        let ink = PrismInk(contrast)
        let p = module.palette
        GlassCard(padding: Spacing.m, radius: Radius.container) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Image(systemName: result?.restored.isEmpty == false ? "arrow.uturn.backward" : "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(p.accentText)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(p.accent.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SpruceFont.bodyStrong)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Spacing.s)
                CapsuleButton(title: "Open Trash", symbol: "trash") { TrashLedger.openTrash() }
                if restorable > 0 || working {
                    CapsuleButton(title: working ? "Putting Back…" : "Put Back All", symbol: "arrow.uturn.backward") {
                        requestPutBack()
                    }
                    .disabled(working)
                    .help("Moves the items back to where they were")
                }
            }
        }
        .frame(maxWidth: 560)
        .task(id: outcome.trashRunIDs) { await loadRestorable() }
        .onChange(of: result) { _, new in
            if let new { AccessibilityNotification.Announcement(new.summary).post() }
        }
        .confirmationDialog("Put back \(CountFormat.items(restorable))?", isPresented: $confirming,
                            titleVisibility: .visible) {
            Button("Put Back All") { putBack() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmation ?? "")
        }
    }

    // MARK: Text

    private var countText: String {
        let count = max(outcome.trashedCount, restorable)
        let items = count > 0 ? CountFormat.items(count) : "Some items"
        return outcome.trashedBytes > 0 ? "\(items) (\(ByteFormat.string(outcome.trashedBytes)))" : items
    }

    private var title: String {
        if let result, !(result.restored.isEmpty && result.failures.isEmpty) { return result.summary }
        let count = max(outcome.trashedCount, restorable)
        return count == 1 ? "\(countText) is in the Trash" : "\(countText) are in the Trash"
    }

    private var detail: String {
        if let result, !(result.restored.isEmpty && result.failures.isEmpty) {
            if let failure = result.failures.first {
                return result.failures.count == 1
                    ? "\(failure.title): \(failure.reason)"
                    : "\(failure.title): \(failure.reason) (and \(CountFormat.grouped(result.failures.count - 1)) more)"
            }
            return restorable > 0
                ? "They're back where they were. \(CountFormat.items(restorable)) can still be put back."
                : "They're back where they were."
        }
        return "Empty the Trash to get the space back."
    }

    // MARK: Actions

    private func requestPutBack() {
        guard !working, restorable > 0 else { return }
        if let confirmation, !confirmation.isEmpty {
            confirming = true
        } else {
            putBack()
        }
    }

    private func putBack() {
        if let activeFlow {
            activeFlow.putBack()
            return
        }
        let runIDs = outcome.trashRunIDs
        guard !runIDs.isEmpty, !localWorking else { return }
        localWorking = true
        let module = self.module
        Task { @MainActor in
            let (done, remaining) = await Task.detached(priority: .userInitiated) { () -> (TrashPutBackResult, Int) in
                let restored = TrashLedger.shared.putBack(runIDs: runIDs)
                return (restored, TrashLedger.shared.restorable(runIDs: runIDs).count)
            }.value
            localResult = done
            localRestorable = remaining
            localWorking = false
            if !done.restored.isEmpty {
                OperationLog.shared.record(module: module, action: "put-back-run", result: "ok",
                                           detail: "\(done.restored.count) item(s)")
            }
        }
    }

    /// Counts the run's items that can still be put back (off the main thread: it reads
    /// the ledger and checks each item in the Trash).
    private func loadRestorable() async {
        guard activeFlow == nil else { return }
        let runIDs = outcome.trashRunIDs
        guard !runIDs.isEmpty else {
            localRestorable = 0
            return
        }
        let count = await Task.detached(priority: .utility) {
            TrashLedger.shared.restorable(runIDs: runIDs).count
        }.value
        localRestorable = count
    }
}

// MARK: - Empty / failure

/// Calm "nothing here" state with a lens, a headline, a message and an optional action.
struct EmptyStateView: View {
    var module: ModuleID
    var title: String
    var message: String
    var symbol: String = "checkmark.seal"
    var mood: PrismLensMood = .clean
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.m) {
            HeroLens(module: module, size: 120, mood: mood, badge: badgeSymbol, parallax: false)
            Text(title)
                .font(SpruceFont.title)
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(SpruceFont.body)
                .foregroundStyle(PrismInk(contrast).secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                CapsuleButton(title: actionTitle, symbol: "arrow.clockwise", action: action)
                    .padding(.top, Spacing.s)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var badgeSymbol: String? {
        symbol == "checkmark.seal" ? nil : symbol
    }
}

/// Error screen with retry.
struct FailureView: View {
    var module: ModuleID
    var message: String
    var title: String = "Couldn't finish this scan."
    var retryTitle: String = "Try Again"
    /// Optional technical details, shown behind a disclosure.
    var details: String? = nil
    var onRetry: () -> Void

    @State private var showDetails = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        VStack(spacing: Spacing.m) {
            Spacer(minLength: Spacing.topInset)
            HeroLens(module: module, size: 130, mood: .warning, parallax: false)
            Text(title)
                .font(SpruceFont.title)
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(SpruceFont.body)
                .foregroundStyle(ink.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let details, !details.isEmpty {
                DisclosureGroup(isExpanded: $showDetails) {
                    ScrollView {
                        Text(details)
                            .font(SpruceFont.mono)
                            .foregroundStyle(ink.tertiary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                } label: {
                    Text("Details").font(SpruceFont.callout.weight(.medium)).foregroundStyle(ink.secondary)
                }
                .frame(maxWidth: 460)
            }
            CapsuleButton(title: retryTitle, symbol: "arrow.clockwise", prominent: true, large: true, action: onRetry)
                .padding(.top, Spacing.s)
            Spacer(minLength: Spacing.xxl)
        }
        .padding(.horizontal, Spacing.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { SpruceSound.play(.error) }
    }
}

// MARK: - Checkup tile

/// A Checkup result tile (B.8.6): mini lens + overline + checkbox, big metric,
/// description, status chip, Review capsule and an optional primary capsule.
struct ResultTile: View {
    var tile: CheckupTile
    var isSelected: Bool
    /// Shows a spinner + "Checking…" instead of the metric.
    var isScanning: Bool = false
    /// Title of an optional white primary capsule ("Clean now").
    var primaryTitle: String? = nil
    var onToggle: () -> Void
    var onReview: (() -> Void)? = nil
    var onPrimary: (() -> Void)? = nil

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let unavailable = tile.status == .unavailable
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                HeroLens(module: tile.module, size: 22, parallax: false)
                    .frame(width: 30, height: 30)
                Text(tile.module.title.uppercased())
                    .font(SpruceFont.overline)
                    .tracking(0.8)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
                if showsCheckbox {
                    SpruceCheckbox(isOn: isSelected, module: tile.module, label: "Include \(tile.module.title)", action: onToggle)
                }
            }
            metric(ink)
            Text(tile.detail)
                .font(SpruceFont.callout)
                .foregroundStyle(ink.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: Spacing.s) {
                StatusPill(text: statusText, status: isScanning ? .info : tile.status)
                    .opacity(dimmed ? 0.45 : 1)
                Spacer(minLength: Spacing.s)
                if let onReview, !unavailable, !isScanning {
                    CapsuleButton(title: "Review", action: onReview)
                }
                if let primaryTitle, let onPrimary, !unavailable, !isScanning, tile.status != .clear {
                    CapsuleButton(title: primaryTitle, prominent: true, action: onPrimary)
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .prismSurface(radius: Radius.card, highlighted: hovering && !unavailable)
        .offset(y: hovering && !reduceMotion && !unavailable ? -2 : 0)
        .opacity(unavailable ? 0.45 : 1)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.standard, value: isSelected)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.module.title), \(isScanning ? "checking" : tile.headline), \(tile.detail)")
        .accessibilityValue(showsCheckbox ? (isSelected ? "selected" : "not selected") : statusText)
        .accessibilityAddTraits(showsCheckbox ? [.isButton] : [])
        .accessibilityAction {
            if showsCheckbox { onToggle() } else { onReview?() }
        }
        .accessibilityAction(named: "Review") { onReview?() }
    }

    private var showsCheckbox: Bool {
        !isScanning && tile.status != .unavailable && tile.status != .clear
    }

    private var dimmed: Bool { showsCheckbox && !isSelected }

    @ViewBuilder
    private func metric(_ ink: PrismInk) -> some View {
        if isScanning {
            HStack(spacing: Spacing.s) {
                ProgressRing(progress: nil, module: tile.module, lineWidth: 2)
                    .frame(width: 14, height: 14)
                Text("Checking…").font(SpruceFont.metricS).foregroundStyle(ink.secondary)
            }
            .frame(height: 40, alignment: .leading)
        } else if tile.status == .clear {
            HStack(spacing: Spacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(StatusColor.success)
                Text(tile.headline)
                    .font(SpruceFont.metricS)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(height: 40, alignment: .leading)
        } else {
            PrismMetricText(text: tile.headline, font: SpruceFont.metricL,
                            color: tile.status == .unavailable ? Ink.disabled : Ink.primary)
                .opacity(dimmed ? 0.45 : 1)
                .frame(height: 40, alignment: .leading)
        }
    }

    private var statusText: String {
        if isScanning { return "Checking…" }
        switch tile.status {
        case .clear: return "All good"
        case .attention: return tile.actionCount > 0 ? CountFormat.items(tile.actionCount, singular: "action") : "Recommended"
        case .critical: return "Needs attention"
        case .info: return "Info"
        case .unavailable: return "Skipped"
        }
    }
}

// MARK: - Standard journey

/// Complete standard journey for a `ScanFlowModel`. Modules with a simple
/// "scan → review list → remove" shape can use this directly.
struct ScanFlowScreen: View {
    @Bindable var flow: ScanFlowModel
    var idleTitle: String? = nil
    var idleSubtitle: String? = nil
    var features: [IdleFeature] = []
    var scanTitle: String = "Scan"
    var actionTitle: String = "Remove"
    var resultsTitle: String? = nil
    var notice: String? = nil
    var emptyTitle: String = "Nothing to clean"
    var emptyMessage: String = "Nothing here needs attention right now."

    @State private var scanStartedAt: Date?
    /// Scan › Run Selected… asks here first (the orb runs directly).
    @State private var confirmMenuRun = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            phaseContent
                .id(phaseKey)
                .transition(.prismPhase(reduceMotion: reduceMotion))
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: phaseKey)
        .onChange(of: phaseKey) { oldKey, newKey in
            if newKey == "scanning" {
                scanStartedAt = Date()
            } else if oldKey == "scanning" && newKey == "results" {
                if let start = scanStartedAt, Date().timeIntervalSince(start) >= 1.5 {
                    SpruceSound.play(.scanComplete)
                }
                scanStartedAt = nil
            }
            if newKey != "results" { confirmMenuRun = false }
        }
        .focusedSceneValue(\.spruceFlow, menuActions)
        .confirmationDialog(menuRunTitle, isPresented: $confirmMenuRun, titleVisibility: .visible) {
            Button(actionTitle, role: .destructive) {
                if flow.phase == .results { flow.run() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(ByteFormat.string(flow.selectedSize)) selected. Only the selected items are touched.")
        }
    }

    /// Scan and Edit menu actions; Run Selected… only opens the confirmation above.
    private var menuActions: SpruceFlowActions {
        var actions = flow.menuActions
        if flow.phase == .results && flow.selectedCount > 0 {
            actions.reviewAndRun = { confirmMenuRun = true }
        }
        return actions
    }

    private var menuRunTitle: String {
        "\(actionTitle) \(CountFormat.items(flow.selectedCount))?"
    }

    private var phaseKey: String {
        switch flow.phase {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .results: return "results"
        case .running: return "running"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch flow.phase {
        case .idle:
            ModuleIdleView(module: flow.module, title: idleTitle, subtitle: idleSubtitle, features: features,
                           actionTitle: scanTitle, notice: notice) {
                SpruceSound.play(.scanStart)
                flow.startScan()
            }
        case .scanning:
            ScanningView(module: flow.module, progress: flow.progress, onStop: { flow.cancel() })
        case .results:
            resultsContent
        case .running:
            ScanningView(module: flow.module, progress: flow.progress, title: "Working…")
        case .done:
            if let outcome = flow.outcome {
                DoneView(module: flow.module, outcome: outcome, flow: flow) { flow.showRemaining() }
            } else {
                EmptyStateView(module: flow.module, title: "All done", message: "Nothing else to do here.",
                               actionTitle: "Back", action: { flow.showRemaining() })
            }
        case .failed(let message):
            FailureView(module: flow.module, message: message) { flow.startScan() }
        }
    }

    private var resultsContent: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: resultsTitle ?? flow.module.title,
                         subtitle: "Found \(ByteFormat.string(flow.totalSize)) · \(CountFormat.items(flow.groups.allItems.count))",
                         backTitle: "Start Over", onBack: { flow.reset() }, module: flow.module)
            if flow.groups.allItems.isEmpty {
                EmptyStateView(module: flow.module, title: emptyTitle, message: emptyMessage,
                               actionTitle: "Scan Again", action: { flow.startScan() })
            } else {
                ReviewSplitView(module: flow.module, groups: $flow.groups, emptyTitle: emptyTitle, emptyMessage: emptyMessage,
                                onIgnore: { flow.ignore($0) })
                ResultsFooter(module: flow.module, selectedBytes: flow.selectedSize, selectedCount: flow.selectedCount,
                              actionTitle: actionTitle, totalBytes: flow.totalSize,
                              totalCount: flow.groups.allItems.count) { flow.run() }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }
}
