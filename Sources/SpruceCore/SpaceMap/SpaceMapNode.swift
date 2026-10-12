import Foundation

/// What a node of the space map stands for.
public enum SpaceMapNodeKind: String, Sendable, Codable, CaseIterable {
    /// An ordinary folder.
    case directory
    /// A bundle or package that Finder shows as one item (.app, .photoslibrary…). Browsable here.
    case package
    /// A regular file (or any other non-directory object such as a socket).
    case file
    /// A symbolic link. Counted with its own (tiny) size and never followed.
    case symlink
    /// Many small files of one folder folded into a single node to keep the tree compact.
    case smallFiles
    /// Pseudo-node: space in use on a volume that no readable file accounts for
    /// (macOS system volumes, local snapshots, purgeable space, unreadable folders).
    case system
}

/// One file, folder or pseudo-item of a space map.
///
/// The tree is built by `SpaceMapScanner` on background threads and then handed to a
/// single owner (the app's main actor), which is the only code that mutates it
/// afterwards (`detach`, `replaceContents`, `insertChild`). Children are always kept
/// sorted largest first; folder totals are post-order aggregates of their children
/// (hard-linked files are counted once by the scanner).
public final class SpaceMapNode: Identifiable, Hashable, CustomStringConvertible, @unchecked Sendable {
    /// Last path component (for a scan root: the display name, e.g. "Macintosh HD").
    public let name: String
    public let kind: SpaceMapNodeKind
    /// Bytes allocated on disk by the whole subtree.
    public internal(set) var size: Int64
    /// Files in the subtree (a folded `smallFiles` node counts every folded file).
    public internal(set) var fileCount: Int
    /// Folders in the subtree, not counting the node itself.
    public internal(set) var folderCount: Int
    /// Logical size of cloud-only (dataless) files in the subtree. They use no local space.
    public internal(set) var cloudOnlyBytes: Int64
    /// The folder could not be listed (permissions / privacy protection).
    public internal(set) var isUnreadable: Bool
    /// File system identity recorded at scan time (0 for pseudo-nodes).
    public let inode: UInt64
    /// Largest first.
    public internal(set) var children: [SpaceMapNode]
    public internal(set) weak var parent: SpaceMapNode?

    /// Seconds since 1970 of the newest modification in the subtree (0 = unknown).
    var modifiedStamp: Double
    /// Absolute path of a scan root (nil for every other node).
    let basePath: String?
    /// Scanner bookkeeping: sub-folders still being read.
    var scanPending = 0

    init(scannedName: String, kind: SpaceMapNodeKind, size: Int64, fileCount: Int, folderCount: Int = 0,
         modifiedStamp: Double, inode: UInt64, cloudOnlyBytes: Int64 = 0, isUnreadable: Bool = false,
         basePath: String? = nil) {
        self.name = scannedName
        self.kind = kind
        self.size = max(0, size)
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.modifiedStamp = modifiedStamp
        self.inode = inode
        self.cloudOnlyBytes = cloudOnlyBytes
        self.isUnreadable = isUnreadable
        self.basePath = basePath
        self.children = []
    }

    /// Creates a node without children. `fileCount` defaults to 1 for files and links.
    public convenience init(name: String, kind: SpaceMapNodeKind, size: Int64 = 0, fileCount: Int? = nil,
                            modified: Date? = nil, inode: UInt64 = 0, cloudOnlyBytes: Int64 = 0,
                            isUnreadable: Bool = false, basePath: String? = nil) {
        let files = fileCount ?? ((kind == .file || kind == .symlink) ? 1 : 0)
        self.init(scannedName: name, kind: kind, size: size, fileCount: files,
                  modifiedStamp: modified?.timeIntervalSince1970 ?? 0, inode: inode,
                  cloudOnlyBytes: cloudOnlyBytes, isUnreadable: isUnreadable, basePath: basePath)
    }

    // MARK: Factories

    /// A folder whose totals are aggregated from `children` (plus its own allocation).
    public static func folder(_ name: String, kind: SpaceMapNodeKind = .directory, ownSize: Int64 = 0,
                              modified: Date? = nil, inode: UInt64 = 0, isUnreadable: Bool = false,
                              basePath: String? = nil, children: [SpaceMapNode]) -> SpaceMapNode {
        let node = SpaceMapNode(name: name, kind: kind, size: ownSize, fileCount: 0, modified: modified,
                                inode: inode, isUnreadable: isUnreadable, basePath: basePath)
        for child in children { child.parent = node }
        node.children = children
        node.finalizeAggregates()
        return node
    }

    public static func file(_ name: String, size: Int64, modified: Date? = nil, inode: UInt64 = 0,
                            cloudOnlyBytes: Int64 = 0) -> SpaceMapNode {
        SpaceMapNode(name: name, kind: .file, size: size, fileCount: 1, modified: modified, inode: inode,
                     cloudOnlyBytes: cloudOnlyBytes)
    }

    // MARK: Identity

    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    public static func == (lhs: SpaceMapNode, rhs: SpaceMapNode) -> Bool { lhs === rhs }

    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    public var description: String { "\(name) (\(size) bytes)" }

    // MARK: Derived

    public var modified: Date? { modifiedStamp > 0 ? Date(timeIntervalSince1970: modifiedStamp) : nil }

    /// Folders and packages (both can be zoomed into).
    public var isFolder: Bool { kind == .directory || kind == .package }

    /// Backed by a real file system object (not a folded group or a pseudo-node).
    public var isReal: Bool { kind != .smallFiles && kind != .system }

    /// Can be opened as the focus of the map.
    public var canZoom: Bool { isFolder && !children.isEmpty }

    /// Files plus folders inside.
    public var itemCount: Int { fileCount + folderCount }

    /// Absolute path (pseudo-nodes get a synthetic path below their parent).
    public var path: String {
        if let basePath { return basePath }
        guard let parent else { return name }
        let base = parent.path
        return base == "/" ? "/" + name : base + "/" + name
    }

    public var url: URL? { isReal ? URL(fileURLWithPath: path) : nil }

    /// From the root down to (and including) this node.
    public var ancestry: [SpaceMapNode] {
        var chain: [SpaceMapNode] = [self]
        var current = parent
        while let node = current {
            chain.append(node)
            current = node.parent
        }
        return chain.reversed()
    }

    /// 0 for the root.
    public var depth: Int {
        var count = 0
        var current = parent
        while let node = current {
            count += 1
            current = node.parent
        }
        return count
    }

    public var root: SpaceMapNode {
        var node = self
        while let parent = node.parent { node = parent }
        return node
    }

    /// True when `ancestor` is a strict ancestor of this node.
    public func isDescendant(of ancestor: SpaceMapNode) -> Bool {
        var current = parent
        while let node = current {
            if node === ancestor { return true }
            current = node.parent
        }
        return false
    }

    /// Still part of the tree that starts at `root`.
    public func isAttached(to root: SpaceMapNode) -> Bool { self.root === root }

    /// Fraction of the parent's size (1 for a root).
    public var shareOfParent: Double {
        guard let parent else { return 1 }
        return parent.size > 0 ? Double(size) / Double(parent.size) : 0
    }

    public func child(named name: String) -> SpaceMapNode? {
        children.first { $0.name == name && $0.isReal }
    }

    /// The node at an absolute path inside this subtree.
    public func node(atPath target: String) -> SpaceMapNode? {
        let base = path
        if target == base { return self }
        let prefix = base == "/" ? "/" : base + "/"
        guard target.hasPrefix(prefix) else { return nil }
        var current = self
        for component in target.dropFirst(prefix.count).split(separator: "/") {
            guard let next = current.children.first(where: { $0.isReal && $0.name == component }) else { return nil }
            current = next
        }
        return current
    }

    /// The direct child of this node that contains (or is) `descendant`.
    public func childOnPath(to descendant: SpaceMapNode) -> SpaceMapNode? {
        var node = descendant
        while let parent = node.parent {
            if parent === self { return node }
            node = parent
        }
        return nil
    }

    /// Largest first; ties by name so the order is stable.
    public static func isOrderedBefore(_ lhs: SpaceMapNode, _ rhs: SpaceMapNode) -> Bool {
        if lhs.size != rhs.size { return lhs.size > rhs.size }
        return lhs.name < rhs.name
    }

    // MARK: Aggregation and edits

    /// Post-order step: own allocation (held in `size` until now) plus every child.
    func finalizeAggregates() {
        var bytes = size
        var files = 0
        var folders = 0
        var cloud = cloudOnlyBytes
        var newest = modifiedStamp
        for child in children {
            bytes += child.size
            files += child.fileCount
            if child.isFolder { folders += 1 + child.folderCount }
            cloud += child.cloudOnlyBytes
            if child.modifiedStamp > newest { newest = child.modifiedStamp }
        }
        size = bytes
        fileCount = files
        folderCount = folders
        cloudOnlyBytes = cloud
        modifiedStamp = newest
        children.sort(by: SpaceMapNode.isOrderedBefore)
    }

    /// Applies a change below this node to it and every ancestor, keeping children sorted.
    func propagate(bytes: Int64, files: Int, folders: Int, cloud: Int64) {
        var current: SpaceMapNode? = self
        while let node = current {
            node.size = max(0, node.size + bytes)
            node.fileCount = max(0, node.fileCount + files)
            node.folderCount = max(0, node.folderCount + folders)
            node.cloudOnlyBytes = max(0, node.cloudOnlyBytes + cloud)
            node.children.sort(by: SpaceMapNode.isOrderedBefore)
            current = node.parent
        }
    }

    private var folderWeight: Int { isFolder ? 1 + folderCount : 0 }

    /// Removes the node from its parent and subtracts its totals from every ancestor
    /// (after it was moved to the Trash, or vanished on a rescan).
    public func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        parent.propagate(bytes: -size, files: -fileCount, folders: -folderWeight, cloud: -cloudOnlyBytes)
        self.parent = nil
    }

    /// Adds a child (e.g. the volume's "System & snapshots" pseudo-node) and updates totals.
    public func insertChild(_ child: SpaceMapNode) {
        if child.parent != nil { child.detach() }
        child.parent = self
        children.append(child)
        propagate(bytes: child.size, files: child.fileCount, folders: child.folderWeight, cloud: child.cloudOnlyBytes)
    }

    /// Takes over the contents and totals of a fresh scan of the same folder (rescan),
    /// updating every ancestor by the difference.
    public func replaceContents(with fresh: SpaceMapNode) {
        let deltaBytes = fresh.size - size
        let deltaFiles = fresh.fileCount - fileCount
        let deltaFolders = fresh.folderCount - folderCount
        let deltaCloud = fresh.cloudOnlyBytes - cloudOnlyBytes
        for child in children where child.parent === self { child.parent = nil }
        let adopted = fresh.children
        fresh.children = []
        for child in adopted { child.parent = self }
        children = adopted.sorted(by: SpaceMapNode.isOrderedBefore)
        size = fresh.size
        fileCount = fresh.fileCount
        folderCount = fresh.folderCount
        cloudOnlyBytes = fresh.cloudOnlyBytes
        modifiedStamp = fresh.modifiedStamp
        isUnreadable = fresh.isUnreadable
        parent?.propagate(bytes: deltaBytes, files: deltaFiles, folders: deltaFolders, cloud: deltaCloud)
    }
}
