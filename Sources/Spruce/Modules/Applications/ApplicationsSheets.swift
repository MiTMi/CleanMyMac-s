import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Uninstall / reset confirmation

/// Confirms an Uninstall, Reset or Remove before anything moves to the Trash.
struct ApplicationsUninstallSheet: View {
    var request: ApplicationsUninstallRequest
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        PrismSheetCard(title: title, message: message, primaryTitle: primaryTitle,
                       primaryRole: request.removesApps ? .destructive : .primary,
                       onCancel: onCancel, onPrimary: onConfirm) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                appList
                if !request.openApps.isEmpty {
                    note(symbol: "circle.fill", tint: StatusColor.success,
                         text: request.openApps.count == 1
                            ? "\(request.openApps[0].name) is open. It's asked to quit first, so it can save your work."
                            : "\(request.openApps.map(\.name).joined(separator: ", ")) are open. They're asked to quit first, so they can save your work.")
                }
                let vendorApps = request.apps.filter(\.prefersVendorUninstaller)
                if !vendorApps.isEmpty && request.removesApps {
                    note(symbol: "exclamationmark.shield", tint: StatusColor.warning,
                         text: "\(vendorApps.map(\.name).joined(separator: ", ")) \(vendorApps.count == 1 ? "has" : "have") a dedicated uninstaller from the developer, which removes system components more cleanly.")
                }
                if request.items?.contains(where: { $0.metadata[ApplicationsMeta.systemDomain] == "1" }) == true {
                    note(symbol: "lock", tint: ModuleID.applications.palette.accentText,
                         text: "Some selected files are shared by all users. macOS asks for your administrator password to move them.")
                }
            }
        }
    }

    @ViewBuilder
    private var appList: some View {
        let ink = PrismInk(contrast)
        let shown = Array(request.apps.prefix(6))
        VStack(alignment: .leading, spacing: 6) {
            ForEach(shown) { app in
                HStack(spacing: Spacing.s) {
                    ItemIcon(url: app.url, symbol: "app", size: 26, module: .applications)
                    Text(app.name)
                        .font(SpruceFont.bodyStrong)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Spacer()
                    if app.size > 0 && request.removesApps {
                        Text(ByteFormat.string(app.size))
                            .font(SpruceFont.captionDigits)
                            .foregroundStyle(ink.tertiary)
                    }
                }
            }
            if request.apps.count > shown.count {
                Text("and \(request.apps.count - shown.count) more")
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
            }
        }
        .padding(Spacing.m)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Ink.subtleFill))
    }

    private func note(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(SpruceFont.callout)
                .foregroundStyle(PrismInk(contrast).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appName: String { request.apps.first?.name ?? "this app" }

    private var title: String {
        if request.items == nil {
            return request.apps.count == 1 ? "Uninstall \u{201C}\(appName)\u{201D}?" : "Uninstall \(request.apps.count) apps?"
        }
        if request.removesApps { return "Uninstall \u{201C}\(appName)\u{201D}?" }
        if request.isReset { return "Reset \u{201C}\(appName)\u{201D}?" }
        return "Remove \(CountFormat.items(request.items?.count ?? 0)) of \(appName)?"
    }

    private var message: String {
        guard let items = request.items else {
            return "The apps and the files that clearly belong to them move to the Trash, where you can put them back. Files that other apps might use stay where they are."
        }
        let size = ByteFormat.string(items.reduce(Int64(0)) { $0 + $1.size })
        if request.removesApps {
            let files = items.count - 1
            return files > 0
                ? "The app and \(CountFormat.items(files, singular: "related item")) (\(size) in total) move to the Trash, where you can put them back."
                : "The app (\(size)) moves to the Trash, where you can put it back."
        }
        if request.isReset {
            return "Its settings, caches and data (\(CountFormat.items(items.count)), \(size)) move to the Trash. The app stays installed and starts like new — you may need to sign in again."
        }
        return "The selected items (\(size)) move to the Trash. The app stays installed."
    }

    private var primaryTitle: String {
        if request.removesApps { return "Uninstall" }
        return request.isReset ? "Reset" : "Move to Trash"
    }
}

// MARK: - Quit before updating

/// "These apps are open" before Homebrew updates them.
struct ApplicationsUpdateQuitSheet: View {
    var prompt: ApplicationsUpdateQuitPrompt
    var onQuit: () -> Void
    var onSkip: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let names = prompt.openApps.map(\.name)
        PrismSheetCard(title: names.count == 1 ? "Quit \(names[0]) first?" : "Quit these apps first?",
                       message: "Apps are replaced while they update. They're asked to quit normally, so they can offer to save your work.",
                       primaryTitle: "Quit and Update", onCancel: onCancel, onPrimary: onQuit) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(prompt.openApps) { app in
                    HStack(spacing: Spacing.s) {
                        ItemIcon(url: app.url, symbol: "app", size: 26, module: .applications)
                        Text(app.name)
                            .font(SpruceFont.bodyStrong)
                            .foregroundStyle(Ink.primary)
                        Spacer()
                        Text("Open now")
                            .font(SpruceFont.caption)
                            .foregroundStyle(PrismInk(contrast).tertiary)
                    }
                }
                if prompt.updates.count > prompt.openApps.count {
                    PrismTextButton(title: "Update only the apps that are closed", symbol: "forward.end",
                                    module: .applications, action: onSkip)
                        .padding(.top, Spacing.xs)
                }
            }
        }
    }
}

// MARK: - Remove plug-in

struct ApplicationsExtensionRemovalSheet: View {
    var ext: ApplicationsExtensionInfo
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        PrismSheetCard(title: "Move \u{201C}\(ext.name)\u{201D} to the Trash?", message: message,
                       primaryTitle: "Move to Trash", primaryRole: .destructive,
                       onCancel: onCancel, onPrimary: onConfirm)
    }

    private var message: String {
        var text = "The \(ext.kind.title.lowercased().dropLastPlural) is removed from \(location). You can put it back from the Trash."
        if !ext.isUserDomain {
            text += " It's installed for all users, so macOS may ask for your administrator password."
        }
        if ext.kind == .preferencePane || ext.kind == .inputMethod {
            text += " Quit System Settings first if it's open."
        }
        return text
    }

    private var location: String {
        guard let path = ext.path else { return "your Mac" }
        return (path as NSString).deletingLastPathComponent.abbreviatingHome
    }
}

private extension String {
    /// "quick look plug-ins" → "quick look plug-in".
    var dropLastPlural: String {
        hasSuffix("s") ? String(dropLast()) : self
    }
}
