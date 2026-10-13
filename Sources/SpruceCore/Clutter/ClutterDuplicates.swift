import Foundation

/// A set of files with identical content.
public struct ClutterDuplicateGroup: Sendable, Hashable, Identifiable, Codable {
    /// Content hash (SHA-256, hex).
    public var hash: String
    /// Members, keeper first, then by path.
    public var files: [ClutterFile]
    /// The copy smart selection keeps.
    public var keeperPath: String
    /// Why the keeper was chosen ("Oldest copy", "Outside Downloads"…).
    public var keeperReason: String

    public init(hash: String, files: [ClutterFile], keeperPath: String, keeperReason: String) {
        self.hash = hash
        self.files = files
        self.keeperPath = keeperPath
        self.keeperReason = keeperReason
    }

    public var id: String { "dup:" + hash }
    public var keeper: ClutterFile? { files.first { $0.path == keeperPath } }
    public var copies: [ClutterFile] { files.filter { $0.path != keeperPath } }
    /// Size of one copy.
    public var fileSize: Int64 { files.map(\.size).max() ?? 0 }
    /// Bytes freed by removing every copy but the keeper.
    public var reclaimableBytes: Int64 { copies.reduce(0) { $0 + $1.size } }
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    public var displayName: String { keeper?.name ?? files.first?.name ?? "" }
}

/// Finds files with identical content: size buckets → partial hash (first and last
/// 64 KB) → full SHA-256. Zero-byte files and cloud placeholders are skipped and
/// hard links of one file count once.
public struct ClutterDuplicateFinder: Sendable {
    public typealias PartialHasher = @Sendable (ClutterFile) -> String?
    public typealias FullHasher = @Sendable (ClutterFile, _ shouldContinue: () -> Bool) -> String?

    public var paths: ClutterPaths
    public var partialHasher: PartialHasher
    public var fullHasher: FullHasher
    /// Files hashed at the same time.
    public var concurrency: Int

    public init(paths: ClutterPaths = ClutterPaths(), concurrency: Int = 4,
                partialHasher: PartialHasher? = nil, fullHasher: FullHasher? = nil) {
        self.paths = paths
        self.concurrency = max(1, concurrency)
        self.partialHasher = partialHasher ?? { file in
            ClutterFileHasher.partialHash(path: file.path, size: file.logicalSize)
        }
        self.fullHasher = fullHasher ?? { file, shouldContinue in
            ClutterFileHasher.fullHash(path: file.path, expectedSize: file.logicalSize, shouldContinue: shouldContinue)
        }
    }

    /// Files that can take part in duplicate detection.
    public func candidates(_ files: [ClutterFile], minimumSize: Int64) -> [ClutterFile] {
        var seen = Set<FileIdentity>()
        var seenPaths = Set<String>()
        var result: [ClutterFile] = []
        for file in files {
            guard file.logicalSize > 0, !file.isPlaceholder, !file.isPackage, !file.isFolder else { continue }
            guard paths.isInDownloads(file.path) || file.logicalSize >= minimumSize else { continue }
            guard seenPaths.insert(file.path).inserted else { continue }
            if file.inode != 0 && !seen.insert(file.identity).inserted { continue }
            result.append(file)
        }
        return result
    }

    /// Groups duplicate files, largest reclaimable first.
    ///
    /// - Parameters:
    ///   - progress: fraction (0…1) of hashing work done and the file being read.
    ///   - shouldContinue: polled between files; returning false ends early with the
    ///     groups confirmed so far.
    public func findDuplicates(
        in files: [ClutterFile],
        minimumSize: Int64,
        progress: @escaping @Sendable (Double, String) -> Void = { _, _ in },
        shouldContinue: @escaping @Sendable () -> Bool = { true }
    ) -> [ClutterDuplicateGroup] {
        let pool = candidates(files, minimumSize: minimumSize)
        // Stage A: same logical size.
        let bySize = Dictionary(grouping: pool, by: \.logicalSize).values.filter { $0.count > 1 }
        let sizeMatched = bySize.flatMap { $0 }
        guard !sizeMatched.isEmpty else { return [] }

        // Stage B: partial hash.
        let partialTotal = sizeMatched.count
        let partials = ClutterParallel.map(sizeMatched, concurrency: concurrency, shouldContinue: shouldContinue) { index, file in
            if index % 16 == 0 { progress(Double(index) / Double(partialTotal) * 0.5, file.path) }
            return partialHasher(file)
        }
        var partialGroups: [String: [ClutterFile]] = [:]
        for (file, hash) in zip(sizeMatched, partials) {
            guard let hash else { continue }
            partialGroups["\(file.logicalSize):\(hash)", default: []].append(file)
        }
        let partialMatched = partialGroups.filter { $0.value.count > 1 }

        // Small files are fully covered by the partial hash.
        var confirmed: [(hash: String, files: [ClutterFile])] = []
        var needsFull: [ClutterFile] = []
        for (key, members) in partialMatched {
            if ClutterFileHasher.partialCoversWholeFile(size: members[0].logicalSize) {
                confirmed.append((key, members))
            } else {
                needsFull.append(contentsOf: members)
            }
        }

        // Stage C: full hash.
        if !needsFull.isEmpty && shouldContinue() {
            let fullTotal = needsFull.reduce(Int64(0)) { $0 + $1.logicalSize }
            let done = ClutterAtomicCounter()
            let fulls = ClutterParallel.map(needsFull, concurrency: concurrency, shouldContinue: shouldContinue) { _, file in
                let hash = fullHasher(file, shouldContinue)
                let bytes = done.add(file.logicalSize)
                progress(0.5 + 0.5 * Double(bytes) / Double(max(fullTotal, 1)), file.path)
                return hash
            }
            var fullGroups: [String: [ClutterFile]] = [:]
            for (file, hash) in zip(needsFull, fulls) {
                guard let hash else { continue }
                fullGroups["\(file.logicalSize):\(hash)", default: []].append(file)
            }
            for (key, members) in fullGroups where members.count > 1 {
                confirmed.append((key, members))
            }
        }
        progress(1, "")

        return confirmed.map { entry in
            let hash = String(entry.hash.split(separator: ":").last ?? Substring(entry.hash))
            return ClutterSmartSelection(paths: paths).makeGroup(hash: hash, files: entry.files)
        }
        .sorted {
            $0.reclaimableBytes != $1.reclaimableBytes ? $0.reclaimableBytes > $1.reclaimableBytes : $0.hash < $1.hash
        }
    }
}

// MARK: - Smart selection

/// Chooses which copy of a duplicate set to keep, and which copies to pre-select.
///
/// Keeper ranking (first difference wins):
/// 1. outside Downloads, the Trash and temporary folders;
/// 2. not in a cloud-synced folder;
/// 3. a clean name (no " copy", " (1)", "Copy of "…);
/// 4. the oldest (creation date, else modification date);
/// 5. the shortest path;
/// 6. alphabetical path (deterministic).
///
/// Every other copy is selected, except copies in cloud-synced folders (deleting
/// those also deletes them on the user's other devices), which are left for review.
public struct ClutterSmartSelection: Sendable {
    public var paths: ClutterPaths

    public init(paths: ClutterPaths = ClutterPaths()) {
        self.paths = paths
    }

    /// True for names that look like a copy of another file.
    public static func hasCopyMarker(_ name: String) -> Bool {
        let base = ((name as NSString).deletingPathExtension).lowercased()
        if base.hasPrefix("copy of ") { return true }
        if base.contains("conflicted copy") || base.contains("'s conflicted") { return true }
        if base.hasSuffix(" copy") { return true }
        // " copy 2", " copy 13"
        if let range = base.range(of: " copy ", options: .backwards) {
            let tail = base[range.upperBound...]
            if !tail.isEmpty && tail.allSatisfy(\.isNumber) { return true }
        }
        // " (1)", "(2)"
        if base.hasSuffix(")"), let open = base.lastIndex(of: "(") {
            let inner = base[base.index(after: open)..<base.index(before: base.endIndex)]
            if !inner.isEmpty && inner.allSatisfy(\.isNumber) { return true }
        }
        // Browser/Finder duplicates such as "report-1", "report_2".
        if let last = base.last, last.isNumber {
            let trimmed = base.reversed().drop(while: \.isNumber)
            if let separator = trimmed.first, separator == "-" || separator == "_",
               base.count - trimmed.count <= 2 {
                return true
            }
        }
        return false
    }

    private struct Rank: Comparable {
        var transient: Int
        var cloud: Int
        var copyMarker: Int
        var origin: Date
        var depth: Int
        var length: Int
        var path: String

        static func < (a: Rank, b: Rank) -> Bool {
            if a.transient != b.transient { return a.transient < b.transient }
            if a.cloud != b.cloud { return a.cloud < b.cloud }
            if a.copyMarker != b.copyMarker { return a.copyMarker < b.copyMarker }
            if a.origin != b.origin { return a.origin < b.origin }
            if a.depth != b.depth { return a.depth < b.depth }
            if a.length != b.length { return a.length < b.length }
            return a.path < b.path
        }
    }

    private func rank(_ file: ClutterFile) -> Rank {
        Rank(transient: paths.isTransient(file.path) ? 1 : 0,
             cloud: isCloud(file) ? 1 : 0,
             copyMarker: Self.hasCopyMarker(file.name) ? 1 : 0,
             origin: file.originDate,
             depth: file.path.split(separator: "/").count,
             length: file.path.count,
             path: file.path)
    }

    public func isCloud(_ file: ClutterFile) -> Bool {
        file.isCloud || paths.isCloud(file.path)
    }

    /// The copy to keep.
    public func keeper(of files: [ClutterFile]) -> ClutterFile? {
        files.min { rank($0) < rank($1) }
    }

    /// Short explanation of why `keeper` wins over the other copies.
    public func keeperReason(_ keeper: ClutterFile, among files: [ClutterFile]) -> String {
        let others = files.filter { $0.path != keeper.path }
        guard !others.isEmpty else { return "Only copy" }
        let k = rank(keeper)
        let ranks = others.map(rank)
        if ranks.allSatisfy({ $0.transient > k.transient }) { return "Kept the copy outside Downloads and the Trash" }
        if ranks.allSatisfy({ $0.cloud > k.cloud }) { return "Kept the copy stored on this Mac" }
        if ranks.allSatisfy({ $0.copyMarker > k.copyMarker }) { return "Kept the copy without “copy” in its name" }
        if ranks.allSatisfy({ $0.origin > k.origin }) { return "Kept the oldest copy" }
        if ranks.allSatisfy({ $0.depth > k.depth || ($0.depth == k.depth && $0.length > k.length) }) {
            return "Kept the copy with the shortest path"
        }
        return "Kept the first copy"
    }

    /// Whether smart selection pre-selects `file` for removal.
    public func shouldSelect(_ file: ClutterFile, keeperPath: String) -> Bool {
        file.path != keeperPath && !isCloud(file)
    }

    /// Builds a group with the keeper first and the remaining copies sorted by path.
    public func makeGroup(hash: String, files: [ClutterFile]) -> ClutterDuplicateGroup {
        guard let keeper = keeper(of: files) else {
            return ClutterDuplicateGroup(hash: hash, files: files, keeperPath: "", keeperReason: "")
        }
        let others = files.filter { $0.path != keeper.path }.sorted { $0.path < $1.path }
        return ClutterDuplicateGroup(hash: hash, files: [keeper] + others, keeperPath: keeper.path,
                                     keeperReason: keeperReason(keeper, among: files))
    }

    /// Smart-selected paths across groups.
    public func selection(for groups: [ClutterDuplicateGroup]) -> Set<String> {
        var selected = Set<String>()
        for group in groups {
            for file in group.files where shouldSelect(file, keeperPath: group.keeperPath) {
                selected.insert(file.path)
            }
        }
        return selected
    }
}

// MARK: - Parallel helpers

/// Bounded parallel map on Dispatch (available on macOS and Linux).
public enum ClutterParallel {
    /// Applies `transform` to every element using up to `concurrency` threads. Elements
    /// processed after `shouldContinue` turns false yield nil. Order is preserved.
    public static func map<T, R>(
        _ items: [T],
        concurrency: Int,
        shouldContinue: @escaping () -> Bool = { true },
        transform: (Int, T) -> R?
    ) -> [R?] {
        guard !items.isEmpty else { return [] }
        let lanes = max(1, min(concurrency, items.count))
        var results = [R?](repeating: nil, count: items.count)
        let lock = NSLock()
        var next = 0
        results.withUnsafeMutableBufferPointer { buffer in
            let base = buffer
            DispatchQueue.concurrentPerform(iterations: lanes) { _ in
                while true {
                    lock.lock()
                    let index = next
                    next += 1
                    lock.unlock()
                    guard index < items.count else { return }
                    guard shouldContinue() else { continue }
                    let value = transform(index, items[index])
                    base[index] = value
                }
            }
        }
        return results
    }
}

/// A thread-safe running total.
public final class ClutterAtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0

    public init() {}

    /// Adds `amount` and returns the new total.
    @discardableResult
    public func add(_ amount: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        value += amount
        return value
    }

    public var current: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
