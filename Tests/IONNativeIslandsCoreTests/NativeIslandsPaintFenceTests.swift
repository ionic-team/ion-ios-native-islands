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
                CGFloat(fence) / CGFloat(NativeIslandsController.fenceRange),
                NativeIslandsController.fenceSentinelY,
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
            controller.dispatchCommand(
                island: "island-1",
                requestedType: "fixture.fence",
                method: "update",
                params: [:],
                instance: nil
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

        func testAFenceAlreadyCommittedOrPassedDoesNotWait() {
            _ = addSentinel(fence: 2)
            applyLayout("retirement", fence: 1)
            XCTAssertEqual(calls, ["retirement"])
        }

        func testWithoutASentinelAFencedLayoutAppliesAtOnce() {
            applyLayout("retirement", fence: 3)
            XCTAssertEqual(calls, ["retirement"])
        }

        func testAFenceWebKitNeverCommitsIsReleasedAfterTheWait() {
            _ = addSentinel(fence: 0)
            applyLayout("retirement", fence: 1)
            spin(NativeIslandsController.maxFenceWait / 2)
            XCTAssertEqual(calls, [])
            spin(NativeIslandsController.maxFenceWait)
            XCTAssertEqual(calls, ["retirement"])
        }

        func testResetDropsHeldCalls() {
            let sentinel = addSentinel(fence: 0)
            applyLayout("retirement", fence: 1)
            controller.reset()
            commit(1, to: sentinel)
            spin(NativeIslandsController.maxFenceWait * 1.5)
            XCTAssertEqual(calls, [])

            applyLayout("after reset")
            XCTAssertEqual(calls, ["after reset"])
        }

        func testFencesCompareAcrossTheWrap() {
            XCTAssertTrue(NativeIslandsController.fencePassed(committed: 1, fence: 1023))
            XCTAssertTrue(NativeIslandsController.fencePassed(committed: 7, fence: 7))
            XCTAssertFalse(NativeIslandsController.fencePassed(committed: 1023, fence: 1))
            XCTAssertFalse(NativeIslandsController.fencePassed(committed: 6, fence: 7))
        }

        func testLayoutValidationTakesOnlyAFenceInRange() {
            func error(_ fence: Any) -> String? {
                controller.validateLayout(components: [], order: [], exclusions: [:], cutouts: [:], fence: fence)
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
