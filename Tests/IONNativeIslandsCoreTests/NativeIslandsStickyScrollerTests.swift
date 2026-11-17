#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsStickyScrollerTests: XCTestCase {
        func testAScrollerInAStickyBarMovesWithTheBarAndSoDoWhatItHoldsAndItsScrollport() throws {
            let container = NativeIslandsContainer(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            let square = NICornerRadii(uniform: 0)
            let chip = IslandComponent(
                id: "chip",
                rect: IslandRect(x: 20, y: 310, width: 100, height: 60, cornerRadii: square),
                scrollPath: ["chips"],
                plane: .overlay,
                coordinateSpace: .document,
                interactive: true,
                active: true
            )
            _ = container.applyLedger(
                components: [chip],
                scrollContainers: [IslandScrollContainer(
                    id: "chips",
                    rect: IslandRect(x: 0, y: 300, width: 400, height: 80, cornerRadii: square),
                    scrollPath: [],
                    contentWidth: 800,
                    contentHeight: 80,
                    offsetX: 0,
                    offsetY: 0,
                    sticky: NISticky(
                        scroller: nil,
                        natural: CGRect(x: 0, y: 300, width: 400, height: 80),
                        bounds: CGRect(x: 0, y: 0, width: 400, height: 3000),
                        top: 0
                    )
                )],
                order: ["chip"],
                exclusions: [:],
                cutouts: [:]
            )
            // Scrolled 500 down the document, the bar has stuck to the top of the screen.
            webView.scrollView.contentOffset = CGPoint(x: 0, y: 500)
            let frame = container.motions.frame(atPageTime: 0)

            XCTAssertEqual(try XCTUnwrap(container.screenRect(of: chip, in: frame)).y, 10)
            XCTAssertEqual(try XCTUnwrap(container.screenClips(id: "chip", in: frame).first).y, 0)
        }
    }
#endif
