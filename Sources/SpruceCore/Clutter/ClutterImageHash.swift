import Foundation

/// An 8-bit grayscale bitmap (row-major, top row first), e.g. a 64-pixel thumbnail.
public struct ClutterGrayImage: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count >= width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    @inline(__always)
    public func pixel(_ x: Int, _ y: Int) -> UInt8 { pixels[y * width + x] }
}

/// Perceptual hashes computed from grayscale thumbnails.
public enum ClutterImageHasher {
    /// Box-filter (area average) resample to `w × h`, values 0…255.
    public static func resample(_ image: ClutterGrayImage, width w: Int, height h: Int) -> [Double] {
        var out = [Double](repeating: 0, count: w * h)
        for ty in 0..<h {
            let y0 = ty * image.height / h
            let y1 = max(y0 + 1, (ty + 1) * image.height / h)
            for tx in 0..<w {
                let x0 = tx * image.width / w
                let x1 = max(x0 + 1, (tx + 1) * image.width / w)
                var sum = 0
                var count = 0
                for y in y0..<min(y1, image.height) {
                    let row = y * image.width
                    for x in x0..<min(x1, image.width) {
                        sum += Int(image.pixels[row + x])
                        count += 1
                    }
                }
                out[ty * w + tx] = count > 0 ? Double(sum) / Double(count) : 0
            }
        }
        return out
    }

    /// 64-bit difference hash: 9×8 grid, one bit per horizontal neighbour pair
    /// (1 when the right pixel is brighter).
    public static func dHash(_ image: ClutterGrayImage) -> UInt64 {
        let grid = resample(image, width: 9, height: 8)
        var hash: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                hash <<= 1
                if grid[y * 9 + x] < grid[y * 9 + x + 1] { hash |= 1 }
            }
        }
        return hash
    }

    /// 64-bit average hash: 8×8 grid, one bit per cell brighter than the mean.
    public static func aHash(_ image: ClutterGrayImage) -> UInt64 {
        let grid = resample(image, width: 8, height: 8)
        let mean = grid.reduce(0, +) / Double(grid.count)
        var hash: UInt64 = 0
        for value in grid {
            hash <<= 1
            if value > mean { hash |= 1 }
        }
        return hash
    }

    @inline(__always)
    public static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
}

/// The perceptual fingerprint of one image file.
public struct ClutterImageFingerprint: Sendable, Hashable, Codable {
    public var path: String
    public var dHash: UInt64
    public var aHash: UInt64
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(path: String, dHash: UInt64, aHash: UInt64, pixelWidth: Int, pixelHeight: Int) {
        self.path = path
        self.dHash = dHash
        self.aHash = aHash
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public init(path: String, thumbnail: ClutterGrayImage, pixelWidth: Int, pixelHeight: Int) {
        self.init(path: path, dHash: ClutterImageHasher.dHash(thumbnail), aHash: ClutterImageHasher.aHash(thumbnail),
                  pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    public var pixelCount: Int { pixelWidth * pixelHeight }
}

/// A set of images that look nearly the same.
public struct ClutterSimilarCluster: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    /// Members, best shot first.
    public var files: [ClutterFile]
    public var fingerprints: [String: ClutterImageFingerprint]
    public var bestPath: String

    public init(id: String, files: [ClutterFile], fingerprints: [String: ClutterImageFingerprint], bestPath: String) {
        self.id = id
        self.files = files
        self.fingerprints = fingerprints
        self.bestPath = bestPath
    }

    public var best: ClutterFile? { files.first { $0.path == bestPath } }
    public var others: [ClutterFile] { files.filter { $0.path != bestPath } }
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    /// Bytes freed by keeping only the best shot.
    public var reclaimableBytes: Int64 { others.reduce(0) { $0 + $1.size } }
}

/// Groups fingerprints into clusters of similar images.
///
/// Candidate pairs come from a BK-tree over dHash (Hamming radius `dHashRadius`) and
/// must also agree on aHash (`aHashRadius`). Pairs are merged closest-first with a
/// complete-linkage guard: two clusters join only if every cross pair is within
/// `linkageRadius`, which stops chains of slightly different pictures (A~B~C~…~Z).
public struct ClutterSimilarClusterer: Sendable {
    public var dHashRadius: Int
    public var aHashRadius: Int
    public var linkageRadius: Int
    /// Clusters larger than this stop growing (keeps the review manageable).
    public var maximumClusterSize: Int

    public init(dHashRadius: Int = 7, aHashRadius: Int = 12, linkageRadius: Int? = nil, maximumClusterSize: Int = 60) {
        self.dHashRadius = max(0, dHashRadius)
        self.aHashRadius = max(0, aHashRadius)
        self.linkageRadius = linkageRadius ?? (max(0, dHashRadius) + 3)
        self.maximumClusterSize = max(2, maximumClusterSize)
    }

    public func isSimilar(_ a: ClutterImageFingerprint, _ b: ClutterImageFingerprint) -> Bool {
        ClutterImageHasher.hamming(a.dHash, b.dHash) <= dHashRadius
            && ClutterImageHasher.hamming(a.aHash, b.aHash) <= aHashRadius
    }

    /// Index clusters (each with at least two members), largest first.
    public func cluster(_ prints: [ClutterImageFingerprint], shouldContinue: () -> Bool = { true }) -> [[Int]] {
        guard prints.count > 1 else { return [] }
        var tree = ClutterBKTree()
        for (index, fp) in prints.enumerated() { tree.insert(fp.dHash, index: index) }

        struct Edge { var d: Int; var a: Int; var i: Int; var j: Int }
        var edges: [Edge] = []
        for (i, fp) in prints.enumerated() {
            if i % 256 == 0 && !shouldContinue() { return [] }
            for j in tree.query(fp.dHash, radius: dHashRadius) where j > i {
                let a = ClutterImageHasher.hamming(fp.aHash, prints[j].aHash)
                guard a <= aHashRadius else { continue }
                edges.append(Edge(d: ClutterImageHasher.hamming(fp.dHash, prints[j].dHash), a: a, i: i, j: j))
            }
        }
        edges.sort { ($0.d, $0.a, $0.i, $0.j) < ($1.d, $1.a, $1.i, $1.j) }

        var parent = Array(prints.indices)
        var members: [Int: [Int]] = [:]
        for i in prints.indices { members[i] = [i] }
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        for edge in edges {
            let ra = find(edge.i), rb = find(edge.j)
            guard ra != rb, let ma = members[ra], let mb = members[rb] else { continue }
            guard ma.count + mb.count <= maximumClusterSize else { continue }
            var compatible = true
            outer: for x in ma {
                for y in mb where ClutterImageHasher.hamming(prints[x].dHash, prints[y].dHash) > linkageRadius {
                    compatible = false
                    break outer
                }
            }
            guard compatible else { continue }
            parent[rb] = ra
            members[ra] = ma + mb
            members[rb] = nil
        }
        return members.values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0[0] < $1[0] }
    }

    /// Builds clusters of files. `files` and `prints` are matched by path.
    public func clusters(files: [ClutterFile], prints: [ClutterImageFingerprint],
                         shouldContinue: () -> Bool = { true }) -> [ClutterSimilarCluster] {
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let usable = prints.filter { byPath[$0.path] != nil }
        return cluster(usable, shouldContinue: shouldContinue).compactMap { indices -> ClutterSimilarCluster? in
            let memberPrints = indices.map { usable[$0] }
            let memberFiles = memberPrints.compactMap { byPath[$0.path] }
            guard memberFiles.count > 1 else { return nil }
            let printMap = Dictionary(memberPrints.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            let best = Self.bestShot(memberFiles, prints: printMap)
            let ordered = [best] + memberFiles.filter { $0.path != best.path }.sorted { $0.path < $1.path }
            let id = "sim:" + ClutterSHA256.hex(ordered.map(\.path).sorted().joined(separator: "\n")).prefix(16)
            return ClutterSimilarCluster(id: String(id), files: ordered, fingerprints: printMap, bestPath: best.path)
        }
        .sorted {
            $0.reclaimableBytes != $1.reclaimableBytes ? $0.reclaimableBytes > $1.reclaimableBytes : $0.id < $1.id
        }
    }

    /// The best shot: most pixels, then the largest file, then the oldest, then the
    /// shortest path.
    public static func bestShot(_ files: [ClutterFile], prints: [String: ClutterImageFingerprint]) -> ClutterFile {
        files.min { a, b in
            let pa = prints[a.path]?.pixelCount ?? 0
            let pb = prints[b.path]?.pixelCount ?? 0
            if pa != pb { return pa > pb }
            if a.logicalSize != b.logicalSize { return a.logicalSize > b.logicalSize }
            if a.originDate != b.originDate { return a.originDate < b.originDate }
            if a.path.count != b.path.count { return a.path.count < b.path.count }
            return a.path < b.path
        }!
    }
}

/// Burkhard–Keller tree over 64-bit hashes with Hamming distance.
public struct ClutterBKTree: Sendable {
    private var hashes: [UInt64] = []
    private var items: [Int] = []
    private var children: [[Int: Int]] = []

    public init() {}

    public var count: Int { hashes.count }

    public mutating func insert(_ hash: UInt64, index: Int) {
        let node = hashes.count
        hashes.append(hash)
        items.append(index)
        children.append([:])
        guard node > 0 else { return }
        var current = 0
        while true {
            let d = ClutterImageHasher.hamming(hash, hashes[current])
            if let child = children[current][d] {
                current = child
            } else {
                children[current][d] = node
                return
            }
        }
    }

    /// Item indices whose hash is within `radius` of `hash`.
    public func query(_ hash: UInt64, radius: Int) -> [Int] {
        guard !hashes.isEmpty else { return [] }
        var found: [Int] = []
        var stack = [0]
        while let node = stack.popLast() {
            let d = ClutterImageHasher.hamming(hash, hashes[node])
            if d <= radius { found.append(items[node]) }
            for (distance, child) in children[node] where distance >= d - radius && distance <= d + radius {
                stack.append(child)
            }
        }
        return found
    }
}
