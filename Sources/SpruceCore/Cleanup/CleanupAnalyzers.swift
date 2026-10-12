import Foundation

/// Category-specific detection that goes beyond "glob + age".
extension CleanupScanner {

    // MARK: Plist helpers

    static func readPlist(_ path: String, maxBytes: Int64 = 8_000_000) -> Any? {
        guard let entry = FileWalker.entry(at: path), entry.isRegularFile, entry.logicalSize <= maxBytes,
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    static func readPlistDictionary(_ path: String) -> [String: Any]? {
        readPlist(path) as? [String: Any]
    }

    // MARK: Broken preferences

    /// Preference domains that are never offered even when damaged: macOS repairs or
    /// owns them, and removing them resets the Dock, Finder, keyboard, network or printing.
    static let protectedPreferenceNames: [String] = [
        ".GlobalPreferences*", "com.apple.dock*", "com.apple.finder*", "com.apple.loginwindow*",
        "loginwindow*", "com.apple.systemuiserver*", "com.apple.HIToolbox*", "com.apple.inputmethod*",
        "com.apple.inputsources*", "com.apple.TextInputMenu*", "com.apple.Bluetooth*", "com.apple.airport*",
        "com.apple.wifi*", "com.apple.networkextension*", "com.apple.security*", "com.apple.keyboard*",
        "org.cups*", "com.apple.print*", "com.apple.windowserver*", "com.apple.controlcenter*",
        "com.apple.systempreferences*", "com.apple.spaces*", "com.apple.universalaccess*",
        "com.apple.symbolichotkeys*", "com.apple.screensaver*", "com.apple.WindowManager*",
        "com.apple.CloudSubscriptionFeatures*", "com.apple.icloud*", "MobileMeAccounts*",
    ]

    static func isAtomicWriteTempSuffix(_ suffix: Substring) -> Bool {
        guard (5...10).contains(suffix.count), suffix.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        return suffix.contains(where: { $0.isNumber || $0.isUppercase })
    }

    func brokenPreferenceDraft(_ rule: CleanupRule, path: String, entry: FileEntry) -> CleanupRowDraft? {
        guard entry.isRegularFile else { return nil }
        let name = entry.name
        if CleanupPaths.matchesAny(name, Self.protectedPreferenceNames) { return nil }
        let dayAgo = context.now.addingTimeInterval(-86_400)
        let note: String
        if name.hasSuffix(".plist") {
            if entry.logicalSize == 0 {
                note = "This settings file is empty. The app creates a fresh one with default settings."
            } else {
                guard entry.logicalSize <= 50_000_000, let data = FileManager.default.contents(atPath: path) else {
                    return nil
                }
                if (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil { return nil }
                note = "This settings file is damaged and can't be read. The app creates a fresh one with default settings."
            }
        } else if name.hasSuffix(".plist.lockfile") {
            guard entry.modified < dayAgo else { return nil }
            note = "A lock left behind by an interrupted settings write."
        } else if let range = name.range(of: ".plist.") {
            guard entry.modified < dayAgo, Self.isAtomicWriteTempSuffix(name[range.upperBound...]) else { return nil }
            note = "A temporary copy left behind by an interrupted settings write."
        } else {
            return nil
        }
        return CleanupRowDraft(
            path: path, entry: entry, title: name,
            subtitle: CleanupPaths.display(CleanupPaths.parent(path), home: context.home),
            size: entry.allocatedSize, count: 1, modified: entry.modified, lastUsed: nil,
            safety: rule.safety, selected: rule.defaultSelected, note: note + " It goes to the Trash."
        )
    }

    // MARK: Broken launch agents

    /// The program a launchd plist starts, when it names an absolute path that no longer
    /// exists. Unreadable plists, Apple items, relative paths and paths on (possibly
    /// unmounted) external volumes are never reported.
    func missingLaunchTarget(plistPath: String, fileName: String) -> (label: String, program: String)? {
        if fileName.hasPrefix("com.apple.") { return nil }
        guard let dict = Self.readPlistDictionary(plistPath) else { return nil }
        let label = dict["Label"] as? String ?? (fileName as NSString).deletingPathExtension
        if label.hasPrefix("com.apple.") { return nil }
        let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first
        guard let program, program.hasPrefix("/"), !program.hasPrefix("/Volumes/") else { return nil }
        if FileWalker.entry(at: program) != nil { return nil }
        // The top-level folder must exist (e.g. /Applications, /usr, /opt); otherwise the
        // target may live on a mount point that is simply not there right now.
        guard let top = CleanupPaths.components(program).first,
              FileWalker.entry(at: "/" + top) != nil else { return nil }
        return (label, program)
    }

    func launchAgentDraft(_ rule: CleanupRule, path: String, entry: FileEntry) -> CleanupRowDraft? {
        guard entry.isRegularFile, let target = missingLaunchTarget(plistPath: path, fileName: entry.name) else {
            return nil
        }
        var draft = CleanupRowDraft(
            path: path, entry: entry, title: target.label,
            subtitle: CleanupPaths.display(CleanupPaths.parent(path), home: context.home),
            size: entry.allocatedSize, count: 1, modified: entry.modified, lastUsed: nil,
            safety: rule.safety, selected: rule.defaultSelected,
            note: "Starts \(CleanupPaths.display(target.program, home: context.home)), which no longer exists. It goes to the Trash."
        )
        draft.metadata[CleanupMetadataKey.launchItem] = "1"
        return draft
    }

    func systemLaunchItemInsights(_ rule: CleanupRule, index: Int) -> [CleanupInsight] {
        guard index < rulePatterns.count else { return [] }
        var insights: [CleanupInsight] = []
        for pattern in rulePatterns[index] {
            for path in CleanupPaths.expand(pattern.absolute, includeHidden: false).paths {
                guard let entry = FileWalker.entry(at: path), entry.isRegularFile,
                      let target = missingLaunchTarget(plistPath: path, fileName: entry.name) else { continue }
                insights.append(CleanupInsight(
                    id: "launch." + path, category: .brokenLoginItems, title: target.label,
                    detail: "A system-wide launch item that starts \(target.program), which no longer exists. Review it in Performance › Login Items (needs your administrator password).",
                    size: entry.allocatedSize, path: path))
            }
        }
        return insights
    }

    // MARK: iOS backups

    func iosBackupDraft(_ rule: CleanupRule, path: String, entry: FileEntry) -> CleanupRowDraft {
        let info = Self.readPlistDictionary(path + "/Info.plist")
        let manifest = Self.readPlistDictionary(path + "/Manifest.plist")
        let deviceName = info?["Device Name"] as? String ?? info?["Display Name"] as? String
        let backupDate = info?["Last Backup Date"] as? Date
        let version = info?["Product Version"] as? String
        let target = info?["Target Identifier"] as? String ?? info?["Unique Identifier"] as? String
        let encrypted = manifest?["IsEncrypted"] as? Bool ?? false
        let usage = measure(path, entry: entry, budget: rule.measureBudget)
        var parts: [String] = []
        if let version { parts.append("iOS \(version)") }
        if encrypted { parts.append("Encrypted") }
        parts.append("Backup \(entry.name.prefix(8))…")
        let deviceKey = target ?? String(entry.name.split(separator: "-").first ?? Substring(entry.name))
        var draft = CleanupRowDraft(
            path: path, entry: entry, title: deviceName ?? "iPhone or iPad backup",
            subtitle: parts.joined(separator: " · "),
            size: usage.bytes, count: max(usage.files, 1), modified: usage.newest,
            lastUsed: backupDate ?? entry.modified,
            safety: .review, selected: false, note: rule.note
        )
        draft.metadata["device"] = deviceKey
        return draft
    }

    /// Flags the newest backup of every device.
    func markLatestBackups(_ items: inout [ScanItem]) {
        var newestByDevice: [String: (index: Int, date: Date)] = [:]
        for (i, item) in items.enumerated() {
            let device = item.metadata["device"] ?? item.id
            let date = item.lastUsed ?? item.modified ?? .distantPast
            if let current = newestByDevice[device], current.date >= date { continue }
            newestByDevice[device] = (i, date)
        }
        for (_, value) in newestByDevice {
            items[value.index].metadata[CleanupMetadataKey.latestBackup] = "1"
            items[value.index].isSelected = false
            items[value.index].metadata[CleanupMetadataKey.recommended] = "0"
            items[value.index].note = "The most recent backup of this device. " + (items[value.index].note ?? "")
        }
    }

    // MARK: Mail

    /// Whether a file was edited after it was saved (modified well after creation).
    static func isChangedByUser(_ path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let created = attributes[.creationDate] as? Date,
              let modified = attributes[.modificationDate] as? Date else { return false }
        return modified.timeIntervalSince(created) > 120
    }

    func mailDownloadDraft(_ rule: CleanupRule, path: String, entry: FileEntry) -> CleanupRowDraft? {
        var title = entry.name
        var filePath = path
        if entry.isDirectory, let names = CleanupPaths.list(path)?.filter({ !$0.hasPrefix(".") }), names.count == 1 {
            title = names[0]
            filePath = CleanupPaths.child(of: path, names[0])
        }
        let usage = measure(path, entry: entry, budget: rule.measureBudget)
        guard usage.bytes > 0 else { return nil }
        let changed = Self.isChangedByUser(filePath)
        var draft = CleanupRowDraft(
            path: path, entry: entry, title: title,
            subtitle: "Opened in Mail",
            size: usage.bytes, count: max(usage.files, 1), modified: usage.newest, lastUsed: nil,
            safety: changed ? .review : rule.safety, selected: changed ? false : rule.defaultSelected,
            note: changed
                ? "Changed by you after it was opened. The message only has the original, so this version can't be downloaded again."
                : rule.note
        )
        draft.metadata[CleanupMetadataKey.group] = "mailAttachments.opened"
        draft.metadata[CleanupMetadataKey.groupTitle] = "Opened in Mail"
        return draft
    }

    /// `~/Library/Mail/V<n>` with the highest n.
    func currentMailStore() -> (path: String?, denied: Bool) {
        guard let mailRoot = Self.resolveToken("~/Library/Mail", context: context),
              let rootEntry = FileWalker.entry(at: mailRoot), rootEntry.isDirectory, !rootEntry.isSymlink else {
            return (nil, false)
        }
        guard let names = CleanupPaths.list(mailRoot) else { return (nil, true) }
        let best = names.compactMap { name -> (String, Int)? in
            guard name.hasPrefix("V"), let n = Int(name.dropFirst()) else { return nil }
            return (name, n)
        }.max { $0.1 < $1.1 }
        guard let best else { return (nil, false) }
        return (CleanupPaths.child(of: mailRoot, best.0), false)
    }

    func mailAccount(for folder: String) -> CleanupMailAccount {
        if let account = context.mailAccounts[folder] { return account }
        if folder == "Mailboxes" { return CleanupMailAccount(name: "On My Mac", kind: .local) }
        return CleanupMailAccount(name: "Mail account", kind: .unknown)
    }

    func mailStoredItems(_ rule: CleanupRule, onProgress: ((String) -> Void)?) -> (items: [ScanItem], denied: Bool) {
        let store = currentMailStore()
        guard let base = store.path else { return ([], store.denied) }
        guard let accounts = CleanupPaths.list(base) else { return ([], true) }
        var items: [ScanItem] = []
        let owner = "com.apple.mail"
        for folder in accounts.sorted() where folder != "MailData" && !folder.hasPrefix(".") {
            if isCancelled() { break }
            let accountPath = CleanupPaths.child(of: base, folder)
            guard let accountEntry = FileWalker.entry(at: accountPath), accountEntry.isDirectory,
                  !accountEntry.isSymlink, !isBlocked(accountPath) else { continue }
            onProgress?(accountPath)
            let account = mailAccount(for: folder)
            var attachmentFolders: [String] = []
            FileWalker.walk(accountPath, options: .init(includeHidden: false, crossDevices: false,
                                                        descendIntoPackages: true, maxDepth: 14)) { e in
                if isCancelled() { return .stop }
                guard e.depth > 0, e.isDirectory, !e.isSymlink else { return .continue }
                if e.name == "Messages" { return .skipChildren }
                if e.name == "Attachments" {
                    attachmentFolders.append(e.path)
                    return .skipChildren
                }
                return .continue
            }
            for folderPath in attachmentFolders {
                FileWalker.walk(folderPath, options: .init(includeHidden: false, crossDevices: false,
                                                           descendIntoPackages: true, maxDepth: 6)) { e in
                    if isCancelled() { return .stop }
                    guard e.isRegularFile, !e.isSymlink, e.allocatedSize > 0 else { return .continue }
                    if isBlocked(e.path) || !isParentWritable(e.path) { return .continue }
                    let changed = Self.isChangedByUser(e.path)
                    let mailbox = CleanupPaths.components(e.path).last(where: { $0.hasSuffix(".mbox") })
                        .map { String($0.dropLast(5)) } ?? "Mailbox"
                    let safety: SafetyLevel
                    let note: String
                    if !account.isRecoverable {
                        safety = .risky
                        note = account.kind == .unknown
                            ? "Spruce couldn't confirm this account keeps messages on a server, so this may be the only copy."
                            : "Stored only on this Mac. Removing it deletes your only copy of this attachment."
                    } else if changed {
                        safety = .review
                        note = "Changed by you after it was downloaded, so the server copy is different."
                    } else {
                        safety = .safe
                        note = "Mail downloads this attachment again from the server when you open the message. It goes to the Trash."
                    }
                    var draft = CleanupRowDraft(
                        path: e.path, entry: e, title: e.name, subtitle: "\(account.name) · \(mailbox)",
                        size: e.allocatedSize, count: 1, modified: e.modified, lastUsed: nil,
                        safety: safety, selected: safety == .safe, note: note
                    )
                    draft.metadata[CleanupMetadataKey.mode] = "whole"
                    draft.metadata[CleanupMetadataKey.group] = "mailAttachments.account.\(folder)"
                    draft.metadata[CleanupMetadataKey.groupTitle] = account.name
                    items.append(finalize(draft, rule: rule, owner: owner))
                    return .continue
                }
            }
        }
        return (items, false)
    }

    func mailTrashInsights() -> [CleanupInsight] {
        guard let base = currentMailStore().path, let accounts = CleanupPaths.list(base) else { return [] }
        var insights: [CleanupInsight] = []
        for folder in accounts.sorted() where folder != "MailData" && !folder.hasPrefix(".") {
            let accountPath = CleanupPaths.child(of: base, folder)
            for box in ["Deleted Messages.mbox", "Trash.mbox"] {
                let path = CleanupPaths.child(of: accountPath, box)
                guard let entry = FileWalker.entry(at: path), entry.isDirectory, !entry.isSymlink else { continue }
                let usage = DiskUsage.measure(path, deadline: Date().addingTimeInterval(10))
                guard usage.fileCount > 0 else { continue }
                let account = mailAccount(for: folder)
                insights.append(CleanupInsight(
                    id: "mailTrash.\(folder).\(box)", category: .trashBins, title: "Mail Trash — \(account.name)",
                    detail: "Deleted messages Mail still keeps. Erase them in Mail (Mailbox › Erase Deleted Items) so the mailbox stays consistent.",
                    size: usage.bytes, path: path, symbol: "envelope"))
            }
        }
        return insights
    }

    // MARK: Xcode

    func decorateDerivedData(_ draft: inout CleanupRowDraft) {
        let name = draft.entry.name
        if let dash = name.lastIndex(of: "-") {
            let suffix = name[name.index(after: dash)...]
            if suffix.count >= 20, suffix.allSatisfy({ $0.isLowercase && $0.isLetter }) {
                draft.title = String(name[..<dash])
            }
        }
        if let info = Self.readPlistDictionary(draft.path + "/info.plist"),
           let workspace = info["WorkspacePath"] as? String {
            draft.subtitle = CleanupPaths.display(workspace, home: context.home)
            if FileWalker.entry(at: workspace) == nil {
                draft.note = "Build data of a project that no longer exists at \(CleanupPaths.display(workspace, home: context.home))."
            }
        }
    }

    /// Keeps the newest entry of every folder unselected (Device Support, docs cache).
    func keepNewest(_ items: inout [ScanItem]) {
        var byParent: [String: [Int]] = [:]
        for (i, item) in items.enumerated() {
            let parent = item.url.map { $0.deletingLastPathComponent().path } ?? ""
            byParent[parent, default: []].append(i)
        }
        for (_, indices) in byParent {
            guard let newest = indices.max(by: { isOlder(items[$0], items[$1]) }) else { continue }
            items[newest].isSelected = false
            items[newest].safety = .review
            items[newest].metadata[CleanupMetadataKey.recommended] = "0"
            items[newest].note = "The newest version, kept so you can keep working with it. " + (items[newest].note ?? "")
        }
    }

    private func isOlder(_ a: ScanItem, _ b: ScanItem) -> Bool {
        let va = a.url.flatMap { CleanupPaths.versionKey($0.lastPathComponent) }
        let vb = b.url.flatMap { CleanupPaths.versionKey($0.lastPathComponent) }
        if let va, let vb, va != vb { return CleanupPaths.versionLess(va, vb) }
        if va != nil && vb == nil { return false }
        if va == nil && vb != nil { return true }
        return (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
    }

    // MARK: Trash on external drives

    func externalTrashItems(_ rule: CleanupRule, onProgress: ((String) -> Void)?) -> [ScanItem] {
        var items: [ScanItem] = []
        for volume in context.externalVolumes {
            if isCancelled() { break }
            let dir = volume.path + "/.Trashes/\(context.uid)"
            guard let dirEntry = FileWalker.entry(at: dir), dirEntry.isDirectory, !dirEntry.isSymlink,
                  let names = CleanupPaths.list(dir) else { continue }
            onProgress?(dir)
            for name in names.sorted() where !CleanupPaths.matchesAny(name, rule.excludedNames) {
                let path = CleanupPaths.child(of: dir, name)
                guard let entry = FileWalker.entry(at: path), !isBlocked(path) else { continue }
                let usage = measure(path, entry: entry, budget: rule.measureBudget)
                var draft = CleanupRowDraft(
                    path: path, entry: entry, title: name, subtitle: "Trash on \(volume.name)",
                    size: usage.bytes, count: max(usage.files, 1), modified: usage.newest, lastUsed: nil,
                    safety: .safe,
                    // Checkup leaves connected drives alone by default: one may be a backup disk.
                    selected: context.purpose != .checkup,
                    note: "In the Trash of \(volume.name). Emptying removes it for good."
                )
                draft.metadata[CleanupMetadataKey.mode] = "whole"
                draft.metadata[CleanupMetadataKey.zone] = dir
                draft.metadata[CleanupMetadataKey.group] = "trashBins.volume.\(volume.path)"
                draft.metadata[CleanupMetadataKey.groupTitle] = "Trash on \(volume.name)"
                draft.metadata[CleanupMetadataKey.trashBin] = volume.name
                items.append(finalize(draft, rule: rule, owner: nil))
            }
        }
        return items
    }

    // MARK: Informational

    func documentVersionInsights() -> [CleanupInsight] {
        for raw in context.documentRevisionsPaths {
            let path = context.systemRoot + raw
            guard let entry = FileWalker.entry(at: path), entry.isDirectory else { continue }
            let readable = CleanupPaths.list(path) != nil
            let usage = readable ? DiskUsage.measure(path, deadline: Date().addingTimeInterval(8)) : .zero
            let size: Int64? = readable && usage.bytes > 0 ? usage.bytes : nil
            return [CleanupInsight(
                id: "documentVersions", category: .documentVersions, title: "Document Versions",
                detail: size == nil
                    ? "macOS keeps earlier versions of documents in a private store it trims by itself. To remove versions, open a document and choose File › Revert To › Browse All Versions."
                    : "Earlier versions of documents kept by macOS, which trims them by itself. To remove versions, open a document and choose File › Revert To › Browse All Versions.",
                size: size, path: nil)]
        }
        return []
    }

    func deletedUserInsights() -> [CleanupInsight] {
        let root = context.systemRoot + context.deletedUsersPath
        guard let names = CleanupPaths.list(root) else { return [] }
        var insights: [CleanupInsight] = []
        for name in names.sorted() where name != ".DS_Store" && name != ".localized" {
            let path = CleanupPaths.child(of: root, name)
            guard let entry = FileWalker.entry(at: path), !entry.isSymlink else { continue }
            let usage = measure(path, entry: entry, budget: 10)
            let title = name.hasSuffix(".dmg") ? String(name.dropLast(4)) : name
            insights.append(CleanupInsight(
                id: "deletedUsers." + name, category: .deletedUsers, title: title,
                detail: "Archive of a deleted user account. If nobody needs these files, delete it in Finder (needs your administrator password).",
                size: usage.bytes > 0 ? usage.bytes : nil, path: path))
        }
        return insights
    }

    func installerInsights(_ rule: CleanupRule, index: Int) -> [CleanupInsight] {
        guard index < rulePatterns.count else { return [] }
        var insights: [CleanupInsight] = []
        for pattern in rulePatterns[index] {
            for path in CleanupPaths.expand(pattern.absolute, includeHidden: false).paths {
                guard let entry = FileWalker.entry(at: path), entry.isDirectory, !entry.isSymlink else { continue }
                let usage = measure(path, entry: entry, budget: 10)
                let name = entry.name.hasSuffix(".app") ? String(entry.name.dropLast(4)) : entry.name
                insights.append(CleanupInsight(
                    id: "installer." + path, category: .oldUpdates, title: name, detail: rule.note,
                    size: usage.bytes, path: path, symbol: "arrow.down.app"))
            }
        }
        return insights
    }
}
