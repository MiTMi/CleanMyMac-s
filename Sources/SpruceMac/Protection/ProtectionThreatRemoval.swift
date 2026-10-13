import AppKit
import Foundation
import SpruceCore

extension ProtectionEngine {
    /// Removes selected threats:
    /// 1. launch jobs are stopped first, but only when launchd confirms the job was loaded
    ///    from the flagged plist and its label passes `ProtectionLaunchControl` (never a
    ///    label macOS itself uses). User agents use `launchctl bootout gui/<uid>/<label>`,
    ///    system daemons one administrator prompt; every stop is checked with `launchctl print`;
    /// 2. running apps that are part of a threat are asked to quit (only known threats are
    ///    force-quit, and only if they refuse);
    /// 3. the files go to the Trash through `FileRemover` (launch items and app bundles
    ///    allowed; administrator-owned items with one password prompt);
    /// 4. jobs whose file stayed are turned off in launchd where that is safe, checked with
    ///    `launchctl print-disabled`;
    /// 5. malicious crontab lines are taken out of the user's crontab.
    /// Anything Spruce can't finish comes back as a failure that says what actually happened.
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
        var jobs: [String: ProtectionJobState] = [:]
        if !launchPlans.isEmpty {
            progress(ScanProgress(fraction: 0.03, message: "Checking startup items…"))
            let systemLabels = (try? await ProtectionMac.runBlocking { _ in ProtectionLaunchControl.systemLabels() }) ?? []
            for plan in launchPlans {
                jobs[plan.itemID] = await Self.inspectJob(plan, uid: uid, systemLabels: systemLabels)
            }
        }

        let userStops = launchPlans.filter { plan in jobs[plan.itemID].map { !$0.isSystem && $0.shouldStop } ?? false }
        if !userStops.isEmpty {
            progress(ScanProgress(fraction: 0.06, message: "Stopping startup items…"))
        }
        for plan in userStops {
            guard let target = jobs[plan.itemID]?.serviceTarget else { continue }
            let result = await Shell.run("/bin/launchctl", ["bootout", target], timeout: 20)
            jobs[plan.itemID]?.attemptedStop = true
            OperationLog.shared.record(module: .protection, action: "launchctl-bootout",
                                       result: result.status == 0 ? "ok" : "error", detail: target)
        }

        let systemStops = launchPlans.filter { plan in jobs[plan.itemID].map { $0.isSystem && $0.shouldStop } ?? false }
        if !systemStops.isEmpty {
            progress(ScanProgress(fraction: 0.1, message: "Waiting for administrator approval to stop system jobs…"))
            let targets = systemStops.compactMap { jobs[$0.itemID]?.serviceTarget }
            do {
                try await PrivilegedRunner.shared.run(targets.map { PrivilegedRunner.Invocation("/bin/launchctl", ["bootout", $0]) })
                for plan in systemStops { jobs[plan.itemID]?.attemptedStop = true }
            } catch {
                let reason = (error as? SpruceError) == .cancelled
                    ? "Administrator approval was cancelled, so this system job was left running and its files were kept."
                    : "Couldn't stop this system job (\(error.localizedDescription)), so its files were kept."
                let skipped = Set(systemStops.map(\.itemID))
                for plan in systemStops {
                    failures.append(ItemFailure(itemID: plan.itemID, title: plan.title, reason: reason))
                }
                filePlans.removeAll { skipped.contains($0.itemID) }
            }
        }

        // Check what launchd says now (the commands above don't report failures reliably).
        for (id, job) in jobs where job.attemptedStop {
            guard let label = job.label else { continue }
            let after = await Self.loadState(domain: job.domainTarget, label: label)
            switch after {
            case .notLoaded: jobs[id]?.stopVerified = true
            case .loaded: jobs[id]?.stopVerified = false
            case .unknown: jobs[id]?.stopVerified = nil
            }
            OperationLog.shared.record(module: .protection, action: "launchctl-verify-stop",
                                       result: after == .notLoaded ? "stopped" : "still-loaded",
                                       detail: job.serviceTarget ?? job.plistPath)
            if job.isSystem && after == .notLoaded { restartAdvised = true }
        }

        // 2. Quit threat apps that are running (their bundles can't be trashed cleanly otherwise).
        var quitBundles: [String] = []
        var forceBundles: [String] = []
        for plan in filePlans {
            let bundles = ([plan.primaryPath].compactMap { $0 } + plan.relatedPaths).filter { $0.lowercased().hasSuffix(".app") }
            quitBundles += bundles
            if plan.isKnownThreat { forceBundles += bundles }
        }
        if !quitBundles.isEmpty {
            let quit = await ProtectionMac.quitApps(inside: quitBundles, forceBundlePaths: forceBundles)
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
        var trashed = (bytes: Int64(0), count: 0, runIDs: [UUID]())
        var trashedAny = false
        var stillPresent: [(plan: ProtectionRemovalPlan, reason: String)] = []
        if !disposeItems.isEmpty {
            // Administrator-owned threats (/Library/LaunchDaemons, helper tools…) are moved
            // to the Trash with one password prompt; PathGuard still checks every path.
            let outcome = await FileRemover.shared.dispose(disposeItems, module: .protection,
                                                           options: [.allowLaunchItems, .allowAppBundles],
                                                           settings: settings, escalate: true, progress: { p in
                progress(ScanProgress(fraction: 0.2 + 0.65 * (p.fraction ?? 0), message: p.message, current: p.current,
                                      bytesFound: p.bytesFound))
            })
            freed = outcome.freedBytes
            trashed = (bytes: outcome.trashedBytes, count: outcome.trashedCount, runIDs: outcome.trashRunIDs)
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
                    if let job = jobs[plan.itemID] {
                        switch job.runState {
                        case .running:
                            restartAdvised = true
                            let why = job.policy.stopRefusal.map { " \($0)." } ?? ""
                            failures.append(ItemFailure(itemID: plan.itemID + "|running", title: plan.title,
                                                        reason: "Moved to the Trash, but it is still running.\(why) Restart your Mac to stop it."))
                        case .unknown:
                            restartAdvised = true
                        case .stopped, .notRunning:
                            break
                        }
                    }
                } else {
                    let reason = reasons[primaryID] ?? "It couldn't be moved to the Trash."
                    if plan.isLaunchJob {
                        stillPresent.append((plan, reason))
                    } else {
                        failures.append(ItemFailure(itemID: plan.itemID, title: plan.title, reason: reason))
                    }
                }
            }
        }

        // 4. Jobs whose file stayed are turned off, so they don't come back at the next
        //    login or restart — only where the label is safe to turn off.
        if !stillPresent.isEmpty {
            progress(ScanProgress(fraction: 0.88, message: "Turning off startup items that stayed…"))
            await disableJobs(stillPresent.map(\.plan), jobs: &jobs, uid: uid)
            for (plan, reason) in stillPresent {
                let job = jobs[plan.itemID]
                if job?.runState == .running || job?.runState == .unknown { restartAdvised = true }
                failures.append(ItemFailure(itemID: plan.itemID, title: plan.title,
                                            reason: Self.stillPresentReason(job: job, fileReason: reason)))
            }
        }

        // 5. Scheduled jobs.
        if !cronPlans.isEmpty {
            progress(ScanProgress(fraction: 0.94, message: "Updating your scheduled jobs…"))
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
                          failures: failures, summary: summary,
                          trashedBytes: trashed.bytes, trashedCount: trashed.count, trashRunIDs: trashed.runIDs)
    }

    // MARK: launchd

    /// Reads the flagged job's label again (it may have changed since the scan), decides
    /// what Spruce may do with it, and asks launchd whether — and from where — it is loaded.
    static func inspectJob(_ plan: ProtectionRemovalPlan, uid: uid_t, systemLabels: Set<String>) async -> ProtectionJobState {
        let plist = plan.primaryPath ?? ""
        let isSystem = plan.launchDomain == .system
        let label: String?
        if FileWalker.entry(at: plist) != nil {
            label = ProtectionLaunchItem.parse(path: plist, domain: plan.launchDomain ?? .user, kind: plan.kind,
                                               home: NSHomeDirectory()).label
        } else {
            label = plan.launchLabel
        }
        let catalogMatched = label.map { ProtectionThreatCatalog.standard.matchLabel($0) != nil } ?? false
        let policy = ProtectionLaunchControl.policy(plistPath: plist, label: label, systemLabels: systemLabels,
                                                    catalogMatchedLabel: catalogMatched)
        var job = ProtectionJobState(plistPath: plist, domainTarget: isSystem ? "system" : "gui/\(uid)", isSystem: isSystem,
                                     policy: policy, before: .unknown)
        if let label = policy.label, ProtectionLaunchControl.isSafeLabel(label) {
            job.before = await loadState(domain: job.domainTarget, label: label)
        }
        return job
    }

    /// `launchctl print <domain>/<label>` (read-only, no administrator rights needed).
    static func loadState(domain: String, label: String) async -> ProtectionLaunchControl.LoadState {
        let result = await Shell.run("/bin/launchctl", ["print", "\(domain)/\(label)"], timeout: 15)
        return ProtectionLaunchControl.loadState(printStatus: result.status, output: result.stdout + "\n" + result.stderr)
    }

    /// Turns off the labels of jobs whose file stayed (where `ProtectionLaunchControl`
    /// allows it), then checks launchd's overrides to see what really happened.
    private func disableJobs(_ plans: [ProtectionRemovalPlan], jobs: inout [String: ProtectionJobState], uid: uid_t) async {
        var userTargets: [String: String] = [:]     // itemID → service target
        var systemTargets: [String: String] = [:]
        for plan in plans {
            guard let job = jobs[plan.itemID], job.policy.mayDisable, let target = job.serviceTarget else { continue }
            if job.isSystem { systemTargets[plan.itemID] = target } else { userTargets[plan.itemID] = target }
        }
        for (id, target) in userTargets {
            let result = await Shell.run("/bin/launchctl", ["disable", target], timeout: 20)
            jobs[id]?.attemptedDisable = true
            OperationLog.shared.record(module: .protection, action: "launchctl-disable",
                                       result: result.status == 0 ? "ok" : "error", detail: target)
        }
        if !systemTargets.isEmpty {
            let invocations = systemTargets.values.sorted().map { PrivilegedRunner.Invocation("/bin/launchctl", ["disable", $0]) }
            do {
                try await PrivilegedRunner.shared.run(invocations)
                for id in systemTargets.keys { jobs[id]?.attemptedDisable = true }
            } catch {
                for id in systemTargets.keys {
                    jobs[id]?.disableError = (error as? SpruceError) == .cancelled
                        ? "Administrator approval was cancelled, so it wasn't turned off"
                        : "It couldn't be turned off (\(error.localizedDescription))"
                }
            }
        }
        guard jobs.values.contains(where: \.attemptedDisable) else { return }
        var userOverrides: [String: Bool]?
        var systemOverrides: [String: Bool]?
        if !userTargets.isEmpty { userOverrides = await Self.overrides(domain: "gui/\(uid)") }
        if !systemTargets.isEmpty { systemOverrides = await Self.overrides(domain: "system") }
        for (id, job) in jobs where job.attemptedDisable {
            guard let label = job.label else { continue }
            let map = job.isSystem ? systemOverrides : userOverrides
            jobs[id]?.disableVerified = map?[label] == true
            OperationLog.shared.record(module: .protection, action: "launchctl-verify-disable",
                                       result: map?[label] == true ? "disabled" : "not-disabled",
                                       detail: job.serviceTarget ?? job.plistPath)
        }
    }

    /// launchd's enable/disable overrides for a domain, nil when they can't be read.
    static func overrides(domain: String) async -> [String: Bool]? {
        let result = await Shell.run("/bin/launchctl", ["print-disabled", domain], timeout: 20)
        guard result.status == 0 else { return nil }
        return ProtectionLaunchControl.disabledOverrides(fromPrintDisabled: result.stdout)
    }

    /// What happened to a launch job whose file couldn't be moved to the Trash.
    static func stillPresentReason(job: ProtectionJobState?, fileReason: String) -> String {
        let reveal = "Reveal it in Finder and drag it to the Trash; macOS will ask for your password."
        guard let job else {
            return "Its file stayed (\(fileReason)). \(reveal)"
        }
        let turnedOff = job.disableVerified == true
        var notes: [String] = []
        if !turnedOff {
            if let why = job.disableError ?? (job.attemptedDisable ? "macOS didn't accept turning it off" : job.policy.disableRefusal) {
                notes.append(why + ".")
            }
        }
        let headline: String
        switch job.runState {
        case .stopped, .notRunning:
            if turnedOff {
                headline = "Stopped and turned off, so it won't start again, but its file stayed (\(fileReason))."
            } else if job.runState == .stopped {
                headline = "Stopped for now, but its file stayed (\(fileReason)), so it will start again at the next login or restart."
            } else {
                headline = "It isn't running, but its file stayed (\(fileReason)), so it may start at the next login or restart."
            }
            return ([headline] + notes + [reveal]).joined(separator: " ")
        case .running, .unknown:
            if turnedOff {
                headline = "Turned off, so it won't start again after a restart, but it is still running and its file stayed (\(fileReason))."
            } else {
                headline = "It couldn't be stopped and its file stayed (\(fileReason))."
                if let stopRefusal = job.policy.stopRefusal, !notes.contains(stopRefusal + ".") { notes.insert(stopRefusal + ".", at: 0) }
            }
            return ([headline] + notes + [reveal, "Then restart your Mac."]).joined(separator: " ")
        }
    }
}

/// One flagged launch job during removal: what Spruce may do, what launchd reported, and
/// what was verified afterwards.
struct ProtectionJobState {
    enum RunState {
        /// launchd has no job from this plist.
        case notRunning
        /// It was loaded and launchd confirms it is gone now.
        case stopped
        /// It is (still) loaded from this plist.
        case running
        /// launchd couldn't tell.
        case unknown
    }

    var plistPath: String
    /// "gui/<uid>" or "system".
    var domainTarget: String
    var isSystem: Bool
    var policy: ProtectionLaunchControl.Policy
    /// launchd's state before Spruce did anything.
    var before: ProtectionLaunchControl.LoadState
    var attemptedStop = false
    /// After `bootout`: true = gone, false = still loaded, nil = unknown.
    var stopVerified: Bool?
    var attemptedDisable = false
    var disableVerified: Bool?
    var disableError: String?

    var label: String? { policy.label }
    var serviceTarget: String? { label.map { "\(domainTarget)/\($0)" } }

    var shouldStop: Bool {
        serviceTarget != nil && ProtectionLaunchControl.shouldStop(policy: policy, plistPath: plistPath, state: before)
    }

    var runState: RunState {
        if attemptedStop {
            switch stopVerified {
            case true?: return .stopped
            case false?: return .running
            case nil: return .unknown
            }
        }
        switch before {
        case .notLoaded:
            return .notRunning
        case .loaded(let path):
            if ProtectionLaunchControl.isLoaded(from: plistPath, state: before) { return .running }
            // Another job with this label is loaded from elsewhere: this plist isn't running.
            return path == nil ? .unknown : .notRunning
        case .unknown:
            return .unknown
        }
    }
}
