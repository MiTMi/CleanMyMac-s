import AppKit
import Foundation
import SpruceCore

/// Lists app extensions (PlugInKit) and plug-in files, turns extensions on/off and removes plug-ins.
enum ApplicationsExtensionManager {
    static let pluginkit = "/usr/bin/pluginkit"

    static func load() async -> [ApplicationsExtensionInfo] {
        let result = await Shell.run(pluginkit, ["-mAvvv"], timeout: 60)
        let appExtensions = ApplicationsPluginKit.extensions(from: ApplicationsPluginKit.parse(result.stdout))
            .filter { ext in
                // Only extensions whose host app still exists.
                guard let path = ext.path else { return true }
                return FileManager.default.fileExists(atPath: path)
            }
        let files = await ApplicationsMac.background {
            ApplicationsExtensionCatalog.files(locations: ApplicationsExtensionCatalog.locations(),
                                               info: ApplicationsExtensionCatalog.bundleInfo(atPath:))
        }
        return (appExtensions + files).sorted {
            if $0.kind != $1.kind {
                return ApplicationsExtensionKind.allCases.firstIndex(of: $0.kind)! < ApplicationsExtensionKind.allCases.firstIndex(of: $1.kind)!
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// `pluginkit -e use|ignore -i <id>`; returns the state read back afterwards.
    static func setEnabled(_ ext: ApplicationsExtensionInfo, enabled: Bool) async -> Bool? {
        guard ext.canToggle, let identifier = ext.identifier,
              ApplicationsTokens.isReverseDNS(identifier, minimumComponents: 2) else { return nil }
        _ = await Shell.run(pluginkit, ["-e", enabled ? "use" : "ignore", "-i", identifier], timeout: 30)
        let check = await Shell.run(pluginkit, ["-mAvvv", "-i", identifier], timeout: 30)
        let entries = ApplicationsPluginKit.parse(check.stdout).filter { $0.identifier == identifier }
        return entries.first?.isEnabled
    }

    /// Moves plug-in files to the Trash through `FileRemover`.
    static func remove(_ extensions: [ApplicationsExtensionInfo], progress: ProgressHandler?) async -> RunOutcome {
        let settings = await ApplicationsMac.settings()
        let removable = extensions.filter(\.canRemove)
        let items: [ScanItem] = await ApplicationsMac.background {
            removable.compactMap { ext -> ScanItem? in
                guard let path = ext.path else { return nil }
                let measured = ApplicationsMeasured.measure(path)
                var meta: [String: String] = [ApplicationsMeta.kind: "extension." + ext.kind.rawValue]
                if let inode = measured.inode { meta[ApplicationsMeta.inode] = String(inode) }
                var item = ScanItem.file(URL(fileURLWithPath: path), size: measured.bytes, itemCount: measured.files,
                                         safety: .review, title: ext.name, metadata: meta)
                item.id = ext.id
                return item
            }
        }
        // Input methods are .app bundles; nothing else needs bundle permission.
        let needsBundles = removable.contains { $0.kind == .inputMethod }
        var outcome = await FileRemover.shared.dispose(items, module: .applications,
                                                       options: needsBundles ? [.allowAppBundles] : [],
                                                       settings: settings, progress: progress)
        let removedIDs = Set(outcome.removedItemIDs)
        if removable.contains(where: { $0.kind == .quickLook && removedIDs.contains($0.id) }) {
            _ = await Shell.run("/usr/bin/qlmanage", ["-r"], timeout: 20)
        }
        outcome.summary = outcome.removedItemIDs.isEmpty
            ? "Nothing was removed"
            : "Removed \(CountFormat.items(outcome.removedItemIDs.count, singular: "plug-in")) · \(ByteFormat.string(outcome.freedBytes))"
        return outcome
    }
}
