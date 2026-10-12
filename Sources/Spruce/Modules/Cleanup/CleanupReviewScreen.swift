import SpruceCore
import SpruceMac
import SwiftUI

/// "Review Details": the two-pane list for one section (or all), with section
/// switching, recommended selection and the Clean orb.
struct CleanupReviewScreen: View {
    @Bindable var screen: CleanupScreenModel
    let section: CleanupSection?

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScreenHeader(title: section?.title ?? "Review Details", subtitle: subtitle, backTitle: "Overview",
                         onBack: { screen.route = .overview }, module: .cleanup,
                         trailing: AnyView(CleanupReviewToolbar(screen: screen, section: section)))
            ReviewSplitView(module: .cleanup, groups: groupsBinding,
                            emptyTitle: emptyTitle, emptyMessage: emptyMessage,
                            onIgnore: { screen.flow.ignore($0) })
                .id(section?.rawValue ?? "all")
            CleanupFooterNotes(needsAdmin: screen.selectionNeedsAdmin, movesToTrash: screen.selectionMovesToTrash)
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
    }

    /// The groups of the focused section, written back into the flow's results.
    private var groupsBinding: Binding<[ScanGroup]> {
        let flow = screen.flow
        let sectionID = section?.rawValue
        return Binding(
            get: {
                guard let sectionID else { return flow.groups }
                return flow.groups.filter { $0.id == sectionID }
            },
            set: { newValue in
                guard sectionID != nil else {
                    flow.groups = newValue
                    return
                }
                var all = flow.groups
                for group in newValue {
                    if let index = all.firstIndex(where: { $0.id == group.id }) { all[index] = group }
                }
                all.removeAll { $0.isEmpty }
                flow.groups = all
            }
        )
    }

    private var focusedGroups: [ScanGroup] {
        guard let section else { return screen.flow.groups }
        return screen.flow.groups.filter { $0.id == section.rawValue }
    }

    private var subtitle: String {
        let groups = focusedGroups
        return "\(ByteFormat.string(groups.totalSize)) in \(CountFormat.items(groups.allItems.count)) · \(ByteFormat.string(groups.selectedSize)) selected"
    }

    private var emptyTitle: String {
        switch section {
        case .some(.mailAttachments): return "No attachments to clean"
        case .some(.trashBins): return "The Trash is empty"
        default: return "Nothing to clean"
        }
    }

    private var emptyMessage: String {
        switch section {
        case .some(.mailAttachments): return "Mail isn't keeping local copies you could clear."
        case .some(.trashBins): return "There's nothing in the Trash of your Mac or connected drives."
        default: return "Nothing here needs attention right now."
        }
    }
}

/// Section switcher and the "Select" menu.
struct CleanupReviewToolbar: View {
    @Bindable var screen: CleanupScreenModel
    let section: CleanupSection?

    var body: some View {
        HStack(spacing: Spacing.s) {
            Picker("Section", selection: sectionBinding) {
                Text("All").tag(CleanupSection?.none)
                ForEach(availableSections) { item in
                    Text(item.title).tag(CleanupSection?.some(item))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Menu {
                Button("Select Recommended") { screen.selectRecommended(in: section) }
                Button("Deselect All") { screen.deselectAll(in: section) }
            } label: {
                Label("Select", systemImage: "checklist")
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Recommended = only files macOS and your apps rebuild on their own")
        }
    }

    private var availableSections: [CleanupSection] {
        CleanupSection.allCases.filter { screen.group(for: $0) != nil }
    }

    private var sectionBinding: Binding<CleanupSection?> {
        Binding(
            get: { section },
            set: { screen.route = .review($0) }
        )
    }
}
