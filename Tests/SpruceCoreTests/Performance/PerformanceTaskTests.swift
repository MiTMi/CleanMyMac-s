import XCTest
@testable import SpruceCore

final class PerformanceTaskCatalogTests: XCTestCase {
    /// Raw values of `PrivilegedRunner.PrivilegedCommand` (SpruceMac). The catalog may only use these.
    private let privilegedCommands: Set<String> = [
        "flushDNS", "purgeMemory", "reindexSpotlight", "runPeriodicScripts", "thinTimeMachineSnapshots",
        "rebuildLaunchServices", "clearFontCaches", "repairHomePermissions", "emptySystemTrashes",
    ]

    func testCatalogCoversEveryTaskOnce() {
        let ids = PerformanceTaskCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids), Set(PerformanceTaskID.allCases))
        XCTAssertEqual(ids.count, PerformanceTaskID.allCases.count)
        for id in PerformanceTaskID.allCases {
            XCTAssertEqual(PerformanceTaskCatalog.definition(id).id, id)
        }
    }

    func testPrivilegedStepsUseKnownCommandsOnly() {
        for def in PerformanceTaskCatalog.all {
            for raw in def.privilegedCommands {
                XCTAssertTrue(privilegedCommands.contains(raw), "\(def.id) uses unknown command \(raw)")
            }
        }
        XCTAssertFalse(PerformanceTaskCatalog.all.flatMap(\.privilegedCommands).contains("rebuildLaunchServices"),
                       "lsregister -kill was removed by Apple; Launch Services is rebuilt per user")
    }

    func testCopyIsCompleteAndOriginal() {
        for def in PerformanceTaskCatalog.all {
            XCTAssertFalse(def.title.isEmpty)
            XCTAssertGreaterThan(def.summary.count, 40, "\(def.id) needs a real description")
            XCTAssertFalse(def.whenToRun.isEmpty)
            XCTAssertFalse(def.requiredExecutables.isEmpty)
            XCTAssertFalse(def.title.contains("CleanMyMac"))
            XCTAssertFalse(def.summary.contains("MacPaw"))
        }
    }

    func testMaintenanceScriptsHiddenWithoutPeriodic() {
        let withoutPeriodic = PerformanceTaskCatalog.available { $0 != "/usr/sbin/periodic" }
        XCTAssertFalse(withoutPeriodic.contains { $0.id == .maintenanceScripts })
        XCTAssertTrue(withoutPeriodic.contains { $0.id == .flushDNS })
        let everything = PerformanceTaskCatalog.available { _ in true }
        XCTAssertTrue(everything.contains { $0.id == .maintenanceScripts })
    }

    func testOrderingAndPrivilegedBatch() {
        let ordered = PerformanceTaskCatalog.ordered([.reindexSpotlight, .freeRAM, .speedUpMail, .flushDNS, .freeRAM])
        XCTAssertEqual(ordered, [.speedUpMail, .flushDNS, .freeRAM, .reindexSpotlight])
        let batch = PerformanceTaskCatalog.privilegedBatch(for: [.freeRAM, .flushDNS, .speedUpMail, .clearFontCaches, .flushDNS])
        XCTAssertEqual(batch, ["clearFontCaches", "flushDNS", "purgeMemory"])
    }

    func testRequirementsDescribeNeeds() {
        let mail = PerformanceTaskCatalog.definition(.speedUpMail)
        XCTAssertFalse(mail.needsAdmin)
        XCTAssertTrue(mail.requirements.contains("Mail to be closed"))
        XCTAssertTrue(mail.requirements.contains("Full Disk Access"))
        let dns = PerformanceTaskCatalog.definition(.flushDNS)
        XCTAssertTrue(dns.needsAdmin)
        XCTAssertEqual(dns.requirements, ["Your administrator password"])
        let fonts = PerformanceTaskCatalog.definition(.clearFontCaches)
        XCTAssertEqual(fonts.userSteps.count, 1)
        XCTAssertEqual(fonts.privilegedCommands, ["clearFontCaches"])
    }

    func testItemIDRoundTrip() {
        for id in PerformanceTaskID.allCases {
            XCTAssertEqual(PerformanceTaskID(itemID: id.itemID), id)
        }
        XCTAssertNil(PerformanceTaskID(itemID: "performance.task.nope"))
        XCTAssertNil(PerformanceTaskID(itemID: "cleanup.x"))
    }
}

final class PerformanceRecommenderTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func def(_ id: PerformanceTaskID) -> PerformanceTaskDefinition { PerformanceTaskCatalog.definition(id) }
    func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    func testRoutineTaskDueWhenNeverRun() {
        let a = PerformanceRecommender.assess(def(.flushDNS), lastRun: nil, conditions: .init(), now: now)
        XCTAssertTrue(a.isRecommended)
        XCTAssertTrue(a.preselect)
        XCTAssertTrue(a.reason.contains("Not run"))
    }

    func testRoutineTaskByLastRunDate() {
        let recent = PerformanceRecommender.assess(def(.flushDNS), lastRun: days(2), conditions: .init(), now: now)
        XCTAssertFalse(recent.isRecommended)
        XCTAssertFalse(recent.preselect)
        let old = PerformanceRecommender.assess(def(.flushDNS), lastRun: days(9), conditions: .init(), now: now)
        XCTAssertTrue(old.isRecommended)
        XCTAssertTrue(old.reason.contains("weekly"))
    }

    func testVPNSuppressesDNSRefresh() {
        let a = PerformanceRecommender.assess(def(.flushDNS), lastRun: nil, conditions: .init(vpnConnected: true), now: now)
        XCTAssertFalse(a.isRecommended)
        XCTAssertTrue(a.reason.contains("VPN"))
    }

    func testMemoryPressureRecommendsRelease() {
        let a = PerformanceRecommender.assess(def(.freeRAM), lastRun: days(1), conditions: .init(memoryPressureLevel: 2), now: now)
        XCTAssertTrue(a.isRecommended)
        XCTAssertTrue(a.preselect)
        let swap = PerformanceRecommender.assess(def(.freeRAM), lastRun: days(1),
                                                 conditions: .init(memoryPressureLevel: 1, swapUsedBytes: 3_000_000_000), now: now)
        XCTAssertTrue(swap.isRecommended)
        let calm = PerformanceRecommender.assess(def(.freeRAM), lastRun: days(1), conditions: .init(memoryPressureLevel: 1), now: now)
        XCTAssertFalse(calm.isRecommended)
    }

    func testPurgeableSpaceNeverPreselected() {
        let big = PerformanceRecommender.assess(def(.purgeableSpace), lastRun: nil,
                                                conditions: .init(purgeableBytes: 12_000_000_000), now: now)
        XCTAssertTrue(big.isRecommended)
        XCTAssertFalse(big.preselect, "thinning snapshots removes recovery points; never pre-select")
        let small = PerformanceRecommender.assess(def(.purgeableSpace), lastRun: nil,
                                                  conditions: .init(purgeableBytes: 200_000_000), now: now)
        XCTAssertFalse(small.isRecommended)
        let full = PerformanceRecommender.assess(def(.purgeableSpace), lastRun: nil,
                                                 conditions: .init(volumeFreeFraction: 0.05), now: now)
        XCTAssertTrue(full.isRecommended)
        let justRan = PerformanceRecommender.assess(def(.purgeableSpace), lastRun: now.addingTimeInterval(-3600),
                                                    conditions: .init(purgeableBytes: 12_000_000_000), now: now)
        XCTAssertFalse(justRan.isRecommended)
    }

    func testSpotlightUnavailableWhenIndexingOff() {
        let a = PerformanceRecommender.assess(def(.reindexSpotlight), lastRun: nil,
                                              conditions: .init(spotlightIndexingEnabled: false), now: now)
        XCTAssertFalse(a.isAvailable)
        XCTAssertFalse(a.isRecommended)
        let on = PerformanceRecommender.assess(def(.reindexSpotlight), lastRun: nil,
                                               conditions: .init(spotlightIndexingEnabled: true), now: now)
        XCTAssertTrue(on.isAvailable)
        XCTAssertFalse(on.isRecommended, "symptom-driven tasks are never recommended by date")
    }

    func testHomePermissionsOnlyWhenProblemFound() {
        let fine = PerformanceRecommender.assess(def(.repairHomePermissions), lastRun: nil, conditions: .init(), now: now)
        XCTAssertFalse(fine.isRecommended)
        let broken = PerformanceRecommender.assess(def(.repairHomePermissions), lastRun: nil,
                                                   conditions: .init(homePermissionProblems: ["~/Library isn't writable"]), now: now)
        XCTAssertTrue(broken.isRecommended)
        XCTAssertFalse(broken.preselect)
        XCTAssertEqual(broken.reason, "~/Library isn't writable")
    }

    func testMailCompactionConditions() {
        let bloated = PerformanceMailIndexInfo(path: "/x", bytes: 300_000_000, pageCount: 1000, freelistCount: 200)
        XCTAssertEqual(bloated.freelistRatio, 0.2, accuracy: 0.0001)
        XCTAssertEqual(bloated.reclaimableBytes, 60_000_000)
        let a = PerformanceRecommender.assess(def(.speedUpMail), lastRun: nil, conditions: .init(mailIndex: .measured(bloated)), now: now)
        XCTAssertTrue(a.isRecommended)
        XCTAssertFalse(a.preselect, "Mail must be quit, so it's never pre-selected")
        XCTAssertTrue(a.reason.contains("20%"))

        let tidy = PerformanceMailIndexInfo(path: "/x", bytes: 300_000_000, pageCount: 1000, freelistCount: 10)
        XCTAssertFalse(PerformanceRecommender.assess(def(.speedUpMail), lastRun: nil,
                                                     conditions: .init(mailIndex: .measured(tidy)), now: now).isRecommended)
        let none = PerformanceRecommender.assess(def(.speedUpMail), lastRun: nil, conditions: .init(mailIndex: .notFound), now: now)
        XCTAssertFalse(none.isAvailable)
        let locked = PerformanceRecommender.assess(def(.speedUpMail), lastRun: nil, conditions: .init(mailIndex: .unreadable), now: now)
        XCTAssertTrue(locked.isAvailable)
        XCTAssertTrue(locked.reason.contains("Full Disk Access"))
    }

    func testScriptsUseSystemRunDate() {
        let system = days(1)
        let conditions = PerformanceConditions(systemScriptsLastRun: system)
        XCTAssertEqual(PerformanceRecommender.effectiveLastRun(.maintenanceScripts, recorded: days(20), conditions: conditions), system)
        XCTAssertEqual(PerformanceRecommender.effectiveLastRun(.maintenanceScripts, recorded: nil, conditions: conditions), system)
        XCTAssertEqual(PerformanceRecommender.effectiveLastRun(.flushDNS, recorded: days(20), conditions: conditions), days(20))
        let states = PerformanceRecommender.states(for: [def(.maintenanceScripts)], recorded: [.maintenanceScripts: days(20)],
                                                   conditions: conditions, now: now)
        XCTAssertFalse(states[0].assessment.isRecommended)
        XCTAssertEqual(states[0].lastRun, system)
    }

    func testAssessmentNeverPreselectsUnavailableOrUnrecommended() {
        let a = PerformanceTaskAssessment(isAvailable: false, isRecommended: true, preselect: true, reason: "x")
        XCTAssertFalse(a.isRecommended)
        XCTAssertFalse(a.preselect)
        let b = PerformanceTaskAssessment(isRecommended: false, preselect: true, reason: "x")
        XCTAssertFalse(b.preselect)
    }
}

final class PerformanceTaskItemTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func states(_ conditions: PerformanceConditions = .init(), recorded: [PerformanceTaskID: Date] = [:]) -> [PerformanceTaskState] {
        PerformanceRecommender.states(for: PerformanceTaskCatalog.available { _ in true }, recorded: recorded,
                                      conditions: conditions, now: now)
    }

    func testItemsArePreselectedOnlyWhenSafeAndRecommended() {
        let group = PerformanceTaskItems.group(for: states(), onlyRecommended: false)
        XCTAssertEqual(group.id, PerformanceTaskItems.maintenanceGroupID)
        for item in group.allItems {
            XCTAssertEqual(item.deletion, .custom)
            XCTAssertEqual(item.size, 0)
            if item.isSelected {
                XCTAssertEqual(item.safety, .safe, "\(item.title) is pre-selected but not safe")
                XCTAssertEqual(item.metadata[PerformanceMetaKey.recommended], "1")
            }
        }
        let selected = Set(PerformanceTaskItems.taskIDs(in: group.allItems.filter(\.isSelected)))
        XCTAssertEqual(selected, [.freeRAM, .flushDNS, .maintenanceScripts])
    }

    func testCheckupGroupShowsOnlyRecommended() {
        let recent = Dictionary(uniqueKeysWithValues: PerformanceTaskID.allCases.map { ($0, now.addingTimeInterval(-3600)) })
        let quiet = PerformanceTaskItems.group(for: states(recorded: recent), onlyRecommended: true)
        XCTAssertTrue(quiet.isEmpty)
        let tile = PerformanceTaskItems.checkupTile(for: states(recorded: recent))
        XCTAssertEqual(tile.status, .clear)
        XCTAssertFalse(tile.isSelected)

        let due = states()
        let tileDue = PerformanceTaskItems.checkupTile(for: due)
        XCTAssertEqual(tileDue.status, .attention)
        XCTAssertEqual(tileDue.actionCount, 3)
        XCTAssertTrue(tileDue.isSelected)
    }

    func testCheckupTileInfoWhenOnlyHeavierTasksRecommended() {
        let recent = Dictionary(uniqueKeysWithValues: PerformanceTaskID.allCases.map { ($0, now.addingTimeInterval(-3 * 86_400)) })
        let s = states(.init(purgeableBytes: 20_000_000_000), recorded: recent)
        let tile = PerformanceTaskItems.checkupTile(for: s)
        XCTAssertEqual(tile.status, .info)
        XCTAssertFalse(tile.isSelected)
        XCTAssertEqual(tile.actionCount, 1)
    }

    func testTaskIDsFromItemsIgnoreOtherItems() {
        let other = ScanItem(id: "/tmp/x", title: "x")
        let task = PerformanceTaskItems.item(for: states()[0])
        XCTAssertEqual(PerformanceTaskItems.taskIDs(in: [other, task]), [states()[0].id])
    }

    func testRunOutcomeFromResults() {
        let results = [
            PerformanceTaskRunResult(id: .flushDNS, status: .done, detail: "ok"),
            PerformanceTaskRunResult(id: .speedUpMail, status: .done, detail: "ok", freedBytes: 50_000_000),
            PerformanceTaskRunResult(id: .freeRAM, status: .skipped, detail: "Cancelled"),
        ]
        let outcome = PerformanceRunSummary.outcome(results)
        XCTAssertEqual(outcome.module, .performance)
        XCTAssertEqual(outcome.processedCount, 2)
        XCTAssertEqual(outcome.freedBytes, 50_000_000)
        XCTAssertEqual(outcome.removedItemIDs, [PerformanceTaskID.flushDNS.itemID, PerformanceTaskID.speedUpMail.itemID])
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(outcome.failures.first?.reason, "Cancelled")
        XCTAssertEqual(outcome.summary, "2 of 3 tasks completed")
        XCTAssertEqual(PerformanceRunSummary.summary([results[0]]), "1 task completed")
        XCTAssertEqual(PerformanceRunSummary.summary([]), "No tasks were run")
    }
}
