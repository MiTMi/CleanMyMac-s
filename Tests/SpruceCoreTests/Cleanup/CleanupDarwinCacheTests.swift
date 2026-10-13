import Foundation
import XCTest
@testable import SpruceCore

/// Rules for the per-user cache folder (`$DARWIN_CACHE`, `/private/var/folders/…/C`).
final class CleanupDarwinCacheTests: XCTestCase {
    private var fx: CleanupFixture!
    private let day = CleanupFixture.day
    private var cache: String { fx.root + "/C" }

    override func setUp() {
        super.setUp()
        fx = CleanupFixture()
        fx.directory("C", in: fx.root)
    }

    override func tearDown() {
        fx.remove()
        super.tearDown()
    }

    /// Creates `relative` below the cache folder, `age` old, with its folders aged too.
    @discardableResult
    private func cached(_ relative: String, bytes: Int = 8_192, age: TimeInterval = 3 * 86_400) -> String {
        let path = fx.file(relative, bytes: bytes, age: age, in: cache)
        fx.ageFolders((path as NSString).deletingLastPathComponent, upTo: cache, age: age)
        return path
    }

    private func context(running: Set<String> = [], quittable: Set<String>? = nil, processes: Set<String> = [],
                         purpose: CleanupScanPurpose = .module) -> CleanupContext {
        fx.context(running: running, quittable: quittable, processes: processes, purpose: purpose, cacheDir: cache)
    }

    private func size(of relative: String) -> Int64 {
        DiskUsage.measure(cache + "/" + relative).bytes
    }

    private func rows(_ report: CleanupScanReport, rule: String) -> [ScanItem] {
        report.groups.allItems.filter { $0.metadata[CleanupMetadataKey.ruleID] == rule }
    }

    // MARK: Developer tools

    func testCompilerModuleCacheIsXcodeJunk() throws {
        cached("clang/ModuleCache/3J1VZ1S2DQ0QO/Foundation-ABC.pcm", bytes: 60_000)
        cached("clang/ModuleCache/2R6XKX4Q8N5ZK/Swift-DEF.pcm", bytes: 10_000, age: 600)
        let (_, report) = fx.scan(context(), sections: [.systemJunk])
        let row = try XCTUnwrap(rows(report, rule: "xcode.clangModuleCache").first)
        XCTAssertTrue(report.items(in: CleanupCategory.xcodeJunk.rawValue).contains(row))
        XCTAssertEqual(row.title, "Compiler Module Cache")
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(row.size, size(of: "clang/ModuleCache/3J1VZ1S2DQ0QO"), "a module folder used in the last day stays")

        let (scanner, busy) = fx.scan(context(processes: ["swift-frontend"]), sections: [.systemJunk])
        let blocked = try XCTUnwrap(rows(busy, rule: "xcode.clangModuleCache").first)
        XCTAssertFalse(blocked.isSelected)
        XCTAssertNotNil(scanner.blockingReason(for: blocked))
    }

    func testDeveloperToolsAndSimulatorCachesAreXcodeJunk() throws {
        cached("com.apple.DeveloperTools/All/Xcode/EmbeddedAppDeltas/x.delta")
        cached("com.apple.CoreSimulator.SimRenderingServices.SimMetalHost/com.apple.metal/1/functions.data")
        let (_, report) = fx.scan(context(), sections: [.systemJunk])
        XCTAssertEqual(rows(report, rule: "xcode.developerToolsCache").count, 1)
        let simulator = try XCTUnwrap(rows(report, rule: "xcode.simulatorShaders").first)
        XCTAssertTrue(simulator.isSelected)
        XCTAssertTrue(rows(report, rule: "caches.gpuShaders").isEmpty, "the Simulator's shaders are counted once")
        XCTAssertTrue(rows(report, rule: "caches.darwinApps").isEmpty, "Apple's folders aren't app caches")

        let (_, booted) = fx.scan(context(processes: ["launchd_sim"]), sections: [.systemJunk])
        XCTAssertFalse(try XCTUnwrap(rows(booted, rule: "xcode.simulatorShaders").first).isSelected)
    }

    // MARK: Apple's folders

    func testSafariSafeBrowsingQuitsSafariFirst() throws {
        cached("com.apple.Safari.SafeBrowsing/Google/db.sqlite")
        let (_, idle) = fx.scan(context(), sections: [.systemJunk])
        let row = try XCTUnwrap(rows(idle, rule: "caches.safariSafeBrowsing").first)
        XCTAssertEqual(row.title, "Safari Safe Browsing Data")
        XCTAssertTrue(row.isSelected)
        XCTAssertTrue(idle.items(in: CleanupCategory.systemCaches.rawValue).contains(row))

        let (_, open) = fx.scan(context(running: ["com.apple.Safari"], quittable: ["com.apple.Safari"]),
                                sections: [.systemJunk])
        let quit = try XCTUnwrap(rows(open, rule: "caches.safariSafeBrowsing").first)
        XCTAssertTrue(quit.isSelected)
        XCTAssertEqual(quit.metadata[CleanupMetadataKey.quitToClean], "1")

        // Its background service keeps the list open: listed, not ticked.
        let (_, service) = fx.scan(context(running: ["com.apple.Safari.SafeBrowsing.Service"], quittable: []),
                                   sections: [.systemJunk])
        XCTAssertFalse(try XCTUnwrap(rows(service, rule: "caches.safariSafeBrowsing").first).isSelected)
    }

    func testMediaAnalysisIsListedForReview() throws {
        cached("com.apple.mediaanalysisd/cache.db")
        let (_, report) = fx.scan(context(), sections: [.systemJunk])
        let row = try XCTUnwrap(rows(report, rule: "caches.mediaAnalysis").first)
        XCTAssertEqual(row.safety, .review)
        XCTAssertFalse(row.isSelected)
    }

    func testAppleIconDockAndFontCachesAreNeverListed() {
        for name in ["com.apple.dock.iconcache", "com.apple.FontRegistry", "com.apple.iconservices",
                     "com.apple.iconservicesagent", "com.apple.LaunchServices-1234"] {
            cached("\(name)/store.data", bytes: 40_000)
        }
        cached("mds/index", bytes: 40_000)
        let (_, report) = fx.scan(context())
        let listed = report.groups.allItems.compactMap(\.url?.path).filter { $0.hasPrefix(cache) }
        XCTAssertEqual(listed, [])
    }

    // MARK: GPU shaders

    func testMacOSShaderCacheIsCounted() throws {
        cached("com.apple.metal/16777235_324/functions.data", bytes: 40_000)
        cached("com.apple.metal/16777235_325/functions.data", bytes: 40_000, age: 600)
        let (_, report) = fx.scan(context(), sections: [.systemJunk])
        let row = try XCTUnwrap(rows(report, rule: "caches.systemShaders").first)
        XCTAssertEqual(row.title, "macOS Shader Cache")
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(row.itemCount, 1, "shaders used in the last day stay")
    }

    func testOpenAppsShadersAskToQuitTheAppFirst() throws {
        cached("com.example.editor/com.apple.metal/1/functions.data", age: 600)
        let (_, open) = fx.scan(context(running: ["com.example.editor"], quittable: ["com.example.editor"]),
                                sections: [.systemJunk])
        let row = try XCTUnwrap(rows(open, rule: "caches.gpuShaders").first)
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(row.metadata[CleanupMetadataKey.quitToClean], "1")
    }

    // MARK: Other apps' folders

    func testAppFoldersAreAppCachesWithTheirShadersCountedOnce() throws {
        cached("com.brave.Browser.helper/com.apple.metal/1/functions.data", bytes: 40_000)
        cached("com.brave.Browser.helper/net/blob.bin", bytes: 20_000)
        let (scanner, report) = fx.scan(context(), sections: [.systemJunk])

        let gpu = try XCTUnwrap(rows(report, rule: "caches.gpuShaders").first)
        XCTAssertEqual(gpu.size, size(of: "com.brave.Browser.helper/com.apple.metal/1"))
        let app = try XCTUnwrap(rows(report, rule: "caches.darwinApps").first)
        XCTAssertEqual(app.title, "com.brave.Browser.helper")
        XCTAssertEqual(app.size, size(of: "com.brave.Browser.helper/net"))
        XCTAssertTrue(app.isSelected)
        XCTAssertEqual(app.metadata[CleanupMetadataKey.owner], "com.brave.Browser.helper")

        let targets = scanner.expand(app).targets.compactMap(\.url?.path)
        XCTAssertEqual(targets, [cache + "/com.brave.Browser.helper/net"], "the shaders stay with their own row")
    }

    func testOpenAppFolderAsksToQuitTheAppFirst() throws {
        cached("com.example.editor/Cache/blob.bin", age: 2 * 3_600)
        let (_, open) = fx.scan(context(running: ["com.example.editor"], quittable: ["com.example.editor"]),
                                sections: [.systemJunk])
        let row = try XCTUnwrap(rows(open, rule: "caches.darwinApps").first)
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(row.metadata[CleanupMetadataKey.quitToClean], "1")

        // A helper that runs on its own (not quittable from the sheet): listed, not ticked.
        let (_, helper) = fx.scan(context(running: ["com.example.editor.helper"], quittable: []),
                                  sections: [.systemJunk])
        XCTAssertFalse(try XCTUnwrap(rows(helper, rule: "caches.darwinApps").first).isSelected)
    }

    func testAppleFolderRowsAreRefusedAtCleanTime() throws {
        cached("com.apple.dock.iconcache/store.data")
        let (scanner, _) = fx.scan(context(), sections: [.systemJunk])
        let forged = ScanItem(id: cache + "/com.apple.dock.iconcache", title: "Dock", url: URL(fileURLWithPath: cache + "/com.apple.dock.iconcache"),
                              size: 1, metadata: [CleanupMetadataKey.ruleID: "caches.darwinApps",
                                                  CleanupMetadataKey.mode: "contents"])
        let expansion = scanner.expand(forged)
        XCTAssertTrue(expansion.targets.isEmpty)
        XCTAssertNotNil(expansion.failure)
    }
}
