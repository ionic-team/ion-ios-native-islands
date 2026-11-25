#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsContainerViewportTests: XCTestCase {
        func testAViewportIslandUnderTheWebViewStaysFixedAsTheDocumentScrolls() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            webView.scrollView.contentSize = CGSize(width: 402, height: 2000)
            container.registerIsland(id: "options", view: UIView(), accessibility: .native)
            let options = IslandComponent(
                id: "options",
                rect: IslandRect(x: 20, y: 300, width: 362, height: 450, cornerRadii: NICornerRadii(uniform: 0)),
                scrollPath: [],
                plane: .underlay,
                coordinateSpace: .viewport,
                interactive: true,
                active: true
            )
            XCTAssertTrue(container.applyLedger(
                components: [options],
                scrollContainers: [],
                order: ["options"],
                exclusions: [:],
                cutouts: [:]
            ).isEmpty)
            let host = try XCTUnwrap(container.hosts["options"]?.view)
            XCTAssertTrue(host.superview === container.underlayPlane)
            let expected = CGRect(x: 20, y: 300, width: 362, height: 450)
            for offset in [CGFloat(0), 120, 360, 0] {
                webView.scrollView.contentOffset = CGPoint(x: 0, y: offset)
                XCTAssertEqual(container.convert(host.bounds, from: host), expected)
                XCTAssertFalse(host.isHidden)
            }
        }

        func testIslandInAPaneFixedToTheViewportFollowsThePaneNotTheDocument() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            webView.scrollView.contentSize = CGSize(width: 402, height: 2000)
            webView.scrollView.contentOffset = CGPoint(x: 0, y: 300)
            let pane = UIScrollView(frame: CGRect(x: 0, y: 80, width: 402, height: 700))
            pane.contentSize = CGSize(width: 402, height: 2000)
            webView.addSubview(pane)
            let preview = UIView()
            container.registerIsland(id: "preview", view: preview, accessibility: .native)
            let label = IslandRegion(
                rect: IslandRect(x: 20, y: 300, width: 100, height: 20, cornerRadii: NICornerRadii(uniform: 0)),
                scrollPath: ["pane"],
                coordinateSpace: .viewport,
                sticky: nil
            )
            XCTAssertTrue(container.applyLedger(
                components: [IslandComponent(
                    id: "preview",
                    rect: IslandRect(x: 20, y: 300, width: 100, height: 100, cornerRadii: NICornerRadii(uniform: 0)),
                    scrollPath: ["pane"],
                    plane: .overlay,
                    coordinateSpace: .viewport,
                    interactive: true,
                    active: true
                )],
                scrollContainers: [IslandScrollContainer(
                    id: "pane",
                    rect: IslandRect(x: 0, y: 80, width: 402, height: 700, cornerRadii: NICornerRadii(uniform: 0)),
                    coordinateSpace: .viewport,
                    scrollPath: [],
                    contentWidth: 402,
                    contentHeight: 2000,
                    offsetX: 0,
                    offsetY: 0
                )],
                order: ["preview"],
                exclusions: [:],
                cutouts: ["preview": [label]]
            ).isEmpty)
            let host = try XCTUnwrap(container.hosts["preview"]?.view)
            let contentHost = try XCTUnwrap(container.hosts["preview"]?.content)
            let placed = CGRect(x: 20, y: 300, width: 100, height: 100)
            XCTAssertEqual(container.convert(host.bounds, from: host), placed)

            webView.scrollView.contentOffset = .zero
            XCTAssertEqual(container.convert(host.bounds, from: host), placed, "the document scrolling does not move it")

            pane.contentOffset = CGPoint(x: 0, y: 100)
            XCTAssertEqual(
                container.convert(host.bounds, from: host),
                placed.offsetBy(dx: 0, dy: -100),
                "the pane scrolling does"
            )
            let mask = try XCTUnwrap(contentHost.layer.mask as? CAShapeLayer)
            let path = try XCTUnwrap(mask.path)
            XCTAssertFalse(
                path.contains(container.convert(CGPoint(x: 60, y: 210), to: contentHost), using: .evenOdd),
                "and its cutout moves with it"
            )
            XCTAssertTrue(path.contains(container.convert(CGPoint(x: 60, y: 250), to: contentHost), using: .evenOdd))
        }
    }
#endif
