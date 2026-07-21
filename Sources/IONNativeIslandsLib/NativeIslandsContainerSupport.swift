#if canImport(UIKit)
import UIKit

internal struct IslandRect {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    var cgRect: CGRect {
        CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }
}

internal struct IslandComponent {
    var id: String
    var rect: IslandRect?
    var scrollPath: [String]
    var plane: NIHostPlane
    var coordinateSpace: NICoordinateSpace
    var interactive: Bool
    var active: Bool
}

internal struct IslandRegion {
    var rect: IslandRect
    var scrollPath: [String]
    var coordinateSpace: NICoordinateSpace
}

internal struct IslandScrollContainer {
    var id: String
    var rect: IslandRect
    var scrollPath: [String]
    var contentWidth: CGFloat
    var contentHeight: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
}

internal enum NativeIslandsCoordinateMapping {
    static func screenRect(
        _ rect: IslandRect,
        coordinateSpace: NICoordinateSpace,
        nestedOffset: CGPoint,
        zoom: CGFloat,
        rootOffset: CGPoint
    ) -> IslandRect {
        let screen = NIContainerGeometry.screenRect(
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
            coordinateSpace: coordinateSpace,
            nestedOffset: nestedOffset,
            zoom: zoom,
            rootOffset: rootOffset
        )
        return IslandRect(
            x: screen.minX,
            y: screen.minY,
            width: screen.width,
            height: screen.height,
            cornerRadius: rect.cornerRadius * zoom
        )
    }

    static func localRect(
        _ screen: IslandRect,
        container: UIView,
        view: UIView
    ) -> IslandRect {
        let local = view.convert(screen.cgRect, from: container)
        let scale = screen.width > 0
            ? local.width / screen.width
            : 1
        return IslandRect(
            x: local.minX,
            y: local.minY,
            width: local.width,
            height: local.height,
            cornerRadius: screen.cornerRadius * abs(scale)
        )
    }
}

internal struct NativeIslandsHitGeometry {
    let rect: IslandRect
    let scrollports: [IslandRect]
    let exclusions: [IslandRect]
    let interactive: Bool
}

internal enum NativeIslandsHitTesting {
    static func decide(
        point: CGPoint,
        order: [String],
        geometry: (String) -> NativeIslandsHitGeometry?
    ) -> NIHitDecision {
        for id in order.reversed() {
            guard
                let value = geometry(id),
                contains(point, in: value.rect),
                value.scrollports.allSatisfy({
                    contains(point, in: $0)
                })
            else {
                continue
            }
            return NIHitRouting.decide([
                NIHitCandidate(
                    id: id,
                    interactive: value.interactive,
                    excluded: value.exclusions.contains {
                        contains(point, in: $0)
                    }
                ),
            ])
        }
        return NIHitRouting.decide([])
    }

    private static func contains(
        _ point: CGPoint,
        in rect: IslandRect
    ) -> Bool {
        NIContainerGeometry.contains(
            point: point,
            in: rect.cgRect,
            cornerRadius: rect.cornerRadius
        )
    }
}

internal final class NativeIslandsHostClipping {
    private var scrollportHosts: [String: [UIView]] = [:]
    private var scrollportMasks: [String: [CAShapeLayer]] = [:]

    func remove(id: String) {
        scrollportHosts[id] = nil
        scrollportMasks[id] = nil
    }

    func reset() {
        scrollportHosts.removeAll()
        scrollportMasks.removeAll()
    }

    func applyCutouts(
        to host: UIView,
        cutouts: [IslandRect]
    ) {
        guard !cutouts.isEmpty else {
            host.layer.mask = nil
            return
        }

        let path = UIBezierPath(rect: host.bounds)
        let simpleRects = cutouts
            .filter { $0.cornerRadius <= 0 }
            .map {
                CGRect(
                    x: $0.x,
                    y: $0.y,
                    width: $0.width,
                    height: $0.height
                ).intersection(host.bounds)
            }
        for rect in NIVisualCutoutGeometry.union(simpleRects) {
            path.append(UIBezierPath(rect: rect))
        }
        for cutout in cutouts where cutout.cornerRadius > 0 {
            let rect = CGRect(
                x: cutout.x,
                y: cutout.y,
                width: cutout.width,
                height: cutout.height
            ).intersection(host.bounds)
            guard !rect.isNull, !rect.isEmpty else { continue }
            let radius = NIContainerGeometry.clampedCornerRadius(
                width: rect.width,
                height: rect.height,
                cornerRadius: cutout.cornerRadius
            )
            path.append(
                UIBezierPath(
                    roundedRect: rect,
                    cornerRadius: radius
                )
            )
        }

        let mask = CAShapeLayer()
        mask.frame = host.bounds
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.layer.mask = mask
        CATransaction.commit()
    }

    func applyScrollports(
        to host: UIView,
        contentHost: UIView,
        islandID: String,
        scrollports: [IslandRect]
    ) {
        var wrappers = scrollportHosts[islandID] ?? []
        if wrappers.count != scrollports.count {
            contentHost.removeFromSuperview()
            wrappers.forEach { $0.removeFromSuperview() }
            wrappers = scrollports.map { _ in
                let wrapper = UIView(frame: host.bounds)
                wrapper.autoresizingMask = [
                    .flexibleWidth,
                    .flexibleHeight,
                ]
                return wrapper
            }
            var parent = host
            for wrapper in wrappers {
                parent.addSubview(wrapper)
                parent = wrapper
            }
            parent.addSubview(contentHost)
            scrollportHosts[islandID] = wrappers
            scrollportMasks[islandID] = scrollports.map { _ in
                CAShapeLayer()
            }
        }
        contentHost.frame = host.bounds
        guard !scrollports.isEmpty else {
            scrollportHosts[islandID] = []
            scrollportMasks[islandID] = []
            return
        }

        let masks = scrollportMasks[islandID] ?? []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, scrollport) in scrollports.enumerated() {
            guard wrappers.indices.contains(index),
                  masks.indices.contains(index) else {
                continue
            }
            let wrapper = wrappers[index]
            let mask = masks[index]
            wrapper.frame = host.bounds
            mask.frame = wrapper.bounds
            mask.path = UIBezierPath(
                roundedRect: CGRect(
                    x: scrollport.x,
                    y: scrollport.y,
                    width: scrollport.width,
                    height: scrollport.height
                ),
                cornerRadius: NIContainerGeometry.clampedCornerRadius(
                    width: scrollport.width,
                    height: scrollport.height,
                    cornerRadius: scrollport.cornerRadius
                )
            ).cgPath
            wrapper.layer.mask = mask
        }
        CATransaction.commit()
    }
}

internal final class NativeIslandsVisibilityTracker {
    private var visibleIDs: Set<String> = []

    var onChange: ((String, Bool) -> Void)?

    func remove(id: String) {
        visibleIDs.remove(id)
    }

    func reset() {
        visibleIDs.removeAll()
    }

    func update(
        container: UIView,
        hosts: [String: UIView],
        screenScrollports: (String) -> [CGRect]
    ) {
        let expanded = container.bounds.insetBy(
            dx: -container.bounds.height * 0.5,
            dy: -container.bounds.height * 0.5
        )
        for (id, host) in hosts {
            var frame = host.convert(host.bounds, to: container)
            for scrollportFrame in screenScrollports(id) {
                frame = frame.intersection(scrollportFrame)
            }
            let visible =
                !host.isHidden &&
                !frame.isNull &&
                frame.intersects(expanded)
            guard visible != visibleIDs.contains(id) else { continue }
            if visible {
                visibleIDs.insert(id)
            } else {
                visibleIDs.remove(id)
            }
            onChange?(id, visible)
        }
    }
}
#endif
