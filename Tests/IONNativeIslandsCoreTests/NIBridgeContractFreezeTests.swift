import XCTest
@testable import IONNativeIslandsLib

/// The core contract is compared for exact equality against the web runtime. These
/// literals are pinned by the same test in TypeScript and Kotlin; editing any of them
/// here without the coordinated bump fails four builds instead of breaking apps.
final class NIBridgeContractFreezeTests: XCTestCase {
    func testCoreContractValuesAreFrozen() {
        XCTAssertEqual(NIBridgeContract.protocolVersion, 6)
        XCTAssertEqual(NIBridgeContract.maxRequestBytes, 16384)
        XCTAssertEqual(NIBridgeContract.maxLayoutBytes, 1_048_576)
        XCTAssertEqual(NIBridgeContract.maxIdentifierBytes, 64)
        XCTAssertEqual(NIBridgeContract.maxCommandBytes, 128)
        XCTAssertEqual(
            NIBridgeContract.maxCoordinateMagnitudeCSSPixels,
            16_777_216
        )
        XCTAssertEqual(NIBridgeContract.maxSizeCSSPixels, 65536)
        XCTAssertEqual(NIBridgeContract.maxRadiusCSSPixels, 65536)
        XCTAssertEqual(NIBridgeContract.errors, [
            "invalid_request", "unknown_command", "handler_failed",
            "payload_too_large", "unsupported_version", "internal_error",
        ])
    }
}
