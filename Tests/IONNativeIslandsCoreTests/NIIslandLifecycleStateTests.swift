import XCTest
@testable import IONNativeIslandsLib

final class NIIslandLifecycleStateTests: XCTestCase {
    func testIdentityCannotChangeComponentType() {
        let state = NIIslandLifecycleState<String>()
        XCTAssertEqual(
            state.registerType(id: "island-1", type: "map"),
            .registered
        )
        XCTAssertEqual(
            state.registerType(id: "island-1", type: "map"),
            .matched
        )
        XCTAssertEqual(
            state.registerType(id: "island-1", type: "camera"),
            .typeMismatch
        )
        XCTAssertEqual(state.type(for: "island-1"), "map")
    }

    func testBufferedCommandsDrainOnceInOrder() {
        let state = NIIslandLifecycleState<Int>()
        XCTAssertEqual(
            state.buffer(
                id: "island-1",
                method: "create",
                payload: 1
            ),
            .buffered
        )
        XCTAssertEqual(
            state.buffer(
                id: "island-1",
                method: "update",
                payload: 2
            ),
            .buffered
        )
        let drained = state.drain(id: "island-1")
        XCTAssertEqual(drained.map(\.method), ["create", "update"])
        XCTAssertEqual(drained.map(\.payload), [1, 2])
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testMountErrorDropsPendingAndDeduplicatesReports() {
        let state = NIIslandLifecycleState<String>()
        XCTAssertEqual(state.buffer(
            id: "island-1",
            method: "create",
            payload: "payload"
        ), .buffered)
        XCTAssertTrue(state.markErrored(id: "island-1"))
        XCTAssertFalse(state.markErrored(id: "island-1"))
        XCTAssertTrue(state.isErrored(id: "island-1"))
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testResetClearsAllPageState() {
        let state = NIIslandLifecycleState<String>()
        XCTAssertTrue(
            state.registerType(id: "island-1", type: "map") == .registered
        )
        XCTAssertEqual(state.buffer(
            id: "island-1",
            method: "create",
            payload: "payload"
        ), .buffered)
        XCTAssertTrue(state.markErrored(id: "island-1"))
        state.reset()
        XCTAssertNil(state.type(for: "island-1"))
        XCTAssertFalse(state.isErrored(id: "island-1"))
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testBufferCapsPendingCommandsAndComponentIDs() {
        let state = NIIslandLifecycleState<String>()
        for index in 0..<(NIIslandLifecycleState<String>.maxPendingCommandsPerID + 10) {
            let result = state.buffer(
                id: "island-1",
                method: "update",
                payload: "\(index)"
            )
            XCTAssertEqual(
                result,
                index < NIIslandLifecycleState<String>.maxPendingCommandsPerID
                    ? .buffered
                    : .pendingCommandLimitExceeded
            )
        }
        XCTAssertEqual(
            state.drain(id: "island-1").count,
            NIIslandLifecycleState<String>.maxPendingCommandsPerID
        )

        let over = NIIslandLifecycleState<String>.maxPendingIDs + 1
        for index in 0..<over {
            let id = "ghost-\(index)"
            XCTAssertEqual(
                state.registerType(id: id, type: "map"),
                .registered
            )
            let result = state.buffer(
                id: id,
                method: "update",
                payload: "value"
            )
            XCTAssertEqual(
                result,
                index < NIIslandLifecycleState<String>.maxPendingIDs
                    ? .buffered
                    : .pendingIDLimitExceeded
            )
            if result != .buffered {
                state.removeType(id: id)
            }
        }
        XCTAssertTrue(state.drain(id: "ghost-\(over - 1)").isEmpty)
        XCTAssertNil(state.type(for: "ghost-\(over - 1)"))
    }

    func testRetainClearsStateForComponentsNoLongerInLayout() {
        let state = NIIslandLifecycleState<String>()
        XCTAssertEqual(state.registerType(id: "keep", type: "map"), .registered)
        XCTAssertEqual(state.registerType(id: "remove", type: "map"), .registered)
        XCTAssertEqual(state.buffer(
            id: "remove",
            method: "create",
            payload: "pending"
        ), .buffered)
        XCTAssertTrue(state.markErrored(id: "remove"))
        state.retain(ids: ["keep"])
        XCTAssertEqual(state.type(for: "keep"), "map")
        XCTAssertNil(state.type(for: "remove"))
        XCTAssertTrue(state.drain(id: "remove").isEmpty)
        XCTAssertFalse(state.isErrored(id: "remove"))
    }

    func testTypeCapacityIsBounded() {
        let state = NIIslandLifecycleState<String>()
        for index in 0..<NIIslandLifecycleState<String>.maxTrackedTypes {
            XCTAssertEqual(
                state.registerType(id: "island-\(index)", type: "map"),
                .registered
            )
        }
        XCTAssertEqual(
            state.registerType(id: "overflow", type: "map"),
            .capacityExceeded
        )
        XCTAssertNil(state.type(for: "overflow"))
    }
}
