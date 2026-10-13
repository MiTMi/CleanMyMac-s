import Foundation
import XCTest
@testable import SpruceCore

final class CloudStorageDiscoveryTests: XCTestCase {
    private var home: String = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "cloud-discovery-\(UUID().uuidString)"
        try fm.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(atPath: home)
    }

    private func mkdir(_ relative: String) throws {
        try fm.createDirectory(atPath: home + "/" + relative, withIntermediateDirectories: true)
    }

    private func touch(_ relative: String) throws {
        XCTAssertTrue(fm.createFile(atPath: home + "/" + relative, contents: Data("x".utf8)))
    }

    func testClassifiesFileProviderFolderNames() {
        let drive = CloudStorageDiscovery.classify(folderName: "GoogleDrive-me@example.com")
        XCTAssertEqual(drive?.kind, .googleDrive)
        XCTAssertEqual(drive?.account, "me@example.com")

        let oneDrive = CloudStorageDiscovery.classify(folderName: "OneDrive-Personal")
        XCTAssertEqual(oneDrive?.kind, .oneDrive)
        XCTAssertEqual(oneDrive?.account, "Personal")

        let orgDrive = CloudStorageDiscovery.classify(folderName: "OneDrive-Contoso Ltd")
        XCTAssertEqual(orgDrive?.account, "Contoso Ltd")

        let dropbox = CloudStorageDiscovery.classify(folderName: "Dropbox")
        XCTAssertEqual(dropbox?.kind, .dropbox)
        XCTAssertNil(dropbox?.account)

        let team = CloudStorageDiscovery.classify(folderName: "Dropbox (Acme)")
        XCTAssertEqual(team?.kind, .dropbox)
        XCTAssertEqual(team?.account, "Acme")

        let box = CloudStorageDiscovery.classify(folderName: "Box-Box")
        XCTAssertEqual(box?.kind, .box)
        XCTAssertNil(box?.account)

        let other = CloudStorageDiscovery.classify(folderName: "SynologyDrive-NAS")
        XCTAssertEqual(other?.kind, .otherFileProvider)
        XCTAssertEqual(other?.customName, "SynologyDrive")
        XCTAssertEqual(other?.account, "NAS")

        XCTAssertNil(CloudStorageDiscovery.classify(folderName: ".hidden"))
        XCTAssertNil(CloudStorageDiscovery.classify(folderName: ""))
    }

    func testDiscoversICloudFileProvidersAndLegacyFolders() throws {
        try mkdir("Library/Mobile Documents/com~apple~CloudDocs/Projects")
        try mkdir("Library/Mobile Documents/iCloud~com~apple~Pages/Documents")
        try mkdir("Library/Mobile Documents/com~apple~TextEdit")          // no Documents folder
        try mkdir("Library/Mobile Documents/ABCDE12345~com~vendor~App/Library") // app-private only
        try mkdir("Library/CloudStorage/OneDrive-Personal")
        try mkdir("Library/CloudStorage/GoogleDrive-me@example.com/My Drive")
        try mkdir("Library/CloudStorage/.Trash")
        try mkdir("Library/CloudStorage/Box-Box")
        try mkdir("Dropbox")
        try touch("Dropbox/.dropbox")
        try touch("Dropbox/notes.txt")
        try mkdir("Google Drive")
        try touch("Google Drive/report.pdf")
        // A symlinked folder is never treated as a provider.
        try mkdir("Elsewhere/OneDrive")
        try fm.createSymbolicLink(atPath: home + "/OneDrive", withDestinationPath: home + "/Elsewhere/OneDrive")

        let providers = CloudStorageDiscovery.discover(home: home)
        XCTAssertEqual(providers.map(\.kind), [.iCloudDrive, .box, .googleDrive, .oneDrive, .dropbox, .googleDrive])
        XCTAssertEqual(providers.map(\.mechanism), [.iCloud, .fileProvider, .fileProvider, .fileProvider, .syncFolder, .syncFolder])

        let iCloud = try XCTUnwrap(providers.first)
        XCTAssertTrue(iCloud.rootPath.hasSuffix("com~apple~CloudDocs"))
        XCTAssertEqual(iCloud.additionalRoots.count, 1)
        XCTAssertTrue(iCloud.additionalRoots[0].hasSuffix("iCloud~com~apple~Pages/Documents"))
        XCTAssertEqual(CloudStorageDiscovery.appFolderName(iCloud.additionalRoots[0]), "Pages")

        XCTAssertEqual(providers[2].displayName, "Google Drive · me@example.com")
        XCTAssertEqual(providers[3].displayName, "OneDrive · Personal")
        XCTAssertFalse(providers[4].mechanism.canFreeUpLocally)
    }

    func testDropboxFolderWithoutMarkerIsIgnored() throws {
        try mkdir("Dropbox")
        try touch("Dropbox/mine.txt")
        XCTAssertTrue(CloudStorageDiscovery.discover(home: home).isEmpty)
    }

    func testEmptyLegacyFolderIsSkippedWhenFileProviderExists() throws {
        try mkdir("Library/CloudStorage/Dropbox")
        try mkdir("Dropbox")
        try touch("Dropbox/.dropbox")
        let providers = CloudStorageDiscovery.discover(home: home)
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.mechanism, .fileProvider)
    }

    func testProviderContainsOnlyPathsInsideItsRoots() {
        let provider = CloudStorageProvider(kind: .iCloudDrive, mechanism: .iCloud, rootPath: "/Users/a/Drive",
                                            additionalRoots: ["/Users/a/Apps/Pages/Documents"])
        XCTAssertTrue(provider.contains("/Users/a/Drive/file.txt"))
        XCTAssertTrue(provider.contains("/users/a/drive/Sub/file.txt"))
        XCTAssertTrue(provider.contains("/Users/a/Apps/Pages/Documents/doc.pages"))
        XCTAssertFalse(provider.contains("/Users/a/Drive"))
        XCTAssertFalse(provider.contains("/Users/a/DriveOther/file.txt"))
        XCTAssertFalse(provider.contains("/Users/a/Apps/Pages/Library/db.sqlite"))
    }
}
