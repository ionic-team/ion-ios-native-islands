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
        state.buffer(
            id: "island-1",
            method: "create",
            payload: 1
        )
        state.buffer(
            id: "island-1",
            method: "update",
            payload: 2
        )
        let drained = state.drain(id: "island-1")
        XCTAssertEqual(drained.map(\.method), ["create", "update"])
        XCTAssertEqual(drained.map(\.payload), [1, 2])
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testMountErrorDropsPendingAndDeduplicatesReports() {
        let state = NIIslandLifecycleState<String>()
        state.buffer(
            id: "island-1",
            method: "create",
            payload: "payload"
        )
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
        state.buffer(
            id: "island-1",
            method: "create",
            payload: "payload"
        )
        XCTAssertTrue(state.markErrored(id: "island-1"))
        state.reset()
        XCTAssertNil(state.type(for: "island-1"))
        XCTAssertFalse(state.isErrored(id: "island-1"))
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testRetainClearsStateForComponentsNoLongerInLayout() {
        let state = NIIslandLifecycleState<String>()
        XCTAssertEqual(state.registerType(id: "keep", type: "map"), .registered)
        XCTAssertEqual(state.registerType(id: "remove", type: "map"), .registered)
        state.buffer(
            id: "remove",
            method: "create",
            payload: "pending"
        )
        XCTAssertTrue(state.markErrored(id: "remove"))
        state.retain(ids: ["keep"])
        XCTAssertEqual(state.type(for: "keep"), "map")
        XCTAssertNil(state.type(for: "remove"))
        XCTAssertTrue(state.drain(id: "remove").isEmpty)
        XCTAssertFalse(state.isErrored(id: "remove"))
    }

    func testACreateForTheKeptInstanceUpdatesAndAnotherRecreates() {
        let state = NIIslandLifecycleState<String>()
        XCTAssertEqual(state.create(id: "one", instance: 1), .create)
        XCTAssertEqual(state.create(id: "one", instance: 1), .update)
        XCTAssertEqual(state.instance(for: "one"), 1)
        XCTAssertEqual(state.create(id: "one", instance: 2), .recreate)
        XCTAssertEqual(state.instance(for: "one"), 2)
    }

    func testAnInstanceIsForgottenWithTheView() {
        let state = NIIslandLifecycleState<String>()
        _ = state.registerType(id: "dropped", type: "map")
        _ = state.registerType(id: "kept", type: "map")
        _ = state.create(id: "dropped", instance: 1)
        _ = state.create(id: "kept", instance: 1)
        state.retain(ids: ["kept"])
        XCTAssertNil(state.instance(for: "dropped"))
        XCTAssertEqual(state.create(id: "dropped", instance: 1), .create)
        _ = state.markErrored(id: "kept")
        XCTAssertNil(state.instance(for: "kept"))
        _ = state.create(id: "kept", instance: 3)
        state.reset()
        XCTAssertNil(state.instance(for: "kept"))
    }

    func testABufferedCreateKeepsItsInstance() {
        let state = NIIslandLifecycleState<String>()
        state.buffer(id: "one", method: "create", payload: "first", instance: 4)
        XCTAssertEqual(state.drain(id: "one").first?.instance, 4)
    }
}
