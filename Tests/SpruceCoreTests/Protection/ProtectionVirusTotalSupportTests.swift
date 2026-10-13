import Foundation
import XCTest
@testable import SpruceCore

final class ProtectionVirusTotalSupportTests: XCTestCase {
    /// Obviously made-up hashes (tests never use real samples).
    static let hashA = String(repeating: "a1", count: 32)
    static let hashB = String(repeating: "b2", count: 32)
    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func verdict(_ hash: String = hashA, malicious: Int = 0, engines: Int = 70, known: Bool = true,
                         checked: Date = now) -> VirusTotalVerdict {
        guard known else { return .notFound(sha256: hash, checked: checked) }
        let stats = VirusTotalAnalysisStats(malicious: malicious, undetected: engines - malicious)
        return VirusTotalVerdict(report: VirusTotalFileReport(sha256: hash, stats: stats), checked: checked)
    }

    private func finding(_ id: String, evidence: ThreatEvidence, severity: ThreatSeverity = .medium, score: Int = 50,
                         sha256: String? = nil, program: String? = nil, virusTotal: VirusTotalVerdict? = nil) -> ProtectionThreatFinding {
        ProtectionThreatFinding(id: id, name: (id as NSString).lastPathComponent, category: .suspicious, severity: severity,
                                evidence: evidence, reasons: ["Unsigned program in a hidden folder"], kind: .file, path: id,
                                sha256: sha256, score: score, programPath: program, virusTotal: virusTotal)
    }

    // MARK: Cache

    func testCacheKeepsKnownAnswersForAWeekAndUnknownOnesForADay() throws {
        var cache = VirusTotalVerdictCache()
        cache.store(verdict(Self.hashA, malicious: 5), now: Self.now)
        cache.store(verdict(Self.hashB, known: false), now: Self.now)
        XCTAssertEqual(cache.fresh(for: Self.hashA.uppercased(), now: Self.now)?.malicious, 5)
        XCTAssertNotNil(cache.fresh(for: Self.hashB, now: Self.now.addingTimeInterval(3_600)))
        XCTAssertNil(cache.fresh(for: Self.hashB, now: Self.now.addingTimeInterval(86_400 + 1)))
        XCTAssertNotNil(cache.fresh(for: Self.hashA, now: Self.now.addingTimeInterval(6 * 86_400)))
        XCTAssertNil(cache.fresh(for: Self.hashA, now: Self.now.addingTimeInterval(7 * 86_400 + 1)))
        XCTAssertNil(cache.fresh(for: "not a hash", now: Self.now))

        cache.prune(now: Self.now.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(Array(cache.verdicts.keys), [Self.hashA])

        let decoded = try JSONDecoder().decode(VirusTotalVerdictCache.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(decoded, cache)
        XCTAssertEqual(try JSONDecoder().decode(VirusTotalVerdictCache.self, from: Data(#"{"verdicts": 3}"#.utf8)),
                       VirusTotalVerdictCache())
    }

    func testCacheDropsTheOldestAnswersBeyondItsLimit() {
        var cache = VirusTotalVerdictCache()
        for index in 0..<(VirusTotalVerdictCache.maxEntries + 3) {
            let hash = String(format: "%064x", index)
            cache.verdicts[hash] = verdict(hash, checked: Self.now.addingTimeInterval(Double(index)))
        }
        cache.prune(now: Self.now.addingTimeInterval(100_000))
        XCTAssertEqual(cache.verdicts.count, VirusTotalVerdictCache.maxEntries)
        XCTAssertNil(cache.verdicts[String(format: "%064x", 0)], "The oldest answer goes first")
    }

    // MARK: Quota

    func testQuotaFollowsThePublicLimitsAndBacksOffAfterRateLimits() throws {
        var quota = VirusTotalQuota()
        for second in 0..<4 { quota.record(now: Self.now.addingTimeInterval(Double(second))) }
        XCTAssertEqual(quota.remainingToday(now: Self.now.addingTimeInterval(5)), 496)
        XCTAssertEqual(quota.decision(now: Self.now.addingTimeInterval(5)), .wait(until: Self.now.addingTimeInterval(60)))
        XCTAssertEqual(quota.decision(now: Self.now.addingTimeInterval(61)), .allowed)

        quota.pause(now: Self.now)
        XCTAssertEqual(quota.blockedUntil, Self.now.addingTimeInterval(60))
        quota.pause(now: Self.now)
        XCTAssertEqual(quota.blockedUntil, Self.now.addingTimeInterval(120))
        for _ in 0..<20 { quota.pause(now: Self.now) }
        XCTAssertEqual(quota.blockedUntil, Self.now.addingTimeInterval(3_600), "Never more than an hour")
        XCTAssertEqual(quota.decision(now: Self.now.addingTimeInterval(100)), .wait(until: Self.now.addingTimeInterval(3_600)))

        let decoded = try JSONDecoder().decode(VirusTotalQuota.self, from: JSONEncoder().encode(quota))
        XCTAssertEqual(decoded, quota)
        quota.recordAnswer()
        XCTAssertNil(quota.blockedUntil)
        XCTAssertEqual(quota.consecutiveRateLimits, 0)
        XCTAssertEqual(try JSONDecoder().decode(VirusTotalQuota.self, from: Data("{}".utf8)), VirusTotalQuota())
    }

    // MARK: Candidates

    func testAutomaticLookupsCoverHeuristicAndRuleFindingsWithAFile() {
        let fresh = verdict(Self.hashB, checked: Self.now.addingTimeInterval(-3_600))
        let stale = verdict(Self.hashB, checked: Self.now.addingTimeInterval(-30 * 86_400))
        let findings = [
            finding("/known", evidence: .knownIndicator, program: "/known"),
            finding("/hash", evidence: .knownHash, sha256: Self.hashA),
            finding("/folder", evidence: .heuristic),
            finding("/heuristic", evidence: .heuristic, severity: .high, program: "/heuristic"),
            finding("/rule", evidence: .ruleMatch, severity: .medium, sha256: Self.hashA),
            finding("/rule-copy", evidence: .ruleMatch, severity: .low, sha256: Self.hashA.uppercased()),
            finding("/checked", evidence: .heuristic, program: "/checked", virusTotal: fresh),
            finding("/stale", evidence: .heuristic, severity: .low, program: "/stale", virusTotal: stale),
        ]
        let picked = VirusTotalCandidates.automatic(findings, now: Self.now)
        XCTAssertEqual(picked.map(\.id), ["/rule", "/heuristic", "/stale"],
                       "Rule matches first, one lookup per file, no catalog matches, nothing checked recently")
        XCTAssertEqual(VirusTotalCandidates.automatic(findings, now: Self.now, limit: 1).map(\.id), ["/rule"])
        XCTAssertTrue(VirusTotalCandidates.automatic(findings, now: Self.now, limit: 0).isEmpty)
        XCTAssertEqual(VirusTotalAPI.normalizedSHA256(VirusTotalCandidates.keyCheckSHA256), VirusTotalCandidates.keyCheckSHA256)
    }

    // MARK: Outcomes

    func testOutcomesFromAnswersAndTheirMessages() {
        let found = VirusTotalLookupOutcome(.found(VirusTotalFileReport(sha256: Self.hashA, stats: VirusTotalAnalysisStats(malicious: 4, undetected: 60))),
                                            sha256: Self.hashA, checked: Self.now)
        XCTAssertEqual(found.verdict?.level, .flagged)
        XCTAssertNil(found.message)
        let missing = VirusTotalLookupOutcome(.notFound, sha256: Self.hashA, checked: Self.now)
        XCTAssertEqual(missing.verdict?.isKnown, false)
        XCTAssertEqual(VirusTotalLookupOutcome(.invalidKey, sha256: Self.hashA), .invalidKey)
        XCTAssertEqual(VirusTotalLookupOutcome(.rateLimited, sha256: Self.hashA), .rateLimited(until: nil))
        XCTAssertEqual(VirusTotalLookupOutcome(.failed("Offline."), sha256: Self.hashA), .failed("Offline."))

        let others: [VirusTotalLookupOutcome] = [.noKey, .invalidKey, .rateLimited(until: nil), .rateLimited(until: Self.now),
                                                 .dailyLimitReached(until: Self.now), .noFile("No file."), .failed("Offline.")]
        for outcome in others {
            XCTAssertNil(outcome.verdict)
            XCTAssertFalse(outcome.message?.isEmpty ?? true, "\(outcome)")
        }

        XCTAssertTrue(VirusTotalKeyCheck.valid.isUsable)
        XCTAssertTrue(VirusTotalKeyCheck.quotaReached.isUsable)
        XCTAssertFalse(VirusTotalKeyCheck.invalid.isUsable)
        XCTAssertFalse(VirusTotalKeyCheck.malformed.isUsable)
        XCTAssertFalse(VirusTotalKeyCheck.failed("Offline.").isUsable)
        XCTAssertTrue(VirusTotalKeyCheck.notChecked.isUsable)
        XCTAssertFalse(VirusTotalKeyCheck.notChecked.message.isEmpty)
        XCTAssertEqual(VirusTotalKeyCheck.failed("Offline.").message, "Offline.")
    }

    // MARK: Review rows

    func testAnswersAreRecordedOnReviewRows() {
        var item = finding("/Users/tester/.hidden/agent", evidence: .heuristic, severity: .medium,
                           program: "/Users/tester/.hidden/agent").scanItem
        XCTAssertNil(item.virusTotalVerdict)
        XCTAssertNil(item.protectionSHA256)
        XCTAssertEqual(item.protectionLookupPath, "/Users/tester/.hidden/agent")

        item.applyVirusTotal(verdict(Self.hashA, malicious: 0))
        XCTAssertEqual(item.virusTotalVerdict?.level, .clean)
        XCTAssertEqual(item.protectionSHA256, Self.hashA)
        XCTAssertEqual(item.metadata[ProtectionMetaKey.reasons]?.components(separatedBy: "\n"),
                       ["Unsigned program in a hidden folder", "VirusTotal: no engine flags this"])
        XCTAssertEqual(item.metadata[ProtectionMetaKey.severity], String(ThreatSeverity.medium.rawValue))
        XCTAssertFalse(item.isSelected, "Answers never change the selection")

        item.applyVirusTotal(verdict(Self.hashA, malicious: 40))
        XCTAssertEqual(item.metadata[ProtectionMetaKey.reasons]?.components(separatedBy: "\n"),
                       ["Unsigned program in a hidden folder", "VirusTotal: flagged by 40 of 70 engines"])
        XCTAssertEqual(item.metadata[ProtectionMetaKey.severity], String(ThreatSeverity.high.rawValue))
        XCTAssertEqual(item.note, "Unsigned program in a hidden folder")
        XCTAssertFalse(item.isSelected)

        // The finding helper and the row helper agree.
        var copy = finding("/Users/tester/.hidden/agent", evidence: .heuristic, severity: .medium,
                           program: "/Users/tester/.hidden/agent")
        copy.applyVirusTotal(verdict(Self.hashA, malicious: 40))
        XCTAssertEqual(copy.scanItem.metadata[ProtectionMetaKey.reasons], item.metadata[ProtectionMetaKey.reasons])
        XCTAssertEqual(copy.scanItem.metadata[ProtectionMetaKey.severity], item.metadata[ProtectionMetaKey.severity])

        var other = ScanItem(id: "cache", title: "Cache", metadata: ["cleanup.rule": "x"])
        other.applyVirusTotal(verdict())
        XCTAssertTrue(other.metadata[ProtectionMetaKey.virusTotal] == nil, "Only malware rows take answers")
        XCTAssertNil(other.protectionLookupPath)
    }

    func testLookupPathsOfDifferentRows() {
        let plain = finding("/Users/tester/Downloads/tool", evidence: .heuristic).scanItem
        XCTAssertEqual(plain.protectionLookupPath, "/Users/tester/Downloads/tool")
        let cron = ProtectionThreatFinding(id: "cron:1", name: "Cron job", category: .suspicious, severity: .medium,
                                           evidence: .heuristic, reasons: ["Runs a hidden script"], kind: .cronJob, path: nil,
                                           cronLine: "* * * * * /tmp/x").scanItem
        XCTAssertNil(cron.protectionLookupPath)
    }

    func testAnswersAreAppliedAcrossGroupsAndSubgroups() {
        let first = finding("/one", evidence: .heuristic, program: "/one")
        let second = finding("/two", evidence: .ruleMatch, severity: .high, sha256: Self.hashB)
        var groups = ProtectionThreatFinding.scanGroups([first, second])
        groups.append(ScanGroup(id: "outer", title: "Outer",
                                children: [ScanGroup(id: "inner", title: "Inner", items: [finding("/three", evidence: .heuristic).scanItem])]))
        let answers = ["/one": verdict(Self.hashA, malicious: 9), "/three": verdict(Self.hashB, known: false)]
        XCTAssertTrue(groups.applyVirusTotal(answers))
        let items = Dictionary(uniqueKeysWithValues: groups.flatMap(\.allItems).map { ($0.id, $0) })
        XCTAssertEqual(items["/one"]?.virusTotalVerdict?.malicious, 9)
        XCTAssertNil(items["/two"]?.virusTotalVerdict)
        XCTAssertEqual(items["/three"]?.virusTotalVerdict?.isKnown, false)
        XCTAssertFalse(groups.applyVirusTotal(answers), "Applying the same answers again changes nothing")
        XCTAssertFalse(groups.applyVirusTotal([:]))

        // One answer reaches every row of the same file.
        XCTAssertTrue(groups.applyVirusTotal(verdict(Self.hashB, malicious: 12), itemID: nil))
        let updated = Dictionary(uniqueKeysWithValues: groups.flatMap(\.allItems).map { ($0.id, $0) })
        XCTAssertEqual(updated["/two"]?.virusTotalVerdict?.malicious, 12)
        XCTAssertEqual(updated["/three"]?.virusTotalVerdict?.malicious, 12, "Its hash was recorded with the first answer")
        XCTAssertEqual(updated["/one"]?.virusTotalVerdict?.malicious, 9)
        XCTAssertFalse(groups.applyVirusTotal(verdict(String(repeating: "c3", count: 32)), itemID: "/missing"))
    }

    func testAnswersAreRecordedOnReports() {
        var report = ProtectionMalwareReport(depth: .quick, findings: [
            finding("/one", evidence: .heuristic, program: "/one"),
            finding("/two", evidence: .ruleMatch, sha256: Self.hashB),
            finding("/three", evidence: .ruleMatch, sha256: Self.hashB.uppercased()),
        ], itemsScanned: 3, duration: 1)
        XCTAssertTrue(report.applyVirusTotal(verdict(Self.hashA, malicious: 3), itemID: "/one"))
        XCTAssertEqual(report.findings[0].virusTotal?.level, .flagged)
        XCTAssertEqual(report.findings[0].sha256, Self.hashA, "The hash is kept for the next lookup")
        XCTAssertEqual(report.findings[0].severity, .high)
        XCTAssertTrue(report.applyVirusTotal(verdict(Self.hashB, known: false)))
        XCTAssertEqual(report.findings[1].virusTotal?.isKnown, false)
        XCTAssertEqual(report.findings[2].virusTotal?.isKnown, false)
        XCTAssertFalse(report.applyVirusTotal(verdict(String(repeating: "c3", count: 32))))
        XCTAssertEqual(report.threatCount, 3)
    }
}
