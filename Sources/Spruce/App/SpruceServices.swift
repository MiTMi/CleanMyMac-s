import AppKit
import SpruceCore
import SpruceMac

/// Finder Services (right-click › Services): "Uninstall with Spruce", "Map Folder with
/// Spruce", "Find Clutter with Spruce", "Shred with Spruce". The `NSServices` entries live
/// in `Support/Info.plist` (checked by `scripts/build-app.sh`); each `NSMessage` names one
/// of these methods.
///
/// A Service only *shows* the files in the right tool (via `AppModel.openFiles`); it
/// never starts a removal — that always needs the tool's own confirmation.
final class SpruceServices: NSObject {
    @objc func uninstallWithSpruce(_ pasteboard: NSPasteboard, userData: String?,
                                   error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        route(pasteboard, to: .uninstaller, error: error)
    }

    @objc func mapFolderWithSpruce(_ pasteboard: NSPasteboard, userData: String?,
                                   error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        route(pasteboard, to: .spaceMap, error: error)
    }

    /// Adds the folders to the places Clutter scans (it never starts a scan by itself).
    @objc func findClutterWithSpruce(_ pasteboard: NSPasteboard, userData: String?,
                                     error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        route(pasteboard, to: .clutter, error: error)
    }

    @objc func shredWithSpruce(_ pasteboard: NSPasteboard, userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        route(pasteboard, to: .shredder, error: error)
    }

    private func route(_ pasteboard: NSPasteboard, to destination: AppModel.FileDestination,
                       error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "Spruce didn't receive any files." as NSString
            return
        }
        MainActor.assumeIsolated {
            AppModel.shared.openFiles(urls, as: destination)
        }
    }
}
