import Foundation

/// Phases of a full Clutter scan, in order (shown as a checklist while scanning).
public enum ClutterScanStage: String, CaseIterable, Sendable, Hashable {
    case indexing
    case largeOld
    case duplicates
    case similarImages
    case downloads

    public var title: String {
        switch self {
        case .indexing: return "Finding files"
        case .largeOld: return ClutterTool.largeOld.title
        case .duplicates: return ClutterTool.duplicates.title
        case .similarImages: return ClutterTool.similarImages.title
        case .downloads: return ClutterTool.downloads.title
        }
    }

    public var symbol: String {
        switch self {
        case .indexing: return "magnifyingglass"
        case .largeOld: return ClutterTool.largeOld.symbol
        case .duplicates: return ClutterTool.duplicates.symbol
        case .similarImages: return ClutterTool.similarImages.symbol
        case .downloads: return ClutterTool.downloads.symbol
        }
    }

    /// Share of the overall progress bar each stage takes.
    var weight: Double {
        switch self {
        case .indexing: return 0.35
        case .largeOld: return 0.05
        case .duplicates: return 0.3
        case .similarImages: return 0.25
        case .downloads: return 0.05
        }
    }
}

/// State of one stage.
public enum ClutterStageState: Sendable, Equatable {
    case waiting
    case running(Double?)
    case done(String)
    case skipped(String)
}

/// Thread-safe tally of a running scan's stages, read by the UI while scanning.
public final class ClutterStageBoard: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [ClutterScanStage: ClutterStageState]
    private let included: [ClutterScanStage]

    public init(stages: [ClutterScanStage] = ClutterScanStage.allCases) {
        included = stages
        states = Dictionary(uniqueKeysWithValues: stages.map { ($0, ClutterStageState.waiting) })
    }

    public var stages: [ClutterScanStage] { included }

    public func set(_ stage: ClutterScanStage, _ state: ClutterStageState) {
        lock.lock()
        defer { lock.unlock() }
        guard states[stage] != nil else { return }
        states[stage] = state
    }

    public func state(of stage: ClutterScanStage) -> ClutterStageState {
        lock.lock()
        defer { lock.unlock() }
        return states[stage] ?? .waiting
    }

    /// Snapshot in display order.
    public var snapshot: [(stage: ClutterScanStage, state: ClutterStageState)] {
        lock.lock()
        defer { lock.unlock() }
        return included.map { ($0, states[$0] ?? .waiting) }
    }

    /// Overall fraction 0…1 from stage weights (running stages count their own fraction,
    /// or half when unknown).
    public var fraction: Double {
        lock.lock()
        defer { lock.unlock() }
        let total = included.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        var done = 0.0
        for stage in included {
            switch states[stage] ?? .waiting {
            case .waiting: break
            case .running(let f): done += stage.weight * min(max(f ?? 0.5, 0), 1)
            case .done, .skipped: done += stage.weight
            }
        }
        return min(1, done / total)
    }
}
