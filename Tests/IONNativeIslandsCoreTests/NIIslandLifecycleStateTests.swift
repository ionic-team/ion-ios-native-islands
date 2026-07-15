import XCTest
@testable import IONNativeIslandsCore

final class NIIslandLifecycleStateTests: XCTestCase {
    func testIdentityCannotChangeType() {
        let state = NIIslandLifecycleState<String>()
        XCTAssertTrue(state.registerType(id: "island-1", type: "map"))
        XCTAssertTrue(state.registerType(id: "island-1", type: "map"))
        XCTAssertFalse(state.registerType(id: "island-1", type: "camera"))
        XCTAssertEqual(state.type(for: "island-1"), "map")
    }

    func testBufferedCommandsDrainExactlyOnceInOrder() {
        let state = NIIslandLifecycleState<Int>()
        state.buffer(id: "island-1", method: "create", payload: 1)
        state.buffer(id: "island-1", method: "setTheme", payload: 2)
        let drained = state.drain(id: "island-1")
        XCTAssertEqual(drained.map(\.method), ["create", "setTheme"])
        XCTAssertEqual(drained.map(\.payload), [1, 2])
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testMountErrorDropsPendingAndDeduplicatesReports() {
        let state = NIIslandLifecycleState<String>()
        state.buffer(id: "island-1", method: "create", payload: "payload")
        XCTAssertTrue(state.markErrored(id: "island-1"))
        XCTAssertFalse(state.markErrored(id: "island-1"))
        XCTAssertTrue(state.isErrored(id: "island-1"))
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
    }

    func testResetKeepsOnlyPersistentIdentityAndDropsPageLocalState() {
        let state = NIIslandLifecycleState<String>()
        state.registerType(id: "persistent", type: "engine")
        state.registerType(id: "ordinary", type: "map")
        state.buffer(id: "persistent", method: "create", payload: "old-page")
        state.markErrored(id: "ordinary")
        state.reset(keeping: ["persistent"])
        XCTAssertEqual(state.type(for: "persistent"), "engine")
        XCTAssertNil(state.type(for: "ordinary"))
        XCTAssertTrue(state.drain(id: "persistent").isEmpty)
        XCTAssertFalse(state.isErrored(id: "ordinary"))
        XCTAssertTrue(state.isAwaitingAdoption(id: "persistent"))
        XCTAssertTrue(state.consumeAdoption(id: "persistent"))
        XCTAssertFalse(state.consumeAdoption(id: "persistent"))
    }

    func testRemovingIdentityDropsEveryAssociatedState() {
        let state = NIIslandLifecycleState<String>()
        state.registerType(id: "island-1", type: "map")
        state.buffer(id: "island-1", method: "create", payload: "payload")
        state.markAwaitingAdoption(id: "island-1")
        state.removeType(id: "island-1")
        XCTAssertNil(state.type(for: "island-1"))
        XCTAssertTrue(state.drain(id: "island-1").isEmpty)
        XCTAssertFalse(state.isAwaitingAdoption(id: "island-1"))
    }
}
