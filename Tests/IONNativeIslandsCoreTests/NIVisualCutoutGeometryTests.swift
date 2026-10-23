import XCTest
@testable import IONNativeIslandsLib

final class NIVisualCutoutGeometryTests: XCTestCase {
    func testOverlappingRectanglesBecomeDisjointUnion() {
        let output = NIVisualCutoutGeometry.union([
            CGRect(x: 0, y: 0, width: 20, height: 20),
            CGRect(x: 10, y: 10, width: 20, height: 20),
        ])

        XCTAssertEqual(
            output.reduce(0) { $0 + $1.width * $1.height },
            700
        )
        for leftIndex in output.indices {
            for rightIndex in output.indices where rightIndex > leftIndex {
                XCTAssertFalse(output[leftIndex].intersects(output[rightIndex]))
            }
        }
    }

    func testAdjacentSlabsAreCoalesced() {
        XCTAssertEqual(
            NIVisualCutoutGeometry.union([
                CGRect(x: 0, y: 0, width: 10, height: 20),
                CGRect(x: 10, y: 0, width: 10, height: 20),
            ]),
            [CGRect(x: 0, y: 0, width: 20, height: 20)]
        )
    }

    func testEmptyAndInvalidRectanglesAreIgnored() {
        XCTAssertEqual(
            NIVisualCutoutGeometry.union([
                .zero,
                CGRect(x: 10, y: 10, width: -5, height: -5),
            ]),
            [CGRect(x: 5, y: 5, width: 5, height: 5)]
        )
    }

    private let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testCutoutsGrowToWholeDevicePixels() {
        let snapped = NIVisualCutoutGeometry.snappedOutward(
            CGRect(x: 10.2, y: 267.4, width: 40.05, height: 20.1),
            scale: 3
        )

        XCTAssertEqual(snapped.minX * 3, (10.2 * 3).rounded(.down), accuracy: 0.0001)
        XCTAssertEqual(snapped.minY * 3, (267.4 * 3).rounded(.down), accuracy: 0.0001)
        XCTAssertEqual(snapped.maxX * 3, ((10.2 + 40.05) * 3).rounded(.up), accuracy: 0.0001)
        XCTAssertEqual(snapped.maxY * 3, ((267.4 + 20.1) * 3).rounded(.up), accuracy: 0.0001)
    }

    func testMaskReachesPastTheHostSoNoCutoutEndsOnItsEdge() {
        let host = CGRect(x: 0, y: 0, width: 40.2, height: 33.53)
        let page = (rect: CGRect(x: -80, y: -300, width: 402, height: 874), radii: NICornerRadii(uniform: 0))
        let path = NIVisualCutoutGeometry.visiblePath(bounds: host, cutouts: [page])
        let clearance = NIVisualCutoutGeometry.edgeClearance

        XCTAssertEqual(path.boundingBox, host.insetBy(dx: -clearance, dy: -clearance))
        XCTAssertFalse(path.contains(CGPoint(x: 20, y: 33.5), using: .evenOdd))
        XCTAssertFalse(path.contains(CGPoint(x: 20, y: 0.1), using: .evenOdd))
    }

    private func shows(
        _ point: CGPoint,
        _ cutouts: [(rect: CGRect, radii: NICornerRadii)]
    )
        -> Bool {
        NIVisualCutoutGeometry.visiblePath(bounds: bounds, cutouts: cutouts)
            .contains(point, using: .evenOdd)
    }

    func testRoundedCutoutInsideAnotherStaysCut() {
        let sheet = (rect: CGRect(x: 0, y: 50, width: 100, height: 50), radii: NICornerRadii(uniform: 0))
        let handle = (rect: CGRect(x: 40, y: 55, width: 20, height: 4), radii: NICornerRadii(uniform: 2))
        let toggle = (rect: CGRect(x: 60, y: 70, width: 30, height: 20), radii: NICornerRadii(uniform: 10))

        XCTAssertFalse(shows(CGPoint(x: 50, y: 57), [sheet, handle, toggle]))
        XCTAssertFalse(shows(CGPoint(x: 75, y: 80), [sheet, handle, toggle]))
        XCTAssertTrue(shows(CGPoint(x: 50, y: 25), [sheet, handle, toggle]))
    }

    func testRepeatedAndOverlappingRoundedCutoutsStayCut() {
        let card = (rect: CGRect(x: 10, y: 10, width: 60, height: 60), radii: NICornerRadii(uniform: 12))
        let badge = (rect: CGRect(x: 50, y: 50, width: 40, height: 40), radii: NICornerRadii(uniform: 12))

        XCTAssertFalse(shows(CGPoint(x: 40, y: 40), [card, card]))
        XCTAssertFalse(shows(CGPoint(x: 60, y: 60), [card, badge]))
        XCTAssertTrue(shows(CGPoint(x: 5, y: 95), [card, badge]))
    }

    func testRoundedCutoutCrossingTheEdgeKeepsItsShape() {
        let bar = (rect: CGRect(x: -20, y: 80, width: 140, height: 40), radii: NICornerRadii(uniform: 20))

        XCTAssertFalse(shows(CGPoint(x: 1, y: 81), [bar]))
        XCTAssertFalse(shows(CGPoint(x: 99, y: 81), [bar]))
        XCTAssertTrue(shows(CGPoint(x: 50, y: 79), [bar]))
    }

    func testCutoutRoundedOnSomeCornersKeepsItsShape() {
        let button = (
            rect: CGRect(x: 20, y: 60, width: 40, height: 40),
            radii: NICornerRadii(topLeft: 12, topRight: 12, bottomRight: 0, bottomLeft: 0)
        )

        XCTAssertTrue(shows(CGPoint(x: 21, y: 61), [button]))
        XCTAssertFalse(shows(CGPoint(x: 21, y: 99), [button]))
        XCTAssertFalse(shows(CGPoint(x: 40, y: 61), [button]))
    }
}
