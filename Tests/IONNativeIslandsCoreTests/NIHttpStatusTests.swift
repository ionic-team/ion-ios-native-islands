import XCTest
@testable import IONNativeIslandsCore

final class NIHttpStatusTests: XCTestCase {
    func testMapsEveryPublicBridgeErrorDeterministically() {
        XCTAssertEqual(NIHttpStatus.forCode(nil), 200)
        XCTAssertEqual(NIHttpStatus.forCode(""), 200)
        XCTAssertEqual(NIHttpStatus.forCode("invalid_request"), 400)
        XCTAssertEqual(NIHttpStatus.forCode("permission_denied"), 403)
        XCTAssertEqual(NIHttpStatus.forCode("unknown_command"), 404)
        XCTAssertEqual(NIHttpStatus.forCode("payload_too_large"), 413)
        XCTAssertEqual(NIHttpStatus.forCode("unsupported_version"), 426)
        XCTAssertEqual(NIHttpStatus.forCode("handler_failed"), 500)
        XCTAssertEqual(NIHttpStatus.forCode("internal_error"), 500)
    }
}
