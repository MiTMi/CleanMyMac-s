import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Extensions: app extensions with on/off switches and plug-in files that can be removed.
struct ApplicationsExtensionsScreen: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            ApplicationsToolHeader(screen: screen, tool: .extensions, title: "Extensions", subtitle: subtitle) {
                trailingControls
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.topInset)
        .padding(.bottom, Spacing.l)
    }

    private var subtitle: String {
        if screen.extensionsPhase == .loading && screen.extensions.isEmpty { return "Looking for extensions…" }
        let all = screen.extensions
        let off = all.filter { $0.isEnabled == false }.count
        var text = CountFormat.items(all.count, singular: "extension")
        if off > 0 { text += " · \(off) turned off" }
        return text
    }

    private var trailingControls: some View {
        HStack(spacing: Spacing.s) {
            PrismSearchField(text: $screen.extensionSearch, prompt: "Search extensions", width: 200)
            if screen.extensionsPhase == .loading {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else {
                PrismIconButton(symbol: "arrow.clockwise", help: "Refresh") { screen.loadExtensions() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if screen.extensions.isEmpty {
            if screen.extensionsPhase == .ready {
                EmptyStateView(module: .applications, title: "No extensions",
                               message: "No third-party extensions or plug-ins are installed. Apple's own are never listed.")
            } else {
                ApplicationsLoadingPane(message: "Looking for extensions and plug-ins…")
            }
        } else {
            HStack(spacing: Spacing.m) {
                ApplicationsExtensionKindColumn(screen: screen)
                    .frame(width: 236)
                ApplicationsExtensionListPane(screen: screen)
            }
        }
    }
}

// MARK: - Kind column

struct ApplicationsExtensionKindColumn: View {
    @Bindable var screen: ApplicationsScreenModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ApplicationsFacetRow(title: "All Extensions", symbol: "square.grid.2x2",
                                     count: CountFormat.grouped(screen.extensionCount(nil)),
                                     isSelected: screen.extensionKind == nil) {
                    withAnimation(Motion.quick) { screen.extensionKind = nil }
                }
                ApplicationsFacetHeader(title: "Types")
                ForEach(screen.extensionKinds, id: \.self) { kind in
                    ApplicationsFacetRow(title: kind.title, symbol: kind.symbol,
                                         count: CountFormat.grouped(screen.extensionCount(kind)),
                                         isSelected: screen.extensionKind == kind) {
                        withAnimation(Motion.quick) { screen.extensionKind = kind }
                    }
                }
            }
            .padding(Spacing.s)
        }
        .scrollIndicators(.never)
        .prismSurface(radius: Radius.container)
    }
}

// MARK: - List

/// A titled block of extensions (one kind, or one category of app extensions).
struct ApplicationsExtensionSection: Identifiable {
    var id: String
    var title: String
    var items: [ApplicationsExtensionInfo]
}

struct ApplicationsExtensionListPane: View {
    @Bindable var screen: ApplicationsScreenModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let sections = self.sections
        VStack(alignment: .leading, spacing: 0) {
            header(ink)
            ApplicationsHairline()
            if showsLegacyQuickLookNote {
                ApplicationsBanner(symbol: "info.circle",
                                   text: "This version of macOS no longer loads legacy Quick Look generators. They can't preview anything and are safe to remove.")
                    .padding(Spacing.s)
            }
            if sections.isEmpty {
                VStack(spacing: Spacing.s) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(ink.tertiary)
                    Text(screen.extensionSearch.isEmpty ? "Nothing of this type." : "No matches for \u{201C}\(screen.extensionSearch)\u{201D}.")
                        .font(SpruceFont.body)
                        .foregroundStyle(ink.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            Text(section.title.uppercased())
                                .font(SpruceFont.overline)
                                .tracking(0.8)
                                .foregroundStyle(ink.tertiary)
                                .padding(.horizontal, Spacing.m)
                                .padding(.top, Spacing.m)
                                .padding(.bottom, Spacing.xs)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.items) { ext in
                                ApplicationsExtensionRow(ext: ext, isBusy: screen.busyExtensionIDs.contains(ext.id),
                                                         onToggle: { screen.setExtension(ext, enabled: $0) },
                                                         onRemove: { screen.requestExtensionRemoval(ext) },
                                                         onReveal: { screen.revealExtension(ext) })
                                ApplicationsHairline(leading: 56)
                            }
                        }
                    }
                    .padding(.bottom, Spacing.s)
                }
            }
        }
        .prismSurface(radius: Radius.container)
    }

    private func header(_ ink: PrismInk) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            PrismCategoryBadge(symbol: screen.extensionKind?.symbol ?? "puzzlepiece.extension", module: .applications, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(screen.extensionKind?.title ?? "All Extensions")
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                Text(screen.extensionKind?.detail
                     ?? "Add-ons from other developers. Turning an app extension off is reversible; plug-in files can be moved to the Trash.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.l)
    }

    private var showsLegacyQuickLookNote: Bool {
        guard screen.extensionKind == .quickLook else { return false }
        if #available(macOS 15, *) { return true }
        return false
    }

    /// App extensions by category; plug-in files by kind.
    private var sections: [ApplicationsExtensionSection] {
        let items = screen.visibleExtensions
        var result: [ApplicationsExtensionSection] = []
        let appExtensions = items.filter { $0.kind == .appExtension }
        let categories = Set(appExtensions.map { $0.category ?? "Other" })
            .sorted { lhs, rhs in
                if lhs == "Other" { return false }
                if rhs == "Other" { return true }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        for category in categories {
            let members = appExtensions.filter { ($0.category ?? "Other") == category }
            result.append(ApplicationsExtensionSection(id: "category:" + category,
                                                       title: category == "Other" ? "Other App Extensions" : category,
                                                       items: members))
        }
        for kind in ApplicationsExtensionKind.allCases where kind != .appExtension {
            let members = items.filter { $0.kind == kind }
            if !members.isEmpty {
                result.append(ApplicationsExtensionSection(id: "kind:" + kind.rawValue, title: kind.title, items: members))
            }
        }
        return result
    }
}

/// One extension or plug-in.
struct ApplicationsExtensionRow: View {
    var ext: ApplicationsExtensionInfo
    var isBusy: Bool
    var onToggle: (Bool) -> Void
    var onRemove: () -> Void
    var onReveal: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        HStack(spacing: Spacing.m) {
            ItemIcon(url: iconURL, symbol: ext.kind.symbol, size: 28, module: .applications)
                .opacity(ext.isEnabled == false ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ext.name)
                        .font(SpruceFont.body.weight(.medium))
                        .foregroundStyle(ext.isEnabled == false ? ink.secondary : Ink.primary)
                        .lineLimit(1)
                    if !ext.isUserDomain {
                        PrismChip(text: "All users", color: StatusColor.info, symbol: "person.2")
                    }
                }
                Text(secondaryLine)
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.s)
            if hovering && (ext.path != nil || ext.hostAppPath != nil) {
                PrismIconButton(symbol: "magnifyingglass", help: "Reveal in Finder", action: onReveal)
                    .transition(.opacity)
            }
            trailing
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 7)
        .frame(minHeight: 46)
        .background(Rectangle().fill(hovering ? ink.subtleFill : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu {
            if ext.path != nil || ext.hostAppPath != nil {
                Button("Reveal in Finder", action: onReveal)
            }
            if let identifier = ext.identifier {
                Button("Copy Identifier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(identifier, forType: .string)
                }
            }
            if ext.canRemove {
                Divider()
                Button("Move to Trash…", action: onRemove)
            }
        }
        .help(helpText)
    }

    @ViewBuilder
    private var trailing: some View {
        if isBusy {
            ProgressView().controlSize(.small).frame(width: 40)
        } else if ext.canToggle {
            Toggle(isOn: Binding(get: { ext.isEnabled ?? true }, set: { onToggle($0) })) {
                Text(ext.isEnabled == false ? "Off" : "On")
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(ModuleID.applications.palette.accent)
            .accessibilityLabel("\(ext.name) enabled")
        } else if ext.canRemove {
            CapsuleButton(title: "Remove…", symbol: "trash", action: onRemove)
        } else if ext.kind == .appExtension {
            Text("Managed by its app")
                .font(SpruceFont.caption)
                .foregroundStyle(PrismInk(contrast).tertiary)
        }
    }

    private var iconURL: URL? {
        if let host = ext.hostAppPath { return URL(fileURLWithPath: host) }
        if let path = ext.path { return URL(fileURLWithPath: path) }
        return nil
    }

    private var secondaryLine: String {
        var parts: [String] = []
        if ext.kind == .appExtension {
            if let host = ext.hostAppName { parts.append("From \(host)") }
            if let category = ext.category, category != "Other" { parts.append(category) }
        } else if let path = ext.path {
            parts.append((path as NSString).deletingLastPathComponent.abbreviatingHome)
        }
        if let version = ext.version, !version.isEmpty { parts.append("v\(version)") }
        if parts.isEmpty, let identifier = ext.identifier { parts.append(identifier) }
        return parts.joined(separator: " · ")
    }

    private var helpText: String {
        var parts: [String] = [ext.kind.title]
        if let identifier = ext.identifier { parts.append(identifier) }
        if let path = ext.path { parts.append(path.abbreviatingHome) }
        return parts.joined(separator: "\n")
    }
}
