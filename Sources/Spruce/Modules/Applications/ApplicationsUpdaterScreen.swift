import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Updater: updates grouped by where they come from, with release notes and actions.
struct ApplicationsUpdaterScreen: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ApplicationsToolHeader(screen: screen, tool: .updater, title: "Updater", subtitle: subtitle) {
                trailingControls
            }
            if screen.updatesPhase == .loading {
                PrismLinearProgress(value: screen.updatesProgress.fraction, module: .applications)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
        .padding(.bottom, Spacing.m)
        .onAppear {
            if screen.selectedUpdateID == nil { screen.selectedUpdateID = screen.visibleUpdates.first?.id }
        }
    }

    private var subtitle: String {
        if screen.updatesPhase == .loading {
            if let current = screen.updatesProgress.current { return "Checking \(current)…" }
            return screen.updatesProgress.message.isEmpty ? "Checking for updates…" : screen.updatesProgress.message
        }
        guard let checked = screen.updatesCheckedAt else { return "Not checked yet" }
        let count = screen.pendingUpdates.count
        let head = count == 0 ? "Everything is up to date" : CountFormat.items(count, singular: "update")
        return "\(head) · checked \(ApplicationsHubText.ago(checked))"
    }

    private var trailingControls: some View {
        HStack(spacing: Spacing.s) {
            PrismSearchField(text: $screen.updateSearch, prompt: "Search updates", width: 180)
            if screen.updatesPhase == .loading {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else {
                CapsuleButton(title: "Check Again", symbol: "arrow.clockwise") { screen.checkUpdates() }
                    .disabled(screen.isInstallingUpdates)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let visible = screen.visibleUpdates
        if screen.updatesCheckedAt == nil {
            if screen.updatesPhase == .loading {
                ApplicationsLoadingPane(message: "Checking the App Store, in-app updaters and Homebrew…",
                                        detail: screen.updatesProgress.current)
            } else {
                EmptyStateView(module: .applications, title: "Check for updates",
                               message: "Spruce asks each app's update feed, the App Store and Homebrew for newer versions. Nothing else is sent.",
                               symbol: "arrow.down.circle", mood: .standard, actionTitle: "Check Now",
                               action: { screen.checkUpdates() })
            }
        } else if visible.isEmpty && screen.ignoredUpdates.isEmpty {
            EmptyStateView(module: .applications,
                           title: screen.updateSearch.isEmpty ? "All your apps are up to date" : "No matches",
                           message: screen.updateSearch.isEmpty
                            ? "No newer versions were found for apps that use the App Store, an in-app updater or Homebrew."
                            : "No update matches \u{201C}\(screen.updateSearch)\u{201D}.",
                           symbol: screen.updateSearch.isEmpty ? "checkmark.seal" : "magnifyingglass",
                           mood: screen.updateSearch.isEmpty ? .clean : .standard)
        } else {
            GeometryReader { geo in
                HStack(spacing: Spacing.m) {
                    ApplicationsUpdateListPane(screen: screen, updates: visible)
                        .frame(width: min(420, max(300, geo.size.width * 0.44)))
                    ApplicationsUpdateDetailPane(screen: screen)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let checked = screen.checkedHomebrewUpdates
        if !checked.isEmpty {
            GlassCard(padding: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "mug")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ModuleID.applications.palette.accentText)
                    Text("\(CountFormat.items(checked.count, singular: "Homebrew update")) selected")
                        .font(SpruceFont.bodyStrong)
                        .foregroundStyle(Ink.primary)
                    Text("Installed one after another with brew upgrade.")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                    Spacer()
                    CapsuleButton(title: "Deselect") { screen.selectedUpdateIDs = [] }
                    CapsuleButton(title: "Update \(checked.count)", symbol: "arrow.down.circle", prominent: true) {
                        screen.installHomebrew(checked)
                    }
                    .disabled(screen.isInstallingUpdates)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - List

struct ApplicationsUpdateListPane: View {
    @Bindable var screen: ApplicationsScreenModel
    var updates: [ApplicationsUpdate]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(ApplicationsUpdateSource.allCases, id: \.self) { source in
                    let items = updates.filter { $0.source == source }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { update in
                                ApplicationsUpdateRow(screen: screen, update: update)
                            }
                        } header: {
                            ApplicationsUpdateSectionHeader(screen: screen, source: source, updates: items)
                        }
                    }
                }
                ignoredSection
            }
            .padding(Spacing.s)
        }
        .scrollIndicators(.automatic)
        .prismSurface(radius: Radius.container)
    }

    @ViewBuilder
    private var ignoredSection: some View {
        let ignored = screen.ignoredUpdates
        if !ignored.isEmpty {
            Button {
                withAnimation(Motion.standard) { screen.showIgnoredUpdates.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: screen.showIgnoredUpdates ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Ignored and skipped (\(ignored.count))")
                        .font(SpruceFont.caption.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(Ink.tertiary)
                .padding(.horizontal, Spacing.s)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if screen.showIgnoredUpdates {
                ForEach(ignored) { update in
                    ApplicationsIgnoredUpdateRow(update: update) { screen.stopIgnoring(update) }
                }
            }
        }
    }
}

struct ApplicationsUpdateSectionHeader: View {
    @Bindable var screen: ApplicationsScreenModel
    var source: ApplicationsUpdateSource
    var updates: [ApplicationsUpdate]
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.s) {
            if source == .homebrew {
                let installable = updates.filter { screen.status(of: $0) != .updated }
                let checked = installable.filter { screen.selectedUpdateIDs.contains($0.id) }.count
                SpruceCheckbox(state: checked == 0 ? SelectionState.none : (checked == installable.count ? .all : .some),
                               module: .applications, label: "Select all Homebrew updates") {
                    let ids = installable.map(\.id)
                    if checked == installable.count {
                        screen.selectedUpdateIDs.subtract(ids)
                    } else {
                        screen.selectedUpdateIDs.formUnion(ids)
                    }
                }
                .disabled(installable.isEmpty)
            } else {
                Image(systemName: source.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ModuleID.applications.palette.accentText)
                    .frame(width: 18)
            }
            Text(source.title.uppercased())
                .font(SpruceFont.overline)
                .tracking(0.8)
                .foregroundStyle(ink.secondary)
            Text(String(updates.count))
                .font(SpruceFont.captionDigits)
                .foregroundStyle(ink.tertiary)
            Spacer()
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 6)
        .help(source.actionDetail)
        .accessibilityAddTraits(.isHeader)
    }
}

struct ApplicationsUpdateRow: View {
    @Bindable var screen: ApplicationsScreenModel
    var update: ApplicationsUpdate

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let isCurrent = screen.selectedUpdateID == update.id
        HStack(spacing: Spacing.s) {
            if update.isUnattended {
                SpruceCheckbox(isOn: screen.selectedUpdateIDs.contains(update.id), module: .applications, label: update.name) {
                    screen.toggleUpdateCheck(update)
                }
                .disabled(screen.status(of: update) == .updated)
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
            ItemIcon(url: URL(fileURLWithPath: update.appPath), symbol: "app", size: 30, module: .applications)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(update.name)
                        .font(SpruceFont.body.weight(.medium))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    if update.isCritical {
                        PrismChip(text: "Important", color: StatusColor.danger, symbol: "exclamationmark")
                    } else if update.isMajor {
                        PrismChip(text: "Major", color: StatusColor.warning, symbol: "sparkles")
                    }
                }
                Text("\(update.installedVersion) → \(update.availableVersion)")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            ApplicationsUpdateStatusView(status: screen.status(of: update))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(isCurrent ? ink.selectedFill : (hovering ? ink.subtleFill : Color.clear)))
        .contentShape(Rectangle())
        .onTapGesture { screen.selectedUpdateID = update.id }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu {
            Button("Skip This Version") { screen.skipVersion(update) }
            Button("Ignore Updates for \(update.name)") { screen.ignoreUpdates(of: update) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : [.isButton])
    }
}

/// Spinner / ✓ / ⚠ for an update row.
struct ApplicationsUpdateStatusView: View {
    var status: ApplicationsUpdateRowStatus?

    var body: some View {
        switch status {
        case .some(.queued):
            Text("Waiting")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
        case .some(.updating):
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Updating…")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.secondary)
            }
        case .some(.updated):
            Label("Updated", systemImage: "checkmark.circle.fill")
                .font(SpruceFont.caption.weight(.semibold))
                .foregroundStyle(StatusColor.success)
        case .some(.failed(let reason)):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(StatusColor.warning)
                .help(reason)
        case .none:
            EmptyView()
        }
    }
}

struct ApplicationsIgnoredUpdateRow: View {
    var update: ApplicationsUpdate
    var onRestore: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Color.clear.frame(width: 18, height: 18)
            ItemIcon(url: URL(fileURLWithPath: update.appPath), symbol: "app", size: 26, module: .applications)
                .opacity(0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(update.name)
                    .font(SpruceFont.body)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                Text("\(update.installedVersion) → \(update.availableVersion)")
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.tertiary)
            }
            Spacer()
            PrismTextButton(title: "Stop Ignoring", module: .applications, action: onRestore)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 5)
    }
}

// MARK: - Detail

struct ApplicationsUpdateDetailPane: View {
    @Bindable var screen: ApplicationsScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if let update = screen.selectedUpdate {
                detail(update)
            } else {
                VStack(spacing: Spacing.s) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(PrismInk(contrast).tertiary)
                    Text("Select an update to see what's new.")
                        .font(SpruceFont.body)
                        .foregroundStyle(PrismInk(contrast).secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .prismSurface(radius: Radius.container)
    }

    private func detail(_ update: ApplicationsUpdate) -> some View {
        let ink = PrismInk(contrast)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .center, spacing: Spacing.m) {
                ItemIcon(url: URL(fileURLWithPath: update.appPath), symbol: "app", size: 56, module: .applications)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(update.name)
                            .font(SpruceFont.title)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                        PrismChip(text: update.source.title, color: ModuleID.applications.palette.accent2, symbol: update.source.symbol)
                    }
                    Text("Version \(update.installedVersion) → \(update.availableVersion)")
                        .font(SpruceFont.callout.monospacedDigit())
                        .foregroundStyle(ink.secondary)
                    Text(metaLine(update))
                        .font(SpruceFont.caption)
                        .foregroundStyle(ink.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ApplicationsUpdateActions(screen: screen, update: update)
            notices(update)
            ApplicationsHairline()
            releaseNotes(update)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(update.id)
    }

    private func metaLine(_ update: ApplicationsUpdate) -> String {
        var parts: [String] = []
        if let date = update.releaseDate { parts.append("Released \(DurationFormat.relative(date))") }
        if let size = update.downloadSize, size > 0 { parts.append("\(ByteFormat.string(size)) download") }
        if let minimum = update.minimumSystemVersion, !minimum.isEmpty { parts.append("Needs macOS \(minimum) or later") }
        if parts.isEmpty { parts.append(update.source.actionDetail) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func notices(_ update: ApplicationsUpdate) -> some View {
        if update.isMajor {
            ApplicationsBanner(symbol: "sparkles",
                               text: "A major upgrade. It may need a new licence or a paid upgrade, so check the developer's page first.",
                               tint: StatusColor.warning)
        }
        if case .some(.failed(let reason)) = screen.status(of: update) {
            ApplicationsBanner(symbol: "exclamationmark.triangle.fill", text: reason, tint: StatusColor.warning)
        }
        if let app = screen.app(for: update), app.isRunning, update.source == .homebrew {
            ApplicationsBanner(symbol: "circle.fill", text: "\(update.name) is open. It's asked to quit before Homebrew updates it.",
                               tint: StatusColor.success)
        }
    }

    @ViewBuilder
    private func releaseNotes(_ update: ApplicationsUpdate) -> some View {
        let ink = PrismInk(contrast)
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("WHAT'S NEW")
                    .font(SpruceFont.overline)
                    .tracking(0.8)
                    .foregroundStyle(ink.tertiary)
                Spacer()
                if update.releaseNotesURL != nil {
                    PrismTextButton(title: "Full Release Notes", symbol: "arrow.up.right", module: .applications) {
                        screen.perform(.releaseNotes, for: update)
                    }
                }
            }
            ScrollView {
                Text(update.releaseNotes ?? fallbackNotes(update))
                    .font(SpruceFont.body)
                    .foregroundStyle(update.releaseNotes == nil ? ink.tertiary : ink.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func fallbackNotes(_ update: ApplicationsUpdate) -> String {
        if update.releaseNotesURL != nil { return "The developer publishes release notes on their website." }
        switch update.source {
        case .homebrew: return "Homebrew doesn't include release notes. The developer's page usually lists the changes."
        case .appStore: return "The App Store didn't provide release notes for this version."
        case .sparkle: return "This update's feed doesn't include release notes."
        }
    }
}

/// Primary and secondary actions for one update.
struct ApplicationsUpdateActions: View {
    @Bindable var screen: ApplicationsScreenModel
    var update: ApplicationsUpdate

    var body: some View {
        let status = screen.status(of: update)
        HStack(spacing: Spacing.s) {
            switch update.source {
            case .homebrew:
                if status == .updated {
                    PrismChip(text: "Updated", color: StatusColor.success, symbol: "checkmark")
                } else {
                    CapsuleButton(title: status == .updating ? "Updating…" : "Update", symbol: "arrow.down.circle", prominent: true) {
                        screen.installHomebrew([update])
                    }
                    .disabled(screen.isInstallingUpdates)
                }
                if update.downloadURL != nil {
                    CapsuleButton(title: "Developer Page", symbol: "safari") { screen.perform(.download, for: update) }
                }
            case .appStore:
                CapsuleButton(title: "Open in App Store", symbol: "bag", prominent: true) { screen.perform(.appStore, for: update) }
            case .sparkle:
                if update.isMajor && update.downloadURL != nil {
                    CapsuleButton(title: "Download Page", symbol: "safari", prominent: true) { screen.perform(.download, for: update) }
                    CapsuleButton(title: "Open App", symbol: "arrow.up.forward.app") { screen.perform(.openApp, for: update) }
                } else {
                    CapsuleButton(title: "Open App to Update", symbol: "arrow.up.forward.app", prominent: true) {
                        screen.perform(.openApp, for: update)
                    }
                    if update.downloadURL != nil {
                        CapsuleButton(title: "Download", symbol: "arrow.down.to.line") { screen.perform(.download, for: update) }
                    }
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Skip Version \(update.availableVersion)") { screen.skipVersion(update) }
                Button("Ignore All Updates for \(update.name)") { screen.ignoreUpdates(of: update) }
            } label: {
                Text("Ignore")
                    .font(SpruceFont.button)
                    .foregroundStyle(Ink.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .prismGlassCapsule()
            .help("Hide this update")
        }
    }
}

extension ApplicationsHubText {
    /// "just now", "5 min ago", "3 h ago", "yesterday".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        return DurationFormat.relative(date, now: now)
    }
}
