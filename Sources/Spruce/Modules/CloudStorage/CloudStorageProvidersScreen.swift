import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Idle screen: the cloud folders found on this Mac as cards (each can be left out of
/// the scan), what the module does, and the Scan orb.
struct CloudStorageProvidersScreen: View {
    let screen: CloudStorageScreenModel

    var body: some View {
        if !screen.providersLoaded {
            ModuleIdleView(
                module: .cloudStorage,
                subtitle: "Free up space taken by downloaded copies of files that are safely stored in the cloud.",
                features: Self.features,
                actionTitle: "Scan",
                actionSubtitle: "Looking for folders…",
                isEnabled: false,
                action: {}
            )
        } else if screen.providers.isEmpty {
            ModuleIdleView(
                module: .cloudStorage,
                subtitle: "Free up space taken by downloaded copies of files that are safely stored in the cloud.",
                features: Self.features,
                actionTitle: "Scan",
                isEnabled: false,
                notice: "No cloud folders were found. Sign in to iCloud Drive in System Settings, or install your provider's Mac app (Google Drive, OneDrive, Dropbox, Box…), then check again.",
                noticeActionTitle: "Check Again",
                lensMood: .limited,
                action: {},
                onNoticeAction: { screen.refreshProviders() }
            )
        } else {
            ModuleIdleView(
                module: .cloudStorage,
                subtitle: "See how much of your cloud storage is downloaded to this Mac and free up the copies you don't need here. Nothing is deleted from the cloud.",
                actionTitle: "Scan",
                actionSubtitle: scanSubtitle,
                isEnabled: !screen.includedProviders.isEmpty,
                accessory: AnyView(CloudStorageProviderList(screen: screen)),
                action: { screen.startScan() }
            )
        }
    }

    private var scanSubtitle: String {
        let count = screen.includedProviders.count
        return count == 0 ? "Choose a folder" : CountFormat.items(count, singular: "folder")
    }

    static let features: [IdleFeature] = [
        IdleFeature(symbol: "icloud", title: "iCloud Drive and more",
                    detail: "Works with iCloud Drive and apps that use macOS cloud folders, such as Google Drive, OneDrive, Dropbox and Box."),
        IdleFeature(symbol: "internaldrive", title: "Local versus cloud",
                    detail: "Shows how much of each cloud is downloaded here and which big files take the most space."),
        IdleFeature(symbol: "arrow.down.circle.dotted", title: "Free up, not delete",
                    detail: "Removes only the downloaded copy. Files stay in the cloud and download again when you open them."),
    ]
}

/// The provider cards plus a short explanation.
struct CloudStorageProviderList: View {
    let screen: CloudStorageScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                SectionHeader(title: "Cloud folders on this Mac")
                Spacer()
                PrismIconButton(symbol: "arrow.clockwise", help: "Look for cloud folders again") {
                    screen.refreshProviders()
                }
            }
            if screen.providers.count > 4 {
                ScrollView { cards }
                    .frame(maxHeight: 300)
            } else {
                cards
            }
            Label("Spruce reads these folders locally and never signs in to your accounts.", systemImage: "lock.shield")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
                .padding(.top, Spacing.xxs)
        }
    }

    private var cards: some View {
        VStack(spacing: Spacing.s) {
            ForEach(screen.providers) { provider in
                CloudStorageProviderCard(provider: provider, isIncluded: screen.isIncluded(provider),
                                         onToggle: { screen.toggleProvider(provider) })
            }
        }
    }
}

/// One provider: symbol badge, name, account, location and how it stores files.
struct CloudStorageProviderCard: View {
    let provider: CloudStorageProvider
    let isIncluded: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        let palette = ModuleID.cloudStorage.palette
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: Spacing.m) {
                PrismCategoryBadge(symbol: provider.kind.symbol, module: .cloudStorage, size: 32, isDimmed: !isIncluded)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(provider.name)
                            .font(SpruceFont.bodyStrong)
                            .foregroundStyle(Ink.primary)
                        if let account = provider.account {
                            Text(account)
                                .font(SpruceFont.caption)
                                .foregroundStyle(Ink.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if provider.mechanism == .syncFolder {
                            PrismChip(text: "Sync folder", color: StatusColor.warning)
                        }
                    }
                    Text(provider.locationLine)
                        .font(SpruceFont.caption.monospacedDigit())
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(provider.mechanism.explanation)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.xs)
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isIncluded ? palette.accentText : Ink.tertiary)
            }
            .padding(Spacing.m)
            .prismSurface(radius: Radius.row, highlighted: hovering, selected: isIncluded, selectionColor: palette.accent.opacity(0.7))
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(PrismPressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help(isIncluded ? "Included in the scan — click to leave it out" : "Left out of the scan — click to include it")
        .accessibilityLabel("\(provider.displayName), \(isIncluded ? "included" : "not included")")
        .accessibilityAddTraits(isIncluded ? .isSelected : [])
    }
}
