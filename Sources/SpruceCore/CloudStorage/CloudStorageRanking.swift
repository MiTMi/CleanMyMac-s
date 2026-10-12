import Foundation

/// Ranking helpers for the "largest files" lists.
public enum CloudStorageRanking {
    public enum Measure: Sendable, Hashable {
        /// Bytes on this Mac.
        case local
        /// Size in the cloud.
        case logical
    }

    public static func value(_ record: CloudStorageFileRecord, _ measure: Measure) -> Int64 {
        switch measure {
        case .local: return record.localBytes
        case .logical: return record.cloudBytes
        }
    }

    /// Biggest first; ties broken by path so the order is stable.
    public static func sorted(_ records: [CloudStorageFileRecord], by measure: Measure) -> [CloudStorageFileRecord] {
        records.sorted { a, b in
            let va = value(a, measure)
            let vb = value(b, measure)
            if va != vb { return va > vb }
            return a.path < b.path
        }
    }
}

/// Keeps the N biggest records seen so far without holding every file in memory.
///
/// Records below `minimumSize` are ignored. Insertion is amortised O(1): the buffer is
/// sorted and trimmed only when it grows to twice the limit.
public struct CloudStorageTopFiles: Sendable {
    public let limit: Int
    public let minimumSize: Int64
    public let measure: CloudStorageRanking.Measure

    private var buffer: [CloudStorageFileRecord] = []
    /// Smallest value still kept after the last trim (cheap pre-filter).
    private var floor: Int64 = 0

    public init(limit: Int, minimumSize: Int64 = 0, measure: CloudStorageRanking.Measure) {
        self.limit = max(0, limit)
        self.minimumSize = max(0, minimumSize)
        self.measure = measure
    }

    public mutating func insert(_ record: CloudStorageFileRecord) {
        guard limit > 0 else { return }
        let value = CloudStorageRanking.value(record, measure)
        guard value > 0, value >= minimumSize, value >= floor else { return }
        buffer.append(record)
        if buffer.count >= limit * 2 { trim() }
    }

    /// The kept records, biggest first, at most `limit`.
    public var sorted: [CloudStorageFileRecord] {
        Array(CloudStorageRanking.sorted(buffer, by: measure).prefix(limit))
    }

    public var count: Int { min(buffer.count, limit) }

    private mutating func trim() {
        buffer = Array(CloudStorageRanking.sorted(buffer, by: measure).prefix(limit))
        if buffer.count == limit, let last = buffer.last {
            floor = CloudStorageRanking.value(last, measure)
        }
    }
}
