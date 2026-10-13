import Foundation
import Observation
import SpruceCore

/// What the Protection screens and Settings show about the detection sources beyond the
/// built-in catalog: Apple's XProtect rules, the downloaded threat list and VirusTotal
/// lookups. The engine keeps it current (`ProtectionEngine.detection`); it changes only on
/// the main thread, so read it from SwiftUI views.
@Observable
public final class ProtectionDetectionState: @unchecked Sendable {
    // MARK: Apple's XProtect rules

    /// Nil until the first `ProtectionEngine.refreshDetectionStatus()`.
    public internal(set) var appleRules: ProtectionAppleRulesStatus?

    // MARK: Threat list

    /// Mirrors `SpruceSettings.threatFeedEnabled`.
    public internal(set) var isThreatListEnabled = true
    /// Version, dates, counts, last problem.
    public internal(set) var threatList = ProtectionThreatFeedStatus()
    /// Downloaded indicators and rules scans use right now (0 while the list is off).
    public internal(set) var threatListIndicatorsInUse = 0
    public internal(set) var threatListRulesInUse = 0
    /// True while the list is being downloaded.
    public internal(set) var isCheckingThreatList = false
    /// The last check's result (Check Now or before a scan); nil before the first one.
    public internal(set) var lastThreatListCheck: ProtectionThreatFeedCheckResult?

    // MARK: VirusTotal

    /// A VirusTotal API key is saved in the Keychain.
    public internal(set) var hasVirusTotalKey = false
    /// Answers by malware row id (`ScanItem.id` = `ProtectionThreatFinding.id`).
    public internal(set) var virusTotalByItemID: [String: VirusTotalVerdict] = [:]
    /// Answers by SHA-256.
    public internal(set) var virusTotalBySHA256: [String: VirusTotalVerdict] = [:]
    /// Rows being looked up (or waiting for a free lookup) right now.
    public internal(set) var virusTotalPending: Set<String> = []
    /// The last problem per row (row id → plain text), cleared when an answer arrives.
    public internal(set) var virusTotalProblems: [String: String] = [:]
    /// A problem that stops lookups altogether (key refused, today's lookups used up);
    /// nil when lookups work.
    public internal(set) var virusTotalNotice: String?
    /// Lookups left today under the public API's limit (500 a day).
    public internal(set) var virusTotalLookupsLeftToday = VirusTotalRateLimit.publicAPI.perDay
    /// Grows with every answer, for views that refresh their rows on change.
    public internal(set) var virusTotalRevision = 0

    public init() {}

    /// The answer for a malware row: recorded on the row, else one that arrived since.
    public func verdict(for item: ScanItem) -> VirusTotalVerdict? {
        if let byID = virusTotalByItemID[item.id] { return byID }
        if let recorded = item.virusTotalVerdict { return recorded }
        if let hash = item.protectionSHA256 { return virusTotalBySHA256[hash] }
        return nil
    }

    public func isLookingUp(_ item: ScanItem) -> Bool {
        virusTotalPending.contains(item.id)
    }

    public func problem(for item: ScanItem) -> String? {
        virusTotalProblems[item.id]
    }
}
