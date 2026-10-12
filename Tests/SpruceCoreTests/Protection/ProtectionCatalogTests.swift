import Foundation
import XCTest
@testable import SpruceCore

final class ProtectionCatalogTests: XCTestCase {

    func testGlobMatchingStaysWithinOneComponent() {
        XCTAssertTrue(ProtectionGlob.matches("/Library/LaunchDaemons/com.*.net-preferences.plist",
                                             "/Library/LaunchDaemons/com.acme.net-preferences.plist"))
        XCTAssertFalse(ProtectionGlob.matches("/Library/LaunchDaemons/com.*.net-preferences.plist",
                                              "/Library/LaunchDaemons/x/com.acme.net-preferences.plist.bak"))
        XCTAssertFalse(ProtectionGlob.matches("~/Library/*", "~/Library/a/b"))
        XCTAssertTrue(ProtectionGlob.matches("com.genieo.*", "COM.Genieo.Engine"))
        XCTAssertTrue(ProtectionGlob.matches("a?c", "abc"))
        XCTAssertFalse(ProtectionGlob.matches("a?c", "a/c"))
        XCTAssertTrue(ProtectionGlob.matches("*", "anything"))
        XCTAssertFalse(ProtectionGlob.matches("*", "any/thing"))
    }

    func testEveryIndicatorPointsAtAFamily() {
        let catalog = ProtectionThreatCatalog.standard
        let ids = Set(catalog.families.map(\.id))
        XCTAssertEqual(ids.count, catalog.families.count, "Duplicate family ids")
        for indicator in catalog.indicators {
            XCTAssertTrue(ids.contains(indicator.familyID), "Unknown family \(indicator.familyID) for \(indicator.pattern)")
        }
    }

    func testHashesAreWellFormedAndUnique() {
        let hashes = ProtectionThreatCatalog.standard.indicators.filter { $0.kind == .sha256 }.map(\.pattern)
        XCTAssertGreaterThan(hashes.count, 50)
        XCTAssertEqual(Set(hashes).count, hashes.count, "Duplicate SHA-256 entries")
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        for hash in hashes {
            XCTAssertEqual(hash.count, 64, hash)
            XCTAssertTrue(hash.unicodeScalars.allSatisfy { hex.contains($0) }, hash)
        }
        XCTAssertEqual(ProtectionThreatCatalog.standard.hashCount, hashes.count)
    }

    func testRegexIndicatorsCompile() {
        for indicator in ProtectionThreatCatalog.standard.indicators where indicator.kind == .pathRegex {
            XCTAssertNotNil(ProtectionRegexCache.regex(indicator.pattern), indicator.pattern)
        }
    }

    func testMatchersFindDocumentedIndicators() {
        let catalog = ProtectionThreatCatalog.standard
        XCTAssertEqual(catalog.matchLabel("com.xdivcmp")?.family.id, "amos")
        XCTAssertEqual(catalog.matchLabel("com.genieo.engine")?.family.id, "genieo")
        XCTAssertEqual(catalog.matchBundleID("com.techyutils.cleaner")?.family.id, "advancedmaccleaner")
        XCTAssertEqual(catalog.matchBundleName("Advanced Mac Cleaner.app")?.family.category, .pua)
        XCTAssertEqual(catalog.matchTeamID("4x5kz42l4b")?.family.id, "shlayer")
        XCTAssertEqual(catalog.matchHash("D94F62EC4B6FFCEC35D5E639D02A52CE226629A5EB3E2A7190174EA8D3B40B5B")?.family.id, "adload")
        XCTAssertEqual(catalog.matchHash("d94f62ec4b6ffcec35d5e639d02a52ce226629a5eb3e2a7190174ea8d3b40b5b")?.evidence, .knownHash)
        XCTAssertEqual(catalog.matchPath("~/Library/Application Support/.1234567890123456789012/Services/x", isExecutable: false)?.family.id,
                       "adload")
        XCTAssertNil(catalog.matchPath("~/Library/Application Support/.12345", isExecutable: false))
        XCTAssertEqual(catalog.matchPath("~/.local-0A1B2C3D-1111-2222-3333-444455556666", isExecutable: false)?.family.id, "cuckoo")
        XCTAssertEqual(catalog.matchPath("/Library/LaunchDaemons/com.whatever.net-preferences.plist", isExecutable: false)?.family.id,
                       "pirrit")
        XCTAssertEqual(catalog.matchPathOrAncestor("~/Library/AppQuest/com.apple.questd", isExecutable: true)?.family.id, "evilquest")
    }

    func testExecutableOnlyIndicatorsIgnoreDataFiles() {
        let catalog = ProtectionThreatCatalog.standard
        XCTAssertNil(catalog.matchPath("~/.helper", isExecutable: false))
        XCTAssertEqual(catalog.matchPath("~/.helper", isExecutable: true)?.family.id, "amos")
        // PHP upload temp files are not executables.
        XCTAssertNil(catalog.matchPath("/private/tmp/phpAb12Cd", isExecutable: false))
        XCTAssertEqual(catalog.matchPath("/private/tmp/phpAb12Cd", isExecutable: true)?.family.id, "adload")
    }

    func testCommonLegitimateNamesAreNotInTheCatalog() {
        let catalog = ProtectionThreatCatalog.standard
        for label in ["com.google.keystone.agent", "com.microsoft.update.agent", "homebrew.mxcl.postgresql@16",
                      "com.docker.vmnetd", "com.dropbox.DropboxMacUpdate.agent", "us.zoom.updater"] {
            XCTAssertNil(catalog.matchLabel(label), label)
        }
        XCTAssertNil(catalog.matchPath("~/.dropbox", isExecutable: false))
        XCTAssertNil(catalog.matchBundleID("com.apple.Safari"))
        XCTAssertNil(catalog.matchBundleID("com.google.Chrome"))
    }

    func testHijackDomainDetection() {
        XCTAssertEqual(ProtectionThreatCatalog.mentionsHijackDomain("https://search.Trovi.com/?q="), "trovi.com")
        XCTAssertNil(ProtectionThreatCatalog.mentionsHijackDomain("https://www.google.com"))
    }

    func testPathSpaceRoundTrip() {
        let space = ProtectionPathSpace(home: "/r/Users/me", root: "/r")
        XCTAssertEqual(space.logical("/r/Users/me/Library/X"), "~/Library/X")
        XCTAssertEqual(space.logical("/r/Library/LaunchDaemons/a.plist"), "/Library/LaunchDaemons/a.plist")
        XCTAssertEqual(space.real("~/x"), "/r/Users/me/x")
        XCTAssertEqual(space.real("/etc/x"), "/r/etc/x")
        XCTAssertEqual(space.logical("/r/Users/me"), "~")
        let realSpace = ProtectionPathSpace(home: "/Users/me")
        XCTAssertEqual(realSpace.system("/Library"), "/Library")
        XCTAssertEqual(realSpace.logical("/Applications/A.app"), "/Applications/A.app")
    }
}
