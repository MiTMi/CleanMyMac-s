import SpruceCore
import SpruceMac
import SwiftUI

/// Review sheet for one Checkup tile: the contributor's `checkupReview` in a two-pane
/// list, edited on a local copy and written back only when the user presses Done.
@MainActor
struct CheckupReviewSheet: View {
    let module: ModuleID
    let session: CheckupSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var groups: [ScanGroup]
    /// Items the user chose to ignore here (already added to the ignore list).
    @State private var ignoredIDs: Set<String> = []
    /// The selection as it was when the sheet opened.
    private let original: [ScanGroup]

    init(module: ModuleID, session: CheckupSession) {
        self.module = module
        self.session = session
        let current = session.reviewGroups(for: module)
        self.original = current
        _groups = State(initialValue: current)
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: "Review \(module.title)", subtitle: subtitle, module: module,
                         trailing: AnyView(headerActions))
            ReviewSplitView(module: module, groups: $groups,
                            emptyTitle: "Nothing left to review",
                            emptyMessage: "Everything in this area was set aside or ignored.",
                            onIgnore: ignore)
            footer
        }
        .padding(Spacing.xl)
        .frame(minWidth: 880, idealWidth: 980, minHeight: 580, idealHeight: 660)
        .background {
            LivingCanvas(module: module, intensity: 0.8, animated: false)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header & footer

    private var subtitle: String {
        let all = groups.allItems
        let selected = all.filter(\.isSelected)
        var line = "\(CountFormat.grouped(selected.count)) of \(CountFormat.items(all.count)) selected"
        if showsBytes { line += " · \(ByteFormat.string(groups.selectedSize)) of \(ByteFormat.string(groups.totalSize))" }
        return line
    }

    private var showsBytes: Bool { groups.totalSize > 0 }

    private var isChanged: Bool { groups != originalWithoutIgnored }

    private var originalWithoutIgnored: [ScanGroup] {
        guard !ignoredIDs.isEmpty else { return original }
        var copy = original
        copy.removeItems(withIDs: ignoredIDs)
        return copy
    }

    private var headerActions: some View {
        Button {
            groups = originalWithoutIgnored
        } label: {
            Label("Recommended", systemImage: "wand.and.stars")
        }
        .buttonStyle(PrismCapsuleButtonStyle(role: .secondary))
        .disabled(!isChanged)
        .help("Restore the selection Checkup suggested")
    }

    private var footer: some View {
        let ink = PrismInk(contrast)
        return HStack(alignment: .center, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SELECTED")
                    .font(SpruceFont.overline)
                    .tracking(0.8)
                    .foregroundStyle(ink.tertiary)
                if showsBytes {
                    PrismMetricText(text: ByteFormat.string(groups.selectedSize), font: SpruceFont.numeral(26))
                        .animation(.snappy(duration: 0.25), value: groups.selectedSize)
                }
                Text(CountFormat.items(groups.selectedItems.count))
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(ink.tertiary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.m)
            Text("Changes apply to this Checkup only.")
                .font(SpruceFont.caption)
                .foregroundStyle(ink.tertiary)
            Button("Cancel", action: cancel)
                .buttonStyle(PrismCapsuleButtonStyle(role: .secondary, large: true))
                .keyboardShortcut(.cancelAction)
            Button("Done", action: done)
                .buttonStyle(PrismCapsuleButtonStyle(role: .primary, large: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Spacing.s)
    }

    // MARK: Actions

    private func ignore(_ item: ScanItem) {
        if let url = item.url {
            SettingsStore.shared.ignore(path: url.path)
        } else {
            SettingsStore.shared.ignore(itemID: item.id)
        }
        ignoredIDs.insert(item.id)
        groups.removeItems(withIDs: [item.id])
    }

    private func done() {
        session.applyReview(module, groups: groups)
        dismiss()
    }

    /// Discards selection edits. Ignored items stay out of the results: they are on
    /// the ignore list now and must not be acted on.
    private func cancel() {
        if !ignoredIDs.isEmpty {
            var current = session.reviewGroups(for: module)
            current.removeItems(withIDs: ignoredIDs)
            session.applyReview(module, groups: current)
        }
        dismiss()
    }
}
