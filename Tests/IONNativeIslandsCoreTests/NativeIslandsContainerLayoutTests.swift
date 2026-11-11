#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsContainerLayoutTests: XCTestCase {
        func testAnIslandInAScrollportIsVisibleHalfAScreenBeforeItScrollsIn() {
            let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
            let scrollport = CGRect(x: 0, y: 100, width: 400, height: 600)
            func visible(atY y: CGFloat) -> Bool {
                NativeIslandsContainer.isNearViewport(
                    CGRect(x: 0, y: y, width: 400, height: 200),
                    scrollports: [scrollport],
                    bounds: bounds
                )
            }
            XCTAssertTrue(visible(atY: 900), "200 points below its scrollport is within the half-screen margin")
            XCTAssertFalse(visible(atY: 1300))
        }

        func testChangingScrollportCountKeepsContentInItsWindow() throws {
            final class Content: UIView {
                var detachments = 0
                override func didMoveToWindow() {
                    super.didMoveToWindow()
                    if window == nil {
                        detachments += 1
                    }
                }
            }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let content = Content()
            let island = NativeIslandsHost(island: content)
            let host = island.view
            host.frame = CGRect(x: 17, y: 214, width: 178, height: 178)
            window.addSubview(host)
            let port = IslandRect(x: -17, y: -214, width: 402, height: 874, cornerRadii: NICornerRadii(uniform: 0))
            for count in [2, 3, 2, 0] {
                island.applyClips(Array(repeating: port, count: count))
                XCTAssertTrue(content.window === window)
                XCTAssertEqual(content.detachments, 0, "a page push changes clips, not the native content lifetime")
            }

            let edge = IslandRect(x: -17, y: -214, width: 402, height: 300, cornerRadii: NICornerRadii(uniform: 0))
            island.applyClips([edge])
            island.applyClips([edge])
            let mask = try XCTUnwrap(host.subviews.first?.layer.mask as? CAShapeLayer)
            XCTAssertEqual(try XCTUnwrap(mask.path).boundingBox.maxY, edge.cgRect.maxY, accuracy: 1e-9, "a scrollport edge clips it")

            var moved = edge
            moved.x += 0.25
            island.applyClips([moved])
            XCTAssertEqual(try XCTUnwrap(mask.path).boundingBox.minX, moved.x, accuracy: 1e-9, "a fractional nested-path shift moves the clip")
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
                    cornerRadii: NICornerRadii(uniform: 0)
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

            let contentHost = try XCTUnwrap(container.hosts["tabs"]?.content)
            XCTAssertEqual(tabBar.frame, contentHost.bounds)
            XCTAssertEqual(tabBar.bounds.size, CGSize(width: 402, height: 83))
        }

        func testIslandCornersRoundIndependently() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            container.registerIsland(id: "sheet", view: UIView(), accessibility: .native)
            func layOut(_ radii: NICornerRadii) throws -> UIView {
                XCTAssertTrue(container.applyLedger(
                    components: [IslandComponent(
                        id: "sheet",
                        rect: IslandRect(x: 0, y: 474, width: 402, height: 400, cornerRadii: radii),
                        scrollPath: [],
                        plane: .overlay,
                        coordinateSpace: .viewport,
                        interactive: true,
                        active: true
                    )],
                    scrollContainers: [],
                    order: ["sheet"],
                    exclusions: [:],
                    cutouts: [:]
                ).isEmpty)
                container.layoutIfNeeded()
                let body = try XCTUnwrap(container.hosts["sheet"]?.body)
                XCTAssertTrue(body.layer.masksToBounds)
                XCTAssertEqual(body.bounds.size, CGSize(width: 402, height: 400))
                return body
            }

            _ = try layOut(NICornerRadii(uniform: 0))

            let top = try layOut(NICornerRadii(topLeft: 24, topRight: 24, bottomRight: 0, bottomLeft: 0))
            XCTAssertEqual(top.layer.cornerRadius, 24)
            XCTAssertEqual(top.layer.maskedCorners, [.layerMinXMinYCorner, .layerMaxXMinYCorner])
            XCTAssertNil(top.layer.mask)

            let mixed = try layOut(NICornerRadii(topLeft: 24, topRight: 8, bottomRight: 0, bottomLeft: 0))
            XCTAssertEqual(mixed.layer.cornerRadius, 0)
            let clip = try XCTUnwrap(mixed.layer.mask as? CAShapeLayer)
            let path = try XCTUnwrap(clip.path)
            XCTAssertFalse(path.contains(CGPoint(x: 2, y: 2)))
            XCTAssertTrue(path.contains(CGPoint(x: 400, y: 3)))
            XCTAssertTrue(path.contains(CGPoint(x: 1, y: 399)))
        }

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

        func testScrollerSlidingWithItsPageStaysBoundAndAClipIsFollowedAtOnce() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            let pane = UIScrollView(frame: CGRect(x: 0, y: 80, width: 402, height: 700))
            pane.contentSize = CGSize(width: 402, height: 2000)
            webView.addSubview(pane)
            let preview = UIView()
            container.registerIsland(id: "preview", view: preview, accessibility: .native)
            func ledger(paneX: CGFloat, offsetY: CGFloat) -> [String: NIInnerScrollFailure] {
                container.applyLedger(
                    components: [IslandComponent(
                        id: "preview",
                        rect: IslandRect(x: paneX + 20, y: 300, width: 100, height: 100, cornerRadii: NICornerRadii(uniform: 0)),
                        scrollPath: ["pane"],
                        plane: .overlay,
                        coordinateSpace: .viewport,
                        interactive: true,
                        active: true
                    )],
                    scrollContainers: [
                        IslandScrollContainer(
                            id: "pane",
                            rect: IslandRect(x: paneX, y: 80, width: 402, height: 700, cornerRadii: NICornerRadii(uniform: 0)),
                            coordinateSpace: .viewport,
                            scrollPath: [],
                            contentWidth: 402,
                            contentHeight: 2000,
                            offsetX: 0,
                            offsetY: offsetY
                        ),
                        IslandScrollContainer(
                            id: "stack",
                            rect: IslandRect(x: 0, y: 0, width: 402, height: 874, cornerRadii: NICornerRadii(uniform: 0)),
                            coordinateSpace: .viewport,
                            scrollPath: [],
                            contentWidth: 804,
                            contentHeight: 874,
                            offsetX: 0,
                            offsetY: 0
                        ),
                    ],
                    order: ["preview"],
                    exclusions: [:],
                    cutouts: ["preview": [IslandRegion(
                        rect: IslandRect(x: 402, y: 0, width: 402, height: 874, cornerRadii: NICornerRadii(uniform: 0)),
                        scrollPath: ["stack"],
                        coordinateSpace: .viewport,
                        sticky: nil
                    )]]
                )
            }
            XCTAssertEqual(ledger(paneX: 0, offsetY: 0), [:], "the clip is followed from the layout at once")
            pane.contentOffset = CGPoint(x: 0, y: 100)
            let host = try XCTUnwrap(container.hosts["preview"]?.view)
            XCTAssertEqual(container.convert(host.bounds, from: host), CGRect(x: 20, y: 200, width: 100, height: 100))

            pane.frame.origin.x = -120
            XCTAssertEqual(ledger(paneX: -100, offsetY: 100), [:], "the sliding pane stays bound")
            XCTAssertEqual(container.convert(host.bounds, from: host), CGRect(x: -80, y: 200, width: 100, height: 100))
            pane.contentOffset = CGPoint(x: 0, y: 150)
            XCTAssertEqual(
                container.convert(host.bounds, from: host),
                CGRect(x: -80, y: 150, width: 100, height: 100),
                "and native scrolling still moves the island"
            )
        }

        func testIslandTakesItsOpacity() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            container.registerIsland(id: "card", view: UIView(), accessibility: .native)
            var card = IslandComponent(
                id: "card",
                rect: IslandRect(x: 20, y: 100, width: 200, height: 120, cornerRadii: NICornerRadii(uniform: 0)),
                scrollPath: [],
                plane: .overlay,
                coordinateSpace: .document,
                interactive: true,
                active: true,
                opacity: 0.4
            )
            let apply = {
                container.applyLedger(components: [card], scrollContainers: [], order: ["card"], exclusions: [:], cutouts: [:])
            }
            XCTAssertTrue(apply().isEmpty)
            let host = try XCTUnwrap(container.hosts["card"]?.view)
            XCTAssertEqual(host.alpha, 0.4, accuracy: 0.001)
            card.opacity = 1
            XCTAssertTrue(apply().isEmpty)
            XCTAssertEqual(host.alpha, 1, accuracy: 0.001)
        }

        func testTouchesAnIslandDeclinesReachThePage() throws {
            /// Takes touches only on a capsule in its middle, as a floating tab bar does.
            final class Capsule: UIView {
                override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                    bounds.insetBy(dx: 64, dy: 0).contains(point) ? self : nil
                }
            }
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            let bar = Capsule()
            container.registerIsland(id: "tabs", view: bar, accessibility: .native)
            XCTAssertTrue(container.applyLedger(
                components: [IslandComponent(
                    id: "tabs",
                    rect: IslandRect(x: 0, y: 791, width: 402, height: 83, cornerRadii: NICornerRadii(uniform: 0)),
                    scrollPath: [],
                    plane: .overlay,
                    coordinateSpace: .viewport,
                    interactive: true,
                    active: true
                )],
                scrollContainers: [],
                order: ["tabs"],
                exclusions: [:],
                cutouts: [:]
            ).isEmpty)

            let host = try XCTUnwrap(container.hosts["tabs"]?.view)
            let gutter = try XCTUnwrap(webView.hitTest(CGPoint(x: 30, y: 820), with: nil))
            XCTAssertTrue(gutter === webView || gutter.isDescendant(of: webView))
            XCTAssertFalse(gutter.isDescendant(of: host))
            XCTAssertTrue(webView.hitTest(CGPoint(x: 200, y: 820), with: nil) === bar)
        }

        func testStickyHeaderCutsAndPassesTapsWhereItSticks() throws {
            let container = NativeIslandsContainer(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            webView.scrollView.contentSize = CGSize(width: 402, height: 2000)
            let map = UIView()
            container.registerIsland(id: "map", view: map, accessibility: .native)
            let header = IslandRegion(
                rect: IslandRect(x: 0, y: 0, width: 402, height: 60, cornerRadii: NICornerRadii(uniform: 0)),
                scrollPath: [],
                coordinateSpace: .document,
                sticky: NISticky(
                    scroller: nil,
                    natural: CGRect(x: 0, y: 0, width: 402, height: 60),
                    bounds: CGRect(x: 0, y: 0, width: 402, height: 2000),
                    top: 0
                )
            )
            XCTAssertTrue(container.applyLedger(
                components: [IslandComponent(
                    id: "map",
                    rect: IslandRect(x: 0, y: 100, width: 402, height: 600, cornerRadii: NICornerRadii(uniform: 0)),
                    scrollPath: [],
                    plane: .overlay,
                    coordinateSpace: .document,
                    interactive: true,
                    active: true
                )],
                scrollContainers: [],
                order: ["map"],
                exclusions: ["map": [header]],
                cutouts: ["map": [header]]
            ).isEmpty)
            let contentHost = try XCTUnwrap(container.hosts["map"]?.content)

            webView.scrollView.contentOffset = CGPoint(x: 0, y: 300)

            let mask = try XCTUnwrap(contentHost.layer.mask as? CAShapeLayer)
            let path = try XCTUnwrap(mask.path)
            XCTAssertFalse(path.contains(container.convert(CGPoint(x: 100, y: 30), to: contentHost), using: .evenOdd))
            XCTAssertTrue(path.contains(container.convert(CGPoint(x: 100, y: 90), to: contentHost), using: .evenOdd))
            let webTarget = try XCTUnwrap(webView.hitTest(CGPoint(x: 100, y: 30), with: nil))
            XCTAssertTrue(webTarget === webView || webTarget.isDescendant(of: webView))
            XCTAssertTrue(webView.hitTest(CGPoint(x: 100, y: 90), with: nil) === map)
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
                    rect: IslandRect(x: 40, y: 130, width: 320, height: 400, cornerRadii: NICornerRadii(uniform: 32)),
                    scrollPath: [],
                    plane: .underlay,
                    coordinateSpace: .document,
                    interactive: true,
                    active: true
                ),
                IslandComponent(
                    id: "options",
                    rect: IslandRect(x: 20, y: 360, width: 362, height: 420, cornerRadii: NICornerRadii(uniform: 0)),
                    scrollPath: [],
                    plane: .underlay,
                    coordinateSpace: .viewport,
                    interactive: true,
                    active: true
                ),
                IslandComponent(
                    id: "tabs",
                    rect: IslandRect(x: 0, y: 790, width: 402, height: 60, cornerRadii: NICornerRadii(uniform: 0)),
                    scrollPath: [],
                    plane: .overlay,
                    coordinateSpace: .viewport,
                    interactive: true,
                    active: true
                ),
            ]
            let confirmation = IslandRegion(
                rect: IslandRect(x: 50, y: 420, width: 302, height: 180, cornerRadii: NICornerRadii(uniform: 0)),
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
            let previewHost = try XCTUnwrap(container.hosts["preview"]?.view)
            let optionsHost = try XCTUnwrap(container.hosts["options"]?.view)
            XCTAssertEqual(container.underlayPlane.subviews.count, 2)
            XCTAssertTrue(container.underlayPlane.subviews[0] === previewHost)
            XCTAssertTrue(container.underlayPlane.subviews[1] === optionsHost)
            XCTAssertTrue(container.hosts["tabs"]?.view.superview === container.overlayPlane)
            XCTAssertNil(optionsHost.layer.mask)
            XCTAssertTrue(webView.hitTest(CGPoint(x: 100, y: 390), with: nil) === options)
            XCTAssertTrue(webView.hitTest(CGPoint(x: 100, y: 200), with: nil) === preview)
            XCTAssertTrue(webView.hitTest(CGPoint(x: 100, y: 810), with: nil) === tabs)
            let webTarget = try XCTUnwrap(webView.hitTest(CGPoint(x: 100, y: 450), with: nil))
            XCTAssertTrue(webTarget === webView || webTarget.isDescendant(of: webView))
            XCTAssertFalse(webTarget === optionsHost || webTarget.isDescendant(of: optionsHost))
            XCTAssertFalse(webTarget === previewHost || webTarget.isDescendant(of: previewHost))
        }
    }
#endif
