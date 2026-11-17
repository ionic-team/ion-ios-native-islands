import CoreGraphics
import XCTest
@testable import IONNativeIslandsLib

final class NIStickyTests: XCTestCase {
    private let header = NISticky(
        scroller: "pane",
        natural: CGRect(x: 0, y: 0, width: 400, height: 60),
        bounds: CGRect(x: 0, y: 0, width: 400, height: 2000),
        top: 0
    )

    func testAnEmptyStickyBoxIsReadAndSticksWhatOverflowsIt() {
        // A sticky box with no height of its own still carries what overflows it as it sticks.
        let sticky = NISticky([
            "scroller": "pane",
            "natural": ["x": 0, "y": 100, "w": 400, "h": 0],
            "bounds": ["x": 0, "y": 0, "w": 400, "h": 2000],
            "top": 0,
        ])

        XCTAssertEqual(sticky?.offset(in: CGRect(x: 0, y: 300, width: 400, height: 800)), CGVector(dx: 0, dy: 200))
    }

    func testAHeaderSticksToTheTopOfItsScrollport() {
        XCTAssertEqual(header.offset(in: CGRect(x: 0, y: 0, width: 400, height: 800)), .zero)
        XCTAssertEqual(header.offset(in: CGRect(x: 0, y: 300, width: 400, height: 800)), CGVector(dx: 0, dy: 300))
    }

    func testAStickyBoxInsideAnotherSticksInsideTheBlockTheOuterOneHasMoved() {
        // A 300 high sidebar stuck at the top until its block ends, holding a box sticking 20 below.
        let sidebar = NISticky(
            scroller: "pane",
            natural: CGRect(x: 0, y: 100, width: 400, height: 300),
            bounds: CGRect(x: 0, y: 0, width: 400, height: 600),
            top: 0
        )
        let label = NISticky(
            scroller: "pane",
            natural: CGRect(x: 0, y: 350, width: 400, height: 40),
            bounds: CGRect(x: 0, y: 100, width: 400, height: 300),
            top: 20,
            within: sidebar
        )

        XCTAssertEqual(label.offset(in: CGRect(x: 0, y: 500, width: 400, height: 800)), CGVector(dx: 0, dy: 200))
        XCTAssertEqual(label.offset(in: CGRect(x: 0, y: 560, width: 400, height: 800)), CGVector(dx: 0, dy: 210))
    }

    func testAStickyBoxStaysInsideItsContainingBlock() {
        let section = NISticky(
            scroller: "pane",
            natural: header.natural,
            bounds: CGRect(x: 0, y: 0, width: 400, height: 500),
            top: 0
        )

        XCTAssertEqual(section.offset(in: CGRect(x: 0, y: 900, width: 400, height: 800)), CGVector(dx: 0, dy: 440))
    }

    func testAFooterSticksToTheBottomAndTopWinsWhenBothApply() {
        let footer = NISticky(
            scroller: "pane",
            natural: CGRect(x: 0, y: 1940, width: 400, height: 60),
            bounds: header.bounds,
            bottom: 0
        )
        var both = header
        both.bottom = 0

        XCTAssertEqual(footer.offset(in: CGRect(x: 0, y: 0, width: 400, height: 800)), CGVector(dx: 0, dy: -1200))
        XCTAssertEqual(footer.offset(in: CGRect(x: 0, y: 1200, width: 400, height: 800)), .zero)
        XCTAssertEqual(both.offset(in: CGRect(x: 0, y: 300, width: 400, height: 800)), CGVector(dx: 0, dy: 300))
    }

    func testStickyDescriptionsAreValidatedAgainstTheRegion() {
        let sticky: [String: Any] = [
            "scroller": "pane",
            "natural": ["x": 0, "y": 0, "w": 400, "h": 60, "r": [0, 0, 0, 0]],
            "bounds": ["x": 0, "y": 0, "w": 400, "h": 2000, "r": [0, 0, 0, 0]],
            "top": 0,
        ]
        func error(_ sticky: [String: Any], scrollPath: [String], space: String = "document") -> String? {
            NILayoutValidation.error(
                components: [[
                    "id": "map",
                    "type": "acme.map",
                    "active": true,
                    "interactive": true,
                    "scrollPath": scrollPath,
                    "plane": "overlay",
                    "coordinateSpace": "document",
                    "rect": ["x": 0, "y": 0, "w": 100, "h": 80, "r": [0, 0, 0, 0]],
                ]],
                scrollContainers: scrollPath.map { id in
                    [
                        "id": id,
                        "scrollPath": Array(scrollPath.prefix { $0 != id }),
                        "rect": ["x": 0, "y": 0, "w": 400, "h": 800],
                        "contentWidth": 400,
                        "contentHeight": 2000,
                        "offsetX": 0,
                        "offsetY": 0,
                    ]
                },
                order: ["map"],
                exclusions: [:],
                cutouts: [
                    "map": [[
                        "rect": ["x": 0, "y": 0, "w": 400, "h": 60, "r": [0, 0, 0, 0]],
                        "scrollPath": space == "viewport" ? [] : scrollPath,
                        "coordinateSpace": space,
                        "sticky": sticky,
                    ]],
                ]
            )
        }
        var documentSticky = sticky
        documentSticky["scroller"] = nil
        var textInset = sticky
        textInset["top"] = "0"

        XCTAssertNil(error(sticky, scrollPath: ["pane"]))
        XCTAssertNil(error(documentSticky, scrollPath: []))
        XCTAssertEqual(error(sticky, scrollPath: ["pane", "inner"]), "cutout 0 for 'map' has an invalid sticky")
        XCTAssertEqual(error(documentSticky, scrollPath: [], space: "viewport"), "cutout 0 for 'map' has an invalid sticky")
        XCTAssertEqual(error(textInset, scrollPath: ["pane"]), "cutout 0 for 'map' has an invalid sticky")
    }
}
