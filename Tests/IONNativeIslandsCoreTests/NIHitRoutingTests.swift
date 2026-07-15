import XCTest
@testable import IONNativeIslandsCore

final class NIHitRoutingTests: XCTestCase {
    func testTopmostNonInteractiveIslandBlocksLowerInteractiveIsland() {
        XCTAssertEqual(NIHitRouting.decide([
            NIHitCandidate(id: "camera", overlay: false, interactive: false, excluded: false),
            NIHitCandidate(id: "map", overlay: false, interactive: true, excluded: false),
        ]), NIHitDecision(owner: "web", reason: "non_interactive"))
    }

    func testInteractiveIslandReceivesGesture() {
        XCTAssertEqual(NIHitRouting.decide([
            NIHitCandidate(id: "map", overlay: false, interactive: true, excluded: false),
        ]), NIHitDecision(owner: "island", island: "map", reason: "interactive_island"))
    }

    func testWebExclusionRetainsWebOwnership() {
        XCTAssertEqual(NIHitRouting.decide([
            NIHitCandidate(id: "map", overlay: false, interactive: true, excluded: true),
        ]), NIHitDecision(owner: "web", reason: "web_exclusion"))
    }

    func testOverlayRetainsWebOwnership() {
        XCTAssertEqual(NIHitRouting.decide([
            NIHitCandidate(id: "glass", overlay: true, interactive: false, excluded: false),
            NIHitCandidate(id: "map", overlay: false, interactive: true, excluded: false),
        ]), NIHitDecision(owner: "web", reason: "overlay_occlusion"))
    }

    func testWebSheetExclusionPreventsNativeTouchObservation() {
        XCTAssertFalse(NIObserverRouting.shouldObserve(pointIsInHost: true, excludedByWeb: true))
    }

    func testObserverStillReceivesVisiblePageTouch() {
        XCTAssertTrue(NIObserverRouting.shouldObserve(pointIsInHost: true, excludedByWeb: false))
        XCTAssertFalse(NIObserverRouting.shouldObserve(pointIsInHost: false, excludedByWeb: false))
    }
}
