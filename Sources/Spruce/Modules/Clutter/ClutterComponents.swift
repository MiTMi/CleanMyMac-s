import AppKit
import QuickLookThumbnailing
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Thumbnails

/// Quick Look thumbnails by path and size, generated off the main thread and cached.
@MainActor
final class ClutterThumbnailCache {
    static let shared = ClutterThumbnailCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()
    /// Files Quick Look has no thumbnail for (archives, unknown types): don't ask again.
    private var unavailable = Set<String>()

    private func key(_ path: String, _ side: CGFloat) -> String { "\(Int(side.rounded()))|\(path)" }

    func cached(path: String, side: CGFloat) -> NSImage? {
        cache.object(forKey: key(path, side) as NSString)
    }

    func load(path: String, side: CGFloat, scale: CGFloat) async -> NSImage? {
        let cacheKey = key(path, side)
        if let hit = cache.object(forKey: cacheKey as NSString) { return hit }
        if unavailable.contains(cacheKey) { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = await Self.generate(path: path, side: side, scale: scale)
        if let image {
            cache.setObject(image, forKey: cacheKey as NSString)
        } else {
            unavailable.insert(cacheKey)
        }
        return image
    }

    private nonisolated static func generate(path: String, side: CGFloat, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path),
                                                   size: CGSize(width: side, height: side),
                                                   scale: max(scale, 1),
                                                   representationTypes: .thumbnail)
        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }
}

/// A file's Quick Look thumbnail in a rounded square, with the Finder icon while it
/// loads (or when the file type has no preview).
struct ClutterThumbnail: View {
    var path: String
    var side: CGFloat
    var symbol: String = "doc"
    /// Crop to fill the square (photos) instead of fitting (documents).
    var fills: Bool = true
    var cornerRadius: CGFloat? = nil
    /// Size to render the thumbnail at, when the displayed size changes with the layout.
    var requestSide: CGFloat? = nil

    @State private var image: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let radius = cornerRadius ?? max(4, side * 0.16)
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Ink.hairline))
                    .transition(.opacity)
            } else {
                ItemIcon(url: URL(fileURLWithPath: path), symbol: symbol, size: side * 0.86, module: .clutter)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .task(id: "\(path)|\(Int(renderSide))") {
            if let hit = ClutterThumbnailCache.shared.cached(path: path, side: renderSide) {
                image = hit
                return
            }
            let loaded = await ClutterThumbnailCache.shared.load(path: path, side: renderSide, scale: displayScale)
            withAnimation(Motion.quick) { image = loaded }
        }
    }

    private var renderSide: CGFloat {
        max(16, (requestSide ?? side).rounded())
    }
}

// MARK: - Flow layout

/// Lays chips out left to right, wrapping onto new lines.
struct ClutterFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0 && lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + lineSpacing
                widest = max(widest, lineWidth)
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
            lineHeight = max(lineHeight, size.height)
        }
        widest = max(widest, lineWidth)
        totalHeight += lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Chips

/// A small status chip on a file row.
struct ClutterRowChip: Identifiable {
    var text: String
    var symbol: String?
    var color: Color

    var id: String { text }

    static var cloud: ClutterRowChip {
        ClutterRowChip(text: "In iCloud", symbol: "icloud", color: StatusColor.info)
    }

    static var keeper: ClutterRowChip {
        ClutterRowChip(text: "Suggested to keep", symbol: "crown.fill", color: StatusColor.success)
    }

    static var bestShot: ClutterRowChip {
        ClutterRowChip(text: "Best shot", symbol: "star.fill", color: StatusColor.success)
    }
}

// MARK: - File row

/// One file of a Clutter list: checkbox · thumbnail · name, chips and folder · date ·
/// hover actions (Quick Look, Reveal, Keep this, more) · size.
struct ClutterFileRow: View {
    @Bindable var screen: ClutterScreenModel
    var file: ClutterFile
    /// Second line; defaults to the containing folder.
    var subtitle: String? = nil
    var chips: [ClutterRowChip] = []
    var dateText: String? = nil
    var thumbnailSide: CGFloat = 30
    /// Shown as a hover action for members of a duplicate set or similar cluster.
    var onKeep: (() -> Void)? = nil

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let selected = screen.isSelected(file.path)
        HStack(spacing: Spacing.m) {
            SpruceCheckbox(isOn: selected, module: .clutter, label: file.name) { screen.toggle(file.path) }
            ClutterThumbnail(path: file.path, side: thumbnailSide, symbol: file.kind.symbol,
                             fills: file.kind == .pictures || file.kind == .movies)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(SpruceFont.body)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    ForEach(chips) { chip in
                        PrismChip(text: chip.text, color: chip.color, symbol: chip.symbol)
                    }
                }
                Text(subtitle ?? file.parentPath.abbreviatingHome)
                    .font(SpruceFont.mono)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.s)
            if hovering {
                actions.transition(.opacity)
            } else if let dateText {
                Text(dateText)
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            Text(ByteFormat.string(file.size))
                .font(SpruceFont.callout.monospacedDigit())
                .foregroundStyle(ink.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 6)
        .frame(minHeight: 46)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(selected ? ModuleID.clutter.palette.accent.opacity(0.10) : (hovering ? ink.subtleFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { screen.toggle(file.path) }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu { ClutterFileMenu(screen: screen, path: file.path, onKeep: onKeep) }
        .help(file.path.abbreviatingHome)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(selected ? "selected" : "not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { screen.toggle(file.path) }
        .accessibilityAction(named: "Quick Look") { screen.quickLook(file.path) }
        .accessibilityAction(named: "Reveal in Finder") { screen.reveal(file.path) }
    }

    private var accessibilityText: String {
        var parts = [file.name, ByteFormat.string(file.size)]
        parts.append(contentsOf: chips.map { $0.text })
        return parts.joined(separator: ", ")
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if let onKeep {
                Button(action: onKeep) {
                    Label("Keep This", systemImage: "crown")
                        .font(SpruceFont.caption.weight(.semibold))
                }
                .buttonStyle(PrismCapsuleButtonStyle(role: .secondary))
                .help("Keep this copy and select the others")
            }
            PrismIconButton(symbol: "eye", help: "Quick Look") { screen.quickLook(file.path) }
            PrismIconButton(symbol: "magnifyingglass", help: "Reveal in Finder") { screen.reveal(file.path) }
            ClutterMoreMenu(screen: screen, path: file.path, onKeep: nil)
        }
    }
}

/// Context-menu items shared by rows and cards.
struct ClutterFileMenu: View {
    var screen: ClutterScreenModel
    var path: String
    var onKeep: (() -> Void)?

    var body: some View {
        Button("Quick Look") { screen.quickLook(path) }
        Button("Reveal in Finder") { screen.reveal(path) }
        Button("Open") { screen.open(path: path) }
        Button("Copy Path") { screen.copyPath(path) }
        if let onKeep {
            Divider()
            Button("Keep This, Select the Others", action: onKeep)
        }
        Divider()
        Button("Ignore from Now On") { screen.ignore(path) }
    }
}

/// "…" button with Open, Copy Path and Ignore.
struct ClutterMoreMenu: View {
    var screen: ClutterScreenModel
    var path: String
    var onKeep: (() -> Void)?

    var body: some View {
        Menu {
            ClutterFileMenu(screen: screen, path: path, onKeep: onKeep)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Ink.controlFill))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More actions")
    }
}

// MARK: - Sidebar

/// A selectable facet or group row in a tool's left pane.
struct ClutterFacetRow: View {
    var title: String
    var symbol: String
    var count: Int
    var bytes: Int64?
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? ModuleID.clutter.palette.accentText : ink.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(SpruceFont.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Ink.primary : ink.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let bytes {
                    Text(ByteFormat.string(bytes))
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(ink.tertiary)
                        .lineLimit(1)
                }
                Text(CountFormat.grouped(count))
                    .font(SpruceFont.captionDigits.weight(.semibold))
                    .foregroundStyle(isSelected ? Ink.primary : ink.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(isSelected ? ModuleID.clutter.palette.accent.opacity(0.35) : ink.controlFill))
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? ink.selectedFill : (hovering ? ink.subtleFill : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityLabel("\(title), \(CountFormat.items(count))")
        .accessibilityAddTraits(isSelected ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
    }
}

extension View {
    /// The frosted pane that holds a tool's sidebar or list.
    func clutterPane() -> some View {
        self.prismSurface(radius: Radius.container)
    }
}

// MARK: - Tool header & footer

/// Header of a tool screen: back to the dashboard, title, summary and trailing controls.
struct ClutterToolHeader<Trailing: View>: View {
    @Bindable var screen: ClutterScreenModel
    var tool: ClutterTool
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ScreenHeader(title: tool.title, subtitle: subtitle, backTitle: "Clutter",
                     onBack: { screen.showDashboard() }, module: nil,
                     trailing: AnyView(HStack(spacing: Spacing.s) { trailing }))
    }
}

/// Selection total and the Move to Trash orb for one tool (or every tool).
struct ClutterToolFooter: View {
    @Bindable var screen: ClutterScreenModel
    var tool: ClutterTool?

    var body: some View {
        ResultsFooter(module: .clutter,
                      selectedBytes: screen.selectedBytes(in: tool),
                      selectedCount: screen.selectedPaths(in: tool).count,
                      actionTitle: "Move to Trash",
                      isEnabled: !screen.isBusy,
                      totalBytes: totalBytes,
                      totalCount: totalCount) {
            screen.requestRemoval(in: tool)
        }
    }

    private var totalBytes: Int64 {
        if let tool { return screen.totalBytes(in: tool) }
        return screen.report?.distinctBytes ?? 0
    }

    private var totalCount: Int {
        if let tool { return screen.fileCount(in: tool) }
        return screen.report?.distinctFileCount ?? 0
    }
}

/// A sort/selection menu styled as a glass capsule.
struct ClutterMenuButton<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(SpruceFont.callout.weight(.medium))
            .foregroundStyle(Ink.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .prismGlassCapsule()
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Empty pane content for a tool or filter with nothing to show.
struct ClutterEmptyPane: View {
    var title: String
    var message: String
    var symbol: String = "checkmark.seal"

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(ModuleID.clutter.palette.accentText)
            Text(title)
                .font(SpruceFont.headline)
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(SpruceFont.callout)
                .foregroundStyle(PrismInk(contrast).secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Removal confirmation

/// Confirms moving the selection to the Trash. When every member of a duplicate set or
/// similar cluster is selected, one of each is kept unless the user opts in.
struct ClutterRemovalSheet: View {
    var request: ClutterRemovalRequest
    var onCancel: () -> Void
    var onConfirm: (_ removeAllCopies: Bool) -> Void

    @State private var removeAllCopies = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        PrismSheetCard(title: title, message: message, primaryTitle: "Move to Trash",
                       primaryRole: removeAllCopies ? .destructive : .primary,
                       onCancel: onCancel, onPrimary: { onConfirm(removeAllCopies) }) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                preview
                if request.completeSets > 0 {
                    Toggle(isOn: $removeAllCopies) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also move the last copy")
                                .font(SpruceFont.bodyStrong)
                                .foregroundStyle(Ink.primary)
                            Text(completeSetsText)
                                .font(SpruceFont.caption)
                                .foregroundStyle(PrismInk(contrast).secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var title: String {
        "Move \(CountFormat.items(request.items.count)) to the Trash?"
    }

    private var message: String {
        "\(ByteFormat.string(request.bytes)) goes to the Trash. You can put anything back from the Trash until you empty it."
    }

    private var completeSetsText: String {
        let sets = CountFormat.items(request.completeSets, singular: "set")
        return "Every copy of \(sets) is selected. Unless you turn this on, Spruce keeps one file of each set."
    }

    private var preview: some View {
        let ink = PrismInk(contrast)
        let shown = Array(request.items.prefix(4))
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(shown, id: \.id) { item in
                HStack(spacing: Spacing.s) {
                    ItemIcon(url: item.url, symbol: item.symbol, size: 18, module: .clutter)
                    Text(item.title)
                        .font(SpruceFont.callout)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Spacing.s)
                    Text(ByteFormat.string(item.size))
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(ink.tertiary)
                }
            }
            if request.items.count > shown.count {
                Text("and \(CountFormat.items(request.items.count - shown.count, singular: "other item"))")
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(ink.subtleFill))
    }
}
