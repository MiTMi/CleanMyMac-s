import Foundation

/// Capacity figures of the volume a scan location lives on.
public struct SpaceMapVolumeInfo: Sendable, Hashable, Codable {
    public var name: String
    public var capacity: Int64
    /// Free right now (purgeable space not included).
    public var available: Int64
    /// Free for important data: free space plus what macOS can purge on demand (APFS).
    public var availableForImportantUsage: Int64?
    public var isInternal: Bool
    public var isRemovable: Bool
    public var isLocal: Bool

    public init(name: String, capacity: Int64, available: Int64, availableForImportantUsage: Int64? = nil,
                isInternal: Bool = true, isRemovable: Bool = false, isLocal: Bool = true) {
        self.name = name
        self.capacity = max(0, capacity)
        self.available = max(0, available)
        self.availableForImportantUsage = availableForImportantUsage
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isLocal = isLocal
    }

    /// Everything not free, purgeable space included.
    public var used: Int64 { max(0, capacity - available) }

    /// Space macOS frees automatically when needed (caches, local snapshots, iCloud copies).
    public var purgeable: Int64 {
        guard let important = availableForImportantUsage else { return 0 }
        return max(0, min(important, capacity) - available)
    }

    /// What Finder reports as available.
    public var availableIncludingPurgeable: Int64 { min(capacity, available + purgeable) }

    public var usedFraction: Double { capacity > 0 ? min(1, Double(used) / Double(capacity)) : 0 }
    public var purgeableFraction: Double { capacity > 0 ? min(1, Double(purgeable) / Double(capacity)) : 0 }

    /// In use, but not accounted for by `scanned` bytes of readable files: the other APFS
    /// volumes (VM, Preboot, Recovery), local snapshots, purgeable data and folders the
    /// scan could not read.
    public func unattributedBytes(scanned: Int64) -> Int64 { max(0, used - scanned) }

    /// "182 GB available of 494 GB".
    public var summary: String {
        "\(ByteFormat.string(availableIncludingPurgeable)) available of \(ByteFormat.string(capacity))"
    }
}

/// A place the space map can scan.
public struct SpaceMapTarget: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, Codable {
        /// The startup disk, scanned from "/" (System and Data volumes together).
        case startup
        /// The user's home folder.
        case home
        /// Another mounted volume, scanned from its root.
        case volume
        /// Any folder the user picked.
        case folder
    }

    public var kind: Kind
    public var path: String
    public var title: String
    public var symbol: String
    /// The volume the location lives on (capacity bars, the system pseudo-node).
    public var volume: SpaceMapVolumeInfo?

    public init(kind: Kind, path: String, title: String, symbol: String, volume: SpaceMapVolumeInfo? = nil) {
        self.kind = kind
        self.path = path
        self.title = title
        self.symbol = symbol
        self.volume = volume
    }

    public var id: String { "\(kind.rawValue):\(path)" }

    /// The whole volume is scanned, so unaccounted space can be shown as a pseudo-node.
    public var coversWholeVolume: Bool { kind == .startup || kind == .volume }

    /// Second line on a target card.
    public var subtitle: String {
        switch kind {
        case .startup, .volume:
            if let volume { return "\(ByteFormat.string(volume.used)) used of \(ByteFormat.string(volume.capacity))" }
            return path
        case .home:
            return "Your files and app data"
        case .folder:
            return path.abbreviatingHome
        }
    }
}

/// A finished scan.
public struct SpaceMapScanResult: Sendable {
    public let target: SpaceMapTarget
    public let root: SpaceMapNode
    public let stats: SpaceMapScanStats
    /// Options used, so a subtree can be rescanned with the same boundary.
    public let options: SpaceMapScanOptions
    public let date: Date
    /// The "System & snapshots" pseudo-node, when the whole volume was scanned.
    public let systemNode: SpaceMapNode?

    public init(target: SpaceMapTarget, root: SpaceMapNode, stats: SpaceMapScanStats, options: SpaceMapScanOptions,
                date: Date = Date(), systemNode: SpaceMapNode? = nil) {
        self.target = target
        self.root = root
        self.stats = stats
        self.options = options
        self.date = date
        self.systemNode = systemNode
    }
}

public enum SpaceMapAccounting {
    public static let systemNodeName = "System & snapshots"

    /// Adds the "System & snapshots" pseudo-node (used space minus scanned bytes) to the
    /// root of a whole-volume scan. Returns nil when the difference is negligible.
    @discardableResult
    public static func attachSystemNode(to root: SpaceMapNode, volume: SpaceMapVolumeInfo,
                                        minimumBytes: Int64 = 50_000_000) -> SpaceMapNode? {
        let hidden = volume.unattributedBytes(scanned: root.size)
        guard hidden >= minimumBytes else { return nil }
        let node = SpaceMapNode(name: systemNodeName, kind: .system, size: hidden, fileCount: 0)
        root.insertChild(node)
        return node
    }

    /// Explanation for the pseudo-node's hover card.
    public static func systemNodeDetail(volume: SpaceMapVolumeInfo, unreadableFolders: Int) -> String {
        var parts = ["macOS system volumes, virtual memory, local snapshots"]
        if volume.purgeable > 0 {
            parts.append("about \(ByteFormat.string(volume.purgeable)) of purgeable space macOS frees on its own")
        }
        if unreadableFolders > 0 {
            parts.append("\(CountFormat.items(unreadableFolders, singular: "folder", plural: "folders")) Spruce couldn't read")
        }
        return parts.joined(separator: ", ") + "."
    }
}
