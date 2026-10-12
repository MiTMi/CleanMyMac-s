import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Shredder: drop or choose items → review → confirm → overwrite and delete → result.
struct ToolboxShredderScreen: View {
    @Bindable var shredder: ToolboxShredderModel
    var onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ToolboxToolFrame(onBack: onBack) {
            ZStack {
                phaseContent
                    .id(phaseKey)
                    .transition(.prismPhase(reduceMotion: reduceMotion))
            }
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: phaseKey)
        }
        .confirmationDialog(confirmTitle, isPresented: $shredder.confirming, titleVisibility: .visible) {
            Button("Shred", role: .destructive) { shredder.shred() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They're overwritten with zeros and deleted. They won't be in the Trash, and this can't be undone.")
        }
    }

    private var confirmTitle: String {
        let items = shredder.shreddable
        if items.count == 1, let only = items.first { return "Shred \u{201C}\(only.name)\u{201D}?" }
        return "Shred \(CountFormat.items(items.count))?"
    }

    private var phaseKey: String {
        switch shredder.phase {
        case .choosing: return "choosing"
        case .inspecting: return "inspecting"
        case .review: return "review"
        case .shredding: return "shredding"
        case .done: return "done"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch shredder.phase {
        case .choosing:
            ToolboxShredderDropScreen(shredder: shredder)
        case .inspecting:
            ScanningView(module: .toolbox, progress: shredder.progress, title: "Checking…", showsBytes: false)
        case .review:
            ToolboxShredderReviewScreen(shredder: shredder)
        case .shredding:
            ScanningView(module: .toolbox, progress: shredder.progress, title: "Shredding…",
                         stopTitle: "Stop", onStop: { shredder.stop() }, showsBytes: false)
        case .done(let outcome):
            DoneView(module: .toolbox, outcome: outcome,
                     headline: outcome.freedBytes > 0 ? nil : (outcome.processedCount > 0 ? "Overwritten" : nil)) {
                shredder.finish()
            }
        }
    }
}

// MARK: - Drop zone

struct ToolboxShredderDropScreen: View {
    @Bindable var shredder: ToolboxShredderModel

    @State private var isTargeted = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.topInset + Spacing.xl)
            HStack(alignment: .center, spacing: Spacing.xl) {
                HeroLens(module: .toolbox, size: 150, glyph: "scissors", parallax: false)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Shredder")
                        .font(SpruceFont.display(34))
                        .foregroundStyle(Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Overwrite files with zeros, then delete them for good, so they don't sit recoverable in the Trash or on the disk.")
                        .font(SpruceFont.body)
                        .foregroundStyle(PrismInk(contrast).secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
            dropZone
            ToolboxShredderCaveat()
                .frame(maxWidth: 620)
            Spacer(minLength: Spacing.l)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.contentInset)
    }

    private var dropZone: some View {
        let accent = ModuleID.toolbox.palette.accent
        return VStack(spacing: Spacing.m) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isTargeted ? accent : Ink.secondary)
            Text(isTargeted ? "Release to add" : "Drop files or folders here")
                .font(SpruceFont.headline)
                .foregroundStyle(Ink.primary)
            CapsuleButton(title: "Choose…", symbol: "folder", prominent: true) {
                shredder.choose()
            }
        }
        .frame(maxWidth: 620)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(isTargeted ? accent.opacity(0.12) : Ink.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isTargeted ? accent : Ink.highlight, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            shredder.add(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .animation(Motion.quick, value: isTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop files or folders to shred")
    }
}

/// Honest note about what overwriting can and can't do on modern Macs.
struct ToolboxShredderCaveat: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(StatusColor.info)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("About SSDs")
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                Text("Your Mac's SSD spreads writes across its cells, and APFS snapshots or copies can keep older versions, so no app can promise every trace is physically erased. FileVault encryption is what really protects deleted data; the Shredder adds a best-effort overwrite and skips the Trash.")
                    .font(SpruceFont.caption)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .prismSurface(radius: Radius.row, tint: StatusColor.info)
    }
}

// MARK: - Review

struct ToolboxShredderReviewScreen: View {
    @Bindable var shredder: ToolboxShredderModel

    @State private var isTargeted = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ScreenHeader(title: "Shredder", subtitle: ToolboxShredPlan.summary(shredder.plans))
            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(shredder.plans) { plan in
                        ToolboxShredRow(plan: plan) { shredder.remove(plan) }
                    }
                }
                .padding(Spacing.s)
            }
            .scrollIndicators(.automatic)
            .background(
                RoundedRectangle(cornerRadius: Radius.container, style: .continuous)
                    .fill(isTargeted ? ModuleID.toolbox.palette.accent.opacity(0.10) : Color.clear)
            )
            .prismSurface(radius: Radius.container)
            .dropDestination(for: URL.self) { urls, _ in
                shredder.add(urls)
                return !urls.isEmpty
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            ToolboxShredderCaveat()
            footer
        }
        .frame(maxWidth: Spacing.readableWidth)
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset + 40)   // below the back bar
        .padding(.bottom, Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            CapsuleButton(title: "Add More…", symbol: "plus") { shredder.choose() }
            CapsuleButton(title: "Clear List", symbol: "xmark") { shredder.clear() }
            Spacer()
            let blocked = shredder.plans.count - shredder.shreddable.count
            if blocked > 0 {
                Text("\(CountFormat.items(blocked)) can't be shredded")
                    .font(SpruceFont.caption)
                    .foregroundStyle(StatusColor.warning)
            }
            CapsuleButton(title: shredder.shreddable.isEmpty ? "Shred" : "Shred \(ByteFormat.string(shredder.shreddableBytes))",
                          symbol: "scissors", destructive: true, large: true) {
                shredder.confirming = true
            }
            .disabled(shredder.shreddable.isEmpty)
        }
    }
}

struct ToolboxShredRow: View {
    var plan: ToolboxShredPlan
    var onRemove: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Spacing.m) {
            ItemIcon(url: URL(fileURLWithPath: plan.root), symbol: plan.isDirectory ? "folder" : "doc", size: 30)
                .opacity(plan.canShred ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(SpruceFont.body.weight(.medium))
                    .foregroundStyle(plan.canShred ? Ink.primary : Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let problem = plan.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(SpruceFont.caption)
                        .foregroundStyle(StatusColor.warning)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(detail)
                        .font(SpruceFont.caption)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: Spacing.m)
            if plan.canShred {
                SizeBadge(bytes: plan.allocatedBytes, emphasized: true)
            }
            PrismIconButton(symbol: "xmark", help: "Remove from the list", action: onRemove)
                .opacity(hovering || !plan.canShred ? 1 : 0.55)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hovering ? Ink.subtleFill : Color.clear))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: plan.root)])
            }
            Button("Remove from List", action: onRemove)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let location = (plan.root as NSString).deletingLastPathComponent.abbreviatingHome
        if plan.isDirectory {
            return "\(CountFormat.items(plan.files.count, singular: "file")) · \(location)"
        }
        return location
    }
}
