import AppKit
import Foundation
import SpruceCore

/// Whether Spruce could read the classic login items through System Events.
public enum PerformanceLoginItemsAccess: Sendable, Equatable {
    case granted
    /// The user declined Automation access to System Events.
    case denied
    case failed(String)
}

/// Everything that starts with your Mac or your session.
public struct PerformanceStartupInventory: Sendable {
    public var items: [PerformanceStartupItem]
    public var loginItemsAccess: PerformanceLoginItemsAccess
    public var date: Date

    public init(items: [PerformanceStartupItem], loginItemsAccess: PerformanceLoginItemsAccess, date: Date = Date()) {
        self.items = items
        self.loginItemsAccess = loginItemsAccess
        self.date = date
    }

    /// Apps that open at login (classic and app-registered).
    public var loginItems: [PerformanceStartupItem] { items.filter { !$0.isBackground } }
    /// Launch agents and daemons.
    public var backgroundItems: [PerformanceStartupItem] { items.filter(\.isBackground) }
}

/// Runs AppleScript in-process on one serial queue (NSAppleScript is not thread-safe).
enum PerformanceAppleScriptRunner {
    enum Result: Sendable {
        case success(String)
        case failure(code: Int, message: String)
    }

    /// errAEEventNotPermitted / errAEEventWouldRequireUserConsent: Automation access was declined.
    static let deniedCodes: Set<Int> = [-1743, -1744]

    private static let queue = DispatchQueue(label: "Spruce.Performance.AppleScript", qos: .userInitiated)

    static func run(_ source: String) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failure(code: 0, message: "The script couldn't be prepared."))
                    return
                }
                var errorInfo: NSDictionary?
                let output = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)."
                    continuation.resume(returning: .failure(code: code, message: message))
                } else {
                    continuation.resume(returning: .success(output.stringValue ?? ""))
                }
            }
        }
    }
}

extension PerformanceEngine {
    // MARK: - Inventory

    /// Lists launch agents and daemons (Apple's skipped), classic login items and items
    /// registered by apps, with their launchd state, vendor and broken status.
    public func startupInventory() async -> PerformanceStartupInventory {
        let home = NSHomeDirectory()
        let uid = getuid()
        let apps = PerformanceAppIndex(apps: PerformanceAppScanner.scan(folders: PerformanceAppScanner.defaultFolders(home: home)))
        async let userStateTask = launchState(domain: "gui/\(uid)", allowListFallback: true)
        async let systemStateTask = launchState(domain: "system", allowListFallback: false)
        async let loginTask = PerformanceAppleScriptRunner.run(PerformanceAppleScript.listLoginItemsSource)
        let userState = await userStateTask
        let systemState = await systemStateTask
        let loginResult = await loginTask

        let fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
        let excluded = [Bundle.main.bundleIdentifier].compactMap { $0 }
        var items: [PerformanceStartupItem] = []
        var labels = Set<String>()

        for domain in PerformanceLaunchDomain.allCases {
            let state = domain == .systemDaemon ? systemState : userState
            for path in PerformanceLaunchPlist.plistPaths(in: domain.folder(home: home)) {
                let plist = PerformanceLaunchPlist.load(path: path, home: home)
                guard let item = PerformanceStartupBuilder.item(from: plist, domain: domain, state: state, apps: apps,
                                                                excludedLabelPrefixes: excluded, fileExists: fileExists) else { continue }
                items.append(item)
                if let label = item.label { labels.insert(label) }
            }
        }

        let access: PerformanceLoginItemsAccess
        var present: [PerformanceLegacyLoginItem] = []
        switch loginResult {
        case .success(let output):
            access = .granted
            present = PerformanceAppleScript.parseLoginItems(output)
        case .failure(let code, let message):
            access = PerformanceAppleScriptRunner.deniedCodes.contains(code) ? .denied : .failed(message)
        }
        let runningPIDs = runningAppPIDs()
        let ownPath = Bundle.main.bundlePath
        var loginIDs = Set<String>()
        for legacy in present where legacy.path != ownPath {
            let item = PerformanceStartupBuilder.loginItem(legacy, isEnabled: true, apps: apps, runningPIDs: runningPIDs,
                                                           fileExists: fileExists)
            if loginIDs.insert(item.id).inserted { items.append(item) }
        }
        if access == .granted {
            for saved in savedDisabledLoginItems()
            where !present.contains(where: { $0.path == saved.path && $0.name == saved.name }) {
                let item = PerformanceStartupBuilder.loginItem(saved, isEnabled: false, apps: apps, fileExists: fileExists)
                if loginIDs.insert(item.id).inserted { items.append(item) }
            }
        }
        items += appRegisteredItems(apps: apps, user: userState, system: systemState, knownLabels: labels, excluded: excluded)
        return PerformanceStartupInventory(items: items, loginItemsAccess: access)
    }

    func launchState(domain: String, allowListFallback: Bool) async -> PerformanceLaunchDomainState {
        let printed = await Shell.run("/bin/launchctl", ["print", domain], timeout: 20)
        var services: [String: PerformanceLaunchService]?
        if printed.status == 0 {
            let parsed = PerformanceLaunchctl.services(fromPrint: printed.stdout)
            services = parsed.isEmpty ? nil : parsed
        }
        if services == nil && allowListFallback {
            let listed = await Shell.run("/bin/launchctl", ["list"], timeout: 20)
            if listed.status == 0 {
                let parsed = PerformanceLaunchctl.services(fromList: listed.stdout)
                services = parsed.isEmpty ? nil : parsed
            }
        }
        return PerformanceLaunchDomainState(services: services, overrides: await overrides(domain: domain))
    }

    func overrides(domain: String) async -> [String: Bool]? {
        let result = await Shell.run("/bin/launchctl", ["print-disabled", domain], timeout: 20)
        guard result.status == 0 else { return nil }
        return PerformanceLaunchctl.disabledOverrides(fromPrintDisabled: result.stdout)
    }

    private func runningAppPIDs() -> [String: Int32] {
        var out: [String: Int32] = [:]
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            if let path = app.bundleURL?.path { out[path] = app.processIdentifier }
        }
        return out
    }

    /// Login-item helpers and launchd plists inside app bundles that the app registered
    /// (they are loaded in launchd). Informational: macOS manages them in System Settings.
    private func appRegisteredItems(apps: PerformanceAppIndex, user: PerformanceLaunchDomainState,
                                    system: PerformanceLaunchDomainState, knownLabels: Set<String>,
                                    excluded: [String]) -> [PerformanceStartupItem] {
        guard user.services != nil || system.services != nil else { return [] }
        var out: [PerformanceStartupItem] = []
        var seen = knownLabels
        let fm = FileManager.default
        for app in apps.apps {
            let id = app.bundleID.lowercased()
            if id.hasPrefix("com.apple.") || excluded.contains(where: { id.hasPrefix($0.lowercased()) }) { continue }
            let library = (app.path as NSString).appendingPathComponent("Contents/Library")
            guard fm.fileExists(atPath: library) else { continue }
            let vendorKey = PerformanceVendor.organization(of: app.bundleID)

            let loginItemsFolder = (library as NSString).appendingPathComponent("LoginItems")
            for name in ((try? fm.contentsOfDirectory(atPath: loginItemsFolder)) ?? []).sorted() where name.hasSuffix(".app") {
                let helperPath = (loginItemsFolder as NSString).appendingPathComponent(name)
                guard let helper = PerformanceAppScanner.read(appAt: helperPath), !seen.contains(helper.bundleID),
                      let service = user.services?[helper.bundleID] else { continue }
                seen.insert(helper.bundleID)
                out.append(PerformanceStartupItem(id: "app:" + helperPath, kind: .appLoginItem, name: helper.name,
                                                  label: helper.bundleID, executablePath: helperPath, vendorKey: vendorKey,
                                                  vendorName: app.name, appPath: app.path, appBundleID: app.bundleID,
                                                  isEnabled: true, isLoaded: true, pid: service.pid))
            }

            let embedded: [(String, PerformanceStartupKind, PerformanceLaunchDomainState)] = [
                ("LaunchAgents", .appAgent, user), ("LaunchDaemons", .appDaemon, system),
            ]
            for (folderName, kind, state) in embedded {
                let folder = (library as NSString).appendingPathComponent(folderName)
                for path in PerformanceLaunchPlist.plistPaths(in: folder) {
                    let plist = PerformanceLaunchPlist.load(path: path)
                    guard let label = plist.label, !seen.contains(label),
                          !PerformanceStartupBuilder.isApple(label: label, fileStem: plist.fileStem),
                          let service = state.services?[label] else { continue }
                    seen.insert(label)
                    let vendor = PerformanceVendorMatch(key: vendorKey, name: app.name, app: app)
                    out.append(PerformanceStartupItem(id: "app:" + path, kind: kind,
                                                      name: PerformanceStartupBuilder.displayName(for: plist, vendor: vendor),
                                                      label: label, plistPath: path, executablePath: plist.executable,
                                                      vendorKey: vendorKey, vendorName: app.name, appPath: app.path,
                                                      appBundleID: app.bundleID, isEnabled: true, isLoaded: true,
                                                      pid: service.pid, runAtLoad: plist.runAtLoad, keepAlive: plist.keepAlive))
                }
            }
        }
        return out
    }

    // MARK: - Saved (switched-off) classic login items

    func savedDisabledLoginItems() -> [PerformanceLegacyLoginItem] {
        guard let data = defaults.data(forKey: Self.disabledLoginItemsKey),
              let items = try? JSONDecoder().decode([PerformanceLegacyLoginItem].self, from: data) else { return [] }
        return items
    }

    func setSavedDisabledLoginItems(_ items: [PerformanceLegacyLoginItem]) {
        if items.isEmpty {
            defaults.removeObject(forKey: Self.disabledLoginItemsKey)
        } else if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.disabledLoginItemsKey)
        }
    }

    // MARK: - Turning items on and off

    /// Turns items on or off, reversibly. Agents use `launchctl` in your session; daemons are
    /// batched into one administrator prompt. Classic login items are removed from System
    /// Events and remembered so they can be turned back on.
    public func setEnabled(_ items: [PerformanceStartupItem], enabled: Bool) async -> RunOutcome {
        var failures: [ItemFailure] = []
        var succeeded: [String] = []
        var launchItems: [PerformanceStartupItem] = []

        for item in items {
            guard item.canToggle else {
                failures.append(ItemFailure(itemID: item.id, title: item.name,
                                            reason: "Its app registered it, so it's changed in System Settings › General › Login Items."))
                continue
            }
            if item.kind == .loginItem {
                let reason: String?
                if enabled {
                    reason = await addLoginItem(item)
                } else {
                    reason = await removeLoginItem(item, remember: true)
                }
                if let reason {
                    failures.append(ItemFailure(itemID: item.id, title: item.name, reason: reason))
                } else {
                    succeeded.append(item.id)
                }
            } else {
                launchItems.append(item)
            }
        }

        let launch = await toggleLaunchItems(launchItems, enable: enabled)
        succeeded += launch.succeeded
        failures += launch.failures

        let verb = enabled ? "Turned on" : "Turned off"
        return RunOutcome(module: .performance, processedCount: succeeded.count, removedItemIDs: succeeded, failures: failures,
                          summary: succeeded.isEmpty ? "Nothing was changed" : "\(verb) \(CountFormat.items(succeeded.count))")
    }

    /// `bootout`+`disable` or `enable`+`bootstrap`, then verifies against launchd's override
    /// database. Global agents fall back to an administrator prompt if your session refuses.
    func toggleLaunchItems(_ items: [PerformanceStartupItem], enable: Bool) async -> (succeeded: [String], failures: [ItemFailure]) {
        guard !items.isEmpty else { return ([], []) }
        let uid = getuid()
        var failures: [ItemFailure] = []
        var succeeded: [String] = []
        var rootInvocations: [PrivilegedRunner.Invocation] = []
        var rootItems: [PerformanceStartupItem] = []
        var toVerify: [PerformanceStartupItem] = []

        for item in items {
            guard let label = item.label, PerformanceLaunchctl.isSafeLabel(label), let plistPath = item.plistPath,
                  let domain = Self.launchDomain(for: item.kind) else {
                failures.append(ItemFailure(itemID: item.id, title: item.name, reason: "It has no valid launchd label, so it can't be switched."))
                continue
            }
            let commands = PerformanceLaunchctl.toggleCommands(enable: enable, domain: domain, uid: uid, label: label, plistPath: plistPath)
            if domain == .systemDaemon {
                rootInvocations += commands.map { PrivilegedRunner.Invocation("/bin/launchctl", $0) }
                rootItems.append(item)
            } else {
                // bootout/bootstrap fail harmlessly when the job is already in the wanted state.
                for arguments in commands { _ = await Shell.run("/bin/launchctl", arguments, timeout: 30) }
                toVerify.append(item)
            }
        }

        if !rootInvocations.isEmpty {
            do {
                try await PrivilegedRunner.shared.run(rootInvocations)
                toVerify += rootItems
            } catch {
                let reason = (error as? SpruceError) == .cancelled ? Self.cancelledDetail : error.localizedDescription
                failures += rootItems.map { ItemFailure(itemID: $0.id, title: $0.name, reason: reason) }
            }
        }

        var retryAsAdmin: [PerformanceStartupItem] = []
        let verified = await verifyToggle(toVerify, enable: enable, uid: uid)
        for item in toVerify {
            if verified.contains(item.id) {
                succeeded.append(item.id)
            } else if item.kind == .globalAgent {
                retryAsAdmin.append(item)
            } else {
                failures.append(ItemFailure(itemID: item.id, title: item.name, reason: "macOS didn't accept the change."))
            }
        }

        if !retryAsAdmin.isEmpty {
            var invocations: [PrivilegedRunner.Invocation] = []
            for item in retryAsAdmin {
                guard let label = item.label, let plistPath = item.plistPath else { continue }
                invocations += PerformanceLaunchctl.toggleCommands(enable: enable, domain: .globalAgent, uid: uid, label: label,
                                                                   plistPath: plistPath)
                    .map { PrivilegedRunner.Invocation("/bin/launchctl", $0) }
            }
            do {
                try await PrivilegedRunner.shared.run(invocations)
                let second = await verifyToggle(retryAsAdmin, enable: enable, uid: uid)
                for item in retryAsAdmin {
                    if second.contains(item.id) {
                        succeeded.append(item.id)
                    } else {
                        failures.append(ItemFailure(itemID: item.id, title: item.name, reason: "macOS didn't accept the change."))
                    }
                }
            } catch {
                let reason = (error as? SpruceError) == .cancelled ? Self.cancelledDetail : error.localizedDescription
                failures += retryAsAdmin.map { ItemFailure(itemID: $0.id, title: $0.name, reason: reason) }
            }
        }
        return (succeeded, failures)
    }

    /// Ids of items whose launchd override now matches the requested state.
    private func verifyToggle(_ items: [PerformanceStartupItem], enable: Bool, uid: UInt32) async -> Set<String> {
        guard !items.isEmpty else { return [] }
        let needsUser = items.contains { $0.kind != .systemDaemon }
        let needsSystem = items.contains { $0.kind == .systemDaemon }
        var userOverrides: [String: Bool]?
        var systemOverrides: [String: Bool]?
        if needsUser { userOverrides = await overrides(domain: "gui/\(uid)") }
        if needsSystem { systemOverrides = await overrides(domain: "system") }
        var ok = Set<String>()
        for item in items {
            guard let label = item.label else { continue }
            let map = item.kind == .systemDaemon ? systemOverrides : userOverrides
            if let disabled = map?[label] {
                if disabled == !enable { ok.insert(item.id) }
            } else if enable && map != nil {
                // No override at all means launchd treats it as enabled.
                ok.insert(item.id)
            }
        }
        return ok
    }

    static func launchDomain(for kind: PerformanceStartupKind) -> PerformanceLaunchDomain? {
        switch kind {
        case .userAgent: return .userAgent
        case .globalAgent: return .globalAgent
        case .systemDaemon: return .systemDaemon
        default: return nil
        }
    }

    /// Returns nil on success, or the reason it failed.
    private func removeLoginItem(_ item: PerformanceStartupItem, remember: Bool) async -> String? {
        let result = await PerformanceAppleScriptRunner.run(PerformanceAppleScript.deleteLoginItemSource(name: item.name))
        switch result {
        case .success:
            var saved = savedDisabledLoginItems().filter { !($0.name == item.name && $0.path == (item.executablePath ?? "")) }
            if remember, let path = item.executablePath, !path.isEmpty {
                saved.append(PerformanceLegacyLoginItem(name: item.name, path: path, hidden: item.opensHidden))
            }
            setSavedDisabledLoginItems(saved)
            return nil
        case .failure(let code, let message):
            return PerformanceAppleScriptRunner.deniedCodes.contains(code)
                ? "Allow Spruce to control System Events in System Settings › Privacy & Security › Automation."
                : message
        }
    }

    private func addLoginItem(_ item: PerformanceStartupItem) async -> String? {
        guard let path = item.executablePath, !path.isEmpty else {
            return "Spruce doesn't know where this item is, so it can't add it back."
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return "The item is no longer at \(path.abbreviatingHome)."
        }
        let result = await PerformanceAppleScriptRunner.run(PerformanceAppleScript.addLoginItemSource(path: path, hidden: item.opensHidden))
        switch result {
        case .success:
            setSavedDisabledLoginItems(savedDisabledLoginItems().filter { !($0.name == item.name && $0.path == path) })
            return nil
        case .failure(let code, let message):
            return PerformanceAppleScriptRunner.deniedCodes.contains(code)
                ? "Allow Spruce to control System Events in System Settings › Privacy & Security › Automation."
                : message
        }
    }

    // MARK: - Removing items

    /// Removes items for good: launchd jobs are stopped, then their plist goes to the Trash
    /// through `FileRemover` (recoverable). Classic login items are deleted from System Events.
    /// Files owned by the system stay in place but are left switched off.
    public func remove(_ items: [PerformanceStartupItem]) async -> RunOutcome {
        var failures: [ItemFailure] = []
        var succeeded: [String] = []
        var launchItems: [PerformanceStartupItem] = []

        for item in items {
            guard item.canRemove else {
                failures.append(ItemFailure(itemID: item.id, title: item.name,
                                            reason: "It's part of \(item.vendorName). Turn it off in System Settings, or uninstall the app."))
                continue
            }
            if item.kind == .loginItem {
                if let reason = await removeLoginItem(item, remember: false) {
                    // A switched-off item exists only in Spruce's list: forget it.
                    if !item.isEnabled {
                        forgetSavedLoginItem(item)
                        succeeded.append(item.id)
                    } else {
                        failures.append(ItemFailure(itemID: item.id, title: item.name, reason: reason))
                    }
                } else {
                    succeeded.append(item.id)
                }
            } else {
                launchItems.append(item)
            }
        }

        if !launchItems.isEmpty {
            let stopped = await stopForRemoval(launchItems)
            failures += stopped.failures
            let ready = launchItems.filter { stopped.succeeded.contains($0.id) }
            let trashed = await trashPlists(ready)
            succeeded += trashed.succeeded
            failures += trashed.failures
        }

        return RunOutcome(module: .performance, processedCount: succeeded.count, removedItemIDs: succeeded,
                          failures: failures,
                          summary: succeeded.isEmpty ? "Nothing was removed" : "Removed \(CountFormat.items(succeeded.count))")
    }

    private func forgetSavedLoginItem(_ item: PerformanceStartupItem) {
        setSavedDisabledLoginItems(savedDisabledLoginItems().filter { !($0.name == item.name && $0.path == (item.executablePath ?? "")) })
    }

    /// Stops jobs before their plist is moved: agents with `bootout` in your session,
    /// daemons with `bootout` + `disable` in one administrator prompt.
    private func stopForRemoval(_ items: [PerformanceStartupItem]) async -> (succeeded: Set<String>, failures: [ItemFailure]) {
        let uid = getuid()
        var ok = Set<String>()
        var failures: [ItemFailure] = []
        var rootInvocations: [PrivilegedRunner.Invocation] = []
        var rootItems: [PerformanceStartupItem] = []
        for item in items {
            guard let label = item.label, PerformanceLaunchctl.isSafeLabel(label), let domain = Self.launchDomain(for: item.kind) else {
                // Unloadable (broken or label-less) plists have nothing running; just move the file.
                if item.label == nil || item.isBroken { ok.insert(item.id) } else {
                    failures.append(ItemFailure(itemID: item.id, title: item.name, reason: "It has no valid launchd label."))
                }
                continue
            }
            let target = PerformanceLaunchctl.serviceTarget(domain: domain, uid: uid, label: label)
            if domain == .systemDaemon {
                rootInvocations.append(PrivilegedRunner.Invocation("/bin/launchctl", ["bootout", target]))
                rootInvocations.append(PrivilegedRunner.Invocation("/bin/launchctl", ["disable", target]))
                rootItems.append(item)
            } else {
                _ = await Shell.run("/bin/launchctl", ["bootout", target], timeout: 30)
                ok.insert(item.id)
            }
        }
        if !rootInvocations.isEmpty {
            do {
                try await PrivilegedRunner.shared.run(rootInvocations)
                for item in rootItems { ok.insert(item.id) }
            } catch {
                let reason = (error as? SpruceError) == .cancelled ? Self.cancelledDetail : error.localizedDescription
                failures += rootItems.map { ItemFailure(itemID: $0.id, title: $0.name, reason: reason) }
            }
        }
        return (ok, failures)
    }

    /// Moves plists to the Trash via `FileRemover` (launch-item permission only). When a file
    /// can't be moved (owned by the system), the job is switched off so it stays stopped.
    private func trashPlists(_ items: [PerformanceStartupItem]) async -> (succeeded: [String], failures: [ItemFailure]) {
        guard !items.isEmpty else { return ([], []) }
        var byPath: [String: PerformanceStartupItem] = [:]
        var scanItems: [ScanItem] = []
        for item in items {
            guard let plistPath = item.plistPath else { continue }
            let url = URL(fileURLWithPath: plistPath)
            let scanItem = ScanItem.file(url, size: PerformanceSystemProbe.fileSize(plistPath), safety: .review,
                                         deletion: .trash, title: item.name)
            byPath[scanItem.id] = item
            scanItems.append(scanItem)
        }
        let outcome = await FileRemover.shared.dispose(scanItems, module: .performance, options: .allowLaunchItems,
                                                       settings: SettingsStore.shared.settings)
        var succeeded = outcome.removedItemIDs.compactMap { byPath[$0]?.id }
        var failures: [ItemFailure] = []
        var keepOff: [(item: PerformanceStartupItem, reason: String)] = []
        for failure in outcome.failures {
            guard let item = byPath[failure.itemID] else { continue }
            if item.kind == .systemDaemon {
                // Already booted out and disabled as administrator.
                let folder = item.plistPath.map { ($0 as NSString).deletingLastPathComponent } ?? "/Library/LaunchDaemons"
                failures.append(ItemFailure(itemID: item.id, title: item.name,
                                            reason: "Switched off for good, but its file stays in \(folder): \(failure.reason)"))
            } else if item.label != nil {
                keepOff.append((item, failure.reason))
            } else {
                failures.append(ItemFailure(itemID: item.id, title: item.name, reason: "Couldn't move it to the Trash: \(failure.reason)"))
            }
        }
        if !keepOff.isEmpty {
            // bootout alone doesn't survive a restart; keep these switched off instead.
            let off = await toggleLaunchItems(keepOff.map { $0.item }, enable: false)
            for entry in keepOff {
                let reason = off.succeeded.contains(entry.item.id)
                    ? "Couldn't move it to the Trash (\(entry.reason)), so Spruce switched it off instead. It stays off after a restart."
                    : "Couldn't move it to the Trash: \(entry.reason)"
                failures.append(ItemFailure(itemID: entry.item.id, title: entry.item.name, reason: reason))
            }
        }
        // Clear launchd's override for user agents that are gone, so a reinstall isn't silently blocked.
        let uid = getuid()
        for item in items where succeeded.contains(item.id) && item.kind == .userAgent && !item.isEnabled {
            if let label = item.label, PerformanceLaunchctl.isSafeLabel(label) {
                _ = await Shell.run("/bin/launchctl", ["enable", "gui/\(uid)/\(label)"], timeout: 20)
            }
        }
        succeeded.sort()
        return (succeeded, failures)
    }
}
