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

    func testAcceptsAScrollerInAStickyBoxAndRefusesOneThatCannotStickThere() {
        func scroller(_ sticky: [String: Any]) -> [[String: Any]] {
            [[
                "id": "chips",
                "rect": ["x": 0, "y": 300, "w": 400, "h": 80],
                "scrollPath": [],
                "coordinateSpace": "document",
                "contentWidth": 800,
                "contentHeight": 80,
                "offsetX": 0,
                "offsetY": 0,
                "sticky": sticky,
            ]]
        }
        let bar: [String: Any] = [
            "natural": ["x": 0, "y": 300, "w": 400, "h": 80],
            "bounds": ["x": 0, "y": 0, "w": 400, "h": 3000],
            "top": 0,
        ]
        var elsewhere = bar
        elsewhere["scroller"] = "pane"

        XCTAssertNil(NILayoutValidation.error(components: components, scrollContainers: scroller(bar), order: ["map"], exclusions: [:], cutouts: [:]))
        XCTAssertEqual(
            NILayoutValidation.error(components: components, scrollContainers: scroller(elsewhere), order: ["map"], exclusions: [:], cutouts: [:]),
            "scroll container 'chips' has an invalid sticky"
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

        var turned = components
        turned[0]["transform"] = ["size": [100, 80], "matrix": [1, 0, 0.5, 1, 0, 0]]
        XCTAssertNil(NILayoutValidation.error(components: turned, order: ["map"], exclusions: [:], cutouts: [:]))
        turned[0]["transform"] = ["size": [100, 80], "matrix": [1, 0, 0, 1]]
        XCTAssertEqual(
            NILayoutValidation.error(components: turned, order: ["map"], exclusions: [:], cutouts: [:]),
            "component 'map' has an invalid transform"
        )
    }

    func testPortalIsOptionalNonEmptyStringIdentifier() {
        func error(_ portal: Any) -> String? {
            var item = components
            item[0]["portal"] = portal
            return NILayoutValidation.error(
                components: item,
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            )
        }

        XCTAssertNil(error("card:weather"))
        XCTAssertEqual(error(""), "component 'map' has an invalid portal")
        XCTAssertEqual(error(42), "component 'map' has an invalid portal")
    }

    func testTransitionTagIsOptionalNonEmptyStringIdentifier() {
        func error(_ transitionTag: Any) -> String? {
            var item = components
            item[0]["transitionTag"] = transitionTag
            return NILayoutValidation.error(
                components: item,
                order: ["map"],
                exclusions: [:],
                cutouts: [:]
            )
        }

        XCTAssertNil(error("hero:card"))
        XCTAssertNil(error(NSNull()))
        XCTAssertEqual(error(""), "component 'map' has an invalid transitionTag")
        XCTAssertEqual(error(42), "component 'map' has an invalid transitionTag")
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
}
