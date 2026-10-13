import SpruceCore
import SpruceMac
import SwiftUI

/// Confirms Free Up Locally: how much space comes back, from which providers, and
/// exactly what happens to the files.
struct CloudStorageConfirmSheet: View {
    let screen: CloudStorageScreenModel

    var body: some View {
        let groups = screen.selectionByProvider
        let count = groups.reduce(0) { $0 + $1.count }
        let bytes = groups.reduce(Int64(0)) { $0 + $1.bytes }
        PrismSheetCard(
            title: "Free up \(ByteFormat.string(bytes)) on this Mac?",
            message: message(groups.map { $0.provider.name }),
            primaryTitle: "Free Up Locally",
            isPrimaryEnabled: count > 0,
            onCancel: { screen.cancelFreeUp() },
            onPrimary: { screen.confirmFreeUp() }
        ) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(groups) { group in
                    HStack(spacing: Spacing.s) {
                        PrismCategoryBadge(symbol: group.provider.kind.symbol, module: .cloudStorage, size: 24)
                        Text(group.provider.displayName)
                            .font(SpruceFont.body.weight(.medium))
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.s)
                        Text(CountFormat.items(group.count, singular: "file"))
                            .font(SpruceFont.captionDigits)
                            .foregroundStyle(Ink.tertiary)
                        Text(ByteFormat.string(group.bytes))
                            .font(SpruceFont.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Ink.primary)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    point("checkmark.icloud", "Nothing is deleted. The files stay in the cloud and on your other devices.")
                    point("folder", "They keep their place in Finder, shown with a cloud icon.")
                    point("arrow.down.circle", "Opening one downloads it again, which needs an internet connection.")
                }
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.subtleFill))
            }
        }
    }

    private func message(_ names: [String]) -> String {
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        let list: String
        switch unique.count {
        case 0: list = "the cloud"
        case 1: list = unique[0]
        case 2: list = "\(unique[0]) and \(unique[1])"
        default: list = unique.dropLast().joined(separator: ", ") + " and " + (unique.last ?? "")
        }
        return "Only the downloaded copies are removed from this Mac. Everything stays safely in \(list)."
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ModuleID.cloudStorage.palette.accentText)
                .frame(width: 16)
            Text(text)
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
