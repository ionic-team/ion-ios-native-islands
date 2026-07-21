import XCTest
@testable import IONNativeIslandsLib

final class NISafeGeometryTests: XCTestCase {
    func testAcceptsBoundaryGeometryAndOptionalRadius() {
        XCTAssertNotNil(NISafeGeometry.parseRect([
            "x": -NISafeGeometry.maxCoordinateMagnitude,
            "y": NISafeGeometry.maxCoordinateMagnitude,
            "w": NISafeGeometry.maxExtent,
            "h": 0.25,
        ]))
        XCTAssertNotNil(NISafeGeometry.parseRect([
            "x": 0,
            "y": 0,
            "w": 1,
            "h": 1,
            "r": NISafeGeometry.maxExtent,
        ]))
    }

    func testRejectsMalformedAndBooleanNumbers() {
        for radius: Any in [true, "12", NSNull()] {
            XCTAssertNil(NISafeGeometry.parseRect([
                "x": 0,
                "y": 0,
                "w": 10,
                "h": 10,
                "r": radius,
            ]))
        }
        XCTAssertNil(NISafeGeometry.parseRect([
            "x": false,
            "y": 0,
            "w": 10,
            "h": 10,
        ]))
    }

    func testRejectsUnsafeGeometryRanges() {
        let valid: [String: Any] = [
            "x": 0,
            "y": 0,
            "w": 10,
            "h": 10,
            "r": 0,
        ]
        for (key, value) in [
            ("x", NISafeGeometry.maxCoordinateMagnitude + 1),
            ("y", -NISafeGeometry.maxCoordinateMagnitude - 1),
            ("w", NISafeGeometry.maxExtent + 1),
            ("h", NISafeGeometry.maxExtent + 1),
            ("r", NISafeGeometry.maxExtent + 1),
        ] {
            var candidate = valid
            candidate[key] = value
            XCTAssertNil(NISafeGeometry.parseRect(candidate), key)
        }
        for (key, value) in [("w", 0.0), ("h", -1.0), ("r", -1.0)] {
            var candidate = valid
            candidate[key] = value
            XCTAssertNil(NISafeGeometry.parseRect(candidate), key)
        }
    }
}
