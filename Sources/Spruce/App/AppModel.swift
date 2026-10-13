import AppKit
import Foundation
import Observation
import SpruceCore
import SpruceMac
import SwiftUI

/// App-wide state: navigation, shared stores, and the module engines.
///
/// CONTRACT: module views read engines and stores from here via
/// `@Environment(AppModel.self)`. Engines are created once and live for the app's
/// lifetime, so scan results survive navigation.
@MainActor
@Observable
final class AppModel {
    /// The app's single model (also reachable from AppKit callbacks such as notifications).
    static let shared = AppModel()

    var selection: ModuleID = .checkup
    /// Set by any view to request navigation to a module and (optionally) a sub-tool.
    var pendingTool: String?
    /// Files handed to Spruce from Finder (Services menu, a drop on the Dock icon, Open
    /// With). `openFiles(_:)` navigates to the module that handles them; that module takes
    /// them with `takePendingFiles(for:)` (which sets this back to `[]`) and shows them —
    /// never acts on them. See `FileDestination`.
    var pendingFiles: [URL] = []
    /// The module `pendingFiles` are meant for (set with them by `openFiles`).
    private(set) var pendingFilesModule: ModuleID?
    /// The in-app Notification Center popover (bell in the sidebar, ⇧⌘N).
    var showsInbox = false
    /// The page the Help window shows.
    var helpPage: HelpPage = .gettingStarted

    let settings = SettingsStore.shared
    let history = HistoryStore.shared
    let monitor = SystemMonitor.shared
    let inbox = InboxStore.shared

    let cleanup = CleanupEngine()
    let protection = ProtectionEngine()
    let performance = PerformanceEngine()
    let applications = ApplicationsEngine()
    let clutter = ClutterEngine()
    let spaceMap = SpaceMapEngine()
    let cloudStorage = CloudStorageEngine()

    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess

    /// SwiftUI's window opener, captured from the menu commands and the main window so
    /// AppKit callbacks (notification clicks, Dock menu, Finder Services) can bring the
    /// main window back after it was closed.
    @ObservationIgnored private var windowOpener: OpenWindowAction?

    init() {}

    /// Every engine that can contribute to Checkup, in tile order. Checkup itself applies
    /// `settings.checkupModules` (it needs the full list for "Include" / "Try Again").
    var checkupContributors: [CheckupContributor] {
        [cleanup, protection, performance, applications, clutter]
    }

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }

    /// Navigate to a module, optionally opening one of its tools.
    func open(_ module: ModuleID, tool: String? = nil) {
        selection = module
        pendingTool = tool
    }

    // MARK: Main window

    func registerWindowOpener(_ opener: OpenWindowAction) {
        windowOpener = opener
    }

    /// Brings the main window to the front, reopening it when it was closed.
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let windowOpener {
            // For a single `Window` scene this reopens it, or brings it forward when open.
            windowOpener(id: "main")
        } else {
            NSApp.windows.first { $0.canBecomeMain && $0.title == "Spruce" }?.makeKeyAndOrderFront(nil)
        }
    }

    /// Opens the Help window on `page`.
    func showHelp(_ page: HelpPage) {
        helpPage = page
        NSApp.activate(ignoringOtherApps: true)
        windowOpener?(id: "help")
    }

    // MARK: Mac Health

    /// The single Mac Health score. The sidebar pill reads it; Activity's gauge and the
    /// menu bar should read it too, so every surface shows the same number.
    var healthReport: ActivityHealthReport {
        ActivityHealth.assess(healthInput())
    }

    func healthInput(now: Date = Date()) -> ActivityHealthInput {
        let prefs = self.settings.settings
        // The monitor's own assessment is the system part of the score.
        let live: [ActivitySystemIssue]? = monitor.health.isRated
            ? monitor.health.issues.map { issue in
                ActivitySystemIssue(kind: issue.kind.rawValue, isCritical: issue.severity == .critical,
                                    title: issue.title, detail: issue.detail, penalty: issue.penalty)
            }
            : nil
        let snapshot: SystemSnapshot? = (live == nil && monitor.hasSample) ? monitor.snapshot : nil
        return ActivityHealthInput(snapshot: snapshot, liveIssues: live, history: history.history,
                                   hasFullDiskAccess: hasFullDiskAccess,
                                   realtimeProtectionEnabled: prefs.realtimeProtection,
                                   lowDiskThresholdPercent: prefs.lowDiskThresholdPercent, now: now)
    }

    // MARK: Files and links from outside

    /// Where a file handed to Spruce from Finder is shown.
    struct FileDestination: Equatable {
        var module: ModuleID
        /// The tool that shows the files (nil: the module's own screen).
        var tool: String?

        static let uninstaller = FileDestination(module: .applications, tool: "applications.uninstaller")
        static let installers = FileDestination(module: .applications, tool: "applications.installers")
        static let spaceMap = FileDestination(module: .spaceMap, tool: "spaceMap")
        static let shredder = FileDestination(module: .toolbox, tool: "toolbox.shredder")
        /// Folders added to the places Clutter scans ("Find Clutter with Spruce"); only an
        /// explicit destination, never picked by `of(_:)`.
        static let clutter = FileDestination(module: .clutter, tool: nil)

        /// `.app` → Uninstaller, `.pkg`/`.mpkg` → Installers, folder → Space Map,
        /// anything else → Shredder (staged, unchecked).
        static func of(_ url: URL) -> FileDestination {
            let ext = url.pathExtension.lowercased()
            if ext == "app" { return .uninstaller }
            if ext == "pkg" || ext == "mpkg" { return .installers }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return .spaceMap
            }
            return .shredder
        }
    }

    /// Shows files from Finder in the module that handles them. Never starts anything:
    /// the module only lists them (unchecked) for the user to review.
    func openFiles(_ urls: [URL], as destination: FileDestination? = nil) {
        var files = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard let first = files.first else { return }
        let target = destination ?? FileDestination.of(first)
        files = files.filter { destination != nil || FileDestination.of($0) == target }
        if target == .uninstaller {
            let refused = files.filter(Self.isSystemApp)
            files.removeAll(where: Self.isSystemApp)
            if !refused.isEmpty {
                Notifier.keep(kind: .tip, title: "Apps that come with macOS stay installed",
                              body: refused.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", ")
                                  + " can't be uninstalled; macOS restores them with every update.",
                              module: ModuleID.applications.rawValue, tool: target.tool)
            }
        }
        pendingFiles = files
        pendingFilesModule = files.isEmpty ? nil : target.module
        open(target.module, tool: target.tool)
        showMainWindow()
    }

    /// Hands the files from Finder to `module`, once: returns them and clears
    /// `pendingFiles` when they are meant for it and it is on screen; otherwise returns
    /// `[]` and leaves them for their module.
    func takePendingFiles(for module: ModuleID) -> [URL] {
        guard selection == module, !pendingFiles.isEmpty,
              pendingFilesModule == nil || pendingFilesModule == module else { return [] }
        let files = pendingFiles
        pendingFiles = []
        pendingFilesModule = nil
        return files
    }

    private static func isSystemApp(_ url: URL) -> Bool {
        let path = url.path
        if path.hasPrefix("/System/") { return true }
        return Bundle(url: url)?.bundleIdentifier?.lowercased().hasPrefix("com.apple.") ?? false
    }

    /// Handles `spruce://` links — navigation only, never an action:
    /// `spruce://open/<module>[?tool=<tool id>]`, `spruce://checkup[?autostart=1]`,
    /// `spruce://inbox`. Returns false for anything it doesn't understand.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let route = SpruceLink(url) else { return false }
        switch route {
        case .open(let module, let tool):
            open(module, tool: tool)
        case .inbox:
            showsInbox = true
        }
        showMainWindow()
        return true
    }
}

/// A parsed `spruce://` link.
enum SpruceLink: Equatable {
    case open(ModuleID, tool: String?)
    case inbox

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "spruce" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") },
                               uniquingKeysWith: { first, _ in first })
        let host = (url.host ?? "").lowercased()
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "open", "modules":
            guard let name = path.first, let module = Self.module(named: name) else { return nil }
            self = .open(module, tool: Self.tool(query["tool"], for: module))
        case "checkup":
            self = .open(.checkup, tool: query["autostart"] == "1" ? "checkup.scan" : nil)
        case "inbox", "notifications":
            self = .inbox
        default:
            guard let module = Self.module(named: host) else { return nil }
            self = .open(module, tool: Self.tool(query["tool"], for: module))
        }
    }

    private static func module(named name: String) -> ModuleID? {
        let key = name.lowercased().replacingOccurrences(of: "-", with: "")
        return ModuleID.allCases.first {
            $0.rawValue.lowercased() == key || $0.title.lowercased().replacingOccurrences(of: " ", with: "") == key
        }
    }

    /// Only tool ids that belong to `module` (see ARCHITECTURE › Navigation & tool identifiers).
    private static func tool(_ raw: String?, for module: ModuleID) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= 64,
              raw.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "." }) else { return nil }
        if raw == module.rawValue || raw.hasPrefix(module.rawValue + ".") { return raw }
        return nil
    }
}
