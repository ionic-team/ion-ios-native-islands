import XCTest
@testable import IONNativeIslandsLib

final class NISafeGeometryTests: XCTestCase {
    func testAcceptsFiniteGeometryAndOptionalRadius() {
        XCTAssertNotNil(NISafeGeometry.parseRect([
            "x": -16_777_216.0,
            "y": 16_777_216.0,
            "w": 65_536.0,
            "h": 0.25,
        ]))
        XCTAssertNotNil(NISafeGeometry.parseRect([
            "x": 0,
            "y": 0,
            "w": 1,
            "h": 1,
            "r": [65_536.0, 0, 16, 0],
        ]))
        XCTAssertEqual(
            NISafeGeometry.parseRect(["x": 0, "y": 0, "w": 40, "h": 20, "r": [16, 16, 0, 0]])?
                .cornerRadii,
            NICornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 0)
        )
    }

    func testRejectsMalformedAndBooleanNumbers() {
        for radius: Any in [true, "12", NSNull(), 12, [12, 12, 12], [12, 12, true, 12]] {
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

    func testRejectsNonPositiveSizesAndNegativeRadii() {
        let valid: [String: Any] = [
            "x": 0,
            "y": 0,
            "w": 10,
            "h": 10,
            "r": [0, 0, 0, 0],
        ]
        for (key, value): (String, Any) in [
            ("x", Double.infinity),
            ("y", Double.nan),
            ("w", 0.0),
            ("h", -1.0),
            ("r", [0, 0, -1, 0]),
        ] {
            var candidate = valid
            candidate[key] = value
            XCTAssertNil(NISafeGeometry.parseRect(candidate), key)
        }
    }
}
