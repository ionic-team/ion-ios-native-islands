import XCTest
@testable import IONNativeIslandsLib

final class NIContainerGeometryTests: XCTestCase {
    func testCalibratedOffsetPreservesNonzeroInitialPosition() {
        func offset(_ native: CGPoint) -> CGPoint {
            NIContainerGeometry.calibratedScrollOffset(
                nativeOffset: native,
                zoom: 2,
                bias: CGPoint(x: 2, y: 5),
                maxDomOffset: CGPoint(x: 1000, y: 1000),
                maxNativeOffset: CGPoint(x: 1000, y: 1000)
            )
        }
        XCTAssertEqual(offset(CGPoint(x: 44, y: 250)), CGPoint(x: 20, y: 120))
        XCTAssertEqual(offset(CGPoint(x: 64, y: 310)), CGPoint(x: 30, y: 150))
    }

    func testCalibratedOffsetAbsorbsOnePointBottomCeilingSlackWhilePreservingOverscroll() {
        let maxDom = CGPoint(x: 0, y: 7100)
        let maxNative = CGPoint(x: 0, y: 7101)

        XCTAssertEqual(
            NIContainerGeometry.calibratedScrollOffset(
                nativeOffset: CGPoint(x: 0, y: 7101),
                zoom: 1,
                bias: .zero,
                maxDomOffset: maxDom,
                maxNativeOffset: maxNative
            ),
            CGPoint(x: 0, y: 7100)
        )
        XCTAssertEqual(
            NIContainerGeometry.calibratedScrollOffset(
                nativeOffset: CGPoint(x: 0, y: 7125),
                zoom: 1,
                bias: .zero,
                maxDomOffset: maxDom,
                maxNativeOffset: maxNative
            ),
            CGPoint(x: 0, y: 7124)
        )
        XCTAssertEqual(
            NIContainerGeometry.calibratedScrollOffset(
                nativeOffset: CGPoint(x: 0, y: 7101),
                zoom: 1,
                bias: CGPoint(x: 0, y: 1),
                maxDomOffset: maxDom,
                maxNativeOffset: maxNative
            ),
            CGPoint(x: 0, y: 7100)
        )
    }

    func testDocumentCoordinatesApplyNestedAndRootOffsets() {
        XCTAssertEqual(
            NIContainerGeometry.screenRect(
                IslandRect(x: 200, y: 300, width: 40, height: 20, cornerRadii: NICornerRadii(uniform: 4)),
                coordinateSpace: .document,
                nestedOffset: CGPoint(x: 25, y: 60),
                zoom: 2,
                rootOffset: CGPoint(x: 10, y: 30)
            ),
            IslandRect(x: 340, y: 450, width: 80, height: 40, cornerRadii: NICornerRadii(uniform: 8))
        )
    }

    func testViewportCoordinatesMoveWithTheirScrollersButNotTheDocument() {
        XCTAssertEqual(
            NIContainerGeometry.screenRect(
                IslandRect(x: 20, y: 30, width: 40, height: 20, cornerRadii: NICornerRadii(uniform: 0)),
                coordinateSpace: .viewport,
                nestedOffset: CGPoint(x: 25, y: 60),
                zoom: 2,
                rootOffset: CGPoint(x: 10, y: 30)
            ).cgRect,
            CGRect(x: -10, y: -60, width: 80, height: 40)
        )
    }

    func testTouchesInATransparentCornerMissTheIsland() {
        let rect = CGRect(x: 20, y: 40, width: 200, height: 120)
        let pill = NICornerRadii(uniform: 160)

        XCTAssertFalse(pill.contains(CGPoint(x: 20, y: 40), in: rect))
        XCTAssertTrue(pill.contains(CGPoint(x: 120, y: 100), in: rect))
        XCTAssertTrue(pill.contains(CGPoint(x: 30, y: 100), in: rect))
        XCTAssertFalse(pill.contains(CGPoint(x: 19, y: 100), in: rect))
        XCTAssertEqual(pill.fitted(to: rect.size), NICornerRadii(uniform: 60))

        let sheet = CGRect(x: 0, y: 0, width: 200, height: 100)
        let top = NICornerRadii(topLeft: 100, topRight: 100, bottomRight: 0, bottomLeft: 0)
        XCTAssertFalse(top.contains(CGPoint(x: 2, y: 2), in: sheet), "each corner rounds on its own")
        XCTAssertTrue(top.contains(CGPoint(x: 1, y: 99), in: sheet))
        XCTAssertTrue(top.contains(CGPoint(x: 199, y: 99), in: sheet))
    }

    func testATurnedIslandIsDrawnByItsMatrixThenItsMotionScale() throws {
        // A 100 x 50 island turned a quarter clockwise covers 50 x 100; a motion draws it at half that.
        let turned = try XCTUnwrap(NIIslandTransform(["size": [100, 50], "matrix": [0, 1, -1, 0, 50, 0]]))
        let rect = IslandRect(x: 200, y: 300, width: 50, height: 100, cornerRadii: NICornerRadii(uniform: 10))
        let body = NIIslandBody(rect: rect, placed: CGSize(width: 25, height: 50), zoom: 1, transform: turned)

        XCTAssertEqual(body.size, CGSize(width: 100, height: 50))
        XCTAssertEqual(body.transform, CGAffineTransform(a: 0, b: 0.5, c: -0.5, d: 0, tx: 25, ty: 0))
        XCTAssertEqual(CGPoint(x: 100, y: 50).applying(body.transform), CGPoint(x: 0, y: 50), "its far corner lands in the host")
        XCTAssertTrue(body.contains(CGPoint(x: 12.5, y: 25)))
        XCTAssertFalse(body.contains(CGPoint(x: 0.5, y: 0.5)), "its own rounded corner, turned, misses")
        XCTAssertNil(NIIslandTransform(["size": [0, 50], "matrix": [1, 0, 0, 1, 0, 0]]))
    }
}
