#if canImport(UIKit)
    import UIKit

    /// Placement: where each island, its clips, cuts and tints are drawn for one motion frame.
    extension NativeIslandsContainer {
        func updateRootTrackedGeometry() {
            follow(components.filter { _, component in
                component.plane == .overlay || component.coordinateSpace == .viewport ||
                    component.sticky.map { $0.scroller == nil } == true ||
                    (component.cutouts + component.tints + component.clips).contains(where: followsRoot)
            }.map(\.key))
        }

        /// Moves `ids` and every pane after a scroll, and reports what came into or left view.
        func follow(_ ids: [String]) {
            let frame = motions.frame()
            for id in ids {
                place(id, in: frame)
            }
            placePanes(in: frame)
            notifyVisibility(in: frame)
        }

        /// Places the islands a motion moves, fades or clips for the display frame shown at native
        /// time `frameTime`.
        func placeIslands(at frameTime: CFTimeInterval) {
            let frame = motions.frame(at: frameTime)
            let moving = motions.placing(frame)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (id, component) in components where carries(component, id: id, onAnyOf: moving) {
                place(id, in: frame)
            }
            placePanes(in: frame)
            CATransaction.commit()
            notifyVisibility(in: frame)
        }

        /// Places island `id` as `frame` draws it. `relayout` asks the island's view to lay out again,
        /// for a new layout rather than a scroll or a motion frame.
        func place(_ id: String, in frame: NIMotionFrame, relayout: Bool = false) {
            guard
                let host = hosts[id],
                !host.view.isHidden,
                let component = components[id],
                let rect = component.rect,
                let screen = screenRect(of: component, in: frame)
            else {
                return
            }
            let view = host.view
            view.alpha = component.opacity * CGFloat(frame.opacity(component.motionPath))
            motions.applyFade(component.motionPath, opacity: component.opacity, to: view.layer, in: frame)
            let parent = plane(for: component)
            let placed = parent.convert(screen.cgRect, from: self)
            view.frame = placed
            let zoom = parent === underlayPlane ? 1 : (webView?.scrollView.zoomScale ?? 1)
            motions.applyMoves(component.motionPath, scale: zoom, to: view.layer, in: frame)
            host.applyClips(screenClips(id: id, in: frame).map { localRect($0, in: view) })
            host.draw(NIIslandBody(rect: rect, placed: placed.size, zoom: zoom, transform: component.transform))
            cut(host, for: component, in: frame)
            host.applyTints(localTints(of: component, in: host.content, frame: frame))
            if relayout {
                view.setNeedsLayout()
            }
        }

        /// Whether any of the `motions` moves the island or a shape it is cut, tinted or clipped by.
        private func carries(_ component: IslandComponent, id: String, onAnyOf motions: Set<String>) -> Bool {
            guard !motions.isEmpty else { return false }
            let regions = component.cutouts + component.tints + component.clips + innerScroll.scrollports(componentID: id)
            return ([component.motionPath] + regions.map(\.motionPath)).contains { !motions.isDisjoint(with: $0) }
        }

        /// Cuts the component's cutouts out of its host, as one Core Animation track while the motions
        /// moving them run there, keyed by those motions, the content's size and the cut rects.
        private func cut(_ host: NativeIslandsHost, for component: IslandComponent, in frame: NIMotionFrame) {
            let scale = window?.screen.scale ?? traitCollection.displayScale
            let content = host.content
            let regions = component.cutouts.filter { !frame.fadedOut($0.motionPath) }
            var moving = motions.cutoutMotion(of: regions, under: component.motionPath, in: frame)
            moving?.key += "|\(content.bounds)|" + regions.map { "\($0.rect.cgRect)" }.joined(separator: ",")
            host.cut(localCutouts(of: component, in: content, scale: scale, frame: frame), moving: moving) { time in
                localCutouts(of: component, in: content, scale: scale, frame: motions.frame(atPageTime: time))
            }
        }

        /// The component's cutouts in `frame`, in `content`'s points, snapped out to whole pixels.
        private func localCutouts(of component: IslandComponent, in content: UIView, scale: CGFloat, frame: NIMotionFrame) -> [IslandRect] {
            component.cutouts.filter { !frame.fadedOut($0.motionPath) }.map {
                var screenRect = screenIslandRect($0, in: frame)
                let snapped = NIVisualCutoutGeometry.snappedOutward(screenRect.cgRect, scale: scale)
                screenRect.x = snapped.minX
                screenRect.y = snapped.minY
                screenRect.width = snapped.width
                screenRect.height = snapped.height
                return localRect(screenRect, in: content)
            }
        }

        func applyOrder() {
            var underlayIndex = 0
            var overlayIndex = 0
            for id in order {
                guard let host = hosts[id], let component = components[id] else { continue }
                if component.plane == .overlay {
                    overlayPlane.insertSubview(host.view, at: min(overlayIndex, overlayPlane.subviews.count))
                    overlayIndex += 1
                } else {
                    underlayPlane.insertSubview(host.view, at: min(underlayIndex, underlayPlane.subviews.count))
                    underlayIndex += 1
                }
            }
            orderPanes()
        }

        private func localTints(
            of component: IslandComponent,
            in view: UIView,
            frame: NIMotionFrame
        )
            -> [(rect: IslandRect, color: CGColor)] {
            component.tints.compactMap { region in
                guard let color = region.color else { return nil }
                let rect = localRect(screenIslandRect(region, in: frame), in: view)
                let alpha = color.alpha * frame.opacity(region.motionPath)
                return (rect, UIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha).cgColor)
            }
        }

        func notifyVisibility(in frame: NIMotionFrame) {
            for (id, host) in hosts {
                let placed = host.view.convert(host.view.bounds, to: self)
                let visible = !host.view.isHidden &&
                    Self.isNearViewport(placed, scrollports: screenClips(id: id, in: frame).map(\.cgRect), bounds: bounds)
                guard visible != host.visible else { continue }
                host.visible = visible
                onIslandVisibility?(id, visible)
            }
        }

        /// Whether `frame`, clipped by its scrollports, is within half a screen of `bounds`, so an
        /// island is told it is visible a little before it scrolls in.
        static func isNearViewport(_ frame: CGRect, scrollports: [CGRect], bounds: CGRect) -> Bool {
            let margin = bounds.height * 0.5
            let clipped = scrollports.reduce(frame) { $0.intersection($1.insetBy(dx: -margin, dy: -margin)) }
            return !clipped.isNull && clipped.intersects(bounds.insetBy(dx: -margin, dy: -margin))
        }

        /// Where `frame` draws `region`, in the container's points: moved as its sticky box sticks,
        /// then by its motions, its scrollers, the zoom and the document's scroll.
        func screenIslandRect(_ region: IslandRegion, in frame: NIMotionFrame) -> IslandRect {
            var rect = region.rect
            if let sticky = region.sticky {
                let shift = sticky.offset(in: stickyView(sticky))
                rect.x += shift.dx
                rect.y += shift.dy
            }
            return NIContainerGeometry.screenRect(
                frame.moved(rect, path: region.motionPath, origins: region.motionOrigins),
                coordinateSpace: region.coordinateSpace,
                nestedOffset: innerScroll.offset(path: region.scrollPath),
                zoom: webView?.scrollView.zoomScale ?? 1,
                rootOffset: webView?.scrollView.contentOffset ?? .zero
            )
        }

        private func stickyView(_ sticky: NISticky) -> CGRect {
            if let scroller = sticky.scroller {
                return innerScroll.visibleContent(containerID: scroller) ?? .zero
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

        /// The box `frame` draws the component over, in the container's points; nil when it has no rect.
        func screenRect(of component: IslandComponent, in frame: NIMotionFrame) -> IslandRect? {
            component.rect.map {
                screenIslandRect(
                    IslandRegion(
                        rect: $0,
                        scrollPath: component.scrollPath,
                        coordinateSpace: component.coordinateSpace,
                        sticky: component.sticky,
                        motionPath: component.motionPath,
                        motionOrigins: component.motionOrigins
                    ),
                    in: frame
                )
            }
        }

        /// The component's body as `frame` draws it, from `origin` in the container's points.
        func screenBody(of component: IslandComponent, in frame: NIMotionFrame) -> (origin: CGPoint, shape: NIIslandBody)? {
            guard let rect = component.rect, let screen = screenRect(of: component, in: frame) else { return nil }
            let zoom = webView?.scrollView.zoomScale ?? 1
            return (
                CGPoint(x: screen.x, y: screen.y),
                NIIslandBody(rect: rect, placed: screen.cgRect.size, zoom: zoom, transform: component.transform)
            )
        }

        /// `screen`, a rect in the container's points, in `view`'s, with its radii scaled to match.
        private func localRect(_ screen: IslandRect, in view: UIView) -> IslandRect {
            let local = view.convert(screen.cgRect, from: self)
            let scale = screen.width > 0 ? local.width / screen.width : 1
            return IslandRect(
                x: local.minX,
                y: local.minY,
                width: local.width,
                height: local.height,
                cornerRadii: screen.cornerRadii.scaled(by: abs(scale))
            )
        }

        /// Every shape island `id` shows only inside, its scrollports and its clips, as `frame` draws them.
        func screenClips(id: String, in frame: NIMotionFrame) -> [IslandRect] {
            (innerScroll.scrollports(componentID: id) + (components[id]?.clips ?? [])).map { screenIslandRect($0, in: frame) }
        }

        private func followsRoot(_ region: IslandRegion) -> Bool {
            region.coordinateSpace == .viewport || region.sticky.map { $0.scroller == nil } ?? false
        }

        func updateDocumentTransform() {
            guard let scrollView = webView?.scrollView else { return }
            underlayPlane.transform = CGAffineTransform(
                scaleX: scrollView.zoomScale,
                y: scrollView.zoomScale
            )
        }
    }
#endif
