#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsContainerLayoutTests: XCTestCase {
        func testResetCompletionRunsAfterTheMainQueueReset() {
            let controller = NativeIslandsController { _, _ in }
            let completed = expectation(description: "reset completed")

            DispatchQueue.global().async {
                controller.reset {
                    XCTAssertTrue(Thread.isMainThread)
                    completed.fulfill()
                }
            }

            wait(for: [completed], timeout: 1)
        }

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

        func testViewportUnderlayStaysFixedAndRetainsHostAcrossPlaneChanges() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            webView.scrollView.contentSize = CGSize(width: 402, height: 2000)
            let native = UIView()
            container.registerIsland(id: "options", view: native, accessibility: .native)
            var options = IslandComponent(
                id: "options",
                rect: IslandRect(x: 20, y: 300, width: 362, height: 450, cornerRadius: 0),
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
            let host = try XCTUnwrap(container.hosts["options"])
            let contentHost = try XCTUnwrap(container.contentHosts["options"])
            XCTAssertTrue(host.superview === container.documentLayer)
            let expected = CGRect(x: 20, y: 300, width: 362, height: 450)
            for offset in [CGFloat(0), 120, 360, 0] {
                webView.scrollView.contentOffset = CGPoint(x: 0, y: offset)
                XCTAssertEqual(container.convert(host.bounds, from: host), expected)
                XCTAssertFalse(host.isHidden)
            }
            options.plane = .overlay
            XCTAssertTrue(container.applyLedger(
                components: [options],
                scrollContainers: [],
                order: ["options"],
                exclusions: [:],
                cutouts: [:]
            ).isEmpty)
            XCTAssertTrue(container.hosts["options"] === host)
            XCTAssertTrue(container.contentHosts["options"] === contentHost)
            XCTAssertTrue(native.superview === contentHost)
            XCTAssertTrue(host.superview === container.overlayLayer)
            XCTAssertEqual(container.convert(host.bounds, from: host), expected)
            options.plane = .underlay
            XCTAssertTrue(container.applyLedger(
                components: [options],
                scrollContainers: [],
                order: ["options"],
                exclusions: [:],
                cutouts: [:]
            ).isEmpty)
            XCTAssertTrue(container.hosts["options"] === host)
            XCTAssertTrue(host.superview === container.documentLayer)
            XCTAssertEqual(container.convert(host.bounds, from: host), expected)
        }

        func testOverlappingUnderlaysKeepNativeOrderAndRouteHigherWebExclusion() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            let preview = UIView()
            let options = UIView()
            let tabs = UIView()
            for (id, view) in [("preview", preview), ("options", options), ("tabs", tabs)] {
                container.registerIsland(id: id, view: view, accessibility: .native)
            }
            let components = [
                IslandComponent(
                    id: "preview",
                    rect: IslandRect(x: 40, y: 130, width: 320, height: 400, cornerRadius: 32),
                    scrollPath: [],
                    plane: .underlay,
                    coordinateSpace: .document,
                    interactive: true,
                    active: true
                ),
                IslandComponent(
                    id: "options",
                    rect: IslandRect(x: 20, y: 360, width: 362, height: 420, cornerRadius: 0),
                    scrollPath: [],
                    plane: .underlay,
                    coordinateSpace: .viewport,
                    interactive: true,
                    active: true
                ),
                IslandComponent(
                    id: "tabs",
                    rect: IslandRect(x: 0, y: 790, width: 402, height: 60, cornerRadius: 0),
                    scrollPath: [],
                    plane: .overlay,
                    coordinateSpace: .viewport,
                    interactive: true,
                    active: true
                ),
            ]
            let confirmation = IslandRegion(
                rect: IslandRect(x: 50, y: 420, width: 302, height: 180, cornerRadius: 0),
                scrollPath: [],
                coordinateSpace: .viewport
            )
            XCTAssertTrue(container.applyLedger(
                components: components,
                scrollContainers: [],
                order: ["preview", "options", "tabs"],
                exclusions: ["options": [confirmation]],
                cutouts: [:]
            ).isEmpty)
            let previewHost = try XCTUnwrap(container.hosts["preview"])
            let optionsHost = try XCTUnwrap(container.hosts["options"])
            XCTAssertEqual(container.documentLayer.subviews.count, 2)
            XCTAssertTrue(container.documentLayer.subviews[0] === previewHost)
            XCTAssertTrue(container.documentLayer.subviews[1] === optionsHost)
            XCTAssertTrue(container.hosts["tabs"]?.superview === container.overlayLayer)
            XCTAssertNil(optionsHost.layer.mask)
            XCTAssertTrue(container.hitTest(CGPoint(x: 100, y: 390), with: nil) === options)
            XCTAssertTrue(container.hitTest(CGPoint(x: 100, y: 200), with: nil) === preview)
            XCTAssertTrue(container.hitTest(CGPoint(x: 100, y: 810), with: nil) === tabs)
            let webTarget = try XCTUnwrap(container.hitTest(CGPoint(x: 100, y: 450), with: nil))
            XCTAssertTrue(webTarget === webView || webTarget.isDescendant(of: webView))
            XCTAssertFalse(webTarget === optionsHost || webTarget.isDescendant(of: optionsHost))
            XCTAssertFalse(webTarget === previewHost || webTarget.isDescendant(of: previewHost))
        }
    }
#endif
