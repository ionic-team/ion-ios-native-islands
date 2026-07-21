import XCTest
@testable import IONNativeIslandsLib

final class NISystemGestureInsetsTests: XCTestCase {
    private let insets = NISystemGestureInsets(left: 20, top: 4, right: 12, bottom: 24)

    func testDetectsEachProtectedEdge() {
        XCTAssertTrue(insets.contains(x: 0, y: 100, width: 400, height: 800))
        XCTAssertTrue(insets.contains(x: 200, y: 0, width: 400, height: 800))
        XCTAssertTrue(insets.contains(x: 399, y: 100, width: 400, height: 800))
        XCTAssertTrue(insets.contains(x: 200, y: 799, width: 400, height: 800))
    }

    func testExactInnerBoundaryBelongsToContent() {
        XCTAssertFalse(insets.contains(x: 20, y: 100, width: 400, height: 800))
        XCTAssertFalse(insets.contains(x: 200, y: 4, width: 400, height: 800))
        XCTAssertFalse(insets.contains(x: 387, y: 100, width: 400, height: 800))
        XCTAssertFalse(insets.contains(x: 200, y: 775, width: 400, height: 800))
    }

    func testInteriorIsNotProtected() {
        XCTAssertFalse(insets.contains(x: 200, y: 300, width: 400, height: 800))
    }

    func testZeroInsetsProtectNothing() {
        XCTAssertFalse(NISystemGestureInsets().contains(x: 0, y: 0, width: 400, height: 800))
    }

    func testOutsidePointsAreNotClassifiedAsEdges() {
        XCTAssertFalse(insets.contains(x: -1, y: 20, width: 400, height: 800))
        XCTAssertFalse(insets.contains(x: 400, y: 20, width: 400, height: 800))
    }
}
