import XCTest
@testable import IONNativeIslandsLib

final class NILayoutValidationTests: XCTestCase {
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

    func testAcceptsSeparateExclusionsAndCutouts() {
        XCTAssertNil(
            NILayoutValidation.error(
                components: components,
                order: ["map"],
                exclusions: [
                    "map": [[
                        "rect": ["x": 10, "y": 10, "w": 20, "h": 20],
                        "scrollPath": [],
                        "coordinateSpace": "document",
                    ]],
                ],
                cutouts: [
                    "map": [[
                        "rect": [
                            "x": 10, "y": 10, "w": 20, "h": 20, "r": [8, 8, 8, 8],
                        ],
                        "scrollPath": [],
                        "coordinateSpace": "viewport",
                    ]],
                ]
            )
        )
    }

    func testRejectsInvalidCutoutOwner() {
        XCTAssertEqual(
            NILayoutValidation.error(
                components: components,
                order: ["map"],
                exclusions: [:],
                cutouts: [
                    "missing": [[
                        "rect": ["x": 0, "y": 0, "w": 10, "h": 10],
                        "scrollPath": [],
                        "coordinateSpace": "document",
                    ]],
                ]
            ),
            "cutouts reference unknown component 'missing'"
        )
    }

    func testRejectsMalformedCutoutGeometry() {
        XCTAssertEqual(
            NILayoutValidation.error(
                components: components,
                order: ["map"],
                exclusions: [:],
                cutouts: [
                    "map": [[
                        "rect": ["x": 0, "y": 0, "w": -1, "h": 10],
                        "scrollPath": [],
                        "coordinateSpace": "document",
                    ]],
                ]
            ),
            "cutout 0 for 'map' is invalid"
        )
    }

    func testRequiresCompleteComponentStateAndActivePaintOrder() {
        var missingState = components
        missingState[0].removeValue(forKey: "interactive")
        XCTAssertEqual(
            NILayoutValidation.error(
                components: missingState,
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            ),
            "component 'map' interactive must be a boolean"
        )

        XCTAssertEqual(
            NILayoutValidation.error(
                components: components,
                order: [],
                exclusions: [:],
                cutouts: [:]
            ),
            "paint order must contain every active component and no inactive components"
        )
    }

    func testRequiresKnownPlaneAndCoordinateSpace() {
        var invalidPlane = components
        invalidPlane[0]["plane"] = "floating"
        XCTAssertEqual(
            NILayoutValidation.error(
                components: invalidPlane,
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            ),
            "component 'map' has an invalid plane"
        )

        var invalidCoordinateSpace = components
        invalidCoordinateSpace[0]["coordinateSpace"] = "screen"
        XCTAssertEqual(
            NILayoutValidation.error(
                components: invalidCoordinateSpace,
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            ),
            "component 'map' has an invalid coordinate space"
        )
    }

    func testPlaneAndCoordinateSpaceAreIndependent() {
        for (plane, coordinateSpace) in [
            ("underlay", "document"),
            ("underlay", "viewport"),
            ("overlay", "document"),
            ("overlay", "viewport"),
        ] {
            var component = components
            component[0]["plane"] = plane
            component[0]["coordinateSpace"] = coordinateSpace

            XCTAssertNil(
                NILayoutValidation.error(
                    components: component,
                    order: ["map"],
                    exclusions: [:],
                    cutouts: [:]
                )
            )
        }
    }

    func testOpacityIsOptionalAndLiesBetweenZeroAndOne() {
        func error(_ opacity: Any) -> String? {
            var faded = components
            faded[0]["opacity"] = opacity
            return NILayoutValidation.error(
                components: faded,
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            )
        }

        XCTAssertNil(error(0.5))
        XCTAssertNil(error(0))
        XCTAssertEqual(error(1.5), "component 'map' has an invalid opacity")
        XCTAssertEqual(error("0.5"), "component 'map' has an invalid opacity")
        XCTAssertEqual(error(true), "component 'map' has an invalid opacity")
    }

    func testViewportComponentsAndRegionsCanSitInAPaneFixedToTheViewport() {
        var viewport = components
        viewport[0]["plane"] = "overlay"
        viewport[0]["coordinateSpace"] = "viewport"
        viewport[0]["scrollPath"] = ["feed"]
        var pane: [String: Any] = [
            "id": "feed",
            "scrollPath": [],
            "coordinateSpace": "viewport",
            "rect": ["x": 0, "y": 0, "w": 320, "h": 480],
            "contentWidth": 320,
            "contentHeight": 960,
            "offsetX": 0,
            "offsetY": 0,
        ]
        let header: [String: Any] = [
            "rect": ["x": 0, "y": 0, "w": 320, "h": 40],
            "scrollPath": ["feed"],
            "coordinateSpace": "viewport",
        ]
        let error = {
            NILayoutValidation.error(
                components: viewport,
                scrollContainers: [pane],
                order: ["map"],
                exclusions: ["map": [header]],
                cutouts: ["map": [header]]
            )
        }

        XCTAssertNil(error())
        pane["coordinateSpace"] = "screen"
        XCTAssertEqual(error(), "scroll container 'feed' has an invalid coordinateSpace")
    }

    func testRegionsRequireDescriptorsAndKnownCoordinateSpace() {
        XCTAssertEqual(
            NILayoutValidation.error(
                components: components,
                order: ["map"],
                exclusions: [
                    "map": [[
                        "rect": ["x": 0, "y": 0, "w": 20, "h": 20],
                        "scrollPath": [],
                    ]],
                ],
                cutouts: [:]
            ),
            "exclusion 0 for 'map' is invalid"
        )

        XCTAssertEqual(
            NILayoutValidation.error(
                components: components,
                order: ["map"],
                exclusions: [:],
                cutouts: [
                    "map": [[
                        "rect": ["x": 0, "y": 0, "w": 20, "h": 20],
                        "scrollPath": ["feed"],
                        "coordinateSpace": "viewport",
                    ]],
                ]
            ),
            "cutout 0 for 'map' is invalid"
        )
    }

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
