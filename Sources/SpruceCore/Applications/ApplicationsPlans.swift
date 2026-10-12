import Foundation

/// Uninstall removes the app and its files; Reset removes only the app's data.
public enum ApplicationsUninstallMode: String, Sendable, CaseIterable, Codable {
    case uninstall
    case reset

    public var title: String {
        switch self {
        case .uninstall: return "Uninstall"
        case .reset: return "Reset"
        }
    }
}

/// Size, file count and identity of a path, measured once.
public struct ApplicationsMeasured: Sendable, Equatable {
    public var bytes: Int64
    public var files: Int
    public var inode: UInt64?

    public init(bytes: Int64, files: Int, inode: UInt64?) {
        self.bytes = bytes
        self.files = files
        self.inode = inode
    }

    /// Measures with `DiskUsage` (allocated bytes, hard links counted once).
    public static func measure(_ path: String) -> ApplicationsMeasured {
        let entry = FileWalker.entry(at: path)
        guard let entry else { return ApplicationsMeasured(bytes: 0, files: 0, inode: nil) }
        if !entry.isDirectory {
            return ApplicationsMeasured(bytes: entry.allocatedSize, files: 1, inode: entry.inode)
        }
        let usage = DiskUsage.measure(path)
        return ApplicationsMeasured(bytes: usage.bytes, files: max(usage.fileCount, 1), inode: entry.inode)
    }
}

/// Metadata keys on Applications `ScanItem`s.
public enum ApplicationsMeta {
    /// `ApplicationsComponentKind` raw value, or "update".
    public static let kind = "applications.kind"
    /// Path of the owning app bundle.
    public static let appPath = "applications.appPath"
    /// "1" when the item is pre-selected for a complete uninstall.
    public static let uninstallDefault = "applications.uninstallDefault"
    /// "1" when the item is pre-selected for a Reset.
    public static let resetDefault = "applications.resetDefault"
    /// "1" when a Reset may remove the item.
    public static let resetData = "applications.resetData"
    /// "1" when the item lives in `/Library` (all users).
    public static let systemDomain = "applications.systemDomain"
    public static let caskToken = "applications.caskToken"
    public static let ownerKey = "applications.ownerKey"
    /// Read by `SpruceSettings.filteringIgnored`.
    public static let bundleID = "bundleID"
    /// Re-checked by `FileRemover` (the item must still be the same file).
    public static let inode = "inode"
}

// MARK: - App component checklist

public enum ApplicationsComponents {

    /// Group id for a component kind.
    public static func groupID(_ kind: ApplicationsComponentKind) -> String { "applications.component." + kind.rawValue }

    /// Builds the app's checklist: the bundle, its Dock icon, then its files by kind.
    public static func groups(app: ApplicationsAppInfo, candidates: [ApplicationsLeftoverCandidate], inDock: Bool,
                              mode: ApplicationsUninstallMode,
                              measure: (String) -> ApplicationsMeasured = ApplicationsMeasured.measure) -> [ScanGroup] {
        var byKind: [ApplicationsComponentKind: [ScanItem]] = [:]
        let common: [String: String] = [ApplicationsMeta.bundleID: app.bundleID, ApplicationsMeta.appPath: app.path]

        var bundleMeta = common
        bundleMeta[ApplicationsMeta.kind] = ApplicationsComponentKind.application.rawValue
        bundleMeta[ApplicationsMeta.uninstallDefault] = "1"
        bundleMeta[ApplicationsMeta.resetDefault] = "0"
        bundleMeta[ApplicationsMeta.resetData] = "0"
        let bundleMeasure = app.size > 0 ? ApplicationsMeasured(bytes: app.size, files: 1, inode: nil) : measure(app.path)
        var bundle = ScanItem.file(app.url, size: bundleMeasure.bytes, itemCount: bundleMeasure.files, safety: .safe,
                                   title: (app.path as NSString).lastPathComponent,
                                   note: "The application itself. It goes to the Trash, where you can put it back.",
                                   lastUsed: app.lastUsed, metadata: bundleMeta)
        bundle.symbol = "app"
        byKind[.application] = [bundle]

        if inDock {
            var dockMeta = common
            dockMeta[ApplicationsMeta.kind] = ApplicationsComponentKind.dockIcon.rawValue
            dockMeta[ApplicationsMeta.uninstallDefault] = "1"
            dockMeta[ApplicationsMeta.resetDefault] = "0"
            dockMeta[ApplicationsMeta.resetData] = "0"
            byKind[.dockIcon] = [ScanItem(
                id: "applications.dock:" + app.path, title: "\(app.name) in the Dock", subtitle: "Removed from the Dock",
                size: 0, safety: .safe, deletion: .custom, symbol: "dock.rectangle",
                note: "The app's tile is removed from the Dock so no question mark is left behind.", metadata: dockMeta)]
        }

        for candidate in candidates {
            var meta = common
            meta[ApplicationsMeta.kind] = candidate.kind.rawValue
            meta[ApplicationsMeta.uninstallDefault] = candidate.isPreselected ? "1" : "0"
            meta[ApplicationsMeta.resetDefault] = candidate.isResetPreselected ? "1" : "0"
            meta[ApplicationsMeta.resetData] = candidate.kind.isResetData && !candidate.isSystemDomain ? "1" : "0"
            meta[ApplicationsMeta.systemDomain] = candidate.isSystemDomain ? "1" : "0"
            let measured = measure(candidate.path)
            if let inode = measured.inode { meta[ApplicationsMeta.inode] = String(inode) }
            let url = URL(fileURLWithPath: candidate.path)
            let item = ScanItem.file(url, size: measured.bytes, itemCount: measured.files, safety: candidate.safety,
                                     note: candidate.note, metadata: meta)
            byKind[candidate.kind, default: []].append(item)
        }

        var groups: [ScanGroup] = []
        for kind in ApplicationsComponentKind.allCases {
            guard let items = byKind[kind], !items.isEmpty else { continue }
            let safety: SafetyLevel = items.allSatisfy { $0.safety == .safe } ? .safe : .review
            groups.append(ScanGroup(id: groupID(kind), title: kind.title, detail: kind.detail, symbol: kind.symbol,
                                    safety: safety, items: items.sorted { $0.size > $1.size }))
        }
        apply(mode: mode, to: &groups)
        return groups
    }

    /// Re-applies the default selection for a mode (the "Smart Selector").
    public static func apply(mode: ApplicationsUninstallMode, to groups: inout [ScanGroup]) {
        for g in groups.indices {
            for i in groups[g].items.indices {
                let item = groups[g].items[i]
                let key = mode == .uninstall ? ApplicationsMeta.uninstallDefault : ApplicationsMeta.resetDefault
                groups[g].items[i].isSelected = item.metadata[key] == "1" && item.safety != .risky
            }
        }
    }

    /// The mode the current selection corresponds to, or nil for a custom selection.
    public static func mode(of groups: [ScanGroup]) -> ApplicationsUninstallMode? {
        for mode in ApplicationsUninstallMode.allCases {
            var copy = groups
            apply(mode: mode, to: &copy)
            if copy.allItems.map(\.isSelected) == groups.allItems.map(\.isSelected) { return mode }
        }
        return nil
    }

    /// True when the selection includes the app bundle (an uninstall rather than a reset).
    public static func removesApp(_ items: [ScanItem]) -> Bool {
        items.contains { $0.metadata[ApplicationsMeta.kind] == ApplicationsComponentKind.application.rawValue }
    }
}

// MARK: - Leftovers of removed apps

public enum ApplicationsOrphanPlan {
    public static let rootGroupID = "applications.leftovers"

    /// One review group per removed app, largest first. Nothing is pre-selected.
    public static func groups(_ orphans: [ApplicationsOrphanGroup],
                              measure: (String) -> ApplicationsMeasured = ApplicationsMeasured.measure) -> [ScanGroup] {
        var groups: [ScanGroup] = []
        for orphan in orphans {
            let items: [ScanItem] = orphan.entries.map { entry in
                let measured = measure(entry.path)
                var meta: [String: String] = [ApplicationsMeta.kind: entry.kind.rawValue, ApplicationsMeta.ownerKey: orphan.ownerKey]
                if let inode = measured.inode { meta[ApplicationsMeta.inode] = String(inode) }
                let note = entry.isBrokenLaunchJob
                    ? "A launch agent whose program no longer exists. It can't run, so removing it is harmless."
                    : "\(entry.kind.title) named after \(orphan.ownerKey), an app that is no longer installed."
                return ScanItem.file(URL(fileURLWithPath: entry.path), size: measured.bytes, itemCount: measured.files,
                                     safety: .review, note: note, modified: entry.modified, metadata: meta)
            }
            guard !items.isEmpty else { continue }
            groups.append(ScanGroup(id: rootGroupID + "." + orphan.id, title: orphan.displayName, detail: orphan.note,
                                    symbol: "questionmark.folder", safety: .review, items: items.sorted { $0.size > $1.size }))
        }
        return groups.sorted { $0.totalSize > $1.totalSize }
    }
}

// MARK: - Installers

public enum ApplicationsInstallerPlan {
    public static let rootGroupID = "applications.installers"

    /// One group per installer kind. Only installers of installed apps older than 30 days
    /// (and not mounted) are pre-selected.
    public static func groups(_ files: [ApplicationsInstallerFile], now: Date = Date()) -> [ScanGroup] {
        var groups: [ScanGroup] = []
        for kind in ApplicationsInstallerKind.allCases {
            let items: [ScanItem] = files.filter { $0.kind == kind }.map { file in
                var meta: [String: String] = [ApplicationsMeta.kind: "installer." + kind.rawValue]
                if let inode = file.inode { meta[ApplicationsMeta.inode] = String(inode) }
                return ScanItem.file(URL(fileURLWithPath: file.path), size: file.size, safety: file.isSafe(now: now) ? .safe : .review,
                                     subtitle: file.installedApp.map { "For \($0) · " + ((file.path as NSString).deletingLastPathComponent).abbreviatingHome },
                                     note: file.note(now: now), modified: file.modified, metadata: meta)
            }
            guard !items.isEmpty else { continue }
            groups.append(ScanGroup(id: rootGroupID + "." + kind.rawValue, title: kind.title,
                                    detail: "Installers in Downloads and on the Desktop. Once an app is installed, its installer is no longer needed.",
                                    symbol: kind.symbol, safety: items.allSatisfy { $0.safety == .safe } ? .safe : .review,
                                    items: items.sorted { $0.size > $1.size }))
        }
        return groups
    }
}

// MARK: - Checkup

public enum ApplicationsCheckupPlan {
    public static let updatesGroupID = "applications.checkup.updates"
    public static let leftoversGroupID = "applications.checkup.leftovers"

    /// Review groups: Homebrew updates (unattended, unselected) and files of removed apps (unselected).
    public static func review(updates: [ApplicationsUpdate], orphanGroups: [ScanGroup]) -> [ScanGroup] {
        var groups: [ScanGroup] = []
        let unattended = updates.filter(\.isUnattended)
        if !unattended.isEmpty {
            let items = unattended.map { update -> ScanItem in
                var meta: [String: String] = [ApplicationsMeta.kind: "update", ApplicationsMeta.bundleID: update.bundleID,
                                              ApplicationsMeta.appPath: update.appPath]
                if let token = update.caskToken { meta[ApplicationsMeta.caskToken] = token }
                return ScanItem(id: "applications.update:" + update.id, title: "\(update.name) \(update.availableVersion)",
                                subtitle: "Installed: \(update.installedVersion)", url: URL(fileURLWithPath: update.appPath),
                                size: 0, safety: .review, isSelected: false, deletion: .custom, symbol: "arrow.down.circle",
                                note: update.isMajor
                                    ? "A major upgrade — it may need a new licence. Installed with Homebrew."
                                    : "Installed with Homebrew (brew upgrade). Quit the app first if it is open.",
                                metadata: meta)
            }
            groups.append(ScanGroup(id: updatesGroupID, title: "Homebrew Updates",
                                    detail: "Selected updates are downloaded and installed with Homebrew.",
                                    symbol: "arrow.down.circle", safety: .review, items: items))
        }
        if !orphanGroups.isEmpty {
            groups.append(ScanGroup(id: leftoversGroupID, title: "Files from Removed Apps",
                                    detail: "Support files of apps that are no longer installed. Review them before removing.",
                                    symbol: "questionmark.folder", safety: .review, children: orphanGroups))
        }
        return groups
    }

    /// The Applications tile: update count first, else the size of leftovers. Informational —
    /// nothing is pre-selected.
    public static func tile(updates: [ApplicationsUpdate], updatesChecked: Bool, orphanGroups: [ScanGroup]) -> CheckupTile {
        let leftoverBytes = orphanGroups.totalSize
        let leftoverApps = orphanGroups.count
        let others = updates.filter { !$0.isUnattended }.count
        if !updates.isEmpty {
            var detail = updates.count == 1 ? "app update available" : "app updates available"
            if others > 0 && others < updates.count { detail += " (\(others) via the App Store or the app)" }
            if leftoverApps > 0 { detail += " · \(ByteFormat.string(leftoverBytes)) from removed apps" }
            return CheckupTile(module: .applications, headline: CountFormat.items(updates.count, singular: "update"),
                               detail: detail, status: .info, isSelected: false)
        }
        if leftoverApps > 0 {
            let detail = "left by \(CountFormat.items(leftoverApps, singular: "removed app")) — review before removing"
            return CheckupTile(module: .applications, headline: ByteFormat.string(leftoverBytes), detail: detail,
                               status: .info, isSelected: false)
        }
        return CheckupTile(module: .applications, headline: updatesChecked ? "Up to date" : "All tidy",
                           detail: updatesChecked ? "No updates or leftovers found" : "No leftovers from removed apps",
                           status: .clear, isSelected: false)
    }
}
