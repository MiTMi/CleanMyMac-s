import Foundation

/// Live progress of one Cleanup section while a scan runs. Drives the scanning
/// checklist ("System Junk · Mail Attachments · Trash Bins" gaining check marks as
/// each finishes).
public struct CleanupSectionProgress: Sendable, Hashable, Identifiable {

    /// What the checklist row shows.
    public enum Status: Sendable, Hashable {
        /// No rule of this section has started yet.
        case waiting
        /// At least one rule is being scanned.
        case running
        /// Finished; bytes found.
        case found(Int64)
        /// Finished without findings.
        case nothingFound
        /// Finished without findings because macOS blocked some locations.
        case unavailable(String)
        /// Every category of the section is excluded in Settings › Scanning.
        case excluded
    }

    public var section: CleanupSection
    public var totalRules: Int
    public var startedRules: Int
    public var finishedRules: Int
    public var bytesFound: Int64
    public var itemsFound: Int
    /// Rules that could not run (missing Full Disk Access or denied by macOS).
    public var unavailableRules: Int
    /// True when at least one unavailable rule needs Full Disk Access.
    public var needsFullDiskAccess: Bool

    public var id: String { section.rawValue }

    public init(section: CleanupSection, totalRules: Int = 0) {
        self.section = section
        self.totalRules = totalRules
        startedRules = 0
        finishedRules = 0
        bytesFound = 0
        itemsFound = 0
        unavailableRules = 0
        needsFullDiskAccess = false
    }

    public var isFinished: Bool { finishedRules >= totalRules }

    public var status: Status {
        if totalRules == 0 { return .excluded }
        if !isFinished { return startedRules > 0 || finishedRules > 0 ? .running : .waiting }
        if bytesFound > 0 { return .found(bytesFound) }
        if unavailableRules > 0 {
            return .unavailable(needsFullDiskAccess ? "Needs Full Disk Access" : "macOS denied access")
        }
        return .nothingFound
    }
}

/// Accumulates per-rule results into per-section progress. Value type; the Mac engine
/// guards it with a lock while rules run concurrently.
public struct CleanupScanTally: Sendable {
    public private(set) var sections: [CleanupSectionProgress]
    private var started: Set<String> = []
    private var finished: Set<String> = []

    /// - Parameters:
    ///   - rules: the rules this scan will run (already filtered by Settings and purpose).
    ///   - sections: the sections the scan covers, shown in display order.
    public init(rules: [CleanupRule], sections: Set<CleanupSection>) {
        self.sections = CleanupSection.allCases.filter { sections.contains($0) }.map { section in
            CleanupSectionProgress(section: section, totalRules: rules.filter { $0.category.section == section }.count)
        }
    }

    /// Marks a rule as in flight.
    public mutating func start(_ rule: CleanupRule) {
        guard started.insert(rule.id).inserted, let i = index(of: rule.category.section) else { return }
        sections[i].startedRules += 1
    }

    /// Records a finished rule (idempotent per rule id).
    public mutating func finish(_ result: CleanupRuleResult) {
        guard finished.insert(result.ruleID).inserted, let i = index(of: result.category.section) else { return }
        sections[i].finishedRules += 1
        sections[i].bytesFound += result.totalBytes
        sections[i].itemsFound += result.items.count
        if let unavailable = result.unavailable {
            sections[i].unavailableRules += 1
            if unavailable.reason == .fullDiskAccess { sections[i].needsFullDiskAccess = true }
        }
    }

    /// Bytes found so far across all sections.
    public var bytesFound: Int64 { sections.reduce(0) { $0 + $1.bytesFound } }

    /// Share of rules finished, or nil when the scan runs no rules.
    public var fraction: Double? {
        let total = sections.reduce(0) { $0 + $1.totalRules }
        guard total > 0 else { return nil }
        return Double(sections.reduce(0) { $0 + $1.finishedRules }) / Double(total)
    }

    public func progress(for section: CleanupSection) -> CleanupSectionProgress? {
        sections.first { $0.section == section }
    }

    private func index(of section: CleanupSection) -> Int? {
        sections.firstIndex { $0.section == section }
    }
}
