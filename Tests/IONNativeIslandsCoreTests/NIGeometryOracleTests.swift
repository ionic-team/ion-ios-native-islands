#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit
    import XCTest
    @testable import IONNativeIslandsLib

    /// Checks native geometry against the browser. `Fixtures/geometry-oracle.json` holds random pages
    /// Chrome drew: the layout the page sent iOS for each, then the page scrolled to a few places,
    /// with the offsets of its scrollers there and the box Chrome drew every island in. Given only
    /// that layout and those offsets, the container must place each island in the same box. A page
    /// the runtime plans on every frame (`follows`), as native cannot follow it from offsets alone,
    /// is checked against the layout it sent for each place. A navigation is checked at times as it
    /// runs, against the layout native holds at each.
    ///
    /// A scroller with no scroll view of its own scrolls to the offsets its layout carries, so each
    /// place is applied as the layout with those offsets, and the WebView scrolled to the document's.
    ///
    /// Regenerate it from capacitor-native-islands, after `npm run build` and
    /// `npm --prefix example-app run build`:
    /// `node scripts/geometry-oracle.mjs ios ../ion-ios-native-islands/Tests/IONNativeIslandsCoreTests/Fixtures/geometry-oracle.json`
    final class NIGeometryOracleTests: XCTestCase {
        private static let tolerance: CGFloat = 0.5

        func testTheContainerPlacesEveryIslandInTheBoxChromeDrawsItIn() throws {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/geometry-oracle.json")
            let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(fixture["platform"] as? String, "ios", "the fixture was made for another platform")
            let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
            var misses: [String] = []
            var checked = 0
            // One WebView for every page: each layout replaces the last page's islands, and a WebView
            // per page leaves WebKit work on the main queue for the tests after this one.
            let container = NativeIslandsContainer(frame: .zero)
            let webView = WKWebView(frame: .zero)
            container.attach(webView: webView)
            defer { container.detachWebView() }
            for page in cases {
                let seed = page["seed"] as? Int ?? 0
                let viewport = try XCTUnwrap(page["viewport"] as? [Double])
                container.frame = CGRect(x: 0, y: 0, width: viewport[0], height: viewport[1])
                webView.frame = container.bounds
                for (place, state) in try XCTUnwrap(page["states"] as? [[String: Any]]).enumerated() {
                    // A page planned on every frame sent native a layout for this place.
                    let sent = try XCTUnwrap(state["layout"] as? [String: Any] ?? page["layout"] as? [String: Any])
                    let layout = try read(sent, scrolledTo: state, seed: seed)
                    _ = container.applyLedger(
                        components: layout.components.map(\.0),
                        scrollContainers: layout.scrollContainers,
                        order: layout.order,
                        exclusions: layout.exclusions,
                        cutouts: layout.cutouts,
                        tints: layout.tints,
                        motions: layout.motions
                    )
                    webView.scrollView.contentOffset = CGPoint(x: number(state["scrollX"]), y: number(state["scrollY"]))
                    // A navigation was read at a time as it ran, a scroll whenever. A motion WebKit has
                    // not shown native plays on the page clock, as here.
                    let time = (state["time"] as? NSNumber)?.doubleValue ?? layout.sentAt ?? 0
                    let frame = NIMotionFrame(motions: layout.motions, held: [], time: time, scrolled: container.motions.scrolled)
                    let chrome = state["islands"] as? [String: [Double]] ?? [:]
                    for (component, _) in layout.components where component.active {
                        guard let expected = chrome[component.id], let box = container.screenRect(of: component, in: frame) else {
                            continue
                        }
                        checked += 1
                        let drawn = [box.x, box.y, box.x + box.width, box.y + box.height]
                        let off = zip(drawn, expected).map { abs($0 - CGFloat($1)) }.max() ?? 0
                        if off > Self.tolerance {
                            misses.append("page \(seed), place \(place), \(component.id): native \(drawn) Chrome \(expected) (off \(off))")
                        }
                    }
                }
            }
            XCTAssertGreaterThan(checked, 0, "the fixture checked no island")
            XCTAssertTrue(
                misses.isEmpty,
                "\(misses.count) of \(checked) island boxes differ from Chrome's (\(fixture["browser"] ?? "")):\n" +
                    misses.prefix(20).joined(separator: "\n")
            )
        }

        /// The page's layout as native reads it, its scrollers scrolled to where `state` has them.
        private func read(_ payload: [String: Any], scrolledTo state: [String: Any], seed: Int) throws -> NativeIslandsLayout {
            var payload = payload
            let offsets = Dictionary(
                uniqueKeysWithValues: (state["offsets"] as? [[String: Any]] ?? []).compactMap { offset in
                    (offset["id"] as? String).map { ($0, offset) }
                }
            )
            payload["scrollContainers"] = (payload["scrollContainers"] as? [[String: Any]] ?? []).map { container in
                guard let id = container["id"] as? String, let offset = offsets[id] else { return container }
                var scrolled = container
                scrolled["offsetX"] = offset["x"]
                scrolled["offsetY"] = offset["y"]
                return scrolled
            }
            if let refusal = NIBridgeSecurity.operationError("applyLayout", payload: payload) {
                XCTFail("page \(seed): the layout was refused (\(refusal.code): \(refusal.message))")
            }
            switch NativeIslandsLayoutParsing.layout(payload) {
            case .success(let layout):
                return layout
            case .failure(let refusal):
                XCTFail("page \(seed): the layout was refused (\(refusal.code): \(refusal.message))")
                throw refusal
            }
        }

        private func number(_ value: Any?) -> CGFloat {
            CGFloat((value as? NSNumber)?.doubleValue ?? 0)
        }
    }
#endif
