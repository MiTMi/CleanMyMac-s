import SpruceCore
import SpruceMac
import SwiftUI

/// Scan summary: headline, one card per section, informational findings and the Clean orb.
struct CleanupResultsScreen: View {
    @Environment(AppModel.self) private var model
    @Bindable var screen: CleanupScreenModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: "Cleanup", subtitle: headerSubtitle, backTitle: "Start Over",
                         onBack: { screen.confirmStartOver = true }, module: .cleanup,
                         trailing: AnyView(CapsuleButton(title: "Review Details", symbol: "list.bullet.rectangle") {
                             screen.route = .review(nil)
                         }))
            if !screen.unavailable.isEmpty {
                CleanupAccessBanner(unavailable: screen.unavailable,
                                    onOpenSettings: { Permissions.openFullDiskAccessSettings() },
                                    onCheckAgain: checkAccessAgain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CleanupHeadline(selected: screen.flow.selectedSize, found: screen.flow.totalSize)
                    cards
                    CleanupInsightsCard(insights: screen.report?.insights ?? [])
                }
                .padding(.bottom, Spacing.m)
            }
            .scrollIndicators(.never)
            CleanupFooterNotes(needsAdmin: screen.selectionNeedsAdmin, movesToTrash: screen.selectionMovesToTrash,
                               emptiesTrash: screen.selectionEmptiesTrash)
            ResultsFooter(module: .cleanup, selectedBytes: screen.flow.selectedSize,
                          selectedCount: screen.flow.selectedCount, actionTitle: "Clean",
                          totalBytes: screen.flow.totalSize, totalCount: screen.flow.groups.allItems.count) {
                screen.requestClean()
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.l)
        .overlay {
            if screen.isWaitingForApps { CleanupWaitingOverlay() }
        }
        .confirmationDialog("Discard these results?", isPresented: $screen.confirmStartOver, titleVisibility: .visible) {
            Button("Start Over", role: .destructive) { screen.startOver() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your selection will be lost. You can scan again at any time.")
        }
    }

    private var headerSubtitle: String {
        guard let date = screen.report?.date ?? screen.flow.lastScanDate else { return "Scan results" }
        let time = date.formatted(date: .omitted, time: .shortened)
        return "Scanned at \(time) · \(CountFormat.items(screen.flow.groups.allItems.count)) found"
    }

    private var cards: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            card(.systemJunk, isLead: true)
                .frame(maxWidth: .infinity)
            VStack(spacing: Spacing.m) {
                card(.mailAttachments, isLead: false)
                card(.trashBins, isLead: false)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func card(_ section: CleanupSection, isLead: Bool) -> some View {
        let group = screen.group(for: section)
        return CleanupSectionCard(
            section: section,
            group: group,
            state: state(for: section, group: group),
            isLead: isLead,
            inUseCount: section == .systemJunk ? screen.inUseCount : 0,
            unavailable: section == .systemJunk ? screen.unavailableItems(in: .systemJunk) : [],
            onReview: { screen.route = .review(section) },
            onClean: { screen.requestClean(in: section) },
            onToggle: { screen.toggleSection(section) },
            onScan: { screen.startScan() },
            onGrantAccess: { Permissions.openFullDiskAccessSettings() }
        )
    }

    private func state(for section: CleanupSection, group: ScanGroup?) -> CleanupCardState {
        guard screen.scannedSections.contains(section) else { return .notScanned }
        if let group, !group.isEmpty { return .ready }
        let blocked = !screen.unavailableItems(in: section).isEmpty
        if blocked && section != .systemJunk { return .needsAccess }
        return .empty
    }

    /// "Check Again" re-reads the permission; the scan reruns as soon as it is granted
    /// (or right away when access was on but macOS refused a location).
    private func checkAccessAgain() {
        model.refreshPermissions()
        let missingAccess = screen.unavailable.contains { $0.reason == .fullDiskAccess }
        if model.hasFullDiskAccess || !missingAccess {
            screen.startScan(sections: screen.scannedSections)
        }
    }
}

/// "6.2 GB ready to clean" hero line.
struct CleanupHeadline: View {
    let selected: Int64
    let found: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if found == 0 {
                Text("Spotless.")
                    .font(SpruceFont.display(34))
                    .foregroundStyle(Ink.primary)
                Text("Nothing here needs cleaning right now.")
                    .font(SpruceFont.body)
                    .foregroundStyle(Ink.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(ByteFormat.string(selected))
                        .font(SpruceFont.numeral(52))
                        .foregroundStyle(ModuleID.cleanup.palette.accentText)
                        .contentTransition(.numericText())
                    Text("ready to clean")
                        .font(SpruceFont.title)
                        .foregroundStyle(Ink.primary)
                }
                Text("of \(ByteFormat.string(found)) found. Pre-selected items are files macOS and your apps rebuild on their own.")
                    .font(SpruceFont.body)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Short notes about how the selection will be handled (password prompt, what goes to
/// the Trash, what is deleted for good).
struct CleanupFooterNotes: View {
    let needsAdmin: Bool
    let movesToTrash: Int
    var emptiesTrash: Int = 0

    var body: some View {
        let notes = self.notes
        if !notes.isEmpty {
            HStack(spacing: Spacing.l) {
                ForEach(notes, id: \.text) { note in
                    Label(note.text, systemImage: note.symbol)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(SpruceFont.caption)
            .foregroundStyle(Ink.tertiary)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private struct Note {
        var text: String
        var symbol: String
    }

    private var notes: [Note] {
        var out: [Note] = []
        if needsAdmin {
            out.append(Note(text: "System files: macOS asks for your password once", symbol: "key"))
        }
        if movesToTrash > 0 {
            out.append(Note(text: "\(CountFormat.items(movesToTrash)) go to the Trash, so you can put them back",
                            symbol: "arrow.uturn.backward"))
        }
        if emptiesTrash > 0 {
            out.append(Note(text: "Emptying the Trash can't be undone", symbol: "trash"))
        }
        return out
    }
}
