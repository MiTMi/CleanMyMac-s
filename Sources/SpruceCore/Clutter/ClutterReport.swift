import Foundation

/// Metadata keys Clutter puts on `ScanItem`s.
public enum ClutterMetadataKey {
    /// `ClutterTool.rawValue` of the tool that listed the item.
    public static let tool = "clutterTool"
    /// Inode at scan time (FileRemover refuses to act if it changed).
    public static let inode = "inode"
    /// Duplicate set / similar cluster id ("dup:…", "sim:…").
    public static let set = "clutterSet"
    /// "1" for the copy smart selection keeps (or the best shot).
    public static let keeper = "clutterKeeper"
}

/// Everything one Clutter scan found.
public struct ClutterScanReport: Sendable, Equatable {
    public var locations: [String]
    public var date: Date
    public var largeOld: [ClutterLargeOldItem]
    public var duplicates: [ClutterDuplicateGroup]
    public var similar: [ClutterSimilarCluster]
    public var downloads: [ClutterDownloadItem]
    /// Tools this report covers (a single-tool scan leaves the others empty).
    public var scannedTools: Set<ClutterTool>
    public var filesExamined: Int
    public var skippedPlaceholders: Int
    public var wasStopped: Bool

    public init(locations: [String] = [], date: Date = Date(), largeOld: [ClutterLargeOldItem] = [],
                duplicates: [ClutterDuplicateGroup] = [], similar: [ClutterSimilarCluster] = [],
                downloads: [ClutterDownloadItem] = [], scannedTools: Set<ClutterTool> = Set(ClutterTool.allCases),
                filesExamined: Int = 0, skippedPlaceholders: Int = 0, wasStopped: Bool = false) {
        self.locations = locations
        self.date = date
        self.largeOld = largeOld
        self.duplicates = duplicates
        self.similar = similar
        self.downloads = downloads
        self.scannedTools = scannedTools
        self.filesExamined = filesExamined
        self.skippedPlaceholders = skippedPlaceholders
        self.wasStopped = wasStopped
    }

    public var isEmpty: Bool { largeOld.isEmpty && duplicates.isEmpty && similar.isEmpty && downloads.isEmpty }

    /// Every file listed by any tool, by path.
    public var filesByPath: [String: ClutterFile] {
        var map: [String: ClutterFile] = [:]
        for item in largeOld { map[item.file.path] = item.file }
        for group in duplicates { for file in group.files { map[file.path] = file } }
        for cluster in similar { for file in cluster.files { map[file.path] = file } }
        for item in downloads { map[item.file.path] = item.file }
        return map
    }

    /// Distinct files the report lists.
    public var distinctFileCount: Int { filesByPath.count }

    /// Distinct bytes the report lists (each file counted once).
    public var distinctBytes: Int64 { filesByPath.values.reduce(0) { $0 + $1.size } }

    /// Paths in `tool`.
    public func paths(in tool: ClutterTool) -> [String] {
        switch tool {
        case .largeOld: return largeOld.map(\.file.path)
        case .duplicates: return duplicates.flatMap { $0.files.map(\.path) }
        case .similarImages: return similar.flatMap { $0.files.map(\.path) }
        case .downloads: return downloads.map(\.file.path)
        }
    }

    /// Default selection: smart-selected duplicate copies and stale unfinished
    /// downloads. Large & Old, Similar Images and other downloads start unselected.
    public func defaultSelection(paths: ClutterPaths = ClutterPaths(), settings: ClutterScanSettings = ClutterScanSettings(),
                                 now: Date = Date()) -> Set<String> {
        var selected = ClutterSmartSelection(paths: paths).selection(for: duplicates)
        for item in downloads where ClutterDownloadsAnalyzer.isStaleIncomplete(item, settings: settings, now: now) {
            selected.insert(item.file.path)
        }
        return selected
    }

    /// Duplicate set and similar cluster membership (set id → member paths).
    public var setMembers: [String: [String]] {
        var sets: [String: [String]] = [:]
        for group in duplicates { sets[group.id] = group.files.map(\.path) }
        for cluster in similar { sets[cluster.id] = cluster.files.map(\.path) }
        return sets
    }

    /// The member each set keeps by default (duplicate keeper, best shot).
    public var preferredKeepers: [String: String] {
        var keep: [String: String] = [:]
        for group in duplicates { keep[group.id] = group.keeperPath }
        for cluster in similar { keep[cluster.id] = cluster.bestPath }
        return keep
    }

    /// Drops removed files from every tool. Sets left with one member disappear; a set
    /// that lost its keeper or best shot picks a new one.
    public mutating func remove(paths removed: Set<String>, clutterPaths: ClutterPaths = ClutterPaths()) {
        guard !removed.isEmpty else { return }
        largeOld.removeAll { removed.contains($0.file.path) }
        downloads.removeAll { removed.contains($0.file.path) }
        let selection = ClutterSmartSelection(paths: clutterPaths)
        duplicates = duplicates.compactMap { group in
            let remaining = group.files.filter { !removed.contains($0.path) }
            guard remaining.count > 1 else { return nil }
            if remaining.count == group.files.count { return group }
            return selection.makeGroup(hash: group.hash, files: remaining)
        }
        similar = similar.compactMap { cluster in
            let remaining = cluster.files.filter { !removed.contains($0.path) }
            guard remaining.count > 1 else { return nil }
            if remaining.count == cluster.files.count { return cluster }
            var prints = cluster.fingerprints
            for path in removed { prints[path] = nil }
            let best = ClutterSimilarClusterer.bestShot(remaining, prints: prints)
            let ordered = [best] + remaining.filter { $0.path != best.path }.sorted { $0.path < $1.path }
            return ClutterSimilarCluster(id: cluster.id, files: ordered, fingerprints: prints, bestPath: best.path)
        }
    }

    /// Per-tool numbers for dashboard tiles.
    public func summary(for tool: ClutterTool) -> ClutterToolSummary {
        switch tool {
        case .largeOld:
            let bytes = largeOld.reduce(Int64(0)) { $0 + $1.file.size }
            return ClutterToolSummary(tool: tool, itemCount: largeOld.count, setCount: 0, totalBytes: bytes,
                                      reclaimableBytes: bytes, dominantSource: nil)
        case .duplicates:
            let copies = duplicates.reduce(0) { $0 + $1.copies.count }
            return ClutterToolSummary(tool: tool, itemCount: copies, setCount: duplicates.count,
                                      totalBytes: duplicates.reduce(0) { $0 + $1.totalBytes },
                                      reclaimableBytes: duplicates.reduce(0) { $0 + $1.reclaimableBytes },
                                      dominantSource: nil)
        case .similarImages:
            let images = similar.reduce(0) { $0 + $1.files.count }
            return ClutterToolSummary(tool: tool, itemCount: images, setCount: similar.count,
                                      totalBytes: similar.reduce(0) { $0 + $1.totalBytes },
                                      reclaimableBytes: similar.reduce(0) { $0 + $1.reclaimableBytes },
                                      dominantSource: nil)
        case .downloads:
            let bytes = downloads.reduce(Int64(0)) { $0 + $1.file.size }
            return ClutterToolSummary(tool: tool, itemCount: downloads.count, setCount: 0, totalBytes: bytes,
                                      reclaimableBytes: bytes,
                                      dominantSource: ClutterDownloadsAnalyzer.dominantSource(downloads))
        }
    }
}

/// Dashboard numbers and wording for one tool.
public struct ClutterToolSummary: Sendable, Equatable {
    public var tool: ClutterTool
    /// Files (Large & Old, Downloads), redundant copies (Duplicates) or images (Similar).
    public var itemCount: Int
    /// Duplicate sets or similar clusters.
    public var setCount: Int
    public var totalBytes: Int64
    /// What removing the suggested items frees (copies beyond one, or everything listed).
    public var reclaimableBytes: Int64
    public var dominantSource: String?

    public init(tool: ClutterTool, itemCount: Int, setCount: Int, totalBytes: Int64, reclaimableBytes: Int64,
                dominantSource: String?) {
        self.tool = tool
        self.itemCount = itemCount
        self.setCount = setCount
        self.totalBytes = totalBytes
        self.reclaimableBytes = reclaimableBytes
        self.dominantSource = dominantSource
    }

    public var isEmpty: Bool { itemCount == 0 }

    /// "412 duplicates found", "2.3 GB of large and old files".
    public var headline: String {
        switch tool {
        case .duplicates:
            return itemCount == 0 ? "No duplicates" : "\(CountFormat.items(itemCount, singular: "duplicate")) found"
        case .similarImages:
            return itemCount == 0 ? "No similar images"
                : "\(CountFormat.items(itemCount, singular: "similar image")) found"
        case .largeOld:
            return itemCount == 0 ? "No large or old files" : "\(ByteFormat.string(totalBytes)) of large and old files"
        case .downloads:
            if itemCount == 0 { return "Downloads is empty" }
            if let source = dominantSource { return "\(ByteFormat.string(totalBytes)) of \(source) downloads" }
            return "\(ByteFormat.string(totalBytes)) of downloads"
        }
    }

    /// The other metric ("3.2 GB to free", "188 files").
    public var detail: String {
        switch tool {
        case .duplicates:
            return itemCount == 0 ? "Every file here is one of a kind."
                : "\(ByteFormat.string(reclaimableBytes)) to free · \(CountFormat.items(setCount, singular: "set"))"
        case .similarImages:
            return itemCount == 0 ? "No near-identical pictures."
                : "\(ByteFormat.string(totalBytes)) in \(CountFormat.items(setCount, singular: "set"))"
        case .largeOld:
            return itemCount == 0 ? "Nothing big or forgotten here." : CountFormat.items(itemCount, singular: "file")
        case .downloads:
            return itemCount == 0 ? "Nothing to sort through." : CountFormat.items(itemCount)
        }
    }
}

// MARK: - Scan items

/// Builds `ScanItem`s and groups from Clutter results.
public enum ClutterItems {
    public static func item(_ file: ClutterFile, tool: ClutterTool, safety: SafetyLevel = .review, selected: Bool = false,
                            note: String? = nil, set: String? = nil, isKeeper: Bool = false) -> ScanItem {
        var metadata: [String: String] = [ClutterMetadataKey.tool: tool.rawValue]
        if file.inode != 0 { metadata[ClutterMetadataKey.inode] = String(file.inode) }
        if let set { metadata[ClutterMetadataKey.set] = set }
        if isKeeper { metadata[ClutterMetadataKey.keeper] = "1" }
        return ScanItem(
            id: file.url.standardizedFileURL.path,
            title: file.name,
            subtitle: file.parentPath.abbreviatingHome,
            url: file.url,
            size: file.size,
            itemCount: 1,
            safety: safety,
            isSelected: selected,
            deletion: .trash,
            lastUsed: file.lastOpened,
            modified: file.modified,
            symbol: file.kind.symbol,
            note: note,
            metadata: metadata
        )
    }

    /// One review list covering all four tools (used by `GroupScanner.scan`). Each file
    /// appears once: duplicates first, then similar images, downloads, large & old.
    public static func reviewGroups(for report: ClutterScanReport, paths: ClutterPaths = ClutterPaths(),
                                    settings: ClutterScanSettings = ClutterScanSettings(), now: Date = Date()) -> [ScanGroup] {
        var used = Set<String>()
        var groups: [ScanGroup] = []
        let selection = ClutterSmartSelection(paths: paths)

        var dupChildren: [ScanGroup] = []
        for group in report.duplicates {
            let items = group.files.compactMap { file -> ScanItem? in
                guard used.insert(file.path).inserted else { return nil }
                let isKeeper = file.path == group.keeperPath
                let note = isKeeper ? "\(group.keeperReason). The other copies are identical."
                    : "Identical to \(group.keeperPath.abbreviatingHome)"
                return item(file, tool: .duplicates, selected: selection.shouldSelect(file, keeperPath: group.keeperPath),
                            note: note, set: group.id, isKeeper: isKeeper)
            }
            guard !items.isEmpty else { continue }
            dupChildren.append(ScanGroup(id: group.id, title: group.displayName,
                                         detail: "\(CountFormat.items(group.files.count, singular: "copy", plural: "copies")) · \(group.keeperReason)",
                                         symbol: "doc.on.doc", safety: .review, items: items))
        }
        if !dupChildren.isEmpty {
            groups.append(ScanGroup(id: "clutter.duplicates", title: ClutterTool.duplicates.title,
                                    detail: "Identical files. One copy of each is kept.",
                                    symbol: ClutterTool.duplicates.symbol, safety: .review, children: dupChildren))
        }

        var simChildren: [ScanGroup] = []
        for cluster in report.similar {
            let items = cluster.files.compactMap { file -> ScanItem? in
                guard used.insert(file.path).inserted else { return nil }
                let isBest = file.path == cluster.bestPath
                return item(file, tool: .similarImages, note: isBest ? "Best shot of this set" : "Looks like \(cluster.best?.name ?? "another picture")",
                            set: cluster.id, isKeeper: isBest)
            }
            guard items.count > 1 else {
                for item in items { used.remove(item.id) }
                continue
            }
            simChildren.append(ScanGroup(id: cluster.id, title: cluster.best?.name ?? "Similar images",
                                         detail: CountFormat.items(cluster.files.count, singular: "image"),
                                         symbol: "photo.on.rectangle", safety: .review, items: items))
        }
        if !simChildren.isEmpty {
            groups.append(ScanGroup(id: "clutter.similarImages", title: ClutterTool.similarImages.title,
                                    detail: "Pictures that look nearly the same. Nothing is selected for you.",
                                    symbol: ClutterTool.similarImages.symbol, safety: .review, children: simChildren))
        }

        var downloadChildren: [ScanGroup] = []
        for category in ClutterDownloadCategory.allCases {
            let items = report.downloads.filter { $0.category == category }.compactMap { download -> ScanItem? in
                guard used.insert(download.file.path).inserted else { return nil }
                let stale = ClutterDownloadsAnalyzer.isStaleIncomplete(download, settings: settings, now: now)
                return item(download.file, tool: .downloads, safety: stale ? .safe : .review, selected: stale,
                            note: downloadNote(download, stale: stale, now: now))
            }
            guard !items.isEmpty else { continue }
            downloadChildren.append(ScanGroup(id: "clutter.downloads.\(category.rawValue)", title: category.title,
                                              detail: category.detail, symbol: category.symbol,
                                              safety: category == .incomplete ? .safe : .review, items: items))
        }
        if !downloadChildren.isEmpty {
            groups.append(ScanGroup(id: "clutter.downloads", title: ClutterTool.downloads.title,
                                    detail: "Things you downloaded. Only unfinished downloads are selected for you.",
                                    symbol: ClutterTool.downloads.symbol, safety: .review, children: downloadChildren))
        }

        var largeChildren: [ScanGroup] = []
        for kind in ClutterKind.allCases {
            let items = report.largeOld.filter { $0.file.kind == kind }.compactMap { entry -> ScanItem? in
                guard used.insert(entry.file.path).inserted else { return nil }
                return item(entry.file, tool: .largeOld, note: largeOldNote(entry, now: now))
            }
            guard !items.isEmpty else { continue }
            largeChildren.append(ScanGroup(id: "clutter.largeOld.\(kind.rawValue)", title: kind.title,
                                           symbol: kind.symbol, safety: .review, items: items))
        }
        if !largeChildren.isEmpty {
            groups.append(ScanGroup(id: "clutter.largeOld", title: ClutterTool.largeOld.title,
                                    detail: "Your own files, so nothing is selected for you.",
                                    symbol: ClutterTool.largeOld.symbol, safety: .review, children: largeChildren))
        }
        return groups
    }

    public static func largeOldNote(_ entry: ClutterLargeOldItem, now: Date = Date()) -> String {
        let used = entry.file.lastOpened.map { "Last opened \(DurationFormat.relative($0, now: now))" }
            ?? "Last used \(DurationFormat.relative(entry.file.effectiveLastUse, now: now))"
        return "\(entry.reason.title) · \(used)"
    }

    public static func downloadNote(_ item: ClutterDownloadItem, stale: Bool, now: Date = Date()) -> String {
        var parts: [String] = []
        if stale { parts.append("Unfinished download, untouched for over a day") }
        parts.append("Downloaded \(DurationFormat.relative(item.referenceDate, now: now))")
        if let source = item.sourceApp ?? item.sourceHost { parts.append("from \(source)") }
        if item.installerAlreadyUsed { parts.append("app already installed") }
        if item.archiveAlreadyExtracted { parts.append("already unpacked") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Removal safety

/// What will actually be removed after the "never every copy" rule.
public struct ClutterRemovalPlan: Sendable, Equatable {
    public var items: [ScanItem]
    /// Items held back so one copy of a set survives.
    public var heldBack: [ItemFailure]

    public init(items: [ScanItem], heldBack: [ItemFailure]) {
        self.items = items
        self.heldBack = heldBack
    }
}

public enum ClutterRemovalPlanner {
    /// Enforces "never remove every copy": when the items selected from a duplicate set
    /// or similar cluster would leave no other member on disk, the preferred keeper
    /// (or the first selected member) is held back — unless `allowRemovingAllCopies`.
    ///
    /// - Parameters:
    ///   - sets: set id → every member path (from the scan).
    ///   - preferredKeepers: set id → the member to keep when one must survive.
    ///   - stillPresent: true when a member path still exists unchanged on disk.
    public static func plan(_ items: [ScanItem], sets: [String: [String]], preferredKeepers: [String: String],
                            allowRemovingAllCopies: Bool, stillPresent: (String) -> Bool) -> ClutterRemovalPlan {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        guard !allowRemovingAllCopies else { return ClutterRemovalPlan(items: unique, heldBack: []) }

        var held = Set<String>()
        var heldBack: [ItemFailure] = []
        let bySet = Dictionary(grouping: unique.filter { $0.metadata[ClutterMetadataKey.set] != nil }) {
            $0.metadata[ClutterMetadataKey.set] ?? ""
        }
        for (setID, selected) in bySet.sorted(by: { $0.key < $1.key }) {
            let selectedPaths = Set(selected.compactMap { $0.url?.standardizedFileURL.path })
            let members = sets[setID] ?? selected.compactMap { $0.url?.standardizedFileURL.path }
            let survivors = members.filter { !selectedPaths.contains($0) && stillPresent($0) }
            guard survivors.isEmpty else { continue }
            let preferred = preferredKeepers[setID]
            let byPreference = selected.first(where: { $0.url?.standardizedFileURL.path == preferred })
            let byFlag = selected.first(where: { $0.metadata[ClutterMetadataKey.keeper] == "1" })
            let keep = byPreference ?? byFlag ?? selected.min(by: { $0.id < $1.id })
            guard let keep else { continue }
            held.insert(keep.id)
            heldBack.append(ItemFailure(itemID: keep.id, title: keep.title,
                                        reason: "Kept so one copy remains"))
        }
        return ClutterRemovalPlan(items: unique.filter { !held.contains($0.id) }, heldBack: heldBack)
    }
}

// MARK: - Checkup

/// Checkup's Clutter review: duplicate downloads (smart-selected copies pre-selected)
/// and old installers (review only).
public enum ClutterCheckupPlanner {
    public static let duplicatesGroupID = "clutter.checkup.duplicates"
    public static let installersGroupID = "clutter.checkup.installers"

    public static func review(duplicates: [ClutterDuplicateGroup], downloads: [ClutterDownloadItem],
                              paths: ClutterPaths = ClutterPaths(), settings: ClutterScanSettings = ClutterScanSettings(),
                              now: Date = Date()) -> [ScanGroup] {
        let selection = ClutterSmartSelection(paths: paths)
        var used = Set<String>()
        var copies: [ScanItem] = []
        for group in duplicates {
            for file in group.copies where used.insert(file.path).inserted {
                copies.append(ClutterItems.item(
                    file, tool: .duplicates, selected: selection.shouldSelect(file, keeperPath: group.keeperPath),
                    note: "Identical to \(group.keeperPath.abbreviatingHome), which is kept", set: group.id))
            }
            used.insert(group.keeperPath)
        }
        var installers: [ScanItem] = []
        for item in downloads where ClutterDownloadsAnalyzer.isOldInstaller(item, settings: settings, now: now) {
            guard used.insert(item.file.path).inserted else { continue }
            installers.append(ClutterItems.item(item.file, tool: .downloads,
                                                note: ClutterItems.downloadNote(item, stale: false, now: now)))
        }
        var groups: [ScanGroup] = []
        if !copies.isEmpty {
            groups.append(ScanGroup(id: duplicatesGroupID, title: "Duplicate Downloads",
                                    detail: "Identical copies in your Downloads folder. One copy of each is always kept.",
                                    symbol: ClutterTool.duplicates.symbol, safety: .review,
                                    items: copies.sorted { $0.size != $1.size ? $0.size > $1.size : $0.id < $1.id }))
        }
        if !installers.isEmpty {
            groups.append(ScanGroup(id: installersGroupID, title: "Old Installers",
                                    detail: "Disk images and packages downloaded over \(settings.oldInstallerDays) days ago. Review before removing.",
                                    symbol: ClutterDownloadCategory.installers.symbol, safety: .review,
                                    items: installers))
        }
        return groups
    }

    public static func tile(for review: [ScanGroup]) -> CheckupTile {
        let selectedBytes = review.selectedSize
        let selectedCount = review.selectedItems.count
        let duplicateCount = review.first(where: { $0.id == duplicatesGroupID })?.totalCount ?? 0
        let installerCount = review.first(where: { $0.id == installersGroupID })?.totalCount ?? 0
        if review.allItems.isEmpty {
            return CheckupTile(module: .clutter, headline: "No clutter",
                               detail: "No duplicate downloads or old installers.", status: .clear)
        }
        var extras: [String] = []
        if installerCount > 0 {
            extras.append("\(CountFormat.items(installerCount, singular: "old installer")) to review")
        }
        if selectedCount > 0 {
            var detail = "in \(CountFormat.items(selectedCount, singular: "duplicate download"))"
            if !extras.isEmpty { detail += " · " + extras.joined(separator: " · ") }
            return CheckupTile(module: .clutter, headline: ByteFormat.string(selectedBytes), detail: detail,
                               status: .attention, reclaimableBytes: selectedBytes, actionCount: selectedCount)
        }
        if duplicateCount > 0 { extras.insert("\(CountFormat.items(duplicateCount, singular: "duplicate download")) to review", at: 0) }
        return CheckupTile(module: .clutter, headline: ByteFormat.string(review.totalSize),
                           detail: extras.joined(separator: " · "), status: .info, isSelected: false)
    }
}
