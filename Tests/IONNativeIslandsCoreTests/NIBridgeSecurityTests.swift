import XCTest
@testable import IONNativeIslandsLib

final class NIBridgeSecurityTests: XCTestCase {
    private let security = NIBridgeSecurity()

    func testAcceptsFixedCreateAndUpdateCommands() {
        for method in ["create", "update"] {
            XCTAssertNoThrow(
                try security.validateCommand(
                    version: NIBridgeSecurity.protocolVersion,
                    island: "map-1",
                    type: "acme.map",
                    method: method,
                    params: ["zoom": 4]
                )
            )
        }
    }

    func testRejectsUnknownCommand() {
        assertCode("unknown_command") {
            try self.security.validateCommand(
                version: NIBridgeSecurity.protocolVersion,
                island: "map-1",
                type: "acme.map",
                method: "capture",
                params: [:]
            )
        }
    }

    func testRejectsMalformedIdentifiersAndNonJSONPayloads() {
        assertCode("invalid_request") {
            try self.security.validateCommand(
                version: NIBridgeSecurity.protocolVersion,
                island: "bad id!",
                type: "acme.map",
                method: "create",
                params: [:]
            )
        }
        assertCode("invalid_request") {
            try self.security.validateCommand(
                version: NIBridgeSecurity.protocolVersion,
                island: "map-1",
                type: "acme.map",
                method: "update",
                params: ["value": Date()]
            )
        }
    }

    func testRejectsMismatchedVersion() {
        assertCode("unsupported_version") {
            try self.security.validateVersion(
                NIBridgeSecurity.protocolVersion + 1
            )
        }
    }

    func testOperationPayloadIsSizeBounded() {
        assertCode("payload_too_large") {
            try self.security.validateOperation(
                "applyLayout",
                payload: [
                    "protocolVersion": NIBridgeSecurity.protocolVersion,
                    "value": String(repeating: "x", count: 64),
                ],
                maxBytes: 32
            )
        }
    }

    func testFrozenOperationByteBoundAcceptsExactLimit() throws {
        let empty: [String: Any] = [
            "protocolVersion": NIBridgeSecurity.protocolVersion,
            "value": "",
        ]
        let emptyBytes = try JSONSerialization.data(
            withJSONObject: empty
        ).count
        let exact: [String: Any] = [
            "protocolVersion": NIBridgeSecurity.protocolVersion,
            "value": String(
                repeating: "x",
                count: NIBridgeSecurity.maxRequestBytes - emptyBytes
            ),
        ]
        XCTAssertEqual(
            try JSONSerialization.data(withJSONObject: exact).count,
            NIBridgeSecurity.maxRequestBytes
        )
        XCTAssertNoThrow(
            try security.validateOperation("reset", payload: exact)
        )

        var tooLarge = exact
        tooLarge["value"] = String(
            repeating: "x",
            count: NIBridgeSecurity.maxRequestBytes - emptyBytes + 1
        )
        assertCode("payload_too_large") {
            try self.security.validateOperation("reset", payload: tooLarge)
        }
    }

    func testLayoutBudgetIsSeparateAndBounded() {
        let overCommandBudget: [String: Any] = [
            "protocolVersion": NIBridgeSecurity.protocolVersion,
            "value": String(
                repeating: "x",
                count: NIBridgeSecurity.maxRequestBytes
            ),
        ]
        XCTAssertNoThrow(
            try security.validateOperation(
                "applyLayout",
                payload: overCommandBudget,
                maxBytes: NIBridgeSecurity.maxLayoutBytes
            )
        )

        let overLayoutBudget: [String: Any] = [
            "protocolVersion": NIBridgeSecurity.protocolVersion,
            "value": String(
                repeating: "x",
                count: NIBridgeSecurity.maxLayoutBytes
            ),
        ]
        assertCode("payload_too_large") {
            try self.security.validateOperation(
                "applyLayout",
                payload: overLayoutBudget,
                maxBytes: NIBridgeSecurity.maxLayoutBytes
            )
        }
    }

    func testRejectsMalformedOperationVersionWithoutBoolCoercion() {
        for version: Any in [true, 1.5, "1"] {
            assertCode("unsupported_version") {
                try self.security.validateOperation(
                    "applyLayout",
                    payload: ["protocolVersion": version]
                )
            }
        }
    }

    func testJSONDepthIsBoundedAt32() {
        XCTAssertNoThrow(
            try security.validateCommand(
                version: NIBridgeSecurity.protocolVersion,
                island: "map-1",
                type: "acme.map",
                method: "update",
                params: ["value": nestedJSON(depth: 31)]
            )
        )
        assertCode("invalid_request") {
            try self.security.validateCommand(
                version: NIBridgeSecurity.protocolVersion,
                island: "map-1",
                type: "acme.map",
                method: "update",
                params: ["value": self.nestedJSON(depth: 32)]
            )
        }
    }

    private func nestedJSON(depth: Int) -> Any {
        (0..<depth).reduce("leaf" as Any) { value, _ in
            ["child": value]
        }
    }

    private func assertCode(
        _ code: String,
        _ action: () throws -> Void
    ) {
        XCTAssertThrowsError(try action()) { error in
            XCTAssertEqual((error as? NIBridgeSecurityError)?.code, code)
        }
    }
}
