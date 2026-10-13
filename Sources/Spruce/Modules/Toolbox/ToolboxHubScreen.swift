import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Toolbox landing: search, favourites, then every tool grouped by module.
struct ToolboxHubScreen: View {
    @Bindable var screen: ToolboxScreenModel
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: Spacing.m, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                if screen.isSearching {
                    searchResults
                } else {
                    favoritesSection
                    ForEach(ToolboxGroup.allCases, id: \.self) { group in
                        let tools = ToolboxCatalog.all.filter { $0.group == group }
                        if !tools.isEmpty {
                            groupSection(group, tools: tools)
                        }
                    }
                }
            }
            .frame(maxWidth: Spacing.readableWidth)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.topInset + Spacing.l)
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .background {
            // ⌘F focuses the search field.
            Button("Search Tools") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            HeroLens(module: .toolbox, size: 84, parallax: false)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Toolbox")
                    .font(SpruceFont.display(34))
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(ModuleID.toolbox.tagline)
                    .font(SpruceFont.body)
                    .foregroundStyle(PrismInk(contrast).secondary)
                Text("\(ToolboxCatalog.all.count) tools · star the ones you use most")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).tertiary)
            }
            Spacer(minLength: Spacing.m)
            ToolboxSearchField(text: $screen.query, isFocused: $searchFocused) {
                if let first = screen.results.first { screen.open(first, model: model) }
            }
        }
    }

    // MARK: Sections

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                SectionHeader(title: "Favorites", symbol: "star.fill")
                Spacer()
                if screen.favorites != ToolboxCatalog.defaultFavorites {
                    PrismTextButton(title: "Reset", module: .toolbox) { screen.resetFavorites() }
                        .help("Go back to the default favourites")
                }
            }
            if screen.favoriteTools.isEmpty {
                Text("Star any tool to keep it here.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .padding(.vertical, Spacing.s)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.m) {
                    ForEach(screen.favoriteTools) { tool in
                        tile(tool, inFavorites: true)
                    }
                }
            }
        }
    }

    private func groupSection(_ group: ToolboxGroup, tools: [ToolboxTool]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: group.title, trailing: CountFormat.items(tools.count, singular: "tool"))
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.m) {
                ForEach(tools) { tool in
                    tile(tool, inFavorites: false)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = screen.results
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Results", trailing: CountFormat.items(results.count, singular: "tool"))
            if results.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("No tool called \u{201C}\(screen.query.trimmingCharacters(in: .whitespaces))\u{201D}.")
                        .font(SpruceFont.body)
                        .foregroundStyle(PrismInk(contrast).secondary)
                    PrismTextButton(title: "Look for files with Space Map", symbol: "arrow.right", module: .toolbox) {
                        model.open(.spaceMap, tool: "spaceMap")
                    }
                }
                .padding(.vertical, Spacing.s)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.m) {
                    ForEach(results) { tool in
                        tile(tool, inFavorites: false)
                    }
                }
            }
        }
    }

    private func tile(_ tool: ToolboxTool, inFavorites: Bool) -> some View {
        var move: ((Int) -> Void)?
        if inFavorites {
            move = { offset in screen.moveFavorite(tool.id, by: offset) }
        }
        return ToolboxToolTile(tool: tool,
                               isFavorite: screen.isFavorite(tool.id),
                               needsAccess: tool.prefersFullDiskAccess && !model.hasFullDiskAccess,
                               onOpen: { screen.open(tool, model: model) },
                               onToggleFavorite: { screen.toggleFavorite(tool.id) },
                               onMove: move)
    }
}

// MARK: - Search field

struct ToolboxSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink.tertiary)
            TextField("Search tools", text: $text)
                .textFieldStyle(.plain)
                .font(SpruceFont.body)
                .foregroundStyle(Ink.primary)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .onExitCommand {
                    text = ""
                    isFocused.wrappedValue = false
                }
            if text.isEmpty {
                Text("⌘F")
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
            } else {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ink.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 260, height: 32)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(ink.controlFill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? Color.white.opacity(0.35) : ink.hairline, lineWidth: 1)
        )
        .animation(Motion.quick, value: isFocused.wrappedValue)
    }
}

// MARK: - Tile

struct ToolboxToolTile: View {
    var tool: ToolboxTool
    var isFavorite: Bool
    var needsAccess: Bool
    var onOpen: () -> Void
    var onToggleFavorite: () -> Void
    /// Set for tiles in the Favourites section (reorder from the context menu).
    var onMove: ((Int) -> Void)?

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top) {
                    PrismCategoryBadge(symbol: tool.symbol, module: tool.tint, size: 40)
                    Spacer(minLength: Spacing.s)
                    // Room for the star overlay.
                    Color.clear.frame(width: 26, height: 26)
                }
                HStack(spacing: Spacing.xs) {
                    Text(tool.title)
                        .font(SpruceFont.headline)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    if tool.isQuickAction {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(tool.tint.palette.accentText)
                            .help("Works right here, without a scan")
                    }
                }
                Text(tool.caption)
                    .font(SpruceFont.caption)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: Spacing.xs) {
                    Text(locationLabel)
                        .font(SpruceFont.caption)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                    if needsAccess {
                        PrismChip(text: "Needs Full Disk Access", color: StatusColor.warning, symbol: "lock.fill")
                    }
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .prismSurface(radius: Radius.card, highlighted: hovering)
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PrismPressStyle())
        .overlay(alignment: .topTrailing) {
            starButton
                .padding(Spacing.m)
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu {
            Button("Open", action: onOpen)
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
            if let onMove {
                Divider()
                Button("Move Earlier") { onMove(-1) }
                Button("Move Later") { onMove(1) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(tool.title). \(tool.caption)"))
    }

    private var locationLabel: String {
        tool.isToolboxOnly ? "Toolbox" : tool.module.title
    }

    @ViewBuilder
    private var starButton: some View {
        if isFavorite || hovering {
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isFavorite ? StatusColor.warning : Ink.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Ink.controlFill))
                    .contentShape(Circle())
            }
            .buttonStyle(PrismPressStyle(pressedScale: 0.9))
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(isFavorite ? "Remove \(tool.title) from Favorites" : "Add \(tool.title) to Favorites")
            .transition(.opacity)
        }
    }
}
