import AppKit
import Foundation
import SpruceCore

extension ProtectionEngine {
    /// Removes selected threats:
    /// 1. launch jobs are unloaded first (`launchctl bootout` in the user's GUI domain, or the
    ///    system domain through one administrator prompt, which also disables the job);
    /// 2. running apps that are part of a threat are force-quit;
    /// 3. the files go to the Trash through `FileRemover` (launch items and app bundles allowed);
    /// 4. malicious crontab lines are taken out of the user's crontab.
    /// Anything Spruce can't remove itself comes back as a failure that says what to do.
    func removeThreats(_ items: [ScanItem], progress: @escaping ProgressHandler) async -> RunOutcome {
        let settings = await ProtectionMac.settings()
        let plans = items.compactMap(ProtectionRemovalPlan.init(item:))
        var failures: [ItemFailure] = []
        var removed: [String] = []
        var restartAdvised = false

        // Sort the plans by what removing them involves.
        var filePlans: [ProtectionRemovalPlan] = []
        var cronPlans: [ProtectionRemovalPlan] = []
        for plan in plans {
            if plan.kind == .cronJob, plan.cronLine != nil {
                cronPlans.append(plan)
            } else if plan.isLaunchJob {
                filePlans.append(plan)
            } else if let note = plan.manualNote {
                failures.append(ItemFailure(itemID: plan.itemID, title: plan.title, reason: note))
            } else if plan.primaryPath == nil {
                failures.append(ItemFailure(itemID: plan.itemID, title: plan.title,
                                            reason: "There's no file Spruce can remove for this item."))
            } else {
                filePlans.append(plan)
            }
        }

        // 1. Stop launch jobs so nothing respawns while their files move.
        let uid = getuid()
        let launchPlans = filePlans.filter(\.isLaunchJob)
        let userPlans = launchPlans.filter { $0.launchDomain != .system }
        if !userPlans.isEmpty {
            progress(ScanProgress(fraction: 0.05, message: "Stopping startup items…"))
        }
        for plan in userPlans {
            guard let plist = plan.primaryPath else { continue }
            let result = await Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", plist], timeout: 20)
            OperationLog.shared.record(module: .protection, action: "launchctl-bootout",
                                       result: result.status == 0 ? "ok" : "not-loaded", detail: plist)
        }
        let systemPlans = launchPlans.filter { $0.launchDomain == .system }
        if !systemPlans.isEmpty {
            progress(ScanProgress(fraction: 0.1, message: "Waiting for administrator approval to stop system jobs…"))
            var invocations: [PrivilegedRunner.Invocation] = []
            for plan in systemPlans {
                guard let plist = plan.primaryPath else { continue }
                invocations.append(PrivilegedRunner.Invocation("/bin/launchctl", ["bootout", "system", plist]))
                if let label = plan.launchLabel, !label.isEmpty {
                    invocations.append(PrivilegedRunner.Invocation("/bin/launchctl", ["disable", "system/\(label)"]))
                }
            }
            do {
                try await PrivilegedRunner.shared.run(invocations)
                restartAdvised = true
                for plan in systemPlans {
                    OperationLog.shared.record(module: .protection, action: "launchctl-bootout-system", result: "ok",
                                               detail: "\(plan.primaryPath ?? "") \(plan.launchLabel ?? "")")
                }
            } catch {
                let reason = (error as? SpruceError) == .cancelled
                    ? "Administrator approval was cancelled, so this system job was left running."
                    : "Couldn't stop this system job: \(error.localizedDescription)"
                let skipped = Set(systemPlans.map(\.itemID))
                for plan in systemPlans {
                    failures.append(ItemFailure(itemID: plan.itemID, title: plan.title, reason: reason))
                }
                filePlans.removeAll { skipped.contains($0.itemID) }
            }
        }

        // 2. Quit threat apps that are running (their bundles can't be trashed cleanly otherwise).
        let bundles = filePlans
            .flatMap { plan -> [String] in [plan.primaryPath].compactMap { $0 } + plan.relatedPaths }
            .filter { $0.lowercased().hasSuffix(".app") }
        if !bundles.isEmpty {
            let quit = await ProtectionMac.forceQuitApps(inside: bundles)
            if quit > 0 { restartAdvised = true }
        }

        // 3. Move the files to the Trash.
        var disposeItems: [ScanItem] = []
        var seen = Set<String>()
        for plan in filePlans {
            guard let primary = plan.primaryPath else { continue }
            var item = ScanItem.file(URL(fileURLWithPath: primary), size: plan.size, safety: .safe, deletion: .trash,
                                     title: plan.title)
            if let inode = plan.inode { item.metadata[ProtectionMetaKey.inode] = inode }
            if seen.insert(item.id).inserted { disposeItems.append(item) }
            for related in plan.relatedPaths {
                let extra = ScanItem.file(URL(fileURLWithPath: related), size: 0, safety: .safe, deletion: .trash,
                                          title: "\(plan.title) · \((related as NSString).lastPathComponent)")
                if seen.insert(extra.id).inserted { disposeItems.append(extra) }
            }
        }
        var freed: Int64 = 0
        var trashedAny = false
        var stillPresent: [ProtectionRemovalPlan] = []
        if !disposeItems.isEmpty {
            let outcome = await FileRemover.shared.dispose(disposeItems, module: .protection,
                                                           options: [.allowLaunchItems, .allowAppBundles],
                                                           settings: settings, progress: { p in
                progress(ScanProgress(fraction: 0.2 + 0.7 * (p.fraction ?? 0), message: p.message, current: p.current,
                                      bytesFound: p.bytesFound))
            })
            freed = outcome.freedBytes
            let done = Set(outcome.removedItemIDs)
            var reasons: [String: String] = [:]
            for failure in outcome.failures where reasons[failure.itemID] == nil {
                reasons[failure.itemID] = failure.reason
            }
            for plan in filePlans {
                guard let primary = plan.primaryPath else { continue }
                let primaryID = URL(fileURLWithPath: primary).standardizedFileURL.path
                if done.contains(primaryID) {
                    removed.append(plan.itemID)
                    trashedAny = true
                    for related in plan.relatedPaths {
                        let relatedID = URL(fileURLWithPath: related).standardizedFileURL.path
                        if let reason = reasons[relatedID] {
                            failures.append(ItemFailure(itemID: plan.itemID + "|" + relatedID,
                                                        title: "\(plan.title) · \((related as NSString).lastPathComponent)",
                                                        reason: "Its program at \(related.abbreviatingHome) stayed: \(reason)"))
                        }
                    }
                } else {
                    let reason = reasons[primaryID] ?? "It couldn't be moved to the Trash."
                    if plan.isLaunchJob {
                        stillPresent.append(plan)
                        failures.append(ItemFailure(
                            itemID: plan.itemID, title: plan.title,
                            reason: "Stopped and turned off, so it won't start again, but the file stayed (\(reason)). "
                                + "Reveal it in Finder and drag it to the Trash; macOS will ask for your password."))
                    } else {
                        failures.append(ItemFailure(itemID: plan.itemID, title: plan.title, reason: reason))
                    }
                }
            }
        }

        // Launch agents whose file stayed are disabled so they don't come back at next login.
        for plan in stillPresent where plan.launchDomain != .system {
            guard let label = plan.launchLabel, !label.isEmpty else { continue }
            let result = await Shell.run("/bin/launchctl", ["disable", "gui/\(uid)/\(label)"], timeout: 20)
            OperationLog.shared.record(module: .protection, action: "launchctl-disable",
                                       result: result.status == 0 ? "ok" : "error", detail: label)
        }

        // 4. Scheduled jobs.
        if !cronPlans.isEmpty {
            progress(ScanProgress(fraction: 0.92, message: "Updating your scheduled jobs…"))
            let lines = Set(cronPlans.compactMap(\.cronLine))
            if let current = await Self.readCrontab() {
                let updated = ProtectionCron.removing(lines, from: current)
                let result = await ProtectionMac.run("/usr/bin/crontab", ["-"], input: Data(updated.utf8))
                if result.status == 0 {
                    removed.append(contentsOf: cronPlans.map(\.itemID))
                    for line in lines {
                        OperationLog.shared.record(module: .protection, action: "crontab-remove", result: "ok", detail: line)
                    }
                } else {
                    let reason = ProtectionMac.message(from: result, fallback: "Your crontab couldn't be updated.")
                    for plan in cronPlans {
                        failures.append(ItemFailure(itemID: plan.itemID, title: plan.title, reason: reason))
                    }
                }
            } else {
                // No crontab any more: the jobs are already gone.
                removed.append(contentsOf: cronPlans.map(\.itemID))
            }
        }

        progress(ScanProgress(fraction: 1, message: "Done", bytesFound: freed))
        var summary = removed.isEmpty
            ? "No threats were removed"
            : "Removed \(CountFormat.items(removed.count, singular: "threat"))."
        if trashedAny {
            summary += " Their files are in the Trash."
        }
        if restartAdvised && !removed.isEmpty {
            summary += " Restart your Mac to make sure nothing is left running."
        }
        return RunOutcome(module: .protection, freedBytes: freed, processedCount: removed.count, removedItemIDs: removed,
                          failures: failures, summary: summary)
    }
}
