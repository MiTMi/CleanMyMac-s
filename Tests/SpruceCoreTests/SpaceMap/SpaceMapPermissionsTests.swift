import Foundation
import XCTest
@testable import SpruceCore

final class SpaceMapPermissionsTests: XCTestCase {
    private let me: UInt32 = 501

    private func facts(itemOwner: UInt32 = 501, isDirectory: Bool = false, itemWritable: Bool = true,
                       itemFlags: UInt32 = 0, parentOwner: UInt32 = 501, parentWritable: Bool = true,
                       sticky: Bool = false, parentFlags: UInt32 = 0, user: UInt32? = nil) -> SpaceMapPermissionFacts {
        SpaceMapPermissionFacts(userID: user ?? me, itemOwner: itemOwner, itemIsDirectory: isDirectory,
                                itemWritable: itemWritable, itemFlags: itemFlags, parentOwner: parentOwner,
                                parentWritable: parentWritable, parentSticky: sticky, parentFlags: parentFlags)
    }

    func testOwnItemsAreMovable() {
        XCTAssertEqual(SpaceMapPermissions.decide(facts()), .userCanMove)
        XCTAssertEqual(SpaceMapPermissions.decide(facts(isDirectory: true)), .userCanMove)
        // A root-owned file in a folder the user may write to (no sticky bit) can be moved.
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 0)), .userCanMove)
    }

    func testUnwritableFolderNeedsAdministrator() {
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 0, parentOwner: 0, parentWritable: false)),
                       .needsAdministrator(rootOwned: true))
        XCTAssertEqual(SpaceMapPermissions.decide(facts(parentOwner: 0, parentWritable: false)),
                       .needsAdministrator(rootOwned: true), "the folder belongs to root")
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 502, parentOwner: 502, parentWritable: false)),
                       .needsAdministrator(rootOwned: false), "another user's folder")
    }

    func testStickyFolderNeedsOwnership() {
        // /cores, /private/tmp: only the item's or the folder's owner may move an item.
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 0, parentOwner: 0, sticky: true)),
                       .needsAdministrator(rootOwned: true))
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 502, parentOwner: 0, sticky: true)),
                       .needsAdministrator(rootOwned: false))
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 501, parentOwner: 0, sticky: true)), .userCanMove)
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 0, parentOwner: 501, sticky: true)), .userCanMove)
    }

    func testFolderMovingElsewhereMustBeWritable() {
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 0, isDirectory: true, itemWritable: false)),
                       .needsAdministrator(rootOwned: true))
        // Files don't rewrite "..": their own permissions don't matter.
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 0, itemWritable: false)), .userCanMove)
    }

    func testLockedItemsAndFolders() {
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemFlags: SpaceMapPermissions.userImmutableFlag)),
                       .locked(byUser: true))
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemFlags: SpaceMapPermissions.restrictedFlag)),
                       .locked(byUser: false))
        XCTAssertEqual(SpaceMapPermissions.decide(facts(parentFlags: SpaceMapPermissions.userAppendFlag)),
                       .locked(byUser: true))
        XCTAssertEqual(SpaceMapPermissions.decide(facts(parentFlags: SpaceMapPermissions.systemImmutableFlag)),
                       .locked(byUser: false))
        // Flags stop root too.
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemFlags: SpaceMapPermissions.userImmutableFlag, user: 0)),
                       .locked(byUser: true))
        // Root bypasses permissions otherwise.
        XCTAssertEqual(SpaceMapPermissions.decide(facts(itemOwner: 0, parentOwner: 0, parentWritable: false, user: 0)),
                       .userCanMove)
    }

    func testRealFactsForOwnFiles() throws {
        let base = NSTemporaryDirectory() + "spacemap-perm-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base + "/folder", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        FileManager.default.createFile(atPath: base + "/file.bin", contents: Data(count: 16))

        let file = try XCTUnwrap(SpaceMapPermissions.facts(ofPath: base + "/file.bin"))
        XCTAssertFalse(file.itemIsDirectory)
        XCTAssertTrue(file.parentWritable)
        let folder = try XCTUnwrap(SpaceMapPermissions.facts(ofPath: base + "/folder"))
        XCTAssertTrue(folder.itemIsDirectory)
        XCTAssertTrue(folder.itemWritable)
        XCTAssertEqual(SpaceMapPermissions.moveAccess(ofPath: base + "/file.bin"), .userCanMove)
        XCTAssertEqual(SpaceMapPermissions.moveAccess(ofPath: base + "/folder"), .userCanMove)

        // Gone since the scan, or no parent: left to FileRemover.
        XCTAssertNil(SpaceMapPermissions.facts(ofPath: base + "/missing"))
        XCTAssertEqual(SpaceMapPermissions.moveAccess(ofPath: base + "/missing"), .userCanMove)
        XCTAssertNil(SpaceMapPermissions.facts(ofPath: "/"))
    }

    func testProtectionReasonRefusesWhatAdministratorRightsCantMove() throws {
        let home = NSTemporaryDirectory() + "spacemap-perm-home-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let guardian = PathGuard(home: home)

        // A disk outside the places where Spruce acts as administrator.
        let external = SpaceMapNode.folder("Data", basePath: "/Volumes/Data", children: [
            .folder("Projects", children: [.file("big.bin", size: 10)]),
        ])
        let projects = try XCTUnwrap(external.node(atPath: "/Volumes/Data/Projects"))
        let bin = try XCTUnwrap(external.node(atPath: "/Volumes/Data/Projects/big.bin"))
        // /opt and the home folder are privileged zones.
        let opt = SpaceMapNode.folder("opt", basePath: "/opt", children: [.folder("tool", children: [])])
        let tool = try XCTUnwrap(opt.node(atPath: "/opt/tool"))
        let homeRoot = SpaceMapNode.folder("Home", basePath: home, children: [.folder("Projects", children: [])])
        let homeProjects = try XCTUnwrap(homeRoot.node(atPath: home + "/Projects"))

        func reason(_ node: SpaceMapNode, _ access: SpaceMapMoveAccess) -> String? {
            SpaceMapCatalog.protectionReason(for: node, guardian: guardian, access: { _ in access })
        }

        XCTAssertNil(reason(projects, .userCanMove))
        XCTAssertEqual(reason(projects, .needsAdministrator(rootOwned: true)), SpaceMapCatalog.rootOwnedReason)
        XCTAssertEqual(reason(bin, .needsAdministrator(rootOwned: false)), SpaceMapCatalog.noPermissionReason)
        XCTAssertNil(reason(tool, .needsAdministrator(rootOwned: true)), "FileRemover asks for the password there")
        XCTAssertNil(reason(homeProjects, .needsAdministrator(rootOwned: true)))
        XCTAssertEqual(reason(homeProjects, .locked(byUser: true)), SpaceMapCatalog.lockedReason)
        XCTAssertEqual(reason(tool, .locked(byUser: false)), SpaceMapCatalog.systemLockedReason)
        // Without a checker nothing changes.
        XCTAssertNil(SpaceMapCatalog.protectionReason(for: projects, guardian: guardian))

        // Earlier refusals win, and the checker isn't asked for them.
        var asked: [String] = []
        let documents = SpaceMapNode.folder("Home", basePath: home, children: [.folder("Documents", children: [])])
        let docs = try XCTUnwrap(documents.node(atPath: home + "/Documents"))
        let refusal = SpaceMapCatalog.protectionReason(for: docs, guardian: guardian, access: { path in
            asked.append(path)
            return .needsAdministrator(rootOwned: true)
        })
        XCTAssertNotNil(refusal)
        XCTAssertNotEqual(refusal, SpaceMapCatalog.rootOwnedReason)
        XCTAssertTrue(asked.isEmpty)
        XCTAssertNotNil(SpaceMapCatalog.protectionReason(for: external, guardian: guardian,
                                                         access: { _ in .userCanMove }), "the scanned location")
    }
}
