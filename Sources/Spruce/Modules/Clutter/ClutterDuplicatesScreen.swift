import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Duplicates: sets of identical files on the left (thumbnail, name, copies, space to
/// free); the focused set on the right with a large preview, the reason for the
/// suggested keeper, a "Select" menu and every copy with Keep This.
struct ClutterDuplicatesScreen: View {
    @Bindable var screen: ClutterScreenModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ClutterToolHeader(screen: screen, tool: .duplicates, subtitle: subtitle) {
                PrismSearchField(text: $screen.duplicatesSearch, prompt: "Search names or folders", width: 210)
                ClutterMenuButton(title: "Select", symbol: "checklist") {
                    ForEach(ClutterCopySelection.allCases) { mode in
                        Button {
                            screen.selectCopies(mode)
                        } label: {
                            Label(mode == .clear ? "Deselect All" : "\(mode.title) in Every Set", systemImage: mode.symbol)
                        }
                    }
                }
            }
            if (screen.report?.duplicates ?? []).isEmpty {
                ClutterEmptyPane(title: "No duplicates",
                                 message: "Every file Spruce compared is one of a kind.")
                    .clutterPane()
            } else {
                HStack(alignment: .top, spacing: Spacing.m) {
                    ClutterDuplicateList(screen: screen)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                        .clutterPane()
                    Group {
                        if let group = screen.focusedDuplicate {
                            ClutterDuplicateDetail(screen: screen, group: group)
                        } else {
                            ClutterEmptyPane(title: "No matches",
                                             message: "No duplicate matches “\(screen.duplicatesSearch)”.",
                                             symbol: "magnifyingglass")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clutterPane()
                }
            }
            ClutterToolFooter(screen: screen, tool: .duplicates)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var subtitle: String {
        let summary = screen.summary(for: .duplicates)
        guard !summary.isEmpty else { return "Compared by content, not by name" }
        return "\(summary.headline) · \(summary.detail) · compared by content"
    }
}

/// The list of duplicate sets.
struct ClutterDuplicateList: View {
    @Bindable var screen: ClutterScreenModel

    var body: some View {
        let groups = screen.visibleDuplicates
        let focusedID = screen.focusedDuplicate?.id
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(groups) { group in
                    ClutterDuplicateGroupRow(screen: screen, group: group, isFocused: group.id == focusedID)
                }
            }
            .padding(Spacing.xs)
        }
        .scrollIndicators(.automatic)
    }
}

/// One duplicate set in the list: checkbox, thumbnail, keeper name, copies and size.
struct ClutterDuplicateGroupRow: View {
    @Bindable var screen: ClutterScreenModel
    var group: ClutterDuplicateGroup
    var isFocused: Bool

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let paths = group.files.map(\.path)
        let state = screen.selectionState(of: paths)
        HStack(spacing: Spacing.s) {
            SpruceCheckbox(state: state, module: .clutter, label: group.displayName) {
                screen.toggleDuplicateGroup(group)
            }
            ClutterThumbnail(path: group.keeperPath, side: 36,
                             symbol: group.keeper?.kind.symbol ?? "doc.on.doc",
                             fills: group.keeper?.kind == .pictures || group.keeper?.kind == .movies)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayName)
                    .font(SpruceFont.body.weight(isFocused ? .semibold : .regular))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(group.files.count) copies · \(ByteFormat.string(group.fileSize)) each")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(ByteFormat.string(group.reclaimableBytes))
                .font(SpruceFont.callout.monospacedDigit())
                .foregroundStyle(ink.secondary)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(isFocused ? ink.selectedFill : (hovering ? ink.subtleFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { screen.focusedDuplicateID = group.id }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.displayName), \(group.files.count) copies, \(ByteFormat.string(group.reclaimableBytes)) to free")
        .accessibilityAddTraits(.isButton)
    }
}

/// The focused duplicate set: preview, facts, selection menu and its copies.
struct ClutterDuplicateDetail: View {
    @Bindable var screen: ClutterScreenModel
    var group: ClutterDuplicateGroup

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                summary
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        SectionHeader(title: "Copies", trailing: selectionLine)
                    }
                    VStack(spacing: 2) {
                        ForEach(group.files) { file in
                            ClutterFileRow(screen: screen, file: file, chips: chips(for: file),
                                           dateText: "Created \(DurationFormat.relative(file.originDate))",
                                           onKeep: { screen.keepOnly(file.path) })
                        }
                    }
                }
            }
            .padding(Spacing.l)
        }
        .scrollIndicators(.automatic)
    }

    private var summary: some View {
        let ink = PrismInk(contrast)
        let keeper = group.keeper ?? group.files.first
        return HStack(alignment: .top, spacing: Spacing.l) {
            ClutterThumbnail(path: group.keeperPath, side: 150, symbol: keeper?.kind.symbol ?? "doc.on.doc",
                             fills: false, cornerRadius: Radius.row)
                .onTapGesture(count: 2) { screen.quickLook(group.keeperPath) }
                .help("Double-click for Quick Look")
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(group.displayName)
                    .font(SpruceFont.title)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let keeper {
                    ClutterFactGrid(facts: [
                        ("Kind", keeper.kind.title),
                        ("Size", "\(ByteFormat.string(group.fileSize)) each"),
                        ("Copies", "\(group.files.count) · \(ByteFormat.string(group.reclaimableBytes)) to free"),
                        ("Created", keeper.originDate.formatted(date: .abbreviated, time: .shortened)),
                        ("Modified", keeper.modified.formatted(date: .abbreviated, time: .shortened)),
                    ])
                }
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill").foregroundStyle(StatusColor.success)
                    Text(group.keeperReason.isEmpty ? "One copy is always kept." : "\(group.keeperReason).")
                        .foregroundStyle(ink.secondary)
                }
                .font(SpruceFont.callout)
                HStack(spacing: Spacing.s) {
                    ClutterMenuButton(title: "Select", symbol: "checklist") {
                        ForEach(ClutterCopySelection.allCases) { mode in
                            Button {
                                screen.selectCopies(mode, in: group.id)
                            } label: {
                                Label(mode.title, systemImage: mode.symbol)
                            }
                        }
                    }
                    CapsuleButton(title: "Quick Look", symbol: "eye") { screen.quickLook(group.keeperPath) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var selectionLine: String {
        let paths = group.files.map(\.path)
        let selected = paths.filter { screen.isSelected($0) }.count
        let kept = paths.count - selected
        if kept == 0 { return "every copy selected" }
        return "\(selected) selected · \(kept) kept"
    }

    private func chips(for file: ClutterFile) -> [ClutterRowChip] {
        var chips: [ClutterRowChip] = []
        if file.path == group.keeperPath { chips.append(.keeper) }
        if ClutterSmartSelection().isCloud(file) { chips.append(.cloud) }
        if ClutterPaths().isInDownloads(file.path) {
            chips.append(ClutterRowChip(text: "Downloads", symbol: "arrow.down.circle", color: StatusColor.info))
        }
        return chips
    }
}

/// Label/value pairs in two aligned columns.
struct ClutterFactGrid: View {
    var facts: [(String, String)]

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: 4) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                GridRow {
                    Text(fact.0)
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                    Text(fact.1)
                        .font(SpruceFont.callout.monospacedDigit())
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}
