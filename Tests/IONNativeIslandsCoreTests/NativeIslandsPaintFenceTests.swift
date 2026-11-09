#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsPaintFenceTests: XCTestCase {
        private let parent = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        private let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        private let controller = NativeIslandsController(events: { _, _ in })
        private var calls: [String] = []

        override func setUp() {
            super.setUp()
            parent.addSubview(webView)
            controller.launchCacheEnabled = false
            controller.ensureContainer(webView: webView)
        }

        private func addSentinel(fence: Int) -> CALayer {
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            commit(fence, to: layer)
            webView.layer.addSublayer(layer)
            return layer
        }

        private func commit(_ fence: Int, to sentinel: CALayer) {
            sentinel.transform = CATransform3DMakeTranslation(
                CGFloat(fence) / CGFloat(NativeIslandsPaintFence.range),
                NativeIslandsPaintFence.sentinelY,
                0
            )
        }

        private func applyLayout(_ name: String, fence: Int? = nil) {
            controller.applyLayout(
                components: [],
                order: [],
                exclusions: [:],
                cutouts: [:],
                fence: fence,
                completion: { [weak self] _ in self?.calls.append(name) }
            )
        }

        private func command(_ name: String) {
            controller.command(
                island: "island-1",
                type: "fixture.fence",
                method: "update"
            ) { [weak self] _ in self?.calls.append(name) }
        }

        private func spin(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        }

        func testAFencedLayoutAndTheCallsAfterItWaitForItsCommit() {
            let sentinel = addSentinel(fence: 4)
            applyLayout("unfenced")
            applyLayout("retirement", fence: 5)
            command("command")
            applyLayout("next")
            XCTAssertEqual(calls, ["unfenced"])

            spin(0.02)
            XCTAssertEqual(calls, ["unfenced"])

            commit(5, to: sentinel)
            spin(0.02)
            XCTAssertEqual(calls, ["unfenced", "retirement", "command", "next"])
        }

        func testAFencedLayoutRunsWhileWebKitSetsTheSentinel() {
            let sentinel = addSentinel(fence: 4)
            applyLayout("retirement", fence: 5)
            command("command")
            XCTAssertEqual(calls, [])

            commit(5, to: sentinel)
            XCTAssertEqual(calls, ["retirement", "command"], "released inside the setter, in WebKit's transaction")
        }

        func testAFenceAlreadyCommittedOrPassedDoesNotWait() {
            _ = addSentinel(fence: 2)
            applyLayout("retirement", fence: 1)
            XCTAssertEqual(calls, ["retirement"])
        }

        func testWithoutASentinelAFencedLayoutWaitsOutTheBound() {
            applyLayout("retirement", fence: 3)
            XCTAssertEqual(calls, [], "no sentinel is no sign the page painted")
            spin(NativeIslandsPaintFence.maxWait * 1.5)
            XCTAssertEqual(calls, ["retirement"])
        }

        func testAFenceWebKitNeverCommitsIsReleasedAfterTheWait() {
            _ = addSentinel(fence: 0)
            applyLayout("retirement", fence: 1)
            spin(NativeIslandsPaintFence.maxWait / 2)
            XCTAssertEqual(calls, [])
            spin(NativeIslandsPaintFence.maxWait)
            XCTAssertEqual(calls, ["retirement"])
        }

        func testResetDropsHeldCalls() {
            let sentinel = addSentinel(fence: 0)
            applyLayout("retirement", fence: 1)
            controller.reset()
            commit(1, to: sentinel)
            spin(NativeIslandsPaintFence.maxWait * 1.5)
            XCTAssertEqual(calls, [])

            applyLayout("after reset")
            XCTAssertEqual(calls, ["after reset"])
        }

        func testFencesCompareAcrossTheWrap() {
            XCTAssertTrue(NativeIslandsPaintFence.passed(committed: 1, fence: 1023))
            XCTAssertTrue(NativeIslandsPaintFence.passed(committed: 7, fence: 7))
            XCTAssertFalse(NativeIslandsPaintFence.passed(committed: 1023, fence: 1))
            XCTAssertFalse(NativeIslandsPaintFence.passed(committed: 6, fence: 7))
        }

        func testLayoutValidationTakesOnlyAFenceInRange() {
            func error(_ fence: Any) -> String? {
                var refusal: String?
                controller.applyLayout(components: [], order: [], exclusions: [:], cutouts: [:], fence: fence, failure: { refusal = $1 })
                return refusal
            }
            XCTAssertNil(error(0))
            XCTAssertNil(error(1023))
            XCTAssertNotNil(error(1024))
            XCTAssertNotNil(error(-1))
            XCTAssertNotNil(error(1.5))
            XCTAssertNotNil(error(true))
        }
    }
#endif
