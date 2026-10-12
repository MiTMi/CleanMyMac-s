import Foundation

// MARK: - Run order

/// Order in which Checkup runs the selected areas.
///
/// Protection first (remove threats before anything else touches their files), then
/// Cleanup and Clutter, then maintenance, and app updates last (slowest, and app
/// relaunches should not disturb cleaning).
public enum CheckupRunOrder {
    public static let order: [ModuleID] = [.protection, .cleanup, .clutter, .performance, .applications]

    /// The selected modules in run order. Modules not in `order` run last, in the
    /// order given by `ModuleID.checkupContributors`.
    public static func plan(for selection: Set<ModuleID>) -> [ModuleID] {
        let known = order.filter { selection.contains($0) }
        let others = ModuleID.checkupContributors.filter { selection.contains($0) && !order.contains($0) }
        let rest = selection.subtracting(known).subtracting(others).sorted { $0.rawValue < $1.rawValue }
        return known + others + rest
    }
}

// MARK: - Run state

/// State of one area while Checkup runs.
public enum CheckupRunState: Equatable, Sendable {
    case waiting
    case running
    case done(RunOutcome)
    case failed(String)
    /// Not run because the user stopped the run.
    case skipped

    public var isFinished: Bool {
        switch self {
        case .done, .failed, .skipped: return true
        case .waiting, .running: return false
        }
    }
}

public struct CheckupRunStep: Identifiable, Equatable, Sendable {
    public var module: ModuleID
    public var id: ModuleID { module }
    public var state: CheckupRunState
    public var progress: ScanProgress

    public init(module: ModuleID, state: CheckupRunState = .waiting, progress: ScanProgress = ScanProgress(message: "")) {
        self.module = module
        self.state = state
        self.progress = progress
    }

    public var outcome: RunOutcome? {
        if case .done(let outcome) = state { return outcome }
        return nil
    }
}

/// Value-type model of a Checkup run: the selected areas, run one after another.
public struct CheckupRunBoard: Equatable, Sendable {
    public private(set) var steps: [CheckupRunStep]
    public private(set) var startedAt: Date
    public private(set) var finishedAt: Date?

    public init(plan: [ModuleID], startedAt: Date = Date()) {
        steps = plan.map { CheckupRunStep(module: $0) }
        self.startedAt = startedAt
    }

    public var modules: [ModuleID] { steps.map(\.module) }

    public func step(_ module: ModuleID) -> CheckupRunStep? { steps.first { $0.module == module } }

    /// The area currently running, if any.
    public var current: CheckupRunStep? { steps.first { $0.state == .running } }

    /// The next area waiting to run.
    public var next: ModuleID? { steps.first { $0.state == .waiting }?.module }

    public var isFinished: Bool { steps.allSatisfy { $0.state.isFinished } }

    /// 0...1: finished areas count fully, the running area by its reported fraction.
    public var overallFraction: Double {
        guard !steps.isEmpty else { return 1 }
        let sum = steps.reduce(0.0) { total, step in
            switch step.state {
            case .done, .failed, .skipped: return total + 1
            case .running: return total + min(step.progress.fraction ?? 0, 0.99)
            case .waiting: return total
            }
        }
        return min(max(sum / Double(steps.count), 0), 1)
    }

    /// Outcomes of the areas that completed, in run order.
    public var outcomes: [RunOutcome] { steps.compactMap(\.outcome) }

    public var freedBytes: Int64 { outcomes.reduce(0) { $0 + max(0, $1.freedBytes) } }

    public var processedCount: Int { outcomes.reduce(0) { $0 + max(0, $1.processedCount) } }

    /// Item failures from completed areas plus one failure per area that threw.
    public var failures: [ItemFailure] {
        steps.flatMap { step -> [ItemFailure] in
            switch step.state {
            case .done(let outcome): return outcome.failures
            case .failed(let reason):
                return [ItemFailure(itemID: "checkup.\(step.module.rawValue)", title: step.module.title, reason: reason)]
            default: return []
            }
        }
    }

    public var skippedModules: [ModuleID] { steps.filter { $0.state == .skipped }.map(\.module) }

    /// Everything that happened, as one outcome attributed to Checkup.
    public var mergedOutcome: RunOutcome {
        RunOutcome(module: .checkup, date: finishedAt ?? startedAt, freedBytes: freedBytes,
                   processedCount: processedCount, removedItemIDs: outcomes.flatMap(\.removedItemIDs),
                   failures: failures, summary: CheckupCopy.runSummary(self))
    }

    // MARK: Mutations

    public mutating func start(_ module: ModuleID) {
        mutate(module) { step in
            guard step.state == .waiting else { return }
            step.state = .running
            step.progress = ScanProgress(fraction: 0, message: "")
        }
    }

    public mutating func update(_ module: ModuleID, progress: ScanProgress) {
        mutate(module) { step in
            guard step.state == .running else { return }
            step.progress = progress
        }
    }

    public mutating func complete(_ module: ModuleID, outcome: RunOutcome, at date: Date = Date()) {
        mutate(module) { step in
            guard step.state == .running || step.state == .waiting else { return }
            var stored = outcome
            stored.module = module
            step.state = .done(stored)
            step.progress = ScanProgress(fraction: 1, message: "")
        }
        finishIfDone(at: date)
    }

    public mutating func fail(_ module: ModuleID, reason: String, at date: Date = Date()) {
        mutate(module) { step in
            guard step.state == .running || step.state == .waiting else { return }
            step.state = .failed(reason)
        }
        finishIfDone(at: date)
    }

    /// Marks every waiting area as skipped (the user pressed Stop).
    public mutating func skipRemaining(at date: Date = Date()) {
        for index in steps.indices where steps[index].state == .waiting {
            steps[index].state = .skipped
        }
        finishIfDone(at: date)
    }

    private mutating func finishIfDone(at date: Date) {
        if isFinished && finishedAt == nil { finishedAt = date }
    }

    private mutating func mutate(_ module: ModuleID, _ body: (inout CheckupRunStep) -> Void) {
        guard let index = steps.firstIndex(where: { $0.module == module }) else { return }
        body(&steps[index])
    }
}
