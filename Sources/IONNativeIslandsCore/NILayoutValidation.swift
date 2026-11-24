import CoreGraphics
import Foundation

enum NILayoutValidation {
    /// The first problem found in a layout, as the message the bridge reports.
    private struct Refusal: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
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
        do {
            try checkMotions(
                motions,
                components: components,
                scrollContainers: scrollContainers,
                regions: [exclusions, cutouts, tints]
            )
            let scrollContainerPaths = try scrollContainerPaths(scrollContainers)
            let (ids, activeIDs) = try componentIDs(components, scrollContainerPaths: scrollContainerPaths)
            var ordered: Set<String> = []
            for id in order {
                guard ids.contains(id) else {
                    throw Refusal("paint order references unknown component '\(id)'")
                }
                guard ordered.insert(id).inserted else {
                    throw Refusal("duplicate paint-order component '\(id)'")
                }
            }
            guard ordered == activeIDs else {
                throw Refusal("paint order must contain every active component and no inactive components")
            }
            for (name, values) in [("exclusion", exclusions), ("cutout", cutouts), ("tint", tints)] {
                try checkRegions(name: name, values: values, ids: ids, scrollContainerPaths: scrollContainerPaths)
            }
            return nil
        } catch {
            return String(describing: error)
        }
    }

    private static func checkMotions(
        _ motions: Any?,
        components: [[String: Any]],
        scrollContainers: [[String: Any]],
        regions: [[String: Any]]
    ) throws {
        let (ids, error) = NIMotionPayload.validate(motions)
        if let error { throw Refusal(error) }
        func checkPath(_ object: [String: Any], label: String) throws {
            let error = NIMotionPayload.pathError(object["motionPath"], ids: ids, label: label) ??
                NIMotionPayload.originsError(
                    object["motionOrigins"],
                    pathLength: (object["motionPath"] as? [Any])?.count ?? 0,
                    label: label
                )
            if let error { throw Refusal(error) }
        }
        for (index, component) in components.enumerated() {
            try checkPath(component, label: "component \(index)")
            for (clip, region) in (component["clips"] as? [[String: Any]] ?? []).enumerated() {
                try checkPath(region, label: "clip \(clip) of component \(index)")
            }
        }
        for (index, container) in scrollContainers.enumerated() {
            try checkPath(container, label: "scroll container \(index)")
        }
        for owners in regions {
            for (id, value) in owners {
                for (index, region) in (value as? [[String: Any]] ?? []).enumerated() {
                    try checkPath(region, label: "region \(index) for '\(id)'")
                }
            }
        }
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty
    }

    /// Every component id, and the active ones.
    private static func componentIDs(
        _ components: [[String: Any]],
        scrollContainerPaths: [String: [String]]
    ) throws
        -> (all: Set<String>, active: Set<String>) {
        var ids: Set<String> = []
        var activeIDs: Set<String> = []
        for (index, component) in components.enumerated() {
            guard
                let id = component["id"] as? String,
                validIdentifier(id)
            else {
                throw Refusal("component \(index) has an invalid id")
            }
            guard
                let type = component["type"] as? String,
                validIdentifier(type)
            else {
                throw Refusal("component \(index) has an invalid type")
            }
            guard ids.insert(id).inserted else {
                throw Refusal("duplicate component id '\(id)'")
            }
            guard let active = NISafeGeometry.strictBool(component["active"]) else {
                throw Refusal("component '\(id)' active must be a boolean")
            }
            guard NISafeGeometry.strictBool(component["interactive"]) != nil else {
                throw Refusal("component '\(id)' interactive must be a boolean")
            }
            guard
                let plane = component["plane"] as? String,
                NIHostPlane(rawValue: plane) != nil
            else {
                throw Refusal("component '\(id)' has an invalid plane")
            }
            guard
                let rawCoordinateSpace =
                component["coordinateSpace"] as? String,
                let coordinateSpace = NICoordinateSpace(rawValue: rawCoordinateSpace)
            else {
                throw Refusal("component '\(id)' has an invalid coordinate space")
            }
            try checkDrawing(of: component, id: id)
            try checkRect(of: component, id: id, active: active)
            guard
                let scrollPath = component["scrollPath"] as? [String],
                validScrollPath(
                    scrollPath,
                    containerPaths: scrollContainerPaths
                )
            else {
                throw Refusal("component '\(id)' has an invalid scroll path")
            }
            try checkStickyAndClips(
                of: component,
                id: id,
                scrollPath: scrollPath,
                coordinateSpace: coordinateSpace,
                scrollContainerPaths: scrollContainerPaths
            )
            if active {
                activeIDs.insert(id)
            }
        }
        return (ids, activeIDs)
    }

    /// How the host draws the component: its opacity, transform and portal.
    private static func checkDrawing(of component: [String: Any], id: String) throws {
        if let opacity = component["opacity"],
           !(NISafeGeometry.strictNumber(opacity).map((0 ... 1).contains) ?? false) {
            throw Refusal("component '\(id)' has an invalid opacity")
        }
        if component["transform"] != nil, NIIslandTransform(component["transform"]) == nil {
            throw Refusal("component '\(id)' has an invalid transform")
        }
        if let rawPortal = component["portal"],
           !(rawPortal is NSNull),
           (rawPortal as? String).map(validIdentifier) != true {
            throw Refusal("component '\(id)' has an invalid portal")
        }
        if let rawTransitionTag = component["transitionTag"],
           !(rawTransitionTag is NSNull),
           (rawTransitionTag as? String).map(validIdentifier) != true {
            throw Refusal("component '\(id)' has an invalid transitionTag")
        }
    }

    /// The box the component sticks with, and the shapes it shows only inside.
    private static func checkStickyAndClips(
        of component: [String: Any],
        id: String,
        scrollPath: [String],
        coordinateSpace: NICoordinateSpace,
        scrollContainerPaths: [String: [String]]
    ) throws {
        if component["sticky"] != nil {
            guard
                let sticky = NISticky(component["sticky"]),
                sticky.fits(scrollPath: scrollPath, coordinateSpace: coordinateSpace)
            else {
                throw Refusal("component '\(id)' has an invalid sticky")
            }
        }
        guard let clips = component["clips"] else { return }
        guard let clips = clips as? [[String: Any]] else {
            throw Refusal("clips for '\(id)' must be an array")
        }
        for (index, clip) in clips.enumerated() {
            try checkRegion(clip, label: "clip \(index) for '\(id)'", scrollContainerPaths: scrollContainerPaths)
        }
    }

    private static func checkRect(of component: [String: Any], id: String, active: Bool) throws {
        guard let value = component["rect"] else {
            throw Refusal("component '\(id)' must include rect")
        }
        if value is NSNull {
            if active { throw Refusal("active component '\(id)' must include a valid rect") }
            return
        }
        guard
            let rect = value as? [String: Any],
            NISafeGeometry.parseRect(rect) != nil
        else {
            throw Refusal("component '\(id)' has an invalid rect")
        }
    }

    /// Each scroll container's scroll path, by id.
    private static func scrollContainerPaths(_ scrollContainers: [[String: Any]]) throws -> [String: [String]] {
        var paths: [String: [String]] = [:]
        for (index, scrollContainer) in scrollContainers.enumerated() {
            guard
                let id = scrollContainer["id"] as? String,
                validIdentifier(id)
            else {
                throw Refusal("scroll container \(index) has an invalid id")
            }
            guard paths[id] == nil else {
                throw Refusal("duplicate scroll container id '\(id)'")
            }
            guard let scrollPath = scrollContainer["scrollPath"] as? [String]
            else {
                throw Refusal("scroll container '\(id)' has an invalid scroll path")
            }
            if let space = scrollContainer["coordinateSpace"],
               (space as? String).flatMap(NICoordinateSpace.init(rawValue:)) == nil {
                throw Refusal("scroll container '\(id)' has an invalid coordinateSpace")
            }
            paths[id] = scrollPath
            guard
                let rect = scrollContainer["rect"] as? [String: Any],
                let parsedRect = NISafeGeometry.parseRect(rect)
            else {
                throw Refusal("scroll container '\(id)' has an invalid rect")
            }
            if scrollContainer["sticky"] != nil {
                let space = (scrollContainer["coordinateSpace"] as? String).flatMap(NICoordinateSpace.init(rawValue:)) ?? .document
                guard
                    let sticky = NISticky(scrollContainer["sticky"]),
                    sticky.fits(scrollPath: scrollPath, coordinateSpace: space)
                else {
                    throw Refusal("scroll container '\(id)' has an invalid sticky")
                }
            }
            let linear = scrollContainer["linear"]
            if linear != nil, NISafeGeometry.numbers(linear, count: 4) == nil {
                throw Refusal("scroll container '\(id)' has an invalid linear")
            }
            // A transformed scroller's rect is the box it is drawn over, not its own size.
            guard
                let contentWidth = NISafeGeometry.strictNumber(
                    scrollContainer["contentWidth"]
                ),
                let contentHeight = NISafeGeometry.strictNumber(
                    scrollContainer["contentHeight"]
                ),
                linear != nil || CGFloat(contentWidth) >= parsedRect.width,
                linear != nil || CGFloat(contentHeight) >= parsedRect.height
            else {
                throw Refusal("scroll container '\(id)' has invalid content size")
            }
            guard
                NISafeGeometry.strictNumber(scrollContainer["offsetX"]) != nil,
                NISafeGeometry.strictNumber(scrollContainer["offsetY"]) != nil
            else {
                throw Refusal("scroll container '\(id)' has invalid offset")
            }
        }
        for (id, path) in paths
            where !validScrollPath(path, containerPaths: paths) ||
            path.contains(id) {
            throw Refusal("scroll container '\(id)' has an invalid scroll path")
        }
        return paths
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

    private static func checkRegions(
        name: String,
        values: [String: Any],
        ids: Set<String>,
        scrollContainerPaths: [String: [String]]
    ) throws {
        for (id, value) in values {
            guard ids.contains(id) else {
                throw Refusal("\(name)s reference unknown component '\(id)'")
            }
            guard let regions = value as? [[String: Any]] else {
                throw Refusal("\(name)s for '\(id)' must be an array")
            }
            for (index, region) in regions.enumerated() {
                let label = "\(name) \(index) for '\(id)'"
                try checkRegion(region, label: label, scrollContainerPaths: scrollContainerPaths)
                if name == "tint", NITintColor(region["color"]) == nil {
                    throw Refusal("\(label) has an invalid color")
                }
            }
        }
    }

    private static func checkRegion(
        _ region: [String: Any],
        label: String,
        scrollContainerPaths: [String: [String]]
    ) throws {
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
            throw Refusal("\(label) is invalid")
        }
        if region["sticky"] != nil {
            guard
                let sticky = NISticky(region["sticky"]),
                sticky.fits(scrollPath: scrollPath, coordinateSpace: coordinateSpace)
            else {
                throw Refusal("\(label) has an invalid sticky")
            }
        }
    }
}
