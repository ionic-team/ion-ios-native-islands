#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NIContainerPlaneMigrationTests: XCTestCase {
        func testAPaneIsPaintedWhereThePageSaysAmongTheIslandsUnderTheWebView() throws {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let container = NativeIslandsContainer(frame: window.bounds)
            window.addSubview(container)
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            container.registerIsland(id: "inside", view: UIView(), accessibility: .native)
            container.registerIsland(id: "under", view: UIView(), accessibility: .native)
            func component(_ id: String, scrollPath: [String]) -> IslandComponent {
                IslandComponent(
                    id: id,
                    rect: IslandRect(x: 20, y: 300, width: 100, height: 100, cornerRadii: NICornerRadii(uniform: 0)),
                    scrollPath: scrollPath,
                    plane: .underlay,
                    coordinateSpace: .document,
                    interactive: false,
                    active: true
                )
            }
            let pane = IslandScrollContainer(
                id: "pane",
                rect: IslandRect(x: 0, y: 100, width: 402, height: 600, cornerRadii: NICornerRadii(uniform: 0)),
                scrollPath: [],
                contentWidth: 402,
                contentHeight: 2000,
                offsetX: 0,
                offsetY: 0
            )
            func apply(_ panes: [String: IslandPane]) {
                _ = container.applyLedger(
                    components: [component("under", scrollPath: []), component("inside", scrollPath: ["pane"])],
                    scrollContainers: [pane],
                    order: ["under", "inside"],
                    exclusions: [:],
                    cutouts: [:],
                    panes: panes
                )
            }

            apply(["pane": IslandPane(color: .red, under: "inside")])
            let view = try XCTUnwrap(container.paneViews["pane"])
            XCTAssertEqual(view.backgroundColor, .red)
            XCTAssertEqual(view.frame, CGRect(x: 0, y: 100, width: 402, height: 600))
            let layers = container.documentLayer.subviews
            let index = try XCTUnwrap(layers.firstIndex(of: view))
            XCTAssertEqual(layers.firstIndex { $0 === container.hosts["under"] }, index - 1)
            XCTAssertEqual(layers.firstIndex { $0 === container.hosts["inside"] }, index + 1)

            apply(["pane": IslandPane(color: .red, under: nil)])
            XCTAssertTrue(container.documentLayer.subviews.last === view, "a pane no island is painted above covers them all")

            apply([:])
            XCTAssertNil(view.superview)
            XCTAssertTrue(container.paneViews.isEmpty)
        }

        func testPlaneChangesKeepContentInItsWindowAndPreserveOrderAndClipping() throws {
            final class Content: UIView {
                var detachments = 0
                override func didMoveToWindow() {
                    super.didMoveToWindow()
                    if window == nil { detachments += 1 }
                }
            }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let container = NativeIslandsContainer(frame: window.bounds)
            window.addSubview(container)
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }

            let content = Content()
            container.registerIsland(id: "preview", view: content, accessibility: .native)
            container.registerIsland(id: "peer", view: UIView(), accessibility: .native)
            let host = try XCTUnwrap(container.hosts["preview"])
            let contentHost = try XCTUnwrap(container.contentHosts["preview"])
            let peerHost = try XCTUnwrap(container.hosts["peer"])
            XCTAssertTrue(content.window === window)
            content.detachments = 0
            let cutout = IslandRegion(
                rect: IslandRect(x: 40, y: 320, width: 20, height: 20, cornerRadii: NICornerRadii(uniform: 0)),
                scrollPath: [],
                coordinateSpace: .viewport,
                sticky: nil
            )
            func component(_ id: String, plane: NIHostPlane, x: CGFloat) -> IslandComponent {
                IslandComponent(
                    id: id,
                    rect: IslandRect(x: x, y: 300, width: 100, height: 100, cornerRadii: NICornerRadii(uniform: 12)),
                    scrollPath: [],
                    plane: plane,
                    coordinateSpace: .viewport,
                    interactive: true,
                    active: true
                )
            }

            for plane in [NIHostPlane.underlay, .overlay, .underlay] {
                XCTAssertTrue(container.applyLedger(
                    components: [component("preview", plane: plane, x: 20), component("peer", plane: plane, x: 140)],
                    scrollContainers: [],
                    order: ["peer", "preview"],
                    exclusions: [:],
                    cutouts: ["preview": [cutout]]
                ).isEmpty)
                container.layoutIfNeeded()

                let parent = plane == .overlay ? container.overlayLayer : container.documentLayer
                XCTAssertTrue(container.hosts["preview"] === host)
                XCTAssertTrue(container.contentHosts["preview"] === contentHost)
                XCTAssertTrue(content.superview === contentHost)
                XCTAssertTrue(content.window === window)
                XCTAssertEqual(content.detachments, 0, "a plane change must not restart the native content lifetime")
                XCTAssertTrue(host.superview === parent)
                XCTAssertTrue(parent.subviews.first === peerHost)
                XCTAssertTrue(parent.subviews.last === host)
                XCTAssertEqual(container.convert(host.bounds, from: host), CGRect(x: 20, y: 300, width: 100, height: 100))
                XCTAssertEqual(host.layer.cornerRadius, 12)
                XCTAssertTrue(host.layer.masksToBounds)
                let mask = try XCTUnwrap(contentHost.layer.mask as? CAShapeLayer)
                let path = try XCTUnwrap(mask.path)
                XCTAssertFalse(path.contains(CGPoint(x: 25, y: 25), using: .evenOdd))
                XCTAssertTrue(path.contains(CGPoint(x: 50, y: 50), using: .evenOdd))
            }
        }
    }
#endif
