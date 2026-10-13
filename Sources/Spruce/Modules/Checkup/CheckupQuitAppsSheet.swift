import AppKit
import SpruceCore
import SwiftUI

/// "Quit these apps first?" before a Checkup run: the open apps that hold up selected
/// items, each with its own Quit button, then Quit All & Run, Skip These Items or Cancel.
/// Apps are only asked to quit normally, so they can offer to save open work; nothing is
/// ever force quit.
///
/// Reads the prompt from the session (not a copy), so apps that quit leave the list and
/// the "Quitting…" state shows as it changes.
@MainActor
struct CheckupQuitAppsSheet: View {
    let session: CheckupSession
    /// The prompt the sheet was opened with (shown while the session clears it).
    var initial: CheckupQuitPrompt

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let apps = session.quitPrompt?.apps ?? initial.apps
        let single = apps.count == 1 ? apps.first : nil
        PrismSheetCard(title: single.map { "Quit \($0.name) first?" } ?? "Some apps should be quit first",
                       message: "Selected items belong to apps that are open, and they can't be cleaned or updated while the apps run. Each app is asked to quit normally, so it can offer to save your work first.",
                       primaryTitle: single == nil ? "Quit All & Run" : "Quit & Run",
                       onCancel: { session.cancelQuitPrompt() },
                       onPrimary: { session.quitAllBlockingAppsAndRun() }) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                VStack(spacing: 0) {
                    ForEach(apps) { app in
                        row(app)
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.subtleFill))
                PrismTextButton(title: "Skip these items and run the rest", symbol: "forward.end", module: .checkup,
                                action: { session.skipBlockedItemsAndRun() })
                    .padding(.top, Spacing.xs)
                    .help("Leaves the items these apps hold up unselected; they stay in the results for later.")
            }
        }
    }

    private func row(_ app: CheckupBlockingApp) -> some View {
        let isQuitting = session.quittingApps.contains(app.processID)
        return HStack(spacing: Spacing.s) {
            ItemIcon(url: app.appPath.map { URL(fileURLWithPath: $0) }, symbol: "app", size: 26, module: .checkup)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text(app.detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(PrismInk(contrast).tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(app.detail)
            }
            Spacer(minLength: Spacing.s)
            if isQuitting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Quitting…")
                        .font(SpruceFont.caption)
                        .foregroundStyle(PrismInk(contrast).secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                CapsuleButton(title: "Quit") { session.quitBlockingApp(app) }
                    .help("Ask \(app.name) to quit")
                    .accessibilityLabel(Text("Quit \(app.name)"))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

/// Covers the results while Quit All waits for the apps to quit.
@MainActor
struct CheckupWaitingForAppsOverlay: View {
    var onRunNow: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            GlassCard(padding: Spacing.xl) {
                HStack(spacing: Spacing.m) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for apps to quit…")
                            .font(SpruceFont.body)
                            .foregroundStyle(Ink.primary)
                        Text("Checkup runs as soon as they have closed.")
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.secondary)
                    }
                    CapsuleButton(title: "Run Now", action: onRunNow)
                        .help("Run without waiting; items of apps that are still open are skipped")
                }
            }
        }
        .transition(.opacity)
    }
}
