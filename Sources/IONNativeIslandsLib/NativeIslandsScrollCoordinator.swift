#if canImport(UIKit)
    import UIKit
    import WebKit

    private struct InnerScrollBinding {
        var offsetBias: CGPoint
    }

    final class NativeIslandsScrollCoordinator {
        private weak var webView: WKWebView?
        private var containers: [String: IslandScrollContainer] = [:]
        private var componentPaths: [String: [String]] = [:]
        private var regionPaths: [String: [[String]]] = [:]
        private var bindings: [String: InnerScrollBinding] = [:]
        private var views: [String: UIScrollView] = [:]
        private var observations: [String: NSKeyValueObservation] = [:]

        var onChange: ((String) -> Void)?

        var componentIDs: [String] {
            Array(componentPaths.keys)
        }

        func path(componentID: String) -> [String] {
            componentPaths[componentID] ?? []
        }

        func removeComponent(id: String) {
            componentPaths[id] = nil
            regionPaths[id] = nil
        }

        func reset() {
            observations.values.forEach { $0.invalidate() }
            observations.removeAll()
            views.removeAll()
            bindings.removeAll()
            componentPaths.removeAll()
            regionPaths.removeAll()
            containers.removeAll()
            webView = nil
        }

        func prepare(
            components: [IslandComponent],
            scrollContainers: [IslandScrollContainer],
            exclusions: [String: [IslandRegion]],
            cutouts: [String: [IslandRegion]],
            webView: WKWebView?
        )
            -> [String: String] {
            reset()
            self.webView = webView
            containers = Dictionary(
                uniqueKeysWithValues: scrollContainers.map { ($0.id, $0) }
            )
            componentPaths = Dictionary(
                uniqueKeysWithValues: components.map { ($0.id, $0.scrollPath) }
            )
            let activeIDs = Set(
                components
                    .filter { $0.active && $0.rect != nil }
                    .map(\.id)
            )
            for id in activeIDs {
                regionPaths[id] =
                    (exclusions[id] ?? []).map(\.scrollPath) +
                    (cutouts[id] ?? []).map(\.scrollPath)
            }

            let referencedIDs = Set(
                components.flatMap {
                    $0.active && $0.rect != nil ? $0.scrollPath : []
                } +
                    regionPaths.values.flatMap { $0 }.flatMap { $0 }
            )
            guard !referencedIDs.isEmpty else { return [:] }
            guard let webView else {
                return failures(
                    components: components,
                    matches: Dictionary(
                        uniqueKeysWithValues: referencedIDs.map {
                            ($0, .missing)
                        }
                    )
                )
            }

            let candidates = nestedScrollViews(in: webView)
            let result = NIScrollContainerMatching.match(
                descriptors: expectedGeometries(
                    ids: referencedIDs,
                    webView: webView
                ),
                candidates: scrollCandidates(
                    candidates,
                    webView: webView
                ),
                tolerance: 1.5
            )
            let zoom = webView.scrollView.zoomScale
            for (id, key) in result.matches {
                guard
                    candidates.indices.contains(key),
                    let descriptor = containers[id],
                    zoom > 0
                else {
                    continue
                }
                let scrollView = candidates[key]
                views[id] = scrollView
                bindings[id] = InnerScrollBinding(
                    offsetBias: CGPoint(
                        x: scrollView.contentOffset.x / zoom -
                            descriptor.offsetX,
                        y: scrollView.contentOffset.y / zoom -
                            descriptor.offsetY
                    )
                )
                observations[id] = scrollView.observe(
                    \.contentOffset,
                    options: [.new]
                ) { [weak self] _, _ in
                    self?.onChange?(id)
                }
            }
            return failures(
                components: components,
                matches: result.failures
            )
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

        func offset(componentID: String) -> CGPoint {
            offset(path: path(componentID: componentID))
        }

        func scrollports(componentID: String) -> [IslandRect] {
            scrollports(path: path(componentID: componentID))
        }

        func scrollports(path: [String]) -> [IslandRect] {
            path.compactMap(currentScrollportRect)
        }

        func offset(path: [String]) -> CGPoint {
            path.reduce(into: .zero) { result, id in
                let value = offset(containerID: id)
                result.x += value.x
                result.y += value.y
            }
        }

        private func offset(containerID: String) -> CGPoint {
            guard
                let descriptor = containers[containerID],
                let binding = bindings[containerID],
                let scrollView = views[containerID]
            else {
                guard let descriptor = containers[containerID] else {
                    return .zero
                }
                return CGPoint(
                    x: descriptor.offsetX,
                    y: descriptor.offsetY
                )
            }
            let zoom = webView?.scrollView.zoomScale ?? 1
            guard zoom > 0 else {
                return CGPoint(
                    x: descriptor.offsetX,
                    y: descriptor.offsetY
                )
            }
            return NIContainerGeometry.calibratedScrollOffset(
                nativeOffset: scrollView.contentOffset,
                zoom: zoom,
                bias: binding.offsetBias
            )
        }

        private func descriptorOffset(path: [String]) -> CGPoint {
            path.reduce(into: .zero) { result, id in
                guard let descriptor = containers[id] else { return }
                result.x += descriptor.offsetX
                result.y += descriptor.offsetY
            }
        }

        private func currentScrollportRect(id: String) -> IslandRect? {
            guard let descriptor = containers[id] else { return nil }
            let ancestorOffset = offset(path: descriptor.scrollPath)
            return IslandRect(
                x: descriptor.rect.x - ancestorOffset.x,
                y: descriptor.rect.y - ancestorOffset.y,
                width: descriptor.rect.width,
                height: descriptor.rect.height,
                cornerRadius: descriptor.rect.cornerRadius
            )
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
                let ancestorOffset = descriptorOffset(
                    path: descriptor.scrollPath
                )
                values[id] = NIScrollContainerDescriptor(
                    geometry: NIScrollContainerGeometry(
                        x: Double(
                            (descriptor.rect.x - ancestorOffset.x) * zoom -
                                rootOffset.x
                        ),
                        y: Double(
                            (descriptor.rect.y - ancestorOffset.y) * zoom -
                                rootOffset.y
                        ),
                        width: Double(descriptor.rect.width * zoom),
                        height: Double(descriptor.rect.height * zoom),
                        contentWidth: Double(descriptor.contentWidth * zoom),
                        contentHeight: Double(descriptor.contentHeight * zoom),
                        offsetX: Double(descriptor.offsetX * zoom),
                        offsetY: Double(descriptor.offsetY * zoom)
                    ),
                    scrollPath: descriptor.scrollPath
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
            components: [IslandComponent],
            matches: [String: NIScrollContainerMatchFailure]
        )
            -> [String: String] {
            components.reduce(into: [:]) { output, component in
                guard component.active, component.rect != nil else { return }
                let paths = [component.scrollPath] +
                    (regionPaths[component.id] ?? [])
                guard let id = paths
                    .flatMap({ $0 })
                    .first(where: {
                        matches[$0] != nil || containers[$0] == nil
                    })
                else {
                    return
                }
                let detail = switch matches[id] ?? .missing {
                case .missing:
                    "missing"
                case .ambiguous:
                    "ambiguous"
                case .sharedCandidate:
                    "shared"
                }
                output[component.id] =
                    "inner_scroll_unavailable:\(id):\(detail)"
            }
        }

        private func nestedScrollViews(in webView: WKWebView) -> [UIScrollView] {
            var scrollViews: [UIScrollView] = []
            func visit(_ view: UIView) {
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
