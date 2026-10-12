import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// The focused folder's children as a list beside the map: checkbox (or the reason an
/// item is protected), icon, name, description, size with share bar, and a chevron to
/// zoom in. Hovering a row highlights its bubble and vice versa.
struct SpaceMapListPanel: View {
    let screen: SpaceMapScreenModel
    let focus: SpaceMapNode
    var hasFullDiskAccess: Bool

    var body: some View {
        let groups = screen.focusGroups
        VStack(spacing: 0) {
            SpaceMapListHeader(screen: screen, focus: focus)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.s)
            Rectangle().fill(Ink.hairline).frame(height: 1)
            if focus.children.isEmpty {
                emptyFolder
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(groups.visible) { node in
                                SpaceMapListRow(screen: screen, node: node, total: focus.size)
                                    .id(node.id)
                            }
                            if let smaller = groups.smaller {
                                SpaceMapSmallerRow(screen: screen, group: smaller, total: focus.size)
                                    .id("smaller")
                                if screen.showsSmallerItems {
                                    ForEach(smaller.nodes) { node in
                                        SpaceMapListRow(screen: screen, node: node, total: focus.size, indent: 14)
                                            .id(node.id)
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: screen.showsSmallerItems) { _, expanded in
                        if expanded {
                            withAnimation(Motion.standard) { proxy.scrollTo("smaller", anchor: .top) }
                        }
                    }
                }
            }
            footer
        }
        .prismSurface(radius: Radius.panel)
    }

    private var emptyFolder: some View {
        VStack(spacing: Spacing.s) {
            Spacer()
            Image(systemName: focus.isUnreadable ? "lock.fill" : "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Ink.tertiary)
            Text(focus.isUnreadable ? "Spruce couldn't read this folder" : "This folder is empty")
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.l)
    }

    @ViewBuilder
    private var footer: some View {
        let unreadable = screen.result?.stats.unreadableFolders ?? 0
        if unreadable > 0 && !hasFullDiskAccess {
            Rectangle().fill(Ink.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(StatusColor.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(CountFormat.items(unreadable, singular: "folder", plural: "folders")) couldn't be read; their space is counted under System & snapshots.")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PrismTextButton(title: "Grant Full Disk Access", symbol: "arrow.up.right", module: .spaceMap) {
                        Permissions.openFullDiskAccessSettings()
                    }
                }
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Folder name, total and quick actions above the list.
struct SpaceMapListHeader: View {
    let screen: SpaceMapScreenModel
    let focus: SpaceMapNode

    var body: some View {
        HStack(spacing: Spacing.s) {
            ItemIcon(url: focus.url, symbol: SpaceMapFileType.of(focus).symbol, size: 30, module: .spaceMap)
            VStack(alignment: .leading, spacing: 1) {
                Text(focus.name)
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(ByteFormat.string(focus.size)) · \(CountFormat.items(focus.itemCount))")
                    .font(SpruceFont.caption.monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: Spacing.xs)
            if screen.isRescanning(focus) {
                ProgressView()
                    .controlSize(.small)
                    .help("Rescanning…")
            } else if focus.isReal {
                PrismIconButton(symbol: "arrow.clockwise", help: "Rescan this folder") {
                    screen.rescan(focus)
                }
            }
            if focus.isReal {
                PrismIconButton(symbol: "magnifyingglass.circle", help: "Reveal in Finder") {
                    screen.reveal(screen.highlighted ?? focus)
                }
            }
        }
    }
}

/// One child of the focused folder.
struct SpaceMapListRow: View {
    let screen: SpaceMapScreenModel
    let node: SpaceMapNode
    let total: Int64
    var indent: CGFloat = 0

    @State private var hovering = false

    var body: some View {
        let isHighlighted = screen.highlighted === node || screen.hovered === node
        HStack(spacing: 10) {
            selector
            ItemIcon(url: node.url, symbol: node.isUnreadable ? "lock.fill" : SpaceMapFileType.of(node).symbol,
                     size: 24, module: .spaceMap)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(SpruceFont.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(screen.subtitle(for: node))
                    .font(SpruceFont.caption)
                    .foregroundStyle(node.isUnreadable ? StatusColor.warning : Ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormat.string(node.size))
                    .font(SpruceFont.callout.monospacedDigit())
                    .foregroundStyle(node.size >= 1_000_000_000 ? ModuleID.spaceMap.palette.accentText : Ink.secondary)
                SpaceMapShareBar(share: total > 0 ? Double(node.size) / Double(total) : 0,
                                 color: SpaceMapStyle.color(for: node, rank: 0))
                    .frame(width: 54, height: 3)
            }
            zoomButton
        }
        .padding(.leading, 8 + indent)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(isHighlighted ? Ink.selectedFill : (hovering ? Ink.subtleFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                if screen.hovered !== node { screen.hovered = node }
            } else if screen.hovered === node {
                screen.hovered = nil
            }
        }
        .onTapGesture(count: 2) {
            if node.canZoom { screen.zoom(into: node) } else { screen.quickLook(node) }
        }
        .onTapGesture {
            screen.highlighted = screen.highlighted === node ? nil : node
        }
        .contextMenu { SpaceMapNodeMenu(screen: screen, node: node) }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.name), \(ByteFormat.string(node.size))")
        .accessibilityAction(named: "Open") { if node.canZoom { screen.zoom(into: node) } }
    }

    @ViewBuilder
    private var selector: some View {
        let reason = screen.protection(of: node).reason
        if reason == nil || screen.isSelected(node) {
            SpruceCheckbox(state: screen.selectionState(of: node), module: .spaceMap, label: node.name) {
                screen.toggle(node)
            }
            .disabled(screen.isCovered(node))
            .help(screen.isCovered(node) ? "Included because its folder is selected" : "Select for removal")
        } else {
            Image(systemName: node.kind == .system || node.kind == .smallFiles ? "info.circle" : "lock.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Ink.tertiary)
                .frame(width: 16, height: 16)
                .help(reason ?? "")
                .accessibilityLabel(reason ?? "Protected")
        }
    }

    @ViewBuilder
    private var zoomButton: some View {
        if node.canZoom {
            Button {
                screen.zoom(into: node)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Ink.primary : Ink.tertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PrismPressStyle())
            .help("Open \(node.name)")
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }
}

/// The "N smaller items" row; expands the folded items in place.
struct SpaceMapSmallerRow: View {
    let screen: SpaceMapScreenModel
    let group: SpaceMapSmallerGroup
    let total: Int64

    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(Motion.standard) { screen.showsSmallerItems.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: screen.showsSmallerItems ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
                    .frame(width: 16, height: 16)
                ItemIcon(url: nil, symbol: "ellipsis.circle.fill", size: 24, module: .spaceMap)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title)
                        .font(SpruceFont.body)
                        .foregroundStyle(Ink.primary)
                    Text(screen.showsSmallerItems ? "Shown below" : "Too small to draw one by one")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                }
                Spacer(minLength: Spacing.xs)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(ByteFormat.string(group.bytes))
                        .font(SpruceFont.callout.monospacedDigit())
                        .foregroundStyle(Ink.secondary)
                    SpaceMapShareBar(share: total > 0 ? Double(group.bytes) / Double(total) : 0,
                                     color: Color.white.opacity(0.5))
                        .frame(width: 54, height: 3)
                }
                Color.clear.frame(width: 22, height: 22)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(screen.hoveringSmaller || hovering ? Ink.subtleFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if screen.hoveringSmaller != inside { screen.hoveringSmaller = inside }
        }
    }
}

/// Thin share-of-folder bar.
struct SpaceMapShareBar: View {
    var share: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(min(max(share, 0), 1))))
            }
        }
        .accessibilityHidden(true)
    }
}
