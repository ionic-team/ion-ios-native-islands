import CoreFoundation
import Foundation

/// Where a CSS `steps()` easing jumps.
enum NIStepJump: String {
    case start
    case end
    case none
    case both
}

enum NIPlaybackDirection: String {
    case normal
    case reverse
    case alternate
    case alternateReverse = "alternate-reverse"
}

enum NIEasing: Equatable {
    case linear
    case cubicBezier(Double, Double, Double, Double)
    case steps(Int, NIStepJump)
    case points(inputs: [Double], outputs: [Double])

    func matches(_ other: NIEasing) -> Bool {
        func controls(_ easing: NIEasing) -> [Double]? {
            switch easing {
            case .linear: [0, 0, 1, 1]
            case .cubicBezier(let startX, let startY, let endX, let endY):
                abs(startX - startY) < 1e-6 && abs(endX - endY) < 1e-6
                    ? [0, 0, 1, 1] : [startX, startY, endX, endY]
            case .points(let inputs, let outputs) where zip(inputs, outputs).allSatisfy { abs($0 - $1) < 1e-6 }:
                [0, 0, 1, 1]
            default: nil
            }
        }
        guard let lhs = controls(self), let rhs = controls(other) else { return self == other }
        return zip(lhs, rhs).allSatisfy { abs($0 - $1) < 1e-6 }
    }

    func apply(_ progress: Double) -> Double {
        switch self {
        case .linear:
            return progress
        case .cubicBezier(let startX, let startY, let endX, let endY):
            return NIEasing.bezier(start: (startX, startY), end: (endX, endY), progress)
        case .steps(let count, let jump):
            var step = (progress * Double(count)).rounded(.down)
            if jump == .start || jump == .both {
                step += 1
            }
            if progress >= 0, step < 0 {
                step = 0
            }
            let jumps = switch jump {
            case .none: Double(count - 1)
            case .both: Double(count + 1)
            case .start, .end: Double(count)
            }
            if progress <= 1, step > jumps {
                step = jumps
            }
            return step / jumps
        case .points(let inputs, let outputs):
            let last = inputs.count - 1
            if progress >= inputs[last] {
                var end = last
                while end > 0, inputs[end - 1] == inputs[last] {
                    end -= 1
                }
                if progress == inputs[last] || end == 0 {
                    return outputs[last]
                }
                return lerp(
                    outputs[end - 1],
                    outputs[last],
                    (progress - inputs[end - 1]) / (inputs[last] - inputs[end - 1])
                )
            }
            var index = 0
            while index < last - 1, progress >= inputs[index + 1] {
                index += 1
            }
            let span = inputs[index + 1] - inputs[index]
            if span <= 0 {
                return outputs[index + 1]
            }
            return lerp(outputs[index], outputs[index + 1], (progress - inputs[index]) / span)
        }
    }

    private static func bezier(
        start: (x: Double, y: Double),
        end: (x: Double, y: Double),
        _ progress: Double
    )
        -> Double {
        if progress <= 0 {
            let slope: Double = if start.x > 0 {
                start.y / start.x
            } else if start.y == 0, end.x > 0 {
                end.y / end.x
            } else if start.y == 0, end.y == 0 {
                1
            } else {
                0
            }
            return slope * progress
        }
        if progress >= 1 {
            let slope: Double = if end.x < 1 {
                (end.y - 1) / (end.x - 1)
            } else if end.y == 1, start.x < 1 {
                (start.y - 1) / (start.x - 1)
            } else if end.y == 1, start.y == 1 {
                1
            } else {
                0
            }
            return 1 + slope * (progress - 1)
        }
        let linearX = 3 * start.x
        let quadraticX = 3 * (end.x - start.x) - linearX
        let cubicX = 1 - linearX - quadraticX
        let linearY = 3 * start.y
        let quadraticY = 3 * (end.y - start.y) - linearY
        let cubicY = 1 - linearY - quadraticY
        func xAt(_ param: Double) -> Double {
            ((cubicX * param + quadraticX) * param + linearX) * param
        }
        func yAt(_ param: Double) -> Double {
            ((cubicY * param + quadraticY) * param + linearY) * param
        }
        func slopeAt(_ param: Double) -> Double {
            (3 * cubicX * param + 2 * quadraticX) * param + linearX
        }
        var param = progress
        for _ in 0..<8 {
            let error = xAt(param) - progress
            if abs(error) < 1e-7 {
                return yAt(param)
            }
            let derivative = slopeAt(param)
            if abs(derivative) < 1e-6 {
                break
            }
            param -= error / derivative
        }
        var low = 0.0
        var high = 1.0
        param = progress
        while high - low > 1e-9 {
            let value = xAt(param)
            if abs(value - progress) < 1e-7 {
                break
            }
            if progress > value {
                low = param
            } else {
                high = param
            }
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
    case scale

    /// How many numbers each keyframe holds: x and y, or one opacity.
    var size: Int {
        self == .opacity ? 1 : 2
    }
}

/// A scroll-driven animation's timeline: the offset, in CSS px, of `scroller` (the document's when
/// nil) along one axis, mapped onto 0% at `start` and 100% at `end`.
struct NIMotionTimeline: Equatable {
    let scroller: String?
    let vertical: Bool
    let start: Double
    let end: Double

    func percent(at offset: Double) -> Double {
        (offset - start) / (end - start) * 100
    }
}

/// Where each scroll-driven motion's scroller is scrolled to, in CSS px; nil when unknown.
typealias NIScrollOffsets = (NIMotionTimeline) -> Double?

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
    var direction: NIPlaybackDirection = .normal
    var startTime: Double
    var playbackRate: Double = 1
    var sampledTime: Double = 0
    /// Times the animation by scrolling: its times are then percentages of the timeline.
    var timeline: NIMotionTimeline?

    private var activeDuration: Double {
        iterations.isInfinite ? .infinity : duration * iterations
    }

    /// Its local time at `pageTime`, or, for a scroll-driven one, at the offset `scrolled` gives.
    func localTime(_ pageTime: Double, scrolled: NIScrollOffsets? = nil) -> Double {
        guard let timeline else { return (pageTime - startTime) * playbackRate }
        guard let offset = scrolled?(timeline) else { return sampledTime }
        return (timeline.percent(at: offset) - startTime) * playbackRate
    }

    /// Whether the clock still moves it after `pageTime`; scrolling moves a scroll-driven one.
    func runs(after pageTime: Double) -> Bool {
        guard timeline == nil else { return false }
        let local = localTime(pageTime)
        return playbackRate > 0 ? local < delay + activeDuration : local > 0
    }

    func value(at localTime: Double) -> [Double] {
        let activeTime = min(max(localTime - delay, 0), activeDuration)
        let overall = (duration > 0 ? activeTime / duration : 0) + iterationStart
        var simple = overall.isInfinite
            ? iterationStart.truncatingRemainder(dividingBy: 1)
            : overall.truncatingRemainder(dividingBy: 1)
        if simple == 0, activeTime > 0, activeTime == activeDuration, iterations != 0 {
            simple = 1
        }
        let iteration = simple == 1 ? overall.rounded(.down) - 1 : overall.rounded(.down)
        let forwards: Bool = switch direction {
        case .normal: true
        case .reverse: false
        case .alternate: iteration.truncatingRemainder(dividingBy: 2) == 0
        case .alternateReverse: iteration.truncatingRemainder(dividingBy: 2) != 0
        }
        return interpolate(easing.apply(forwards ? simple : 1 - simple))
    }

    private func interpolate(_ progress: Double) -> [Double] {
        let last = keyframes.count - 1
        var index = 0
        if progress >= 1 {
            index = last - 1
            while index > 0, keyframes[index].offset == keyframes[last].offset {
                index -= 1
            }
        } else if progress > 0 {
            while index < last - 1, progress >= keyframes[index + 1].offset {
                index += 1
            }
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
    /// The key path a transform animation with a scale value function is recorded under.
    static let scaleKeyPath = "transform/scale"

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
        let keyPath = switch channel {
        case .translate: "transform"
        case .opacity: "opacity"
        case .scale: NIWebKitAnimation.scaleKeyPath
        }
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
    let key: String

    init(id: String, animations: [NIMotionAnimation]) {
        self.id = id
        self.animations = animations
        self.key = "\(id)@" + animations.map { String($0.startTime) }.joined(separator: ",")
    }

    mutating func shiftStart(byMilliseconds delta: Double) {
        for index in animations.indices {
            animations[index].startTime += delta
        }
    }

    var translationAnimation: NIMotionAnimation? {
        animations.first { $0.channel == .translate }
    }

    var fadeAnimation: NIMotionAnimation? {
        animations.first { $0.channel == .opacity }
    }

    var scaleAnimation: NIMotionAnimation? {
        animations.first { $0.channel == .scale }
    }

    /// Whether scrolling moves it rather than the clock.
    var isScrollDriven: Bool {
        animations.contains { $0.timeline != nil }
    }

    /// Whether scrolling `scroller` (the document when nil) moves it.
    func followsScroll(_ scroller: String?) -> Bool {
        animations.contains { $0.timeline.map { $0.scroller == scroller } ?? false }
    }

    /// The scale about this motion's origin, relative to the one the plan was drawn at.
    func scale(at pageTime: Double, scrolled: NIScrollOffsets? = nil) -> CGSize {
        guard let animation = scaleAnimation else { return CGSize(width: 1, height: 1) }
        let then = animation.value(at: animation.sampledTime)
        guard then.count == 2, then[0] > 0, then[1] > 0 else { return CGSize(width: 1, height: 1) }
        let now = animation.value(at: animation.localTime(pageTime, scrolled: scrolled))
        return CGSize(width: now[0] / then[0], height: now[1] / then[1])
    }

    func offset(at pageTime: Double, scrolled: NIScrollOffsets? = nil) -> CGPoint {
        guard let animation = translationAnimation else { return .zero }
        let now = animation.value(at: animation.localTime(pageTime, scrolled: scrolled))
        let then = animation.value(at: animation.sampledTime)
        return CGPoint(x: now[0] - then[0], y: now[1] - then[1])
    }

    func translation(at pageTime: Double) -> CGPoint? {
        guard let animation = translationAnimation else { return nil }
        let value = animation.value(at: animation.localTime(pageTime))
        return CGPoint(x: value[0], y: value[1])
    }

    func opacity(at pageTime: Double, scrolled: NIScrollOffsets? = nil) -> Double? {
        fadeAnimation.map { min(1, max(0, $0.value(at: $0.localTime(pageTime, scrolled: scrolled))[0])) }
    }

    /// The opacity where the layout measured the motion.
    var measuredOpacity: Double? {
        fadeAnimation.map { min(1, max(0, $0.value(at: $0.sampledTime)[0])) }
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

    func nativeSeconds(pageTime: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return offsetMilliseconds.isFinite ? (pageTime + offsetMilliseconds) / 1000 : nil
    }

    func clear() {
        lock.lock()
        offsetMilliseconds = .infinity
        lock.unlock()
    }
}
