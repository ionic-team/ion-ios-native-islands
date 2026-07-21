import XCTest
@testable import IONNativeIslandsLib

final class NIHitRoutingTests: XCTestCase {
    func testTopmostNonInteractiveIslandKeepsWebOwnership() {
        XCTAssertEqual(
            NIHitRouting.decide([
                NIHitCandidate(
                    id: "camera",
                    interactive: false,
                    excluded: false
                ),
                NIHitCandidate(
                    id: "map",
                    interactive: true,
                    excluded: false
                ),
            ]),
            NIHitDecision(owner: "web", reason: "non_interactive")
        )
    }

    func testInteractiveIslandReceivesGesture() {
        XCTAssertEqual(
            NIHitRouting.decide([
                NIHitCandidate(
                    id: "map",
                    interactive: true,
                    excluded: false
                ),
            ]),
            NIHitDecision(
                owner: "island",
                island: "map",
                reason: "interactive_island"
            )
        )
    }

    func testWebExclusionKeepsWebOwnership() {
        XCTAssertEqual(
            NIHitRouting.decide([
                NIHitCandidate(
                    id: "map",
                    interactive: true,
                    excluded: true
                ),
            ]),
            NIHitDecision(owner: "web", reason: "web_exclusion")
        )
    }
}
