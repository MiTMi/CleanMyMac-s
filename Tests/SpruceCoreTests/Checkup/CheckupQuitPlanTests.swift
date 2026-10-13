import XCTest
@testable import SpruceCore

final class CheckupQuitPlanTests: XCTestCase {
    func testOneRowPerAppWithWhatItHoldsUp() {
        let needs = [
            CheckupAppNeed(processID: 40, bundleID: "com.google.Chrome", name: "Google Chrome",
                           appPath: "/Applications/Google Chrome.app", module: .cleanup, itemID: "/c/1"),
            CheckupAppNeed(processID: 40, bundleID: "com.google.Chrome", name: "Google Chrome",
                           module: .cleanup, itemID: "/c/2"),
            // The same item reported twice is counted once.
            CheckupAppNeed(processID: 40, bundleID: "com.google.Chrome", name: "Google Chrome",
                           module: .cleanup, itemID: "/c/2"),
            CheckupAppNeed(processID: 40, bundleID: "com.google.Chrome", name: "Google Chrome",
                           module: .applications, itemID: "applications.update:brew:google-chrome", label: "Update"),
            CheckupAppNeed(processID: 12, bundleID: "com.apple.mail", name: "Mail",
                           module: .performance, itemID: "performance.task.mail", label: "Speed Up Mail"),
            // Spruce itself is never asked to quit.
            CheckupAppNeed(processID: 99, bundleID: "app.spruce", name: "Spruce", module: .cleanup, itemID: "/s"),
        ]
        let apps = CheckupQuitPlan.blockingApps(needs, ownProcessID: 99)
        XCTAssertEqual(apps.map(\.name), ["Google Chrome", "Mail"], "sorted by name")

        let chrome = apps[0]
        XCTAssertEqual(chrome.id, 40)
        XCTAssertEqual(chrome.appPath, "/Applications/Google Chrome.app")
        XCTAssertEqual(chrome.itemIDs[.cleanup], ["/c/1", "/c/2"])
        XCTAssertEqual(chrome.modules, [.cleanup, .applications], "run order")
        XCTAssertEqual(chrome.detail, "Cleanup: 2 items · Applications: Update")

        XCTAssertEqual(apps[1].detail, "Performance: Speed Up Mail")
    }

    func testDetailShortensLongLabelLists() {
        let needs = (1...4).map { index in
            CheckupAppNeed(processID: 7, bundleID: "com.apple.mail", name: "Mail", module: .performance,
                           itemID: "task\(index)", label: "Task \(index)")
        }
        XCTAssertEqual(CheckupQuitPlan.blockingApps(needs).first?.detail, "Performance: Task 1, Task 2 +2 more")
    }

    func testNoNeedsNoRows() {
        XCTAssertTrue(CheckupQuitPlan.blockingApps([]).isEmpty)
        let onlySpruce = [CheckupAppNeed(processID: 5, bundleID: "app.spruce", name: "Spruce", module: .cleanup, itemID: "x")]
        XCTAssertTrue(CheckupQuitPlan.blockingApps(onlySpruce, ownProcessID: 5).isEmpty)
    }

    func testSkipDeselectsOnlyTheHeldUpItems() {
        let needs = [
            CheckupAppNeed(processID: 1, bundleID: "a", name: "A", module: .cleanup, itemID: "/a"),
            CheckupAppNeed(processID: 2, bundleID: "b", name: "B", module: .cleanup, itemID: "/b"),
            CheckupAppNeed(processID: 2, bundleID: "b", name: "B", module: .applications, itemID: "u:b"),
        ]
        let ids = CheckupQuitPlan.itemIDs(of: CheckupQuitPlan.blockingApps(needs))
        XCTAssertEqual(ids[.cleanup], ["/a", "/b"])
        XCTAssertEqual(ids[.applications], ["u:b"])

        let groups = [
            ScanGroup(id: "caches", title: "Caches", safety: .safe, items: [
                ScanItem(id: "/a", title: "A", safety: .safe),
                ScanItem(id: "/keep", title: "Keep", safety: .safe),
            ], children: [
                ScanGroup(id: "nested", title: "Nested", items: [ScanItem(id: "/b", title: "B", safety: .safe)]),
            ]),
        ]
        let result = CheckupQuitPlan.deselecting(ids[.cleanup] ?? [], in: groups)
        XCTAssertEqual(Set(result.selectedItems.map(\.id)), ["/keep"])
        XCTAssertEqual(result.allItems.count, 3, "items stay in the review for later")
        XCTAssertEqual(CheckupQuitPlan.deselecting([], in: groups), groups)
    }
}
