#if canImport(UIKit)
    import QuartzCore
    import UIKit

    /// An animation WebKit committed to Core Animation for the page, as matched against a motion.
    struct WebKitAnimation {
        let drawn: NIWebKitAnimation
        let source: CAPropertyAnimation
        let group: CAAnimationGroup?

        /// WebKit's translation as an additive track an island can replay, or nil when its timing
        /// cannot be copied.
        var track: CAKeyframeAnimation? {
            if let group,
               group.speed != 1 || group.timeOffset != 0 ||
               group.repeatCount != 0 && group.repeatCount != 1 || group.autoreverses {
                return nil
            }
            if let function = source.valueFunction?.name, function != .translate {
                return nil
            }
            let track = CAKeyframeAnimation(keyPath: "position")
            if let keyframes = source as? CAKeyframeAnimation {
                track.keyTimes = keyframes.keyTimes
                track.timingFunctions = keyframes.timingFunctions
                track.calculationMode = keyframes.calculationMode
            }
            track.values = drawn.values.map { NSValue(cgPoint: CGPoint(x: $0[0], y: $0.count > 1 ? $0[1] : 0)) }
            track.timingFunction = source.timingFunction
            track.duration = source.duration
            track.repeatCount = source.repeatCount
            track.repeatDuration = source.repeatDuration
            track.autoreverses = source.autoreverses
            track.speed = source.speed
            track.timeOffset = source.timeOffset
            track.beginTime = drawn.begin
            track.preferredFrameRateRange = source.preferredFrameRateRange
            track.isAdditive = true
            track.fillMode = .both
            track.isRemovedOnCompletion = false
            return track
        }

        /// The running animations WebKit committed under `root`, within `CALayer.webKitScanLimit`
        /// layers. The planes islands are placed in are not WebKit's and are skipped.
        static func committed(under root: CALayer) -> [WebKitAnimation] {
            var found: [WebKitAnimation] = []
            var visited = 0
            func visit(_ layer: CALayer, hiddenAbove: Bool) {
                guard !layer.isIslandPlane else { return }
                visited += 1
                guard visited <= CALayer.webKitScanLimit else { return }
                let hidden = hiddenAbove || layer.isHidden
                let drawsNothing = layer.contents == nil &&
                    (layer.backgroundColor?.alpha ?? 0) == 0 &&
                    (layer.sublayers?.isEmpty ?? true)
                for key in layer.animationKeys() ?? [] {
                    guard let animation = layer.animation(forKey: key) else { continue }
                    if let group = animation as? CAAnimationGroup {
                        found += group.animations?.compactMap { read($0, group: group, hidden: hidden || drawsNothing) } ?? []
                    } else if let read = read(animation, group: nil, hidden: hidden || drawsNothing) {
                        found.append(read)
                    }
                }
                layer.sublayers?.forEach { visit($0, hiddenAbove: hidden) }
            }
            visit(root, hiddenAbove: false)
            return found
        }

        private static func read(_ animation: CAAnimation, group: CAAnimationGroup?, hidden: Bool) -> WebKitAnimation? {
            // WebKit commits a paused Web Animation at speed 0 before the running one, and starting an
            // island on that track would hold it still.
            guard
                animation.speed != 0, group?.speed ?? 1 != 0,
                let property = animation as? CAPropertyAnimation,
                let keyPath = property.keyPath
            else {
                return nil
            }
            let keyframes = animation as? CAKeyframeAnimation
            let raw: [Any]
            if let values = keyframes?.values {
                raw = values
            } else if let basic = animation as? CABasicAnimation, let from = basic.fromValue, let toValue = basic.toValue {
                raw = [from, toValue]
            } else {
                return nil
            }
            let values: [[Double]] = raw.compactMap { value in
                if let numbers = value as? [NSNumber] {
                    return numbers.map(\.doubleValue)
                }
                if let number = value as? NSNumber {
                    return [number.doubleValue]
                }
                if let matrix = (value as? NSValue)?.caTransform3DValue {
                    return [Double(matrix.m41), Double(matrix.m42)]
                }
                return nil
            }
            guard values.count == raw.count else { return nil }
            // WebKit draws the `scale` property as a transform animation whose values are scale factors;
            // it is told apart so a scale is matched against scales only.
            let drawnKeyPath = property.valueFunction?.name == .scale ? NIWebKitAnimation.scaleKeyPath : keyPath
            return WebKitAnimation(
                drawn: NIWebKitAnimation(
                    keyPath: drawnKeyPath,
                    values: values,
                    duration: animation.duration,
                    begin: animation.beginTime + (group?.beginTime ?? 0),
                    hidden: hidden,
                    offsets: keyframes?.keyTimes?.map(\.doubleValue),
                    easing: easing(animation.timingFunction),
                    segmentEasings: keyframes?.timingFunctions?.map(easing),
                    interpolatesLinearly: keyframes == nil || keyframes?.calculationMode == .linear
                ),
                source: property,
                group: group
            )
        }

        private static func easing(_ function: CAMediaTimingFunction?) -> NIEasing {
            guard let function else { return .linear }
            var first: [Float] = [0, 0]
            var last: [Float] = [0, 0]
            function.getControlPoint(at: 1, values: &first)
            function.getControlPoint(at: 2, values: &last)
            return .cubicBezier(Double(first[0]), Double(first[1]), Double(last[0]), Double(last[1]))
        }
    }
#endif
