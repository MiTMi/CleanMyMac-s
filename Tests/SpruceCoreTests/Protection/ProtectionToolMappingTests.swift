import Foundation
import XCTest
@testable import SpruceCore

final class ProtectionToolMappingTests: XCTestCase {

    // MARK: Privacy groups

    private func trace(_ kind: ProtectionTraceKind, source: String = "chrome", safety: SafetyLevel? = nil) -> ProtectionTrace {
        ProtectionTrace(id: "privacy.\(source).\(kind.rawValue)", sourceID: source, kind: kind, title: kind.title,
                        detail: kind.detail(engine: .chromium), safety: safety ?? kind.defaultSafety,
                        files: [ProtectionTraceFile(path: "/tmp/\(source)/\(kind.rawValue)", size: 100, deletion: .trash)])
    }

    func testPrivacyGroupOrdersTracesAndKeepsDefaultSelection() throws {
        let browser = try XCTUnwrap(ProtectionPrivacyCatalog.browser(.chrome))
        let source = ProtectionTraceSource(id: "chrome", title: "Google Chrome", browser: browser, profiles: ["Work", "Home"],
                                           traces: [trace(.cookies), trace(.history), trace(.cache)], isUnreadable: false)
        let group = try XCTUnwrap(source.scanGroup(isRunning: false))
        XCTAssertEqual(group.id, "protection.privacy.chrome")
        XCTAssertEqual(ProtectionPrivacyGroup.sourceID(groupID: group.id), "chrome")
        XCTAssertEqual(group.items.map { $0.metadata[ProtectionPrivacyMetaKey.kind] }, ["history", "cookies", "cache"])
        XCTAssertEqual(group.safety, .review, "Cookies make the whole group a review group")
        XCTAssertTrue(group.items[0].isSelected, "History is safe and pre-selected")
        XCTAssertFalse(group.items[1].isSelected, "Cookies sign you out, so they're never pre-selected")
        XCTAssertTrue(group.detail.contains("Work, Home"))
        XCTAssertFalse(group.items.contains { $0.protectionBrowserWasRunning })
        XCTAssertTrue(group.items.allSatisfy { $0.deletion == .custom && $0.url == nil })
    }

    func testPrivacyGroupMarksRunningBrowser() throws {
        let browser = try XCTUnwrap(ProtectionPrivacyCatalog.browser(.firefox))
        let source = ProtectionTraceSource(id: "firefox", title: "Firefox", browser: browser, profiles: ["default-release"],
                                           traces: [trace(.cache, source: "firefox")], isUnreadable: false)
        let group = try XCTUnwrap(source.scanGroup(isRunning: true))
        XCTAssertTrue(group.items.allSatisfy(\.protectionBrowserWasRunning))
        XCTAssertTrue(group.detail.contains("is open"))
        XCTAssertEqual(group.symbol, "flame")
        let plan = try XCTUnwrap(ProtectionPrivacyPlan(item: group.items[0]))
        XCTAssertEqual(plan.sourceID, "firefox")
        XCTAssertEqual(plan.files.map(\.path), ["/tmp/firefox/cache"])
    }

    func testEmptyPrivacySourceHasNoGroup() {
        let source = ProtectionTraceSource(id: "safari", title: "Safari", browser: ProtectionPrivacyCatalog.browser(.safari),
                                           profiles: [], traces: [], isUnreadable: true)
        XCTAssertNil(source.scanGroup(isRunning: false))
    }

    // MARK: Permissions

    private func grant(_ service: String, _ client: String, type: Int = 0, auth: ProtectionTCCAuth = .allowed,
                       db: ProtectionTCCDatabase = .user, indirect: String? = nil) -> ProtectionTCCGrant {
        ProtectionTCCGrant(service: service, client: client, clientType: type, auth: auth, authReason: 2,
                           lastModified: Date(timeIntervalSince1970: 1_700_000_000), indirectObject: indirect, database: db)
    }

    func testPermissionGroupsListOnlyGrantedAppsAndNeverPreselect() throws {
        let grants = [
            grant("kTCCServiceCamera", "us.zoom.xos"),
            grant("kTCCServiceCamera", "com.old.Gone"),
            grant("kTCCServiceCamera", "com.denied.App", auth: .denied),
            grant("kTCCServiceScreenCapture", "/usr/local/bin/recorder", type: 1, db: .system),
            grant("kTCCServiceMicrophone", "com.denied.App", auth: .denied),
            grant("kTCCServiceSomethingInternal", "com.apple.x"),
        ]
        let groups = ProtectionPermissionGroup.scanGroups(grants) { grant in
            if grant.client == "com.old.Gone" {
                return ProtectionPermissionClient(displayName: grant.client, appPath: nil, isMissing: true)
            }
            return ProtectionPermissionClient(displayName: grant.client == "us.zoom.xos" ? "zoom.us" : grant.client,
                                              appPath: "/Applications/x.app", isMissing: false)
        }
        XCTAssertEqual(groups.map(\.title), ["Screen & System Audio Recording", "Camera"], "Catalog order, empty services dropped")
        XCTAssertTrue(groups.allItems.allSatisfy { !$0.isSelected && $0.safety == .review && $0.deletion == .custom })

        let camera = try XCTUnwrap(groups.first { $0.id == "protection.permissions.kTCCServiceCamera" })
        XCTAssertEqual(camera.items.map(\.title), ["com.old.Gone", "zoom.us"], "Leftover grants first, denied grants hidden")
        XCTAssertEqual(camera.items[0].metadata[ProtectionPermissionMetaKey.missing], "1")
        XCTAssertTrue(camera.items[0].subtitle?.contains("App not found") == true)

        let zoomPlan = try XCTUnwrap(ProtectionPermissionPlan(item: camera.items[1]))
        XCTAssertEqual(zoomPlan.resetArguments, ["reset", "Camera", "us.zoom.xos"])
        XCTAssertEqual(zoomPlan.settingsURL, "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")

        let screen = try XCTUnwrap(groups.first { $0.title == "Screen & System Audio Recording" })
        let pathPlan = try XCTUnwrap(ProtectionPermissionPlan(item: screen.items[0]))
        XCTAssertNil(pathPlan.resetArguments, "Path clients can't be reset with tccutil")
        XCTAssertEqual(screen.items[0].subtitle, "/usr/local/bin/recorder")
    }

    func testAutomationGrantShowsTarget() throws {
        let groups = ProtectionPermissionGroup.scanGroups([grant("kTCCServiceAppleEvents", "com.example.Tool",
                                                                 indirect: "com.apple.finder")]) { _ in
            ProtectionPermissionClient(displayName: "Tool", appPath: nil, isMissing: false)
        }
        let item = try XCTUnwrap(groups.first?.items.first)
        XCTAssertEqual(item.subtitle, "Can control com.apple.finder")
        XCTAssertEqual(ProtectionPermissionPlan(item: item)?.resetArguments, ["reset", "AppleEvents", "com.example.Tool"])
    }

    func testBundleIDValidationRejectsInjectionAndBareForms() {
        XCTAssertTrue(ProtectionTCCGrant.isValidBundleID("com.google.Chrome"))
        XCTAssertTrue(ProtectionTCCGrant.isValidBundleID("org.mozilla.firefox_beta"))
        XCTAssertFalse(ProtectionTCCGrant.isValidBundleID(""))
        XCTAssertFalse(ProtectionTCCGrant.isValidBundleID("-all"))
        XCTAssertFalse(ProtectionTCCGrant.isValidBundleID("com.x; rm -rf ~"))
        XCTAssertFalse(ProtectionTCCGrant.isValidBundleID("/Applications/X.app"))
        XCTAssertNil(ProtectionPermissionPlan(item: ScanItem(id: "x", title: "x")))
    }

    func testAccessDeniedDetection() {
        XCTAssertTrue(ProtectionTCCParser.isAccessDenied("Error: unable to open database \"TCC.db\": authorization denied"))
        XCTAssertFalse(ProtectionTCCParser.isAccessDenied(""))
    }

    // MARK: Checkup

    private func finding(_ id: String, category: ThreatCategory, evidence: ThreatEvidence) -> ProtectionThreatFinding {
        ProtectionThreatFinding(id: "/Users/me/\(id)", name: id, family: evidence == .heuristic ? nil : "Adload",
                                category: category, severity: .high, evidence: evidence, reasons: ["Reason"],
                                kind: .launchAgent, path: "/Users/me/\(id)", score: 60)
    }

    func testCheckupTileStates() {
        let clear = ProtectionCheckupSummary.tile(for: [])
        XCTAssertEqual(clear.status, .clear)
        XCTAssertFalse(clear.isSelected)
        XCTAssertEqual(ProtectionCheckupSummary.tile(for: [], unreadableLocations: 2).detail.contains("Full Disk Access"), true)

        let known = ProtectionThreatFinding.scanGroups([finding("a", category: .adware, evidence: .knownIndicator),
                                                        finding("b", category: .suspicious, evidence: .heuristic)])
        let critical = ProtectionCheckupSummary.tile(for: known)
        XCTAssertEqual(critical.status, .critical)
        XCTAssertTrue(critical.isSelected)
        XCTAssertEqual(critical.actionCount, 1)
        XCTAssertEqual(critical.headline, "2 threats")

        let suspicious = ProtectionThreatFinding.scanGroups([finding("c", category: .suspicious, evidence: .heuristic)])
        let attention = ProtectionCheckupSummary.tile(for: suspicious)
        XCTAssertEqual(attention.status, .attention)
        XCTAssertFalse(attention.isSelected)
    }

    // MARK: Real-time

    func testLaunchWatchReportsOnlyNewThirdPartyPlists() {
        let added = ProtectionLaunchWatch.addedItems(
            previous: ["com.vendor.updater.plist"],
            current: ["com.vendor.updater.plist", "com.apple.thing.plist", ".hidden.plist", "com.evil.agent.plist",
                      "notes.txt", "Com.Apple.Other.plist"])
        XCTAssertEqual(added, ["com.evil.agent.plist"])
    }

    func testRealtimeEventText() {
        let plain = ProtectionRealtimeEvent(path: "/Users/me/Library/LaunchAgents/com.vendor.sync.plist",
                                            label: "com.vendor.sync", domain: .user, kind: .launchAgent, finding: nil)
        XCTAssertFalse(plain.isThreat)
        XCTAssertEqual(plain.notificationTitle, "New startup item")
        XCTAssertTrue(plain.notificationBody.hasPrefix("com.vendor.sync will now run automatically"))

        let threat = ProtectionRealtimeEvent(path: "/Library/LaunchDaemons/com.evil.plist", label: "com.evil", domain: .system,
                                             kind: .launchDaemon,
                                             finding: finding("evil", category: .adware, evidence: .knownIndicator))
        XCTAssertTrue(threat.isThreat)
        XCTAssertEqual(threat.notificationTitle, "Threat added to startup items")
        XCTAssertTrue(threat.notificationBody.contains("Adload"))
        XCTAssertEqual(threat.location, "/Library/LaunchDaemons")
    }

    // MARK: XProtect

    func testXProtectVersionParsing() {
        let output = "Version: 5297\nInstalled: 2025-01-28 19:57:47 +0000\n"
        let parsed = ProtectionXProtectParser.parseVersionCommand(output)
        XCTAssertEqual(parsed.version, "5297")
        XCTAssertEqual(parsed.installed, Date(timeIntervalSince1970: 1_738_094_267))

        XCTAssertEqual(ProtectionXProtectParser.parseVersionCommand("XProtect version 5310").version, "5310")
        XCTAssertEqual(ProtectionXProtectParser.parseVersionCommand("Version: 2.1.10.\n").version, "2.1.10")
        let empty = ProtectionXProtectParser.parseVersionCommand("")
        XCTAssertNil(empty.version)
        XCTAssertNil(empty.installed)
    }
}
