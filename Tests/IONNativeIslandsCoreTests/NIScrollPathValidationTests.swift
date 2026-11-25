import XCTest
@testable import IONNativeIslandsLib

final class NIScrollPathValidationTests: XCTestCase {
    private let components: [[String: Any]] = [
        [
            "id": "map",
            "type": "acme.map",
            "active": true,
            "interactive": true,
            "scrollPath": [],
            "plane": "underlay",
            "coordinateSpace": "document",
            "rect": ["x": 0, "y": 0, "w": 100, "h": 80, "r": [12, 12, 12, 12]],
        ],
    ]

    func testAcceptsAComponentInsideOneScrollContainer() {
        var nested = components
        nested[0]["scrollPath"] = ["feed"]

        XCTAssertNil(
            NILayoutValidation.error(
                components: nested,
                scrollContainers: [
                    [
                        "id": "feed",
                        "scrollPath": [],
                        "rect": [
                            "x": 0,
                            "y": 0,
                            "w": 320,
                            "h": 480,
                        ],
                        "contentWidth": 640,
                        "contentHeight": 100_000,
                        "offsetX": -40,
                        "offsetY": -120,
                    ],
                ],
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            )
        )
    }

    func testRejectsUnknownAndMalformedScrollContainers() {
        var nested = components
        nested[0]["scrollPath"] = ["missing"]
        XCTAssertEqual(
            NILayoutValidation.error(
                components: nested,
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            ),
            "component 'map' has an invalid scroll path"
        )

        nested[0]["scrollPath"] = ["feed"]
        XCTAssertEqual(
            NILayoutValidation.error(
                components: nested,
                scrollContainers: [
                    [
                        "id": "feed",
                        "scrollPath": [],
                        "rect": [
                            "x": 0,
                            "y": 0,
                            "w": 320,
                            "h": 480,
                        ],
                        "contentWidth": 100,
                        "contentHeight": 960,
                        "offsetX": 0,
                        "offsetY": 0,
                    ],
                ],
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            ),
            "scroll container 'feed' has invalid content size"
        )
    }

    func testAcceptsNestedScrollPath() {
        var nested = components
        nested[0]["scrollPath"] = ["outer", "inner"]

        XCTAssertNil(
            NILayoutValidation.error(
                components: nested,
                scrollContainers: [
                    [
                        "id": "outer",
                        "scrollPath": [],
                        "rect": ["x": 0, "y": 0, "w": 320, "h": 480],
                        "contentWidth": 320,
                        "contentHeight": 960,
                        "offsetX": 0,
                        "offsetY": 40,
                    ],
                    [
                        "id": "inner",
                        "scrollPath": ["outer"],
                        "rect": ["x": 0, "y": 200, "w": 320, "h": 240],
                        "contentWidth": 320,
                        "contentHeight": 720,
                        "offsetX": 0,
                        "offsetY": 20,
                    ],
                ],
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            )
        )
    }

    func testRejectsMalformedNestedScrollPath() {
        var nested = components
        nested[0]["scrollPath"] = ["inner", "outer"]

        XCTAssertEqual(
            NILayoutValidation.error(
                components: nested,
                scrollContainers: [
                    [
                        "id": "outer",
                        "scrollPath": [],
                        "rect": ["x": 0, "y": 0, "w": 320, "h": 480],
                        "contentWidth": 320,
                        "contentHeight": 960,
                        "offsetX": 0,
                        "offsetY": 0,
                    ],
                    [
                        "id": "inner",
                        "scrollPath": ["outer"],
                        "rect": ["x": 0, "y": 200, "w": 320, "h": 240],
                        "contentWidth": 320,
                        "contentHeight": 720,
                        "offsetX": 0,
                        "offsetY": 0,
                    ],
                ],
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            ),
            "component 'map' has an invalid scroll path"
        )
    }
}
