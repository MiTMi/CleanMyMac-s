import Foundation
import XCTest
@testable import SpruceCore

final class CleanupSimulatorRuntimeTests: XCTestCase {
    private var fx: CleanupFixture!

    override func setUp() {
        super.setUp()
        fx = CleanupFixture()
    }

    override func tearDown() {
        fx.remove()
        super.tearDown()
    }

    // MARK: Parsing `simctl runtime list -j`

    private let listJSON = """
    {
      "0A1B2C3D-0000-4000-8000-000000000001" : {
        "build" : "21A328",
        "deletable" : true,
        "identifier" : "0A1B2C3D-0000-4000-8000-000000000001",
        "kind" : "Disk Image",
        "lastUsedAt" : "2024-05-01T10:20:30.123Z",
        "path" : "/Library/Developer/CoreSimulator/Images/0A1B2C3D-0000-4000-8000-000000000001.dmg",
        "platformIdentifier" : "com.apple.platform.iphonesimulator",
        "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
        "sizeBytes" : 7516192768,
        "state" : "Ready",
        "version" : "17.0"
      },
      "0A1B2C3D-0000-4000-8000-000000000002" : {
        "build" : "21R355",
        "deletable" : false,
        "identifier" : "0A1B2C3D-0000-4000-8000-000000000002",
        "platformIdentifier" : "com.apple.platform.watchsimulator",
        "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.watchOS-10-0",
        "sizeBytes" : 3221225472,
        "version" : "10.0"
      },
      "0A1B2C3D-0000-4000-8000-000000000003" : {
        "deletable" : true,
        "identifier" : "0A1B2C3D-0000-4000-8000-000000000003",
        "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.xrOS-1-0",
        "sizeBytes" : 1024,
        "version" : "1.0"
      },
      "not-a-uuid; rm -rf /" : {
        "deletable" : true,
        "identifier" : "--all",
        "sizeBytes" : 1,
        "version" : "1.0"
      },
      "broken" : "oops"
    }
    """

    func testParsesRuntimeList() throws {
        let runtimes = CleanupSimulatorRuntimes.parse(Data(listJSON.utf8))
        XCTAssertEqual(runtimes.map(\.platform), ["iOS", "visionOS", "watchOS"])
        let ios = try XCTUnwrap(runtimes.first)
        XCTAssertEqual(ios.identifier, "0A1B2C3D-0000-4000-8000-000000000001")
        XCTAssertEqual(ios.version, "17.0")
        XCTAssertEqual(ios.build, "21A328")
        XCTAssertEqual(ios.sizeBytes, 7_516_192_768)
        XCTAssertEqual(ios.path, "/Library/Developer/CoreSimulator/Images/0A1B2C3D-0000-4000-8000-000000000001.dmg")
        XCTAssertTrue(ios.isDeletable)
        let lastUsed = try XCTUnwrap(ios.lastUsed)
        XCTAssertEqual(lastUsed.timeIntervalSince1970, 1_714_558_830.123, accuracy: 0.01)
        XCTAssertFalse(runtimes[2].isDeletable)
        XCTAssertNil(runtimes[1].lastUsed)
    }

    func testMalformedOutputGivesNothing() {
        XCTAssertTrue(CleanupSimulatorRuntimes.parse(Data()).isEmpty)
        XCTAssertTrue(CleanupSimulatorRuntimes.parse(Data("[1, 2]".utf8)).isEmpty)
        XCTAssertTrue(CleanupSimulatorRuntimes.parse(Data("No runtimes".utf8)).isEmpty)
    }

    func testOnlyUUIDsArePassedToSimctl() {
        XCTAssertTrue(CleanupSimulatorRuntimes.isValidIdentifier("0A1B2C3D-0000-4000-8000-000000000001"))
        XCTAssertFalse(CleanupSimulatorRuntimes.isValidIdentifier(""))
        XCTAssertFalse(CleanupSimulatorRuntimes.isValidIdentifier("--all"))
        XCTAssertFalse(CleanupSimulatorRuntimes.isValidIdentifier("-0A1B"))
        XCTAssertFalse(CleanupSimulatorRuntimes.isValidIdentifier("all"))
        XCTAssertFalse(CleanupSimulatorRuntimes.isValidIdentifier("0A1B 2C3D"))
        XCTAssertFalse(CleanupSimulatorRuntimes.isValidIdentifier(String(repeating: "a", count: 65)))
    }

    // MARK: Scanner rows

    private func runtime(_ n: Int, platform: String = "iOS", version: String = "17.0", size: Int64 = 7_000_000_000,
                         path: String? = nil, deletable: Bool = true) -> CleanupSimulatorRuntime {
        CleanupSimulatorRuntime(identifier: String(format: "0A1B2C3D-0000-4000-8000-%012d", n), platform: platform,
                                version: version, build: "21A328", sizeBytes: size, path: path, isDeletable: deletable)
    }

    private func context(_ runtimes: [CleanupSimulatorRuntime], processes: Set<String> = [],
                         purpose: CleanupScanPurpose = .module) -> CleanupContext {
        var context = fx.context(processes: processes, purpose: purpose)
        context.simulatorRuntimes = runtimes
        return context
    }

    func testRuntimesAreListedUnderXcodeJunkUnselected() throws {
        let image = fx.file("CoreSimulator/Images/one.dmg", bytes: 4_096, in: fx.system)
        let (scanner, report) = fx.scan(context([runtime(1, path: image), runtime(2, platform: "tvOS", version: "17.2")]),
                                        sections: [.systemJunk])
        let items = report.items(in: CleanupCategory.xcodeJunk.rawValue)
            .filter { $0.metadata[CleanupMetadataKey.ruleID] == "xcode.simulatorRuntimes" }
        XCTAssertEqual(items.count, 2)
        let ios = try XCTUnwrap(items.first { $0.title == "iOS 17.0 Simulator" })
        XCTAssertEqual(ios.id, "simulator-runtime:0A1B2C3D-0000-4000-8000-000000000001")
        XCTAssertEqual(ios.size, 7_000_000_000, "simctl's size, not the sparse image's")
        XCTAssertEqual(ios.safety, .review)
        XCTAssertFalse(ios.isSelected)
        XCTAssertEqual(ios.url?.path, image)
        XCTAssertEqual(ios.metadata[CleanupMetadataKey.mode], "simulatorRuntime")
        XCTAssertEqual(ios.metadata[CleanupMetadataKey.simulatorRuntime], "0A1B2C3D-0000-4000-8000-000000000001")
        XCTAssertEqual(ios.metadata[CleanupMetadataKey.recommended], "0")
        XCTAssertNil(ios.metadata[CleanupMetadataKey.inUse])
        XCTAssertNil(scanner.blockingReason(for: ios))
        let tv = try XCTUnwrap(items.first { $0.title == "tvOS 17.2 Simulator" })
        XCTAssertNil(tv.url, "no URL for an image that isn't on disk")
    }

    func testRuntimesAreNeverRemovedAsFiles() throws {
        let image = fx.file("CoreSimulator/Images/one.dmg", bytes: 4_096, in: fx.system)
        let (scanner, report) = fx.scan(context([runtime(1, path: image)]), sections: [.systemJunk])
        let item = try XCTUnwrap(report.item(endingWith: "0A1B2C3D-0000-4000-8000-000000000001"))
        let expansion = scanner.expand(item)
        XCTAssertTrue(expansion.targets.isEmpty)
        XCTAssertNotNil(expansion.failure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image))
    }

    func testRunningSimulatorBlocksRemoval() throws {
        let (scanner, report) = fx.scan(context([runtime(1)], processes: ["launchd_sim"]), sections: [.systemJunk])
        let item = try XCTUnwrap(report.item(endingWith: "0A1B2C3D-0000-4000-8000-000000000001"))
        XCTAssertFalse(item.isSelected)
        XCTAssertEqual(item.metadata[CleanupMetadataKey.inUse], "1")
        XCTAssertTrue(item.note?.hasPrefix("A simulator is running") ?? false)
        XCTAssertNotNil(scanner.blockingReason(for: item))
    }

    func testSkipsRuntimesSimctlWontDelete() {
        let runtimes = [
            runtime(1, deletable: false),
            runtime(2, size: 0),
            CleanupSimulatorRuntime(identifier: "--all", platform: "iOS", version: "17.0", sizeBytes: 9_000),
        ]
        let (_, report) = fx.scan(context(runtimes), sections: [.systemJunk])
        XCTAssertFalse(report.groups.allItems.contains { $0.metadata[CleanupMetadataKey.ruleID] == "xcode.simulatorRuntimes" })
    }

    func testIgnoredImagePathIsHonored() {
        let image = fx.file("CoreSimulator/Images/one.dmg", bytes: 4_096, in: fx.system)
        var settings = SpruceSettings()
        settings.ignoredPaths = [fx.system + "/CoreSimulator/Images"]
        let (_, report) = fx.scan(context([runtime(1, path: image)]), settings: settings, sections: [.systemJunk])
        XCTAssertNil(report.item(endingWith: "0A1B2C3D-0000-4000-8000-000000000001"))
    }

    func testCheckupNeverOffersRuntimes() {
        let rule = CleanupCatalog.rules.first { $0.id == "xcode.simulatorRuntimes" }
        XCTAssertEqual(rule?.isCheckupEligible, false)
        XCTAssertEqual(CleanupCatalog.rules.first { $0.id == "xcode.deviceSupport" }?.isCheckupEligible, false)
        let (_, report) = fx.scan(context([runtime(1)], purpose: .checkup))
        XCTAssertNil(report.item(endingWith: "0A1B2C3D-0000-4000-8000-000000000001"))
    }
}
