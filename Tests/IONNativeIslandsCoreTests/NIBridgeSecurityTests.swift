import XCTest
@testable import IONNativeIslandsLib

final class NIBridgeSecurityTests: XCTestCase {
    private let security = NIBridgeSecurity()

    func testAcceptsFixedCreateAndUpdateCommands() {
        for method in ["create", "update"] {
            XCTAssertNoThrow(
                try security.validateCommand(
                    island: "map-1",
                    type: "acme.map",
                    method: method,
                    params: ["zoom": 4],
                    instance: 1
                )
            )
        }
    }

    func testACreateNamesTheInstanceNativeKeepsItsViewFor() {
        for instance in [nil, 0] as [Int?] {
            assertCode("invalid_request") {
                try self.security.validateCommand(
                    island: "map-1",
                    type: "acme.map",
                    method: "create",
                    params: [:],
                    instance: instance
                )
            }
        }
        XCTAssertEqual(security.commandInstance(NSNumber(value: 2)), 2)
        XCTAssertNil(security.commandInstance(NSNumber(value: 2.5)))
        XCTAssertNil(security.commandInstance(true))
    }

    func testRejectsUnknownCommand() {
        assertCode("unknown_command") {
            try self.security.validateCommand(
                island: "map-1",
                type: "acme.map",
                method: "capture",
                params: [:],
                instance: 1
            )
        }
    }

    func testRejectsEmptyIdentifiersAndNonJSONPayloads() {
        assertCode("invalid_request") {
            try self.security.validateCommand(
                island: "",
                type: "acme.map",
                method: "create",
                params: [:],
                instance: 1
            )
        }
        assertCode("invalid_request") {
            try self.security.validateCommand(
                island: "map-1",
                type: "acme.map",
                method: "update",
                params: ["value": Date()],
                instance: 1
            )
        }
        assertCode("invalid_request") {
            try self.security.validateOperation(
                "reset",
                payload: ["value": Date()]
            )
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
