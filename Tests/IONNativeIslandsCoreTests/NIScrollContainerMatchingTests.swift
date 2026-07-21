import XCTest
@testable import IONNativeIslandsLib

final class NIScrollContainerMatchingTests: XCTestCase {
    private let main = NIScrollContainerGeometry(
        x: 16,
        y: 72,
        width: 364,
        height: 514,
        contentWidth: 364,
        contentHeight: 1148,
        offsetX: 0,
        offsetY: 120
    )

    func testMatchesOneCandidateWithinTolerance() {
        let candidate = NIScrollContainerGeometry(
            x: 16.5,
            y: 71.5,
            width: 364,
            height: 514,
            contentWidth: 364,
            contentHeight: 1148.5,
            offsetX: 0,
            offsetY: 120.5
        )

        XCTAssertEqual(
            NIScrollContainerMatching.match(
                descriptors: [
                    "main": NIScrollContainerDescriptor(geometry: main),
                ],
                candidates: [
                    NIScrollContainerCandidate(
                        key: 4,
                        geometry: candidate
                    ),
                ],
                tolerance: 1
            ),
            NIScrollContainerMatchResult(
                matches: ["main": 4],
                failures: [:]
            )
        )
    }

    func testRejectsMissingAndAmbiguousCandidates() {
        let missing = NIScrollContainerMatching.match(
            descriptors: [
                "main": NIScrollContainerDescriptor(geometry: main),
            ],
            candidates: [],
            tolerance: 1
        )
        XCTAssertEqual(missing.failures["main"], .missing)

        let ambiguous = NIScrollContainerMatching.match(
            descriptors: [
                "main": NIScrollContainerDescriptor(geometry: main),
            ],
            candidates: [
                NIScrollContainerCandidate(key: 1, geometry: main),
                NIScrollContainerCandidate(key: 2, geometry: main),
            ],
            tolerance: 1
        )
        XCTAssertEqual(ambiguous.failures["main"], .ambiguous)
        XCTAssertTrue(ambiguous.matches.isEmpty)
    }

    func testRejectsOneCandidateClaimedByTwoDescriptors() {
        let result = NIScrollContainerMatching.match(
            descriptors: [
                "first": NIScrollContainerDescriptor(geometry: main),
                "second": NIScrollContainerDescriptor(geometry: main),
            ],
            candidates: [
                NIScrollContainerCandidate(key: 1, geometry: main),
            ],
            tolerance: 1
        )

        XCTAssertEqual(result.failures["first"], .sharedCandidate)
        XCTAssertEqual(result.failures["second"], .sharedCandidate)
        XCTAssertTrue(result.matches.isEmpty)
    }

    func testCurrentOffsetParticipatesInMatching() {
        let staleOffset = NIScrollContainerGeometry(
            x: main.x,
            y: main.y,
            width: main.width,
            height: main.height,
            contentWidth: main.contentWidth,
            contentHeight: main.contentHeight,
            offsetX: main.offsetX,
            offsetY: 0
        )

        let result = NIScrollContainerMatching.match(
            descriptors: [
                "main": NIScrollContainerDescriptor(geometry: main),
            ],
            candidates: [
                NIScrollContainerCandidate(
                    key: 1,
                    geometry: staleOffset
                ),
            ],
            tolerance: 1
        )

        XCTAssertEqual(result.failures["main"], .missing)
    }

    func testPreservesSignedBounceOffsets() {
        let reversed = NIScrollContainerGeometry(
            x: main.x,
            y: main.y,
            width: main.width,
            height: main.height,
            contentWidth: 900,
            contentHeight: main.contentHeight,
            offsetX: -40,
            offsetY: -120
        )

        XCTAssertEqual(
            NIScrollContainerMatching.match(
                descriptors: [
                    "reversed": NIScrollContainerDescriptor(
                        geometry: reversed
                    ),
                ],
                candidates: [
                    NIScrollContainerCandidate(
                        key: 3,
                        geometry: reversed
                    ),
                ],
                tolerance: 1
            ).matches["reversed"],
            3
        )
    }

    func testMatchesNestedCandidatesByAncestorPath() {
        let inner = NIScrollContainerGeometry(
            x: 16,
            y: 180,
            width: 364,
            height: 220,
            contentWidth: 364,
            contentHeight: 660,
            offsetX: 0,
            offsetY: 40
        )
        let result = NIScrollContainerMatching.match(
            descriptors: [
                "outer": NIScrollContainerDescriptor(geometry: main),
                "inner": NIScrollContainerDescriptor(
                    geometry: inner,
                    scrollPath: ["outer"]
                ),
            ],
            candidates: [
                NIScrollContainerCandidate(key: 2, geometry: main),
                NIScrollContainerCandidate(
                    key: 4,
                    geometry: inner,
                    ancestorKeys: [2]
                ),
            ],
            tolerance: 1
        )

        XCTAssertEqual(result.matches, ["outer": 2, "inner": 4])
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testUsesUniqueGeometryWhenWebKitHierarchyIsFlat() {
        let inner = NIScrollContainerGeometry(
            x: 16,
            y: 180,
            width: 364,
            height: 220,
            contentWidth: 364,
            contentHeight: 660,
            offsetX: 0,
            offsetY: 40
        )
        let result = NIScrollContainerMatching.match(
            descriptors: [
                "outer": NIScrollContainerDescriptor(geometry: main),
                "inner": NIScrollContainerDescriptor(
                    geometry: inner,
                    scrollPath: ["outer"]
                ),
            ],
            candidates: [
                NIScrollContainerCandidate(key: 2, geometry: main),
                NIScrollContainerCandidate(
                    key: 4,
                    geometry: inner,
                    ancestorKeys: []
                ),
            ],
            tolerance: 1
        )

        XCTAssertEqual(result.matches, ["outer": 2, "inner": 4])
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testUsesTopologyToDisambiguateEqualNestedCandidates() {
        let inner = NIScrollContainerGeometry(
            x: 16,
            y: 180,
            width: 364,
            height: 220,
            contentWidth: 364,
            contentHeight: 660,
            offsetX: 0,
            offsetY: 40
        )
        let result = NIScrollContainerMatching.match(
            descriptors: [
                "outer": NIScrollContainerDescriptor(geometry: main),
                "inner": NIScrollContainerDescriptor(
                    geometry: inner,
                    scrollPath: ["outer"]
                ),
            ],
            candidates: [
                NIScrollContainerCandidate(key: 2, geometry: main),
                NIScrollContainerCandidate(
                    key: 4,
                    geometry: inner,
                    ancestorKeys: [2]
                ),
                NIScrollContainerCandidate(
                    key: 6,
                    geometry: inner,
                    ancestorKeys: []
                ),
            ],
            tolerance: 1
        )

        XCTAssertEqual(result.matches, ["outer": 2, "inner": 4])
        XCTAssertTrue(result.failures.isEmpty)
    }
}
