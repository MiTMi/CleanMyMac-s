import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Privacy results: one group per browser (plus macOS), traces as items, Clean action.
struct ProtectionPrivacyResultsScreen: View {
    @Bindable var screen: ProtectionScreenModel
    @Bindable var flow: ScanFlowModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: "Privacy", subtitle: subtitle, backTitle: "Protection", onBack: { screen.showHub() },
                         module: .protection,
                         trailing: AnyView(PrismTextButton(title: "Start Over", symbol: "arrow.counterclockwise",
                                                           module: .protection) { screen.startOver(.privacy) }))
            banners
            if flow.groups.allItems.isEmpty {
                EmptyStateView(module: .protection, title: "No privacy traces found",
                               message: "Your browsers and macOS aren't keeping anything Spruce can clear right now.",
                               actionTitle: "Scan Again", action: { screen.startScan(.privacy) })
            } else {
                ReviewSplitView(module: .protection, groups: $flow.groups, emptyTitle: "Nothing selected here",
                                emptyMessage: "No privacy traces in this group.", onIgnore: nil, showsSearch: false)
                ResultsFooter(module: .protection, selectedBytes: flow.selectedSize, selectedCount: flow.selectedCount,
                              actionTitle: "Clean", isEnabled: !screen.isQuittingBrowsers, totalBytes: flow.totalSize,
                              totalCount: flow.groups.allItems.count) {
                    screen.requestPrivacyClean()
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    private var subtitle: String {
        let sources = flow.groups.count
        guard sources > 0 else { return "Browsers and macOS lists" }
        return "\(ByteFormat.string(flow.totalSize)) of traces in \(CountFormat.items(sources, singular: "place"))"
    }

    @ViewBuilder
    private var banners: some View {
        let running = screen.runningBrowsersInResults()
        if !running.isEmpty {
            ProtectionNoticeBanner(
                symbol: "exclamationmark.triangle.fill",
                text: "\(ProtectionPrivacyText.list(running.map { ProtectionPrivacyCleaner.name(ofSource: $0) })) \(running.count == 1 ? "is" : "are") open. Quit before cleaning so nothing is written back.",
                actionTitle: screen.isQuittingBrowsers ? "Quitting…" : (running.count == 1 ? "Quit Browser" : "Quit Browsers"),
                action: { screen.quitBrowsers(running) })
        }
        if let report = screen.privacyReport, report.needsFullDiskAccess, !screen.hasFullDiskAccess {
            ProtectionNoticeBanner(
                symbol: "lock.fill",
                text: "\(ProtectionPrivacyText.list(report.unreadableSources))'s data is protected by macOS. Allow Full Disk Access, then scan again to include it.",
                actionTitle: "Grant Access",
                action: { Permissions.openFullDiskAccessSettings() })
        }
    }
}

enum ProtectionPrivacyText {
    /// "Safari", "Safari and Chrome", "Safari, Chrome and Firefox".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}

/// "Quit these browsers to clean?" with Quit and Clean / Skip / Cancel.
struct ProtectionBrowserQuitSheet: View {
    var prompt: ProtectionBrowserPrompt
    var onQuit: () -> Void
    var onSkip: () -> Void
    var onCancel: () -> Void

    var body: some View {
        PrismSheetCard(title: prompt.sourceIDs.count == 1 ? "Quit \(prompt.names[0]) to clean it?" : "Quit these browsers to clean them?",
                       message: "Browsers keep their history and cookies open while running and would write them back. They may ask you to save first.",
                       primaryTitle: "Quit and Clean", onCancel: onCancel, onPrimary: onQuit) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(prompt.sourceIDs, id: \.self) { sourceID in
                    HStack(spacing: Spacing.s) {
                        ProtectionBrowserIcon(sourceID: sourceID)
                        Text(ProtectionPrivacyCleaner.name(ofSource: sourceID))
                            .font(SpruceFont.body.weight(.medium))
                            .foregroundStyle(Ink.primary)
                        Spacer()
                    }
                }
                Button("Skip These Browsers and Clean the Rest", action: onSkip)
                    .buttonStyle(.plain)
                    .font(SpruceFont.callout.weight(.semibold))
                    .foregroundStyle(ModuleID.protection.palette.accentText)
                    .padding(.top, Spacing.xs)
            }
        }
    }
}

/// The installed browser's app icon (falls back to a globe).
struct ProtectionBrowserIcon: View {
    var sourceID: String

    var body: some View {
        ItemIcon(url: appURL, symbol: "globe", size: 24, module: .protection)
    }

    private var appURL: URL? {
        guard let id = ProtectionBrowserID(rawValue: sourceID),
              let browser = ProtectionPrivacyCatalog.browser(id) else { return nil }
        for bundleID in browser.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return url }
        }
        return nil
    }
}
