import XCTest
@testable import IONNativeIslandsLib

final class NIIslandLifecycleStateTests: XCTestCase {
    func testIdentityCannotChangeComponentType() {
        let state = NIIslandLifecycleState<String>()
        XCTAssertTrue(state.registerType(id: "island-1", type: "map"))
        XCTAssertTrue(state.registerType(id: "island-1", type: "map"))
        XCTAssertFalse(state.registerType(id: "island-1", type: "camera"))
        XCTAssertEqual(state.type(for: "island-1"), "map")
    }

    func testBufferedCommandsDrainOnceInOrder() {
        let state = NIIslandLifecycleState<Int>()
        state.buffer(id: "island-1", command: .create(instance: 4), payload: 1)
        state.buffer(id: "island-1", command: .update, payload: 2)
        let drained = state.drain(id: "island-1")
        XCTAssertEqual(drained.map(\.command), [.create(instance: 4), .update])
        XCTAssertEqual(drained.map(\.payload), [1, 2])
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testMountErrorDropsPendingAndIsReportedOnce() {
        let state = NIIslandLifecycleState<String>()
        state.buffer(id: "island-1", command: .update, payload: "payload")
        XCTAssertTrue(state.markErrored(id: "island-1"))
        XCTAssertFalse(state.markErrored(id: "island-1"))
        XCTAssertTrue(state.isErrored(id: "island-1"))
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testRetainForgetsIslandsNoLongerInTheLayout() {
        let state = NIIslandLifecycleState<String>()
        _ = state.registerType(id: "keep", type: "map")
        _ = state.registerType(id: "remove", type: "map")
        _ = state.create(id: "remove", instance: 1)
        state.buffer(id: "remove", command: .update, payload: "pending")
        XCTAssertTrue(state.markErrored(id: "remove"))
        state.retain(ids: ["keep"])
        XCTAssertEqual(state.type(for: "keep"), "map")
        XCTAssertNil(state.type(for: "remove"))
        XCTAssertTrue(state.drain(id: "remove").isEmpty)
        XCTAssertFalse(state.isErrored(id: "remove"))
        XCTAssertEqual(state.create(id: "remove", instance: 1), .create)
    }

    func testTransferMovesTypeInstanceAndPendingCommands() {
        let state = NIIslandLifecycleState<String>()
        _ = state.registerType(id: "card", type: "app-preview")
        _ = state.create(id: "card", instance: 7)
        state.buffer(id: "card", command: .update, payload: "next")
        state.transfer(from: "card", to: "studio")
        XCTAssertNil(state.type(for: "card"))
        XCTAssertNil(state.instance(for: "card"))
        XCTAssertEqual(state.type(for: "studio"), "app-preview")
        XCTAssertEqual(state.instance(for: "studio"), 7)
        XCTAssertEqual(state.drain(id: "studio").map(\.payload), ["next"])
    }
}
