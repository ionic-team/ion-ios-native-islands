#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsControllerTests: XCTestCase {
        private final class ProbeIsland: NativeIsland, NativeIslandEventEmitting {
            let view = UIView()
            var eventSink: ((String, [String: Any]) -> Void)?
        }

        private final class EventLog {
            var values: [(String, [String: Any])] = []
        }

        private struct Fixture {
            var parent: UIView
            var webView: WKWebView
            var controller: NativeIslandsController
        }

        private func fixture(
            events: @escaping (String, [String: Any]) -> Void
        )
            -> Fixture {
            let parent = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let webView = WKWebView(frame: parent.bounds)
            parent.addSubview(webView)
            let controller = NativeIslandsController(events: events)
            controller.ensureContainer(webView: webView)
            return Fixture(parent: parent, webView: webView, controller: controller)
        }

        private func layout(type: String, x: Double = 1000) -> (
            components: [[String: Any]],
            scrollContainers: [[String: Any]]
        ) {
            let rect: [String: Any] = ["x": x, "y": 2000, "w": 200, "h": 200, "r": [0, 0, 0, 0]]
            return (
                components: [[
                    "id": "gallery-island",
                    "type": type,
                    "plane": "overlay",
                    "coordinateSpace": "document",
                    "scrollPath": ["scroll-1"],
                    "interactive": false,
                    "active": true,
                    "rect": ["x": x + 20, "y": 2040, "w": 50, "h": 40, "r": [0, 0, 0, 0]],
                ]],
                scrollContainers: [[
                    "id": "scroll-1",
                    "rect": rect,
                    "scrollPath": [String](),
                    "coordinateSpace": "document",
                    "contentWidth": 400,
                    "contentHeight": 1200,
                    "offsetX": 10,
                    "offsetY": 80,
                ]]
            )
        }

        private func scroller(x: CGFloat) -> UIScrollView {
            let view = UIScrollView(frame: CGRect(x: x, y: 2000, width: 200, height: 200))
            view.contentInsetAdjustmentBehavior = .never
            view.contentSize = CGSize(width: 400, height: 1200)
            view.setContentOffset(CGPoint(x: 10, y: 80), animated: false)
            return view
        }

        func testDisposedViewCannotEmitIntoItsReplacement() throws {
            let type = "fixture.eventLifetime"
            var created: [ProbeIsland] = []
            NativeIslandsRegistry.register(componentName: type) {
                let island = ProbeIsland()
                created.append(island)
                return island
            }
            let events = EventLog()
            let fixture = fixture { events.values.append(($0, $1)) }
            defer { fixture.controller.dispose() }
            func apply(_ showing: Bool) {
                var component = layout(type: type).components[0]
                component["scrollPath"] = [String]()
                fixture.controller.applyLayout(
                    components: showing ? [component] : [],
                    order: showing ? ["gallery-island"] : [],
                    exclusions: [:],
                    cutouts: [:],
                    failure: { XCTFail("\($0): \($1)") }
                )
            }
            apply(true)
            let old = try XCTUnwrap(created.last?.eventSink)
            apply(false)
            old("drawn", [:])
            apply(true)
            old("drawn", [:])
            let replacement = try XCTUnwrap(created.last?.eventSink)
            replacement("drawn", [:])
            XCTAssertEqual(events.values.count, 1)
            XCTAssertEqual(events.values.first?.1["island"] as? String, "gallery-island")
            fixture.controller.reset()
            replacement("drawn", [:])
            apply(true)
            replacement("drawn", [:])
            let current = try XCTUnwrap(created.last?.eventSink)
            current("drawn", [:])
            fixture.controller.dispose()
            current("drawn", [:])
            XCTAssertEqual(events.values.count, 2)
        }

        func testACreateForANewInstanceReplacesTheComponentAndStampsItsEvents() throws {
            let type = "fixture.instance"
            var created: [ProbeIsland] = []
            NativeIslandsRegistry.register(componentName: type) {
                let island = ProbeIsland()
                created.append(island)
                return island
            }
            let events = EventLog()
            let fixture = fixture { events.values.append(($0, $1)) }
            defer { fixture.controller.dispose() }
            var component = layout(type: type).components[0]
            component["scrollPath"] = [String]()
            fixture.controller.applyLayout(
                components: [component],
                order: ["gallery-island"],
                exclusions: [:],
                cutouts: [:],
                failure: { XCTFail("\($0): \($1)") }
            )
            func create(_ instance: Int) {
                fixture.controller.dispatchCommandOnMain(
                    island: "gallery-island",
                    requestedType: type,
                    method: "create",
                    params: [:],
                    instance: instance
                ) { XCTAssertNil($0["code"]) }
            }
            create(1)
            create(1)
            XCTAssertEqual(created.count, 1, "the same instance updates the view native keeps")
            let first = try XCTUnwrap(created.last?.eventSink)
            first("drawn", [:])
            create(2)
            XCTAssertEqual(created.count, 2, "another instance gets a new component")
            first("drawn", [:])
            try XCTUnwrap(created.last?.eventSink)("drawn", [:])
            XCTAssertEqual(events.values.map { $0.1["instance"] as? Int }, [1, 2])
        }

        func testMissingScrollerRejectsLayoutThenReusesIslandWhenItAppears() throws {
            let type = "fixture.scrollRetry"
            var created: [ProbeIsland] = []
            NativeIslandsRegistry.register(componentName: type, accessibility: .native) {
                let island = ProbeIsland()
                created.append(island)
                return island
            }
            let events = EventLog()
            let fixture = fixture { event, payload in
                events.values.append((event, payload))
            }
            defer {
                fixture.controller.dispose()
                fixture.parent.removeFromSuperview()
            }

            let input = layout(type: type)
            let failed = expectation(description: "missing inner scroller rejects the layout")
            var failures: [(String, String)] = []
            var completions = 0
            fixture.controller.applyLayout(
                components: input.components,
                scrollContainers: input.scrollContainers,
                order: ["gallery-island"],
                exclusions: [:],
                cutouts: [:],
                sentAt: 1000,
                failure: { code, message in
                    failures.append((code, message))
                    failed.fulfill()
                },
                completion: { _ in completions += 1 }
            )
            wait(for: [failed], timeout: 2)

            let island = try XCTUnwrap(fixture.controller.islands["gallery-island"] as? ProbeIsland)
            XCTAssertEqual(failures.count, 1)
            XCTAssertEqual(failures[0].0, "invalid_request")
            XCTAssertTrue(failures[0].1.contains("inner_scroll_unavailable:scroll-1:missing"))
            XCTAssertTrue(failures[0].1.contains("'gallery-island'"))
            XCTAssertEqual(completions, 0, "a refused layout is not acknowledged")
            XCTAssertNil(fixture.controller.lastLayoutAppliedAt)
            XCTAssertFalse(fixture.controller.lifecycle.isErrored(id: "gallery-island"))
            XCTAssertTrue(events.values.isEmpty, "a missing view does not emit islandError")
            XCTAssertEqual(created.count, 1)

            fixture.webView.addSubview(scroller(x: 1000))
            let applied = expectation(description: "the same island applies after its scroller appears")
            var retryFailures: [(String, String)] = []
            var retryCompletions = 0
            fixture.controller.applyLayout(
                components: input.components,
                scrollContainers: input.scrollContainers,
                order: ["gallery-island"],
                exclusions: [:],
                cutouts: [:],
                sentAt: 1000,
                failure: { code, message in retryFailures.append((code, message)) },
                completion: { _ in
                    retryCompletions += 1
                    applied.fulfill()
                }
            )
            wait(for: [applied], timeout: 2)

            XCTAssertTrue(retryFailures.isEmpty)
            XCTAssertEqual(retryCompletions, 1)
            XCTAssertNotNil(fixture.controller.lastLayoutAppliedAt)
            XCTAssertTrue(fixture.controller.islands["gallery-island"] === island)
            XCTAssertEqual(created.count, 1, "retry keeps the existing native island instance")
            XCTAssertFalse(fixture.controller.lifecycle.isErrored(id: "gallery-island"))
            XCTAssertTrue(events.values.isEmpty)
        }

        func testSupersededLayoutCannotReportNewerApplyTime() {
            let type = "fixture.layoutTime"
            NativeIslandsRegistry.register(componentName: type) { ProbeIsland() }
            let fixture = fixture { _, _ in }
            defer { fixture.controller.dispose() }
            let input = layout(type: type)
            let oldCompleted = expectation(description: "superseded layout completes")
            let newCompleted = expectation(description: "new layout applies")
            var oldTime: Double?
            var newTime: Double?
            fixture.controller.applyLayout(
                components: input.components,
                scrollContainers: input.scrollContainers,
                order: ["gallery-island"],
                exclusions: [:],
                cutouts: [:],
                sentAt: 1000,
                failure: { XCTFail("\($0): \($1)") },
                completion: { appliedAt in
                    oldTime = appliedAt
                    oldCompleted.fulfill()
                }
            )
            fixture.controller.applyLayout(
                components: [],
                order: [],
                exclusions: [:],
                cutouts: [:],
                sentAt: 1100,
                failure: { XCTFail("\($0): \($1)") },
                completion: { appliedAt in
                    newTime = appliedAt
                    newCompleted.fulfill()
                }
            )
            wait(for: [oldCompleted, newCompleted], timeout: 2)
            XCTAssertNil(oldTime)
            XCTAssertNotNil(newTime)
            XCTAssertEqual(fixture.controller.lastLayoutAppliedAt, newTime)
        }

        func testAmbiguousScrollerStillFailsTheIslandAndCompletesTheLayout() {
            let type = "fixture.scrollAmbiguous"
            NativeIslandsRegistry.register(componentName: type, accessibility: .native) {
                ProbeIsland()
            }
            let events = EventLog()
            let fixture = fixture { event, payload in
                events.values.append((event, payload))
            }
            defer {
                fixture.controller.dispose()
                fixture.parent.removeFromSuperview()
            }
            fixture.webView.addSubview(scroller(x: 999))
            fixture.webView.addSubview(scroller(x: 1001))

            let input = layout(type: type)
            let completed = expectation(description: "ambiguous native composition finishes fail-closed")
            var failures: [(String, String)] = []
            var completions = 0
            fixture.controller.applyLayout(
                components: input.components,
                scrollContainers: input.scrollContainers,
                order: ["gallery-island"],
                exclusions: [:],
                cutouts: [:],
                sentAt: 1000,
                failure: { code, message in failures.append((code, message)) },
                completion: { _ in
                    completions += 1
                    completed.fulfill()
                }
            )
            wait(for: [completed], timeout: 2)

            XCTAssertTrue(failures.isEmpty)
            XCTAssertEqual(completions, 1)
            XCTAssertNotNil(fixture.controller.lastLayoutAppliedAt)
            XCTAssertTrue(fixture.controller.lifecycle.isErrored(id: "gallery-island"))
            XCTAssertEqual(events.values.count, 1)
            XCTAssertEqual(events.values[0].0, "islandError")
            XCTAssertTrue((events.values[0].1["reason"] as? String)?.contains("inner_scroll_unavailable:scroll-1:ambiguous") == true)
        }
    }
#endif
