#if canImport(UIKit)
    import CoreFoundation
    import UIKit

    enum NativeIslandsLayoutParsing {
        static func components(
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
                        interactive: boolean(value["interactive"]) ?? false,
                        active: boolean(value["active"]) ?? false,
                        opacity: NISafeGeometry.strictNumber(value["opacity"]).map { CGFloat($0) } ?? 1,
                        motionPath: NIMotionPayload.path(value["motionPath"])
                    ),
                    type
                )
            }
        }

        static func scrollContainers(
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
                    motionPath: NIMotionPayload.path(value["motionPath"])
                )
            }
        }

        static func panes(from value: Any?) -> [String: IslandPane]? {
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
                    color: UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1),
                    under: entry["under"] as? String
                )
            }
            return panes
        }

        static func regions(
            from values: [String: Any]
        )
            -> [String: [IslandRegion]] {
            values.reduce(into: [:]) { output, entry in
                guard let regions = entry.value as? [[String: Any]] else {
                    return
                }
                output[entry.key] = regions.compactMap { value in
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
                        color: NITintColor(value["color"])
                    )
                }
            }
        }

        private static func rect(
            from value: [String: Any]?
        )
            -> IslandRect? {
            guard let value, let rect = NISafeGeometry.parseRect(value) else {
                return nil
            }
            return IslandRect(
                x: CGFloat(rect.x),
                y: CGFloat(rect.y),
                width: CGFloat(rect.width),
                height: CGFloat(rect.height),
                cornerRadii: rect.cornerRadii
            )
        }

        private static func boolean(_ value: Any?) -> Bool? {
            guard
                let number = value as? NSNumber,
                CFGetTypeID(number) == CFBooleanGetTypeID()
            else {
                return nil
            }
            return number.boolValue
        }
    }
#endif
