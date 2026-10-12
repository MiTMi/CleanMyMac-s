import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Leftovers (files of removed apps) and Installers: scan → review → move to Trash.
struct ApplicationsFilesScreen: View {
    @Bindable var screen: ApplicationsScreenModel
    @Bindable var review: ApplicationsFileReview
    var tool: ApplicationsTool

    var body: some View {
        switch review.phase {
        case .idle:
            ZStack(alignment: .topLeading) {
                ModuleIdleView(module: .applications, title: title, subtitle: idleSubtitle, features: features,
                               actionTitle: "Scan") {
                    SpruceSound.play(.scanStart)
                    review.scan()
                }
                PrismBackButton(title: "Applications") { screen.goHub() }
                    .padding(.leading, Spacing.xl)
                    .padding(.top, Spacing.topInset)
            }
        case .scanning:
            ScanningView(module: .applications, progress: review.progress, title: scanningTitle,
                         onStop: { review.cancel() })
        case .results:
            results
        case .running:
            ScanningView(module: .applications, progress: review.progress, title: "Moving to the Trash…")
        case .done:
            if let outcome = review.outcome {
                DoneView(module: .applications, outcome: outcome) { review.showRemaining() }
            } else {
                EmptyStateView(module: .applications, title: "All done", message: "Nothing else to do here.",
                               actionTitle: "Back", action: { review.showRemaining() })
            }
        }
    }

    private var results: some View {
        VStack(spacing: Spacing.m) {
            ApplicationsToolHeader(screen: screen, tool: tool, title: title, subtitle: subtitle) {
                CapsuleButton(title: "Scan Again", symbol: "arrow.clockwise") { review.scan() }
            }
            if !review.groups.isEmpty {
                ApplicationsBanner(symbol: tool == .leftovers ? "info.circle" : "shippingbox", text: bannerText)
            }
            if review.groups.allItems.isEmpty {
                EmptyStateView(module: .applications, title: emptyTitle, message: emptyMessage,
                               actionTitle: "Scan Again", action: { review.scan() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReviewSplitView(module: .applications, groups: $review.groups, emptyTitle: emptyTitle,
                                emptyMessage: emptyMessage, onIgnore: { review.ignore($0) })
                ResultsFooter(module: .applications, selectedBytes: review.groups.selectedSize,
                              selectedCount: review.selectedItems.count, actionTitle: "Move to Trash",
                              totalBytes: review.totalSize, totalCount: review.groups.allItems.count) {
                    review.run()
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
    }

    // MARK: Copy

    private var title: String {
        tool == .leftovers ? "Files from Removed Apps" : "Old Installers"
    }

    private var idleSubtitle: String {
        tool == .leftovers
            ? "Support files that apps leave behind after you drag them to the Trash."
            : "Disk images, installer packages and app archives you no longer need."
    }

    private var scanningTitle: String {
        tool == .leftovers ? "Looking for files of removed apps…" : "Looking for old installers…"
    }

    private var subtitle: String {
        let items = review.groups.allItems.count
        if items == 0 { return "Nothing found" }
        if tool == .leftovers {
            return "\(ByteFormat.string(review.totalSize)) · \(CountFormat.items(review.groups.count, singular: "removed app")) · \(CountFormat.items(items, singular: "item"))"
        }
        return "\(ByteFormat.string(review.totalSize)) · \(CountFormat.items(items, singular: "installer"))"
    }

    private var bannerText: String {
        tool == .leftovers
            ? "These files are named after apps that are no longer installed. Spruce can't be completely sure nothing uses them, so nothing is selected — look through them first. Everything goes to the Trash."
            : "Installers of apps you already have, downloaded more than a month ago, are selected. Others stay unticked in case you still need them."
    }

    private var emptyTitle: String {
        tool == .leftovers ? "No leftovers found" : "No old installers"
    }

    private var emptyMessage: String {
        tool == .leftovers
            ? "No files from removed apps were found in your Library."
            : "Downloads and the Desktop have no disk images or installer packages."
    }

    private var features: [IdleFeature] {
        if tool == .leftovers {
            return [
                IdleFeature(symbol: "questionmark.folder", title: "Named after removed apps",
                            detail: "Only files whose names match an app that's no longer installed are listed."),
                IdleFeature(symbol: "hand.raised", title: "Nothing pre-selected",
                            detail: "You decide what goes. Apple's files and shared components are never listed."),
                IdleFeature(symbol: "trash", title: "Recoverable",
                            detail: "Removed files go to the Trash, where you can put them back."),
            ]
        }
        return [
            IdleFeature(symbol: "externaldrive", title: "Disk images and packages",
                        detail: ".dmg, .pkg, .xip and app archives in Downloads and on the Desktop."),
            IdleFeature(symbol: "checkmark.circle", title: "Matched to your apps",
                        detail: "Installers of apps you already have are recognised and pre-selected once they're a month old."),
            IdleFeature(symbol: "trash", title: "Recoverable",
                        detail: "Removed installers go to the Trash."),
        ]
    }
}
