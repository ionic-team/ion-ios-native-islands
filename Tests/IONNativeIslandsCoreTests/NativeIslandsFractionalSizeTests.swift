#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsFractionalSizeTests: XCTestCase {
        func testPositiveFractionalDimensionsRemainVisible() throws {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            let container = NativeIslandsContainer(frame: window.bounds)
            let webView = WKWebView(frame: container.bounds)
            window.addSubview(webView)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            let content = UIView()
            container.registerIsland(id: "line", view: content, accessibility: .native)
            for size in [CGSize(width: 0.5, height: 20), CGSize(width: 20, height: 0.5)] {
                _ = container.applyLedger(
                    components: [IslandComponent(
                        id: "line",
                        rect: IslandRect(
                            x: 20,
                            y: 20,
                            width: size.width,
                            height: size.height,
                            cornerRadii: NICornerRadii(uniform: 0)
                        ),
                        scrollPath: [],
                        plane: .overlay,
                        coordinateSpace: .viewport,
                        interactive: false,
                        active: true
                    )],
                    scrollContainers: [],
                    order: ["line"],
                    exclusions: [:],
                    cutouts: [:]
                )
                container.layoutIfNeeded()
                XCTAssertFalse(try XCTUnwrap(container.hosts["line"]?.view).isHidden)
                XCTAssertEqual(content.bounds.size, size)
            }
        }
    }
#endif
