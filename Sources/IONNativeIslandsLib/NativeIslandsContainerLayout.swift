#if canImport(UIKit)
    import UIKit

    extension NativeIslandsContainer {
        func updateAllInnerScrollGeometry() {
            for id in innerScroll.componentIDs {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
            updatePaneGeometry()
            notifyVisibility()
        }

        func updateInnerScrollGeometry(containerID: String) {
            for id in innerScroll.componentIDs(affectedBy: containerID) {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
            updatePaneGeometry()
            notifyVisibility()
        }

        func updateHostGeometry(
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
                scrollPath: component.scrollPath,
                motionPath: component.motionPath
            )
            host.alpha = alpha(of: component)
            let parent = component.plane == .overlay
                ? overlayLayer
                : documentLayer
            host.frame = parent.convert(screen.cgRect, from: self)
            let motionScale = parent === documentLayer ? 1 : (webView?.scrollView.zoomScale ?? 1)
            applyMotion(trackedMoves(component.motionPath), scale: motionScale, to: host.layer)
            contentHost.frame = host.bounds
            let localScale = screen.width > 0
                ? host.bounds.width / screen.width
                : 1
            let radii = screen.cornerRadii
                .scaled(by: abs(localScale))
                .fitted(to: host.bounds.size)
            let layerRadius = radii.sharedRadius(in: host.bounds.size)
            host.layer.cornerRadius = layerRadius ?? 0
            host.layer.maskedCorners = radii.maskedCorners
            host.layer.masksToBounds = true

            let shape = layerRadius == nil
                ? [IslandRect(
                    x: 0,
                    y: 0,
                    width: host.bounds.width,
                    height: host.bounds.height,
                    cornerRadii: radii
                )]
                : []
            let localScrollports = screenScrollports(id: id).map {
                NativeIslandsCoordinateMapping.localRect(
                    $0,
                    container: self,
                    view: host
                )
            } + shape
            hostClipping.applyScrollports(
                to: host,
                contentHost: contentHost,
                islandID: id,
                scrollports: localScrollports
            )
            let scale = window?.screen.scale ?? traitCollection.displayScale
            let localCutouts = (cutouts[id] ?? []).filter { !fadedOut($0.motionPath) }.map {
                var screenRect = screenIslandRect($0)
                let snapped = NIVisualCutoutGeometry.snappedOutward(screenRect.cgRect, scale: scale)
                screenRect.x = snapped.minX
                screenRect.y = snapped.minY
                screenRect.width = snapped.width
                screenRect.height = snapped.height
                return NativeIslandsCoordinateMapping.localRect(
                    screenRect,
                    container: self,
                    view: contentHost
                )
            }
            hostClipping.applyCutouts(
                to: contentHost,
                islandID: id,
                cutouts: localCutouts
            )
            hostClipping.applyTints(to: contentHost, islandID: id, tints: localTints(id: id, in: contentHost))
            if updateStaticGeometry {
                host.setNeedsLayout()
            }
        }

        func applyOrder() {
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
            orderPanes()
        }

        private func localTints(id: String, in view: UIView) -> [(rect: IslandRect, color: CGColor)] {
            (tints[id] ?? []).compactMap { region in
                guard let color = region.color else { return nil }
                let rect = NativeIslandsCoordinateMapping.localRect(screenIslandRect(region), container: self, view: view)
                let alpha = color.alpha * motionOpacity(region.motionPath)
                return (rect, UIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha).cgColor)
            }
        }

        func notifyVisibility() {
            visibility.update(
                container: self,
                hosts: hosts,
                screenScrollports: { [weak self] id in
                    self?.screenScrollports(id: id).map(\.cgRect) ?? []
                }
            )
        }

        func screenIslandRect(_ region: IslandRegion) -> IslandRect {
            var rect = region.rect
            if let sticky = region.sticky {
                let shift = sticky.offset(in: stickyView(sticky))
                rect.x += shift.dx
                rect.y += shift.dy
            }
            return screenIslandRect(
                rect,
                coordinateSpace: region.coordinateSpace,
                scrollPath: region.scrollPath,
                motionPath: region.motionPath
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

        func screenIslandRect(
            _ rect: IslandRect,
            coordinateSpace: NICoordinateSpace,
            scrollPath: [String],
            motionPath: [String] = []
        )
            -> IslandRect {
            NativeIslandsCoordinateMapping.screenRect(
                moved(rect, motionPath: motionPath),
                coordinateSpace: coordinateSpace,
                nestedOffset: innerScroll.offset(path: scrollPath),
                zoom: webView?.scrollView.zoomScale ?? 1,
                rootOffset: webView?.scrollView.contentOffset ?? .zero
            )
        }

        func screenScrollports(id: String) -> [IslandRect] {
            innerScroll.scrollports(componentID: id).map(screenIslandRect)
        }

        private func followsRoot(_ region: IslandRegion) -> Bool {
            region.coordinateSpace == .viewport || region.sticky.map { $0.scroller == nil } ?? false
        }

        func updateRootTrackedGeometry() {
            for (id, component) in components
                where component.plane == .overlay ||
                component.coordinateSpace == .viewport ||
                (cutouts[id] ?? []).contains(where: followsRoot) || (tints[id] ?? []).contains(where: followsRoot) {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
            updatePaneGeometry()
            notifyVisibility()
        }

        func updateDocumentTransform() {
            guard let scrollView = webView?.scrollView else { return }
            documentLayer.transform = CGAffineTransform(
                scaleX: scrollView.zoomScale,
                y: scrollView.zoomScale
            )
        }
    }
#endif
