#if canImport(UIKit)
    import UIKit
    import WebKit

    /// A plane islands are placed in. Scans of WebKit's layers and views skip these, so they see only
    /// what WebKit made.
    final class NativeIslandsPlane: UIView {}

    extension CALayer {
        /// Whether this is the layer of a plane islands are placed in.
        var isIslandPlane: Bool {
            delegate is NativeIslandsPlane
        }

        /// The most layers a scan of WebKit's tree visits, so a very large page cannot stall the
        /// main thread.
        static let webKitScanLimit = 4000
    }

    /// Holds the two planes islands are placed in: one under the page, inside the WebView's scroll
    /// view, and one over it. The container is the WebView's top subview.
    final class NativeIslandsContainer: UIView {
        /// The WebView's backgrounds as the host app had them, restored when compositing ends.
        private struct WebViewOrigin {
            var opaque: Bool
            var background: UIColor?
            var scrollBackground: UIColor?
        }

        weak var webView: WKWebView?
        private var webViewOrigin: WebViewOrigin?
        let underlayPlane = NativeIslandsPlane()
        let overlayPlane = NativeIslandsPlane()
        var hosts: [String: NativeIslandsHost] = [:]
        /// The components of the last layout, with their regions.
        var components: [String: IslandComponent] = [:]
        var order: [String] = []
        let innerScroll = NativeIslandsScrollCoordinator()
        let motions: NativeIslandsMotions
        var onIslandVisibility: ((String, Bool) -> Void)?
        private var scrollObservation: NSKeyValueObservation?
        private var zoomObservation: NSKeyValueObservation?
        var panes: [String: Pane] = [:]

        /// Motions run on `pageClock`, which maps the page's time to native time.
        init(frame: CGRect = .zero, pageClock: NIPageClock = NIPageClock()) {
            self.motions = NativeIslandsMotions(pageClock: pageClock)
            super.init(frame: frame)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("NativeIslandsContainer is not loaded from an archive")
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            motions.webKitLayer = webView.layer
            motions.onFrame = { [weak self] frameTime in
                self?.placeIslands(at: frameTime)
            }
            motions.scrolled = { [weak self] timeline in
                guard let self else { return nil }
                guard let scroller = timeline.scroller else {
                    guard let scrollView = self.webView?.scrollView, scrollView.zoomScale > 0 else { return nil }
                    let offset = timeline.vertical ? scrollView.contentOffset.y : scrollView.contentOffset.x
                    return Double(offset / scrollView.zoomScale)
                }
                return innerScroll.scrollOffset(containerID: scroller).map { Double(timeline.vertical ? $0.y : $0.x) }
            }
            innerScroll.onChange = { [weak self] id in
                guard let self else { return }
                follow(innerScroll.componentIDs(affectedBy: id) + componentIDs(movedBy: motions.following(id)))
            }
            webViewOrigin = WebViewOrigin(
                opaque: webView.isOpaque,
                background: webView.backgroundColor,
                scrollBackground: webView.scrollView.backgroundColor
            )

            backgroundColor = .clear
            frame = webView.bounds
            autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.addSubview(self)

            underlayPlane.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            underlayPlane.backgroundColor = .clear
            underlayPlane.clipsToBounds = false
            underlayPlane.layer.anchorPoint = .zero
            underlayPlane.layer.position = .zero
            webView.scrollView.insertSubview(underlayPlane, at: 0)

            overlayPlane.frame = bounds
            overlayPlane.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlayPlane.backgroundColor = .clear
            overlayPlane.clipsToBounds = false
            addSubview(overlayPlane)

            scrollObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                self?.updateRootTrackedGeometry()
            }
            zoomObservation = webView.scrollView.observe(\.zoomScale, options: [.new]) { [weak self] _, _ in
                guard let self else { return }
                updateDocumentTransform()
                follow(innerScroll.componentIDs)
            }
            updateDocumentTransform()
        }

        func detachWebView() {
            scrollObservation?.invalidate()
            zoomObservation?.invalidate()
            scrollObservation = nil
            zoomObservation = nil
            onIslandVisibility = nil
            removeAllIslands()
            motions.webKitLayer = nil
            motions.onFrame = nil
            motions.scrolled = nil
            underlayPlane.removeFromSuperview()
            overlayPlane.removeFromSuperview()
            removeFromSuperview()

            guard let webView, let origin = webViewOrigin else { return }
            restoreBackground(of: webView, from: origin)
            self.webView = nil
        }

        func registerIsland(
            id: String,
            view: UIView,
            accessibility: NativeIslandAccessibility
        ) {
            hosts[id]?.view.removeFromSuperview()
            let host = NativeIslandsHost(island: view)
            host.view.accessibilityElementsHidden = accessibility == .web
            hosts[id] = host
            underlayPlane.addSubview(host.view)
        }

        func replaceIslandView(id: String, view: UIView) {
            hosts[id]?.hold(view)
        }

        func removeIsland(id: String) {
            hosts.removeValue(forKey: id)?.view.removeFromSuperview()
            components[id] = nil
            innerScroll.removeComponent(id: id)
            order.removeAll { $0 == id }
        }

        /// Hands island `oldID`'s host to `newID`, which shows it morphing from where `oldID` showed it.
        func transferIsland(from oldID: String, to newID: String) {
            if let host = hosts.removeValue(forKey: oldID) {
                host.handOver()
                hosts[newID] = host
            }
            components[newID] = components.removeValue(forKey: oldID)
            innerScroll.removeComponent(id: oldID)
            order.removeAll { $0 == oldID }
        }

        func removeAllIslands() {
            hosts.values.forEach { $0.view.removeFromSuperview() }
            hosts.removeAll()
            components.removeAll()
            order.removeAll()
            innerScroll.reset()
            motions.reset()
            removeAllPanes()
        }

        /// Places every island the layout shows and hides the rest. Returns the islands hidden
        /// because a scroll container they sit in has no native scroll view to follow.
        func applyLedger(
            components newComponents: [IslandComponent],
            scrollContainers: [IslandScrollContainer],
            order: [String],
            exclusions: [String: [IslandRegion]],
            cutouts: [String: [IslandRegion]],
            tints: [String: [IslandRegion]] = [:],
            motions incoming: [String: NIMotion] = [:],
            panes: [String: IslandPane] = [:]
        )
            -> [String: NIInnerScrollFailure] {
            motions.adopt(incoming)
            let frame = motions.frame()
            self.order = order
            components = Dictionary(uniqueKeysWithValues: newComponents.map { component in
                var component = component
                component.exclusions = exclusions[component.id] ?? []
                component.cutouts = cutouts[component.id] ?? []
                component.tints = tints[component.id] ?? []
                return (component.id, component)
            })
            let innerScrollFailures = innerScroll.prepare(
                components: newComponents,
                scrollContainers: scrollContainers,
                exclusions: exclusions,
                cutouts: cutouts.merging(tints) { $0 + $1 },
                webView: webView
            )

            for (id, host) in hosts where components[id] == nil {
                host.view.isHidden = true
            }
            for component in newComponents {
                show(component, unless: innerScrollFailures[component.id] != nil, in: frame)
            }
            applyPanes(panes, scrollContainers: scrollContainers)
            placePanes(in: frame)
            applyOrder()
            if underlayPlane.superview !== webView?.scrollView {
                underlayPlane.removeFromSuperview()
                webView?.scrollView.insertSubview(underlayPlane, at: 0)
            }
            webView?.scrollView.sendSubviewToBack(underlayPlane)
            webView?.bringSubviewToFront(self)
            bringSubviewToFront(overlayPlane)
            updateDocumentTransform()
            updateRootTrackedGeometry()
            notifyVisibility(in: frame)
            motions.scheduleFrames()
            return innerScrollFailures
        }

        /// Moves the component's host to its plane and places it there, or hides it when the layout
        /// does not show it or `failed`.
        private func show(_ component: IslandComponent, unless failed: Bool, in frame: NIMotionFrame) {
            guard let host = hosts[component.id] else { return }
            host.show(inPortal: component.portal != nil, fixed: component.scrollPath.isEmpty) {
                let parent = plane(for: component)
                if host.view.superview !== parent {
                    parent.addSubview(host.view)
                }
                guard !failed, component.active, let rect = component.rect, rect.width > 0, rect.height > 0 else {
                    host.view.isHidden = true
                    return false
                }
                host.view.isHidden = false
                place(component.id, in: frame, relayout: true)
                return true
            }
        }

        func setCompositingActive(_ active: Bool, canvasColor: UIColor? = nil) {
            guard let webView else { return }
            if active {
                webView.isOpaque = false
                webView.backgroundColor = .clear
                webView.scrollView.backgroundColor = canvasColor ?? webView.underPageBackgroundColor
            } else if let origin = webViewOrigin {
                restoreBackground(of: webView, from: origin)
            }
        }

        private func restoreBackground(of webView: WKWebView, from origin: WebViewOrigin) {
            webView.isOpaque = origin.opaque
            webView.backgroundColor = origin.background
            webView.scrollView.backgroundColor = origin.scrollBackground
        }

        func plane(for component: IslandComponent) -> UIView {
            component.plane == .overlay ? overlayPlane : underlayPlane
        }

        override func hitTest(
            _ point: CGPoint,
            with event: UIEvent?
        )
            -> UIView? {
            // Nil leaves the touch to the page under this view.
            guard webView != nil, !inLeadingEdge(point) else { return nil }
            let frame = motions.frame()
            // The topmost island under the point owns the touch, unless it is not interactive or the
            // page excludes the point. Only its own views take it: one it declines (beside a floating
            // tab bar, say) goes to whatever lies under it, not to the frames the host wraps it in.
            for id in order.reversed() {
                guard
                    let host = hosts[id],
                    !host.view.isHidden,
                    let component = components[id],
                    let body = screenBody(of: component, in: frame),
                    body.shape.contains(CGPoint(x: point.x - body.origin.x, y: point.y - body.origin.y)),
                    screenClips(id: id, in: frame).allSatisfy({ $0.contains(point) })
                else {
                    continue
                }
                let excluded = component.exclusions.contains {
                    !frame.fadedOut($0.motionPath) && screenIslandRect($0, in: frame).contains(point)
                }
                guard component.interactive, !excluded else { return nil }
                if let hit = host.view.hitTest(convert(point, to: host.view), with: event),
                   hit !== host.body, hit.isDescendant(of: host.body) {
                    return hit
                }
            }
            return nil
        }

        /// Touches at the leading edge go to the page, for swipe-back in the page's router. The home
        /// indicator needs no band: the system takes its gesture before the app sees it.
        private func inLeadingEdge(_ point: CGPoint) -> Bool {
            let band: CGFloat = 20
            guard bounds.contains(point) else { return false }
            return effectiveUserInterfaceLayoutDirection == .rightToLeft
                ? point.x >= bounds.width - band
                : point.x < band
        }
    }
#endif
