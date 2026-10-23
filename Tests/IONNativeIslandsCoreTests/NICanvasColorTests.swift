import XCTest
@testable import IONNativeIslandsLib

final class NICanvasColorTests: XCTestCase {
    func testReadsAnOpaqueHexCanvas() {
        XCTAssertEqual(NICanvasColor("#f3f6F8"), NICanvasColor("#F3F6F8"))
        let color = NICanvasColor("#ff8000")
        XCTAssertEqual(color?.red, 1)
        XCTAssertEqual(color?.green ?? 0, 128.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(color?.blue, 0)
    }

    func testRefusesAnythingElse() {
        for value: Any in ["#fff", "f3f6f8", "#f3f6f8aa", "#g3f6f8", "#+3f6f8", 0xF3F6F8] {
            XCTAssertNil(NICanvasColor(value), "\(value)")
        }
        XCTAssertNil(NICanvasColor(nil))
    }
}
