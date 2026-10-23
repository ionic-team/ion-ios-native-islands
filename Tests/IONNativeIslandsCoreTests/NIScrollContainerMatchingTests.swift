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

    func testRejectsAMissingCandidate() {
        let missing = NIScrollContainerMatching.match(
            descriptors: [
                "main": NIScrollContainerDescriptor(geometry: main),
            ],
            candidates: [],
            tolerance: 1
        )
        XCTAssertEqual(missing.failures["main"], .missing)
    }

    func testLookalikeScrollersPairWithScrollViewsFromTheTop() {
        let two = NIScrollContainerMatching.match(
            descriptors: [
                "lower": NIScrollContainerDescriptor(geometry: main, order: 1),
                "upper": NIScrollContainerDescriptor(geometry: main, order: 0),
            ],
            candidates: [
                NIScrollContainerCandidate(key: 3, geometry: main),
                NIScrollContainerCandidate(key: 7, geometry: main),
            ],
            tolerance: 1
        )
        XCTAssertEqual(two.matches, ["upper": 7, "lower": 3])
        XCTAssertTrue(two.failures.isEmpty)

        let one = NIScrollContainerMatching.match(
            descriptors: [
                "lower": NIScrollContainerDescriptor(geometry: main, order: 1),
                "upper": NIScrollContainerDescriptor(geometry: main, order: 0),
            ],
            candidates: [NIScrollContainerCandidate(key: 1, geometry: main)],
            tolerance: 1
        )
        XCTAssertEqual(one.matches, ["upper": 1])
        XCTAssertEqual(one.failures, ["lower": .sharedCandidate])
    }

    func testDifferentScrollersNeverShareAScrollView() {
        let other = NIScrollContainerGeometry(
            x: main.x,
            y: main.y,
            width: main.width,
            height: main.height,
            contentWidth: main.contentWidth,
            contentHeight: main.contentHeight,
            offsetX: main.offsetX,
            offsetY: 300
        )
        let live = NIScrollContainerGeometry(
            x: main.x,
            y: main.y,
            width: main.width,
            height: main.height,
            contentWidth: main.contentWidth,
            contentHeight: main.contentHeight,
            offsetX: main.offsetX,
            offsetY: 200
        )
        let result = NIScrollContainerMatching.match(
            descriptors: [
                "first": NIScrollContainerDescriptor(geometry: main),
                "second": NIScrollContainerDescriptor(geometry: other, order: 1),
            ],
            candidates: [NIScrollContainerCandidate(key: 1, geometry: live)],
            tolerance: 1
        )
        XCTAssertEqual(result.failures["first"], .sharedCandidate)
        XCTAssertEqual(result.failures["second"], .sharedCandidate)
        XCTAssertTrue(result.matches.isEmpty)
    }

    func testCurrentOffsetParticipatesInMatching() {
        func scrolled(to offsetY: Double) -> NIScrollContainerGeometry {
            NIScrollContainerGeometry(
                x: main.x,
                y: main.y,
                width: main.width,
                height: main.height,
                contentWidth: main.contentWidth,
                contentHeight: main.contentHeight,
                offsetX: main.offsetX,
                offsetY: offsetY
            )
        }
        let descriptors = [
            "main": NIScrollContainerDescriptor(geometry: main),
        ]

        XCTAssertEqual(
            NIScrollContainerMatching.match(
                descriptors: descriptors,
                candidates: [
                    NIScrollContainerCandidate(key: 1, geometry: scrolled(to: 0)),
                    NIScrollContainerCandidate(key: 2, geometry: main),
                ],
                tolerance: 1
            ).matches,
            ["main": 2]
        )

        let moved = NIScrollContainerMatching.match(
            descriptors: descriptors,
            candidates: [
                NIScrollContainerCandidate(key: 1, geometry: scrolled(to: 0)),
                NIScrollContainerCandidate(key: 2, geometry: scrolled(to: 300)),
            ],
            tolerance: 1
        )
        XCTAssertTrue(moved.matches.isEmpty)
        XCTAssertEqual(moved.failures["main"], .ambiguous)
    }

    func testMatchesTheOnlyScrollerThatMovedAfterTheWebSampledIt() {
        let live = NIScrollContainerGeometry(
            x: main.x,
            y: main.y,
            width: main.width,
            height: main.height,
            contentWidth: main.contentWidth,
            contentHeight: main.contentHeight,
            offsetX: main.offsetX,
            offsetY: main.offsetY + 10
        )

        XCTAssertEqual(
            NIScrollContainerMatching.match(
                descriptors: [
                    "main": NIScrollContainerDescriptor(geometry: main),
                ],
                candidates: [NIScrollContainerCandidate(key: 1, geometry: live)],
                tolerance: 1
            ),
            NIScrollContainerMatchResult(matches: ["main": 1], failures: [:])
        )
        XCTAssertFalse(
            NIScrollContainerMatching.offsetsMatch(main, live, tolerance: 1)
        )

        let resized = NIScrollContainerGeometry(
            x: main.x,
            y: main.y,
            width: main.width,
            height: main.height,
            contentWidth: main.contentWidth,
            contentHeight: main.contentHeight + 40,
            offsetX: main.offsetX,
            offsetY: main.offsetY + 10
        )
        XCTAssertEqual(
            NIScrollContainerMatching.match(
                descriptors: [
                    "main": NIScrollContainerDescriptor(geometry: main),
                ],
                candidates: [
                    NIScrollContainerCandidate(key: 1, geometry: resized),
                ],
                tolerance: 1
            ).failures["main"],
            .missing
        )
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

    func testEqualScrollportsBindTheTopmostScrollView() {
        let descriptor = NIScrollContainerDescriptor(geometry: main)
        let first = NIScrollContainerCandidate(key: 3, geometry: main)
        let second = NIScrollContainerCandidate(key: 7, geometry: main)

        for candidates in [[first, second], [second, first]] {
            let result = NIScrollContainerMatching.match(
                descriptors: ["main": descriptor],
                candidates: candidates,
                tolerance: 1
            )
            XCTAssertEqual(result.matches, ["main": second.key])
            XCTAssertTrue(result.failures.isEmpty)
        }

        let moving = NIScrollContainerGeometry(
            x: main.x,
            y: main.y,
            width: main.width,
            height: main.height,
            contentWidth: main.contentWidth,
            contentHeight: main.contentHeight,
            offsetX: main.offsetX,
            offsetY: 248
        )
        let movingDescriptor = NIScrollContainerDescriptor(geometry: moving)
        let movingCandidate = NIScrollContainerCandidate(
            key: first.key,
            geometry: moving
        )

        XCTAssertEqual(
            NIScrollContainerMatching.match(
                descriptors: ["main": movingDescriptor],
                candidates: [second, movingCandidate],
                tolerance: 1
            ).matches,
            ["main": first.key]
        )

        let restored = NIScrollContainerMatching.match(
            descriptors: ["main": descriptor],
            candidates: [first, second],
            tolerance: 1
        )
        XCTAssertEqual(restored.matches, ["main": second.key])
    }

    func testAnOptionalClipWithoutAScrollViewDoesNotBlockTheScrollerInside() {
        let view = NIScrollContainerGeometry(
            x: 0,
            y: 0,
            width: 402,
            height: 874,
            contentWidth: 804,
            contentHeight: 874,
            offsetX: 0,
            offsetY: 0
        )
        let page = NIScrollContainerGeometry(
            x: 0,
            y: 62,
            width: 402,
            height: 714,
            contentWidth: 402,
            contentHeight: 1388,
            offsetX: 0,
            offsetY: 0
        )
        let descriptors = [
            "view": NIScrollContainerDescriptor(geometry: view),
            "page": NIScrollContainerDescriptor(
                geometry: page,
                scrollPath: ["view"]
            ),
        ]
        let candidates = [NIScrollContainerCandidate(key: 0, geometry: page)]

        XCTAssertEqual(
            NIScrollContainerMatching.match(
                descriptors: descriptors,
                candidates: candidates,
                tolerance: 1.5,
                optional: ["view"]
            ),
            NIScrollContainerMatchResult(matches: ["page": 0], failures: [:])
        )

        let strict = NIScrollContainerMatching.match(
            descriptors: descriptors,
            candidates: candidates,
            tolerance: 1.5
        )
        XCTAssertEqual(strict.failures["view"], .missing)
        XCTAssertEqual(strict.failures["page"], .missing)
    }

    func testAnOptionalContainerWithLookalikesBindsTheTopmost() {
        let result = NIScrollContainerMatching.match(
            descriptors: ["main": NIScrollContainerDescriptor(geometry: main)],
            candidates: [
                NIScrollContainerCandidate(key: 1, geometry: main),
                NIScrollContainerCandidate(key: 2, geometry: main),
            ],
            tolerance: 1,
            optional: ["main"]
        )
        XCTAssertEqual(result.matches, ["main": 2])
    }
}
