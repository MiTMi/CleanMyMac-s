import AppKit
import Foundation
import SpruceCore
import SpruceMac
import SwiftUI

// MARK: - Updater

extension ApplicationsScreenModel {

    /// Checks once per visit; a check older than 30 minutes is repeated.
    func ensureUpdates() {
        guard updatesPhase != .loading else { return }
        if let checked = updatesCheckedAt, Date().timeIntervalSince(checked) < 30 * 60 { return }
        checkUpdates()
    }

    /// Checks Sparkle feeds, the App Store and Homebrew (network).
    func checkUpdates() {
        guard updatesPhase != .loading, !isInstallingUpdates else { return }
        setUpdatesPhase(.loading)
        setUpdatesProgress(ScanProgress(fraction: 0, message: "Checking for updates…"))
        let engine = self.engine
        let report: ProgressHandler = { p in
            Task { @MainActor [weak self] in
                guard let self, self.updatesPhase == .loading else { return }
                self.setUpdatesProgress(p)
            }
        }
        Task { [weak self] in
            let found = await engine.checkUpdates(progress: report)
            guard let self else { return }
            self.replaceUpdates(found, checkedAt: Date())
            self.setUpdatesPhase(.ready)
            if let selected = self.selectedUpdateID, !self.visibleUpdates.contains(where: { $0.id == selected }) {
                self.selectedUpdateID = nil
            }
            if self.selectedUpdateID == nil { self.selectedUpdateID = self.visibleUpdates.first?.id }
            self.selectedUpdateIDs = self.selectedUpdateIDs.filter { id in self.visibleUpdates.contains { $0.id == id } }
        }
    }

    /// Updates not ignored by the user, one per app.
    var visibleUpdates: [ApplicationsUpdate] {
        let s = settings
        let filtered = ApplicationsUpdateIgnore.filtered(allUpdates, ignoredItemIDs: s.ignoredItemIDs,
                                                         ignoredBundleIDs: s.ignoredBundleIDs)
        let q = updateSearch.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return filtered }
        return filtered.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Updates the user skipped or ignored (shown on request, can be restored).
    var ignoredUpdates: [ApplicationsUpdate] {
        let ids = Set(settings.ignoredItemIDs)
        var seen = Set<String>()
        return allUpdates.filter { update in
            (ids.contains(update.ignoreAppKey) || ids.contains(update.skipVersionKey)) && seen.insert(update.appPath).inserted
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Updates still to install (excludes ones installed during this session).
    var pendingUpdates: [ApplicationsUpdate] {
        let s = settings
        return ApplicationsUpdateIgnore.filtered(allUpdates, ignoredItemIDs: s.ignoredItemIDs, ignoredBundleIDs: s.ignoredBundleIDs)
            .filter { updateStatus[$0.id] != .updated }
    }

    var selectedUpdate: ApplicationsUpdate? {
        guard let id = selectedUpdateID else { return nil }
        return allUpdates.first { $0.id == id }
    }

    /// Homebrew updates ticked for a batch update.
    var checkedHomebrewUpdates: [ApplicationsUpdate] {
        visibleUpdates.filter { selectedUpdateIDs.contains($0.id) && $0.isUnattended && updateStatus[$0.id] != .updated }
    }

    func toggleUpdateCheck(_ update: ApplicationsUpdate) {
        guard update.isUnattended else { return }
        if selectedUpdateIDs.contains(update.id) {
            selectedUpdateIDs.remove(update.id)
        } else {
            selectedUpdateIDs.insert(update.id)
        }
    }

    func app(for update: ApplicationsUpdate) -> ApplicationsAppInfo? {
        apps.first { $0.path == update.appPath }
    }

    // MARK: Ignore

    func ignoreUpdates(of update: ApplicationsUpdate) {
        SettingsStore.shared.ignore(itemID: update.ignoreAppKey)
        selectedUpdateIDs.remove(update.id)
        if selectedUpdateID == update.id { selectedUpdateID = visibleUpdates.first?.id }
        toast = ApplicationsToast(message: "Updates for \(update.name) won't be shown again.")
    }

    func skipVersion(_ update: ApplicationsUpdate) {
        SettingsStore.shared.ignore(itemID: update.skipVersionKey)
        selectedUpdateIDs.remove(update.id)
        if selectedUpdateID == update.id { selectedUpdateID = visibleUpdates.first?.id }
        toast = ApplicationsToast(message: "Skipped \(update.name) \(update.availableVersion).")
    }

    func stopIgnoring(_ update: ApplicationsUpdate) {
        let keys: Set<String> = [update.ignoreAppKey, update.skipVersionKey]
        SettingsStore.shared.settings.ignoredItemIDs.removeAll { keys.contains($0) }
        selectedUpdateID = update.id
    }

    // MARK: Actions

    /// Hand-off actions (App Store, the app's own updater, download page, release notes).
    func perform(_ action: ApplicationsEngine.UpdateAction, for update: ApplicationsUpdate) {
        engine.open(update, action: action)
    }

    /// Installs Homebrew updates, asking first when an app is open.
    func installHomebrew(_ updates: [ApplicationsUpdate]) {
        let targets = updates.filter { $0.isUnattended && updateStatus[$0.id] != .updated }
        guard !targets.isEmpty, !isInstallingUpdates else { return }
        let engine = self.engine
        let targetApps = targets.compactMap { app(for: $0) }
        Task { [weak self] in
            let open = await engine.runningApps(among: targetApps)
            guard let self else { return }
            if open.isEmpty {
                self.runHomebrew(targets)
            } else {
                self.updateQuitPrompt = ApplicationsUpdateQuitPrompt(updates: targets, openApps: open)
            }
        }
    }

    /// Quits the open apps (normally, so they can save), then updates.
    func quitAndInstall() {
        guard let prompt = updateQuitPrompt else { return }
        updateQuitPrompt = nil
        let engine = self.engine
        Task { [weak self] in
            let stillOpen = await engine.quit(prompt.openApps)
            guard let self else { return }
            let blocked = Set(stillOpen.map(\.path))
            for update in prompt.updates where blocked.contains(update.appPath) {
                self.setStatus(.failed("Still open — quit it and try again"), for: update.id)
            }
            self.runHomebrew(prompt.updates.filter { !blocked.contains($0.appPath) })
        }
    }

    /// Updates only the apps that are not open.
    func installSkippingOpen() {
        guard let prompt = updateQuitPrompt else { return }
        updateQuitPrompt = nil
        let open = Set(prompt.openApps.map(\.path))
        runHomebrew(prompt.updates.filter { !open.contains($0.appPath) })
    }

    func cancelQuitPrompt() {
        updateQuitPrompt = nil
    }

    /// Runs `brew upgrade --cask` for each update, one at a time.
    private func runHomebrew(_ updates: [ApplicationsUpdate]) {
        guard !updates.isEmpty else { return }
        setInstalling(true)
        for update in updates { setStatus(.queued, for: update.id) }
        let engine = self.engine
        Task { [weak self] in
            guard let self else { return }
            var succeeded: [ApplicationsUpdate] = []
            var failures: [ItemFailure] = []
            for update in updates {
                self.setStatus(.updating, for: update.id)
                let result = await engine.applyHomebrewUpdate(update)
                self.setStatus(result.ok ? .updated : .failed(result.message), for: update.id)
                if result.ok {
                    succeeded.append(update)
                } else {
                    failures.append(ItemFailure(itemID: update.id, title: update.name, reason: result.message))
                }
            }
            self.setInstalling(false)
            self.selectedUpdateIDs.subtract(succeeded.map(\.id))
            // Versions on disk changed: refresh the catalog rows of updated apps.
            let refreshed = engine.lastApps
            for update in succeeded {
                if let fresh = refreshed.first(where: { $0.path == update.appPath }) {
                    self.replaceApp(fresh)
                }
            }
            let outcome = RunOutcome(module: .applications, processedCount: succeeded.count,
                                     removedItemIDs: succeeded.map(\.id), failures: failures,
                                     summary: succeeded.isEmpty
                                        ? "No apps were updated"
                                        : "Updated \(CountFormat.items(succeeded.count, singular: "app")) with Homebrew")
            if !succeeded.isEmpty { HistoryStore.shared.record(outcome, kind: .update) }
            if failures.isEmpty {
                self.toast = ApplicationsToast(message: outcome.summary)
            } else if succeeded.isEmpty, failures.count == 1, let only = failures.first {
                self.toast = ApplicationsToast(message: "\(only.title): \(only.reason)", isError: true)
            } else {
                self.toast = ApplicationsToast(message: "\(outcome.summary). \(CountFormat.items(failures.count, singular: "update")) failed.",
                                               isError: true)
            }
        }
    }

    func status(of update: ApplicationsUpdate) -> ApplicationsUpdateRowStatus? {
        updateStatus[update.id]
    }

    // MARK: Extensions

    func loadExtensions() {
        guard extensionsPhase != .loading else { return }
        setExtensionsPhase(.loading)
        let engine = self.engine
        Task { [weak self] in
            let found = await engine.loadExtensions()
            guard let self else { return }
            self.replaceExtensions(found)
            self.setExtensionsPhase(.ready)
        }
    }

    var visibleExtensions: [ApplicationsExtensionInfo] {
        let q = extensionSearch.trimmingCharacters(in: .whitespaces)
        return extensions.filter { ext in
            if let kind = extensionKind, ext.kind != kind { return false }
            guard !q.isEmpty else { return true }
            return [ext.name, ext.hostAppName ?? "", ext.identifier ?? "", ext.category ?? ""].contains {
                $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    func extensionCount(_ kind: ApplicationsExtensionKind?) -> Int {
        guard let kind else { return extensions.count }
        return extensions.filter { $0.kind == kind }.count
    }

    /// Kinds that have at least one item, in catalog order.
    var extensionKinds: [ApplicationsExtensionKind] {
        ApplicationsExtensionKind.allCases.filter { kind in extensions.contains { $0.kind == kind } }
    }

    /// Turns an app extension on or off and reads the state back from macOS.
    func setExtension(_ ext: ApplicationsExtensionInfo, enabled: Bool) {
        guard ext.canToggle, !busyExtensionIDs.contains(ext.id) else { return }
        setBusy(true, extensionID: ext.id)
        updateExtension(ext.id) { $0.isEnabled = enabled }
        let engine = self.engine
        Task { [weak self] in
            let state = await engine.setExtension(ext, enabled: enabled)
            guard let self else { return }
            self.setBusy(false, extensionID: ext.id)
            let actual = state ?? ext.isEnabled
            self.updateExtension(ext.id) { $0.isEnabled = actual }
            if actual != enabled {
                self.toast = ApplicationsToast(message: "macOS didn't change \(ext.name). Try again in System Settings › Login Items & Extensions.",
                                               isError: true)
            }
        }
    }

    func requestExtensionRemoval(_ ext: ApplicationsExtensionInfo) {
        guard ext.canRemove else { return }
        extensionRemoval = ext
    }

    /// Moves the confirmed plug-in to the Trash.
    func confirmExtensionRemoval() {
        guard let ext = extensionRemoval else { return }
        extensionRemoval = nil
        setBusy(true, extensionID: ext.id)
        let engine = self.engine
        Task { [weak self] in
            let outcome = await engine.removeExtensions([ext])
            guard let self else { return }
            self.setBusy(false, extensionID: ext.id)
            if outcome.removedItemIDs.contains(ext.id) {
                self.replaceExtensions(self.extensions.filter { $0.id != ext.id })
                HistoryStore.shared.record(outcome, kind: .clean)
                self.toast = ApplicationsToast(message: "Moved \(ext.name) to the Trash.")
            } else {
                let reason = outcome.failures.first?.reason ?? "It couldn't be moved to the Trash."
                self.toast = ApplicationsToast(message: "\(ext.name): \(reason)", isError: true)
            }
        }
    }

    func revealExtension(_ ext: ApplicationsExtensionInfo) {
        if let path = ext.path ?? ext.hostAppPath { engine.reveal(path) }
    }
}
