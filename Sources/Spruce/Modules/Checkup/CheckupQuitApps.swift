import AppKit
import SpruceCore
import SpruceMac

/// Finds the open apps that hold up selected Checkup items, for the "Quit these apps
/// first?" sheet shown before a run:
///
/// * Cleanup — data of an app that is running (rows with an owner; the engine skips them
///   while the app is open, the same check the Cleanup module asks about);
/// * Performance — maintenance tasks that need an app closed (Mail);
/// * Applications — updates of apps that are open.
@MainActor
enum CheckupQuitApps {
    static func blockingApps(plan: [ModuleID], contributors: [ModuleID: CheckupContributor]) -> [CheckupBlockingApp] {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            !app.isTerminated && app.activationPolicy != .prohibited && app.bundleIdentifier != nil
        }
        guard !running.isEmpty else { return [] }
        var needs: [CheckupAppNeed] = []

        func need(_ app: NSRunningApplication, _ module: ModuleID, _ item: ScanItem, label: String? = nil) -> CheckupAppNeed {
            let bundleID = app.bundleIdentifier ?? ""
            return CheckupAppNeed(processID: app.processIdentifier, bundleID: bundleID,
                                  name: app.localizedName ?? bundleID, appPath: app.bundleURL?.path,
                                  module: module, itemID: item.id, label: label)
        }

        for module in plan {
            guard let contributor = contributors[module] else { continue }
            let selected = contributor.checkupReview.selectedItems
            guard !selected.isEmpty else { continue }
            switch module {
            case .cleanup:
                for item in selected {
                    guard let owner = item.metadata[CleanupMetadataKey.owner] else { continue }
                    for app in running where CleanupOwnership.matches(owner: owner, bundleID: app.bundleIdentifier ?? "") {
                        needs.append(need(app, module, item))
                    }
                }
            case .performance:
                for item in selected {
                    guard let id = PerformanceTaskItems.taskIDs(in: [item]).first else { continue }
                    let definition = PerformanceTaskCatalog.definition(id)
                    for required in definition.appsToQuit {
                        for app in running where app.bundleIdentifier == required.bundleID {
                            needs.append(need(app, module, item, label: definition.title))
                        }
                    }
                }
            case .applications:
                for item in selected where item.metadata[ApplicationsMeta.kind] == "update" {
                    guard let path = item.metadata[ApplicationsMeta.appPath] else { continue }
                    let key = (path as NSString).standardizingPath
                    for app in running {
                        guard let url = app.bundleURL, (url.path as NSString).standardizingPath == key else { continue }
                        needs.append(need(app, module, item, label: "Update"))
                    }
                }
            default:
                break
            }
        }
        return CheckupQuitPlan.blockingApps(needs, ownProcessID: ProcessInfo.processInfo.processIdentifier)
    }
}
