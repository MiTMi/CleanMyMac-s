import AppKit
import CryptoKit
import Foundation
import Security
import SpruceCore

/// Installs Sparkle updates in place, the way the app's own updater would — but only when
/// every check passes:
///
/// 1. The archive downloads over HTTPS (rule 8: only when the user presses Update).
/// 2. Its Ed25519 signature (`sparkle:edSignature`) verifies against the developer's key
///    in the installed app (`SUPublicEDKey`).
/// 3. The unpacked app has the same bundle id, a newer version, a valid code signature and
///    the same Team ID as the installed app.
/// 4. The old version goes to the Trash through `FileRemover` (it can be put back), and the
///    new one takes its place. If that fails, the old version is put back.
///
/// Anything else is left to the app's own updater.
enum ApplicationsSparkleInstaller {

    struct Result: Sendable {
        var ok: Bool
        var message: String
        /// The old version's Trash run (for history and Put Back).
        var outcome: RunOutcome?
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        configuration.httpAdditionalHeaders = ["User-Agent": "Spruce/1.0 (Macintosh; update download)"]
        return URLSession(configuration: configuration)
    }()

    static func install(_ update: ApplicationsUpdate, app: ApplicationsAppInfo, progress: ProgressHandler?) async -> Result {
        if let blocker = ApplicationsSparkleInstallPlan.blocker(update: update, app: app) {
            return Result(ok: false, message: blocker)
        }
        guard let downloadURL = update.downloadURL, let signature = update.edSignature,
              let publicKey = app.sparklePublicEDKey, let teamID = app.teamID else {
            return Result(ok: false, message: "This update can't be checked, so the app installs it itself.")
        }
        let appURL = URL(fileURLWithPath: app.path)
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            return Result(ok: false, message: "Spruce can't write to \(parent.path.abbreviatingHome). Open the app to update it.")
        }
        if await isRunning(path: app.path) {
            return Result(ok: false, message: "\(app.name) is open. Quit it and try again.")
        }

        // A work folder on the same disk as the app, so the final move is a rename.
        let workFolder: URL
        do {
            workFolder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: appURL, create: true)
        } catch {
            return Result(ok: false, message: "Spruce couldn't prepare a folder for the update: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: workFolder) }

        // 1. Download.
        progress?(ScanProgress(fraction: nil, message: "Downloading \(app.name) \(update.availableVersion)…"))
        let archive: URL
        switch await download(downloadURL, into: workFolder) {
        case .success(let url): archive = url
        case .failure(let message): return Result(ok: false, message: message)
        }

        // 2. Verify the developer's signature over the exact bytes downloaded.
        progress?(ScanProgress(fraction: nil, message: "Checking the developer's signature…"))
        let verified: Bool = await ApplicationsMac.background {
            Self.verifyEdDSA(archive: archive, signature: signature, publicKey: publicKey)
        }
        guard verified else {
            return Result(ok: false, message: "The download's signature doesn't match the developer's key, so it wasn't installed.")
        }

        // 3. Unpack and check the new app.
        progress?(ScanProgress(fraction: nil, message: "Unpacking…"))
        let staging = workFolder.appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        if let failure = await unpack(archive, into: staging, workFolder: workFolder) {
            return Result(ok: false, message: failure)
        }
        guard let newApp = findApp(in: staging, bundleID: app.bundleID, preferredName: appURL.lastPathComponent) else {
            return Result(ok: false, message: "The download doesn't contain \(app.name).")
        }
        progress?(ScanProgress(fraction: nil, message: "Checking the new version…"))
        if let failure = await checkNewApp(newApp, installed: app, teamID: teamID) {
            return Result(ok: false, message: failure)
        }
        if await isRunning(path: app.path) {
            return Result(ok: false, message: "\(app.name) was opened during the update. Quit it and try again.")
        }

        // 4. Swap: the old version goes to the Trash (recoverable), the new one moves in.
        progress?(ScanProgress(fraction: nil, message: "Installing…"))
        ApplicationsTrashWatcher.noteSpruceRemoval(bundleIDs: [app.bundleID])
        let settings = await ApplicationsMac.settings()
        var meta: [String: String] = [ApplicationsMeta.bundleID: app.bundleID, ApplicationsMeta.appPath: app.path]
        if let inode = FileWalker.entry(at: app.path)?.inode { meta[ApplicationsMeta.inode] = String(inode) }
        let oldItem = ScanItem.file(appURL, size: app.size, safety: .safe,
                                    title: "\(appURL.lastPathComponent) \(app.versionLabel)", metadata: meta)
        let outcome = await FileRemover.shared.dispose([oldItem], module: .applications, options: [.allowAppBundles],
                                                       settings: settings)
        guard outcome.removedItemIDs.contains(oldItem.id), FileWalker.entry(at: app.path) == nil else {
            let reason = outcome.failures.first?.reason ?? "it couldn't be moved to the Trash"
            return Result(ok: false, message: "The old version stayed in place: \(reason).")
        }
        do {
            try FileManager.default.moveItem(at: newApp, to: appURL)
        } catch {
            let restored = TrashLedger.shared.putBack(runIDs: outcome.trashRunIDs)
            let note = restored.restored.isEmpty
                ? " The old version is in the Trash; drag it back to \(parent.path.abbreviatingHome)."
                : " The old version was put back."
            return Result(ok: false, message: "The new version couldn't be moved into place (\(error.localizedDescription))." + note)
        }
        OperationLog.shared.record(module: .applications, action: "update", result: "ok", bytes: 0,
                                   detail: "\(app.path) \(app.versionLabel) -> \(update.availableVersion)")
        // Let Launch Services see the new version right away.
        _ = await Shell.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                            ["-f", app.path], timeout: 20)
        return Result(ok: true, message: "Updated to \(update.availableVersion)", outcome: outcome)
    }

    // MARK: Steps

    private enum Download {
        case success(URL)
        case failure(String)
    }

    private static func download(_ url: URL, into folder: URL) async -> Download {
        do {
            let (temporary, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: temporary)
                return .failure("The developer's server didn't send the update.")
            }
            if let finalScheme = http.url?.scheme?.lowercased(), finalScheme != "https" {
                try? FileManager.default.removeItem(at: temporary)
                return .failure("The download was redirected to an insecure address, so it wasn't used.")
            }
            let destination = folder.appendingPathComponent("download")
            try FileManager.default.moveItem(at: temporary, to: destination)
            let size = FileWalker.entry(at: destination.path)?.logicalSize ?? 0
            guard size > 0, size <= ApplicationsSparkleInstallPlan.maximumDownload else {
                return .failure("The download is empty or too large.")
            }
            return .success(destination)
        } catch {
            return .failure("The download failed: \(error.localizedDescription)")
        }
    }

    /// Ed25519 (Sparkle's EdDSA) over the whole archive.
    static func verifyEdDSA(archive: URL, signature: String, publicKey: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey), keyData.count == 32,
              let signatureData = Data(base64Encoded: signature), signatureData.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let data = try? Data(contentsOf: archive, options: .alwaysMapped) else { return false }
        return key.isValidSignature(signatureData, for: data)
    }

    /// Unpacks the archive; returns a failure message or nil.
    private static func unpack(_ archive: URL, into staging: URL, workFolder: URL) async -> String? {
        guard let kind = sniff(archive) else {
            return "The download is an installer package or a format Spruce doesn't unpack. Open the app to update it."
        }
        switch kind {
        case .zip:
            let result = await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path], timeout: 600)
            return result.status == 0 ? nil : "The archive couldn't be unpacked."
        case .tar:
            let result = await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", staging.path], timeout: 600)
            return result.status == 0 ? nil : "The archive couldn't be unpacked."
        case .diskImage:
            let mount = workFolder.appendingPathComponent("mount", isDirectory: true)
            try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            // No input: a disk image that asks to accept a licence fails instead of waiting.
            let attach = await ApplicationsMac.run("/usr/bin/hdiutil", ["attach", archive.path, "-nobrowse", "-readonly",
                                                                         "-noautoopen", "-noverify", "-mountpoint", mount.path],
                                                   timeout: 300)
            guard attach.status == 0 else {
                return "The disk image couldn't be opened (it may ask to accept a licence). Open the app to update it."
            }
            let failure = await copyApps(from: mount, to: staging)
            let detach = await ApplicationsMac.run("/usr/bin/hdiutil", ["detach", mount.path], timeout: 60)
            if detach.status != 0 {
                _ = await ApplicationsMac.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"], timeout: 60)
            }
            return failure
        }
    }

    /// Copies the apps at the top of a mounted disk image into `staging`.
    private static func copyApps(from mount: URL, to staging: URL) async -> String? {
        let apps = ((try? FileManager.default.contentsOfDirectory(atPath: mount.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".app") }
        guard !apps.isEmpty else { return "The disk image doesn't contain an app." }
        var copied = 0
        for name in apps {
            let source = mount.appendingPathComponent(name)
            guard FileWalker.entry(at: source.path)?.isSymlink == false else { continue }
            let copy = await Shell.run("/usr/bin/ditto", [source.path, staging.appendingPathComponent(name).path], timeout: 600)
            if copy.status != 0 { return "The app couldn't be copied from the disk image." }
            copied += 1
        }
        return copied == 0 ? "The disk image doesn't contain an app." : nil
    }

    private static func sniff(_ archive: URL) -> ApplicationsSparkleInstallPlan.ArchiveKind? {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return nil }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 512)) ?? Data()
        let size = (try? handle.seekToEnd()) ?? 0
        var trailer = Data()
        if size >= 512, (try? handle.seek(toOffset: size - 512)) != nil {
            trailer = (try? handle.read(upToCount: 512)) ?? Data()
        }
        return ApplicationsSparkleInstallPlan.sniff(header: header, trailer: trailer)
    }

    /// The unpacked app with the installed app's bundle id (top level, or one folder down).
    private static func findApp(in folder: URL, bundleID: String, preferredName: String) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where !name.hasPrefix(".") && name != "__MACOSX" {
            let url = folder.appendingPathComponent(name)
            if name.lowercased().hasSuffix(".app") {
                candidates.append(url)
            } else if FileWalker.entry(at: url.path)?.isDirectory == true {
                for child in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] where child.lowercased().hasSuffix(".app") {
                    candidates.append(url.appendingPathComponent(child))
                }
            }
        }
        let matching = candidates.filter { candidate in
            guard FileWalker.entry(at: candidate.path)?.isSymlink == false else { return false }
            let plist = ApplicationsPlist.dictionary(atPath: candidate.appendingPathComponent("Contents/Info.plist").path)
            return (plist?["CFBundleIdentifier"] as? String)?.caseInsensitiveCompare(bundleID) == .orderedSame
        }
        return matching.first { $0.lastPathComponent == preferredName } ?? matching.first
    }

    /// Same bundle id, newer version, valid signature, same Team ID. Returns a failure or nil.
    private static func checkNewApp(_ url: URL, installed: ApplicationsAppInfo, teamID: String) async -> String? {
        await ApplicationsMac.background {
            guard let plist = ApplicationsPlist.dictionary(atPath: url.appendingPathComponent("Contents/Info.plist").path) else {
                return "The new version can't be read."
            }
            let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
            let build = (plist["CFBundleVersion"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let version = (plist["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces) ?? build
            guard ApplicationsSparkleInstallPlan.acceptsReplacement(installed: installed, newBundleID: bundleID,
                                                                     newVersion: version, newBuild: build) else {
                return "The download isn't a newer version of \(installed.name), so it wasn't installed."
            }
            var staticCode: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess, let code = staticCode else {
                return "The new version's signature can't be read."
            }
            let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSStrictValidate)
                                   | UInt32(kSecCSCheckNestedCode))
            guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
                return "The new version's code signature isn't valid, so it wasn't installed."
            }
            let signing = ApplicationsCatalogReader.signingInfo(path: url.path)
            guard let newTeam = signing.teamID, newTeam == teamID else {
                return "The new version is signed by a different developer, so it wasn't installed."
            }
            return nil
        }
    }

    @MainActor
    private static func runningInstances(path: String) -> [NSRunningApplication] {
        let standardized = (path as NSString).standardizingPath
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL.map { ($0.path as NSString).standardizingPath } == standardized
        }
    }

    private static func isRunning(path: String) async -> Bool {
        await MainActor.run { !runningInstances(path: path).isEmpty }
    }

    /// Opens the app again after an update (it was open before).
    @MainActor
    static func relaunch(path: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration, completionHandler: nil)
    }
}
