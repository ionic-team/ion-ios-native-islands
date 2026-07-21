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
}
