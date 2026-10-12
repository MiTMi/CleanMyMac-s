import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Colours

/// Original Space Map palette: folders on a violet → pink ramp by size rank, files by
/// type, folded and pseudo items in neutral tones, selection in the removal rose.
enum SpaceMapStyle {
    static let selection = Color(hex: 0xFF5C8A)
    static let smaller = Color.white.opacity(0.16)
    static let system = Color(hex: 0x5B6585)
    static let unreadable = StatusColor.warning

    static func color(for node: SpaceMapNode, rank: Int) -> Color {
        if node.isUnreadable { return unreadable }
        let palette = ModuleID.spaceMap.palette
        switch SpaceMapFileType.of(node) {
        case .folder:
            let t = min(1, Double(rank) / 14)
            return palette.accent.prismMix(palette.accent2, t)
        case .application: return Color(hex: 0x5CC8FF)
        case .package: return Color(hex: 0x6F8CFF)
        case .video: return Color(hex: 0xFFB35C)
        case .audio: return Color(hex: 0xFF7FA3)
        case .image: return Color(hex: 0xFFD75E)
        case .archive: return Color(hex: 0x9BE36F)
        case .diskImage: return Color(hex: 0x4FD6C8)
        case .document: return Color(hex: 0x8DB6FF)
        case .code: return Color(hex: 0xB4ABDF)
        case .other: return Color(hex: 0xA59FC9)
        case .smallFiles: return Color(hex: 0x8C86A8)
        case .system: return system
        }
    }

    /// Deeper rings and inner bubbles get lighter.
    static func color(for node: SpaceMapNode, rank: Int, depth: Int) -> Color {
        let base = color(for: node, rank: rank)
        return depth <= 1 ? base : base.prismMix(.white, min(0.45, Double(depth - 1) * 0.13))
    }
}

// MARK: - Capacity bar

/// Volume usage: used (accent), the purgeable part (lighter, at the end of used) and the
/// current selection as a rose overlay at the end of the used part.
struct SpaceMapCapacityBar: View {
    var volume: SpaceMapVolumeInfo
    var selectedBytes: Int64 = 0
    var height: CGFloat = 8

    var body: some View {
        let palette = ModuleID.spaceMap.palette
        GeometryReader { geo in
            let width = geo.size.width
            let capacity = max(Double(volume.capacity), 1)
            let usedWidth = width * CGFloat(min(1, Double(volume.used) / capacity))
            let purgeableWidth = min(usedWidth, width * CGFloat(Double(volume.purgeable) / capacity))
            let selectedWidth = min(usedWidth, width * CGFloat(Double(selectedBytes) / capacity))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [palette.accent, palette.accent2], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(usedWidth, height))
                if purgeableWidth > 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: purgeableWidth)
                        .offset(x: usedWidth - purgeableWidth)
                }
                if selectedWidth > 0 {
                    Rectangle()
                        .fill(SpaceMapStyle.selection)
                        .frame(width: max(2, selectedWidth))
                        .offset(x: usedWidth - max(2, selectedWidth))
                }
            }
            .clipShape(Capsule())
            .animation(Motion.standard, value: selectedBytes)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(volume.name) usage")
        .accessibilityValue("\(ByteFormat.string(volume.used)) used of \(ByteFormat.string(volume.capacity))")
    }
}

// MARK: - Hover card

/// What the hover card describes.
enum SpaceMapHoverSubject {
    case node(SpaceMapNode)
    case smaller(SpaceMapSmallerGroup)
}

/// Floating details for the item under the pointer.
struct SpaceMapHoverCard: View {
    let screen: SpaceMapScreenModel
    let subject: SpaceMapHoverSubject
    /// Size the share is measured against (the focused folder).
    let total: Int64

    static let width: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch subject {
            case .node(let node): nodeContent(node)
            case .smaller(let group): smallerContent(group)
            }
        }
        .padding(Spacing.m)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.container, style: .continuous).fill(.regularMaterial))
        .background(RoundedRectangle(cornerRadius: Radius.container, style: .continuous).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: Radius.container, style: .continuous).strokeBorder(Ink.hairline))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func nodeContent(_ node: SpaceMapNode) -> some View {
        HStack(spacing: Spacing.s) {
            ItemIcon(url: node.url, symbol: SpaceMapFileType.of(node).symbol, size: 26, module: .spaceMap)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                Text(SpaceMapFileType.of(node).label)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
        HStack(alignment: .firstTextBaseline) {
            Text(ByteFormat.string(node.size))
                .font(SpruceFont.metricS)
                .foregroundStyle(ModuleID.spaceMap.palette.accentText)
            Spacer()
            if total > 0 {
                Text(PrismMetric.percentText(Double(node.size) / Double(total)))
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.secondary)
            }
        }
        if node.kind == .system {
            Text(screen.systemNodeDetail)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(screen.subtitle(for: node))
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            detailLines(node)
        }
        if screen.isSelected(node) || screen.isCovered(node) {
            Label("Selected for removal", systemImage: "checkmark.circle.fill")
                .font(SpruceFont.caption.weight(.semibold))
                .foregroundStyle(SpaceMapStyle.selection)
        } else if node.isReal, let reason = screen.protection(of: node).reason, node.parent != nil {
            Label(reason, systemImage: "lock.fill")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func detailLines(_ node: SpaceMapNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if node.isFolder || node.kind == .smallFiles {
                Text(CountFormat.items(node.fileCount, singular: "file", plural: "files")
                     + (node.folderCount > 0 ? " · " + CountFormat.items(node.folderCount, singular: "folder", plural: "folders") : ""))
            }
            if let modified = node.modified {
                Text("Modified \(DurationFormat.relative(modified))")
            }
            if node.cloudOnlyBytes > 0 {
                Text("+ \(ByteFormat.string(node.cloudOnlyBytes)) in the cloud only")
            }
        }
        .font(SpruceFont.captionDigits)
        .foregroundStyle(Ink.tertiary)
    }

    @ViewBuilder
    private func smallerContent(_ group: SpaceMapSmallerGroup) -> some View {
        HStack(spacing: Spacing.s) {
            ItemIcon(url: nil, symbol: "ellipsis.circle.fill", size: 26, module: .spaceMap)
            Text(group.title)
                .font(SpruceFont.bodyStrong)
                .foregroundStyle(Ink.primary)
        }
        Text(ByteFormat.string(group.bytes))
            .font(SpruceFont.metricS)
            .foregroundStyle(ModuleID.spaceMap.palette.accentText)
        Text("Each is too small to draw. Click to list them.")
            .font(SpruceFont.caption)
            .foregroundStyle(Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Top-left corner for a card near `point`, kept inside `bounds` and off the pointer.
    static func origin(near point: CGPoint, in bounds: CGSize, estimatedHeight: CGFloat = 170) -> CGPoint {
        var x = point.x + 18
        var y = point.y + 18
        if x + width > bounds.width - 6 { x = point.x - width - 18 }
        if y + estimatedHeight > bounds.height - 6 { y = max(6, bounds.height - estimatedHeight - 6) }
        return CGPoint(x: max(6, x), y: max(6, y))
    }
}

// MARK: - Context menu

/// Actions for one item (list rows and the map).
struct SpaceMapNodeMenu: View {
    let screen: SpaceMapScreenModel
    let node: SpaceMapNode

    var body: some View {
        if node.canZoom {
            Button("Open") { screen.zoom(into: node) }
        }
        if node.isReal && node.parent != nil {
            if screen.isSelected(node) {
                Button("Deselect") { screen.toggle(node) }
            } else if screen.isSelectable(node) && !screen.isCovered(node) {
                Button("Select for Removal") { screen.toggle(node) }
            }
            Divider()
        }
        if node.isReal {
            Button("Reveal in Finder") { screen.reveal(node) }
            Button("Quick Look") { screen.quickLook(node) }
            Button("Copy Path") { screen.copyPath(node) }
        }
        if node.isFolder && node.isReal {
            Button("Rescan Folder") { screen.rescan(node) }
        }
        if node.isReal && node.parent != nil {
            Divider()
            Button("Never Offer for Removal") { screen.ignore(node) }
        }
    }
}

// MARK: - Removal sheet

/// "Check Selection": every selected item with its location and size; unticking keeps
/// the row so it can be ticked again. Confirming moves the ticked items to the Trash.
struct SpaceMapRemovalSheet: View {
    let screen: SpaceMapScreenModel
    @State private var rows: [SpaceMapNode] = []
    @State private var excluded: Set<ObjectIdentifier> = []

    private var included: [SpaceMapNode] { rows.filter { !excluded.contains($0.id) } }
    private var includedBytes: Int64 { included.reduce(0) { $0 + $1.size } }

    var body: some View {
        PrismSheetCard(
            title: included.isEmpty ? "Nothing to move" : "Move \(CountFormat.items(included.count)) to the Trash?",
            message: "You can put them back from the Trash until you empty it. The space is freed when the Trash is emptied.",
            primaryTitle: "Move to Trash",
            isPrimaryEnabled: !included.isEmpty,
            onCancel: { screen.removalSheetShown = false },
            onPrimary: { screen.confirmRemoval(included) }
        ) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(rows) { node in
                            row(node)
                        }
                    }
                }
                .frame(maxHeight: 260)
                HStack {
                    Text("Total")
                        .font(SpruceFont.callout)
                        .foregroundStyle(Ink.secondary)
                    Spacer()
                    Text(ByteFormat.string(includedBytes))
                        .font(SpruceFont.bodyStrong.monospacedDigit())
                        .foregroundStyle(Ink.primary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, Spacing.s)
            }
        }
        .onAppear {
            rows = screen.selection.sorted(by: SpaceMapNode.isOrderedBefore)
        }
    }

    private func row(_ node: SpaceMapNode) -> some View {
        let isIncluded = !excluded.contains(node.id)
        return HStack(spacing: Spacing.s) {
            SpruceCheckbox(isOn: isIncluded, module: .spaceMap, label: node.name) {
                if isIncluded { excluded.insert(node.id) } else { excluded.remove(node.id) }
            }
            ItemIcon(url: node.url, symbol: SpaceMapFileType.of(node).symbol, size: 24, module: .spaceMap)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(SpruceFont.body)
                    .foregroundStyle(isIncluded ? Ink.primary : Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text((node.parent?.path ?? node.path).abbreviatingHome)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.s)
            Text(ByteFormat.string(node.size))
                .font(SpruceFont.callout.monospacedDigit())
                .foregroundStyle(isIncluded ? Ink.primary : Ink.tertiary)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.subtleFill))
    }
}
