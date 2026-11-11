#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsContainerTouchTests: XCTestCase {
        /// Takes touches only on a capsule in its middle, as a floating tab bar does.
        private final class Capsule: UIView {
            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                bounds.insetBy(dx: 64, dy: 0).contains(point) ? self : nil
            }
        }

        private let container = NativeIslandsContainer(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        private let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        private let bar = Capsule()

        override func setUp() {
            container.attach(webView: webView)
        }

        override func tearDown() {
            container.detachWebView()
        }

        /// Lays out `views` full width, bottom to top, each from its y to the bottom of the screen.
        private func place(_ views: KeyValuePairs<String, (view: UIView, y: CGFloat)>) {
            for (id, island) in views {
                container.registerIsland(id: id, view: island.view, accessibility: .native)
            }
            XCTAssertTrue(container.applyLedger(
                components: views.map { id, island in
                    IslandComponent(
                        id: id,
                        rect: IslandRect(x: 0, y: island.y, width: 402, height: 874 - island.y, cornerRadii: NICornerRadii(uniform: 0)),
                        scrollPath: [],
                        plane: .overlay,
                        coordinateSpace: .viewport,
                        interactive: true,
                        active: true
                    )
                },
                scrollContainers: [],
                order: views.map(\.key),
                exclusions: [:],
                cutouts: [:]
            ).isEmpty)
        }

        func testTouchesAnIslandDeclinesReachThePage() throws {
            place(["tabs": (bar, 791)])

            let host = try XCTUnwrap(container.hosts["tabs"]?.view)
            let gutter = try XCTUnwrap(webView.hitTest(CGPoint(x: 30, y: 820), with: nil))
            XCTAssertTrue(gutter === webView || gutter.isDescendant(of: webView))
            XCTAssertFalse(gutter.isDescendant(of: host))
            XCTAssertTrue(webView.hitTest(CGPoint(x: 200, y: 820), with: nil) === bar)
        }

        func testTouchesAnIslandDeclinesReachTheIslandUnderIt() {
            let list = UIView()
            place(["list": (list, 0), "tabs": (bar, 791)])

            XCTAssertTrue(webView.hitTest(CGPoint(x: 30, y: 820), with: nil) === list)
            XCTAssertTrue(webView.hitTest(CGPoint(x: 200, y: 820), with: nil) === bar)
        }
    }
#endif
