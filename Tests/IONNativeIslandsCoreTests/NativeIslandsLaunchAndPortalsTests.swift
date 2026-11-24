#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsLaunchAndPortalsTests: XCTestCase {
        private final class TrackingIsland: NativeIsland, NativeIslandEventEmitting {
            let view = UIView()
            var eventSink: ((String, [String: Any]) -> Void)?
            var createCalls: [[String: Any]] = []
            var updateCalls: [[String: Any]] = []
            var destroyCalls = 0

            func create(properties: [String: Any]) {
                createCalls.append(properties)
            }

            func update(properties: [String: Any]) {
                updateCalls.append(properties)
            }

            func onDestroy() {
                destroyCalls += 1
            }
        }

        private func makeComponent(
            id: String,
            type: String,
            portal: String? = nil,
            x: Double = 24,
            y: Double = 48,
            width: Double = 160,
            height: Double = 160,
            radius: Double = 24
        )
            -> [String: Any] {
            var payload: [String: Any] = [
                "id": id,
                "type": type,
                "plane": "overlay",
                "coordinateSpace": "viewport",
                "scrollPath": [String](),
                "interactive": true,
                "active": true,
                "rect": [
                    "x": x,
                    "y": y,
                    "w": width,
                    "h": height,
                    "r": [radius, radius, radius, radius],
                ],
            ]
            if let portal {
                payload["portal"] = portal
            }
            return payload
        }

        /// Whether `view` is in `root`'s hierarchy with nothing between them hidden.
        private func shows(_ view: UIView, in root: UIView) -> Bool {
            var current: UIView? = view
            while let candidate = current, candidate !== root {
                if candidate.isHidden {
                    return false
                }
                current = candidate.superview
            }
            return current === root
        }

        func testPortalHandoffReusesTheView() throws {
            let type = "fixture.portalIsland"
            var created: [TrackingIsland] = []
            NativeIslandsRegistry.register(componentName: type) {
                let island = TrackingIsland()
                created.append(island)
                return island
            }
            var receivedEvents: [(String, [String: Any])] = []
            let parent = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let webView = WKWebView(frame: parent.bounds)
            parent.addSubview(webView)
            let controller = NativeIslandsController { event, payload in
                receivedEvents.append((event, payload))
            }
            controller.launchCacheEnabled = false
            controller.ensureContainer(webView: webView)
            defer { controller.dispose() }

            let cardComponent = makeComponent(
                id: "card-island",
                type: type,
                portal: "card:weather",
                x: 20,
                y: 120,
                width: 160,
                height: 160,
                radius: 20
            )
            controller.applyLayout(
                components: [cardComponent],
                order: ["card-island"],
                exclusions: [:],
                cutouts: [:],
                failure: { XCTFail("\($0): \($1)") }
            )
            controller.command(
                island: "card-island",
                type: type,
                method: "create",
                params: ["title": "Weather"],
                instance: 1
            ) { _ in }

            XCTAssertEqual(created.count, 1)
            let originalIsland = try XCTUnwrap(created.first)
            XCTAssertEqual(originalIsland.createCalls.count, 1)

            let studioComponent = makeComponent(
                id: "studio-island",
                type: type,
                portal: "card:weather",
                x: 36,
                y: 80,
                width: 330,
                height: 330,
                radius: 36
            )
            controller.applyLayout(
                components: [studioComponent],
                order: ["studio-island"],
                exclusions: [:],
                cutouts: [:],
                failure: { XCTFail("\($0): \($1)") }
            )

            XCTAssertEqual(created.count, 1)
            XCTAssertEqual(originalIsland.destroyCalls, 0)
            XCTAssertTrue(shows(originalIsland.view, in: parent))

            // Its events now speak for the id that took it over, with the instance it was created for.
            originalIsland.eventSink?("drawn", [:])
            XCTAssertEqual(receivedEvents.last?.0, "drawn")
            XCTAssertEqual(receivedEvents.last?.1["island"] as? String, "studio-island")
            XCTAssertEqual(receivedEvents.last?.1["instance"] as? Int, 1)
        }

        private func seedLaunchCache(type: String, store: UserDefaults) {
            let parent = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let webView = WKWebView(frame: parent.bounds)
            parent.addSubview(webView)
            let controller = NativeIslandsController { _, _ in }
            controller.launchCacheEnabled = true
            controller.launchCacheStore = store
            controller.ensureContainer(webView: webView)
            let launchComp = makeComponent(
                id: "native-island-1",
                type: type,
                portal: "card:hero",
                x: 24,
                y: 64,
                width: 180,
                height: 180
            )
            controller.applyLayout(
                components: [launchComp],
                order: ["native-island-1"],
                exclusions: [:],
                cutouts: [:],
                canvasColor: "#10141c",
                failure: { XCTFail("\($0): \($1)") }
            )
            controller.command(
                island: "native-island-1",
                type: type,
                method: "create",
                params: ["headline": "Cached Hero"],
                instance: 1
            ) { _ in }
            controller.dispose()
        }

        func testALaunchScreenWithoutFixedIslandsClearsTheLaunchCache() throws {
            let type = "fixture.clearedLaunchIsland"
            NativeIslandsRegistry.register(componentName: type) { TrackingIsland() }
            let suiteName = "io.ionic.nativeislands.tests.\(UUID().uuidString)"
            let store = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { store.removePersistentDomain(forName: suiteName) }
            seedLaunchCache(type: type, store: store)
            XCTAssertNotNil(NativeIslandsLaunchCache.load(from: store))

            let parent = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let webView = WKWebView(frame: parent.bounds)
            parent.addSubview(webView)
            let controller = NativeIslandsController { _, _ in }
            controller.launchCacheEnabled = false
            controller.launchCacheStore = store
            controller.ensureContainer(webView: webView)
            controller.launchCacheEnabled = true
            controller.applyLayout(
                components: [],
                order: [],
                exclusions: [:],
                cutouts: [:],
                canvasColor: "#10141c",
                failure: { XCTFail("\($0): \($1)") }
            )
            // The cache is written once per run-loop turn, or as the host goes.
            controller.dispose()
            XCTAssertNil(NativeIslandsLaunchCache.load(from: store))
        }

        func testLaunchCacheKeepsTheTransitionTag() throws {
            let suiteName = "io.ionic.nativeislands.tests.\(UUID().uuidString)"
            let store = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { store.removePersistentDomain(forName: suiteName) }
            let card = IslandComponent(
                id: "card",
                rect: IslandRect(x: 20, y: 100, width: 200, height: 120, cornerRadii: NICornerRadii(uniform: 0)),
                scrollPath: [],
                plane: .overlay,
                coordinateSpace: .viewport,
                interactive: true,
                active: true,
                transitionTag: "hero-card"
            )
            NativeIslandsLaunchCache.save(
                NativeIslandsLaunchCache.Snapshot(
                    canvasColor: nil,
                    order: ["card"],
                    entries: [NativeIslandsLaunchCache.Entry(component: card, type: "acme.card", properties: [:])]
                ),
                to: store
            )
            let restored = try XCTUnwrap(NativeIslandsLaunchCache.load(from: store))
            XCTAssertEqual(restored.entries.first?.component.transitionTag, "hero-card")
        }

        func testFrozenFirstFrameRestoresOnLaunchAndHandsOffWithoutRecreate() throws {
            let type = "fixture.launchIsland"
            var created: [TrackingIsland] = []
            NativeIslandsRegistry.register(componentName: type) {
                let island = TrackingIsland()
                created.append(island)
                return island
            }
            let suiteName = "io.ionic.nativeislands.tests.\(UUID().uuidString)"
            let store = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { store.removePersistentDomain(forName: suiteName) }

            seedLaunchCache(type: type, store: store)
            XCTAssertEqual(created.count, 1)
            created.removeAll()

            // The next launch shows the cached frame as soon as the container is installed.
            let parent2 = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let webView2 = WKWebView(frame: parent2.bounds)
            parent2.addSubview(webView2)
            let controller2 = NativeIslandsController { _, _ in }
            controller2.launchCacheEnabled = true
            controller2.launchCacheStore = store
            controller2.ensureContainer(webView: webView2)
            defer { controller2.dispose() }

            XCTAssertEqual(created.count, 1)
            let frozenIsland = try XCTUnwrap(created.first)
            XCTAssertEqual(frozenIsland.createCalls.first?["headline"] as? String, "Cached Hero")
            XCTAssertTrue(shows(frozenIsland.view, in: parent2))

            // The page's first reset keeps it.
            controller2.reset()
            XCTAssertEqual(frozenIsland.destroyCalls, 0)
            XCTAssertTrue(shows(frozenIsland.view, in: parent2))

            // The page's first layout and create adopt it in place.
            let liveComp = makeComponent(
                id: "native-island-1",
                type: type,
                portal: "card:hero",
                x: 24,
                y: 64,
                width: 180,
                height: 180
            )
            controller2.applyLayout(
                components: [liveComp],
                order: ["native-island-1"],
                exclusions: [:],
                cutouts: [:],
                canvasColor: "#10141c",
                failure: { XCTFail("\($0): \($1)") }
            )
            controller2.command(
                island: "native-island-1",
                type: type,
                method: "create",
                params: ["headline": "Live Hero"],
                instance: 1
            ) { _ in }

            XCTAssertEqual(created.count, 1)
            XCTAssertEqual(frozenIsland.destroyCalls, 0)
            XCTAssertEqual(frozenIsland.createCalls.count, 1)
            XCTAssertEqual(frozenIsland.updateCalls.last?["headline"] as? String, "Live Hero")

            // Adopted by the page, it is the page's now: a reset destroys it.
            controller2.reset()
            XCTAssertEqual(frozenIsland.destroyCalls, 1)
        }
    }
#endif
