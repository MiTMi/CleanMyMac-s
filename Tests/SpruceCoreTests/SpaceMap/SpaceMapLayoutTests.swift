import Foundation
import XCTest
@testable import SpruceCore

final class SpaceMapPackTests: XCTestCase {
    private func assertNoOverlap(_ circles: [SpaceMapCircle], tolerance: Double = 1e-6,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for i in circles.indices {
            for j in circles.indices where j > i {
                XCTAssertFalse(circles[i].overlaps(circles[j], tolerance: tolerance),
                               "circles \(i) and \(j) overlap", file: file, line: line)
            }
        }
    }

    func testSiblingsAreTangentWithoutOverlap() {
        let radii: [Double] = [10, 8, 6, 5, 5, 4, 3, 3, 2, 2, 1.5, 1, 1, 0.5]
        let packed = SpaceMapPack.siblings(radii: radii)
        XCTAssertEqual(packed.circles.count, radii.count)
        XCTAssertEqual(packed.circles.map(\.r), radii)
        assertNoOverlap(packed.circles, tolerance: 1e-6)
        for circle in packed.circles {
            XCTAssertTrue(packed.enclosing.encloses(circle, tolerance: 1e-6))
        }
        XCTAssertEqual(packed.enclosing.x, 0, accuracy: 1e-9)
        XCTAssertEqual(packed.enclosing.y, 0, accuracy: 1e-9)
        // Compact: the packing uses a reasonable share of the enclosing disc.
        let used = packed.circles.reduce(0) { $0 + $1.area }
        XCTAssertGreaterThan(used / packed.enclosing.area, 0.5)
    }

    func testSmallCounts() {
        XCTAssertTrue(SpaceMapPack.siblings(radii: []).circles.isEmpty)
        let one = SpaceMapPack.siblings(radii: [3])
        XCTAssertEqual(one.enclosing.r, 3)
        let two = SpaceMapPack.siblings(radii: [3, 1])
        XCTAssertEqual(two.enclosing.r, 4, accuracy: 1e-9)
        XCTAssertFalse(two.circles[0].overlaps(two.circles[1]))
        let three = SpaceMapPack.siblings(radii: [1, 1, 1])
        assertNoOverlap(three.circles)
        // Three unit circles: enclosing radius 1 + 2/sqrt(3).
        XCTAssertEqual(three.enclosing.r, 1 + 2 / 3.0.squareRoot(), accuracy: 1e-6)
    }

    func testEncloseKnownCases() {
        let single = SpaceMapPack.enclose([SpaceMapCircle(x: 5, y: 5, r: 2)])
        XCTAssertEqual(single, SpaceMapCircle(x: 5, y: 5, r: 2))
        let pair = SpaceMapPack.enclose([SpaceMapCircle(x: -2, y: 0, r: 1), SpaceMapCircle(x: 2, y: 0, r: 1)])
        XCTAssertEqual(pair.x, 0, accuracy: 1e-9)
        XCTAssertEqual(pair.r, 3, accuracy: 1e-9)
        let nested = SpaceMapPack.enclose([SpaceMapCircle(x: 0, y: 0, r: 10), SpaceMapCircle(x: 1, y: 1, r: 1)])
        XCTAssertEqual(nested.r, 10, accuracy: 1e-9)
        var random = SpaceMapLCG()
        let scattered = (0..<30).map { _ in
            SpaceMapCircle(x: random.next() * 100, y: random.next() * 100, r: random.next() * 10 + 0.1)
        }
        let enclosing = SpaceMapPack.enclose(scattered)
        for circle in scattered {
            XCTAssertTrue(enclosing.encloses(circle, tolerance: 1e-6))
        }
    }

    func testLayoutIsAreaProportionalAndFits() {
        let values: [Double] = [4_000_000_000, 1_000_000_000, 250_000_000, 90_000_000, 1, 0]
        let circles = SpaceMapPack.layout(values: values, width: 800, height: 500, inset: 10)
        XCTAssertEqual(circles.count, values.count)
        // Area ratio follows the value ratio.
        XCTAssertEqual(circles[0].area / circles[1].area, 4, accuracy: 1e-6)
        XCTAssertEqual(circles[1].r / circles[2].r, 2, accuracy: 1e-6)
        for circle in circles {
            XCTAssertGreaterThan(circle.r, 0)
            XCTAssertGreaterThanOrEqual(circle.x - circle.r, -1e-6)
            XCTAssertLessThanOrEqual(circle.x + circle.r, 800 + 1e-6)
            XCTAssertGreaterThanOrEqual(circle.y - circle.r, 10 - 1e-6)
            XCTAssertLessThanOrEqual(circle.y + circle.r, 490 + 1e-6)
        }
        assertNoOverlap(circles, tolerance: 1e-6)
        // Deterministic.
        XCTAssertEqual(circles, SpaceMapPack.layout(values: values, width: 800, height: 500, inset: 10))
        XCTAssertTrue(SpaceMapPack.layout(values: [], width: 100, height: 100).isEmpty)
        XCTAssertEqual(SpaceMapPack.layout(values: [0, 0], width: 100, height: 100).count, 2)
    }

    func testHitTest() {
        let circles = [SpaceMapCircle(x: 50, y: 50, r: 40), SpaceMapCircle(x: 50, y: 50, r: 10),
                       SpaceMapCircle(x: 200, y: 50, r: 20)]
        XCTAssertEqual(SpaceMapPack.hitTest(circles, x: 50, y: 52), 1, "smallest containing disc wins")
        XCTAssertEqual(SpaceMapPack.hitTest(circles, x: 20, y: 50), 0)
        XCTAssertEqual(SpaceMapPack.hitTest(circles, x: 205, y: 45), 2)
        XCTAssertNil(SpaceMapPack.hitTest(circles, x: 400, y: 400))
    }
}

final class SpaceMapBubbleMapTests: XCTestCase {
    func testBuildsTopChildrenPlusSmallerBubble() {
        var children: [SpaceMapNode] = (0..<30).map { SpaceMapNode.file("f\($0)", size: Int64(10_000 - $0 * 10)) }
        let sub = SpaceMapNode.folder("Projects", children: (0..<5).map { .file("p\($0)", size: 40_000) })
        children.append(sub)
        let root = SpaceMapNode.folder("root", basePath: "/r", children: children)
        let map = SpaceMapBubbleMapBuilder.build(focus: root, width: 900, height: 600, limit: 24, minShare: 0)
        XCTAssertEqual(map.bubbles.count, 25)
        XCTAssertTrue(map.bubbles.first?.node === sub, "largest first, in the middle")
        guard case .smaller(let group) = map.bubbles.last?.content else { return XCTFail("expected a smaller bubble") }
        XCTAssertEqual(group.count, 7)
        XCTAssertFalse(map.bubbles[0].inner.isEmpty, "big folders preview their children")
        for inner in map.bubbles[0].inner {
            XCTAssertTrue(map.bubbles[0].circle.encloses(inner.circle, tolerance: 1e-6))
        }
        let center = map.bubbles[0].circle
        XCTAssertTrue(map.bubble(atX: center.x, y: center.y)?.node === sub)
        XCTAssertNotNil(map.bubble(for: group.nodes[0]))
        XCTAssertTrue(map.bubble(for: sub)?.node === sub)
    }
}

final class SpaceMapSunburstTests: XCTestCase {
    func testRingsNestInsideTheirParents() throws {
        let root = SpaceMapFixture.tree()
        let segments = SpaceMapSunburst.layout(focus: root, maxDepth: 3, holeRadius: 50, outerRadius: 200, minAngle: 0.0001)
        let depth1 = segments.filter { $0.depth == 1 }
        XCTAssertEqual(depth1.map { $0.node?.name ?? "?" }, ["movies", "big.iso", "docs", "tiny.txt"])
        let total = depth1.reduce(0) { $0 + $1.span }
        XCTAssertEqual(total, 2 * Double.pi, accuracy: 1e-9)
        XCTAssertEqual(depth1[0].span / depth1[1].span, 900.0 / 400.0, accuracy: 1e-9)
        XCTAssertEqual(depth1[0].innerRadius, 50, accuracy: 1e-9)
        XCTAssertEqual(depth1[0].outerRadius, 100, accuracy: 1e-9)

        let movies = try XCTUnwrap(depth1.first)
        let movieChildren = segments.filter { $0.parent === movies.node }
        XCTAssertEqual(movieChildren.count, 2)
        for child in movieChildren {
            XCTAssertEqual(child.depth, 2)
            XCTAssertGreaterThanOrEqual(child.startAngle, movies.startAngle - 1e-12)
            XCTAssertLessThanOrEqual(child.endAngle, movies.endAngle + 1e-12)
        }
        XCTAssertTrue(segments.allSatisfy { $0.depth <= 3 })
    }

    func testTinySegmentsFold() {
        let children = [SpaceMapNode.file("big", size: 1_000_000)] + (0..<20).map { SpaceMapNode.file("t\($0)", size: 100) }
        let root = SpaceMapNode.folder("r", basePath: "/r", children: children)
        let segments = SpaceMapSunburst.layout(focus: root, maxDepth: 2, holeRadius: 10, outerRadius: 100, minAngle: 0.01)
        XCTAssertEqual(segments.filter { $0.node != nil }.count, 1)
        let folded = segments.first { $0.node == nil }
        XCTAssertEqual(folded?.foldedCount, 20)
        XCTAssertEqual(folded?.bytes, 2000)
    }

    func testAnglesAndHitTest() throws {
        XCTAssertEqual(SpaceMapSunburst.angle(dx: 0, dy: -1), 0, accuracy: 1e-12)
        XCTAssertEqual(SpaceMapSunburst.angle(dx: 1, dy: 0), Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(SpaceMapSunburst.angle(dx: 0, dy: 1), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(SpaceMapSunburst.angle(dx: -1, dy: 0), 3 * Double.pi / 2, accuracy: 1e-12)
        let point = SpaceMapSunburst.point(angle: Double.pi / 2, radius: 10, cx: 0, cy: 0)
        XCTAssertEqual(point.x, 10, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0, accuracy: 1e-9)

        let root = SpaceMapFixture.tree()
        let segments = SpaceMapSunburst.layout(focus: root, maxDepth: 2, holeRadius: 50, outerRadius: 150, minAngle: 0.0001)
        // Just right of 12 o'clock on the first ring is the largest child (movies).
        let hit = try XCTUnwrap(SpaceMapSunburst.hitTest(segments, dx: 1, dy: -75))
        XCTAssertEqual(segments[hit].node?.name, "movies")
        XCTAssertNil(SpaceMapSunburst.hitTest(segments, dx: 0, dy: -10), "the hole is empty")
        XCTAssertNil(SpaceMapSunburst.hitTest(segments, dx: 0, dy: -400))
    }
}
