#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    /// An island on a motion follows the page as WebKit draws it: matched to WebKit's own Core Animation
    /// and replayed on the island's layer, or placed every frame from the page clock.
    final class NativeIslandsMotionMatchingTests: XCTestCase {
        /// One WebView for every test: starting a web process busies the main thread for a while.
        private static let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        private let rect = IslandRect(x: 20, y: 100, width: 200, height: 120, cornerRadii: NICornerRadii(uniform: 0))
        private var container = NativeIslandsContainer(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        private var webView: WKWebView {
            Self.webView
        }

        /// Maps page time to native time, as the controller's bridge samples it.
        private var clock = NIPageClock()

        /// Stands in for the layers WebKit commits the page's animations to, which a real page can
        /// replace at any time.
        private var page = CALayer()

        private final class Loaded: NSObject, WKNavigationDelegate {
            let done: () -> Void

            init(_ done: @escaping () -> Void) {
                self.done = done
            }

            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
                done()
            }
        }

        private static var pageLoaded = false

        override func setUp() {
            super.setUp()
            // These tests time motions against the page clock, so the web process must have started
            // first (it busies the main thread), and the page must set its viewport: an empty one is
            // laid out 980 px wide, and WebKit zooms the WebView out once its first commit lands.
            if !Self.pageLoaded {
                let loaded = expectation(description: "the page loads")
                let delegate = Loaded { loaded.fulfill() }
                webView.navigationDelegate = delegate
                webView.loadHTMLString("<meta name=\"viewport\" content=\"width=device-width\">", baseURL: nil)
                // A freshly booted simulator can take 15 s to start the web process.
                wait(for: [loaded], timeout: 60)
                webView.navigationDelegate = nil
                Self.pageLoaded = true
            }
            clock = NIPageClock()
            container = NativeIslandsContainer(frame: webView.bounds, pageClock: clock)
            container.attach(webView: webView)
            page = CALayer()
            webView.layer.addSublayer(page)
            container.registerIsland(id: "card", view: UIView(), accessibility: .native)
        }

        override func tearDown() {
            page.removeFromSuperlayer()
            container.detachWebView()
            super.tearDown()
        }

        private func animation(
            _ channel: NIMotionChannel,
            from: [Double],
            to end: [Double],
            easing: NIEasing = .linear,
            duration: Double,
            startTime: Double = 1000
        )
            -> NIMotionAnimation {
            NIMotionAnimation(
                channel: channel,
                keyframes: [
                    NIMotionKeyframe(offset: 0, value: from, easing: easing),
                    NIMotionKeyframe(offset: 1, value: end, easing: .linear),
                ],
                duration: duration,
                startTime: startTime
            )
        }

        /// Lays out the card on `motion` and returns its host view.
        @discardableResult
        private func layOut(_ motion: NIMotion?, opacity: CGFloat = 1) throws -> UIView {
            let card = IslandComponent(
                id: "card",
                rect: rect,
                scrollPath: [],
                plane: .overlay,
                coordinateSpace: .document,
                interactive: true,
                active: true,
                opacity: opacity,
                motionPath: motion.map { [$0.id] } ?? []
            )
            XCTAssertTrue(container.applyLedger(
                components: [card],
                scrollContainers: [],
                order: ["card"],
                exclusions: [:],
                cutouts: [:],
                motions: motion.map { [$0.id: $0] } ?? [:]
            ).isEmpty)
            return try XCTUnwrap(container.hosts["card"]?.view)
        }

        /// Adds a layer to the page that WebKit draws `animation` on.
        @discardableResult
        private func draw(_ animation: CAAnimation? = nil) -> CALayer {
            let layer = CALayer()
            layer.backgroundColor = UIColor.orange.cgColor
            page.addSublayer(layer)
            if let animation {
                // As WebKit commits it: otherwise Core Animation can drop it from a layer no window draws.
                animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: "webkit")
            }
            return layer
        }

        private func spin(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        }

        /// Runs the main run loop, where native matches and places motions, until `done`. The two-second
        /// cap only ends a run that will never match; a loaded simulator can take well over a frame.
        private func spin(until done: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 2)
            while !done(), Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            }
        }

        /// The tracks that move `layer` on Core Animation, and the constant that cancels its model.
        private func moves(_ layer: CALayer) -> (tracks: [CAKeyframeAnimation], rebase: CGPoint?) {
            let animations = (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) as? CAPropertyAnimation }
                .filter { $0.keyPath == "position" && $0.isAdditive }
            let rebase = animations.compactMap { $0 as? CABasicAnimation }.first
            return (animations.compactMap { $0 as? CAKeyframeAnimation }, (rebase?.fromValue as? NSValue)?.cgPointValue)
        }

        private func fades(_ layer: CALayer) -> [String: CAKeyframeAnimation] {
            (layer.animationKeys() ?? []).reduce(into: [:]) { fades, key in
                if let fade = layer.animation(forKey: key) as? CAKeyframeAnimation, fade.keyPath == "opacity" {
                    fades[key] = fade
                }
            }
        }

        func testAnIslandMovesOnWebKitsTrackFromWhereItsModelIs() throws {
            let begin = CACurrentMediaTime() + 0.1
            clock.sample(pageMilliseconds: 1000, nativeSeconds: begin)
            let push = NIMotion(id: "page", animations: [animation(.translate, from: [0, 0], to: [-80, 0], duration: 1200)])
            let webKit = CAKeyframeAnimation(keyPath: "transform")
            webKit.values = [[0, 0, 0], [-80, 0, 0]]
            webKit.duration = 1.2
            webKit.beginTime = begin
            draw(webKit)
            let host = try layOut(push)
            spin { !moves(host.layer).tracks.isEmpty }
            try layOut(push)

            let (tracks, rebase) = moves(host.layer)
            let track = try XCTUnwrap(tracks.first)
            XCTAssertEqual(tracks.count, 1)
            XCTAssertEqual(track.beginTime, begin, accuracy: 1e-9)
            XCTAssertEqual(track.values?.last as? NSValue, NSValue(cgPoint: CGPoint(x: -80, y: 0)))
            let cancel = try XCTUnwrap(rebase)
            XCTAssertEqual(host.layer.position.x + cancel.x, rect.cgRect.midX, accuracy: 1e-6, "the rebase cancels the model's move")

            try layOut(nil)
            XCTAssertTrue(moves(host.layer).tracks.isEmpty, "no motion leaves no track")
            XCTAssertNil(moves(host.layer).rebase)
        }

        func testAMotionDoesNotBorrowAnotherElementsDifferentCurve() throws {
            let begin = CACurrentMediaTime() + 0.1
            clock.sample(pageMilliseconds: 1000, nativeSeconds: begin)
            let motion = NIMotion(id: "page", animations: [
                animation(.translate, from: [160, 0], to: [0, 0], easing: .cubicBezier(0.42, 0, 1, 1), duration: 1200),
            ])
            for (curve, delay) in [(CAMediaTimingFunctionName.linear, 0.0), (.easeIn, 0.02)] {
                let slide = CAKeyframeAnimation(keyPath: "transform")
                slide.values = [[160, 0, 0], [0, 0, 0]]
                slide.keyTimes = [0, 1]
                slide.timingFunction = CAMediaTimingFunction(name: .linear)
                slide.timingFunctions = [CAMediaTimingFunction(name: curve)]
                slide.duration = 1.2
                slide.beginTime = begin + delay
                draw(slide)
            }
            let host = try layOut(motion)
            spin { !moves(host.layer).tracks.isEmpty }
            try layOut(motion)

            let track = try XCTUnwrap(moves(host.layer).tracks.first)
            XCTAssertEqual(track.timingFunctions?.first, CAMediaTimingFunction(name: .easeIn))
            XCTAssertEqual(track.beginTime, begin + 0.02, accuracy: 1e-6)
        }

        func testAMotionWaitsForTheRunningAnimationAfterAPausedOne() throws {
            let begin = CACurrentMediaTime() + 0.1
            clock.sample(pageMilliseconds: 1000, nativeSeconds: begin)
            let motion = NIMotion(id: "slide", animations: [animation(.translate, from: [0, 0], to: [160, 0], duration: 600)])
            let webKitLayer = draw()
            func slide(speed: Float, delay: CFTimeInterval) {
                let animation = CABasicAnimation(keyPath: "transform")
                animation.fromValue = [0, 0, 0]
                animation.toValue = [160, 0, 0]
                animation.duration = 0.6
                animation.beginTime = begin + delay
                animation.speed = speed
                // As WebKit commits them: otherwise Core Animation can drop a paused one from a layer no
                // window draws, taking the running one that replaces it along.
                animation.isRemovedOnCompletion = false
                webKitLayer.add(animation, forKey: "slide")
            }

            slide(speed: 0, delay: -0.011)
            let host = try layOut(motion)
            spin(0.03)
            try layOut(motion)
            XCTAssertTrue(moves(host.layer).tracks.isEmpty, "a paused animation never moves")

            slide(speed: 1, delay: 0.001)
            spin { !moves(host.layer).tracks.isEmpty }
            try layOut(motion)
            let track = try XCTUnwrap(moves(host.layer).tracks.first)
            XCTAssertEqual(track.beginTime, begin + 0.001, accuracy: 1e-6)
            XCTAssertEqual(track.speed, 1)
        }

        func testAMotionWebKitDoesNotDrawIsHeldForAFrameThenRunsOnThePageClock() throws {
            let now = CACurrentMediaTime()
            clock.sample(pageMilliseconds: 1000, nativeSeconds: now)
            // One started as the layout was sent; one ended before it arrived, which still has to be let go.
            for startTime in [1000.0, 0] {
                let motion = NIMotion(id: "page", animations: [
                    animation(.translate, from: [0, 0], to: [100, 0], duration: 400, startTime: startTime),
                    animation(.opacity, from: [1], to: [0.5], duration: 400, startTime: startTime),
                ])
                let host = try layOut(nil)
                try layOut(motion)
                XCTAssertEqual(host.frame.minX, 20, accuracy: 1e-6, "the first frame waits for WebKit")
                XCTAssertEqual(host.alpha, 1, accuracy: 1e-6)

                spin { host.frame.minX > 20 }
                XCTAssertGreaterThan(host.frame.minX, 20, "then it moves rather than standing still")
                XCTAssertLessThan(host.alpha, 1)
                XCTAssertTrue(moves(host.layer).tracks.isEmpty, "frame by frame, as WebKit runs an animation it keeps")
                let placed = host.frame.minX
                try layOut(motion)
                XCTAssertGreaterThanOrEqual(host.frame.minX, placed, "a layout sent mid-motion keeps it running")

                spin(0.45)
                spin { host.frame.minX == 120 }
                XCTAssertEqual(host.frame.minX, 120, accuracy: 1e-6)
                XCTAssertEqual(host.alpha, 0.5, accuracy: 1e-6)
            }
        }

        func testAMatchWhoseTrackCannotBeCopiedStillRunsOnCoreAnimation() throws {
            let begin = CACurrentMediaTime() + 0.1
            clock.sample(pageMilliseconds: 1000, nativeSeconds: begin)
            let motion = NIMotion(id: "slide", animations: [animation(.translate, from: [0, 0], to: [160, 0], duration: 600)])
            let slide = CABasicAnimation(keyPath: "transform")
            slide.fromValue = [0, 0, 0]
            slide.toValue = [160, 0, 0]
            slide.duration = 0.6
            let group = CAAnimationGroup()
            group.animations = [slide]
            group.duration = 0.6
            group.beginTime = begin + 0.004
            group.timeOffset = 0.001
            draw(group)
            let host = try layOut(motion)
            spin { !moves(host.layer).tracks.isEmpty }
            try layOut(motion)

            let track = try XCTUnwrap(moves(host.layer).tracks.first, "WebKit runs it on Core Animation, so the island does")
            XCTAssertEqual(track.beginTime, begin + 0.004, accuracy: 1e-6)
            XCTAssertEqual(track.duration, 0.6, accuracy: 1e-9)
            XCTAssertEqual((track.values?.last as? NSValue)?.cgPointValue, CGPoint(x: 160, y: 0))
        }

        func testAFadeWebKitRunsOnCoreAnimationRunsOnTheIslandsAlphaToo() throws {
            let begin = CACurrentMediaTime()
            clock.sample(pageMilliseconds: 1000, nativeSeconds: begin)
            let fade = NIMotion(id: "page", animations: [animation(.opacity, from: [1], to: [0], duration: 300)])
            let host = try layOut(fade, opacity: 0.5)
            XCTAssertTrue(fades(host.layer).isEmpty, "a held fade stays put")

            spin(0.03)
            try layOut(fade, opacity: 0.5)
            XCTAssertTrue(fades(host.layer).isEmpty, "a fade WebKit keeps runs frame by frame")

            let webKitFade = CABasicAnimation(keyPath: "opacity")
            webKitFade.fromValue = 1
            webKitFade.toValue = 0
            webKitFade.duration = 0.3
            webKitFade.beginTime = begin
            draw(webKitFade)
            spin { !fades(host.layer).isEmpty }
            try layOut(fade, opacity: 0.5)
            let running = fades(host.layer)
            let track = try XCTUnwrap(running.first?.value)
            XCTAssertEqual(running.count, 1)
            XCTAssertEqual(track.duration, 0.3, accuracy: 1e-9)
            XCTAssertEqual(track.values?.first as? Double ?? -1, 0.5, accuracy: 1e-9, "times the island's own opacity")
            XCTAssertEqual(track.values?.last as? Double ?? -1, 0, accuracy: 1e-9)
            try layOut(fade, opacity: 0.5)
            XCTAssertEqual(Set(fades(host.layer).keys), Set(running.keys), "kept while the same fade runs")

            try layOut(nil, opacity: 0.5)
            XCTAssertTrue(fades(host.layer).isEmpty)
        }
    }
#endif
