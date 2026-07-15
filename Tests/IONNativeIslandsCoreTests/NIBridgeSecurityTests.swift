import XCTest
@testable import IONNativeIslandsCore

final class NIBridgeSecurityTests: XCTestCase {
    func testCanonicalWireGoldenVectors() throws {
        for vector in NIGoldenVectors.all {
            let decoded = try NIWireCodec.decode(Data(vector.input.utf8))
            XCTAssertEqual(try NIWireCodec.encodeString(decoded), vector.canonical, vector.name)
        }
    }

    private func subject(permissions: [String] = ["map.control", "layout.control"]) -> NIBridgeSecurity {
        NIBridgeSecurity(
            origins: ["capacitor://localhost"],
            capabilities: ["maps"],
            permissions: permissions)
    }

    func testAcceptsRegisteredCommand() throws {
        XCTAssertNoThrow(try subject().validateCommand(
            version: 2, contractDigest: NIBridgeSecurity.contractDigest,
            island: "map-1", type: "map", method: "setCamera",
            params: ["lat": 1.0], origin: "capacitor://localhost",
            customCommands: ["create", "setCamera", "panTo"], customCapability: "maps",
                customPermission: "map.control"))
    }

    func testRejectsOriginPermissionUnknownCommandAndOversizedPayload() {
        assertCode("permission_denied") {
            try subject().validateCommand(
                version: 2, contractDigest: NIBridgeSecurity.contractDigest,
                island: "map-1", type: "map", method: "setCamera",
                params: [:], origin: "https://evil.example",
                customCommands: ["create", "setCamera", "panTo"], customCapability: "maps",
                customPermission: "map.control")
        }
        assertCode("permission_denied") {
            try subject(permissions: []).validateCommand(
                version: 2, contractDigest: NIBridgeSecurity.contractDigest,
                island: "map-1", type: "map", method: "setCamera",
                params: [:], origin: "capacitor://localhost",
                customCommands: ["create", "setCamera", "panTo"], customCapability: "maps",
                customPermission: "map.control")
        }
        assertCode("unknown_command") {
            try subject().validateCommand(
                version: 2, contractDigest: NIBridgeSecurity.contractDigest,
                island: "map-1", type: "map", method: "erase",
                params: [:], origin: "capacitor://localhost",
                customCommands: ["create", "setCamera", "panTo"], customCapability: "maps",
                customPermission: "map.control")
        }
        assertCode("payload_too_large") {
            try subject().validateCommand(
                version: 2, contractDigest: NIBridgeSecurity.contractDigest,
                island: "map-1", type: "map", method: "setCamera",
                params: ["blob": String(repeating: "x", count: NIBridgeSecurity.maxRequestBytes)],
                origin: "capacitor://localhost",
                customCommands: ["create", "setCamera", "panTo"], customCapability: "maps",
                customPermission: "map.control")
        }
    }

    func testOperationGateUsesSameOriginPermissionAndSizePolicy() throws {
        XCTAssertNoThrow(try subject().validateOperation(
            "applyLayout", payload: ["protocolVersion": 2, "contractDigest": NIBridgeSecurity.contractDigest,
                                     "components": []], origin: "capacitor://localhost",
            permission: "layout.control"))
        assertCode("permission_denied") {
            try self.subject(permissions: []).validateOperation(
                "applyLayout", payload: ["protocolVersion": 2, "contractDigest": NIBridgeSecurity.contractDigest],
                origin: "capacitor://localhost",
                permission: "layout.control")
        }
    }

    func testRegistryPermissionChainAndProtocolVersionFailClosed() throws {
        // Island policy rides the registration entry: the per-command override outranks the
        // type permission, and both outrank the custom.<type>.command default.
        let chain = NIBridgeSecurity(
            origins: ["capacitor://localhost"],
            capabilities: ["camera"],
            permissions: ["camera.view"])
        XCTAssertNoThrow(try chain.validateCommand(
            version: 2, contractDigest: NIBridgeSecurity.contractDigest,
            island: "cam-1", type: "camera", method: "start", params: [:],
            origin: "capacitor://localhost",
            customCommands: ["start", "capture"], customCapability: "camera",
            customPermission: "camera.view",
            customCommandPermissions: ["camera.capture": "camera.capture"]))
        assertCode("permission_denied") {
            try chain.validateCommand(
                version: 2, contractDigest: NIBridgeSecurity.contractDigest,
                island: "cam-1", type: "camera", method: "capture", params: [:],
                origin: "capacitor://localhost",
                customCommands: ["start", "capture"], customCapability: "camera",
                customPermission: "camera.view",
                customCommandPermissions: ["camera.capture": "camera.capture"])
        }
        assertCode("unsupported_version") {
            try self.subject().validateCommand(
                version: NIBridgeSecurity.protocolVersion + 1,
                contractDigest: NIBridgeSecurity.contractDigest,
                island: "map-1", type: "map", method: "setCamera",
                params: [:], origin: "capacitor://localhost",
                customCommands: ["create", "setCamera", "panTo"], customCapability: "maps",
                customPermission: "map.control")
        }
        assertCode("unsupported_version") {
            try self.subject().validateCommand(
                version: NIBridgeSecurity.protocolVersion, contractDigest: "stale",
                island: "map-1", type: "map", method: "setCamera",
                params: [:], origin: "capacitor://localhost",
                customCommands: ["create", "setCamera", "panTo"], customCapability: "maps",
                customPermission: "map.control")
        }
    }

    func testCustomFactoryPolicyAndResponseLimitsFailClosed() throws {
        let custom = NIBridgeSecurity(
            origins: ["capacitor://localhost"],
            capabilities: ["custom.fixture"],
            permissions: ["custom.fixture.command"])
        XCTAssertNoThrow(try custom.validateCommand(
            version: 2, contractDigest: NIBridgeSecurity.contractDigest,
            island: "fixture-1", type: "fixture", method: "setTheme", params: [:],
            origin: "capacitor://localhost", customCommands: ["create", "setTheme"],
            customCapability: "custom.fixture"))
        assertCode("unknown_command") {
            try custom.validateCommand(
                version: 2, contractDigest: NIBridgeSecurity.contractDigest,
                island: "fixture-1", type: "fixture", method: "erase", params: [:],
                origin: "capacitor://localhost", customCommands: ["create", "setTheme"],
                customCapability: "custom.fixture")
        }
        assertCode("invalid_request") {
            try custom.validateCommand(
                version: 2, contractDigest: NIBridgeSecurity.contractDigest,
                island: "bad id!", type: "fixture", method: "create", params: [:],
                origin: "capacitor://localhost", customCommands: ["create"],
                customCapability: "custom.fixture")
        }
        assertCode("internal_error") {
            try custom.validateResponse(["value": Date()])
        }
        assertCode("payload_too_large") {
            try custom.validateResponse([
                "value": String(repeating: "x", count: NIBridgeSecurity.maxResponseBytes)
            ])
        }
    }

    private func assertCode(_ code: String, _ action: () throws -> Void) {
        XCTAssertThrowsError(try action()) { error in
            XCTAssertEqual((error as? NIBridgeSecurityError)?.code, code)
        }
    }
}
