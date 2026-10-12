import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// The Uninstaller: facet column, app list with multi-select, and the per-app detail.
struct ApplicationsUninstallerScreen: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        switch screen.runState {
        case .running(let progress):
            ScanningView(module: .applications, progress: progress, title: screen.runTitle, showsBytes: true)
        case .done(let outcome, _):
            DoneView(module: .applications, outcome: outcome) { screen.finishRun() }
        case .none:
            if screen.detail != nil {
                ApplicationsAppDetailScreen(screen: screen)
            } else {
                ApplicationsAppListScreen(screen: screen)
            }
        }
    }
}

// MARK: - List screen

struct ApplicationsAppListScreen: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ApplicationsToolHeader(screen: screen, tool: .uninstaller, title: "Uninstaller", subtitle: subtitle) {
                trailingControls
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if screen.catalogPhase == .ready || !screen.apps.isEmpty {
                ResultsFooter(module: .applications, selectedBytes: screen.selectedAppsSize,
                              selectedCount: screen.selectedApps.count, actionTitle: "Uninstall",
                              totalCount: screen.removableApps.count, showsBytes: screen.sizesMeasured) {
                    screen.requestUninstall(screen.selectedApps)
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var subtitle: String {
        if screen.catalogPhase == .loading && screen.apps.isEmpty { return "Finding applications…" }
        var parts = [CountFormat.items(screen.removableApps.count, singular: "app")]
        if screen.isMeasuring {
            parts.append("measuring sizes…")
        } else if screen.sizesMeasured {
            parts.append(ByteFormat.string(screen.totalAppsSize))
        }
        return parts.joined(separator: " · ")
    }

    private var trailingControls: some View {
        HStack(spacing: Spacing.s) {
            PrismSearchField(text: $screen.search, prompt: "Search apps", width: 200)
            ApplicationsSortMenu(screen: screen)
            if screen.catalogPhase == .loading || screen.isMeasuring {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else {
                PrismIconButton(symbol: "arrow.clockwise", help: "Reload the app list") { screen.loadCatalog() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if screen.apps.isEmpty {
            if screen.catalogPhase == .ready {
                EmptyStateView(module: .applications, title: "No applications found",
                               message: "Spruce looks in /Applications and ~/Applications.", symbol: "square.grid.2x2",
                               mood: .standard, actionTitle: "Look Again", action: { screen.loadCatalog() })
            } else {
                ApplicationsLoadingPane(message: "Finding your applications…", detail: screen.catalogProgress.current)
            }
        } else {
            HStack(spacing: Spacing.m) {
                ApplicationsFacetColumn(screen: screen)
                    .frame(width: 236)
                ApplicationsAppListPane(screen: screen)
            }
        }
    }
}

/// "Sort by" menu with direction.
struct ApplicationsSortMenu: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        Menu {
            Picker("Sort by", selection: $screen.sort) {
                ForEach(ApplicationsAppSort.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Reverse Order", isOn: $screen.sortReversed)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(screen.sort.rawValue)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Ink.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .prismGlassCapsule()
        .help("Sort by")
    }
}

// MARK: - Facet column

struct ApplicationsFacetColumn: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                facetRow(.all)
                facetRow(.unused)
                facetRow(.selected, hideZero: true)
                ApplicationsFacetHeader(title: "Sources")
                ForEach(screen.sourceFacets, id: \.self) { facet in
                    facetRow(facet)
                }
                if !screen.intelOnlyApps.isEmpty {
                    ApplicationsFacetHeader(title: "Compatibility")
                    facetRow(.intelOnly)
                }
                vendorSection
                ApplicationsFacetHeader(title: "macOS")
                facetRow(.system)
                cleanupSection
            }
            .padding(Spacing.s)
        }
        .scrollIndicators(.never)
        .prismSurface(radius: Radius.container)
    }

    @ViewBuilder
    private var vendorSection: some View {
        let vendors = screen.vendorFacets
        if !vendors.isEmpty {
            ApplicationsFacetHeader(title: "Vendors")
            ForEach(vendors, id: \.name) { vendor in
                ApplicationsFacetRow(title: vendor.name, symbol: ApplicationsAppFacet.vendor(vendor.name).symbol,
                                     count: String(vendor.count), isSelected: screen.facet == .vendor(vendor.name)) {
                    select(.vendor(vendor.name))
                }
            }
        }
    }

    @ViewBuilder
    private var cleanupSection: some View {
        ApplicationsFacetHeader(title: "Clean up")
        ApplicationsFacetRow(title: "Files from Removed Apps", symbol: "questionmark.folder",
                             count: screen.leftovers.hasResults ? ByteFormat.string(screen.leftovers.totalSize) : nil,
                             isSelected: false, showsChevron: true) {
            screen.open(.leftovers)
        }
        ApplicationsFacetRow(title: "Old Installers", symbol: "shippingbox",
                             count: screen.installers.hasResults ? ByteFormat.string(screen.installers.totalSize) : nil,
                             isSelected: false, showsChevron: true) {
            screen.open(.installers)
        }
    }

    private func facetRow(_ facet: ApplicationsAppFacet, hideZero: Bool = false) -> some View {
        let count = screen.count(for: facet)
        return ApplicationsFacetRow(title: facet.title, symbol: facet.symbol,
                                    count: hideZero && count == 0 ? nil : CountFormat.grouped(count),
                                    isSelected: screen.facet == facet) {
            select(facet)
        }
    }

    private func select(_ facet: ApplicationsAppFacet) {
        withAnimation(Motion.quick) { screen.facet = facet }
    }
}

// MARK: - App list

struct ApplicationsAppListPane: View {
    @Bindable var screen: ApplicationsScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let apps = screen.visibleApps
        VStack(spacing: 0) {
            header(count: apps.count)
            ApplicationsHairline()
            if screen.facet == .system {
                ApplicationsBanner(symbol: "lock.fill",
                                   text: "Apps that come with macOS are part of the system. They're shown for reference and can't be removed.")
                    .padding(Spacing.s)
            } else if screen.facet == .unused {
                ApplicationsBanner(symbol: "moon.zzz",
                                   text: "Apps you haven't opened in \(ApplicationsHubText.period(days: screen.settings.unusedAppDays)). Change the period in Settings.")
                    .padding(Spacing.s)
            }
            if apps.isEmpty {
                emptyList
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(apps) { app in
                            ApplicationsAppRow(app: app, isSelected: screen.selectedAppIDs.contains(app.id),
                                               sizeKnown: screen.sizesMeasured || app.size > 0,
                                               onToggle: { screen.toggleSelection(app) },
                                               onOpen: { screen.showDetail(app) },
                                               onUninstall: { screen.requestUninstall([app]) },
                                               onReveal: { screen.engine.reveal(app.path) },
                                               onLaunch: { screen.engine.launch(app) },
                                               onIgnore: { screen.ignoreApp(app) })
                            ApplicationsHairline(leading: 82)
                        }
                    }
                }
            }
        }
        .prismSurface(radius: Radius.container)
    }

    private func header(count: Int) -> some View {
        let ink = PrismInk(contrast)
        return HStack(spacing: Spacing.m) {
            if screen.facet != .system {
                SpruceCheckbox(state: screen.visibleSelectionState, module: .applications, label: "Select all") {
                    screen.setVisibleSelected(screen.visibleSelectionState != .all)
                }
            }
            Text(screen.facet.title)
                .font(SpruceFont.headline)
                .foregroundStyle(Ink.primary)
            Text(CountFormat.items(count, singular: "app"))
                .font(SpruceFont.captionDigits)
                .foregroundStyle(ink.tertiary)
            Spacer(minLength: Spacing.s)
            if screen.isMeasuring {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Measuring sizes…")
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var emptyList: some View {
        let ink = PrismInk(contrast)
        VStack(spacing: Spacing.s) {
            Image(systemName: screen.search.isEmpty ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ink.tertiary)
            Text(emptyText)
                .font(SpruceFont.body)
                .foregroundStyle(ink.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyText: String {
        if !screen.search.isEmpty { return "No apps match \u{201C}\(screen.search)\u{201D}." }
        switch screen.facet {
        case .unused: return "Every app has been opened recently."
        case .selected: return "No apps selected. Tick apps in any list to collect them here."
        case .intelOnly: return "All your apps run natively on Apple silicon."
        default: return "No apps in this group."
        }
    }
}

/// One app in the Uninstaller list.
struct ApplicationsAppRow: View {
    var app: ApplicationsAppInfo
    var isSelected: Bool
    var sizeKnown: Bool
    var onToggle: () -> Void
    var onOpen: () -> Void
    var onUninstall: () -> Void
    var onReveal: () -> Void
    var onLaunch: () -> Void
    var onIgnore: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.m) {
            selector
            ItemIcon(url: app.url, symbol: "app", size: 34, module: .applications)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(SpruceFont.body.weight(.medium))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    ApplicationsAppBadges(app: app, compact: true)
                }
                Text(secondaryLine)
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            if hovering {
                hoverActions
                    .transition(.opacity)
            }
            Text(sizeKnown ? ByteFormat.string(app.size) : "—")
                .font(SpruceFont.callout.monospacedDigit())
                .foregroundStyle(ink.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            Button(action: onOpen) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hovering ? Ink.primary : ink.tertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the app's files")
            .accessibilityLabel("Show \(app.name)'s files")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 7)
        .background(Rectangle().fill(hovering ? ink.subtleFill : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            if app.canUninstall { onToggle() } else { onOpen() }
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .combine)
        .accessibilityValue(app.canUninstall ? (isSelected ? "selected" : "not selected") : "part of macOS")
        .accessibilityAction(named: "Show files") { onOpen() }
    }

    @ViewBuilder
    private var selector: some View {
        if app.canUninstall {
            SpruceCheckbox(isOn: isSelected, module: .applications, label: app.name, action: onToggle)
        } else {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PrismInk(contrast).tertiary)
                .frame(width: 18, height: 18)
                .help("Part of macOS — can't be removed")
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            PrismIconButton(symbol: "magnifyingglass", help: "Reveal in Finder", action: onReveal)
            if app.canUninstall {
                PrismIconButton(symbol: "trash", help: "Uninstall \(app.name)…", action: onUninstall)
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Show Files") { onOpen() }
        Button("Open \(app.name)") { onLaunch() }
        Button("Reveal in Finder") { onReveal() }
        if app.canUninstall {
            Divider()
            Button("Uninstall…") { onUninstall() }
            Button("Ignore This App") { onIgnore() }
        }
    }

    private var secondaryLine: String {
        var parts: [String] = []
        if !app.versionLabel.isEmpty { parts.append(app.versionLabel) }
        if app.vendor != "Other" { parts.append(app.vendor) }
        parts.append(app.applicationsLastUsedText)
        return parts.joined(separator: " · ")
    }
}
