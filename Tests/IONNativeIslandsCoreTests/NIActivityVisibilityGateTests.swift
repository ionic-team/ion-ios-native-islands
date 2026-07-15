import XCTest
@testable import IONNativeIslandsCore

final class NIActivityVisibilityGateTests: XCTestCase {
    func testStartsRunnable() {
        XCTAssertTrue(NIActivityVisibilityGate().shouldRun)
    }

    func testBackgroundAndViewportMustBothRecover() {
        let gate = NIActivityVisibilityGate()
        XCTAssertFalse(gate.setViewportVisible(false))
        XCTAssertFalse(gate.setAppActive(false))
        XCTAssertFalse(gate.setAppActive(true))
        XCTAssertTrue(gate.setViewportVisible(true))
    }

    func testForegroundDoesNotRestartAnOffscreenRenderer() {
        let gate = NIActivityVisibilityGate()
        gate.setViewportVisible(false)
        gate.setAppActive(false)

        XCTAssertFalse(gate.setAppActive(true))
    }

    func testViewportEntryDoesNotRestartWhileBackgrounded() {
        let gate = NIActivityVisibilityGate()
        gate.setAppActive(false)
        gate.setViewportVisible(false)

        XCTAssertFalse(gate.setViewportVisible(true))
    }

    func testDestructionIsTerminal() {
        let gate = NIActivityVisibilityGate()
        XCTAssertFalse(gate.destroy())
        XCTAssertFalse(gate.setAppActive(true))
        XCTAssertFalse(gate.setViewportVisible(true))
    }
}
