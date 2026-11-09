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

    private let inner = NIScrollContainerGeometry(
        x: 16,
        y: 180,
        width: 364,
        height: 220,
        contentWidth: 364,
        contentHeight: 660,
        offsetX: 0,
        offsetY: 40
    )

    private func match(
        _ descriptors: [String: NIScrollContainerDescriptor],
        _ candidates: [NIScrollContainerCandidate],
        tolerance: Double = 1,
        optional: Set<String> = []
    )
        -> NIScrollContainerMatchResult {
        NIScrollContainerMatching.match(
            descriptors: descriptors,
            candidates: candidates,
            tolerance: tolerance,
            optional: optional
        )
    }

    func testALoneScrollViewWithinToleranceMatchesAndNoneIsMissing() {
        let near = NIScrollContainerGeometry(
            x: 16.5,
            y: 71.5,
            width: 364,
            height: 514,
            contentWidth: 364,
            contentHeight: 1148.5,
            offsetX: 0,
            offsetY: 120.5
        )
        let bounced = main.with(contentWidth: 900, offsetX: -40, offsetY: -120)
        for (sent, drawn) in [(main, near), (bounced, bounced)] {
            XCTAssertEqual(
                match(["main": NIScrollContainerDescriptor(geometry: sent)], [NIScrollContainerCandidate(key: 4, geometry: drawn)]),
                NIScrollContainerMatchResult(matches: ["main": 4], failures: [:])
            )
        }
        XCTAssertEqual(match(["main": NIScrollContainerDescriptor(geometry: main)], []).failures["main"], .missing)
    }

    func testLookalikeScrollersPairWithScrollViewsFromTheTop() {
        let descriptors = [
            "lower": NIScrollContainerDescriptor(geometry: main, order: 1),
            "upper": NIScrollContainerDescriptor(geometry: main, order: 0),
        ]
        let two = match(descriptors, [
            NIScrollContainerCandidate(key: 3, geometry: main),
            NIScrollContainerCandidate(key: 7, geometry: main),
        ])
        XCTAssertEqual(two.matches, ["upper": 7, "lower": 3])
        XCTAssertTrue(two.failures.isEmpty)

        let one = match(descriptors, [NIScrollContainerCandidate(key: 1, geometry: main)])
        XCTAssertEqual(one.matches, ["upper": 1])
        XCTAssertEqual(one.failures, ["lower": .sharedCandidate])
    }

    func testDifferentScrollersNeverShareAScrollView() {
        let result = match(
            [
                "first": NIScrollContainerDescriptor(geometry: main),
                "second": NIScrollContainerDescriptor(geometry: main.with(offsetY: 300), order: 1),
            ],
            [NIScrollContainerCandidate(key: 1, geometry: main.with(offsetY: 200))]
        )
        XCTAssertEqual(result.failures["first"], .sharedCandidate)
        XCTAssertEqual(result.failures["second"], .sharedCandidate)
        XCTAssertTrue(result.matches.isEmpty)
    }

    func testCurrentOffsetParticipatesInMatching() {
        let descriptors = ["main": NIScrollContainerDescriptor(geometry: main)]
        XCTAssertEqual(
            match(descriptors, [
                NIScrollContainerCandidate(key: 1, geometry: main.with(offsetY: 0)),
                NIScrollContainerCandidate(key: 2, geometry: main),
            ]).matches,
            ["main": 2]
        )

        let moved = match(descriptors, [
            NIScrollContainerCandidate(key: 1, geometry: main.with(offsetY: 0)),
            NIScrollContainerCandidate(key: 2, geometry: main.with(offsetY: 300)),
        ])
        XCTAssertTrue(moved.matches.isEmpty)
        XCTAssertEqual(moved.failures["main"], .ambiguous)
    }

    func testMatchesTheOnlyScrollerThatMovedAfterTheWebSampledIt() {
        let descriptors = ["main": NIScrollContainerDescriptor(geometry: main)]
        let live = main.with(offsetY: main.offsetY + 10)
        XCTAssertEqual(
            match(descriptors, [NIScrollContainerCandidate(key: 1, geometry: live)]),
            NIScrollContainerMatchResult(matches: ["main": 1], failures: [:])
        )
        XCTAssertFalse(NIScrollContainerMatching.offsetsMatch(main, live, tolerance: 1))

        let resized = live.with(contentHeight: main.contentHeight + 40)
        XCTAssertEqual(match(descriptors, [NIScrollContainerCandidate(key: 1, geometry: resized)]).failures["main"], .missing)
    }

    func testANestedScrollerMatchesItsScrollViewByAncestryOrUniqueGeometry() {
        let descriptors = [
            "outer": NIScrollContainerDescriptor(geometry: main),
            "inner": NIScrollContainerDescriptor(geometry: inner, scrollPath: ["outer"]),
        ]
        let outer = NIScrollContainerCandidate(key: 2, geometry: main)
        let nested = NIScrollContainerCandidate(key: 4, geometry: inner, ancestorKeys: [2])
        let flat = NIScrollContainerCandidate(key: 4, geometry: inner, ancestorKeys: [])
        let stray = NIScrollContainerCandidate(key: 6, geometry: inner, ancestorKeys: [])
        for candidates in [[outer, nested], [outer, flat], [outer, nested, stray]] {
            let result = match(descriptors, candidates)
            XCTAssertEqual(result.matches, ["outer": 2, "inner": 4])
            XCTAssertTrue(result.failures.isEmpty)
        }
    }

    func testEqualScrollportsBindTheTopmostScrollView() {
        let descriptor = NIScrollContainerDescriptor(geometry: main)
        let first = NIScrollContainerCandidate(key: 3, geometry: main)
        let second = NIScrollContainerCandidate(key: 7, geometry: main)
        for candidates in [[first, second], [second, first]] {
            let result = match(["main": descriptor], candidates)
            XCTAssertEqual(result.matches, ["main": second.key])
            XCTAssertTrue(result.failures.isEmpty)
        }

        let moving = main.with(offsetY: 248)
        XCTAssertEqual(
            match(
                ["main": NIScrollContainerDescriptor(geometry: moving)],
                [second, NIScrollContainerCandidate(key: first.key, geometry: moving)]
            ).matches,
            ["main": first.key]
        )
        XCTAssertEqual(match(["main": descriptor], [first, second]).matches, ["main": second.key])
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
            "page": NIScrollContainerDescriptor(geometry: page, scrollPath: ["view"]),
        ]
        let candidates = [NIScrollContainerCandidate(key: 0, geometry: page)]
        XCTAssertEqual(
            match(descriptors, candidates, tolerance: 1.5, optional: ["view"]),
            NIScrollContainerMatchResult(matches: ["page": 0], failures: [:])
        )

        let strict = match(descriptors, candidates, tolerance: 1.5)
        XCTAssertEqual(strict.failures["view"], .missing)
        XCTAssertEqual(strict.failures["page"], .missing)
    }

    func testAnOptionalContainerWithLookalikesBindsTheTopmost() {
        let result = match(
            ["main": NIScrollContainerDescriptor(geometry: main)],
            [NIScrollContainerCandidate(key: 1, geometry: main), NIScrollContainerCandidate(key: 2, geometry: main)],
            optional: ["main"]
        )
        XCTAssertEqual(result.matches, ["main": 2])
    }
}

extension NIScrollContainerGeometry {
    fileprivate func with(
        contentWidth: Double? = nil,
        contentHeight: Double? = nil,
        offsetX: Double? = nil,
        offsetY: Double? = nil
    )
        -> NIScrollContainerGeometry {
        NIScrollContainerGeometry(
            x: x,
            y: y,
            width: width,
            height: height,
            contentWidth: contentWidth ?? self.contentWidth,
            contentHeight: contentHeight ?? self.contentHeight,
            offsetX: offsetX ?? self.offsetX,
            offsetY: offsetY ?? self.offsetY
        )
    }
}
