#if canImport(UIKit)
    import UIKit
    import WebKit

    final class NativeIslandsContainer: UIView {
        private weak var webView: WKWebView?
        private weak var originalWebViewParent: UIView?
        private var originalWebViewIndex = 0
        private var originalWebViewFrame = CGRect.zero
        private var originalWebViewAutoresizing: UIView.AutoresizingMask = []
        private var originalWebViewOpaque = true
        private var originalWebViewBackground: UIColor?
        private var originalScrollBackground: UIColor?
        private let documentLayer = UIView()
        private let overlayLayer = UIView()
        private var hosts: [String: UIView] = [:]
        private var contentHosts: [String: UIView] = [:]
        private let hostClipping = NativeIslandsHostClipping()
        private var components: [String: IslandComponent] = [:]
        private var layoutRects: [String: IslandRect] = [:]
        private let innerScroll = NativeIslandsScrollCoordinator()
        private var exclusions: [String: [IslandRegion]] = [:]
        private var cutouts: [String: [IslandRegion]] = [:]
        private var interactiveIDs: Set<String> = []
        private var order: [String] = []
        private var scrollObservation: NSKeyValueObservation?
        private var zoomObservation: NSKeyValueObservation?
        private var systemGestureInsets = NISystemGestureInsets()
        private let visibility = NativeIslandsVisibilityTracker()

        var onIslandVisibility: ((String, Bool) -> Void)? {
            get { visibility.onChange }
            set { visibility.onChange = newValue }
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            updateSystemGestureInsets()
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            innerScroll.onChange = { [weak self] id in
                self?.updateInnerScrollGeometry(containerID: id)
            }
            originalWebViewParent = webView.superview
            originalWebViewIndex =
                webView.superview?.subviews.firstIndex(of: webView) ?? 0
            originalWebViewFrame = webView.frame
            originalWebViewAutoresizing = webView.autoresizingMask
            originalWebViewOpaque = webView.isOpaque
            originalWebViewBackground = webView.backgroundColor
            originalScrollBackground = webView.scrollView.backgroundColor

            updateSystemGestureInsets()
            backgroundColor = .clear
            webView.frame = bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(webView)

            documentLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            documentLayer.backgroundColor = .clear
            documentLayer.clipsToBounds = false
            documentLayer.layer.anchorPoint = .zero
            documentLayer.layer.position = .zero
            webView.scrollView.insertSubview(documentLayer, at: 0)

            overlayLayer.frame = bounds
            overlayLayer.autoresizingMask = [
                .flexibleWidth,
                .flexibleHeight,
            ]
            overlayLayer.backgroundColor = .clear
            overlayLayer.clipsToBounds = false
            addSubview(overlayLayer)

            scrollObservation = webView.scrollView.observe(
                \.contentOffset,
                options: [.new]
            ) { [weak self] _, _ in
                self?.updateRootTrackedGeometry()
            }
            zoomObservation = webView.scrollView.observe(
                \.zoomScale,
                options: [.new]
            ) { [weak self] _, _ in
                self?.updateDocumentTransform()
                self?.updateAllInnerScrollGeometry()
                self?.notifyVisibility()
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
            documentLayer.removeFromSuperview()
            overlayLayer.removeFromSuperview()

            guard let webView else { return }
            webView.removeFromSuperview()
            if let parent = originalWebViewParent {
                parent.insertSubview(
                    webView,
                    at: min(originalWebViewIndex, parent.subviews.count)
                )
            }
            webView.frame = originalWebViewFrame
            webView.autoresizingMask = originalWebViewAutoresizing
            webView.isOpaque = originalWebViewOpaque
            webView.backgroundColor = originalWebViewBackground
            webView.scrollView.backgroundColor = originalScrollBackground
            self.webView = nil
        }

        func registerIsland(
            id: String,
            view: UIView,
            accessibility: NativeIslandAccessibility
        ) {
            hosts[id]?.removeFromSuperview()
            hostClipping.remove(id: id)
            let host = UIView(
                frame: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
            host.isHidden = true
            host.accessibilityElementsHidden = accessibility == .web
            let contentHost = UIView(frame: host.bounds)
            contentHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(contentHost)
            view.frame = contentHost.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentHost.addSubview(view)
            hosts[id] = host
            contentHosts[id] = contentHost
            documentLayer.addSubview(host)
        }

        func removeIsland(id: String) {
            hosts.removeValue(forKey: id)?.removeFromSuperview()
            contentHosts[id] = nil
            hostClipping.remove(id: id)
            components[id] = nil
            layoutRects[id] = nil
            innerScroll.removeComponent(id: id)
            exclusions[id] = nil
            cutouts[id] = nil
            interactiveIDs.remove(id)
            visibility.remove(id: id)
            order.removeAll { $0 == id }
        }

        func removeAllIslands() {
            hosts.values.forEach { $0.removeFromSuperview() }
            hosts.removeAll()
            contentHosts.removeAll()
            hostClipping.reset()
            components.removeAll()
            layoutRects.removeAll()
            innerScroll.reset()
            exclusions.removeAll()
            cutouts.removeAll()
            interactiveIDs.removeAll()
            visibility.reset()
            order.removeAll()
        }

        func applyLedger(
            components newComponents: [IslandComponent],
            scrollContainers: [IslandScrollContainer],
            order: [String],
            exclusions: [String: [IslandRegion]],
            cutouts: [String: [IslandRegion]]
        )
            -> [String: String] {
            self.order = order
            self.exclusions = exclusions
            self.cutouts = cutouts
            components = Dictionary(
                uniqueKeysWithValues: newComponents.map { ($0.id, $0) }
            )
            let innerScrollFailures = prepareInnerScrollBindings(
                components: newComponents,
                scrollContainers: scrollContainers,
                exclusions: exclusions,
                cutouts: cutouts
            )
            interactiveIDs = Set(
                newComponents
                    .filter {
                        $0.active &&
                            $0.interactive &&
                            $0.rect != nil &&
                            innerScrollFailures[$0.id] == nil
                    }
                    .map(\.id)
            )

            let liveIDs = Set(newComponents.map(\.id))
            for (id, host) in hosts where !liveIDs.contains(id) {
                host.isHidden = true
                layoutRects[id] = nil
            }

            for component in newComponents {
                guard let host = hosts[component.id] else { continue }
                let parent = component.plane == .overlay
                    ? overlayLayer
                    : documentLayer
                if host.superview !== parent {
                    host.removeFromSuperview()
                    parent.addSubview(host)
                }
                guard
                    component.active,
                    let rect = component.rect,
                    rect.width >= 1,
                    rect.height >= 1,
                    innerScrollFailures[component.id] == nil
                else {
                    host.isHidden = true
                    layoutRects[component.id] = nil
                    continue
                }
                layoutRects[component.id] = rect
                host.isHidden = false
                updateHostGeometry(id: component.id)
            }

            applyOrder()
            if documentLayer.superview !== webView?.scrollView {
                documentLayer.removeFromSuperview()
                webView?.scrollView.insertSubview(documentLayer, at: 0)
            }
            webView?.scrollView.sendSubviewToBack(documentLayer)
            bringSubviewToFront(overlayLayer)
            updateDocumentTransform()
            updateRootTrackedGeometry()
            notifyVisibility()
            return innerScrollFailures
        }

        func setCompositingActive(_ active: Bool) {
            guard let webView else { return }
            if active {
                webView.isOpaque = false
                webView.backgroundColor = .clear
                webView.scrollView.backgroundColor = .clear
            } else {
                webView.isOpaque = originalWebViewOpaque
                webView.backgroundColor = originalWebViewBackground
                webView.scrollView.backgroundColor = originalScrollBackground
            }
        }

        override func hitTest(
            _ point: CGPoint,
            with event: UIEvent?
        )
            -> UIView? {
            guard webView != nil else {
                return super.hitTest(point, with: event)
            }
            if systemGestureInsets.contains(
                x: Double(point.x),
                y: Double(point.y),
                width: Double(bounds.width),
                height: Double(bounds.height)
            ) {
                return webHitTest(point, event: event)
            }
            let decision = NativeIslandsHitTesting.decide(
                point: point,
                order: order
            ) { [self] id in
                guard
                    let host = hosts[id],
                    !host.isHidden,
                    let component = components[id],
                    let layoutRect = component.rect
                else {
                    return nil
                }
                return NativeIslandsHitGeometry(
                    rect: screenIslandRect(
                        layoutRect,
                        coordinateSpace: component.coordinateSpace,
                        scrollPath: component.scrollPath
                    ),
                    scrollports: screenScrollports(id: id),
                    exclusions: (exclusions[id] ?? []).map(screenIslandRect),
                    interactive: interactiveIDs.contains(id)
                )
            }
            if decision.owner == "island",
               let target = decision.island,
               let targetView = hosts[target] {
                let converted = convert(point, to: targetView)
                return targetView.hitTest(converted, with: event) ?? targetView
            }
            return webHitTest(point, event: event)
        }

        private func prepareInnerScrollBindings(
            components: [IslandComponent],
            scrollContainers: [IslandScrollContainer],
            exclusions: [String: [IslandRegion]],
            cutouts: [String: [IslandRegion]]
        )
            -> [String: String] {
            innerScroll.prepare(
                components: components,
                scrollContainers: scrollContainers,
                exclusions: exclusions,
                cutouts: cutouts,
                webView: webView
            )
        }

        private func updateAllInnerScrollGeometry() {
            for id in innerScroll.componentIDs {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
            notifyVisibility()
        }

        private func updateInnerScrollGeometry(containerID: String) {
            for id in innerScroll.componentIDs(affectedBy: containerID) {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
            notifyVisibility()
        }

        private func updateHostGeometry(
            id: String,
            updateStaticGeometry: Bool = true
        ) {
            guard
                let host = hosts[id],
                let contentHost = contentHosts[id],
                let component = components[id],
                let layoutRect = layoutRects[id]
            else {
                return
            }
            let screen = screenIslandRect(
                layoutRect,
                coordinateSpace: component.coordinateSpace,
                scrollPath: component.scrollPath
            )
            let parent = component.plane == .overlay
                ? overlayLayer
                : documentLayer
            host.frame = parent.convert(screen.cgRect, from: self)
            contentHost.frame = host.bounds
            let localScale = screen.width > 0
                ? host.bounds.width / screen.width
                : 1
            let cornerRadius = NIContainerGeometry.clampedCornerRadius(
                width: host.bounds.width,
                height: host.bounds.height,
                cornerRadius: screen.cornerRadius * abs(localScale)
            )
            host.layer.cornerRadius = cornerRadius
            host.layer.masksToBounds = cornerRadius > 0

            let localScrollports = screenScrollports(id: id).map {
                NativeIslandsCoordinateMapping.localRect(
                    $0,
                    container: self,
                    view: host
                )
            }
            hostClipping.applyScrollports(
                to: host,
                contentHost: contentHost,
                islandID: id,
                scrollports: localScrollports
            )
            let localCutouts = (cutouts[id] ?? []).map {
                NativeIslandsCoordinateMapping.localRect(
                    screenIslandRect($0),
                    container: self,
                    view: contentHost
                )
            }
            hostClipping.applyCutouts(
                to: contentHost,
                cutouts: localCutouts
            )
            if updateStaticGeometry {
                host.setNeedsLayout()
            }
        }

        private func applyOrder() {
            var documentIndex = 0
            var overlayIndex = 0
            for id in order {
                guard
                    let host = hosts[id],
                    let component = components[id]
                else {
                    continue
                }
                if component.plane == .overlay {
                    overlayLayer.insertSubview(
                        host,
                        at: min(overlayIndex, overlayLayer.subviews.count)
                    )
                    overlayIndex += 1
                } else {
                    documentLayer.insertSubview(
                        host,
                        at: min(documentIndex, documentLayer.subviews.count)
                    )
                    documentIndex += 1
                }
            }
        }

        private func notifyVisibility() {
            visibility.update(
                container: self,
                hosts: hosts,
                screenScrollports: { [weak self] id in
                    self?.screenScrollports(id: id).map(\.cgRect) ?? []
                }
            )
        }

        private func screenIslandRect(_ region: IslandRegion) -> IslandRect {
            screenIslandRect(
                region.rect,
                coordinateSpace: region.coordinateSpace,
                scrollPath: region.scrollPath
            )
        }

        private func screenIslandRect(
            _ rect: IslandRect,
            coordinateSpace: NICoordinateSpace,
            scrollPath: [String]
        )
            -> IslandRect {
            NativeIslandsCoordinateMapping.screenRect(
                rect,
                coordinateSpace: coordinateSpace,
                nestedOffset: innerScroll.offset(path: scrollPath),
                zoom: webView?.scrollView.zoomScale ?? 1,
                rootOffset: webView?.scrollView.contentOffset ?? .zero
            )
        }

        private func screenScrollports(id: String) -> [IslandRect] {
            innerScroll.scrollports(componentID: id).map {
                screenIslandRect(
                    $0,
                    coordinateSpace: .document,
                    scrollPath: []
                )
            }
        }

        private func updateRootTrackedGeometry() {
            for (id, component) in components
                where component.plane == .overlay ||
                component.coordinateSpace == .viewport ||
                (cutouts[id] ?? []).contains(where: {
                    $0.coordinateSpace == .viewport
                }) {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
            notifyVisibility()
        }

        private func updateDocumentTransform() {
            guard let scrollView = webView?.scrollView else { return }
            documentLayer.transform = CGAffineTransform(
                scaleX: scrollView.zoomScale,
                y: scrollView.zoomScale
            )
        }
    }

    extension NativeIslandsContainer {
        private func webHitTest(
            _ point: CGPoint,
            event: UIEvent?
        )
            -> UIView {
            guard let webView else { return self }
            let converted = convert(point, to: webView)
            return webView.hitTest(converted, with: event) ?? webView
        }

        private func updateSystemGestureInsets() {
            let leading: Double = 20
            let rightToLeft =
                effectiveUserInterfaceLayoutDirection == .rightToLeft
            systemGestureInsets = NISystemGestureInsets(
                left: rightToLeft ? 0 : leading,
                right: rightToLeft ? leading : 0,
                bottom: Double(safeAreaInsets.bottom)
            )
        }
    }
#endif
