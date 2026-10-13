import Foundation
import XCTest
@testable import SpruceCore

final class ProtectionPrivacyTests: XCTestCase {
    var fx: ProtectionFixture!

    override func setUp() {
        super.setUp()
        fx = ProtectionFixture()
    }

    override func tearDown() {
        fx.remove()
        super.tearDown()
    }

    private func scanner(quickLook: String? = nil) -> ProtectionPrivacyScanner {
        ProtectionPrivacyScanner(space: ProtectionPathSpace(home: fx.home), quickLookCachePath: quickLook)
    }

    func testChromiumTraces() throws {
        let profile = "~/Library/Application Support/Google/Chrome/Default"
        fx.file(profile + "/Preferences", Data("{}".utf8))
        fx.file(profile + "/History", Data(repeating: 1, count: 4096))
        fx.file(profile + "/History-journal")
        fx.file(profile + "/Cookies")
        fx.file(profile + "/Web Data")
        fx.file(profile + "/Login Data")
        fx.file(profile + "/IndexedDB/https_example.com_0.indexeddb.leveldb/000001.log")
        fx.file(profile + "/IndexedDB/chrome-extension_abcdef_0.indexeddb.leveldb/000001.log")
        fx.file(profile + "/Local Storage/leveldb/000001.log")
        fx.file("~/Library/Caches/Google/Chrome/Default/Cache/Cache_Data/data_0", Data(repeating: 2, count: 8192))
        let localState: [String: Any] = ["profile": ["info_cache": ["Default": ["name": "Personal"]]]]
        fx.file("~/Library/Application Support/Google/Chrome/Local State", try JSONSerialization.data(withJSONObject: localState))

        let sources = scanner().scan(includeSystem: false)
        let chrome = try XCTUnwrap(sources.first { $0.id == "chrome" })
        XCTAssertEqual(chrome.profiles, ["Personal"])
        let byKind = Dictionary(uniqueKeysWithValues: chrome.traces.map { ($0.kind, $0) })

        let history = try XCTUnwrap(byKind[.history])
        XCTAssertEqual(history.safety, .safe)
        XCTAssertEqual(Set(history.files.map { ($0.path as NSString).lastPathComponent }), ["History", "History-journal"])
        XCTAssertTrue(history.files.allSatisfy { $0.deletion == .trash })

        XCTAssertEqual(byKind[.cookies]?.safety, .review)
        XCTAssertEqual(byKind[.autofill]?.safety, .review)

        let cache = try XCTUnwrap(byKind[.cache])
        XCTAssertEqual(cache.files.first?.deletion, .remove, "Caches under ~/Library/Caches are removed permanently")

        let siteData = try XCTUnwrap(byKind[.siteData])
        XCTAssertTrue(siteData.files.contains { $0.path.hasSuffix("https_example.com_0.indexeddb.leveldb") })
        XCTAssertFalse(siteData.files.contains { $0.path.contains("chrome-extension_") }, "Extension storage is never touched")
        XCTAssertFalse(siteData.files.contains { $0.path.contains("Local Storage") })

        let allPaths = chrome.traces.flatMap(\.files).map(\.path)
        XCTAssertFalse(allPaths.contains { $0.hasSuffix("Login Data") }, "Saved passwords are never offered")
    }

    func testFirefoxTracesKeepBookmarksUnselected() throws {
        let profile = "~/Library/Application Support/Firefox/Profiles/abcd1234.default-release"
        fx.file(profile + "/places.sqlite")
        fx.file(profile + "/cookies.sqlite")
        fx.file(profile + "/formhistory.sqlite")
        fx.file(profile + "/logins.json")
        fx.file(profile + "/storage/default/https+++example.com/ls/data.sqlite")
        fx.file(profile + "/storage/default/moz-extension+++1234/idb/x.sqlite")
        fx.file("~/Library/Caches/Firefox/Profiles/abcd1234.default-release/cache2/entries/x")

        let firefox = try XCTUnwrap(scanner().scan(includeSystem: false).first { $0.id == "firefox" })
        XCTAssertEqual(firefox.profiles, ["default-release"])
        let byKind = Dictionary(uniqueKeysWithValues: firefox.traces.map { ($0.kind, $0) })
        XCTAssertEqual(byKind[.history]?.safety, .review, "places.sqlite also holds bookmarks")
        XCTAssertNotNil(byKind[.cache])
        XCTAssertFalse(firefox.traces.flatMap(\.files).contains { $0.path.hasSuffix("logins.json") })
        XCTAssertFalse(byKind[.siteData]?.files.contains { $0.path.contains("moz-extension") } ?? true)
        XCTAssertTrue(byKind[.siteData]?.files.contains { $0.path.contains("https+++example.com") } ?? false)
    }

    func testSafariAndSystemTraces() throws {
        fx.file("~/Library/Safari/History.db")
        fx.file("~/Library/Safari/History.db-wal")
        fx.file("~/Library/Safari/Downloads.plist")
        fx.file("~/Library/Safari/Bookmarks.plist")
        fx.file("~/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db")
        let shared = "~/Library/Application Support/com.apple.sharedfilelist"
        fx.file(shared + "/com.apple.LSSharedFileList.RecentDocuments.sfl3")
        fx.file(shared + "/com.apple.LSSharedFileList.RecentApplications.sfl3")
        fx.file(shared + "/com.apple.LSSharedFileList.FavoriteItems.sfl3")
        fx.file(shared + "/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.apple.textedit.sfl3")
        let quickLook = fx.directory("/var/folders/xx/C/com.apple.QuickLook.thumbnailcache")
        fx.file("/var/folders/xx/C/com.apple.QuickLook.thumbnailcache/index.sqlite", Data(repeating: 3, count: 2048))

        let sources = scanner(quickLook: quickLook).scan()
        let safari = try XCTUnwrap(sources.first { $0.id == "safari" })
        XCTAssertFalse(safari.isUnreadable)
        let kinds = Set(safari.traces.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.history, .downloads]))
        let safariPaths = safari.traces.flatMap(\.files).map(\.path)
        XCTAssertFalse(safariPaths.contains { $0.hasSuffix("Bookmarks.plist") })
        XCTAssertFalse(safariPaths.contains { $0.hasSuffix("SafariTabs.db") }, "Open tabs and tab groups are left alone")

        let system = try XCTUnwrap(sources.first { $0.id == ProtectionTraceSource.systemID })
        let recent = try XCTUnwrap(system.traces.first { $0.kind == .recentItems })
        let names = Set(recent.files.map { ($0.path as NSString).lastPathComponent })
        XCTAssertEqual(names, ["com.apple.LSSharedFileList.RecentDocuments.sfl3",
                               "com.apple.LSSharedFileList.RecentApplications.sfl3", "com.apple.textedit.sfl3"])
        let ql = try XCTUnwrap(system.traces.first { $0.kind == .quickLookThumbnails })
        XCTAssertEqual(ql.customAction, ProtectionTrace.quickLookResetAction)
        XCTAssertGreaterThan(ql.size, 0)
        XCTAssertEqual(ql.safety, .safe)
    }

    func testPrivacyPlanRoundTrip() throws {
        fx.file("~/Library/Application Support/Google/Chrome/Default/Preferences", Data("{}".utf8))
        fx.file("~/Library/Application Support/Google/Chrome/Default/Cookies")
        let chrome = try XCTUnwrap(scanner().scan(includeSystem: false).first { $0.id == "chrome" })
        let cookies = try XCTUnwrap(chrome.traces.first { $0.kind == .cookies })
        let item = cookies.scanItem
        XCTAssertEqual(item.deletion, .custom)
        XCTAssertFalse(item.isSelected)
        let plan = try XCTUnwrap(ProtectionPrivacyPlan(item: item))
        XCTAssertEqual(plan.sourceID, "chrome")
        XCTAssertEqual(plan.kind, .cookies)
        XCTAssertEqual(plan.files.map(\.path), cookies.files.map(\.path))
        XCTAssertEqual(plan.files.first?.deletion, .trash)
    }

    func testNoBrowserDataMeansNoSources() {
        XCTAssertTrue(scanner().scan(includeSystem: false).isEmpty)
    }
}

final class ProtectionPermissionsTests: XCTestCase {
    let sample = """
    [{"service":"kTCCServiceCamera","client":"us.zoom.xos","client_type":0,"auth_value":2,"auth_reason":2,"last_modified":1700000000,"indirect":""},
    {"service":"kTCCServiceMicrophone","client":"us.zoom.xos","client_type":0,"auth_value":0,"auth_reason":2,"last_modified":1700000100,"indirect":""},
    {"service":"kTCCServiceAppleEvents","client":"com.example.automator","client_type":0,"auth_value":2,"auth_reason":3,"last_modified":0,"indirect":"com.apple.finder"},
    {"service":"kTCCServiceUbiquity","client":"com.example.cloud","client_type":0,"auth_value":2,"auth_reason":2,"last_modified":1,"indirect":"UNUSED"},
    {"service":"kTCCServiceCamera","client":"/usr/local/bin/tool","client_type":1,"auth_value":3,"auth_reason":2,"last_modified":5,"indirect":""}]
    """

    func testParsesSqliteJSON() {
        let grants = ProtectionTCCParser.parse(json: sample, database: .user)
        XCTAssertEqual(grants.count, 5)
        let camera = grants.first { $0.service == "kTCCServiceCamera" && $0.isBundleClient }
        XCTAssertEqual(camera?.auth, .allowed)
        XCTAssertEqual(camera?.lastModified, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(grants.first { $0.service == "kTCCServiceMicrophone" }?.auth, .denied)
        XCTAssertEqual(grants.first { $0.service == "kTCCServiceAppleEvents" }?.indirectObject, "com.apple.finder")
        XCTAssertNil(grants.first { $0.service == "kTCCServiceAppleEvents" }?.lastModified)
        XCTAssertNil(grants.first { $0.service == "kTCCServiceUbiquity" }?.indirectObject)
        XCTAssertEqual(grants.first { !$0.isBundleClient }?.auth, .limited)
        XCTAssertTrue(ProtectionTCCParser.parse(json: "", database: .user).isEmpty)
        XCTAssertTrue(ProtectionTCCParser.parse(json: "not json", database: .user).isEmpty)
    }

    func testGroupsFollowCatalogAndDropInternalServices() {
        let grants = ProtectionTCCParser.parse(json: sample, database: .user)
            + ProtectionTCCParser.parse(json: sample, database: .system)
        let groups = ProtectionPermissionGroup.groups(from: grants, includeEmpty: false)
        XCTAssertFalse(groups.contains { $0.service.id == "kTCCServiceUbiquity" })
        let camera = groups.first { $0.service.id == "kTCCServiceCamera" }
        XCTAssertEqual(camera?.grants.count, 2, "Same client in both databases is listed once")
        XCTAssertEqual(camera?.grantedCount, 2)
        let mic = groups.first { $0.service.id == "kTCCServiceMicrophone" }
        XCTAssertEqual(mic?.grantedCount, 0)

        let all = ProtectionPermissionGroup.groups(from: [], includeEmpty: true)
        XCTAssertEqual(all.count, ProtectionTCCCatalog.services.count)
    }

    func testServiceCatalog() {
        let ids = ProtectionTCCCatalog.services.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let camera = ProtectionTCCCatalog.service("kTCCServiceCamera")
        XCTAssertEqual(camera?.tccutilName, "Camera")
        XCTAssertEqual(camera?.settingsURLString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        XCTAssertNil(ProtectionTCCCatalog.service(ProtectionTCCCatalog.locationServicesID)?.tccutilName)
        for service in ProtectionTCCCatalog.services where service.id != ProtectionTCCCatalog.locationServicesID {
            XCTAssertEqual("kTCCService" + (service.tccutilName ?? ""), service.id)
        }
    }
}
