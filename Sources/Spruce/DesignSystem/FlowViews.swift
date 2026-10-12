import AppKit
import SpruceCore
import SwiftUI

// Standard screens for the module journey. CONTRACT: keep names and existing
// parameters; restyling and new defaulted parameters are fine.

/// A feature bullet on a module's idle screen.
struct IdleFeature: Identifiable {
    var id: String { title }
    var symbol: String
    var title: String
    var detail: String
}

/// Idle/intro screen: hero art, title, tagline, feature bullets, primary orb.
struct ModuleIdleView: View {
    var module: ModuleID
    var title: String? = nil
    var subtitle: String? = nil
    var features: [IdleFeature] = []
    var actionTitle: String = "Scan"
    var actionSubtitle: String? = nil
    var isEnabled: Bool = true
    var notice: String? = nil
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.xl)
            HStack(alignment: .center, spacing: Spacing.xxxl) {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text(title ?? module.title)
                        .font(SpruceFont.display())
                        .foregroundStyle(Ink.primary)
                    Text(subtitle ?? module.tagline)
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !features.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            ForEach(features) { f in
                                HStack(alignment: .top, spacing: Spacing.m) {
                                    Image(systemName: f.symbol)
                                        .font(.system(size: 16))
                                        .foregroundStyle(module.palette.accentText)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.title).font(SpruceFont.headline).foregroundStyle(Ink.primary)
                                        Text(f.detail).font(SpruceFont.callout).foregroundStyle(Ink.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, Spacing.s)
                    }
                    if let notice {
                        Label(notice, systemImage: "info.circle")
                            .font(SpruceFont.callout)
                            .foregroundStyle(StatusColor.warning)
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
                HeroLens(module: module, size: 220)
            }
            .padding(.horizontal, Spacing.xxxl)
            Spacer(minLength: Spacing.xl)
            ActionOrb(title: actionTitle, subtitle: actionSubtitle, module: module, isEnabled: isEnabled, action: action)
                .padding(.bottom, 28)
        }
    }
}

/// Scanning/running screen with live progress.
struct ScanningView: View {
    var module: ModuleID
    var progress: ScanProgress
    var title: String = "Scanning…"
    var stopTitle: String = "Stop"
    var onStop: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            HeroLens(module: module, size: 200, isAnimating: true)
            VStack(spacing: Spacing.s) {
                Text(title).font(SpruceFont.title).foregroundStyle(Ink.primary)
                Text(progress.message).font(SpruceFont.body).foregroundStyle(Ink.secondary)
                if let current = progress.current {
                    Text(current)
                        .font(SpruceFont.mono)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                }
                if progress.bytesFound > 0 {
                    Text(ByteFormat.string(progress.bytesFound))
                        .font(SpruceFont.numeral(40))
                        .foregroundStyle(module.palette.accentText)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            if let onStop {
                ActionOrb(title: stopTitle, module: module, progress: progress.fraction, isBusy: true, action: onStop)
                    .padding(.bottom, 28)
            } else {
                ProgressRing(progress: progress.fraction, module: module)
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Two-pane review list for grouped scan results with checkboxes.
struct ReviewSplitView: View {
    var module: ModuleID
    @Binding var groups: [ScanGroup]
    var emptyTitle: String = "Nothing found"
    var emptyMessage: String = "Your Mac is spotless here."
    /// Called when the user chooses "Ignore" on an item (nil hides the action).
    var onIgnore: ((ScanItem) -> Void)? = nil

    @State private var selectedGroupID: String?
    @State private var sortBySize = true
    @State private var search = ""

    private var flatGroups: [ScanGroup] {
        groups.flatMap { g -> [ScanGroup] in
            g.children.isEmpty ? [g] : [ScanGroup(id: g.id, title: g.title, detail: g.detail, symbol: g.symbol,
                                                 safety: g.safety, items: g.items)] .filter { !$0.items.isEmpty } + g.children
        }
    }

    private var currentGroup: ScanGroup? {
        let all = flatGroups
        return all.first { $0.id == selectedGroupID } ?? all.first
    }

    var body: some View {
        if groups.allItems.isEmpty {
            EmptyStateView(module: module, title: emptyTitle, message: emptyMessage)
        } else {
            HStack(spacing: Spacing.m) {
                groupList.frame(width: 300)
                itemList
            }
        }
    }

    private var groupList: some View {
        GlassCard(padding: Spacing.s) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(flatGroups) { group in
                        let isCurrent = group.id == currentGroup?.id
                        HStack(spacing: Spacing.s) {
                            SpruceCheckbox(state: group.selectionState, module: module) {
                                setGroup(group.id, selected: group.selectionState != .all)
                            }
                            Image(systemName: group.symbol)
                                .foregroundStyle(module.palette.accentText)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.title).font(SpruceFont.body.weight(.medium)).foregroundStyle(Ink.primary)
                                    .lineLimit(1)
                                Text(CountFormat.items(group.totalCount)).font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
                            }
                            Spacer()
                            Text(ByteFormat.string(group.totalSize))
                                .font(SpruceFont.callout.monospacedDigit())
                                .foregroundStyle(Ink.secondary)
                        }
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, 7)
                        .background(isCurrent ? Ink.selectedFill : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedGroupID = group.id }
                    }
                }
            }
        }
    }

    private var itemList: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                if let group = currentGroup {
                    HStack(spacing: Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title).font(SpruceFont.headline).foregroundStyle(Ink.primary)
                            if !group.detail.isEmpty {
                                Text(group.detail).font(SpruceFont.caption).foregroundStyle(Ink.tertiary).lineLimit(2)
                            }
                        }
                        Spacer()
                        TextField("Search", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Picker("", selection: $sortBySize) {
                            Text("Size").tag(true)
                            Text("Name").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                    .padding(Spacing.m)
                    Divider().overlay(Ink.hairline)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sorted(group.items)) { item in
                                ItemRow(item: item, module: module, onToggle: { toggle(item) }, onIgnore: onIgnore)
                                Divider().overlay(Ink.hairline).padding(.leading, 52)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sorted(_ items: [ScanItem]) -> [ScanItem] {
        let filtered = search.isEmpty ? items : items.filter {
            $0.title.localizedCaseInsensitiveContains(search) || ($0.subtitle ?? "").localizedCaseInsensitiveContains(search)
        }
        return sortBySize ? filtered.sorted { $0.size > $1.size }
            : filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func toggle(_ item: ScanItem) {
        groups.setSelected(!item.isSelected, itemID: item.id)
    }

    private func setGroup(_ id: String, selected: Bool) {
        func apply(_ gs: inout [ScanGroup]) -> Bool {
            for i in gs.indices {
                if gs[i].id == id {
                    // For a parent shown flattened, only its own items are affected.
                    if gs[i].children.isEmpty {
                        gs[i].setAllSelected(selected)
                    } else {
                        for j in gs[i].items.indices { gs[i].items[j].isSelected = selected && gs[i].items[j].safety != .risky }
                    }
                    return true
                }
                if apply(&gs[i].children) { return true }
            }
            return false
        }
        _ = apply(&groups)
    }
}

/// One selectable result row.
struct ItemRow: View {
    var item: ScanItem
    var module: ModuleID
    var onToggle: () -> Void
    var onIgnore: ((ScanItem) -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.m) {
            SpruceCheckbox(isOn: item.isSelected, module: module, action: onToggle)
            ItemIcon(url: item.url, symbol: item.symbol, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title).font(SpruceFont.body).foregroundStyle(Ink.primary).lineLimit(1)
                    if item.safety != .safe {
                        Circle().fill(StatusColor.of(item.safety)).frame(width: 6, height: 6)
                            .help(item.safety.label)
                    }
                }
                if let subtitle = item.subtitle {
                    Text(subtitle).font(SpruceFont.caption).foregroundStyle(Ink.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if let lastUsed = item.lastUsed {
                Text(DurationFormat.relative(lastUsed)).font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
            }
            Text(ByteFormat.string(item.size)).font(SpruceFont.callout.monospacedDigit()).foregroundStyle(Ink.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .contextMenu {
            if let url = item.url {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            if let onIgnore {
                Button("Ignore") { onIgnore(item) }
            }
        }
        .help(item.note ?? item.safety.label)
    }
}

/// Footer with the selection total and the primary orb on results screens.
struct ResultsFooter: View {
    var module: ModuleID
    var selectedBytes: Int64
    var selectedCount: Int
    var actionTitle: String = "Remove"
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected").font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
                Text(ByteFormat.string(selectedBytes)).font(SpruceFont.numeral(28)).foregroundStyle(Ink.primary)
                    .contentTransition(.numericText())
                Text(CountFormat.items(selectedCount)).font(SpruceFont.caption).foregroundStyle(Ink.tertiary)
            }
            .frame(width: 180, alignment: .leading)
            Spacer()
            ActionOrb(title: actionTitle, subtitle: selectedBytes > 0 ? ByteFormat.string(selectedBytes) : nil,
                      module: module, isEnabled: isEnabled && selectedCount > 0, diameter: 84, action: action)
            Spacer()
            Color.clear.frame(width: 180, height: 1)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
    }
}

/// Completion screen.
struct DoneView: View {
    var module: ModuleID
    var outcome: RunOutcome
    var headline: String? = nil
    var doneTitle: String = "Done"
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            ZStack {
                Circle().fill(module.palette.glow.opacity(0.35)).frame(width: 220, height: 220).blur(radius: 40)
                Image(systemName: outcome.failures.isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 88, weight: .ultraLight))
                    .foregroundStyle(module.palette.accentGradient)
            }
            Text(headline ?? (outcome.freedBytes > 0 ? "\(ByteFormat.string(outcome.freedBytes)) freed" : "All done"))
                .font(SpruceFont.display(30))
                .foregroundStyle(Ink.primary)
            if !outcome.summary.isEmpty {
                Text(outcome.summary).font(SpruceFont.body).foregroundStyle(Ink.secondary)
            }
            if !outcome.failures.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Couldn't complete", trailing: CountFormat.items(outcome.failures.count))
                        ForEach(outcome.failures.prefix(6), id: \.self) { f in
                            HStack(alignment: .top) {
                                Text(f.title).font(SpruceFont.callout).foregroundStyle(Ink.primary).lineLimit(1)
                                Spacer()
                                Text(f.reason).font(SpruceFont.caption).foregroundStyle(Ink.tertiary).lineLimit(2)
                            }
                        }
                    }
                }
                .frame(maxWidth: 560)
            }
            Spacer()
            ActionOrb(title: doneTitle, module: module, diameter: 84, action: onDone)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    var module: ModuleID
    var title: String
    var message: String
    var symbol: String = "checkmark.seal"

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(module.palette.accentGradient)
            Text(title).font(SpruceFont.title).foregroundStyle(Ink.primary)
            Text(message).font(SpruceFont.body).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Error screen with retry.
struct FailureView: View {
    var module: ModuleID
    var message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            EmptyStateView(module: module, title: "Something went wrong", message: message, symbol: "exclamationmark.triangle")
            CapsuleButton(title: "Try Again", symbol: "arrow.clockwise", prominent: true, action: onRetry)
                .padding(.bottom, Spacing.xxl)
        }
    }
}

/// A Checkup result tile.
struct ResultTile: View {
    var tile: CheckupTile
    var isSelected: Bool
    var onToggle: () -> Void
    var onReview: (() -> Void)? = nil

    var body: some View {
        let p = tile.module.palette
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    Image(systemName: p.symbol).foregroundStyle(p.accentText)
                    Text(tile.module.title).font(SpruceFont.headline).foregroundStyle(Ink.primary)
                    Spacer()
                    if tile.status != .unavailable && tile.status != .clear {
                        SpruceCheckbox(isOn: isSelected, module: tile.module, action: onToggle)
                    }
                }
                Text(tile.headline)
                    .font(SpruceFont.numeral(34))
                    .foregroundStyle(tile.status == .unavailable ? Ink.disabled : Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(tile.detail).font(SpruceFont.callout).foregroundStyle(Ink.secondary).lineLimit(2)
                Spacer(minLength: 0)
                HStack {
                    StatusPill(text: statusText, status: tile.status)
                    Spacer()
                    if let onReview, tile.status != .unavailable {
                        CapsuleButton(title: "Review", action: onReview)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        }
        .opacity(tile.status == .unavailable ? 0.6 : 1)
    }

    private var statusText: String {
        switch tile.status {
        case .clear: return "All good"
        case .attention: return tile.actionCount > 0 ? CountFormat.items(tile.actionCount, singular: "action") : "Recommended"
        case .critical: return "Needs attention"
        case .info: return "Info"
        case .unavailable: return "Skipped"
        }
    }
}

/// Complete standard journey for a `ScanFlowModel`. Modules with a simple
/// "scan → review list → remove" shape can use this directly.
struct ScanFlowScreen: View {
    @Bindable var flow: ScanFlowModel
    var idleTitle: String? = nil
    var idleSubtitle: String? = nil
    var features: [IdleFeature] = []
    var scanTitle: String = "Scan"
    var actionTitle: String = "Remove"
    var resultsTitle: String? = nil
    var notice: String? = nil

    var body: some View {
        switch flow.phase {
        case .idle:
            ModuleIdleView(module: flow.module, title: idleTitle, subtitle: idleSubtitle, features: features,
                           actionTitle: scanTitle, notice: notice) { flow.startScan() }
        case .scanning:
            ScanningView(module: flow.module, progress: flow.progress, onStop: { flow.cancel() })
        case .results:
            VStack(spacing: Spacing.m) {
                ScreenHeader(title: resultsTitle ?? flow.module.title,
                             subtitle: "Found \(ByteFormat.string(flow.totalSize)) · \(CountFormat.items(flow.groups.allItems.count))",
                             backTitle: "Start Over", onBack: { flow.reset() })
                ReviewSplitView(module: flow.module, groups: $flow.groups, onIgnore: { flow.ignore($0) })
                ResultsFooter(module: flow.module, selectedBytes: flow.selectedSize, selectedCount: flow.selectedCount,
                              actionTitle: actionTitle) { flow.run() }
            }
            .padding([.horizontal, .top], Spacing.xl)
        case .running:
            ScanningView(module: flow.module, progress: flow.progress, title: "Working…")
        case .done:
            if let outcome = flow.outcome {
                DoneView(module: flow.module, outcome: outcome) { flow.showRemaining() }
            }
        case .failed(let message):
            FailureView(module: flow.module, message: message) { flow.startScan() }
        }
    }
}
