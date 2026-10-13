import Foundation

/// Why a file is listed in Large & Old Files.
public enum ClutterLargeOldReason: String, Codable, Sendable, Hashable {
    case large
    case old
    case largeAndOld

    public var isLarge: Bool { self != .old }
    public var isOld: Bool { self != .large }

    public var title: String {
        switch self {
        case .large: return "Large"
        case .old: return "Not opened in a long time"
        case .largeAndOld: return "Large and not opened in a long time"
        }
    }
}

/// Size facet ("By Size").
public enum ClutterSizeBucket: String, CaseIterable, Codable, Sendable, Hashable {
    case huge      // ≥ 5 GB
    case large     // 1–5 GB
    case medium    // 100 MB – 1 GB
    case small     // < 100 MB

    public static func bucket(for bytes: Int64) -> ClutterSizeBucket {
        if bytes >= 5_000_000_000 { return .huge }
        if bytes >= 1_000_000_000 { return .large }
        if bytes >= 100_000_000 { return .medium }
        return .small
    }

    public var title: String {
        switch self {
        case .huge: return "Huge · over 5 GB"
        case .large: return "1 to 5 GB"
        case .medium: return "100 MB to 1 GB"
        case .small: return "Under 100 MB"
        }
    }
}

/// Last-used facet ("By Last Opened").
public enum ClutterAgeBucket: String, CaseIterable, Codable, Sendable, Hashable {
    case thisWeek
    case thisMonth
    case months       // 1–6 months
    case halfYear     // 6–12 months
    case overAYear

    public static func bucket(for date: Date, now: Date = Date()) -> ClutterAgeBucket {
        let days = now.timeIntervalSince(date) / 86_400
        if days < 7 { return .thisWeek }
        if days < 31 { return .thisMonth }
        if days < 183 { return .months }
        if days < 365 { return .halfYear }
        return .overAYear
    }

    public var title: String {
        switch self {
        case .thisWeek: return "Used this week"
        case .thisMonth: return "Used this month"
        case .months: return "1 to 6 months ago"
        case .halfYear: return "6 to 12 months ago"
        case .overAYear: return "Over a year ago"
        }
    }
}

/// One Large & Old Files result.
public struct ClutterLargeOldItem: Sendable, Hashable, Identifiable, Codable {
    public var file: ClutterFile
    public var reason: ClutterLargeOldReason

    public init(file: ClutterFile, reason: ClutterLargeOldReason) {
        self.file = file
        self.reason = reason
    }

    public var id: String { file.path }
    public var sizeBucket: ClutterSizeBucket { ClutterSizeBucket.bucket(for: file.size) }

    public func ageBucket(now: Date = Date()) -> ClutterAgeBucket {
        ClutterAgeBucket.bucket(for: file.effectiveLastUse, now: now)
    }
}

/// Filters walk results into Large & Old Files.
///
/// A file qualifies when it is at least `largeFileThreshold` big, or when it is at
/// least `oldMinimumSize` big and has not been opened or changed for `oldFileDays`.
public enum ClutterLargeOldFilter {
    public static func reason(for file: ClutterFile, settings: ClutterScanSettings,
                              now: Date = Date()) -> ClutterLargeOldReason? {
        guard !file.isPlaceholder, !file.isFolder, file.size > 0 else { return nil }
        let isLarge = file.size >= settings.largeFileThreshold
        let cutoff = now.addingTimeInterval(-TimeInterval(settings.oldFileDays) * 86_400)
        let isOld = file.size >= settings.oldMinimumSize && file.effectiveLastUse < cutoff
        switch (isLarge, isOld) {
        case (true, true): return .largeAndOld
        case (true, false): return .large
        case (false, true): return .old
        default: return nil
        }
    }

    /// Qualifying files, largest first.
    public static func items(from files: [ClutterFile], settings: ClutterScanSettings,
                             now: Date = Date()) -> [ClutterLargeOldItem] {
        files.compactMap { file in
            reason(for: file, settings: settings, now: now).map { ClutterLargeOldItem(file: file, reason: $0) }
        }
        .sorted { $0.file.size != $1.file.size ? $0.file.size > $1.file.size : $0.file.path < $1.file.path }
    }
}

/// Filter + sort state of the Large & Old list (shared by the UI and tests).
public struct ClutterLargeOldQuery: Equatable, Sendable {
    public enum Sort: String, CaseIterable, Sendable {
        case size = "Size"
        case name = "Name"
        case lastOpened = "Last Opened"
        case kind = "Kind"
    }

    public enum Scope: String, CaseIterable, Sendable {
        case all = "All Files"
        case large = "Large"
        case old = "Old"
        case selected = "Selected"
    }

    public var scope: Scope = .all
    public var kind: ClutterKind?
    public var sizeBucket: ClutterSizeBucket?
    public var ageBucket: ClutterAgeBucket?
    public var search: String = ""
    public var sort: Sort = .size
    public var ascending: Bool = false

    public init() {}

    public func apply(_ items: [ClutterLargeOldItem], selected: Set<String>, now: Date = Date()) -> [ClutterLargeOldItem] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = items.filter { item in
            switch scope {
            case .all: break
            case .large: if !item.reason.isLarge { return false }
            case .old: if !item.reason.isOld { return false }
            case .selected: if !selected.contains(item.id) { return false }
            }
            if let kind, item.file.kind != kind { return false }
            if let sizeBucket, item.sizeBucket != sizeBucket { return false }
            if let ageBucket, item.ageBucket(now: now) != ageBucket { return false }
            if !needle.isEmpty && !item.file.path.lowercased().contains(needle) { return false }
            return true
        }
        return filtered.sorted { a, b in
            let ordered: Bool
            switch sort {
            case .size:
                if a.file.size == b.file.size { return a.file.path < b.file.path }
                ordered = a.file.size < b.file.size
            case .name:
                let cmp = a.file.name.localizedStandardCompare(b.file.name)
                if cmp == .orderedSame { return a.file.path < b.file.path }
                ordered = cmp == .orderedAscending
            case .lastOpened:
                if a.file.effectiveLastUse == b.file.effectiveLastUse { return a.file.path < b.file.path }
                ordered = a.file.effectiveLastUse < b.file.effectiveLastUse
            case .kind:
                if a.file.kind == b.file.kind {
                    if a.file.size == b.file.size { return a.file.path < b.file.path }
                    return a.file.size > b.file.size
                }
                ordered = a.file.kind.title < b.file.kind.title
            }
            return ascending ? ordered : !ordered
        }
    }
}
