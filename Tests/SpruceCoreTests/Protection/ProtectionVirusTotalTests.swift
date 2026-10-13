import Foundation
import XCTest
@testable import SpruceCore

/// Answers shaped like VirusTotal's API v3 file reports and errors (values made up).
enum VirusTotalFixture {
    static let hash = String(repeating: "0123456789abcdef", count: 4)

    static let malicious = """
    {
      "data": {
        "attributes": {
          "type_description": "Mach-O",
          "names": ["Player", "Player.app"],
          "last_modification_date": 1760000000,
          "type_tag": "macho",
          "reputation": -24,
          "total_votes": {"harmless": 0, "malicious": 3},
          "popular_threat_classification": {
            "suggested_threat_label": "trojan.adload/macos",
            "popular_threat_category": [{"count": 31, "value": "trojan"}, {"count": 6, "value": "adware"}],
            "popular_threat_name": [{"count": 18, "value": "adload"}]
          },
          "meaningful_name": "Player",
          "sha256": "\(hash)",
          "md5": "00000000000000000000000000000000",
          "size": 482112,
          "last_analysis_date": 1759900000,
          "last_analysis_stats": {
            "malicious": 45, "suspicious": 0, "undetected": 21, "harmless": 0, "timeout": 1,
            "confirmed-timeout": 0, "failure": 2, "type-unsupported": 7
          },
          "last_analysis_results": {
            "ExampleAV": {"method": "blacklist", "engine_name": "ExampleAV", "category": "malicious", "result": "OSX.Adload"}
          }
        },
        "type": "file",
        "id": "\(hash)",
        "links": {"self": "https://www.virustotal.com/api/v3/files/\(hash)"}
      }
    }
    """

    static let clean = """
    {"data": {"type": "file", "id": "\(hash)", "attributes": {
      "meaningful_name": "Notes Helper", "last_analysis_date": 1759000000, "reputation": 0,
      "last_analysis_stats": {"malicious": 0, "suspicious": 0, "undetected": 58, "harmless": 0, "timeout": 0,
                              "confirmed-timeout": 0, "failure": 0, "type-unsupported": 14}}}}
    """

    static let notFound = """
    {"error": {"code": "NotFoundError", "message": "File \\"\(hash)\\" not found"}}
    """

    static let quota = """
    {"error": {"code": "QuotaExceededError", "message": "Quota exceeded"}}
    """

    static let wrongKey = """
    {"error": {"code": "WrongCredentialsError", "message": "Wrong API key"}}
    """

    static let forbidden = """
    {"error": {"code": "ForbiddenError", "message": "You are not allowed to perform the requested operation"}}
    """
}

final class ProtectionVirusTotalTests: XCTestCase {
    let sha256 = VirusTotalFixture.hash

    func parse(_ status: Int, _ body: String) -> VirusTotalLookupResult {
        VirusTotalAPI.parse(statusCode: status, body: Data(body.utf8), sha256: sha256)
    }

    func testMaliciousReportIsFlagged() throws {
        guard case .found(let report) = parse(200, VirusTotalFixture.malicious) else {
            return XCTFail("Expected a report")
        }
        XCTAssertEqual(report.sha256, sha256)
        XCTAssertEqual(report.stats.malicious, 45)
        XCTAssertEqual(report.stats.typeUnsupported, 7)
        XCTAssertEqual(report.stats.confirmedTimeout, 0)
        XCTAssertEqual(report.stats.engines, 66)
        XCTAssertEqual(report.threatLabel, "trojan.adload/macos")
        XCTAssertEqual(report.meaningfulName, "Player")
        XCTAssertEqual(report.typeDescription, "Mach-O")
        XCTAssertEqual(report.reputation, -24)
        XCTAssertEqual(report.lastAnalysisDate, Date(timeIntervalSince1970: 1_759_900_000))

        let checked = Date(timeIntervalSince1970: 1_760_000_000)
        let verdict = try XCTUnwrap(parse(200, VirusTotalFixture.malicious).verdict(checked: checked, sha256: sha256))
        XCTAssertEqual(verdict.level, .flagged)
        XCTAssertEqual(verdict.title, "Flagged by 45 of 66 engines")
        XCTAssertEqual(verdict.detail, "45 of 66 security engines on VirusTotal flag this file as malicious. Most call it trojan.adload/macos.")
        XCTAssertEqual(verdict.reason, "VirusTotal: flagged by 45 of 66 engines")
        XCTAssertEqual(verdict.link?.absoluteString, "https://www.virustotal.com/gui/file/\(sha256)")
        XCTAssertEqual(verdict.checked, checked)
    }

    func testCleanReportAndOtherLevels() throws {
        let clean = try XCTUnwrap(parse(200, VirusTotalFixture.clean).verdict(sha256: sha256))
        XCTAssertEqual(clean.level, .clean)
        XCTAssertEqual(clean.title, "No engine flags this")
        XCTAssertEqual(clean.detail, "None of the 58 security engines on VirusTotal flag this file.")
        XCTAssertEqual(clean.fileName, "Notes Helper")
        XCTAssertNil(clean.threatLabel)

        func verdict(_ stats: VirusTotalAnalysisStats) -> VirusTotalVerdict {
            VirusTotalVerdict(report: VirusTotalFileReport(sha256: sha256, stats: stats))
        }
        let two = verdict(VirusTotalAnalysisStats(malicious: 2, undetected: 60))
        XCTAssertEqual(two.level, .someFlags)
        XCTAssertEqual(two.title, "Some engines flag this")
        XCTAssertEqual(two.detail, "2 of 62 engines call it malicious. A few detections can be false alarms.")
        let suspicious = verdict(VirusTotalAnalysisStats(suspicious: 1, undetected: 60))
        XCTAssertEqual(suspicious.level, .someFlags)
        XCTAssertEqual(suspicious.detail, "1 engine calls it suspicious. A few detections can be false alarms.")
        XCTAssertEqual(verdict(VirusTotalAnalysisStats(malicious: 3, undetected: 1)).level, .flagged)
        let pending = verdict(VirusTotalAnalysisStats(typeUnsupported: 10))
        XCTAssertEqual(pending.level, .unknown)
        XCTAssertEqual(pending.title, "No results yet")

        let unknown = try XCTUnwrap(parse(404, VirusTotalFixture.notFound).verdict(sha256: sha256.uppercased()))
        XCTAssertEqual(unknown.level, .unknown)
        XCTAssertFalse(unknown.isKnown)
        XCTAssertEqual(unknown.sha256, sha256)
        XCTAssertEqual(unknown.title, "Not known to VirusTotal")
        XCTAssertEqual(unknown.reason, "VirusTotal: not known to VirusTotal")
    }

    func testErrorsAreReadable() {
        XCTAssertEqual(parse(404, VirusTotalFixture.notFound), .notFound)
        XCTAssertEqual(parse(429, VirusTotalFixture.quota), .rateLimited)
        XCTAssertEqual(parse(401, VirusTotalFixture.wrongKey), .invalidKey)
        XCTAssertEqual(parse(403, VirusTotalFixture.forbidden), .invalidKey)
        XCTAssertNil(parse(429, VirusTotalFixture.quota).verdict(sha256: sha256))
        XCTAssertNotNil(VirusTotalLookupResult.invalidKey.errorMessage)
        XCTAssertNil(VirusTotalLookupResult.notFound.errorMessage)
        if case .failed(let message) = parse(503, "<html>busy</html>") {
            XCTAssertTrue(message.contains("isn't answering"))
        } else {
            XCTFail("Expected a failure")
        }
        if case .failed(let message) = parse(409, #"{"error": {"code": "AlreadyExistsError"}}"#) {
            XCTAssertTrue(message.contains("AlreadyExistsError"))
        } else {
            XCTFail("Expected a failure")
        }
        if case .failed = parse(200, "not json") {} else { XCTFail("Garbage isn't a report") }
        if case .failed = parse(200, #"{"error": null}"#) {} else { XCTFail("No data isn't a report") }
        let other = String(repeating: "f", count: 64)
        if case .failed(let message) = parse(200, VirusTotalFixture.clean.replacingOccurrences(of: sha256, with: other)) {
            XCTAssertTrue(message.contains("different file"))
        } else {
            XCTFail("A report about another file is refused")
        }
        // Odd field types don't hide the verdict.
        let odd = #"{"data": {"id": "\#(sha256)", "attributes": {"meaningful_name": 5, "reputation": "bad", "#
            + #""last_analysis_date": 1759000000.5, "last_analysis_stats": {"malicious": 4, "undetected": "x"}}}}"#
        guard case .found(let report) = parse(200, odd) else { return XCTFail("Expected a report") }
        XCTAssertEqual(report.stats.malicious, 4)
        XCTAssertEqual(report.stats.undetected, 0)
        XCTAssertNil(report.meaningfulName)
        XCTAssertNil(report.reputation)
        XCTAssertEqual(report.lastAnalysisDate, Date(timeIntervalSince1970: 1_759_000_000))
    }

    func testAddresses() {
        XCTAssertEqual(VirusTotalAPI.fileReportURL(sha256: sha256.uppercased())?.absoluteString,
                       "https://www.virustotal.com/api/v3/files/\(sha256)")
        XCTAssertEqual(VirusTotalAPI.guiURL(sha256: " \(sha256)\n")?.absoluteString, "https://www.virustotal.com/gui/file/\(sha256)")
        XCTAssertNil(VirusTotalAPI.fileReportURL(sha256: "abc"))
        XCTAssertNil(VirusTotalAPI.guiURL(sha256: "../../etc/passwd" + String(repeating: "a", count: 48)))
        XCTAssertEqual(VirusTotalAPI.keyHeader, "x-apikey")
        XCTAssertEqual(VirusTotalAPI.normalizedKey("  testkeytestkeytestkey \n"), "testkeytestkeytestkey")
        XCTAssertNil(VirusTotalAPI.normalizedKey("test key"))
        XCTAssertNil(VirusTotalAPI.normalizedKey("short"))
        XCTAssertNil(VirusTotalAPI.normalizedKey("testkeytestkey\u{0}testkey"))
    }

    func testRateLimitAllowsFourAMinuteAndFiveHundredADay() {
        let limit = VirusTotalRateLimit.publicAPI
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(limit.decision(history: [], now: now), .allowed)
        let three = [now.addingTimeInterval(-50), now.addingTimeInterval(-20), now.addingTimeInterval(-5)]
        XCTAssertEqual(limit.decision(history: three, now: now), .allowed)
        let four = three + [now.addingTimeInterval(-1)]
        XCTAssertEqual(limit.decision(history: Array(four.reversed()), now: now), .wait(until: now.addingTimeInterval(10)))
        XCTAssertEqual(limit.decision(history: four, now: now.addingTimeInterval(10)), .allowed)
        // Lookups older than a minute don't count against the minute.
        XCTAssertEqual(limit.decision(history: four.map { $0.addingTimeInterval(-120) }, now: now), .allowed)

        let day = (0..<500).map { now.addingTimeInterval(-86_000 + Double($0) * 100) }
        let decision = limit.decision(history: day, now: now)
        XCTAssertEqual(decision, .dailyLimitReached(until: day[0].addingTimeInterval(86_400)))
        XCTAssertEqual(decision.nextAttempt, now.addingTimeInterval(400))
        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(limit.remainingToday(history: day, now: now), 0)
        XCTAssertEqual(limit.remainingToday(history: Array(day.prefix(20)), now: now), 480)
        XCTAssertEqual(limit.decision(history: day, now: now.addingTimeInterval(401)), .allowed)

        // The clock was set back: future times count as now and can't block for long.
        let future = Array(repeating: now.addingTimeInterval(3_600), count: 4)
        XCTAssertEqual(limit.decision(history: future, now: now), .wait(until: now.addingTimeInterval(60)))
        XCTAssertEqual(limit.pruned(future + [now.addingTimeInterval(-90_000)], now: now), Array(repeating: now, count: 4))

        // A 429 asks for a pause.
        XCTAssertEqual(limit.decision(history: [], now: now, blockedUntil: now.addingTimeInterval(30)),
                       .wait(until: now.addingTimeInterval(30)))
        XCTAssertEqual(limit.decision(history: [], now: now, blockedUntil: now.addingTimeInterval(-1)), .allowed)
        XCTAssertEqual(limit.decision(history: four, now: now, blockedUntil: now.addingTimeInterval(30)),
                       .wait(until: now.addingTimeInterval(30)))
    }

    func testFindingsKeepTheVerdict() throws {
        var finding = ProtectionThreatFinding(id: "/Users/me/x", name: "x", category: .suspicious, severity: .medium,
                                              evidence: .heuristic, reasons: ["Unsigned program in a hidden folder"],
                                              kind: .executable, path: "/Users/me/x", programPath: "/Users/me/x")
        let checked = Date(timeIntervalSince1970: 1_760_000_000)
        let clean = try XCTUnwrap(parse(200, VirusTotalFixture.clean).verdict(checked: checked, sha256: sha256))
        finding.applyVirusTotal(clean)
        XCTAssertEqual(finding.reasons, ["Unsigned program in a hidden folder", "VirusTotal: no engine flags this"])
        XCTAssertEqual(finding.severity, .medium)
        XCTAssertEqual(finding.sha256, sha256)

        let flagged = try XCTUnwrap(parse(200, VirusTotalFixture.malicious).verdict(checked: checked, sha256: sha256))
        finding.applyVirusTotal(flagged)
        XCTAssertEqual(finding.reasons, ["Unsigned program in a hidden folder", "VirusTotal: flagged by 45 of 66 engines"])
        XCTAssertEqual(finding.severity, .high)
        XCTAssertEqual(finding.evidence, .heuristic, "Evidence and pre-selection stay")
        XCTAssertFalse(finding.isRecommendedForRemoval)

        let item = finding.scanItem
        XCTAssertEqual(item.metadata[ProtectionMetaKey.program], "/Users/me/x")
        let decoded = try XCTUnwrap(VirusTotalVerdict(metadataValue: item.metadata[ProtectionMetaKey.virusTotal]))
        XCTAssertEqual(decoded, flagged)
        XCTAssertNil(VirusTotalVerdict(metadataValue: "{"))
        XCTAssertNil(VirusTotalVerdict(metadataValue: nil))

        XCTAssertTrue(flagged.isFresh(now: checked.addingTimeInterval(86_400)))
        XCTAssertFalse(flagged.isFresh(now: checked.addingTimeInterval(8 * 86_400)))
        XCTAssertFalse(flagged.isFresh(now: checked.addingTimeInterval(-60)))
    }

    func testFindingsDecodeWithoutTheNewFields() throws {
        let json = """
        {"id": "/x", "name": "x", "category": "adware", "severity": 3, "evidence": "knownIndicator",
         "reasons": ["Known"], "kind": "file", "path": "/x", "relatedPaths": [], "score": 0, "size": 12}
        """
        let finding = try JSONDecoder().decode(ProtectionThreatFinding.self, from: Data(json.utf8))
        XCTAssertEqual(finding.category, .adware)
        XCTAssertEqual(finding.severity, .high)
        XCTAssertEqual(finding.ruleHits, [])
        XCTAssertNil(finding.programPath)
        XCTAssertNil(finding.virusTotal)

        var full = finding
        full.ruleHits = [ProtectionRuleHit(source: "Apple XProtect", rule: "XProtect_MACOS_ADLOAD_D", detail: "MACOS.ADLOAD.D")]
        full.virusTotal = VirusTotalVerdict.notFound(sha256: sha256, checked: Date(timeIntervalSince1970: 1_000))
        full.programPath = "/x"
        let data = try JSONEncoder().encode(full)
        XCTAssertEqual(try JSONDecoder().decode(ProtectionThreatFinding.self, from: data), full)
        let future = #"{"id": "/y", "name": "y", "category": "wiper", "evidence": "aiGuess", "kind": "hologram"}"#
        let lenient = try JSONDecoder().decode(ProtectionThreatFinding.self, from: Data(future.utf8))
        XCTAssertEqual(lenient.category, .suspicious)
        XCTAssertEqual(lenient.evidence, .heuristic)
        XCTAssertEqual(lenient.kind, .file)
    }
}
