#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsMotionMatchingTests: XCTestCase {
        @MainActor
        func testAMotionDoesNotBorrowAnotherElementsDifferentCurve() throws {
            let container = NativeIslandsContainer(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let webView = WKWebView(frame: container.bounds)
            container.attach(webView: webView)
            defer {
                container.stopMotion()
                container.detachWebView()
            }
            let begin = CACurrentMediaTime() + 0.1
            let clock = NIPageClock()
            clock.sample(pageMilliseconds: 1000, nativeSeconds: begin)
            container.pageClock = clock
            let motion = NIMotion(id: "page", animations: [NIMotionAnimation(
                channel: .translate,
                keyframes: [
                    NIMotionKeyframe(offset: 0, value: [160, 0], easing: .cubicBezier(0.42, 0, 1, 1)),
                    NIMotionKeyframe(offset: 1, value: [0, 0], easing: .linear),
                ],
                duration: 1200,
                startTime: 1000
            )])
            for (curve, delay) in [(CAMediaTimingFunctionName.linear, 0.0), (.easeIn, 0.02)] {
                let layer = CALayer()
                layer.backgroundColor = UIColor.orange.cgColor
                webView.layer.addSublayer(layer)
                let animation = CAKeyframeAnimation(keyPath: "transform")
                animation.values = [[160, 0, 0], [0, 0, 0]]
                animation.keyTimes = [0, 1]
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.timingFunctions = [CAMediaTimingFunction(name: curve)]
                animation.duration = 1.2
                animation.beginTime = begin + delay
                layer.add(animation, forKey: "slide")
            }
            container.adopt(["page": motion])
            container.syncMotions()
            XCTAssertEqual(try XCTUnwrap(container.motionStartCorrections[motion.key]), 20, accuracy: 0.001)
            let track = try XCTUnwrap(container.motionTracks[motion.key])
            XCTAssertEqual(track.timingFunctions?.first, CAMediaTimingFunction(name: .easeIn))
        }
    }
#endif
