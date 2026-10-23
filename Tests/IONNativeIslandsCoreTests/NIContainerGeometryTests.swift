import XCTest
@testable import IONNativeIslandsLib

final class NIContainerGeometryTests: XCTestCase {
    func testCalibratedOffsetPreservesNonzeroInitialPosition() {
        let bias = CGPoint(x: 2, y: 5)

        XCTAssertEqual(
            NIContainerGeometry.calibratedScrollOffset(
                nativeOffset: CGPoint(x: 44, y: 250),
                zoom: 2,
                bias: bias
            ),
            CGPoint(x: 20, y: 120)
        )
        XCTAssertEqual(
            NIContainerGeometry.calibratedScrollOffset(
                nativeOffset: CGPoint(x: 64, y: 310),
                zoom: 2,
                bias: bias
            ),
            CGPoint(x: 30, y: 150)
        )
    }

    func testDocumentRectScalesThenSubtractsNativeScroll() {
        XCTAssertEqual(
            NIContainerGeometry.screenRect(
                x: 10,
                y: 20,
                width: 30,
                height: 40,
                zoom: 2,
                offset: CGPoint(x: 5, y: -5)
            ),
            CGRect(x: 15, y: 45, width: 60, height: 80)
        )
    }

    func testZoomedExclusionUsesSameCoordinateSpaceAsIsland() {
        let exclusion = NIContainerGeometry.screenRect(
            x: 100,
            y: 150,
            width: 20,
            height: 30,
            zoom: 1.5,
            offset: CGPoint(x: 10, y: 25)
        )
        XCTAssertEqual(exclusion, CGRect(x: 140, y: 200, width: 30, height: 45))
        XCTAssertTrue(exclusion.contains(CGPoint(x: 155, y: 220)))
    }

    func testDocumentCoordinatesApplyNestedAndRootOffsets() {
        XCTAssertEqual(
            NIContainerGeometry.screenRect(
                x: 200,
                y: 300,
                width: 40,
                height: 20,
                coordinateSpace: .document,
                nestedOffset: CGPoint(x: 25, y: 60),
                zoom: 2,
                rootOffset: CGPoint(x: 10, y: 30)
            ),
            CGRect(x: 340, y: 450, width: 80, height: 40)
        )
    }

    func testViewportCoordinatesMoveWithTheirScrollersButNotTheDocument() {
        XCTAssertEqual(
            NIContainerGeometry.screenRect(
                x: 20,
                y: 30,
                width: 40,
                height: 20,
                coordinateSpace: .viewport,
                nestedOffset: CGPoint(x: 25, y: 60),
                zoom: 2,
                rootOffset: CGPoint(x: 10, y: 30)
            ),
            CGRect(x: -10, y: -60, width: 80, height: 40)
        )
    }

    func testRoundedRectRejectsTransparentCorners() {
        let rect = CGRect(x: 20, y: 40, width: 200, height: 120)
        let pill = NICornerRadii(uniform: 160)

        XCTAssertFalse(pill.contains(CGPoint(x: 20, y: 40), in: rect))
        XCTAssertTrue(pill.contains(CGPoint(x: 120, y: 100), in: rect))
        XCTAssertTrue(pill.contains(CGPoint(x: 30, y: 100), in: rect))
        XCTAssertFalse(pill.contains(CGPoint(x: 19, y: 100), in: rect))
        XCTAssertEqual(pill.fitted(to: rect.size), NICornerRadii(uniform: 60))
    }

    func testCornersRoundIndependently() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let top = NICornerRadii(topLeft: 100, topRight: 100, bottomRight: 0, bottomLeft: 0)

        XCTAssertFalse(top.contains(CGPoint(x: 2, y: 2), in: rect))
        XCTAssertTrue(top.contains(CGPoint(x: 1, y: 99), in: rect))
        XCTAssertTrue(top.contains(CGPoint(x: 199, y: 99), in: rect))
        XCTAssertEqual(top.fitted(to: rect.size), top)
        XCTAssertNil(top.sharedRadius(in: rect.size))
        XCTAssertEqual(
            NICornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 0)
                .sharedRadius(in: rect.size),
            16
        )
        XCTAssertEqual(NICornerRadii.square.sharedRadius(in: rect.size), 0)

        let path = top.path(in: rect)
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 2)))
        XCTAssertTrue(path.contains(CGPoint(x: 100, y: 50)))
        XCTAssertTrue(path.contains(CGPoint(x: 1, y: 99)))
    }
}
