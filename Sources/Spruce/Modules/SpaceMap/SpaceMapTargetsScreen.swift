import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Idle screen: pick the startup disk, the home folder, another disk or any folder,
/// each shown as a card with its capacity bar, then Scan.
struct SpaceMapTargetsScreen: View {
    let screen: SpaceMapScreenModel
    var hasFullDiskAccess: Bool

    var body: some View {
        ModuleIdleView(
            module: .spaceMap,
            subtitle: "Map what fills a disk or folder, zoom into the biggest bubbles and move what you don't need to the Trash.",
            actionTitle: "Scan",
            actionSubtitle: screen.selectedTarget?.title,
            isEnabled: screen.canStartScan,
            notice: hasFullDiskAccess ? nil
                : "Without Full Disk Access some folders can't be measured; their space is shown as System & snapshots.",
            noticeActionTitle: "Grant Access",
            accessory: AnyView(SpaceMapTargetList(screen: screen)),
            action: { screen.startScan() },
            onNoticeAction: { Permissions.openFullDiskAccessSettings() }
        )
    }
}

/// The location cards plus "Choose Folder…".
struct SpaceMapTargetList: View {
    let screen: SpaceMapScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Location")
            if screen.targets.count > 4 {
                ScrollView {
                    cards
                }
                .frame(maxHeight: 290)
            } else {
                cards
            }
            chooseFolderButton
        }
    }

    private var cards: some View {
        VStack(spacing: Spacing.s) {
            ForEach(screen.targets) { target in
                SpaceMapTargetCard(target: target, isSelected: screen.selectedTargetID == target.id,
                                   onSelect: { screen.select(target) },
                                   onScan: {
                                       screen.select(target)
                                       screen.startScan()
                                   })
            }
        }
    }

    private var chooseFolderButton: some View {
        Button {
            screen.chooseFolder()
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ModuleID.spaceMap.palette.accentText)
                    .frame(width: 30, height: 30)
                Text("Choose Folder…")
                    .font(SpruceFont.bodyStrong)
                    .foregroundStyle(Ink.primary)
                Spacer()
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismPressStyle())
        .help("Map any folder or disk")
    }
}

/// One location: icon, name, usage line and capacity bar.
struct SpaceMapTargetCard: View {
    let target: SpaceMapTarget
    let isSelected: Bool
    let onSelect: () -> Void
    let onScan: () -> Void

    @State private var hovering = false

    var body: some View {
        let palette = ModuleID.spaceMap.palette
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: Spacing.s) {
                    ItemIcon(url: URL(fileURLWithPath: target.path), symbol: target.symbol, size: 30, module: .spaceMap)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(target.title)
                            .font(SpruceFont.bodyStrong)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                        Text(target.subtitle)
                            .font(SpruceFont.caption.monospacedDigit())
                            .foregroundStyle(Ink.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: Spacing.xs)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? palette.accentText : Ink.tertiary)
                }
                if let volume = target.volume {
                    if target.coversWholeVolume {
                        SpaceMapCapacityBar(volume: volume, height: 6)
                        Text(volumeLine(volume))
                            .font(SpruceFont.caption.monospacedDigit())
                            .foregroundStyle(Ink.secondary)
                    } else {
                        Text("On \(volume.name) · \(ByteFormat.string(volume.availableIncludingPurgeable)) available")
                            .font(SpruceFont.caption.monospacedDigit())
                            .foregroundStyle(Ink.secondary)
                    }
                }
            }
            .padding(Spacing.m)
            .prismSurface(radius: Radius.row, highlighted: hovering, selected: isSelected, selectionColor: palette.accent)
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(PrismPressStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { onScan() })
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityLabel("\(target.title), \(target.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func volumeLine(_ volume: SpaceMapVolumeInfo) -> String {
        var line = "\(ByteFormat.string(volume.availableIncludingPurgeable)) available"
        if volume.purgeable > 0 {
            line += " · \(ByteFormat.string(volume.purgeable)) purgeable"
        }
        return line
    }
}
