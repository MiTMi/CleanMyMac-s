import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Applications landing: intro → scan → overview tiles.
struct ApplicationsHubScreen: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        switch screen.overviewPhase {
        case .idle:
            ModuleIdleView(module: .applications, features: Self.features, actionTitle: "Scan",
                           accessory: AnyView(idleAccessory)) {
                SpruceSound.play(.scanStart)
                screen.startOverview()
            }
        case .scanning:
            ScanningView(module: .applications, progress: screen.overviewProgress, title: "Looking through your apps…",
                         onStop: { screen.cancelOverview() }, steps: screen.overviewSteps, showsBytes: false)
        case .ready:
            ApplicationsOverviewScreen(screen: screen)
        }
    }

    private var idleAccessory: some View {
        HStack(spacing: Spacing.l) {
            PrismTextButton(title: "Open App Manager", symbol: "chevron.right", module: .applications) {
                screen.openUninstaller(facet: .all)
            }
            PrismTextButton(title: "Updates", symbol: "chevron.right", module: .applications) {
                screen.open(.updater)
            }
            PrismTextButton(title: "Extensions", symbol: "chevron.right", module: .applications) {
                screen.open(.extensions)
            }
        }
        .padding(.top, Spacing.xs)
    }

    static let features: [IdleFeature] = [
        IdleFeature(symbol: "trash.square", title: "Uninstall completely",
                    detail: "Remove apps together with their support files, or reset an app to a fresh start."),
        IdleFeature(symbol: "arrow.down.circle", title: "Keep apps current",
                    detail: "Updates from the App Store, in-app updaters and Homebrew in one list."),
        IdleFeature(symbol: "questionmark.folder", title: "Tidy what's left behind",
                    detail: "Files of apps you already deleted, and installers you no longer need."),
        IdleFeature(symbol: "puzzlepiece.extension", title: "Control extensions",
                    detail: "Turn Finder, Share and Safari extensions on or off, and remove old plug-ins."),
    ]
}

// MARK: - Overview

struct ApplicationsOverviewScreen: View {
    @Bindable var screen: ApplicationsScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.l, alignment: .top),
                                    GridItem(.flexible(), spacing: Spacing.l, alignment: .top)],
                          alignment: .leading, spacing: Spacing.l) {
                    ApplicationsUnusedTile(screen: screen)
                    ApplicationsUpdatesTile(screen: screen)
                    ApplicationsLeftoversTile(screen: screen)
                    ApplicationsInstallersTile(screen: screen)
                    ApplicationsExtensionsTile(screen: screen)
                    if !screen.intelOnlyApps.isEmpty {
                        ApplicationsIntelTile(screen: screen)
                    }
                }
            }
            .frame(maxWidth: Spacing.readableWidth)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.topInset + Spacing.l)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .prismCanvasIntensity(PrismCanvasMath.Intensity.results)
    }

    private var header: some View {
        let ink = PrismInk(contrast)
        return HStack(alignment: .center, spacing: Spacing.l) {
            HeroLens(module: .applications, size: 84, mood: .standard, parallax: false)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(CountFormat.items(screen.removableApps.count, singular: "app")) on your Mac")
                    .font(SpruceFont.display(34))
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(sizeLine)
                    .font(SpruceFont.body.monospacedDigit())
                    .foregroundStyle(ink.secondary)
                HStack(spacing: Spacing.s) {
                    CapsuleButton(title: "Open App Manager", symbol: "square.grid.2x2", prominent: true) {
                        screen.openUninstaller(facet: .all)
                    }
                    CapsuleButton(title: "Scan Again", symbol: "arrow.clockwise") {
                        screen.startOverview()
                    }
                }
                .padding(.top, Spacing.xs)
            }
            Spacer(minLength: 0)
        }
    }

    private var sizeLine: String {
        if screen.isMeasuring || !screen.sizesMeasured {
            return "Measuring how much space they use…"
        }
        var parts = ["Using \(ByteFormat.string(screen.totalAppsSize))"]
        let system = screen.apps.filter(\.isSystem).count
        if system > 0 { parts.append("plus \(CountFormat.items(system, singular: "app")) that come with macOS") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Tile shell

/// Shared layout of an overview tile: badge, title, metric, caption, content, actions.
struct ApplicationsHubTile<Content: View, Actions: View>: View {
    var symbol: String
    var title: String
    var metric: String
    var unit: String? = nil
    var caption: String
    var status: (text: String, tile: TileStatus)? = nil
    var isWorking: Bool = false
    var onOpen: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        GlassCard(isHighlighted: hovering) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .center, spacing: Spacing.s) {
                    PrismCategoryBadge(symbol: symbol, module: .applications, size: 36)
                    Text(title.uppercased())
                        .font(SpruceFont.overline)
                        .tracking(0.8)
                        .foregroundStyle(ink.secondary)
                    Spacer(minLength: Spacing.s)
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else if let status {
                        StatusPill(text: status.text, status: status.tile)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric)
                        .font(SpruceFont.metricL)
                        .foregroundStyle(Ink.primary)
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit)
                            .font(SpruceFont.unit)
                            .foregroundStyle(ink.secondary)
                    }
                }
                Text(caption)
                    .font(SpruceFont.callout)
                    .foregroundStyle(ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: Spacing.s) {
                    actions
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(title): \(metric) \(unit ?? ""), \(caption)"))
    }
}

/// A row of small overlapping app icons.
struct ApplicationsIconCluster: View {
    var urls: [URL]
    var extra: Int = 0

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(urls.prefix(5).enumerated()), id: \.offset) { _, url in
                ItemIcon(url: url, symbol: "app", size: 30, module: .applications)
                    .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(SpruceFont.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Ink.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Ink.controlFill))
                    .padding(.leading, 12)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tiles

struct ApplicationsUnusedTile: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        let unused = screen.unusedApps
        let size = unused.reduce(Int64(0)) { $0 + $1.size }
        ApplicationsHubTile(symbol: "moon.zzz", title: "Unused apps", metric: CountFormat.grouped(unused.count),
                            caption: caption(count: unused.count),
                            status: tileStatus(empty: unused.isEmpty),
                            isWorking: screen.isMeasuring,
                            onOpen: { screen.openUninstaller(facet: unused.isEmpty ? .all : .unused) }) {
            if !unused.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ApplicationsIconCluster(urls: unused.map(\.url), extra: max(0, unused.count - 5))
                    if screen.sizesMeasured {
                        Text("Together they use \(ByteFormat.string(size)).")
                            .font(SpruceFont.caption.monospacedDigit())
                            .foregroundStyle(Ink.tertiary)
                    }
                }
            }
        } actions: {
            CapsuleButton(title: unused.isEmpty ? "Open Uninstaller" : "Review", symbol: unused.isEmpty ? nil : "eye") {
                screen.openUninstaller(facet: unused.isEmpty ? .all : .unused)
            }
        }
    }

    private func tileStatus(empty: Bool) -> (text: String, tile: TileStatus)? {
        empty ? ("In use", .clear) : ("Review", .info)
    }

    private func caption(count: Int) -> String {
        let period = ApplicationsHubText.period(days: screen.settings.unusedAppDays)
        if count == 0 { return "Every app has been opened in the last \(period)." }
        return count == 1 ? "app you haven't opened in \(period)" : "apps you haven't opened in \(period)"
    }
}

struct ApplicationsUpdatesTile: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        let pending = screen.pendingUpdates
        let homebrew = pending.filter(\.isUnattended)
        ApplicationsHubTile(symbol: "arrow.down.circle", title: "Updates", metric: metric(pending.count),
                            caption: caption(pending.count), status: status(pending.count),
                            isWorking: screen.updatesPhase == .loading || screen.isInstallingUpdates,
                            onOpen: { screen.open(.updater) }) {
            if !pending.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pending.prefix(3)) { update in
                        HStack(spacing: Spacing.s) {
                            ItemIcon(url: URL(fileURLWithPath: update.appPath), symbol: "app", size: 18, module: .applications)
                            Text(update.name)
                                .font(SpruceFont.caption.weight(.medium))
                                .foregroundStyle(Ink.primary)
                                .lineLimit(1)
                            Text("\(update.installedVersion) → \(update.availableVersion)")
                                .font(SpruceFont.captionDigits)
                                .foregroundStyle(Ink.tertiary)
                                .lineLimit(1)
                        }
                    }
                    if pending.count > 3 {
                        Text("and \(pending.count - 3) more")
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                }
            }
        } actions: {
            if screen.updatesCheckedAt == nil && screen.updatesPhase != .loading {
                CapsuleButton(title: "Check for Updates", symbol: "arrow.clockwise", prominent: true) { screen.open(.updater) }
            } else {
                CapsuleButton(title: "Review", symbol: "eye") { screen.open(.updater) }
                if !homebrew.isEmpty && !screen.isInstallingUpdates {
                    CapsuleButton(title: "Update \(homebrew.count) with Homebrew", symbol: "mug", prominent: true) {
                        screen.installHomebrew(homebrew)
                    }
                }
            }
        }
    }

    private func metric(_ count: Int) -> String {
        screen.updatesCheckedAt == nil ? "—" : CountFormat.grouped(count)
    }

    private func caption(_ count: Int) -> String {
        if screen.updatesPhase == .loading && screen.updatesCheckedAt == nil { return "Checking for updates…" }
        if screen.updatesCheckedAt == nil { return "Check the App Store, in-app updaters and Homebrew for newer versions." }
        if count == 0 { return "All your apps are up to date." }
        return count == 1 ? "update available" : "updates available"
    }

    private func status(_ count: Int) -> (text: String, tile: TileStatus)? {
        guard screen.updatesCheckedAt != nil else { return nil }
        return count == 0 ? ("Up to date", .clear) : ("Available", .attention)
    }
}

struct ApplicationsLeftoversTile: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        let review = screen.leftovers
        let parts = ByteFormat.parts(review.totalSize)
        let appCount = review.groups.count
        ApplicationsHubTile(symbol: "questionmark.folder", title: "Files from removed apps",
                            metric: appCount == 0 ? "0" : parts.value, unit: appCount == 0 ? nil : parts.unit,
                            caption: appCount == 0
                                ? "No files left behind by apps you removed."
                                : "left by \(CountFormat.items(appCount, singular: "removed app")) — review before removing",
                            status: tileStatus(empty: appCount == 0),
                            isWorking: review.phase == .scanning || review.phase == .running,
                            onOpen: { screen.open(.leftovers) }) {
            if appCount > 0 {
                Text(review.groups.prefix(4).map(\.title).joined(separator: ", ") + (appCount > 4 ? "…" : ""))
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(2)
            }
        } actions: {
            CapsuleButton(title: "Review", symbol: "eye") { screen.open(.leftovers) }
        }
    }

    private func tileStatus(empty: Bool) -> (text: String, tile: TileStatus)? {
        empty ? ("Tidy", .clear) : ("Review", .info)
    }
}

struct ApplicationsInstallersTile: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        let review = screen.installers
        let parts = ByteFormat.parts(review.totalSize)
        let count = review.groups.allItems.count
        let selected = review.selectedItems
        let selectedSize = selected.reduce(Int64(0)) { $0 + $1.size }
        ApplicationsHubTile(symbol: "shippingbox", title: "Old installers",
                            metric: count == 0 ? "0" : parts.value, unit: count == 0 ? nil : parts.unit,
                            caption: count == 0
                                ? "No disk images or installer packages in Downloads or on the Desktop."
                                : "in \(CountFormat.items(count, singular: "installer")) in Downloads and on the Desktop",
                            status: tileStatus(empty: count == 0),
                            isWorking: review.phase == .scanning || review.phase == .running,
                            onOpen: { screen.open(.installers) }) {
            if !selected.isEmpty {
                Text("\(CountFormat.items(selected.count, singular: "installer")) of installed apps, older than a month, are selected (\(ByteFormat.string(selectedSize))).")
                    .font(SpruceFont.caption.monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            CapsuleButton(title: "Review", symbol: "eye") { screen.open(.installers) }
            if !selected.isEmpty && !review.isBusy {
                CapsuleButton(title: "Move to Trash", symbol: "trash", prominent: true) {
                    screen.route = .tool(.installers)
                    review.run()
                }
            }
        }
    }

    private func tileStatus(empty: Bool) -> (text: String, tile: TileStatus)? {
        empty ? ("Tidy", .clear) : nil
    }
}

struct ApplicationsExtensionsTile: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        let all = screen.extensions
        let appExtensions = all.filter { $0.kind == .appExtension }
        let off = appExtensions.filter { $0.isEnabled == false }.count
        ApplicationsHubTile(symbol: "puzzlepiece.extension", title: "Extensions",
                            metric: CountFormat.grouped(all.count),
                            caption: all.isEmpty ? "No third-party extensions or plug-ins." : "extensions and plug-ins from other developers",
                            status: nil, isWorking: screen.extensionsPhase == .loading,
                            onOpen: { screen.open(.extensions) }) {
            if !all.isEmpty {
                Text(summary(appExtensions: appExtensions.count, off: off, plugins: all.count - appExtensions.count))
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            CapsuleButton(title: "Manage", symbol: "slider.horizontal.3") { screen.open(.extensions) }
        }
    }

    private func summary(appExtensions: Int, off: Int, plugins: Int) -> String {
        var parts: [String] = []
        if appExtensions > 0 {
            parts.append("\(CountFormat.items(appExtensions, singular: "app extension"))" + (off > 0 ? " (\(off) off)" : ""))
        }
        if plugins > 0 { parts.append(CountFormat.items(plugins, singular: "plug-in")) }
        return parts.joined(separator: " · ")
    }
}

struct ApplicationsIntelTile: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        let intel = screen.intelOnlyApps
        ApplicationsHubTile(symbol: "cpu", title: "Intel-only apps", metric: CountFormat.grouped(intel.count),
                            caption: intel.count == 1
                                ? "app runs through Rosetta. A native version is usually faster and lighter."
                                : "apps run through Rosetta. Native versions are usually faster and lighter.",
                            status: infoStatus, onOpen: { screen.openUninstaller(facet: .intelOnly) }) {
            ApplicationsIconCluster(urls: intel.map(\.url), extra: max(0, intel.count - 5))
        } actions: {
            CapsuleButton(title: "Review", symbol: "eye") { screen.openUninstaller(facet: .intelOnly) }
        }
    }

    private var infoStatus: (text: String, tile: TileStatus)? { ("Info", .info) }
}

/// Small text helpers for the overview.
enum ApplicationsHubText {
    /// 180 → "6 months", 30 → "30 days", 365 → "12 months".
    static func period(days: Int) -> String {
        if days >= 60 {
            let months = Int((Double(days) / 30.0).rounded())
            return "\(months) months"
        }
        return days == 1 ? "1 day" : "\(days) days"
    }
}
