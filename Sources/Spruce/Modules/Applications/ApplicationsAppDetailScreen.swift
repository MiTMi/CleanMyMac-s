import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// One app: summary, Uninstall / Reset selector and the checklist of its files.
struct ApplicationsAppDetailScreen: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        if let detail = screen.detail {
            VStack(spacing: Spacing.m) {
                ApplicationsToolHeader(screen: screen, tool: .uninstaller, title: detail.app.name,
                                       subtitle: subtitle(detail), backTitle: screen.facet.title,
                                       onBack: { screen.closeDetail() }) {
                    trailingControls(detail.app)
                }
                ApplicationsAppSummaryCard(app: detail.app, filesSize: detail.isLoading ? nil : detail.groups.totalSize,
                                           sizeKnown: screen.sizesMeasured || detail.app.size > 0)
                if detail.app.canUninstall {
                    ApplicationsModeBar(screen: screen, app: detail.app, isLoading: detail.isLoading)
                    content(detail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ResultsFooter(module: .applications, selectedBytes: detail.groups.selectedSize,
                                  selectedCount: detail.groups.selectedItems.count, actionTitle: screen.detailActionTitle,
                                  isEnabled: !detail.isLoading, totalBytes: detail.groups.totalSize,
                                  totalCount: detail.groups.allItems.count) {
                        screen.requestDetailAction()
                    }
                } else {
                    ApplicationsBanner(symbol: "lock.fill",
                                       text: "\(detail.app.name) comes with macOS. It's protected by the system and can't be removed or reset.")
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.topInset)
            .padding(.bottom, detail.app.canUninstall ? 0 : Spacing.l)
        }
    }

    private func subtitle(_ detail: ApplicationsDetailState) -> String {
        if detail.isLoading { return "Finding the app's files…" }
        let count = detail.groups.allItems.count
        return "\(CountFormat.items(count, singular: "item")) · \(ByteFormat.string(detail.groups.totalSize))"
    }

    private func trailingControls(_ app: ApplicationsAppInfo) -> some View {
        HStack(spacing: Spacing.s) {
            CapsuleButton(title: "Open", symbol: "arrow.up.forward.app") { screen.engine.launch(app) }
            CapsuleButton(title: "Reveal", symbol: "magnifyingglass") { screen.engine.reveal(app.path) }
            if app.canUninstall {
                Menu {
                    Button("Ignore This App") { screen.ignoreApp(app) }
                    Button("Find Files Again") { screen.loadComponents(mode: screen.detailMode ?? .uninstall) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .background(Circle().fill(Ink.controlFill))
                .help("More")
            }
        }
    }

    @ViewBuilder
    private func content(_ detail: ApplicationsDetailState) -> some View {
        if detail.isLoading {
            ApplicationsLoadingPane(message: "Finding \(detail.app.name)'s files…",
                                    detail: "Library folders are searched for files named after the app.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(detail.groups) { group in
                        ApplicationsComponentGroupCard(group: group,
                                                       onToggleGroup: {
                                                           screen.setDetailGroup(group.id, selected: group.selectionState == SelectionState.none)
                                                       },
                                                       onToggleItem: { screen.toggleDetailItem($0.id) },
                                                       onIgnore: { screen.ignoreDetailItem($0) })
                    }
                }
                .padding(.bottom, Spacing.s)
            }
            .scrollIndicators(.automatic)
        }
    }
}

// MARK: - Summary

struct ApplicationsAppSummaryCard: View {
    var app: ApplicationsAppInfo
    /// Total of the checklist (app + files), nil while loading.
    var filesSize: Int64?
    var sizeKnown: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        GlassCard(padding: Spacing.l) {
            HStack(alignment: .center, spacing: Spacing.l) {
                ItemIcon(url: app.url, symbol: "app", size: 64, module: .applications)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.s) {
                        Text(app.name)
                            .font(SpruceFont.headline)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                        ApplicationsAppBadges(app: app)
                    }
                    Text(factsLine)
                        .font(SpruceFont.callout)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(1)
                    Text(datesLine)
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                        .lineLimit(1)
                    Text(app.path.abbreviatingHome)
                        .font(SpruceFont.mono)
                        .foregroundStyle(ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: Spacing.m)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sizeKnown ? ByteFormat.string(app.size) : "—")
                        .font(SpruceFont.metricS)
                        .foregroundStyle(Ink.primary)
                    Text("app size")
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                    if let filesSize, filesSize > app.size {
                        Text("\(ByteFormat.string(filesSize)) with its files")
                            .font(SpruceFont.captionDigits)
                            .foregroundStyle(ink.secondary)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var factsLine: String {
        var parts: [String] = []
        if !app.versionLabel.isEmpty { parts.append("Version \(app.versionLabel)") }
        parts.append(app.vendor == "Other" ? "Unknown developer" : app.vendor)
        if app.architecture != .unknown { parts.append(app.architecture.title) }
        parts.append(app.source == .other ? "Installed directly" : "From \(app.source.title)")
        return parts.joined(separator: " · ")
    }

    private var datesLine: String {
        var parts = [app.applicationsLastUsedText]
        if let added = app.dateAdded { parts.append("Added \(DurationFormat.relative(added))") }
        if !app.bundleID.isEmpty { parts.append(app.bundleID) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Mode bar

/// Uninstall / Reset selector with an explanation of what each does.
struct ApplicationsModeBar: View {
    @Bindable var screen: ApplicationsScreenModel
    var app: ApplicationsAppInfo
    var isLoading: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let mode = screen.detailMode
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                HStack(spacing: 2) {
                    ForEach(ApplicationsUninstallMode.allCases, id: \.self) { option in
                        modeButton(option, isCurrent: mode == option)
                    }
                }
                .padding(3)
                .prismGlassCapsule()
                .disabled(isLoading)
                if mode == nil && !isLoading {
                    PrismChip(text: "Custom selection", color: ModuleID.applications.palette.accent2, symbol: "hand.point.up.left")
                }
                Text(explanation(mode))
                    .font(SpruceFont.callout)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if app.isRunning {
                ApplicationsBanner(symbol: "circle.fill", text: "\(app.name) is open. Spruce asks it to quit first, so it can save your work.",
                                   tint: StatusColor.success)
            }
            if app.prefersVendorUninstaller {
                ApplicationsBanner(symbol: "exclamationmark.shield",
                                   text: "\(app.vendor) ships its own uninstaller for this app. Security and management tools install system components that only their uninstaller removes cleanly.",
                                   tint: StatusColor.warning)
            }
        }
    }

    private func modeButton(_ option: ApplicationsUninstallMode, isCurrent: Bool) -> some View {
        Button {
            withAnimation(Motion.quick) { screen.applyDetailMode(option) }
        } label: {
            Text(option.title)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? Ink.primary : PrismInk(contrast).secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(isCurrent ? PrismInk(contrast).selectedFill : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(PrismPressStyle())
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .help(option == .uninstall ? "Select the app and all the files that clearly belong to it" : "Select only the app's data, keeping the app")
    }

    private func explanation(_ mode: ApplicationsUninstallMode?) -> String {
        switch mode {
        case .some(.uninstall): return "Removes the app and the files it created. Everything goes to the Trash."
        case .some(.reset): return "Keeps the app and removes its settings, caches and data, so it starts like new."
        case nil: return "You picked the items by hand. Everything selected goes to the Trash."
        }
    }
}

// MARK: - Component group

/// One kind of file (Caches, Preferences…) with a tri-state checkbox and its items.
struct ApplicationsComponentGroupCard: View {
    var group: ScanGroup
    var onToggleGroup: () -> Void
    var onToggleItem: (ScanItem) -> Void
    var onIgnore: (ScanItem) -> Void

    @State private var expanded = true
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                SpruceCheckbox(state: group.selectionState, module: .applications, label: group.title, action: onToggleGroup)
                PrismCategoryBadge(symbol: group.symbol, module: .applications, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(group.title)
                            .font(SpruceFont.bodyStrong)
                            .foregroundStyle(Ink.primary)
                        PrismSafetyBadge(safety: group.safety)
                    }
                    Text(group.detail)
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.s)
                Text(CountFormat.items(group.items.count))
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(ink.tertiary)
                Text(ByteFormat.string(group.totalSize))
                    .font(SpruceFont.callout.monospacedDigit())
                    .foregroundStyle(ink.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
                Button {
                    withAnimation(Motion.standard) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .foregroundStyle(ink.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse \(group.title)" : "Expand \(group.title)")
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            if expanded {
                ApplicationsHairline()
                ForEach(group.items) { item in
                    ItemRow(item: item, module: .applications, onToggle: { onToggleItem(item) },
                            onIgnore: isIgnorable(item) ? onIgnore : nil)
                    if item.id != group.items.last?.id {
                        ApplicationsHairline(leading: 56)
                    }
                }
            }
        }
        .prismSurface(radius: Radius.container)
    }

    /// The app itself and its Dock tile are never put on the ignore list from here.
    private func isIgnorable(_ item: ScanItem) -> Bool {
        let kind = item.metadata[ApplicationsMeta.kind]
        return kind != ApplicationsComponentKind.application.rawValue && kind != ApplicationsComponentKind.dockIcon.rawValue
    }
}
