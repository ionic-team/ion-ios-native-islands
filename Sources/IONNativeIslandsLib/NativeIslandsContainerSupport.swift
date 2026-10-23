#if canImport(UIKit)
    import UIKit

    struct IslandRect: Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        var cornerRadii: NICornerRadii

        func containsBox(_ size: CGSize) -> Bool {
            let right = x + width
            let bottom = y + height
            guard x <= 0, y <= 0, right >= size.width, bottom >= size.height else { return false }
            let radii = cornerRadii
            return (radii.topLeft <= 0 || x + radii.topLeft <= 0 || y + radii.topLeft <= 0) &&
                (radii.topRight <= 0 || right - radii.topRight >= size.width || y + radii.topRight <= 0) &&
                (radii.bottomRight <= 0 || right - radii.bottomRight >= size.width || bottom - radii.bottomRight >= size.height) &&
                (radii.bottomLeft <= 0 || x + radii.bottomLeft <= 0 || bottom - radii.bottomLeft >= size.height)
        }

        var cgRect: CGRect {
            CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        }
    }

    extension NICornerRadii {
        var maskedCorners: CACornerMask {
            var corners: CACornerMask = []
            if topLeft > 0 {
                corners.insert(.layerMinXMinYCorner)
            }
            if topRight > 0 {
                corners.insert(.layerMaxXMinYCorner)
            }
            if bottomRight > 0 {
                corners.insert(.layerMaxXMaxYCorner)
            }
            if bottomLeft > 0 {
                corners.insert(.layerMinXMaxYCorner)
            }
            return corners
        }
    }

    struct IslandComponent {
        var id: String
        var rect: IslandRect?
        var scrollPath: [String]
        var plane: NIHostPlane
        var coordinateSpace: NICoordinateSpace
        var interactive: Bool
        var active: Bool
        var opacity: CGFloat = 1
        var motionPath: [String] = []
    }

    struct IslandRegion {
        var rect: IslandRect
        var scrollPath: [String]
        var coordinateSpace: NICoordinateSpace
        var sticky: NISticky?
        var motionPath: [String] = []
        var color: NITintColor?
    }

    struct IslandScrollContainer {
        var id: String
        var rect: IslandRect
        var coordinateSpace: NICoordinateSpace = .document
        var scrollPath: [String]
        var contentWidth: CGFloat
        var contentHeight: CGFloat
        var offsetX: CGFloat
        var offsetY: CGFloat
        var motionPath: [String] = []
    }

    enum NativeIslandsCoordinateMapping {
        static func screenRect(
            _ rect: IslandRect,
            coordinateSpace: NICoordinateSpace,
            nestedOffset: CGPoint,
            zoom: CGFloat,
            rootOffset: CGPoint
        )
            -> IslandRect {
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
                cornerRadii: rect.cornerRadii.scaled(by: zoom)
            )
        }

        static func localRect(
            _ screen: IslandRect,
            container: UIView,
            view: UIView
        )
            -> IslandRect {
            let local = view.convert(screen.cgRect, from: container)
            let scale = screen.width > 0
                ? local.width / screen.width
                : 1
            return IslandRect(
                x: local.minX,
                y: local.minY,
                width: local.width,
                height: local.height,
                cornerRadii: screen.cornerRadii.scaled(by: abs(scale))
            )
        }
    }

    struct NativeIslandsHitGeometry {
        let rect: IslandRect
        let scrollports: [IslandRect]
        let exclusions: [IslandRect]
        let interactive: Bool
    }

    enum NativeIslandsHitTesting {
        static func decide(
            point: CGPoint,
            order: [String],
            geometry: (String) -> NativeIslandsHitGeometry?
        )
            -> NIHitDecision {
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
        )
            -> Bool {
            rect.cornerRadii.contains(point, in: rect.cgRect)
        }
    }

    final class NativeIslandsHostClipping {
        private struct CutoutMaskInput: Equatable {
            var bounds: CGRect
            var cutouts: [IslandRect]
        }

        private struct CutoutMaskState {
            var input: CutoutMaskInput
            var layer: CAShapeLayer
        }

        private struct ScrollportMaskInput: Equatable {
            var bounds: CGRect
            var scrollport: IslandRect
        }

        private var scrollportHosts: [String: [UIView]] = [:]
        private var scrollportMasks: [String: [CAShapeLayer]] = [:]
        private var cutoutMasks: [String: CutoutMaskState] = [:]
        private var scrollportMaskInputs: [String: [ScrollportMaskInput]] = [:]
        private var tintLayers: [String: CALayer] = [:]

        func remove(id: String) {
            scrollportHosts[id] = nil
            scrollportMasks[id] = nil
            cutoutMasks[id] = nil
            scrollportMaskInputs[id] = nil
            tintLayers.removeValue(forKey: id)?.removeFromSuperlayer()
        }

        func reset() {
            scrollportHosts.removeAll()
            scrollportMasks.removeAll()
            cutoutMasks.removeAll()
            scrollportMaskInputs.removeAll()
            tintLayers.values.forEach { $0.removeFromSuperlayer() }
            tintLayers.removeAll()
        }

        func applyTints(
            to host: UIView,
            islandID: String,
            tints: [(rect: IslandRect, color: CGColor)]
        ) {
            guard !tints.isEmpty || tintLayers[islandID] != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            guard !tints.isEmpty else {
                tintLayers.removeValue(forKey: islandID)?.removeFromSuperlayer()
                return
            }
            let container = tintLayers[islandID] ?? {
                let layer = CALayer()
                layer.masksToBounds = true
                layer.compositingFilter = "sourceAtop"
                return layer
            }()
            tintLayers[islandID] = container
            if container.superlayer !== host.layer || host.layer.sublayers?.last !== container {
                host.layer.addSublayer(container)
            }
            container.frame = host.bounds
            var shapes = container.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
            while shapes.count < tints.count {
                let shape = CAShapeLayer()
                container.addSublayer(shape)
                shapes.append(shape)
            }
            for (index, shape) in shapes.enumerated() {
                guard tints.indices.contains(index) else {
                    shape.removeFromSuperlayer()
                    continue
                }
                shape.path = tints[index].rect.cornerRadii.path(in: tints[index].rect.cgRect)
                shape.fillColor = tints[index].color
            }
        }

        func applyCutouts(
            to host: UIView,
            islandID: String,
            cutouts: [IslandRect]
        ) {
            guard !cutouts.isEmpty else {
                host.layer.mask = nil
                cutoutMasks[islandID] = nil
                return
            }

            let mask = host.layer.mask as? CAShapeLayer ?? CAShapeLayer()
            let input = CutoutMaskInput(bounds: host.bounds, cutouts: cutouts)
            if let cached = cutoutMasks[islandID],
               cached.input == input,
               cached.layer === mask,
               mask.path != nil {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.frame = host.bounds
            mask.masksToBounds = true
            mask.path = NIVisualCutoutGeometry.visiblePath(
                bounds: host.bounds,
                cutouts: cutouts.map {
                    (
                        rect: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height),
                        radii: $0.cornerRadii
                    )
                }
            )
            mask.fillRule = .evenOdd
            host.layer.mask = mask
            cutoutMasks[islandID] = CutoutMaskState(input: input, layer: mask)
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
                let previous = wrappers
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
                previous.forEach { $0.removeFromSuperview() }
                scrollportHosts[islandID] = wrappers
                scrollportMasks[islandID] = scrollports.map { _ in
                    CAShapeLayer()
                }
                scrollportMaskInputs[islandID] = nil
            }
            contentHost.frame = host.bounds
            contentHost.subviews.forEach { $0.frame = contentHost.bounds }
            guard !scrollports.isEmpty else {
                scrollportHosts[islandID] = []
                scrollportMasks[islandID] = []
                scrollportMaskInputs[islandID] = []
                return
            }

            let masks = scrollportMasks[islandID] ?? []
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for wrapper in wrappers {
                wrapper.frame = host.bounds
            }
            let inputs = scrollports.indices.map { index in
                ScrollportMaskInput(bounds: wrappers[index].bounds, scrollport: scrollports[index])
            }
            let previousInputs = scrollportMaskInputs[islandID] ?? []
            for (index, scrollport) in scrollports.enumerated() {
                guard wrappers.indices.contains(index),
                      masks.indices.contains(index)
                else {
                    continue
                }
                let wrapper = wrappers[index]
                let mask = masks[index]
                if scrollport.containsBox(wrapper.bounds.size) {
                    wrapper.layer.mask = nil
                    continue
                }
                mask.frame = wrapper.bounds
                if previousInputs.count != inputs.count || previousInputs[index] != inputs[index] || mask.path == nil {
                    mask.path = scrollport.cornerRadii.path(in: CGRect(
                        x: scrollport.x,
                        y: scrollport.y,
                        width: scrollport.width,
                        height: scrollport.height
                    ))
                }
                wrapper.layer.mask = mask
            }
            scrollportMaskInputs[islandID] = inputs
            CATransaction.commit()
        }
    }

    final class NativeIslandsVisibilityTracker {
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
            let margin = container.bounds.height * 0.5
            let expanded = container.bounds.insetBy(dx: -margin, dy: -margin)
            for (id, host) in hosts {
                var frame = host.convert(host.bounds, to: container)
                for scrollportFrame in screenScrollports(id) {
                    frame = frame.intersection(scrollportFrame.insetBy(dx: -margin, dy: -margin))
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
