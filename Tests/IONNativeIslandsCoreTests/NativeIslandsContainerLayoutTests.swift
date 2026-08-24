#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsContainerLayoutTests: XCTestCase {
        func testRegisteredViewMatchesUpdatedHostBounds() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)

            let tabBar = UITabBar()
            tabBar.items = [
                UITabBarItem(title: "Home", image: nil, tag: 0),
                UITabBarItem(title: "Search", image: nil, tag: 1),
            ]
            container.registerIsland(
                id: "tabs",
                view: tabBar,
                accessibility: .native
            )

            let component = IslandComponent(
                id: "tabs",
                rect: IslandRect(
                    x: 0,
                    y: 791,
                    width: 402,
                    height: 83,
                    cornerRadius: 0
                ),
                scrollPath: [],
                plane: .overlay,
                coordinateSpace: .viewport,
                interactive: true,
                active: true
            )
            XCTAssertTrue(container.applyLedger(
                components: [component],
                scrollContainers: [],
                order: ["tabs"],
                exclusions: [:],
                cutouts: [:]
            ).isEmpty)

            container.layoutIfNeeded()

            let contentHost = try XCTUnwrap(container.contentHosts["tabs"])
            XCTAssertEqual(tabBar.frame, contentHost.bounds)
            XCTAssertEqual(tabBar.bounds.size, CGSize(width: 402, height: 83))
        }
    }
#endif
