import XCTest
@testable import IONNativeIslandsCore

final class NIContainerGeometryTests: XCTestCase {
    func testDocumentRectScalesThenSubtractsNativeScroll() {
        XCTAssertEqual(
            NIContainerGeometry.screenRect(
                x: 10, y: 20, width: 30, height: 40,
                zoom: 2, offset: CGPoint(x: 5, y: -5)
            ),
            CGRect(x: 15, y: 45, width: 60, height: 80)
        )
    }

    func testFixedRectIgnoresNativeScroll() {
        XCTAssertEqual(
            NIContainerGeometry.screenRect(
                x: 10, y: 20, width: 30, height: 40,
                zoom: 2, offset: CGPoint(x: 500, y: 600), fixed: true
            ),
            CGRect(x: 20, y: 40, width: 60, height: 80)
        )
    }

    func testZoomedExclusionUsesSameCoordinateSpaceAsIsland() {
        let exclusion = NIContainerGeometry.screenRect(
            x: 100, y: 150, width: 20, height: 30,
            zoom: 1.5, offset: CGPoint(x: 10, y: 25)
        )
        XCTAssertEqual(exclusion, CGRect(x: 140, y: 200, width: 30, height: 45))
        XCTAssertTrue(exclusion.contains(CGPoint(x: 155, y: 220)))
    }
}
