import Foundation

// MARK: - Scan state

/// Scan state of one Checkup area (one contributing module).
public enum CheckupAreaState: Equatable, Sendable {
    /// Included and queued, not started yet.
    case waiting
    /// The contributor's `checkupScan` is running.
    case scanning
    /// Finished with a tile.
    case finished(CheckupTile)
    /// Turned off in Settings › Scanning (`SpruceSettings.checkupModules`).
    case excluded
    /// The scan threw; the reason is user-facing.
    case failed(String)
    /// No contributor is registered for this module.
    case unsupported

    /// True while the area still has scanning work to do.
    public var isPending: Bool {
        switch self {
        case .waiting, .scanning: return true
        default: return false
        }
    }

    /// True when the area takes part in the scan (not excluded or unsupported).
    public var isParticipating: Bool {
        switch self {
        case .excluded, .unsupported: return false
        default: return true
        }
    }
}

/// One Checkup area: its scan state and the latest progress it reported.
public struct CheckupArea: Identifiable, Equatable, Sendable {
    public var module: ModuleID
    public var id: ModuleID { module }
    public var state: CheckupAreaState
    public var progress: ScanProgress
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(module: ModuleID, state: CheckupAreaState, progress: ScanProgress = ScanProgress(message: ""),
                startedAt: Date? = nil, finishedAt: Date? = nil) {
        self.module = module
        self.state = state
        self.progress = progress
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    /// The finished tile, if any.
    public var tile: CheckupTile? {
        if case .finished(let tile) = state { return tile }
        return nil
    }

    /// Progress of this area in 0...1 at `now`.
    ///
    /// Finished and failed areas count as complete. A scanning area uses the
    /// contributor's fraction when it reports one; otherwise an asymptotic estimate
    /// based on elapsed time (never above 0.9) keeps the combined ring moving.
    public func fraction(at now: Date) -> Double {
        switch state {
        case .finished, .failed: return 1
        case .excluded, .unsupported, .waiting: return 0
        case .scanning:
            if let reported = progress.fraction { return min(reported, 0.99) }
            guard let startedAt else { return 0 }
            let elapsed = max(0, now.timeIntervalSince(startedAt))
            return 0.9 * (1 - exp(-elapsed / CheckupBoard.indeterminateTimeConstant))
        }
    }
}

// MARK: - Board

/// Value-type model of a Checkup scan: one area per contributing module, in tile order.
///
/// The app's session owns one of these and mutates it as contributors report; all
/// derived numbers (combined progress, bytes found, result tiles, default selection)
/// are computed here so they can be unit-tested.
public struct CheckupBoard: Equatable, Sendable {
    /// Seconds after which an indeterminate area is estimated at ~57 % (×0.9).
    public static let indeterminateTimeConstant: TimeInterval = 20

    public static let excludedReason = "Turned off in Settings"
    public static let unsupportedReason = "Not available in this version"

    public private(set) var areas: [CheckupArea]

    /// - Parameters:
    ///   - modules: tile order (defaults to `ModuleID.checkupContributors`).
    ///   - included: modules the user included (`SpruceSettings.checkupModules`).
    ///   - available: modules that have a registered contributor.
    public init(modules: [ModuleID] = ModuleID.checkupContributors, included: Set<ModuleID>, available: Set<ModuleID>) {
        areas = modules.map { module in
            let state: CheckupAreaState
            if !included.contains(module) {
                state = .excluded
            } else if !available.contains(module) {
                state = .unsupported
            } else {
                state = .waiting
            }
            return CheckupArea(module: module, state: state)
        }
    }

    // MARK: Queries

    public func area(_ module: ModuleID) -> CheckupArea? {
        areas.first { $0.module == module }
    }

    /// Modules that still have to be scanned (waiting or scanning).
    public var pendingModules: [ModuleID] { areas.filter { $0.state.isPending }.map(\.module) }

    /// Modules that take part in the scan (not excluded/unsupported).
    public var participatingModules: [ModuleID] { areas.filter { $0.state.isParticipating }.map(\.module) }

    public var isScanning: Bool { areas.contains { $0.state.isPending } }

    /// True when at least one area can be scanned.
    public var hasWork: Bool { !participatingModules.isEmpty }

    /// Combined progress across participating areas, 0...1.
    public func overallFraction(at now: Date = Date()) -> Double {
        let parts = areas.filter { $0.state.isParticipating }
        guard !parts.isEmpty else { return 1 }
        let sum = parts.reduce(0.0) { $0 + $1.fraction(at: now) }
        return min(max(sum / Double(parts.count), 0), 1)
    }

    /// Reclaimable bytes found so far: finished tiles plus the running totals of
    /// areas still scanning.
    public var bytesFound: Int64 {
        areas.reduce(0) { total, area in
            switch area.state {
            case .finished(let tile): return total + max(0, tile.reclaimableBytes)
            case .scanning: return total + max(0, area.progress.bytesFound)
            default: return total
            }
        }
    }

    /// Result tile for every area, in tile order. Excluded, unsupported, failed and
    /// unfinished areas become `.unavailable` tiles with a reason.
    public var tiles: [CheckupTile] { areas.map(Self.tile(for:)) }

    public func tile(for module: ModuleID) -> CheckupTile? {
        area(module).map(Self.tile(for:))
    }

    public static func tile(for area: CheckupArea) -> CheckupTile {
        switch area.state {
        case .finished(let tile): return tile
        case .excluded: return .unavailable(area.module, reason: excludedReason)
        case .unsupported: return .unavailable(area.module, reason: unsupportedReason)
        case .failed(let reason): return .unavailable(area.module, reason: "Couldn't finish: \(reason)")
        case .waiting, .scanning: return .unavailable(area.module, reason: "Not scanned")
        }
    }

    /// Whether a tile can be included in Run (it has a checkbox).
    public static func isSelectable(_ tile: CheckupTile) -> Bool {
        tile.status != .unavailable && tile.status != .clear
    }

    /// Tiles included in Run by default: selectable tiles whose `isSelected` is set.
    public var defaultSelection: Set<ModuleID> {
        Set(tiles.filter { Self.isSelectable($0) && $0.isSelected }.map(\.module))
    }

    /// Modules whose tile can be toggled.
    public var selectableModules: Set<ModuleID> {
        Set(tiles.filter(Self.isSelectable).map(\.module))
    }

    // MARK: Mutations

    /// Marks an area as started. Only waiting areas can start.
    public mutating func start(_ module: ModuleID, at date: Date = Date()) {
        mutate(module) { area in
            guard area.state == .waiting else { return }
            area.state = .scanning
            area.startedAt = date
            area.finishedAt = nil
        }
    }

    /// Records progress for an area that is still scanning; ignored otherwise (late
    /// progress events must not resurrect a finished area).
    public mutating func update(_ module: ModuleID, progress: ScanProgress) {
        mutate(module) { area in
            guard area.state.isPending else { return }
            if area.state == .waiting { area.state = .scanning }
            area.progress = progress
        }
    }

    public mutating func finish(_ module: ModuleID, tile: CheckupTile, at date: Date = Date()) {
        mutate(module) { area in
            guard area.state.isPending else { return }
            var stored = tile
            stored.module = module
            area.state = .finished(stored)
            area.finishedAt = date
        }
    }

    public mutating func fail(_ module: ModuleID, reason: String, at date: Date = Date()) {
        mutate(module) { area in
            guard area.state.isPending else { return }
            area.state = .failed(reason)
            area.finishedAt = date
        }
    }

    /// Puts one area back in the queue (rescan a failed area, or include an area that
    /// was excluded at scan time).
    public mutating func requeue(_ module: ModuleID) {
        mutate(module) { area in
            area.state = .waiting
            area.progress = ScanProgress(message: "")
            area.startedAt = nil
            area.finishedAt = nil
        }
    }

    /// Replaces the finished tile of an area (after the user edited its review).
    public mutating func replaceTile(_ module: ModuleID, with tile: CheckupTile) {
        mutate(module) { area in
            guard case .finished = area.state else { return }
            var stored = tile
            stored.module = module
            area.state = .finished(stored)
        }
    }

    private mutating func mutate(_ module: ModuleID, _ body: (inout CheckupArea) -> Void) {
        guard let index = areas.firstIndex(where: { $0.module == module }) else { return }
        body(&areas[index])
    }
}

// MARK: - Selection summary

/// Totals for the tiles currently included in Run (the Summary tile and the Run orb).
public struct CheckupSelectionSummary: Equatable, Sendable {
    /// Selected modules in tile order.
    public var modules: [ModuleID]
    public var reclaimableBytes: Int64
    public var actionCount: Int
    /// Number of tiles that could be selected.
    public var selectableCount: Int

    public init(tiles: [CheckupTile], selection: Set<ModuleID>) {
        let selectable = tiles.filter(CheckupBoard.isSelectable)
        let chosen = selectable.filter { selection.contains($0.module) }
        modules = chosen.map(\.module)
        reclaimableBytes = chosen.reduce(0) { $0 + max(0, $1.reclaimableBytes) }
        actionCount = chosen.reduce(0) { $0 + max(0, $1.actionCount) }
        selectableCount = selectable.count
    }

    public var isEmpty: Bool { modules.isEmpty }

    /// Short orb subtitle: "7.1 GB", "4 actions" or "Nothing selected".
    public var orbDetail: String {
        if modules.isEmpty { return "Nothing selected" }
        if reclaimableBytes > 0 { return ByteFormat.string(reclaimableBytes) }
        if actionCount > 0 { return CountFormat.items(actionCount, singular: "action") }
        return CountFormat.items(modules.count, singular: "area")
    }
}

// MARK: - Review edits

/// Re-derives a tile after the user edited its review selection in Checkup.
public enum CheckupReviewAdjustment {
    private static let byteUnits: Set<String> = ["bytes", "KB", "MB", "GB", "TB", "PB"]

    /// True when `headline` is a `ByteFormat` size ("4.2 GB", "512 bytes", "Zero KB").
    public static func isByteHeadline(_ headline: String) -> Bool {
        let trimmed = headline.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.lastIndex(of: " ") else { return false }
        let unit = String(trimmed[trimmed.index(after: space)...])
        let value = String(trimmed[..<space])
        guard byteUnits.contains(unit) else { return false }
        return value == "Zero" || Double(value) != nil
    }

    /// The tile as it should read after the review selection changed.
    ///
    /// * Size tiles show the newly selected size (or the total found when nothing is
    ///   selected any more) and reclaim exactly the selected bytes.
    /// * Count tiles keep their headline; the action count follows the selection.
    /// * An informational tile becomes "attention" once something is selected.
    public static func adjusted(_ tile: CheckupTile, review: [ScanGroup]) -> CheckupTile {
        guard tile.status != .unavailable, tile.status != .clear else { return tile }
        var result = tile
        let selectedBytes = review.selectedSize
        let selectedCount = review.selectedItems.count
        let sizeBased = isByteHeadline(tile.headline)
        if sizeBased {
            result.headline = ByteFormat.string(selectedCount > 0 ? selectedBytes : review.totalSize)
        }
        if sizeBased || tile.reclaimableBytes > 0 {
            result.reclaimableBytes = selectedBytes
        }
        result.actionCount = selectedCount
        if tile.status == .info && selectedCount > 0 {
            result.status = .attention
        }
        result.isSelected = selectedCount > 0
        return result
    }
}
