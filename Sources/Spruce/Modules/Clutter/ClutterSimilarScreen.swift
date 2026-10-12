import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Similar Images: sets of nearly identical pictures on the left; the focused set as a
/// grid of large thumbnails with the best shot marked. Nothing is selected for the user;
/// "Select All but Best" does it in one click.
struct ClutterSimilarScreen: View {
    @Bindable var screen: ClutterScreenModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ClutterToolHeader(screen: screen, tool: .similarImages, subtitle: subtitle) {
                PrismSearchField(text: $screen.similarSearch, prompt: "Search names or folders", width: 210)
                ClutterMenuButton(title: "Select", symbol: "checklist") {
                    Button {
                        screen.selectAllButBest()
                    } label: {
                        Label("All but the Best Shot in Every Set", systemImage: "star")
                    }
                    Button {
                        screen.deselectAll(in: .similarImages)
                    } label: {
                        Label("Deselect All", systemImage: "circle")
                    }
                }
            }
            if (screen.report?.similar ?? []).isEmpty {
                ClutterEmptyPane(title: "No similar images",
                                 message: "None of your pictures look nearly the same as another.")
                    .clutterPane()
            } else {
                HStack(alignment: .top, spacing: Spacing.m) {
                    ClutterClusterList(screen: screen)
                        .frame(width: 280)
                        .frame(maxHeight: .infinity)
                        .clutterPane()
                    Group {
                        if let cluster = screen.focusedCluster {
                            ClutterClusterDetail(screen: screen, cluster: cluster)
                        } else {
                            ClutterEmptyPane(title: "No matches",
                                             message: "No picture matches “\(screen.similarSearch)”.",
                                             symbol: "magnifyingglass")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clutterPane()
                }
            }
            ClutterToolFooter(screen: screen, tool: .similarImages)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var subtitle: String {
        let summary = screen.summary(for: .similarImages)
        guard !summary.isEmpty else { return "Pictures that look nearly the same" }
        return "\(summary.headline) · \(summary.detail) · up to \(ByteFormat.string(summary.reclaimableBytes)) to free"
    }
}

/// The list of similar-image sets.
struct ClutterClusterList: View {
    @Bindable var screen: ClutterScreenModel

    var body: some View {
        let clusters = screen.visibleClusters
        let focusedID = screen.focusedCluster?.id
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(clusters) { cluster in
                    ClutterClusterRow(screen: screen, cluster: cluster, isFocused: cluster.id == focusedID)
                }
            }
            .padding(Spacing.xs)
        }
        .scrollIndicators(.automatic)
    }
}

/// One similar-image set: checkbox, stacked thumbnails, best shot's name, image count.
struct ClutterClusterRow: View {
    @Bindable var screen: ClutterScreenModel
    var cluster: ClutterSimilarCluster
    var isFocused: Bool

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let state = screen.selectionState(of: cluster.files.map(\.path))
        HStack(spacing: Spacing.s) {
            SpruceCheckbox(state: state, module: .clutter, label: cluster.best?.name ?? "Similar images") {
                screen.toggleCluster(cluster)
            }
            ZStack {
                if let second = cluster.others.first {
                    ClutterThumbnail(path: second.path, side: 34, symbol: "photo")
                        .rotationEffect(.degrees(7))
                        .offset(x: 5, y: -2)
                        .opacity(0.8)
                }
                ClutterThumbnail(path: cluster.bestPath, side: 36, symbol: "photo")
                    .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
            }
            .frame(width: 46, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(cluster.best?.name ?? "Similar images")
                    .font(SpruceFont.body.weight(isFocused ? .semibold : .regular))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(CountFormat.items(cluster.files.count, singular: "image")) · \(ByteFormat.string(cluster.totalBytes))")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(isFocused ? ink.selectedFill : (hovering ? ink.subtleFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { screen.focusedClusterID = cluster.id }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cluster.best?.name ?? "Similar images"), \(CountFormat.items(cluster.files.count, singular: "image"))")
        .accessibilityAddTraits(.isButton)
    }
}

/// The focused set as a grid of image cards.
struct ClutterClusterDetail: View {
    @Bindable var screen: ClutterScreenModel
    var cluster: ClutterSimilarCluster

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(CountFormat.items(cluster.files.count, singular: "similar image"))")
                        .font(SpruceFont.headline)
                        .foregroundStyle(Ink.primary)
                    Text(selectionLine)
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(ink.tertiary)
                }
                Spacer()
                CapsuleButton(title: "Select All but Best", symbol: "star") { screen.selectAllButBest(cluster.id) }
                CapsuleButton(title: "Deselect", symbol: "circle") {
                    screen.setSelected(cluster.files.map(\.path), false)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            Divider().overlay(Ink.hairline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 240), spacing: Spacing.m)],
                          spacing: Spacing.m) {
                    ForEach(cluster.files) { file in
                        ClutterImageCard(screen: screen, file: file, isBest: file.path == cluster.bestPath,
                                         fingerprint: cluster.fingerprints[file.path])
                    }
                }
                .padding(Spacing.l)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var selectionLine: String {
        let selected = cluster.files.filter { screen.isSelected($0.path) }
        if selected.isEmpty { return "Nothing selected · pick the ones you don't need" }
        if selected.count == cluster.files.count { return "Every image selected" }
        return "\(selected.count) selected · \(ByteFormat.string(selected.reduce(0) { $0 + $1.size }))"
    }
}

/// One picture of a similar set: large thumbnail, checkbox, best-shot badge, details and
/// Quick Look / Keep This.
struct ClutterImageCard: View {
    @Bindable var screen: ClutterScreenModel
    var file: ClutterFile
    var isBest: Bool
    var fingerprint: ClutterImageFingerprint?

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let selected = screen.isSelected(file.path)
        let accent = ModuleID.clutter.palette.accent
        VStack(alignment: .leading, spacing: Spacing.s) {
            GeometryReader { geo in
                ClutterThumbnail(path: file.path, side: max(16, min(geo.size.width, geo.size.height)), symbol: "photo",
                                 fills: true, cornerRadius: Radius.row, requestSide: 240)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                SpruceCheckbox(isOn: selected, module: .clutter, label: file.name) { screen.toggle(file.path) }
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if isBest {
                    PrismChip(text: "Best shot", color: StatusColor.success, symbol: "star.fill")
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hovering {
                    hoverActions
                        .padding(8)
                        .transition(.opacity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(SpruceFont.callout.weight(.medium))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailLine)
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                Text(file.parentPath.abbreviatingHome)
                    .font(SpruceFont.mono)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Radius.row + 4, style: .continuous)
                .fill(selected ? accent.opacity(0.14) : (hovering ? ink.subtleFill : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row + 4, style: .continuous)
                .strokeBorder(selected ? accent.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { screen.toggle(file.path) }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: selected)
        .contextMenu { ClutterFileMenu(screen: screen, path: file.path, onKeep: { screen.keepOnly(file.path) }) }
        .help(file.path.abbreviatingHome)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(file.name)\(isBest ? ", best shot" : ""), \(detailLine)")
        .accessibilityValue(selected ? "selected" : "not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { screen.toggle(file.path) }
        .accessibilityAction(named: "Quick Look") { screen.quickLook(file.path) }
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            if !isBest || screen.isSelected(file.path) {
                Button {
                    screen.keepOnly(file.path)
                } label: {
                    Label("Keep This", systemImage: "crown")
                        .font(SpruceFont.caption.weight(.semibold))
                }
                .buttonStyle(PrismCapsuleButtonStyle(role: .secondary))
                .help("Keep this picture and select the others")
            }
            PrismIconButton(symbol: "eye", help: "Quick Look") { screen.quickLook(file.path) }
            PrismIconButton(symbol: "magnifyingglass", help: "Reveal in Finder") { screen.reveal(file.path) }
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let fingerprint, fingerprint.pixelWidth > 0, fingerprint.pixelHeight > 0 {
            parts.append("\(fingerprint.pixelWidth) × \(fingerprint.pixelHeight)")
        }
        parts.append(ByteFormat.string(file.size))
        parts.append(file.originDate.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}
