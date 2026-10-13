import SpruceCore
import SpruceMac
import SwiftUI

/// Pages of the local Help window (Help › Spruce Help, Keyboard Shortcuts, Permissions Guide).
enum HelpPage: Hashable, Identifiable {
    case gettingStarted
    case module(ModuleID)
    case safety
    case permissions
    case shortcuts

    var id: String {
        switch self {
        case .gettingStarted: return "start"
        case .module(let module): return "module." + module.rawValue
        case .safety: return "safety"
        case .permissions: return "permissions"
        case .shortcuts: return "shortcuts"
        }
    }

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .module(let module): return module.title
        case .safety: return "Safety & the Trash"
        case .permissions: return "Permissions"
        case .shortcuts: return "Keyboard Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: return "sparkles"
        case .module(let module): return module.palette.symbol
        case .safety: return "checkmark.shield"
        case .permissions: return "lock.open"
        case .shortcuts: return "keyboard"
        }
    }

    static var sidebar: [HelpPage] {
        [.gettingStarted] + ModuleID.allCases.map { .module($0) } + [.safety, .permissions, .shortcuts]
    }
}

/// The Help window: a short page per module plus safety, permissions and shortcuts.
struct HelpView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List(HelpPage.sidebar, selection: Binding<HelpPage?>(
                get: { model.helpPage },
                set: { if let page = $0 { model.helpPage = page } }
            )) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            ScrollView {
                HelpPageView(page: model.helpPage)
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(Spacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(hex: 0x101018))
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct HelpPageView: View {
    var page: HelpPage

    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(spacing: Spacing.m) {
                Image(systemName: page.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(accent)
                Text(page.title)
                    .font(SpruceFont.display(30))
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            switch page {
            case .shortcuts:
                ShortcutTable()
            default:
                ForEach(Array(HelpContent.paragraphs(for: page).enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(SpruceFont.body)
                        .foregroundStyle(PrismInk(contrast).secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let points = HelpContent.points(for: page)
                if !points.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(points, id: \.self) { point in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(accent)
                                Text(point)
                                    .font(SpruceFont.body)
                                    .foregroundStyle(Ink.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                actions
            }
        }
    }

    private var accent: Color {
        if case .module(let module) = page { return module.palette.accentText }
        return StatusColor.info
    }

    @ViewBuilder
    private var actions: some View {
        switch page {
        case .module(let module):
            CapsuleButton(title: "Open \(module.title)", symbol: "arrow.right.circle", prominent: true) {
                model.open(module)
                model.showMainWindow()
            }
        case .permissions:
            HStack(spacing: Spacing.s) {
                CapsuleButton(title: "Full Disk Access…", symbol: "lock.open", prominent: true) {
                    Permissions.openFullDiskAccessSettings()
                }
                CapsuleButton(title: "App Management…", symbol: "app.badge.checkmark") {
                    Permissions.openAppManagementSettings()
                }
                CapsuleButton(title: "Login Items…", symbol: "person.crop.circle.badge.checkmark") {
                    Permissions.openLoginItemsSettings()
                }
            }
        default:
            EmptyView()
        }
    }
}

/// Every keyboard shortcut in the main menu.
struct ShortcutTable: View {
    @Environment(\.colorSchemeContrast) private var contrast

    static let rows: [(keys: String, action: String)] = [
        ("⌘1 … ⌘9", "Go to Checkup … Toolbox"),
        ("⇧⌘A", "Go to Activity"),
        ("⌘R", "Scan again"),
        ("⌘.", "Stop the current scan or run"),
        ("⌘↩", "Review and run the selection (always asks first)"),
        ("⌘Y", "Quick Look the focused item"),
        ("⇧⌘R", "Reveal the focused item in Finder"),
        ("⌥⌘C", "Copy the focused item's path"),
        ("⌥⌘A", "Deselect all items"),
        ("⇧⌘N", "Show the Notification Center"),
        ("⌘,", "Settings"),
        ("⌘?", "Spruce Help"),
        ("⌘/", "This list of shortcuts"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.action)
                        .font(SpruceFont.body)
                        .foregroundStyle(Ink.primary)
                    Spacer()
                    Text(row.keys)
                        .font(SpruceFont.mono)
                        .foregroundStyle(PrismInk(contrast).secondary)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, 3)
                        .background(Ink.controlFill, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }
                .padding(.vertical, Spacing.s)
                if index < Self.rows.count - 1 {
                    Divider().overlay(Ink.hairline)
                }
            }
            Text("Nothing that deletes files has a shortcut of its own: every removal goes through its confirmation.")
                .font(SpruceFont.caption)
                .foregroundStyle(PrismInk(contrast).tertiary)
                .padding(.top, Spacing.m)
        }
    }
}

/// Short, original help copy.
enum HelpContent {
    static func paragraphs(for page: HelpPage) -> [String] {
        switch page {
        case .gettingStarted:
            return [
                "Spruce keeps your Mac tidy, safe and quick. Every tool follows the same rhythm: scan, review what was found, choose what to act on, and confirm.",
                "Start with Checkup — one scan across Cleanup, Protection, Performance, Applications and Clutter — or pick a single module in the sidebar. Nothing is removed until you confirm it.",
            ]
        case .module(let module):
            return [module.tagline] + moduleDetail(module)
        case .safety:
            return [
                "Spruce moves files to the Trash by default, so you can put them back: the completion screen's Put Back All returns a whole run while its items are still in the Trash. Only caches, logs and temporary files that rebuild themselves are deleted directly.",
                "Every path is checked again right before anything happens. System folders, other people's files, keychains, password managers and iCloud Drive are always off limits, and apps can only be removed by the Uninstaller.",
                "Items that need administrator rights ask for your password once per run. They go to a separate folder in the Trash and keep their original owner, so emptying it asks for the password again.",
                "Each file Spruce moves or removes is written to the operations log (Activity › Operations Log), and every run to your activity history.",
            ]
        case .permissions:
            return [
                "Full Disk Access lets Spruce see Mail downloads, Safari data, and other folders macOS protects. Without it, those scans skip what they can't read.",
                "App Management lets Spruce update and uninstall apps that macOS guards. Notifications let alerts and the weekly reminder reach you. Login Items is where macOS lists what Spruce helps you turn off.",
                "Spruce never sends your files anywhere. Network requests are limited to app update checks (when you open Updater; with update alerts on, also during Checkup and once a day), downloading an update you choose to install, Protection's threat list (at most once a day while it's on in Settings), and VirusTotal lookups once you add your own key, which send a file's SHA-256 fingerprint only.",
            ]
        case .shortcuts:
            return []
        }
    }

    static func points(for page: HelpPage) -> [String] {
        switch page {
        case .gettingStarted:
            return [
                "Safe items are selected for you; items to review are not.",
                "Add anything to the ignore list (right-click › Ignore) and Spruce leaves it alone in every scan.",
                "The menu bar monitor shows disk, memory and CPU at a glance, and the bell keeps alerts you missed.",
            ]
        case .module(let module):
            return modulePoints(module)
        default:
            return []
        }
    }

    private static func moduleDetail(_ module: ModuleID) -> [String] {
        switch module {
        case .checkup:
            return ["Checkup gathers the recommended actions of every module into one review. Open a tile to fine-tune what it will do before you run it."]
        case .cleanup:
            return ["Cleanup finds caches, logs, leftovers of removed apps, mail attachments and the contents of your Trash bins."]
        case .protection:
            return ["Protection looks for known malware and adware, clears browser privacy traces (the browser must be closed), and lists the apps that hold sensitive permissions."]
        case .performance:
            return ["Performance runs maintenance tasks and shows what opens at login or runs in the background, and which apps use the most resources."]
        case .applications:
            return ["Applications removes apps together with their support files, updates outdated apps, finds leftovers, installers and plug-ins."]
        case .clutter:
            return ["Clutter finds large and old files, duplicates, similar photos and an overflowing Downloads folder. Nothing is preselected except redundant duplicate copies."]
        case .spaceMap:
            return ["Space Map draws your disk as nested bubbles so you can see where the space went and move big folders to the Trash."]
        case .cloudStorage:
            return ["Cloud Storage shows which files of iCloud Drive and other providers are stored locally and frees those copies, keeping them in the cloud."]
        case .toolbox:
            return ["Toolbox gathers every individual tool: the Shredder, screen cleaning, Empty Trash, Free Up RAM and Flush DNS."]
        case .activity:
            return ["Activity shows your Mac Health score, what to do next, and a timeline of everything Spruce did."]
        }
    }

    private static func modulePoints(_ module: ModuleID) -> [String] {
        switch module {
        case .cleanup:
            return ["Data of running apps is skipped where removing it could corrupt their state.",
                    "Root-owned system caches and logs ask for your administrator password once."]
        case .protection:
            return ["Real-time protection watches common launch locations and alerts you to new threats."]
        case .applications:
            return ["Apps that come with macOS can't be uninstalled; macOS restores them with every update."]
        case .clutter:
            return ["Files go to the Trash, so you can put them back.",
                    "Drop folders on Clutter (or use Finder › Services › Find Clutter with Spruce) to add them to the places it looks in."]
        case .spaceMap:
            return ["Folders macOS manages can't be selected, nor can items owned by the system outside app, support, cache, log and temporary folders.",
                    "Drop a folder on Space Map (or use Finder › Services › Map Folder with Spruce) to map it."]
        default:
            return []
        }
    }
}
