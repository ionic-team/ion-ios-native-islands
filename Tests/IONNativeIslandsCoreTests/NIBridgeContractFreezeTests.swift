import XCTest
@testable import IONNativeIslandsCore

// The core contract is compared for exact equality against the web runtime. These
// literals are pinned by the same test in TypeScript and Kotlin; editing any of them
// here without the coordinated bump fails four builds instead of breaking apps.
final class NIBridgeContractFreezeTests: XCTestCase {
    func testCoreContractValuesAreFrozen() {
        XCTAssertEqual(NIBridgeContract.protocolVersion, 2)
        XCTAssertEqual(NIBridgeContract.contractDigest, "ni-core-1.0")
        XCTAssertEqual(NIBridgeContract.maxRequestBytes, 16384)
        XCTAssertEqual(NIBridgeContract.maxResponseBytes, 2_097_152)
        XCTAssertEqual(NIBridgeContract.maxIdentifierBytes, 64)
        XCTAssertEqual(NIBridgeContract.maxCommandBytes, 128)
        XCTAssertEqual(NIBridgeContract.errors, [
            "invalid_request", "unknown_command", "permission_denied", "handler_failed",
            "payload_too_large", "unsupported_version", "internal_error",
        ])
        XCTAssertEqual(NIBridgeContract.commands["__page"], ["setBackdrop"])
        XCTAssertEqual(NIBridgeContract.capabilities["__page"], "effects")
        XCTAssertEqual(NIBridgeContract.permissions["__page"], "effects.overlay")
    }
}
