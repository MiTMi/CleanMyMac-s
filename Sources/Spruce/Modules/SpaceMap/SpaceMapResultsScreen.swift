import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// The map: navigation bar with breadcrumbs, the children list beside the bubble (or
/// ring) map, and the selection bar with the volume gauge and the Remove orb.
struct SpaceMapResultsScreen: View {
    @Bindable var screen: SpaceMapScreenModel
    var hasFullDiskAccess: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let result = screen.result, let focus = screen.focus {
            VStack(spacing: Spacing.m) {
                SpaceMapResultsHeader(screen: screen, result: result, focus: focus)
                HStack(alignment: .top, spacing: Spacing.m) {
                    SpaceMapListPanel(screen: screen, focus: focus, hasFullDiskAccess: hasFullDiskAccess)
                        .frame(width: 330)
                    mapArea(result: result, focus: focus)
                }
                .frame(maxHeight: .infinity)
                SpaceMapSelectionBar(screen: screen, result: result)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.topInset)
            .padding(.bottom, Spacing.m)
            .prismCanvasIntensity(PrismCanvasMath.Intensity.results)
            .overlay(alignment: .bottom) { toast }
        } else {
            EmptyStateView(module: .spaceMap, title: "No map yet", message: "Choose a location and scan it.",
                           symbol: "circle.hexagongrid", mood: .standard, actionTitle: "Choose Location") {
                screen.newScan()
            }
        }
    }

    private func mapArea(result: SpaceMapScanResult, focus: SpaceMapNode) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch screen.viewMode {
                case .bubbles:
                    SpaceMapBubbleCanvas(screen: screen, focus: focus)
                case .rings:
                    SpaceMapRingsCanvas(screen: screen, focus: focus)
                        .id(focus.id)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Motion.standard, value: focus.id)
            mapCaption(result: result, focus: focus)
                .padding(Spacing.m)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).fill(Color.black.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Ink.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    private func mapCaption(result: SpaceMapScanResult, focus: SpaceMapNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ByteFormat.string(focus.size))
                .font(SpruceFont.metricS)
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
            Text(captionDetail(result: result, focus: focus))
                .font(SpruceFont.caption.monospacedDigit())
                .foregroundStyle(Ink.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.black.opacity(0.25)))
    }

    private func captionDetail(result: SpaceMapScanResult, focus: SpaceMapNode) -> String {
        var parts: [String] = []
        if focus.parent == nil, let volume = result.target.volume, result.target.coversWholeVolume {
            parts.append("in use on \(volume.name)")
        } else if result.root.size > 0, focus !== result.root {
            parts.append("\(PrismMetric.percentText(Double(focus.size) / Double(result.root.size))) of \(result.root.name)")
        } else {
            parts.append(CountFormat.items(focus.itemCount))
        }
        parts.append("scanned \(DurationFormat.relative(result.date)) in \(DurationFormat.short(max(1, result.stats.elapsed)))")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var toast: some View {
        if let message = screen.toast {
            PrismToast(message: message, symbol: "exclamationmark.triangle.fill", tint: StatusColor.warning,
                       actionTitle: "Dismiss") { screen.toast = nil }
                .padding(.bottom, 120)
                .transition(.opacity)
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if screen.toast == message { screen.toast = nil }
                }
        }
    }
}

// MARK: - Header

struct SpaceMapResultsHeader: View {
    @Bindable var screen: SpaceMapScreenModel
    let result: SpaceMapScanResult
    let focus: SpaceMapNode

    var body: some View {
        HStack(spacing: Spacing.s) {
            navigationButton("chevron.left", help: "Back (⌘[)", enabled: screen.canGoBack) { screen.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            navigationButton("chevron.right", help: "Forward (⌘])", enabled: screen.canGoForward) { screen.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            navigationButton("arrow.up", help: "Enclosing folder (⌘↑)", enabled: screen.canZoomOut) { screen.zoomOut() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            SpaceMapBreadcrumbBar(screen: screen, focus: focus, target: result.target)
                .padding(.leading, Spacing.xs)
            Spacer(minLength: Spacing.s)
            Picker("View", selection: $screen.viewMode) {
                ForEach(SpaceMapViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .help("Show the map as bubbles or rings")
            CapsuleButton(title: "New Scan", symbol: "arrow.counterclockwise") { screen.newScan() }
                .help("Choose another location. Nothing is removed.")
        }
        .frame(minHeight: 34)
    }

    private func navigationButton(_ symbol: String, help: String, enabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        PrismIconButton(symbol: symbol, help: help, action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }
}

/// Root › … › focused folder; earlier levels are buttons, folded ones sit in a menu.
struct SpaceMapBreadcrumbBar: View {
    let screen: SpaceMapScreenModel
    let focus: SpaceMapNode
    let target: SpaceMapTarget

    var body: some View {
        let crumbs = SpaceMapBreadcrumbs.trail(to: focus, maxVisible: 5)
        HStack(spacing: 4) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.tertiary)
                }
                crumbView(crumb, isFirst: index == 0, isLast: index == crumbs.count - 1)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func crumbView(_ crumb: SpaceMapCrumb, isFirst: Bool, isLast: Bool) -> some View {
        switch crumb {
        case .node(let node):
            Button {
                screen.jump(to: node)
            } label: {
                HStack(spacing: 4) {
                    if isFirst {
                        Image(systemName: target.symbol)
                            .font(.system(size: 11, weight: .medium))
                    }
                    Text(node.name)
                        .truncationMode(.middle)
                }
                .font(isLast ? SpruceFont.bodyStrong : SpruceFont.body)
                .foregroundStyle(isLast ? Ink.primary : Ink.secondary)
                .frame(maxWidth: isLast ? 220 : 150)
                .fixedSize(horizontal: !isLast, vertical: false)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLast)
            .help(node.path)
        case .collapsed(let nodes):
            Menu {
                ForEach(nodes) { node in
                    Button(node.name) { screen.jump(to: node) }
                }
            } label: {
                Text("…").font(SpruceFont.bodyStrong).foregroundStyle(Ink.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Selection bar

struct SpaceMapSelectionBar: View {
    let screen: SpaceMapScreenModel
    let result: SpaceMapScanResult

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            gauge
            Spacer(minLength: Spacing.m)
            summary
            ActionOrb(title: "Remove",
                      subtitle: screen.selection.isEmpty ? nil : ByteFormat.string(screen.selectedBytes),
                      module: .spaceMap, isEnabled: !screen.selection.isEmpty, diameter: 78,
                      isReady: !screen.selection.isEmpty) {
                screen.requestRemoval()
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .prismSurface(radius: Radius.panel)
    }

    @ViewBuilder
    private var gauge: some View {
        if let volume = result.target.volume {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: result.target.coversWholeVolume ? result.target.symbol : "internaldrive")
                        .foregroundStyle(Ink.secondary)
                    Text(volume.name)
                        .font(SpruceFont.bodyStrong)
                        .foregroundStyle(Ink.primary)
                    Text(volume.summary)
                        .font(SpruceFont.caption.monospacedDigit())
                        .foregroundStyle(Ink.tertiary)
                }
                SpaceMapCapacityBar(volume: volume, selectedBytes: screen.selectedBytes)
                    .frame(width: 300)
                HStack(spacing: Spacing.m) {
                    legend(color: ModuleID.spaceMap.palette.accent, text: "Used \(ByteFormat.string(volume.used))")
                    if volume.purgeable > 0 {
                        legend(color: Color.white.opacity(0.5), text: "Purgeable \(ByteFormat.string(volume.purgeable))")
                    }
                    if screen.selectedBytes > 0 {
                        legend(color: SpaceMapStyle.selection, text: "Selected \(ByteFormat.string(screen.selectedBytes))")
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.target.title)
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                Text("\(ByteFormat.string(result.root.size)) · \(CountFormat.items(result.root.fileCount, singular: "file", plural: "files"))")
                    .font(SpruceFont.caption.monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(SpruceFont.caption.monospacedDigit())
                .foregroundStyle(Ink.secondary)
        }
    }

    private var summary: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(screen.selection.isEmpty ? "Nothing selected"
                 : "\(CountFormat.items(screen.selection.count)) selected · \(CountFormat.items(screen.selectedFiles, singular: "file", plural: "files"))")
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.secondary)
            Text(ByteFormat.string(screen.selectedBytes))
                .font(SpruceFont.metricS)
                .foregroundStyle(screen.selection.isEmpty ? Ink.tertiary : Ink.primary)
                .contentTransition(.numericText())
                .animation(Motion.standard, value: screen.selectedBytes)
            if !screen.selection.isEmpty {
                HStack(spacing: Spacing.m) {
                    PrismTextButton(title: "Clear", module: .spaceMap) { screen.clearSelection() }
                    PrismTextButton(title: "Check Selection", module: .spaceMap) { screen.requestRemoval() }
                }
            } else {
                Text("Tick items in the list or click files on the map")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }
}
