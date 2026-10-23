import CoreFoundation
import Foundation

enum NIEasing: Equatable {
    case linear
    case cubicBezier(Double, Double, Double, Double)
    case steps(Int, String)
    case points(inputs: [Double], outputs: [Double])

    func matches(_ other: NIEasing) -> Bool {
        func controls(_ easing: NIEasing) -> [Double]? {
            switch easing {
            case .linear: return [0, 0, 1, 1]
            case let .cubicBezier(startX, startY, endX, endY):
                return abs(startX - startY) < 1e-6 && abs(endX - endY) < 1e-6
                    ? [0, 0, 1, 1] : [startX, startY, endX, endY]
            case let .points(inputs, outputs) where zip(inputs, outputs).allSatisfy({ abs($0 - $1) < 1e-6 }):
                return [0, 0, 1, 1]
            default: return nil
            }
        }
        guard let lhs = controls(self), let rhs = controls(other) else { return self == other }
        return zip(lhs, rhs).allSatisfy { abs($0 - $1) < 1e-6 }
    }

    func apply(_ progress: Double) -> Double {
        switch self {
        case .linear:
            return progress
        case let .cubicBezier(startX, startY, endX, endY):
            return NIEasing.bezier(start: (startX, startY), end: (endX, endY), progress)
        case let .steps(count, jump):
            var step = (progress * Double(count)).rounded(.down)
            if jump == "start" || jump == "both" { step += 1 }
            if progress >= 0, step < 0 { step = 0 }
            let jumps: Double
            switch jump {
            case "none": jumps = Double(count - 1)
            case "both": jumps = Double(count + 1)
            default: jumps = Double(count)
            }
            if progress <= 1, step > jumps { step = jumps }
            return step / jumps
        case let .points(inputs, outputs):
            let last = inputs.count - 1
            if progress >= inputs[last] {
                var end = last
                while end > 0, inputs[end - 1] == inputs[last] { end -= 1 }
                if progress == inputs[last] || end == 0 { return outputs[last] }
                return lerp(
                    outputs[end - 1],
                    outputs[last],
                    (progress - inputs[end - 1]) / (inputs[last] - inputs[end - 1])
                )
            }
            var index = 0
            while index < last - 1, progress >= inputs[index + 1] { index += 1 }
            let span = inputs[index + 1] - inputs[index]
            if span <= 0 { return outputs[index + 1] }
            return lerp(outputs[index], outputs[index + 1], (progress - inputs[index]) / span)
        }
    }

    private static func bezier(
        start: (x: Double, y: Double),
        end: (x: Double, y: Double),
        _ progress: Double
    ) -> Double {
        if progress <= 0 {
            let slope: Double
            if start.x > 0 {
                slope = start.y / start.x
            } else if start.y == 0, end.x > 0 {
                slope = end.y / end.x
            } else if start.y == 0, end.y == 0 {
                slope = 1
            } else {
                slope = 0
            }
            return slope * progress
        }
        if progress >= 1 {
            let slope: Double
            if end.x < 1 {
                slope = (end.y - 1) / (end.x - 1)
            } else if end.y == 1, start.x < 1 {
                slope = (start.y - 1) / (start.x - 1)
            } else if end.y == 1, start.y == 1 {
                slope = 1
            } else {
                slope = 0
            }
            return 1 + slope * (progress - 1)
        }
        let linearX = 3 * start.x
        let quadraticX = 3 * (end.x - start.x) - linearX
        let cubicX = 1 - linearX - quadraticX
        let linearY = 3 * start.y
        let quadraticY = 3 * (end.y - start.y) - linearY
        let cubicY = 1 - linearY - quadraticY
        func xAt(_ param: Double) -> Double { ((cubicX * param + quadraticX) * param + linearX) * param }
        func yAt(_ param: Double) -> Double { ((cubicY * param + quadraticY) * param + linearY) * param }
        func slopeAt(_ param: Double) -> Double { (3 * cubicX * param + 2 * quadraticX) * param + linearX }
        var param = progress
        for _ in 0 ..< 8 {
            let error = xAt(param) - progress
            if abs(error) < 1e-7 { return yAt(param) }
            let derivative = slopeAt(param)
            if abs(derivative) < 1e-6 { break }
            param -= error / derivative
        }
        var low = 0.0
        var high = 1.0
        param = progress
        while high - low > 1e-9 {
            let value = xAt(param)
            if abs(value - progress) < 1e-7 { break }
            if progress > value { low = param } else { high = param }
            param = (high - low) / 2 + low
        }
        return yAt(param)
    }
}

private func lerp(_ start: Double, _ end: Double, _ amount: Double) -> Double {
    start + (end - start) * amount
}

enum NIMotionChannel: String {
    case translate
    case opacity
}

struct NIMotionKeyframe {
    let offset: Double
    let value: [Double]
    let easing: NIEasing
}

struct NIMotionAnimation {
    let channel: NIMotionChannel
    let keyframes: [NIMotionKeyframe]
    var easing: NIEasing = .linear
    var delay: Double = 0
    let duration: Double
    var iterations: Double = 1
    var iterationStart: Double = 0
    var direction: String = "normal"
    var startTime: Double
    var playbackRate: Double = 1
    var sampledTime: Double = 0

    private var activeDuration: Double {
        iterations.isInfinite ? .infinity : duration * iterations
    }

    func localTime(_ pageTime: Double) -> Double {
        (pageTime - startTime) * playbackRate
    }

    func runs(after pageTime: Double) -> Bool {
        let local = localTime(pageTime)
        return playbackRate > 0 ? local < delay + activeDuration : local > 0
    }

    func value(at localTime: Double) -> [Double] {
        let activeTime = min(max(localTime - delay, 0), activeDuration)
        let overall = (duration > 0 ? activeTime / duration : 0) + iterationStart
        var simple = overall.isInfinite
            ? iterationStart.truncatingRemainder(dividingBy: 1)
            : overall.truncatingRemainder(dividingBy: 1)
        if simple == 0, activeTime > 0, activeTime == activeDuration, iterations != 0 { simple = 1 }
        let iteration = simple == 1 ? overall.rounded(.down) - 1 : overall.rounded(.down)
        let forwards: Bool
        switch direction {
        case "reverse": forwards = false
        case "alternate": forwards = iteration.truncatingRemainder(dividingBy: 2) == 0
        case "alternate-reverse": forwards = iteration.truncatingRemainder(dividingBy: 2) != 0
        default: forwards = true
        }
        return interpolate(easing.apply(forwards ? simple : 1 - simple))
    }

    private func interpolate(_ progress: Double) -> [Double] {
        let last = keyframes.count - 1
        var index = 0
        if progress >= 1 {
            index = last - 1
            while index > 0, keyframes[index].offset == keyframes[last].offset { index -= 1 }
        } else if progress > 0 {
            while index < last - 1, progress >= keyframes[index + 1].offset { index += 1 }
        }
        let from = keyframes[index]
        let next = keyframes[index + 1]
        let span = next.offset - from.offset
        let local = span > 0 ? (progress - from.offset) / span : 1
        let eased = from.easing.apply(local)
        return zip(from.value, next.value).map { lerp($0, $1, eased) }
    }
}

struct NIWebKitAnimation {
    let keyPath: String
    let values: [[Double]]
    let duration: Double
    let begin: Double
    var hidden = false
    var offsets: [Double]?
    var easing: NIEasing = .linear
    var segmentEasings: [NIEasing]?
    var interpolatesLinearly = true
}

extension NIMotionAnimation {
    func isDrawn(by animation: NIWebKitAnimation) -> Bool {
        let keyPath = channel == .translate ? "transform" : "opacity"
        let tolerance = channel == .translate ? 0.5 : 0.01
        guard
            animation.keyPath == keyPath,
            animation.values.count == keyframes.count,
            abs(animation.duration * 1000 - duration) < 1,
            animation.interpolatesLinearly,
            easing.matches(animation.easing)
        else {
            return false
        }
        let offsets = animation.offsets ?? keyframes.indices.map { Double($0) / Double(keyframes.count - 1) }
        let segments = animation.segmentEasings ?? Array(repeating: .linear, count: keyframes.count - 1)
        guard offsets.count == keyframes.count, segments.count == keyframes.count - 1,
              zip(offsets, keyframes).allSatisfy({ abs($0 - $1.offset) < 1e-4 }),
              zip(segments, keyframes.dropLast()).allSatisfy({ $0.matches($1.easing) })
        else { return false }
        return zip(animation.values, keyframes).allSatisfy { values, keyframe in
            values.count >= keyframe.value.count && zip(values, keyframe.value).allSatisfy { abs($0 - $1) <= tolerance }
        }
    }
}

struct NIMotion {
    let id: String
    private(set) var animations: [NIMotionAnimation]
    var held = false
    let key: String

    init(id: String, animations: [NIMotionAnimation]) {
        self.id = id
        self.animations = animations
        key = "\(id)@" + animations.map { String($0.startTime) }.joined(separator: ",")
    }

    mutating func shiftStart(byMilliseconds delta: Double) {
        for index in animations.indices { animations[index].startTime += delta }
    }

    private var translation: NIMotionAnimation? {
        animations.first { $0.channel == .translate }
    }

    private var fade: NIMotionAnimation? {
        animations.first { $0.channel == .opacity }
    }

    func offset(at pageTime: Double) -> CGPoint {
        guard !held, let animation = translation else { return .zero }
        let now = animation.value(at: animation.localTime(pageTime))
        let then = animation.value(at: animation.sampledTime)
        return CGPoint(x: now[0] - then[0], y: now[1] - then[1])
    }

    func translation(at pageTime: Double) -> CGPoint? {
        guard !held, let animation = translation else { return nil }
        let value = animation.value(at: animation.localTime(pageTime))
        return CGPoint(x: value[0], y: value[1])
    }

    func opacity(at pageTime: Double) -> Double? {
        fade.map { min(1, max(0, $0.value(at: held ? $0.sampledTime : $0.localTime(pageTime))[0])) }
    }

    func runs(after pageTime: Double) -> Bool {
        animations.contains { $0.runs(after: pageTime) }
    }
}

final class NIPageClock {
    private let lock = NSLock()
    private var offsetMilliseconds = Double.infinity

    func sample(pageMilliseconds: Double, nativeSeconds: Double) {
        guard pageMilliseconds.isFinite else { return }
        lock.lock()
        offsetMilliseconds = min(offsetMilliseconds, nativeSeconds * 1000 - pageMilliseconds)
        lock.unlock()
    }

    func pageTime(nativeSeconds: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return offsetMilliseconds.isFinite ? nativeSeconds * 1000 - offsetMilliseconds : nil
    }

    func clear() {
        lock.lock()
        offsetMilliseconds = .infinity
        lock.unlock()
    }
}

enum NIMotionPayload {
    private static let directions: Set<String> = ["normal", "reverse", "alternate", "alternate-reverse"]
    private static let fills: Set<String> = ["none", "forwards", "backwards", "both"]
    private static let jumps: Set<String> = ["start", "end", "none", "both"]

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
            guard let animations = motion["animations"] as? [Any], (1 ... 2).contains(animations.count) else {
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
            let size = channel == "translate" ? 2 : 1
            guard let value = keyframe["value"] as? [Any], value.count == size else {
                return "keyframe \(index) has an invalid value"
            }
            for component in value {
                guard let number = number(component) else { return "keyframe \(index) has an invalid value" }
                if channel != "translate", !(0 ... 1).contains(number) {
                    return "keyframe \(index) has an invalid value"
                }
            }
            if let easing = keyframe["easing"], let error = easingError(easing) {
                return "keyframe \(index) \(error)"
            }
        }
        return nil
    }

    private static func animationError(_ animation: [String: Any], channels: inout Set<String>) -> String? {
        guard let channel = animation["channel"] as? String, channel == "translate" || channel == "opacity" else {
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
        guard let direction = animation["direction"] as? String, directions.contains(direction) else {
            return "has an invalid direction"
        }
        guard let fill = animation["fill"] as? String, fills.contains(fill) else { return "has an invalid fill" }
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
                let jump = easing["jump"] as? String, jumps.contains(jump),
                jump != "none" || count >= 2
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

    private static func animation(_ value: [String: Any]) -> NIMotionAnimation? {
        guard
            let channel = (value["channel"] as? String).flatMap(NIMotionChannel.init(rawValue:)),
            let keyframes = value["keyframes"] as? [[String: Any]],
            let duration = number(value["duration"]),
            let startTime = number(value["startTime"])
        else {
            return nil
        }
        return NIMotionAnimation(
            channel: channel,
            keyframes: keyframes.map {
                NIMotionKeyframe(
                    offset: number($0["offset"]) ?? 0,
                    value: ($0["value"] as? [Any] ?? []).compactMap(number),
                    easing: easing($0["easing"])
                )
            },
            easing: easing(value["easing"]),
            delay: number(value["delay"]) ?? 0,
            duration: duration,
            iterations: value["iterations"] is NSNull ? .infinity : number(value["iterations"]) ?? 1,
            iterationStart: number(value["iterationStart"]) ?? 0,
            direction: value["direction"] as? String ?? "normal",
            startTime: startTime,
            playbackRate: number(value["playbackRate"]) ?? 1,
            sampledTime: number(value["sampledTime"]) ?? 0
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
        if let steps = number(easing["steps"]), let jump = easing["jump"] as? String {
            return .steps(Int(steps), jump)
        }
        return .linear
    }

    private static func number(_ value: Any?) -> Double? {
        NISafeGeometry.strictNumber(value)
    }
}
