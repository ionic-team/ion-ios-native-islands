import CoreFoundation
import Foundation

enum NILayoutValidation {
    private struct ComponentIDs {
        var all: Set<String>
        var active: Set<String>
        var error: String?
    }

    static func error(
        components: [[String: Any]],
        scrollContainers: [[String: Any]] = [],
        order: [String],
        exclusions: [String: Any],
        cutouts: [String: Any],
        tints: [String: Any] = [:],
        motions: Any? = nil
    )
        -> String? {
        if let error = motionError(
            motions,
            components: components,
            scrollContainers: scrollContainers,
            regions: [exclusions, cutouts, tints]
        ) {
            return error
        }
        var scrollContainerIDs: Set<String> = []
        var scrollContainerPaths: [String: [String]] = [:]
        if let error = scrollContainerError(
            scrollContainers,
            ids: &scrollContainerIDs,
            paths: &scrollContainerPaths
        ) {
            return error
        }
        let componentResult = componentIDs(
            components,
            scrollContainerPaths: scrollContainerPaths
        )
        if let error = componentResult.error {
            return error
        }
        let ids = componentResult.all
        let activeIDs = componentResult.active
        var ordered: Set<String> = []
        for id in order {
            guard ids.contains(id) else {
                return "paint order references unknown component '\(id)'"
            }
            guard ordered.insert(id).inserted else {
                return "duplicate paint-order component '\(id)'"
            }
        }
        guard ordered == activeIDs else {
            return "paint order must contain every active component and no inactive components"
        }
        return regionError(
            name: "exclusion",
            values: exclusions,
            ids: ids,
            scrollContainerPaths: scrollContainerPaths
        ) ?? regionError(
            name: "cutout",
            values: cutouts,
            ids: ids,
            scrollContainerPaths: scrollContainerPaths
        ) ?? regionError(
            name: "tint",
            values: tints,
            ids: ids,
            scrollContainerPaths: scrollContainerPaths
        )
    }

    private static func motionError(
        _ motions: Any?,
        components: [[String: Any]],
        scrollContainers: [[String: Any]],
        regions: [[String: Any]]
    )
        -> String? {
        let (ids, error) = NIMotionPayload.validate(motions)
        if let error { return error }
        for (index, component) in components.enumerated() {
            if let error = NIMotionPayload.pathError(component["motionPath"], ids: ids, label: "component \(index)") {
                return error
            }
        }
        for (index, container) in scrollContainers.enumerated() {
            if let error = NIMotionPayload.pathError(
                container["motionPath"],
                ids: ids,
                label: "scroll container \(index)"
            ) {
                return error
            }
        }
        for owners in regions {
            for (id, value) in owners {
                for (index, region) in (value as? [[String: Any]] ?? []).enumerated() {
                    if let error = NIMotionPayload.pathError(
                        region["motionPath"],
                        ids: ids,
                        label: "region \(index) for '\(id)'"
                    ) {
                        return error
                    }
                }
            }
        }
        return nil
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty
    }

    private static func componentIDs(
        _ components: [[String: Any]],
        scrollContainerPaths: [String: [String]]
    )
        -> ComponentIDs {
        var ids: Set<String> = []
        var activeIDs: Set<String> = []
        func failure(_ error: String) -> ComponentIDs {
            ComponentIDs(all: ids, active: activeIDs, error: error)
        }
        for (index, component) in components.enumerated() {
            guard
                let id = component["id"] as? String,
                validIdentifier(id)
            else {
                return failure("component \(index) has an invalid id")
            }
            guard
                let type = component["type"] as? String,
                validIdentifier(type)
            else {
                return failure("component \(index) has an invalid type")
            }
            guard ids.insert(id).inserted else {
                return failure("duplicate component id '\(id)'")
            }
            guard let active = boolean(component["active"]) else {
                return failure(
                    "component '\(id)' active must be a boolean"
                )
            }
            guard boolean(component["interactive"]) != nil else {
                return failure(
                    "component '\(id)' interactive must be a boolean"
                )
            }
            guard
                let plane = component["plane"] as? String,
                NIHostPlane(rawValue: plane) != nil
            else {
                return failure(
                    "component '\(id)' has an invalid plane"
                )
            }
            guard
                let rawCoordinateSpace =
                component["coordinateSpace"] as? String,
                NICoordinateSpace(rawValue: rawCoordinateSpace) != nil
            else {
                return failure(
                    "component '\(id)' has an invalid coordinate space"
                )
            }
            if let opacity = component["opacity"] {
                guard
                    let value = NISafeGeometry.strictNumber(opacity),
                    (0 ... 1).contains(value)
                else {
                    return failure("component '\(id)' has an invalid opacity")
                }
            }
            if let error = componentRectError(
                component,
                id: id,
                active: active
            ) {
                return failure(error)
            }
            guard
                let scrollPath = component["scrollPath"] as? [String],
                validScrollPath(
                    scrollPath,
                    containerPaths: scrollContainerPaths
                )
            else {
                return failure(
                    "component '\(id)' has an invalid scroll path"
                )
            }
            if active {
                activeIDs.insert(id)
            }
        }
        return ComponentIDs(all: ids, active: activeIDs, error: nil)
    }

    private static func componentRectError(
        _ component: [String: Any],
        id: String,
        active: Bool
    )
        -> String? {
        guard let value = component["rect"] else {
            return "component '\(id)' must include rect"
        }
        if value is NSNull {
            return active
                ? "active component '\(id)' must include a valid rect"
                : nil
        }
        guard
            let rect = value as? [String: Any],
            NISafeGeometry.parseRect(rect) != nil
        else {
            return "component '\(id)' has an invalid rect"
        }
        return nil
    }

    private static func scrollContainerError(
        _ scrollContainers: [[String: Any]],
        ids: inout Set<String>,
        paths: inout [String: [String]]
    )
        -> String? {
        for (index, scrollContainer) in scrollContainers.enumerated() {
            guard
                let id = scrollContainer["id"] as? String,
                validIdentifier(id)
            else {
                return "scroll container \(index) has an invalid id"
            }
            guard ids.insert(id).inserted else {
                return "duplicate scroll container id '\(id)'"
            }
            guard let scrollPath = scrollContainer["scrollPath"] as? [String]
            else {
                return "scroll container '\(id)' has an invalid scroll path"
            }
            if let space = scrollContainer["coordinateSpace"],
               (space as? String).flatMap(NICoordinateSpace.init(rawValue:)) == nil {
                return "scroll container '\(id)' has an invalid coordinateSpace"
            }
            paths[id] = scrollPath
            guard
                let rect = scrollContainer["rect"] as? [String: Any],
                let parsedRect = NISafeGeometry.parseRect(rect)
            else {
                return "scroll container '\(id)' has an invalid rect"
            }
            guard
                let contentWidth = NISafeGeometry.strictNumber(
                    scrollContainer["contentWidth"]
                ),
                let contentHeight = NISafeGeometry.strictNumber(
                    scrollContainer["contentHeight"]
                ),
                contentWidth >= parsedRect.width,
                contentHeight >= parsedRect.height
            else {
                return "scroll container '\(id)' has invalid content size"
            }
            guard
                NISafeGeometry.strictNumber(scrollContainer["offsetX"]) != nil,
                NISafeGeometry.strictNumber(scrollContainer["offsetY"]) != nil
            else {
                return "scroll container '\(id)' has invalid offset"
            }
        }
        for (id, path) in paths
            where !validScrollPath(path, containerPaths: paths) ||
            path.contains(id) {
            return "scroll container '\(id)' has an invalid scroll path"
        }
        return nil
    }

    private static func validScrollPath(
        _ path: [String],
        containerPaths: [String: [String]]
    )
        -> Bool {
        guard Set(path).count == path.count else {
            return false
        }
        for (index, id) in path.enumerated() {
            guard
                let ancestorPath = containerPaths[id],
                ancestorPath == Array(path.prefix(index))
            else {
                return false
            }
        }
        return true
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

    private static func regionError(
        name: String,
        values: [String: Any],
        ids: Set<String>,
        scrollContainerPaths: [String: [String]]
    )
        -> String? {
        for (id, value) in values {
            guard ids.contains(id) else {
                return "\(name)s reference unknown component '\(id)'"
            }
            guard let regions = value as? [[String: Any]] else {
                return "\(name)s for '\(id)' must be an array"
            }
            for (index, region) in regions.enumerated() {
                guard
                    let rect = region["rect"] as? [String: Any],
                    NISafeGeometry.parseRect(rect) != nil,
                    let scrollPath = region["scrollPath"] as? [String],
                    validScrollPath(
                        scrollPath,
                        containerPaths: scrollContainerPaths
                    ),
                    let rawCoordinateSpace =
                    region["coordinateSpace"] as? String,
                    let coordinateSpace =
                    NICoordinateSpace(rawValue: rawCoordinateSpace)
                else {
                    return "\(name) \(index) for '\(id)' is invalid"
                }
                if name == "tint", NITintColor(region["color"]) == nil {
                    return "\(name) \(index) for '\(id)' has an invalid color"
                }
                if region["sticky"] != nil {
                    guard
                        let sticky = NISticky(region["sticky"]),
                        sticky.fits(scrollPath: scrollPath, coordinateSpace: coordinateSpace)
                    else {
                        return "\(name) \(index) for '\(id)' has an invalid sticky"
                    }
                }
            }
        }
        return nil
    }
}
