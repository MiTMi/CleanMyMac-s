import Foundation
import XCTest
@testable import SpruceCore

final class ApplicationsVersionTests: XCTestCase {

    func testNumericComparison() {
        XCTAssertEqual(ApplicationsVersion.compare("1.2.10", "1.2.9"), .orderedDescending)
        XCTAssertEqual(ApplicationsVersion.compare("1.10", "1.9"), .orderedDescending)
        XCTAssertEqual(ApplicationsVersion.compare("2.0", "10.0"), .orderedAscending)
        XCTAssertEqual(ApplicationsVersion.compare("120", "119"), .orderedDescending)
        XCTAssertEqual(ApplicationsVersion.compare("20240101123456", "20231231000000"), .orderedDescending)
    }

    func testTrailingZerosAreIgnored() {
        XCTAssertEqual(ApplicationsVersion.compare("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(ApplicationsVersion.compare("1.2.0.0", "1.2"), .orderedSame)
        XCTAssertEqual(ApplicationsVersion.compare("1.2.1", "1.2"), .orderedDescending)
        XCTAssertEqual(ApplicationsVersion.compare("1.0", "1.0.1"), .orderedAscending)
    }

    func testPrereleaseTagsAreOlder() {
        XCTAssertEqual(ApplicationsVersion.compare("1.0b1", "1.0"), .orderedAscending)
        XCTAssertEqual(ApplicationsVersion.compare("1.0", "1.0b1"), .orderedDescending)
        XCTAssertEqual(ApplicationsVersion.compare("1.0b2", "1.0b1"), .orderedDescending)
        XCTAssertEqual(ApplicationsVersion.compare("1.2a", "1.2.1"), .orderedAscending)
        XCTAssertEqual(ApplicationsVersion.compare("2.0 beta", "2.0"), .orderedAscending)
    }

    func testCaskVersionSplitting() {
        XCTAssertEqual(ApplicationsVersion.splitCaskVersion("1.2.3,456")?.version, "1.2.3")
        XCTAssertEqual(ApplicationsVersion.splitCaskVersion("1.2.3,456")?.build, "456")
        XCTAssertEqual(ApplicationsVersion.splitCaskVersion("4.0,99:abcdef")?.build, "99")
        XCTAssertNil(ApplicationsVersion.splitCaskVersion("latest"))
        XCTAssertNil(ApplicationsVersion.splitCaskVersion("121.0")?.build)
    }

    func testCleaning() {
        XCTAssertEqual(ApplicationsVersion.cleaned("v1.2.3"), "1.2.3")
        XCTAssertEqual(ApplicationsVersion.cleaned("Version 4.5"), "4.5")
        XCTAssertEqual(ApplicationsVersion.cleaned("2.1 (Build 300)"), "2.1")
        XCTAssertEqual(ApplicationsVersion.cleaned("vivaldi"), "vivaldi")
    }

    func testUpdateDecisionFollowsSparkleBuilds() {
        // Build numbers decide when both are known.
        XCTAssertTrue(ApplicationsVersion.isUpdate(availableVersion: "1.2", availableBuild: "121", installedVersion: "1.2", installedBuild: "120"))
        XCTAssertFalse(ApplicationsVersion.isUpdate(availableVersion: "1.2.1", availableBuild: "120", installedVersion: "1.2", installedBuild: "120"))
        // An older display version is never an update, whatever the build says.
        XCTAssertFalse(ApplicationsVersion.isUpdate(availableVersion: "1.9", availableBuild: "9999", installedVersion: "2.0", installedBuild: "200"))
        // Without builds, display versions decide.
        XCTAssertTrue(ApplicationsVersion.isUpdate(availableVersion: "3.1", availableBuild: nil, installedVersion: "3.0.4", installedBuild: ""))
        XCTAssertFalse(ApplicationsVersion.isUpdate(availableVersion: "3.0.4", availableBuild: nil, installedVersion: "3.0.4", installedBuild: ""))
    }

    func testPrereleaseAndMajorDetection() {
        XCTAssertTrue(ApplicationsVersion.isPrerelease("2.0b3"))
        XCTAssertTrue(ApplicationsVersion.isPrerelease("3.1-rc1"))
        XCTAssertTrue(ApplicationsVersion.isPrerelease("4.0 Beta"))
        XCTAssertFalse(ApplicationsVersion.isPrerelease("4.0.2"))
        XCTAssertTrue(ApplicationsVersion.isMajorUpgrade(from: "5.9.1", to: "6.0"))
        XCTAssertFalse(ApplicationsVersion.isMajorUpgrade(from: "5.9.1", to: "5.10"))
    }

    func testOSGates() {
        XCTAssertTrue(ApplicationsVersion.osSatisfies(minimum: "10.13", current: "14.5.0"))
        XCTAssertFalse(ApplicationsVersion.osSatisfies(minimum: "15.0", current: "14.5.0"))
        XCTAssertTrue(ApplicationsVersion.osSatisfies(minimum: nil, current: "14.5.0"))
        XCTAssertFalse(ApplicationsVersion.osSatisfies(maximum: "13.99", current: "14.0"))
    }
}
