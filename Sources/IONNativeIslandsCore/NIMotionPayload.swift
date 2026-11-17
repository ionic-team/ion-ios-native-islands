import CoreFoundation
import Foundation

enum NIMotionPayload {
    private static let fills: Set<String> = ["none", "forwards", "backwards", "both"]

    static func validate(_ value: Any?) -> (ids: Set<String>, error: String?) {
        guard let value, !(value is NSNull) else { return ([], nil) }
        guard let motions = value as? [Any] else { return ([], "motions must be an array") }
        var ids: Set<String> = []
        for (index, raw) in motions.enumerated() {
            guard let motion = raw as? [String: Any] else { return (ids, "motion \(index) must be an object") }
            guard let id = motion["id"] as? String, NILayoutValidation.validIdentifier(id) else {
                return (ids, "motion \(index) has an invalid id")
            }
            guard ids.insert(id).inserted else { return (ids, "duplicate motion id '\(id)'") }
            guard let animations = motion["animations"] as? [Any], !animations.isEmpty else {
                return (ids, "motion '\(id)' has an invalid number of animations")
            }
            var channels: Set<String> = []
            for (entry, animation) in animations.enumerated() {
                guard let animation = animation as? [String: Any] else {
                    return (ids, "motion '\(id)' animation \(entry) must be an object")
                }
                if let error = animationError(animation, channels: &channels) {
                    return (ids, "motion '\(id)' animation \(entry) \(error)")
                }
            }
        }
        return (ids, nil)
    }

    private static func keyframesError(_ keyframes: [Any], channel: String) -> String? {
        var previous = 0.0
        for (index, raw) in keyframes.enumerated() {
            guard let keyframe = raw as? [String: Any] else { return "keyframe \(index) must be an object" }
            guard let offset = number(keyframe["offset"]), offset >= previous, offset <= 1 else {
                return "keyframe offsets must ascend within 0 to 1"
            }
            if (index == 0 && offset != 0) || (index == keyframes.count - 1 && offset != 1) {
                return "keyframes must span 0 to 1"
            }
            previous = offset
            let size = NIMotionChannel(rawValue: channel)?.size ?? 2
            guard let value = keyframe["value"] as? [Any], value.count == size else {
                return "keyframe \(index) has an invalid value"
            }
            for component in value {
                guard let number = number(component) else { return "keyframe \(index) has an invalid value" }
                let valid = switch channel {
                case "translate": true
                case "scale": number >= 0
                default: (0 ... 1).contains(number)
                }
                if !valid { return "keyframe \(index) has an invalid value" }
            }
            if let easing = keyframe["easing"], let error = easingError(easing) {
                return "keyframe \(index) \(error)"
            }
        }
        return nil
    }

    private static func animationError(_ animation: [String: Any], channels: inout Set<String>) -> String? {
        guard let channel = animation["channel"] as? String, NIMotionChannel(rawValue: channel) != nil else {
            return "has an invalid channel"
        }
        guard channels.insert(channel).inserted else { return "repeats a channel" }
        guard let keyframes = animation["keyframes"] as? [Any], keyframes.count >= 2 else {
            return "has an invalid number of keyframes"
        }
        if let error = keyframesError(keyframes, channel: channel) { return error }
        if let easing = animation["easing"], let error = easingError(easing) { return error }
        for name in ["startTime", "sampledTime", "delay", "endDelay"] where number(animation[name]) == nil {
            return "has an invalid \(name)"
        }
        guard let duration = number(animation["duration"]), duration > 0 else {
            return "has an invalid duration"
        }
        if !(animation["iterations"] is NSNull) {
            guard let iterations = number(animation["iterations"]), iterations >= 0 else {
                return "has an invalid iterations"
            }
        }
        guard let start = number(animation["iterationStart"]), start >= 0 else {
            return "has an invalid iterationStart"
        }
        guard let rate = number(animation["playbackRate"]), rate != 0 else {
            return "has an invalid playbackRate"
        }
        guard (animation["direction"] as? String).flatMap(NIPlaybackDirection.init(rawValue:)) != nil else {
            return "has an invalid direction"
        }
        guard let fill = animation["fill"] as? String, fills.contains(fill) else { return "has an invalid fill" }
        if let timeline = animation["timeline"] { return timelineError(timeline) }
        return nil
    }

    private static func timelineError(_ value: Any) -> String? {
        guard let timeline = value as? [String: Any] else { return "timeline must be an object" }
        if let scroller = timeline["scroller"] {
            guard let id = scroller as? String, NILayoutValidation.validIdentifier(id) else {
                return "has an invalid timeline scroller"
            }
        }
        guard let axis = timeline["axis"] as? String, axis == "x" || axis == "y" else {
            return "has an invalid timeline axis"
        }
        guard let start = number(timeline["start"]), let end = number(timeline["end"]), end > start else {
            return "has an invalid timeline range"
        }
        return nil
    }

    private static func easingError(_ value: Any) -> String? {
        guard let easing = value as? [String: Any] else { return "easing must be an object" }
        let bezier = easing["bezier"] as? [Any]
        let steps = easing["steps"]
        let points = easing["points"] as? [Any]
        guard [bezier as Any?, steps, points as Any?].compactMap({ $0 }).count == 1 else {
            return "easing must name exactly one function"
        }
        if let bezier {
            let values = bezier.compactMap(number)
            guard
                bezier.count == 4, values.count == 4,
                (0 ... 1).contains(values[0]), (0 ... 1).contains(values[2])
            else {
                return "has an invalid cubic Bézier"
            }
        }
        if let steps {
            guard
                let count = number(steps), count.rounded() == count, count >= 1,
                let jump = (easing["jump"] as? String).flatMap(NIStepJump.init(rawValue:)),
                jump != .none || count >= 2
            else {
                return "has invalid steps"
            }
        }
        if let points {
            let values = points.compactMap(number)
            guard
                points.count % 2 == 0, points.count >= 4, values.count == points.count
            else {
                return "has invalid linear stops"
            }
            var input = -Double.infinity
            for index in stride(from: 0, to: values.count, by: 2) {
                if values[index] < input { return "has invalid linear stops" }
                input = values[index]
            }
        }
        return nil
    }

    static func pathError(_ value: Any?, ids: Set<String>, label: String) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let path = value as? [Any] else { return "\(label) motionPath must be an array" }
        var seen: Set<String> = []
        for (index, raw) in path.enumerated() {
            guard let id = raw as? String else { return "\(label) motionPath entry \(index) has an invalid id" }
            guard ids.contains(id) else { return "\(label) motionPath references unknown motion '\(id)'" }
            guard seen.insert(id).inserted else { return "\(label) motionPath repeats motion '\(id)'" }
        }
        return nil
    }

    static func parse(_ value: Any?) -> [String: NIMotion] {
        guard let motions = value as? [[String: Any]] else { return [:] }
        var parsed: [String: NIMotion] = [:]
        for motion in motions {
            guard let id = motion["id"] as? String, let animations = motion["animations"] as? [[String: Any]] else {
                continue
            }
            parsed[id] = NIMotion(id: id, animations: animations.compactMap(animation))
        }
        return parsed
    }

    static func path(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    /// Where each motion in a path scales about: one [x, y] per entry, from the region's corner.
    static func originsError(_ value: Any?, pathLength: Int, label: String) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let origins = value as? [Any] else { return "\(label) motionOrigins must be an array" }
        guard origins.count == pathLength else { return "\(label) motionOrigins must match its motionPath" }
        for (index, raw) in origins.enumerated() {
            guard let origin = raw as? [Any], origin.count == 2, origin.allSatisfy({ number($0) != nil }) else {
                return "\(label) motionOrigins entry \(index) is invalid"
            }
        }
        return nil
    }

    static func origins(_ value: Any?) -> [CGPoint] {
        (value as? [[Any]] ?? []).compactMap { origin in
            guard origin.count == 2, let x = number(origin[0]), let y = number(origin[1]) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    private static func animation(_ value: [String: Any]) -> NIMotionAnimation? {
        guard
            let channel = (value["channel"] as? String).flatMap(NIMotionChannel.init(rawValue:)),
            let keyframes = value["keyframes"] as? [[String: Any]],
            let duration = number(value["duration"]),
            let startTime = number(value["startTime"])
        else {
            return nil
        }
        let frames = keyframes.map {
            NIMotionKeyframe(
                offset: number($0["offset"]) ?? 0,
                value: ($0["value"] as? [Any] ?? []).compactMap(number),
                easing: easing($0["easing"])
            )
        }
        return NIMotionAnimation(
            channel: channel,
            keyframes: frames,
            easing: easing(value["easing"]),
            delay: number(value["delay"]) ?? 0,
            duration: duration,
            iterations: value["iterations"] is NSNull ? .infinity : number(value["iterations"]) ?? 1,
            iterationStart: number(value["iterationStart"]) ?? 0,
            direction: (value["direction"] as? String).flatMap(NIPlaybackDirection.init(rawValue:)) ?? .normal,
            startTime: startTime,
            playbackRate: number(value["playbackRate"]) ?? 1,
            sampledTime: number(value["sampledTime"]) ?? 0,
            timeline: (value["timeline"] as? [String: Any]).flatMap(timeline)
        )
    }

    private static func timeline(_ value: [String: Any]) -> NIMotionTimeline? {
        guard let start = number(value["start"]), let end = number(value["end"]) else { return nil }
        return NIMotionTimeline(
            scroller: value["scroller"] as? String,
            vertical: value["axis"] as? String == "y",
            start: start,
            end: end
        )
    }

    private static func easing(_ value: Any?) -> NIEasing {
        guard let easing = value as? [String: Any] else { return .linear }
        if let bezier = (easing["bezier"] as? [Any])?.compactMap(number), bezier.count == 4 {
            return .cubicBezier(bezier[0], bezier[1], bezier[2], bezier[3])
        }
        if let points = (easing["points"] as? [Any])?.compactMap(number), points.count >= 4 {
            return .points(
                inputs: stride(from: 0, to: points.count, by: 2).map { points[$0] },
                outputs: stride(from: 1, to: points.count, by: 2).map { points[$0] }
            )
        }
        if let steps = number(easing["steps"]), let jump = (easing["jump"] as? String).flatMap(NIStepJump.init(rawValue:)) {
            return .steps(Int(steps), jump)
        }
        return .linear
    }

    private static func number(_ value: Any?) -> Double? {
        NISafeGeometry.strictNumber(value)
    }
}
