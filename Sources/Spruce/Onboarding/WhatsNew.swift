import AppKit
import Foundation
import SpruceCore
import SpruceMac
import SwiftUI

// "What's New": a short sheet shown once after Spruce is updated to a version with
// release notes (never on first launch, where the welcome guide runs instead), and on
// demand from Settings › About or Help › What's New.
//
// Wiring for the main window (owned by the app shell):
//   RootView:  `.whatsNewOnUpdate()`  (shows it once after an update, and on request)
//   Help menu: `Button("What's New") { WhatsNewTracker.requestShow() }`

// MARK: - Release notes

/// Where a What's New item leads.
enum WhatsNewLink: Hashable, Sendable {
    /// A module, optionally one of its tools (tool ids from docs/ARCHITECTURE.md).
    case module(ModuleID, tool: String?)
    /// A tab of the Settings window.
    case settings(SettingsTab)
    /// The in-app Notification Center.
    case inbox
}

struct WhatsNewItem: Identifiable, Hashable, Sendable {
    var symbol: String
    /// Palette of the item's badge.
    var module: ModuleID
    var title: String
    var detail: String
    var link: WhatsNewLink? = nil
    var linkTitle: String = "Show Me"

    var id: String { title }
}

struct WhatsNewRelease: Identifiable, Hashable, Sendable {
    /// `CFBundleShortVersionString` these notes belong to.
    var version: String
    var headline: String
    var items: [WhatsNewItem]

    var id: String { version }
}

/// Release notes bundled with the app. Add an entry (3–5 items) for each version whose
/// changes people should hear about; a version without one updates silently.
enum WhatsNewCatalog {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "1.0.0",
            headline: "Reminders on your schedule, scans that run on their own, and tidier app removal.",
            items: [
                WhatsNewItem(symbol: "calendar.badge.clock", module: .checkup,
                             title: "Checkup reminders, your way",
                             detail: "Every 3 days, weekly, every 2 weeks or monthly, at the time you pick. Running a Checkup yourself pushes the next reminder back.",
                             link: .settings(.notifications), linkTitle: "Choose"),
                WhatsNewItem(symbol: "clock.arrow.circlepath", module: .protection,
                             title: "Automatic malware scans",
                             detail: "A Quick scan runs daily or weekly while Spruce is open. Anything it finds waits for your review.",
                             link: .settings(.protection), linkTitle: "Set Up"),
                WhatsNewItem(symbol: "arrow.down.app", module: .applications,
                             title: "Update alerts",
                             detail: "Spruce looks for newer versions of your apps once a day and tells you when new ones arrive.",
                             link: .module(.applications, tool: "applications.updater"), linkTitle: "Open Updater"),
                WhatsNewItem(symbol: "trash.square", module: .applications,
                             title: "Finish removing apps from the Trash",
                             detail: "Drag an app to the Trash and Spruce offers to clear the files it left behind, after you review them.",
                             link: .module(.applications, tool: "applications.leftovers"), linkTitle: "Open Leftovers"),
                WhatsNewItem(symbol: "bell.badge", module: .performance,
                             title: "Notification Center",
                             detail: "Alerts, reminders and finished runs stay in the bell in the sidebar (⇧⌘N), so nothing slips by.",
                             link: .inbox, linkTitle: "Open"),
            ]
        ),
    ]

    /// Notes for `version`, or the newest notes when the version is unknown or has none
    /// of its own (development builds, small fix releases).
    static func release(for version: String?) -> WhatsNewRelease? {
        if let version, let exact = releases.first(where: { ApplicationsVersion.compare($0.version, version) == .orderedSame }) {
            return exact
        }
        let eligible = version.map { current in
            releases.filter { ApplicationsVersion.compare($0.version, current) != .orderedDescending }
        } ?? releases
        return newest(in: eligible.isEmpty ? releases : eligible)
    }

    static func newest(in releases: [WhatsNewRelease]) -> WhatsNewRelease? {
        releases.max { ApplicationsVersion.compare($0.version, $1.version) == .orderedAscending }
    }
}

// MARK: - When to show it

/// Decides when What's New appears: once after an update to a version with notes.
enum WhatsNewTracker {
    /// `UserDefaults` key: the last version whose notes were shown (or skipped).
    static let lastSeenKey = "app.spruce.whatsNew.lastSeenVersion"
    /// Posted (main thread) to show What's New in the main window.
    static let showRequest = Notification.Name("app.spruce.whatsNew.show")

    /// The running version (nil for `swift run` builds without an Info.plist).
    static var currentVersion: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var lastSeenVersion: String? {
        get { UserDefaults.standard.string(forKey: lastSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSeenKey) }
    }

    /// The notes to show after an update, or nil.
    ///
    /// Nothing while onboarding hasn't been completed (first launch), when the version
    /// is unknown, or when this version (or a newer one) was already seen. Otherwise the
    /// newest notes for a version after the one last seen, up to the running one. People
    /// updating from a build without What's New (`lastSeen == nil`) see the running
    /// version's notes.
    static func release(toShowFor current: String?, lastSeen: String?, hasCompletedOnboarding: Bool,
                        catalog: [WhatsNewRelease] = WhatsNewCatalog.releases) -> WhatsNewRelease? {
        guard hasCompletedOnboarding, let current else { return nil }
        if let lastSeen, ApplicationsVersion.compare(lastSeen, current) != .orderedAscending { return nil }
        let candidates = catalog.filter { release in
            guard ApplicationsVersion.compare(release.version, current) != .orderedDescending else { return false }
            guard let lastSeen else { return true }
            return ApplicationsVersion.compare(release.version, lastSeen) == .orderedDescending
        }
        return WhatsNewCatalog.newest(in: candidates)
    }

    static func pendingRelease(hasCompletedOnboarding: Bool) -> WhatsNewRelease? {
        release(toShowFor: currentVersion, lastSeen: lastSeenVersion, hasCompletedOnboarding: hasCompletedOnboarding)
    }

    /// Remembers that the running version's notes were shown, or covered by onboarding.
    /// Never moves backwards (running an older build doesn't replay newer notes later).
    static func markCurrentVersionSeen() {
        guard let currentVersion else { return }
        if let lastSeenVersion, ApplicationsVersion.compare(lastSeenVersion, currentVersion) != .orderedAscending { return }
        lastSeenVersion = currentVersion
    }

    /// Asks the main window to show What's New (Help › What's New).
    static func requestShow() {
        NotificationCenter.default.post(name: showRequest, object: nil)
    }
}

// MARK: - Presenting in the main window

extension View {
    /// Shows What's New once after Spruce was updated, and whenever
    /// `WhatsNewTracker.requestShow()` is called. Apply to the main window's root view.
    func whatsNewOnUpdate() -> some View {
        modifier(WhatsNewPresenter())
    }
}

struct WhatsNewPresenter: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var release: WhatsNewRelease?

    func body(content: Content) -> some View {
        content
            .task { await checkAfterUpdate() }
            .onReceive(NotificationCenter.default.publisher(for: WhatsNewTracker.showRequest)) { _ in
                release = WhatsNewCatalog.release(for: WhatsNewTracker.currentVersion)
            }
            .sheet(item: $release) { shown in
                WhatsNewView(release: shown) { release = nil }
                    .environment(model)
            }
    }

    @MainActor
    private func checkAfterUpdate() async {
        // On first launch the welcome guide finishes by marking this version as seen.
        guard model.settings.settings.hasCompletedOnboarding else { return }
        guard let pending = WhatsNewTracker.pendingRelease(hasCompletedOnboarding: true) else {
            // Same version, or an update without notes of its own.
            WhatsNewTracker.markCurrentVersionSeen()
            return
        }
        // Let the window settle before the sheet slides in.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        WhatsNewTracker.markCurrentVersionSeen()
        if release == nil { release = pending }
    }
}

// MARK: - Sheet

/// The What's New sheet: a few highlights, each with a link to try it.
struct WhatsNewView: View {
    var release: WhatsNewRelease
    var onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            OnboardingBackdrop(module: .checkup)
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.m)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(release.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Divider().opacity(0.5).padding(.leading, 56)
                            }
                            WhatsNewRow(item: item) { follow(item) }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    .prismSurface(radius: Radius.container)
                    .padding(.horizontal, Spacing.xl)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.l)
            }
        }
        .frame(width: 580, height: 520)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            HeroLens(module: .checkup, size: 54, glyph: "sparkles", parallax: false)
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("What's New in Spruce \(Self.shortVersion(release.version))")
                    .font(SpruceFont.title)
                    .foregroundStyle(Ink.primary)
                Text(release.headline)
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var footer: some View {
        HStack {
            Text("Nothing changes on your Mac until you choose it.")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
            Spacer()
            Button("Continue", action: onClose)
                .buttonStyle(PrismCapsuleButtonStyle(role: .primary, large: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Opens what the item is about, then closes the sheet. Navigation only.
    private func follow(_ item: WhatsNewItem) {
        guard let link = item.link else { return }
        switch link {
        case .module(let module, let tool):
            model.open(module, tool: tool)
            model.showMainWindow()
        case .settings(let tab):
            UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
            openSettings()
        case .inbox:
            model.showMainWindow()
            model.showsInbox = true
        }
        onClose()
    }

    /// "1.0" for "1.0.0" (trailing ".0" patch dropped).
    static func shortVersion(_ version: String) -> String {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 3, parts[2] == "0" { return parts[0...1].joined(separator: ".") }
        return version
    }
}

private struct WhatsNewRow: View {
    var item: WhatsNewItem
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            PrismCategoryBadge(symbol: item.symbol, module: item.module, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                Text(item.detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s)
            if item.link != nil {
                PrismTextButton(title: item.linkTitle, symbol: "arrow.right", module: item.module, action: action)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s + 2)
        .accessibilityElement(children: .contain)
    }
}
