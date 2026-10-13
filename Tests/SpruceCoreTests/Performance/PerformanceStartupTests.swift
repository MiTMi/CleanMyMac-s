import XCTest
@testable import SpruceCore

final class PerformanceLaunchPlistTests: XCTestCase {
    private func xml(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>\(body)</dict></plist>
        """.utf8)
    }

    func testParsesAllKeys() {
        let data = xml("""
        <key>Label</key><string>com.example.agent</string>
        <key>ProgramArguments</key><array><string>~/bin/agent</string><string>--quiet</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
        <key>Disabled</key><true/>
        <key>AssociatedBundleIdentifiers</key><array><string>com.example.App</string></array>
        <key>StartInterval</key><integer>3600</integer>
        <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer></dict>
        """)
        let p = PerformanceLaunchPlist.parse(data: data, path: "/Users/t/Library/LaunchAgents/com.example.agent.plist", home: "/Users/t")
        XCTAssertTrue(p.isValid)
        XCTAssertEqual(p.label, "com.example.agent")
        XCTAssertNil(p.program)
        XCTAssertEqual(p.programArguments, ["/Users/t/bin/agent", "--quiet"])
        XCTAssertEqual(p.executable, "/Users/t/bin/agent")
        XCTAssertTrue(p.runAtLoad)
        XCTAssertTrue(p.keepAlive)
        XCTAssertTrue(p.disabledKey)
        XCTAssertEqual(p.associatedBundleIdentifiers, ["com.example.App"])
        XCTAssertEqual(p.startInterval, 3600)
        XCTAssertTrue(p.hasCalendarInterval)
        XCTAssertEqual(p.fileStem, "com.example.agent")
    }

    func testProgramWinsOverArgumentsAndBundleProgram() {
        let data = xml("""
        <key>Label</key><string>com.example.d</string>
        <key>Program</key><string>/Library/PrivilegedHelperTools/com.example.d</string>
        <key>ProgramArguments</key><array><string>ignored</string></array>
        <key>BundleProgram</key><string>Contents/MacOS/helper</string>
        <key>KeepAlive</key><true/>
        """)
        let p = PerformanceLaunchPlist.parse(data: data, path: "/Library/LaunchDaemons/com.example.d.plist")
        XCTAssertEqual(p.executable, "/Library/PrivilegedHelperTools/com.example.d")
        XCTAssertEqual(p.bundleProgram, "Contents/MacOS/helper")
        XCTAssertTrue(p.keepAlive)
        XCTAssertFalse(p.runAtLoad)
    }

    func testBinaryPlistAndInvalidData() throws {
        let dict: [String: Any] = ["Label": "com.example.bin", "Program": "/usr/local/bin/x", "RunAtLoad": true]
        let binary = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        let p = PerformanceLaunchPlist.parse(data: binary, path: "/x.plist")
        XCTAssertTrue(p.isValid)
        XCTAssertEqual(p.label, "com.example.bin")
        XCTAssertTrue(p.runAtLoad)

        let garbage = PerformanceLaunchPlist.parse(data: Data([0xCF, 0xFA, 0xED, 0xFE, 0x07]), path: "/y.plist")
        XCTAssertFalse(garbage.isValid)
        let array = try PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml, options: 0)
        XCTAssertFalse(PerformanceLaunchPlist.parse(data: array, path: "/z.plist").isValid)
    }

    func testListsPlistFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perf-plists-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["b.plist", "a.plist", ".hidden.plist", "notes.txt"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        let paths = PerformanceLaunchPlist.plistPaths(in: dir.path).map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(paths, ["a.plist", "b.plist"])
        XCTAssertTrue(PerformanceLaunchPlist.plistPaths(in: dir.path + "/missing").isEmpty)
    }
}

final class PerformanceVendorTests: XCTestCase {
    let apps = PerformanceAppIndex(apps: [
        PerformanceInstalledApp(bundleID: "com.docker.docker", name: "Docker", path: "/Applications/Docker.app"),
        PerformanceInstalledApp(bundleID: "com.google.Chrome", name: "Google Chrome", path: "/Applications/Google Chrome.app"),
        PerformanceInstalledApp(bundleID: "com.google.drivefs", name: "Google Drive", path: "/Applications/Google Drive.app"),
        PerformanceInstalledApp(bundleID: "com.example", name: "Example", path: "/Applications/Example.app"),
        PerformanceInstalledApp(bundleID: "us.zoom.xos", name: "zoom.us", path: "/Applications/zoom.us.app"),
    ])

    func testOrganizationAndNames() {
        XCTAssertEqual(PerformanceVendor.organization(of: "com.google.keystone.agent"), "com.google")
        XCTAssertEqual(PerformanceVendor.organization(of: "single"), "single")
        XCTAssertEqual(PerformanceVendor.displayName(forOrganization: "com.google"), "Google")
        XCTAssertEqual(PerformanceVendor.displayName(forOrganization: "com.acmecorp"), "Acmecorp")
        XCTAssertEqual(PerformanceVendor.outermostAppBundle(in: "/Applications/Foo.app/Contents/Library/Helper.app/Contents/MacOS/h"),
                       "/Applications/Foo.app")
        XCTAssertNil(PerformanceVendor.outermostAppBundle(in: "/usr/local/bin/foo"))
    }

    func testAssociatedBundleIdentifiersWin() {
        let m = PerformanceVendor.resolve(label: "com.unrelated.helper", fileStem: nil, executable: "/usr/local/bin/x",
                                          associatedBundleIDs: ["com.docker.docker"], apps: apps)
        XCTAssertEqual(m.name, "Docker")
        XCTAssertEqual(m.app?.path, "/Applications/Docker.app")
        XCTAssertEqual(m.key, "com.docker")
    }

    func testProgramInsideAppBundle() {
        let m = PerformanceVendor.resolve(label: "x.y.z", fileStem: nil,
                                          executable: "/Applications/Google Chrome.app/Contents/MacOS/updater",
                                          associatedBundleIDs: [], apps: apps)
        XCTAssertEqual(m.name, "Google Chrome")
    }

    func testLabelPrefixIsBoundaryAware() {
        XCTAssertEqual(apps.app(matchingLabel: "com.docker.docker.helper")?.name, "Docker")
        XCTAssertNil(apps.app(matchingLabel: "com.example123.agent"), "com.example must not match com.example123")
        XCTAssertEqual(apps.app(matchingLabel: "com.example.agent")?.name, "Example")
    }

    func testOrganizationFallbacks() {
        let google = PerformanceVendor.resolve(label: "com.google.keystone.agent", fileStem: nil,
                                               executable: "/Users/t/Library/Google/GoogleSoftwareUpdate/ksinstall",
                                               associatedBundleIDs: [], apps: apps)
        XCTAssertEqual(google.name, "Google", "two Google apps installed: name the organisation")
        XCTAssertNil(google.app)

        let zoom = PerformanceVendor.resolve(label: "us.zoom.ZoomDaemon", fileStem: nil, executable: "/Library/PrivilegedHelperTools/us.zoom.ZoomDaemon",
                                             associatedBundleIDs: [], apps: apps)
        XCTAssertEqual(zoom.name, "zoom.us", "single app in the organisation")

        let unknown = PerformanceVendor.resolve(label: "org.acme.sync", fileStem: nil, executable: "/opt/acme/sync",
                                                associatedBundleIDs: [], apps: apps)
        XCTAssertEqual(unknown.name, "Acme")
        XCTAssertEqual(unknown.key, "org.acme")

        let goneApp = PerformanceVendor.resolve(label: "com.gone.helper", fileStem: nil,
                                                executable: "/Applications/Gone.app/Contents/MacOS/helper",
                                                associatedBundleIDs: [], apps: apps)
        XCTAssertEqual(goneApp.name, "Gone")
    }

    func testAppScannerReadsInfoPlists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("perf-apps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func makeApp(_ relative: String, id: String, display: String? = nil) throws {
            let contents = root.appendingPathComponent(relative).appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": "Ignored"]
            if let display { info["CFBundleDisplayName"] = display }
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try makeApp("Alpha.app", id: "com.alpha.app")
        try makeApp("Suite/Beta.app", id: "com.beta.app", display: "Beta Pro")
        try makeApp("Deep/Deeper/Gamma.app", id: "com.gamma.app")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Broken.app"), withIntermediateDirectories: true)

        let found = PerformanceAppScanner.scan(folders: [root.path])
        XCTAssertEqual(Set(found.map(\.bundleID)), ["com.alpha.app", "com.beta.app"])
        XCTAssertEqual(found.first { $0.bundleID == "com.alpha.app" }?.name, "Alpha")
        XCTAssertEqual(found.first { $0.bundleID == "com.beta.app" }?.name, "Beta Pro")
    }
}

final class PerformanceBrokenAndBuilderTests: XCTestCase {
    let apps = PerformanceAppIndex(apps: [
        PerformanceInstalledApp(bundleID: "com.example.App", name: "Example", path: "/Applications/Example.app"),
    ])

    private func plist(label: String? = "com.example.agent", program: String? = "/opt/example/agent",
                       valid: Bool = true, disabled: Bool = false, bundleProgram: String? = nil,
                       associated: [String] = []) -> PerformanceLaunchPlist {
        PerformanceLaunchPlist(path: "/Library/LaunchAgents/\(label ?? "nolabel").plist", isValid: valid, label: label,
                               program: program, bundleProgram: bundleProgram, runAtLoad: true, disabledKey: disabled,
                               associatedBundleIdentifiers: associated)
    }

    func testBrokenReasons() {
        let exists: (String) -> Bool = { $0 == "/opt/example/agent" || $0 == "/Volumes/Mounted" }
        XCTAssertNil(PerformanceBrokenCheck.reason(for: plist(), apps: apps, fileExists: exists))
        XCTAssertNotNil(PerformanceBrokenCheck.reason(for: plist(program: "/opt/gone/agent"), apps: apps, fileExists: exists))
        XCTAssertNil(PerformanceBrokenCheck.reason(for: plist(program: "node"), apps: apps, fileExists: exists),
                     "bare command names are resolved through PATH")
        XCTAssertNil(PerformanceBrokenCheck.reason(for: plist(program: "/Volumes/Offline/bin/x"), apps: apps, fileExists: exists),
                     "disk not connected isn't broken")
        XCTAssertNotNil(PerformanceBrokenCheck.reason(for: plist(program: "/Volumes/Mounted/bin/x"), apps: apps, fileExists: exists))
        XCTAssertNotNil(PerformanceBrokenCheck.reason(for: plist(label: nil), apps: apps, fileExists: exists))
        XCTAssertNotNil(PerformanceBrokenCheck.reason(for: plist(valid: false), apps: apps, fileExists: exists))
        XCTAssertNotNil(PerformanceBrokenCheck.reason(for: plist(program: nil), apps: apps, fileExists: exists))
        XCTAssertNil(PerformanceBrokenCheck.reason(for: plist(program: nil, bundleProgram: "Contents/MacOS/h",
                                                              associated: ["com.example.App"]), apps: apps, fileExists: exists))
        XCTAssertNotNil(PerformanceBrokenCheck.reason(for: plist(program: nil, bundleProgram: "Contents/MacOS/h",
                                                                 associated: ["com.removed.App"]), apps: apps, fileExists: exists))
    }

    func testBuilderSkipsAppleAndOwnItems() {
        let state = PerformanceLaunchDomainState(services: [:], overrides: [:])
        XCTAssertNil(PerformanceStartupBuilder.item(from: plist(label: "com.apple.foo"), domain: .globalAgent, state: state,
                                                    apps: apps, fileExists: { _ in true }))
        XCTAssertNil(PerformanceStartupBuilder.item(from: plist(label: "com.spruce.app.menu"), domain: .userAgent, state: state,
                                                    apps: apps, excludedLabelPrefixes: ["com.spruce.app"], fileExists: { _ in true }))
        XCTAssertNotNil(PerformanceStartupBuilder.item(from: plist(), domain: .globalAgent, state: state, apps: apps,
                                                       excludedLabelPrefixes: ["com.spruce.app"], fileExists: { _ in true }))
    }

    func testOverridesBeatPlistDisabledKey() {
        let running = PerformanceLaunchDomainState(
            services: ["com.example.agent": PerformanceLaunchService(label: "com.example.agent", pid: 812, lastExitStatus: nil)],
            overrides: ["com.example.agent": false])
        let item = PerformanceStartupBuilder.item(from: plist(disabled: true), domain: .globalAgent, state: running,
                                                  apps: apps, fileExists: { _ in true })!
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.isLoaded, true)
        XCTAssertEqual(item.pid, 812)
        XCTAssertEqual(item.status, .running)
        XCTAssertEqual(item.kind, .globalAgent)
        XCTAssertEqual(item.vendorName, "Example")
        XCTAssertTrue(item.canToggle)

        let off = PerformanceLaunchDomainState(services: [:], overrides: ["com.example.agent": true])
        let disabled = PerformanceStartupBuilder.item(from: plist(), domain: .systemDaemon, state: off, apps: apps,
                                                      fileExists: { _ in true })!
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertEqual(disabled.status, .disabled)
        XCTAssertTrue(disabled.kind.needsAdmin)

        let unknown = PerformanceLaunchDomainState(services: nil, overrides: nil)
        let plain = PerformanceStartupBuilder.item(from: plist(disabled: true), domain: .userAgent, state: unknown, apps: apps,
                                                   fileExists: { _ in true })!
        XCTAssertFalse(plain.isEnabled, "without launchd overrides the plist's Disabled key counts")
        XCTAssertNil(plain.isLoaded)
    }

    func testBrokenStatusAndDisplayName() {
        let state = PerformanceLaunchDomainState(services: [:], overrides: [:])
        let broken = PerformanceStartupBuilder.item(from: plist(program: "/Applications/Example.app/Contents/Library/LoginItems/Example Helper.app/Contents/MacOS/x"),
                                                    domain: .userAgent, state: state, apps: apps, fileExists: { _ in false })!
        XCTAssertEqual(broken.status, .broken)
        XCTAssertEqual(broken.name, "Example Helper")
        XCTAssertTrue(broken.statusDetail.contains("missing"))
    }

    func testAppRegisteredItemsAreReadOnly() {
        let item = PerformanceStartupItem(id: "app:/x", kind: .appAgent, name: "Helper", label: "com.x.helper",
                                          vendorKey: "com.x", vendorName: "X", isEnabled: true, isLoaded: true)
        XCTAssertEqual(item.status, .managedBySystem)
        XCTAssertFalse(item.canToggle)
        XCTAssertFalse(item.canRemove)
        XCTAssertTrue(item.isBackground)
        XCTAssertFalse(PerformanceStartupKind.appLoginItem.isBackground)
    }

    func testLegacyLoginItem() {
        let legacy = PerformanceLegacyLoginItem(name: "Example", path: "/Applications/Example.app", hidden: true)
        let item = PerformanceStartupBuilder.loginItem(legacy, isEnabled: true, apps: apps, fileExists: { _ in true })
        XCTAssertEqual(item.kind, .loginItem)
        XCTAssertEqual(item.vendorName, "Example")
        XCTAssertEqual(item.appPath, "/Applications/Example.app")
        XCTAssertTrue(item.opensHidden)
        XCTAssertEqual(item.status, .enabled)
        XCTAssertTrue(item.statusDetail.contains("hidden"))

        let gone = PerformanceStartupBuilder.loginItem(PerformanceLegacyLoginItem(name: "Old", path: "/Applications/Old.app", hidden: false),
                                                       isEnabled: true, apps: apps, fileExists: { _ in false })
        XCTAssertEqual(gone.status, .broken)
        let off = PerformanceStartupBuilder.loginItem(PerformanceLegacyLoginItem(name: "Old", path: "/Applications/Old.app", hidden: false),
                                                      isEnabled: false, apps: apps, fileExists: { _ in false })
        XCTAssertEqual(off.status, .disabled, "a switched-off item isn't reported as broken")
    }

    func testGroupingByVendor() {
        func item(_ name: String, key: String, vendor: String, broken: Bool = false) -> PerformanceStartupItem {
            PerformanceStartupItem(id: name, kind: .userAgent, name: name, label: "l." + name, vendorKey: key, vendorName: vendor,
                                   isEnabled: true, brokenReason: broken ? "x" : nil)
        }
        let groups = PerformanceStartupGrouping.groups([
            item("updater", key: "com.google", vendor: "Google Chrome"),
            item("drive", key: "com.google", vendor: "Google Drive"),
            item("zeta", key: "com.docker", vendor: "Docker"),
            item("alpha", key: "com.docker", vendor: "Docker", broken: true),
        ])
        XCTAssertEqual(groups.map(\.title), ["Docker", "Google"])
        XCTAssertEqual(groups[0].items.map(\.name), ["alpha", "zeta"], "broken items first")
        XCTAssertEqual(groups[0].brokenCount, 1)
        XCTAssertEqual(groups[1].items.count, 2)
    }
}

final class PerformanceAppleScriptTests: XCTestCase {
    func testQuoting() {
        XCTAssertEqual(PerformanceAppleScript.quote("Plain"), "\"Plain\"")
        XCTAssertEqual(PerformanceAppleScript.quote("Say \"hi\" \\ bye"), "\"Say \\\"hi\\\" \\\\ bye\"")
        XCTAssertTrue(PerformanceAppleScript.deleteLoginItemSource(name: "A \"B\"", path: "").contains("\"A \\\"B\\\"\""))
        XCTAssertTrue(PerformanceAppleScript.addLoginItemSource(path: "/Applications/A.app", hidden: true).contains("hidden:true"))
    }

    func testParsesLoginItemOutput() {
        let output = "Dropbox\t/Applications/Dropbox.app\tfalse\nHidden Thing\t/Applications/Hidden.app\ttrue\n\t/Applications/Nameless.app\tfalse\nNoPath\t\tfalse\n\n"
        let items = PerformanceAppleScript.parseLoginItems(output)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0], PerformanceLegacyLoginItem(name: "Dropbox", path: "/Applications/Dropbox.app", hidden: false))
        XCTAssertTrue(items[1].hidden)
        XCTAssertEqual(items[2].name, "Nameless")
        XCTAssertEqual(items[3].path, "")
        XCTAssertTrue(PerformanceAppleScript.parseLoginItems("").isEmpty)
    }

    func testDeletesLoginItemsByPathNotName() {
        let byPath = PerformanceAppleScript.deleteLoginItemSource(name: "Helper", path: "/Applications/A \"B\".app")
        XCTAssertTrue(byPath.contains("whose path is \"/Applications/A \\\"B\\\".app\""))
        XCTAssertFalse(byPath.contains("name"), "two items can share a name: a known path decides alone")

        let byName = PerformanceAppleScript.deleteLoginItemSource(name: "Helper", path: "")
        XCTAssertTrue(byName.contains("n is \"Helper\""))
        XCTAssertTrue(byName.contains("p is \"\" and"), "without a path, only items without a path may go")
        XCTAssertFalse(byName.contains("every login item whose name"))
    }

    func testSavedLoginItemsRoundTrip() throws {
        let items = [PerformanceLegacyLoginItem(name: "A", path: "/Applications/A.app", hidden: false)]
        let data = try JSONEncoder().encode(items)
        XCTAssertEqual(try JSONDecoder().decode([PerformanceLegacyLoginItem].self, from: data), items)
    }
}

final class PerformanceStartupIgnoreTests: XCTestCase {
    private func agent(_ name: String, plist: String, label: String? = nil, executable: String? = nil,
                       app: String? = nil, bundleID: String? = nil) -> PerformanceStartupItem {
        PerformanceStartupItem(id: plist, kind: .userAgent, name: name, label: label, plistPath: plist,
                               executablePath: executable, vendorKey: "v", vendorName: "V", appPath: app,
                               appBundleID: bundleID, isEnabled: true)
    }

    func testNothingIgnoredKeepsEverything() {
        let items = [agent("a", plist: "/Users/t/Library/LaunchAgents/a.plist")]
        XCTAssertEqual(PerformanceStartupIgnore.filtered(items, settings: SpruceSettings()), items)
    }

    func testMatchesPathsBundleIDsLabelsAndItemIDs() {
        let home = NSHomeDirectory()
        let byPlistFolder = agent("folder", plist: home + "/Library/LaunchAgents/x.plist")
        let byExecutable = agent("exe", plist: "/Library/LaunchAgents/e.plist", executable: "/opt/tool/bin/run")
        let byApp = agent("app", plist: "/Library/LaunchAgents/p.plist", app: "/Applications/Kept.app")
        let byBundle = agent("bundle", plist: "/Library/LaunchAgents/b.plist", bundleID: "com.Example.App")
        let byLabel = agent("label", plist: "/Library/LaunchAgents/l.plist", label: "com.example.helper")
        let byID = agent("id", plist: "/Library/LaunchAgents/i.plist")
        let login = PerformanceStartupItem(id: "login:/Applications/Login.app", kind: .loginItem, name: "Login",
                                           executablePath: "/Applications/Login.app", vendorKey: "l", vendorName: "L",
                                           isEnabled: true)
        let free = agent("free", plist: "/Library/LaunchAgents/f.plist", label: "com.free.agent",
                         executable: "/usr/local/bin/free", app: "/Applications/Free.app", bundleID: "com.free.app")

        var settings = SpruceSettings()
        settings.ignoredPaths = ["~/Library/LaunchAgents", "/opt/tool", "/Applications/Kept.app", "/Applications/Login.app"]
        settings.ignoredBundleIDs = ["com.example.app", "COM.EXAMPLE.HELPER"]
        settings.ignoredItemIDs = ["/Library/LaunchAgents/i.plist"]

        let all = [byPlistFolder, byExecutable, byApp, byBundle, byLabel, byID, login, free]
        for item in all where item != free {
            XCTAssertTrue(PerformanceStartupIgnore.isIgnored(item, settings: settings), item.name)
        }
        XCTAssertEqual(PerformanceStartupIgnore.filtered(all, settings: settings), [free])
    }

    func testRelativeProgramPathsNeverMatch() {
        var settings = SpruceSettings()
        settings.ignoredPaths = ["/usr/bin"]
        let item = agent("rel", plist: "/Library/LaunchAgents/r.plist", executable: "bin/tool")
        XCTAssertFalse(PerformanceStartupIgnore.isIgnored(item, settings: settings))
    }
}
