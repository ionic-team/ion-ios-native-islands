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

    func testViewportCoordinatesIgnoreEveryScrollOffset() {
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
            CGRect(x: 40, y: 60, width: 80, height: 40)
        )
    }

    func testRoundedRectRejectsTransparentCorners() {
        let rect = CGRect(x: 20, y: 40, width: 200, height: 120)

        XCTAssertFalse(
            NIContainerGeometry.contains(
                point: CGPoint(x: 20, y: 40),
                in: rect,
                cornerRadius: 160
            )
        )
        XCTAssertTrue(
            NIContainerGeometry.contains(
                point: CGPoint(x: 120, y: 100),
                in: rect,
                cornerRadius: 160
            )
        )
        XCTAssertTrue(
            NIContainerGeometry.contains(
                point: CGPoint(x: 30, y: 100),
                in: rect,
                cornerRadius: 160
            )
        )
        XCTAssertFalse(
            NIContainerGeometry.contains(
                point: CGPoint(x: 19, y: 100),
                in: rect,
                cornerRadius: 160
            )
        )
        XCTAssertEqual(
            NIContainerGeometry.clampedCornerRadius(
                width: 200,
                height: 120,
                cornerRadius: 160
            ),
            60
        )
    }
}
