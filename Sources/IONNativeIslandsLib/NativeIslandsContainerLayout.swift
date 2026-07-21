#if canImport(UIKit)
    import UIKit

    extension NativeIslandsContainer {
        func updateAllInnerScrollGeometry() {
            for id in innerScroll.componentIDs {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
            notifyVisibility()
        }

        func updateInnerScrollGeometry(containerID: String) {
            for id in innerScroll.componentIDs(affectedBy: containerID) {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
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
            screenIslandRect(
                region.rect,
                coordinateSpace: region.coordinateSpace,
                scrollPath: region.scrollPath
            )
        }

        func screenIslandRect(
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

        func screenScrollports(id: String) -> [IslandRect] {
            innerScroll.scrollports(componentID: id).map {
                screenIslandRect(
                    $0,
                    coordinateSpace: .document,
                    scrollPath: []
                )
            }
        }

        func updateRootTrackedGeometry() {
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

        func updateDocumentTransform() {
            guard let scrollView = webView?.scrollView else { return }
            documentLayer.transform = CGAffineTransform(
                scaleX: scrollView.zoomScale,
                y: scrollView.zoomScale
            )
        }
    }
#endif
