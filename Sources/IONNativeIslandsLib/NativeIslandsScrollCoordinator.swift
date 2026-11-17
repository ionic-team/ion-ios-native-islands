#if canImport(UIKit)
    import UIKit
    import WebKit

    /// The scroll view a scroll container follows, and how far its native offset ran ahead of the
    /// page's when it was bound.
    private struct InnerScrollBinding {
        let view: UIScrollView
        let offsetBias: CGPoint
        let observation: NSKeyValueObservation
    }

    /// Why an island cannot follow scroll container `container`: it has no native scroll view, or
    /// more than one could be it.
    struct NIInnerScrollFailure: Equatable {
        let container: String
        let kind: NIScrollContainerMatchFailure

        var reason: String {
            "inner_scroll_unavailable:\(container):\(kind.rawValue)"
        }
    }

    final class NativeIslandsScrollCoordinator {
        private weak var webView: WKWebView?
        private var containers: [String: IslandScrollContainer] = [:]
        private var paintOrder: [String: Int] = [:]
        private var componentPaths: [String: [String]] = [:]
        private var regionPaths: [String: [[String]]] = [:]
        private var bindings: [String: InnerScrollBinding] = [:]

        var onChange: ((String) -> Void)?

        var componentIDs: [String] {
            Array(componentPaths.keys)
        }

        func removeComponent(id: String) {
            componentPaths[id] = nil
            regionPaths[id] = nil
        }

        func reset() {
            bindings.values.forEach { $0.observation.invalidate() }
            clear()
        }

        private func clear() {
            bindings.removeAll()
            componentPaths.removeAll()
            regionPaths.removeAll()
            containers.removeAll()
            paintOrder.removeAll()
            webView = nil
        }

        func prepare(
            components: [IslandComponent],
            scrollContainers: [IslandScrollContainer],
            exclusions: [String: [IslandRegion]],
            cutouts: [String: [IslandRegion]],
            webView: WKWebView?
        )
            -> [String: NIInnerScrollFailure] {
            let previous = bindings
            clear()
            // A scroll view still bound keeps its observation; the others stop.
            defer {
                let kept = Set(bindings.values.map { ObjectIdentifier($0.observation) })
                for binding in previous.values where !kept.contains(ObjectIdentifier(binding.observation)) {
                    binding.observation.invalidate()
                }
            }
            self.webView = webView
            containers = Dictionary(uniqueKeysWithValues: scrollContainers.map { ($0.id, $0) })
            paintOrder = Dictionary(uniqueKeysWithValues: scrollContainers.enumerated().map { ($1.id, $0) })
            componentPaths = Dictionary(uniqueKeysWithValues: components.map { ($0.id, $0.scrollPath) })
            let shown = components.filter { $0.active && $0.rect != nil }
            for component in shown {
                regionPaths[component.id] =
                    (exclusions[component.id] ?? []).map(\.scrollPath) +
                    (cutouts[component.id] ?? []).map(\.scrollPath) +
                    component.clips.map(\.scrollPath)
            }

            let referencedIDs = Set(
                shown.flatMap(\.scrollPath) + regionPaths.values.flatMap { $0 }.flatMap { $0 }
            )
            guard !referencedIDs.isEmpty else { return [:] }
            guard let webView else {
                return failures(
                    shown: shown,
                    unmatched: Dictionary(uniqueKeysWithValues: referencedIDs.map { ($0, .missing) })
                )
            }
            return failures(shown: shown, unmatched: bindScrollViews(for: referencedIDs, in: webView, keeping: previous))
        }

        /// Binds each scroller in `ids` to the scroll view WebKit made for it, and returns why the rest
        /// have none. `previous` holds the bindings of the last layout.
        private func bindScrollViews(
            for ids: Set<String>,
            in webView: WKWebView,
            keeping previous: [String: InnerScrollBinding]
        )
            -> [String: NIScrollContainerMatchFailure] {
            let candidates = nestedScrollViews(in: webView)
            let expected = expectedGeometries(ids: ids, webView: webView)
            let found = scrollCandidates(candidates, webView: webView)
            // Points a scroll view's geometry may differ from the page's and still match, to absorb
            // rounding between CSS pixels and native points.
            let tolerance = 1.5
            let result = NIScrollContainerMatching.match(
                descriptors: expected,
                candidates: found,
                tolerance: tolerance,
                optional: Set(
                    containers.values
                        .filter { $0.offsetX == 0 && $0.offsetY == 0 }
                        .map(\.id)
                )
            )
            let zoom = webView.scrollView.zoomScale
            for (id, key) in result.matches {
                guard let descriptor = containers[id], zoom > 0 else { continue }
                let scrollView = candidates[key]
                let moving = scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
                let settled = !moving && (expected[id].map {
                    NIScrollContainerMatching.offsetsMatch($0.geometry, found[key].geometry, tolerance: tolerance)
                } ?? true)
                // The bias is measured only while the scroller is still at the offset the page sent;
                // otherwise the same scroll view keeps the bias it had.
                let bias = settled
                    ? CGPoint(
                        x: scrollView.contentOffset.x / zoom - descriptor.offsetX,
                        y: scrollView.contentOffset.y / zoom - descriptor.offsetY
                    )
                    : previous[id].flatMap { $0.view === scrollView ? $0.offsetBias : nil } ?? .zero
                bind(id, to: scrollView, offsetBias: bias, keeping: previous[id])
            }
            var unmatched = result.failures
            let bound = Set(bindings.values.map { ObjectIdentifier($0.view) })
            for id in expected.keys where result.matches[id] == nil {
                // A scroller sliding with its page can match nothing; it keeps the scroll view it had
                // while that is still in the WebView and no other scroller took it.
                guard
                    let kept = previous[id],
                    kept.view.isDescendant(of: webView),
                    !bound.contains(ObjectIdentifier(kept.view))
                else {
                    continue
                }
                bind(id, to: kept.view, offsetBias: kept.offsetBias, keeping: kept)
                unmatched[id] = nil
            }
            return unmatched
        }

        /// Follows `scrollView` for scroller `id`, with the observation `previous` had when it bound the
        /// same scroll view.
        private func bind(_ id: String, to scrollView: UIScrollView, offsetBias: CGPoint, keeping previous: InnerScrollBinding?) {
            let observation = previous.flatMap { $0.view === scrollView ? $0.observation : nil } ??
                scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.onChange?(id)
                }
            bindings[id] = InnerScrollBinding(view: scrollView, offsetBias: offsetBias, observation: observation)
        }

        func componentIDs(affectedBy containerID: String) -> [String] {
            componentPaths.compactMap {
                let paths = regionPaths[$0.key] ?? []
                return $0.value.contains(containerID) ||
                    paths.contains { $0.contains(containerID) }
                    ? $0.key
                    : nil
            }
        }

        func scrollports(componentID: String) -> [IslandRegion] {
            (componentPaths[componentID] ?? []).compactMap { containers[$0]?.scrollport }
        }

        /// How far the scrollers on `path` move what they hold on the page: each offset drawn as the
        /// transforms at and above its scroller draw it, less how the sticky box it sits in moves it on.
        func offset(path: [String]) -> CGPoint {
            path.reduce(into: .zero) { result, id in
                let value = drawnOffset(containerID: id)
                let shift = containers[id].map(stuck) ?? .zero
                result.x += value.x - shift.dx
                result.y += value.y - shift.dy
            }
        }

        /// How the sticky box `container` sits in moves it, and what it holds, from where it is laid out.
        private func stuck(_ container: IslandScrollContainer) -> CGVector {
            container.sticky.map { $0.offset(in: stickyView($0)) } ?? .zero
        }

        /// What `sticky`'s scroller shows of its content now, or the document's viewport.
        func stickyView(_ sticky: NISticky) -> CGRect {
            if let scroller = sticky.scroller {
                return visibleContent(containerID: scroller) ?? .zero
            }
            guard let scrollView = webView?.scrollView, scrollView.zoomScale > 0 else { return .zero }
            let zoom = scrollView.zoomScale
            return CGRect(
                x: scrollView.contentOffset.x / zoom,
                y: scrollView.contentOffset.y / zoom,
                width: scrollView.bounds.width / zoom,
                height: scrollView.bounds.height / zoom
            )
        }

        private func drawnOffset(containerID: String) -> CGPoint {
            offset(containerID: containerID).applying(containers[containerID]?.linear ?? .identity)
        }

        /// How far scroller `containerID` is scrolled, in CSS px; nil when it is not in the layout.
        func scrollOffset(containerID: String) -> CGPoint? {
            containers[containerID] == nil ? nil : offset(containerID: containerID)
        }

        private func offset(containerID: String) -> CGPoint {
            guard let descriptor = containers[containerID] else { return .zero }
            let zoom = webView?.scrollView.zoomScale ?? 1
            guard let binding = bindings[containerID], zoom > 0 else {
                return CGPoint(x: descriptor.offsetX, y: descriptor.offsetY)
            }
            let scrollView = binding.view
            return NIContainerGeometry.calibratedScrollOffset(
                nativeOffset: scrollView.contentOffset,
                zoom: zoom,
                bias: binding.offsetBias,
                maxDomOffset: CGPoint(
                    x: max(0, descriptor.contentWidth - descriptor.rect.width),
                    y: max(0, descriptor.contentHeight - descriptor.rect.height)
                ),
                maxNativeOffset: CGPoint(
                    x: max(0, (scrollView.contentSize.width - scrollView.bounds.width) / zoom),
                    y: max(0, (scrollView.contentSize.height - scrollView.bounds.height) / zoom)
                )
            )
        }

        func visibleContent(containerID: String) -> CGRect? {
            guard let descriptor = containers[containerID] else { return nil }
            let offset = drawnOffset(containerID: containerID)
            return CGRect(
                x: descriptor.rect.x + offset.x,
                y: descriptor.rect.y + offset.y,
                width: descriptor.rect.width,
                height: descriptor.rect.height
            )
        }

        private func descriptorOffset(path: [String]) -> CGPoint {
            path.reduce(into: .zero) { result, id in
                guard let descriptor = containers[id] else { return }
                let offset = CGPoint(x: descriptor.offsetX, y: descriptor.offsetY).applying(descriptor.linear)
                let shift = stuck(descriptor)
                result.x += offset.x - shift.dx
                result.y += offset.y - shift.dy
            }
        }

        private func expectedGeometries(
            ids: Set<String>,
            webView: WKWebView
        )
            -> [String: NIScrollContainerDescriptor] {
            let zoom = webView.scrollView.zoomScale
            let rootOffset = webView.scrollView.contentOffset
            return ids.reduce(into: [:]) { values, id in
                guard let descriptor = containers[id] else { return }
                // WebKit draws a scroller in a sticky box where the box has stuck it.
                let shift = stuck(descriptor)
                var rect = descriptor.rect
                rect.x += shift.dx
                rect.y += shift.dy
                let frame = NIContainerGeometry.screenRect(
                    rect,
                    coordinateSpace: descriptor.coordinateSpace,
                    nestedOffset: descriptorOffset(path: descriptor.scrollPath),
                    zoom: zoom,
                    rootOffset: rootOffset
                )
                values[id] = NIScrollContainerDescriptor(
                    geometry: NIScrollContainerGeometry(
                        x: Double(frame.x),
                        y: Double(frame.y),
                        width: Double(frame.width),
                        height: Double(frame.height),
                        contentWidth: Double(descriptor.contentWidth * zoom),
                        contentHeight: Double(descriptor.contentHeight * zoom),
                        offsetX: Double(descriptor.offsetX * zoom),
                        offsetY: Double(descriptor.offsetY * zoom)
                    ),
                    scrollPath: descriptor.scrollPath,
                    order: paintOrder[id] ?? 0
                )
            }
        }

        private func scrollCandidates(
            _ scrollViews: [UIScrollView],
            webView: WKWebView
        )
            -> [NIScrollContainerCandidate] {
            let keys = Dictionary(
                uniqueKeysWithValues: scrollViews.enumerated().map {
                    (ObjectIdentifier($0.element), $0.offset)
                }
            )
            return scrollViews.enumerated().map { index, scrollView in
                let frame = scrollView.convert(scrollView.bounds, to: webView)
                var ancestors: [Int] = []
                var current = scrollView.superview
                while let view = current, view !== webView {
                    if let ancestor = view as? UIScrollView,
                       let key = keys[ObjectIdentifier(ancestor)] {
                        ancestors.append(key)
                    }
                    current = view.superview
                }
                return NIScrollContainerCandidate(
                    key: index,
                    geometry: NIScrollContainerGeometry(
                        x: Double(frame.minX),
                        y: Double(frame.minY),
                        width: Double(frame.width),
                        height: Double(frame.height),
                        contentWidth: Double(scrollView.contentSize.width),
                        contentHeight: Double(scrollView.contentSize.height),
                        offsetX: Double(scrollView.contentOffset.x),
                        offsetY: Double(scrollView.contentOffset.y)
                    ),
                    ancestorKeys: Array(ancestors.reversed())
                )
            }
        }

        private func failures(
            shown: [IslandComponent],
            unmatched: [String: NIScrollContainerMatchFailure]
        )
            -> [String: NIInnerScrollFailure] {
            shown.reduce(into: [:]) { output, component in
                let paths = [component.scrollPath] +
                    (regionPaths[component.id] ?? [])
                guard let id = paths
                    .flatMap({ $0 })
                    .first(where: {
                        unmatched[$0] != nil || containers[$0] == nil
                    })
                else {
                    return
                }
                output[component.id] = NIInnerScrollFailure(container: id, kind: unmatched[id] ?? .missing)
            }
        }

        private func nestedScrollViews(in webView: WKWebView) -> [UIScrollView] {
            var scrollViews: [UIScrollView] = []
            func visit(_ view: UIView) {
                guard !(view is NativeIslandsPlane) else { return }
                if let scrollView = view as? UIScrollView,
                   scrollView !== webView.scrollView {
                    scrollViews.append(scrollView)
                }
                view.subviews.forEach(visit)
            }
            visit(webView)
            return scrollViews
        }
    }
#endif
