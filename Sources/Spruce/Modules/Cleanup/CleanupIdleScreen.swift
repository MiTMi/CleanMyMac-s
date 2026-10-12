import SpruceCore
import SpruceMac
import SwiftUI

/// Cleanup's intro: what it does, the Full Disk Access notice and the Scan orb.
struct CleanupIdleScreen: View {
    @Environment(AppModel.self) private var model
    @Bindable var screen: CleanupScreenModel

    private static let features: [IdleFeature] = [
        IdleFeature(symbol: CleanupSection.systemJunk.symbol, title: "System Junk",
                    detail: "Caches, logs, build data and broken leftovers that apps and macOS rebuild."),
        IdleFeature(symbol: CleanupSection.mailAttachments.symbol, title: "Mail Attachments",
                    detail: "Local copies Mail can download again whenever you open the message."),
        IdleFeature(symbol: CleanupSection.trashBins.symbol, title: "Trash Bins",
                    detail: "The Trash of your Mac and of connected drives, emptied for good."),
    ]

    var body: some View {
        ModuleIdleView(
            module: .cleanup,
            title: "Cleanup",
            subtitle: "Clear out files your Mac and your apps can rebuild on their own. Your documents are never touched.",
            features: Self.features,
            actionTitle: "Scan",
            notice: model.hasFullDiskAccess
                ? nil
                : "Without Full Disk Access, Mail attachments, the Trash and iOS backups can't be checked.",
            noticeActionTitle: model.hasFullDiskAccess ? nil : "Grant Full Disk Access",
            accessory: lastRunAccessory,
            action: { screen.startScan() },
            onNoticeAction: { Permissions.openFullDiskAccessSettings() }
        )
        .onAppear { model.refreshPermissions() }
    }

    private var lastRunAccessory: AnyView? {
        let entries = model.history.history.entries.filter { $0.module == .cleanup && $0.kind == .clean }
        guard let last = entries.max(by: { $0.date < $1.date }) else { return nil }
        let freed = last.bytes > 0 ? " · \(ByteFormat.string(last.bytes)) freed" : ""
        return AnyView(
            Label("Last cleaned \(DurationFormat.relative(last.date))\(freed)", systemImage: "clock.arrow.circlepath")
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.secondary)
        )
    }
}
