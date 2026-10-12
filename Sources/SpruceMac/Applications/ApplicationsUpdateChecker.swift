import AppKit
import Foundation
import SpruceCore

/// Checks Sparkle feeds, the App Store and Homebrew for newer versions of installed apps.
///
/// Network use is limited to what update checks need: each app's own appcast, Apple's
/// iTunes lookup API (App Store apps only), and Homebrew's own tooling.
enum ApplicationsUpdateChecker {

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.httpAdditionalHeaders = ["User-Agent": "Spruce/1.0 (Macintosh; update check)"]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Checks every eligible app; progress reports each finished app.
    static func check(apps: [ApplicationsAppInfo], progress: ProgressHandler?) async -> [ApplicationsUpdate] {
        let candidates = apps.filter { !$0.isSystem && !$0.bundleID.isEmpty }
        let sparkleApps = candidates.filter { $0.sparkleFeedURL != nil && $0.source != .appStore && $0.source != .setapp }
        let storeApps = candidates.filter {
            $0.source == .appStore && !$0.bundleID.lowercased().hasPrefix("com.apple.installassistant")
        }
        let total = sparkleApps.count + storeApps.count + 1
        let done = ApplicationsLocked(0)
        let report: @Sendable (String) -> Void = { name in
            let count = done.update { (value: inout Int) -> Int in
                value += 1
                return value
            }
            progress?(ScanProgress(fraction: Double(count) / Double(total), message: "Checking for updates…", current: name))
        }

        var updates: [ApplicationsUpdate] = []
        let country = (Locale.current.region?.identifier ?? "US").lowercased()

        await withTaskGroup(of: ApplicationsUpdate?.self) { group in
            var pending: [@Sendable () async -> ApplicationsUpdate?] = []
            for app in sparkleApps {
                pending.append { let u = await sparkleUpdate(for: app); report(app.name); return u }
            }
            for app in storeApps {
                pending.append { let u = await storeUpdate(for: app, country: country); report(app.name); return u }
            }
            var index = 0
            let limit = 8
            while index < min(limit, pending.count) {
                let job = pending[index]
                group.addTask { await job() }
                index += 1
            }
            while let result = await group.next() {
                if let result { updates.append(result) }
                if index < pending.count {
                    let job = pending[index]
                    group.addTask { await job() }
                    index += 1
                }
            }
        }

        progress?(ScanProgress(fraction: Double(total - 1) / Double(total), message: "Checking Homebrew…"))
        updates += await homebrewUpdates(apps: candidates)
        report("Homebrew")
        return updates
    }

    // MARK: Sparkle

    static func sparkleUpdate(for app: ApplicationsAppInfo) async -> ApplicationsUpdate? {
        guard let raw = app.sparkleFeedURL, let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        var urls = [url]
        if scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let secure = components.url { urls.insert(secure, at: 0) }
        }
        for candidate in urls {
            guard let data = await fetch(candidate) else { continue }
            let items = ApplicationsAppcast.parse(data)
            guard !items.isEmpty else { continue }
            guard let best = ApplicationsAppcast.bestItem(items, isAppleSilicon: isAppleSilicon) else { return nil }
            return ApplicationsUpdate.fromAppcast(best, app: app, feedURL: candidate)
        }
        return nil
    }

    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }

    // MARK: App Store

    static func storeUpdate(for app: ApplicationsAppInfo, country: String) async -> ApplicationsUpdate? {
        for entity in ["desktopSoftware", "macSoftware"] {
            guard let url = ApplicationsITunes.lookupURL(bundleID: app.bundleID, country: country, entity: entity),
                  let data = await fetch(url) else { continue }
            let results = ApplicationsITunes.decode(data)
            guard let first = results.first else { continue }
            return ApplicationsITunes.update(from: first, app: app)
        }
        return nil
    }

    // MARK: Homebrew

    static func homebrewUpdates(apps: [ApplicationsAppInfo]) async -> [ApplicationsUpdate] {
        guard let brew = ApplicationsMac.brewPath else { return [] }
        let info = await ApplicationsMac.run(brew, ["info", "--cask", "--installed", "--json=v2"],
                                             environment: ApplicationsMac.brewEnvironment, timeout: 120)
        guard info.status == 0 else { return [] }
        let casks = ApplicationsHomebrew.parseInfo(Data(info.stdout.utf8))
        guard !casks.isEmpty else { return [] }
        let outdated = await ApplicationsMac.run(brew, ["outdated", "--cask", "--greedy", "--json=v2"],
                                                 environment: ApplicationsMac.brewEnvironment, timeout: 180)
        guard outdated.status == 0 || !outdated.stdout.isEmpty else { return [] }
        return ApplicationsHomebrew.updates(outdated: ApplicationsHomebrew.parseOutdated(Data(outdated.stdout.utf8)),
                                            casks: casks, apps: apps)
    }

    /// Runs `brew upgrade --cask <token>` as the current user.
    static func upgradeCask(_ token: String) async -> (ok: Bool, message: String) {
        guard let brew = ApplicationsMac.brewPath else { return (false, "Homebrew is not installed.") }
        guard token.range(of: "^[A-Za-z0-9@._+-]+$", options: .regularExpression) != nil else {
            return (false, "Unexpected cask name.")
        }
        let result = await ApplicationsMac.run(brew, ["upgrade", "--cask", token], environment: ApplicationsMac.brewEnvironment,
                                               timeout: 1800)
        if result.status == 0 { return (true, "Updated with Homebrew") }
        let reason = ApplicationsMac.tail(result.stderr.isEmpty ? result.stdout : result.stderr)
        if reason.lowercased().contains("sudo") || reason.lowercased().contains("password") {
            return (false, "This update needs an administrator password. Run “brew upgrade --cask \(token)” in Terminal.")
        }
        return (false, reason.isEmpty ? "Homebrew could not update this app." : reason)
    }

    /// The version now on disk (read without any bundle cache).
    static func installedVersion(appPath: String) -> (version: String, build: String)? {
        let plist = ApplicationsPlist.dictionary(atPath: (appPath as NSString).appendingPathComponent("Contents/Info.plist"))
        guard let plist else { return nil }
        let build = plist["CFBundleVersion"] as? String ?? ""
        let version = plist["CFBundleShortVersionString"] as? String ?? build
        return (version, build)
    }
}
