#if canImport(UIKit)
    import UIKit

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
        var portal: String?
        var transitionTag: String?
        var motionOrigins: [CGPoint] = []
        /// How the island's own box maps onto `rect`; nil when it is drawn at `rect`.
        var transform: NIIslandTransform?
        /// The sticky box the island moves with; `rect` is where it sits unstuck.
        var sticky: NISticky?
        /// Shapes the island shows only inside, beyond its scrollports.
        var clips: [IslandRegion] = []
        var exclusions: [IslandRegion] = []
        var cutouts: [IslandRegion] = []
        var tints: [IslandRegion] = []
    }

    struct IslandRegion {
        var rect: IslandRect
        var scrollPath: [String]
        var coordinateSpace: NICoordinateSpace
        var sticky: NISticky?
        var motionPath: [String] = []
        var color: NITintColor?
        var motionOrigins: [CGPoint] = []
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
        var motionOrigins: [CGPoint] = []
        /// The linear part of the transforms at and above the scroller, applied to its scroll offset.
        var linear: CGAffineTransform = .identity
        /// The sticky box the scroller sits in; `rect` is where it sits unstuck.
        var sticky: NISticky?

        var scrollport: IslandRegion {
            IslandRegion(
                rect: rect,
                scrollPath: scrollPath,
                coordinateSpace: coordinateSpace,
                sticky: sticky,
                motionPath: motionPath,
                motionOrigins: motionOrigins
            )
        }
    }

    /// A layout as native applies it.
    struct NativeIslandsLayout {
        let components: [(IslandComponent, String)]
        let scrollContainers: [IslandScrollContainer]
        let order: [String]
        let exclusions: [String: [IslandRegion]]
        let cutouts: [String: [IslandRegion]]
        let tints: [String: [IslandRegion]]
        let motions: [String: NIMotion]
        let panes: [String: IslandPane]
        let canvasColor: String?
        /// The page time it was sent at.
        let sentAt: Double?
        /// The paint fence it applies with.
        let fence: Int?
    }

    /// Reads an `applyLayout` payload into the container's types.
    enum NativeIslandsLayoutParsing {
        /// The layout in `payload`, an object that passed the bridge's shape checks, or why it is refused.
        static func layout(_ payload: [String: Any]) -> Result<NativeIslandsLayout, NIBridgeError> {
            guard
                let components = payload["components"] as? [[String: Any]],
                let scrollContainers = payload["scrollContainers"] as? [[String: Any]],
                let order = payload["order"] as? [String],
                let exclusions = payload["exclusions"] as? [String: Any],
                let cutouts = payload["cutouts"] as? [String: Any],
                let tints = payload["tints"] == nil ? [:] : payload["tints"] as? [String: Any]
            else {
                return .failure(NIBridgeError(
                    "invalid_request",
                    "layout envelope must contain component, scroll container, order, exclusion, and cutout fields"
                ))
            }
            if let reason = error(
                in: payload,
                components: components,
                scrollContainers: scrollContainers,
                order: order,
                exclusions: exclusions,
                cutouts: cutouts,
                tints: tints
            ) {
                return .failure(NIBridgeError("invalid_request", reason))
            }
            return .success(NativeIslandsLayout(
                components: self.components(from: components),
                scrollContainers: self.scrollContainers(from: scrollContainers),
                order: order,
                exclusions: regions(from: exclusions),
                cutouts: regions(from: cutouts),
                tints: regions(from: tints),
                motions: NIMotionPayload.parse(payload["motions"]),
                panes: panes(from: payload["panes"]) ?? [:],
                canvasColor: payload["canvasColor"] as? String,
                sentAt: (payload["sentAt"] as? NSNumber)?.doubleValue,
                fence: (payload["fence"] as? NSNumber)?.intValue
            ))
        }

        private static func error(
            in payload: [String: Any],
            components: [[String: Any]],
            scrollContainers: [[String: Any]],
            order: [String],
            exclusions: [String: Any],
            cutouts: [String: Any],
            tints: [String: Any]
        )
            -> String? {
            let canvasColor = payload["canvasColor"]
            let panes = payload["panes"]
            let motions = payload["motions"]
            let sentAt = payload["sentAt"]
            let fence = payload["fence"]
            if canvasColor != nil, NICanvasColor(canvasColor) == nil {
                return "applyLayout canvasColor must be an opaque hex color"
            }
            if self.panes(from: panes) == nil {
                return "applyLayout panes must map scroll container ids to an opaque hex color and an optional island id"
            }
            if sentAt != nil, (NISafeGeometry.strictNumber(sentAt) ?? -1) < 0 {
                return "applyLayout sentAt must be a non-negative number"
            }
            if motions != nil, sentAt == nil {
                return "applyLayout motions require sentAt"
            }
            if fence != nil, !(0..<NativeIslandsPaintFence.range).contains(NISafeGeometry.strictInteger(fence) ?? -1) {
                return "applyLayout fence must be an integer from 0 to \(NativeIslandsPaintFence.range - 1)"
            }
            return NILayoutValidation.error(
                components: components,
                scrollContainers: scrollContainers,
                order: order,
                exclusions: exclusions,
                cutouts: cutouts,
                tints: tints,
                motions: motions
            )
        }

        private static func components(
            from values: [[String: Any]]
        )
            -> [(IslandComponent, String)] {
            values.compactMap { value in
                guard
                    let id = value["id"] as? String,
                    let type = value["type"] as? String,
                    let rawPlane = value["plane"] as? String,
                    let plane = NIHostPlane(rawValue: rawPlane),
                    let rawCoordinateSpace =
                    value["coordinateSpace"] as? String,
                    let coordinateSpace =
                    NICoordinateSpace(rawValue: rawCoordinateSpace)
                else {
                    return nil
                }
                return (
                    IslandComponent(
                        id: id,
                        rect: rect(from: value["rect"] as? [String: Any]),
                        scrollPath: value["scrollPath"] as? [String] ?? [],
                        plane: plane,
                        coordinateSpace: coordinateSpace,
                        interactive: NISafeGeometry.strictBool(value["interactive"]) ?? false,
                        active: NISafeGeometry.strictBool(value["active"]) ?? false,
                        opacity: NISafeGeometry.strictNumber(value["opacity"]).map { CGFloat($0) } ?? 1,
                        motionPath: NIMotionPayload.path(value["motionPath"]),
                        portal: (value["portal"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                        transitionTag: (value["transitionTag"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                        motionOrigins: NIMotionPayload.origins(value["motionOrigins"]),
                        transform: NIIslandTransform(value["transform"]),
                        sticky: NISticky(value["sticky"]),
                        clips: (value["clips"] as? [[String: Any]] ?? []).compactMap(region(from:))
                    ),
                    type
                )
            }
        }

        private static func scrollContainers(
            from values: [[String: Any]]
        )
            -> [IslandScrollContainer] {
            values.compactMap { value in
                guard
                    let id = value["id"] as? String,
                    let rect = rect(
                        from: value["rect"] as? [String: Any]
                    ),
                    let contentWidth = NISafeGeometry.strictNumber(
                        value["contentWidth"]
                    ),
                    let contentHeight = NISafeGeometry.strictNumber(
                        value["contentHeight"]
                    ),
                    let offsetX = NISafeGeometry.strictNumber(
                        value["offsetX"]
                    ),
                    let offsetY = NISafeGeometry.strictNumber(
                        value["offsetY"]
                    )
                else {
                    return nil
                }
                return IslandScrollContainer(
                    id: id,
                    rect: rect,
                    coordinateSpace: (value["coordinateSpace"] as? String)
                        .flatMap(NICoordinateSpace.init(rawValue:)) ?? .document,
                    scrollPath: value["scrollPath"] as? [String] ?? [],
                    contentWidth: CGFloat(contentWidth),
                    contentHeight: CGFloat(contentHeight),
                    offsetX: CGFloat(offsetX),
                    offsetY: CGFloat(offsetY),
                    motionPath: NIMotionPayload.path(value["motionPath"]),
                    motionOrigins: NIMotionPayload.origins(value["motionOrigins"]),
                    linear: NISafeGeometry.numbers(value["linear"], count: 4).map {
                        CGAffineTransform(a: $0[0], b: $0[1], c: $0[2], d: $0[3], tx: 0, ty: 0)
                    } ?? .identity,
                    sticky: NISticky(value["sticky"])
                )
            }
        }

        private static func panes(from value: Any?) -> [String: IslandPane]? {
            guard let value else { return [:] }
            guard let entries = value as? [String: Any] else { return nil }
            var panes: [String: IslandPane] = [:]
            for (id, raw) in entries {
                guard
                    let entry = raw as? [String: Any],
                    let color = NICanvasColor(entry["color"]),
                    entry["under"] == nil || entry["under"] is String
                else {
                    return nil
                }
                panes[id] = IslandPane(
                    color: color.uiColor,
                    under: entry["under"] as? String
                )
            }
            return panes
        }

        private static func regions(
            from values: [String: Any]
        )
            -> [String: [IslandRegion]] {
            values.reduce(into: [:]) { output, entry in
                guard let regions = entry.value as? [[String: Any]] else {
                    return
                }
                output[entry.key] = regions.compactMap(region(from:))
            }
        }

        private static func region(from value: [String: Any]) -> IslandRegion? {
            guard
                let rect = rect(
                    from: value["rect"] as? [String: Any]
                ),
                let scrollPath = value["scrollPath"] as? [String],
                let rawCoordinateSpace =
                value["coordinateSpace"] as? String,
                let coordinateSpace =
                NICoordinateSpace(rawValue: rawCoordinateSpace)
            else {
                return nil
            }
            return IslandRegion(
                rect: rect,
                scrollPath: scrollPath,
                coordinateSpace: coordinateSpace,
                sticky: NISticky(value["sticky"]),
                motionPath: NIMotionPayload.path(value["motionPath"]),
                color: NITintColor(value["color"]),
                motionOrigins: NIMotionPayload.origins(value["motionOrigins"])
            )
        }

        private static func rect(
            from value: [String: Any]?
        )
            -> IslandRect? {
            value.flatMap { NISafeGeometry.parseRect($0) }
        }
    }
#endif
