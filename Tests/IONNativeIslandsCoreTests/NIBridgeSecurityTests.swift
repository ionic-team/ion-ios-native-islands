import XCTest
@testable import IONNativeIslandsLib

final class NIBridgeSecurityTests: XCTestCase {
    private func command(
        island: String = "map-1",
        method: String,
        params: [String: Any] = [:],
        instance: Int? = 1
    ) -> Result<NIIslandCommand, NIBridgeError> {
        NIBridgeSecurity.command(island: island, type: "acme.map", method: method, params: params, instance: instance)
    }

    func testReadsCreateWithItsInstanceAndUpdate() throws {
        XCTAssertEqual(try command(method: "create", params: ["zoom": 4], instance: 3).get(), .create(instance: 3))
        XCTAssertEqual(try command(method: "update", instance: nil).get(), .update)
    }

    func testRefusesWhatNativeCannotRun() {
        XCTAssertEqual(command(method: "capture").failure?.code, "unknown_command")
        for instance in [nil, 0] as [Int?] {
            XCTAssertEqual(command(method: "create", instance: instance).failure?.code, "invalid_request")
        }
        XCTAssertEqual(command(island: "", method: "create").failure?.code, "invalid_request")
        XCTAssertEqual(command(method: "update", params: ["value": Date()]).failure?.code, "invalid_request")
        XCTAssertEqual(NIBridgeSecurity.operationError("reset", payload: ["value": Date()])?.code, "invalid_request")
    }

    func testAnInstanceIsAPositiveInteger() {
        XCTAssertEqual(NIBridgeSecurity.commandInstance(NSNumber(value: 2)), 2)
        XCTAssertNil(NIBridgeSecurity.commandInstance(NSNumber(value: 2.5)))
        XCTAssertNil(NIBridgeSecurity.commandInstance(true))
    }
}

private extension Result {
    var failure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
