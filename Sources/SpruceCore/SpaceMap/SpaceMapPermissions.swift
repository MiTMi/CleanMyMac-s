import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Whether the current user can move an item to the Trash on their own, as far as
/// ownership, permissions and file flags go.
public enum SpaceMapMoveAccess: Sendable, Equatable {
    /// The user can move it to the Trash without administrator rights.
    case userCanMove
    /// Moving it needs administrator rights. `rootOwned`: root owns the item or the folder
    /// it is in (macOS or an installer put it there).
    case needsAdministrator(rootOwned: Bool)
    /// Locked (Finder's Locked checkbox, `byUser`) or protected by macOS (system immutable
    /// flag, System Integrity Protection), on the item or its folder: not even an
    /// administrator can move it.
    case locked(byUser: Bool)
}

/// Ownership, permission and flag facts about an item and the folder it is in, as read by
/// `SpaceMapPermissions.facts(ofPath:)` (`lstat` on the item, `stat` and `access` on its folder).
public struct SpaceMapPermissionFacts: Sendable, Equatable {
    /// The current user's id.
    public var userID: UInt32
    public var itemOwner: UInt32
    public var itemIsDirectory: Bool
    /// The user may write to the item itself (a folder moving to another folder rewrites its "..").
    public var itemWritable: Bool
    /// BSD file flags of the item (0 where the platform has none).
    public var itemFlags: UInt32
    public var parentOwner: UInt32
    /// The user may add and remove entries in the folder (write and search permission).
    public var parentWritable: Bool
    /// The folder has the sticky bit (e.g. `/private/tmp`, `/cores`): only the owner of an
    /// item or of the folder may move the item.
    public var parentSticky: Bool
    public var parentFlags: UInt32

    public init(userID: UInt32, itemOwner: UInt32, itemIsDirectory: Bool, itemWritable: Bool, itemFlags: UInt32 = 0,
                parentOwner: UInt32, parentWritable: Bool, parentSticky: Bool = false, parentFlags: UInt32 = 0) {
        self.userID = userID
        self.itemOwner = itemOwner
        self.itemIsDirectory = itemIsDirectory
        self.itemWritable = itemWritable
        self.itemFlags = itemFlags
        self.parentOwner = parentOwner
        self.parentWritable = parentWritable
        self.parentSticky = parentSticky
        self.parentFlags = parentFlags
    }
}

/// Decides up front whether an item of the space map can be moved to the Trash by the
/// user, needs administrator rights, or can't be moved at all, so the map can say so
/// before the user selects it (`SpaceMapCatalog.protectionReason(for:guardian:settings:access:)`).
public enum SpaceMapPermissions {
    /// `UF_IMMUTABLE` (Finder's Locked).
    public static let userImmutableFlag: UInt32 = 0x0000_0002
    /// `UF_APPEND`.
    public static let userAppendFlag: UInt32 = 0x0000_0004
    /// `SF_IMMUTABLE`.
    public static let systemImmutableFlag: UInt32 = 0x0002_0000
    /// `SF_APPEND`.
    public static let systemAppendFlag: UInt32 = 0x0004_0000
    /// `SF_RESTRICTED` (System Integrity Protection).
    public static let restrictedFlag: UInt32 = 0x0008_0000

    /// What it takes to move the item at `path` to the Trash. An item that can't be read
    /// (gone since the scan, or its folder unreadable) counts as movable: `FileRemover`
    /// checks it again and reports what happens.
    public static func moveAccess(ofPath path: String) -> SpaceMapMoveAccess {
        guard let facts = facts(ofPath: path) else { return .userCanMove }
        return decide(facts)
    }

    /// The decision for already gathered facts.
    public static func decide(_ facts: SpaceMapPermissionFacts) -> SpaceMapMoveAccess {
        let systemLock = systemImmutableFlag | restrictedFlag
        let itemLock = userImmutableFlag | systemLock
        // A folder that is immutable or append-only can't lose entries.
        let parentLock = itemLock | userAppendFlag | systemAppendFlag
        if facts.itemFlags & itemLock != 0 || facts.parentFlags & parentLock != 0 {
            let bySystem = facts.itemFlags & systemLock != 0
                || facts.parentFlags & (systemLock | systemAppendFlag) != 0
            return .locked(byUser: !bySystem)
        }
        // Root bypasses permissions (Spruce never runs as root, but tests and tools might).
        if facts.userID == 0 { return .userCanMove }
        let rootOwned = facts.itemOwner == 0 || facts.parentOwner == 0
        if !facts.parentWritable {
            return .needsAdministrator(rootOwned: rootOwned)
        }
        if facts.parentSticky && facts.itemOwner != facts.userID && facts.parentOwner != facts.userID {
            return .needsAdministrator(rootOwned: facts.itemOwner == 0)
        }
        if facts.itemIsDirectory && !facts.itemWritable {
            return .needsAdministrator(rootOwned: rootOwned)
        }
        return .userCanMove
    }

    /// Reads the facts for `path` (the item itself is never followed if it is a link).
    /// Nil when the item or its folder can't be read.
    public static func facts(ofPath path: String) -> SpaceMapPermissionFacts? {
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasPrefix("/"), standardized != "/" else { return nil }
        let parentPath = (standardized as NSString).deletingLastPathComponent
        var item = stat()
        guard lstat(standardized, &item) == 0 else { return nil }
        var parent = stat()
        guard stat(parentPath, &parent) == 0 else { return nil }
        let isDirectory = UInt32(item.st_mode) & 0o170000 == 0o040000
        let sticky = UInt32(parent.st_mode) & 0o1000 != 0
        let parentWritable = Self.isAccessible(parentPath, mode: W_OK | X_OK)
        let itemWritable = isDirectory ? Self.isAccessible(standardized, mode: W_OK) : true
        var itemFlags: UInt32 = 0
        var parentFlags: UInt32 = 0
        #if canImport(Darwin)
        itemFlags = UInt32(item.st_flags)
        parentFlags = UInt32(parent.st_flags)
        #endif
        return SpaceMapPermissionFacts(userID: UInt32(getuid()), itemOwner: UInt32(item.st_uid),
                                       itemIsDirectory: isDirectory, itemWritable: itemWritable,
                                       itemFlags: itemFlags, parentOwner: UInt32(parent.st_uid),
                                       parentWritable: parentWritable, parentSticky: sticky,
                                       parentFlags: parentFlags)
    }

    /// `access(2)` with the real user id (ACLs included).
    private static func isAccessible(_ path: String, mode: Int32) -> Bool {
        #if canImport(Darwin)
        return Darwin.access(path, mode) == 0
        #elseif canImport(Glibc)
        return Glibc.access(path, mode) == 0
        #elseif canImport(Musl)
        return Musl.access(path, mode) == 0
        #else
        return true
        #endif
    }
}
