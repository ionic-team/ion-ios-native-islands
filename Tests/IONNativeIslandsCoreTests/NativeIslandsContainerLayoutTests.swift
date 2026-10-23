// swiftlint:disable file_length
#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    // swiftlint:disable:next type_body_length
    final class NativeIslandsContainerLayoutTests: XCTestCase {
        func testAnIslandInAScrollportIsVisibleHalfAScreenBeforeItScrollsIn() {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
            let host = UIView(frame: CGRect(x: 0, y: 900, width: 400, height: 200))
            container.addSubview(host)
            let tracker = NativeIslandsVisibilityTracker()
            var reported: [String: Bool] = [:]
            tracker.onChange = { reported[$0] = $1 }
            let scrollport = CGRect(x: 0, y: 100, width: 400, height: 600)

            tracker.update(container: container, hosts: ["near": host], screenScrollports: { _ in [scrollport] })
            XCTAssertEqual(reported["near"], true, "200 points below its scrollport is within the half-screen margin")

            host.frame.origin.y = 1300
            tracker.update(container: container, hosts: ["near": host], screenScrollports: { _ in [scrollport] })
            XCTAssertEqual(reported["near"], false)
        }

        func testAScrollportHoldingTheWholeIslandLeavesNoMask() {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
            let content = UIView(frame: host.bounds)
            host.addSubview(content)
            let clipping = NativeIslandsHostClipping()
            let around = IslandRect(x: -30, y: -500, width: 200, height: 900, cornerRadii: NICornerRadii(uniform: 0))
            clipping.applyScrollports(to: host, contentHost: content, islandID: "a", scrollports: [around])
            XCTAssertNil(content.superview?.layer.mask, "a scrollport around the island clips nothing")

            let edge = IslandRect(x: -30, y: 60, width: 200, height: 900, cornerRadii: NICornerRadii(uniform: 0))
            clipping.applyScrollports(to: host, contentHost: content, islandID: "a", scrollports: [edge])
            XCTAssertNotNil((content.superview?.layer.mask as? CAShapeLayer)?.path, "a scrollport edge across the island clips it")

            let rounded = IslandRect(x: 0, y: 0, width: 120, height: 120, cornerRadii: NICornerRadii(uniform: 16))
            XCTAssertFalse(rounded.containsBox(host.bounds.size), "its rounded corners cut the island's corners")
            XCTAssertTrue(around.containsBox(host.bounds.size))
        }

        func testCutoutMaskIsUpdatedInPlaceAndCleared() throws {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
            let clipping = NativeIslandsHostClipping()
            let first = IslandRect(x: 20, y: 20, width: 20, height: 20, cornerRadii: NICornerRadii(uniform: 0))
            let second = IslandRect(x: 80, y: 80, width: 20, height: 20, cornerRadii: NICornerRadii(uniform: 0))

            clipping.applyCutouts(to: host, islandID: "preview", cutouts: [first])
            let mask = try XCTUnwrap(host.layer.mask as? CAShapeLayer)
            let firstPath = try XCTUnwrap(mask.path)
            clipping.applyCutouts(to: host, islandID: "preview", cutouts: [first])
            XCTAssertTrue(try XCTUnwrap(mask.path) === firstPath, "unchanged local cutouts reuse their mask path")

            clipping.applyCutouts(to: host, islandID: "preview", cutouts: [second])
            let secondPath = try XCTUnwrap(mask.path)
            XCTAssertFalse(secondPath === firstPath, "a moved cutout builds a new local path")

            XCTAssertTrue(host.layer.mask === mask)
            XCTAssertTrue(secondPath.contains(CGPoint(x: 25, y: 25), using: .evenOdd))
            XCTAssertFalse(secondPath.contains(CGPoint(x: 85, y: 85), using: .evenOdd))
            clipping.applyCutouts(to: host, islandID: "preview", cutouts: [])
            XCTAssertNil(host.layer.mask)
        }

        func testATrackedMotionMovesALayerWithWebKitsAnimationFromWhereItsModelIs() throws {
            let container = NativeIslandsContainer(frame: .zero)
            let clock = NIPageClock()
            clock.sample(pageMilliseconds: 1000, nativeSeconds: 10)
            container.pageClock = clock
            let motion = NIMotion(id: "page", animations: [NIMotionAnimation(
                channel: .translate,
                keyframes: [
                    NIMotionKeyframe(offset: 0, value: [0, 0], easing: .linear),
                    NIMotionKeyframe(offset: 1, value: [-80, 0], easing: .linear),
                ],
                duration: 400,
                startTime: 1000
            )])
            container.motions = ["page": motion]
            let webKit = CAKeyframeAnimation(keyPath: "position")
            webKit.values = [NSValue(cgPoint: .zero), NSValue(cgPoint: CGPoint(x: -80, y: 0))]
            webKit.duration = 0.4
            webKit.beginTime = 10
            webKit.isAdditive = true
            container.motionTracks[motion.key] = webKit
            let layer = CALayer()

            container.motionFrameTime = 10.1 // page time 1100, a quarter of the way
            container.applyMotion(container.trackedMoves(["page"]), scale: 2, to: layer)
            let move = try XCTUnwrap(layer.animation(forKey: "ni.move.\(motion.key).1.0.2.0") as? CAKeyframeAnimation)
            XCTAssertTrue(move.isAdditive)
            XCTAssertEqual(move.values?.last as? NSValue, NSValue(cgPoint: CGPoint(x: -160, y: 0)))
            let rebase = try XCTUnwrap(layer.animation(forKey: "ni.rebase") as? CABasicAnimation)
            XCTAssertEqual((rebase.fromValue as? NSValue)?.cgPointValue.x ?? .nan, 40, accuracy: 1e-9, "cancels the 20 px the model holds")

            container.applyMotion([], scale: 2, to: layer)
            XCTAssertNil(layer.animationKeys(), "no motion leaves no animation")
        }

        func testAFreshMotionWaitsForWebKitsCommittedStart() {
            let container = NativeIslandsContainer(frame: .zero)
            let motion = NIMotion(id: "page", animations: [NIMotionAnimation(
                channel: .translate,
                keyframes: [
                    NIMotionKeyframe(offset: 0, value: [402, 0], easing: .linear),
                    NIMotionKeyframe(offset: 1, value: [0, 0], easing: .linear),
                ],
                duration: 400,
                startTime: 1000
            )])
            container.adopt(["page": motion])
            XCTAssertEqual(container.motions["page"]?.offset(at: 1200).x ?? 0, 0, accuracy: 1e-9)
            container.stopMotion()
        }

        func testAnUnmatchedMotionKeepsFrameCallbacksUntilItCanBeReleased() {
            let container = NativeIslandsContainer(frame: .zero)
            let clock = NIPageClock()
            clock.sample(pageMilliseconds: 1000, nativeSeconds: CACurrentMediaTime())
            container.pageClock = clock
            let motion = NIMotion(id: "page", animations: [NIMotionAnimation(
                channel: .translate,
                keyframes: [
                    NIMotionKeyframe(offset: 0, value: [402, 0], easing: .linear),
                    NIMotionKeyframe(offset: 1, value: [0, 0], easing: .linear),
                ],
                duration: 400,
                startTime: 0
            )])
            container.adopt(["page": motion])
            container.scheduleMotionFrames()
            XCTAssertNotNil(container.motionLink, "a held motion still needs to be matched or timed out")
            container.stopMotion()
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
            let host = UIView(frame: CGRect(x: 17, y: 214, width: 178, height: 178))
            let contentHost = UIView(frame: host.bounds)
            let content = Content(frame: contentHost.bounds)
            window.addSubview(host)
            host.addSubview(contentHost)
            contentHost.addSubview(content)
            let clipping = NativeIslandsHostClipping()
            let port = IslandRect(x: -17, y: -214, width: 402, height: 874, cornerRadii: NICornerRadii(uniform: 0))
            for count in [2, 3, 2, 0] {
                clipping.applyScrollports(to: host, contentHost: contentHost, islandID: "preview", scrollports: Array(repeating: port, count: count))
                XCTAssertTrue(content.window === window)
                XCTAssertEqual(content.detachments, 0, "a page push changes clips, not the native content lifetime")
            }

            let edge = IslandRect(x: -17, y: -214, width: 402, height: 300, cornerRadii: NICornerRadii(uniform: 0))
            clipping.applyScrollports(to: host, contentHost: contentHost, islandID: "preview", scrollports: [edge])
            let wrapper = try XCTUnwrap(host.subviews.first)
            let mask = try XCTUnwrap(wrapper.layer.mask as? CAShapeLayer)
            let originalPath = try XCTUnwrap(mask.path)
            clipping.applyScrollports(to: host, contentHost: contentHost, islandID: "preview", scrollports: [edge])
            XCTAssertTrue(try XCTUnwrap(mask.path) === originalPath, "unchanged local scrollports reuse their mask path")

            let moved = IslandRect(
                x: edge.x + 0.25,
                y: edge.y,
                width: edge.width,
                height: edge.height,
                cornerRadii: edge.cornerRadii
            )
            clipping.applyScrollports(to: host, contentHost: contentHost, islandID: "preview", scrollports: [moved])
            XCTAssertFalse(try XCTUnwrap(mask.path) === originalPath, "a fractional nested-path shift invalidates the shape")
        }

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

            let contentHost = try XCTUnwrap(container.contentHosts["tabs"])
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
                let host = try XCTUnwrap(container.hosts["sheet"])
                XCTAssertTrue(host.layer.masksToBounds)
                XCTAssertEqual(container.contentHosts["sheet"]?.bounds.size, CGSize(width: 402, height: 400))
                return host
            }

            _ = try layOut(NICornerRadii(uniform: 0))

            let top = try layOut(NICornerRadii(topLeft: 24, topRight: 24, bottomRight: 0, bottomLeft: 0))
            XCTAssertEqual(top.layer.cornerRadius, 24)
            XCTAssertEqual(top.layer.maskedCorners, [.layerMinXMinYCorner, .layerMaxXMinYCorner])
            XCTAssertTrue(top.subviews.allSatisfy { $0.layer.mask == nil })

            let mixed = try layOut(NICornerRadii(topLeft: 24, topRight: 8, bottomRight: 0, bottomLeft: 0))
            XCTAssertEqual(mixed.layer.cornerRadius, 0)
            let clip = try XCTUnwrap(mixed.subviews.first?.layer.mask as? CAShapeLayer)
            let path = try XCTUnwrap(clip.path)
            XCTAssertFalse(path.contains(CGPoint(x: 2, y: 2)))
            XCTAssertTrue(path.contains(CGPoint(x: 400, y: 3)))
            XCTAssertTrue(path.contains(CGPoint(x: 1, y: 399)))
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
            let host = try XCTUnwrap(container.hosts["preview"])
            let contentHost = try XCTUnwrap(container.contentHosts["preview"])
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
            func ledger(paneX: CGFloat, offsetY: CGFloat) -> [String: String] {
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
            let host = try XCTUnwrap(container.hosts["preview"])
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
            let host = try XCTUnwrap(container.hosts["card"])
            XCTAssertEqual(host.alpha, 0.4, accuracy: 0.001)
            card.opacity = 1
            XCTAssertTrue(apply().isEmpty)
            XCTAssertEqual(host.alpha, 1, accuracy: 0.001)
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
            let contentHost = try XCTUnwrap(container.contentHosts["map"])

            webView.scrollView.contentOffset = CGPoint(x: 0, y: 300)

            let mask = try XCTUnwrap(contentHost.layer.mask as? CAShapeLayer)
            let path = try XCTUnwrap(mask.path)
            XCTAssertFalse(path.contains(container.convert(CGPoint(x: 100, y: 30), to: contentHost), using: .evenOdd))
            XCTAssertTrue(path.contains(container.convert(CGPoint(x: 100, y: 90), to: contentHost), using: .evenOdd))
            let webTarget = try XCTUnwrap(container.hitTest(CGPoint(x: 100, y: 30), with: nil))
            XCTAssertTrue(webTarget === webView || webTarget.isDescendant(of: webView))
            XCTAssertTrue(container.hitTest(CGPoint(x: 100, y: 90), with: nil) === map)
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
