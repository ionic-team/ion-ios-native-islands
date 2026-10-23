#if canImport(UIKit)
    import QuartzCore
    import UIKit

    extension NativeIslandsContainer {
        var motionTime: Double? {
            guard !motions.isEmpty else { return nil }
            let time = motionFrameTime ?? motionLink.map(nextFrameTime) ?? CACurrentMediaTime()
            return pageClock?.pageTime(nativeSeconds: time)
        }

        func moved(_ rect: IslandRect, motionPath: [String]) -> IslandRect {
            guard !motionPath.isEmpty, let time = motionTime else { return rect }
            var moved = rect
            for id in motionPath {
                guard let offset = motions[id]?.offset(at: time) else { continue }
                moved.x += offset.x
                moved.y += offset.y
            }
            return moved
        }

        func fadedOut(_ path: [String]) -> Bool {
            motionOpacity(path) < 0.5
        }

        func motionOpacity(_ path: [String]) -> Double {
            guard !path.isEmpty, let time = motionTime else { return 1 }
            return path.reduce(1.0) { $0 * (motions[$1]?.opacity(at: time) ?? 1) }
        }

        func alpha(of component: IslandComponent) -> CGFloat {
            component.opacity * CGFloat(motionOpacity(component.motionPath))
        }

        func scheduleMotionFrames() {
            guard
                let now = pageClock?.pageTime(nativeSeconds: CACurrentMediaTime()),
                !unsyncedMotions.isEmpty || motions.values.contains(where: { $0.runs(after: now) })
            else {
                return
            }
            guard motionLink == nil else { return }
            let link = CADisplayLink(target: NativeIslandsMotionTarget(self), selector: #selector(NativeIslandsMotionTarget.tick(_:)))
            link.add(to: .main, forMode: .common)
            motionLink = link
        }

        func stopMotion() {
            motionLink?.invalidate()
            motionLink = nil
            if let observer = commitObserver {
                CFRunLoopObserverInvalidate(observer)
                commitObserver = nil
            }
        }

        func adopt(_ incoming: [String: NIMotion]) {
            let now = CACurrentMediaTime()
            var adopted = incoming
            for (id, motion) in incoming {
                if let correction = motionStartCorrections[motion.key] {
                    adopted[id]?.shiftStart(byMilliseconds: correction)
                } else {
                    unsyncedMotions[motion.key] = unsyncedMotions[motion.key] ?? now
                    adopted[id]?.held = true
                }
            }
            let keys = Set(incoming.values.map(\.key))
            motionStartCorrections = motionStartCorrections.filter { keys.contains($0.key) }
            motionTracks = motionTracks.filter { keys.contains($0.key) }
            unsyncedMotions = unsyncedMotions.filter { keys.contains($0.key) }
            motions = adopted
            watchForWebKitCommits()
        }

        private func webKitAnimations() -> [WebKitAnimation] {
            var found: [WebKitAnimation] = []
            var visited = 0
            func add(_ animation: CAAnimation, group: CAAnimationGroup?, hidden: Bool) {
                let groupBegin = group?.beginTime ?? 0
                guard let property = animation as? CAPropertyAnimation, let keyPath = property.keyPath else { return }
                let raw: [Any]
                if let keyframes = animation as? CAKeyframeAnimation, let values = keyframes.values {
                    raw = values
                } else if let basic = animation as? CABasicAnimation, let from = basic.fromValue, let toValue = basic.toValue {
                    raw = [from, toValue]
                } else {
                    return
                }
                let values: [[Double]] = raw.compactMap { value in
                    if let numbers = value as? [NSNumber] { return numbers.map(\.doubleValue) }
                    if let number = value as? NSNumber { return [number.doubleValue] }
                    if let matrix = (value as? NSValue)?.caTransform3DValue { return [Double(matrix.m41), Double(matrix.m42)] }
                    return nil
                }
                guard values.count == raw.count else { return }
                func easing(_ function: CAMediaTimingFunction?) -> NIEasing {
                    guard let function else { return .linear }
                    var first: [Float] = [0, 0]
                    var last: [Float] = [0, 0]
                    function.getControlPoint(at: 1, values: &first)
                    function.getControlPoint(at: 2, values: &last)
                    return .cubicBezier(Double(first[0]), Double(first[1]), Double(last[0]), Double(last[1]))
                }
                let keyframes = animation as? CAKeyframeAnimation
                found.append(WebKitAnimation(
                    drawn: NIWebKitAnimation(
                        keyPath: keyPath,
                        values: values,
                        duration: animation.duration,
                        begin: animation.beginTime + groupBegin,
                        hidden: hidden,
                        offsets: keyframes?.keyTimes?.map(\.doubleValue),
                        easing: easing(animation.timingFunction),
                        segmentEasings: keyframes?.timingFunctions?.map { easing($0) },
                        interpolatesLinearly: keyframes == nil || keyframes?.calculationMode == .linear
                    ),
                    source: property,
                    group: group
                ))
            }
            func visit(_ layer: CALayer, hiddenAbove: Bool) {
                visited += 1
                guard visited <= 4000 else { return }
                let hidden = hiddenAbove || layer.isHidden
                if let keys = layer.animationKeys(), !keys.isEmpty {
                    addAnimations(of: layer, keys: keys, hidden: hidden)
                }
                layer.sublayers?.forEach { visit($0, hiddenAbove: hidden) }
            }
            func addAnimations(of layer: CALayer, keys: [String], hidden: Bool) {
                let drawsNothing = layer.contents == nil &&
                    (layer.backgroundColor?.alpha ?? 0) == 0 &&
                    (layer.sublayers?.isEmpty ?? true)
                let shown = !(hidden || drawsNothing)
                for key in keys {
                    guard let animation = layer.animation(forKey: key) else { continue }
                    if let group = animation as? CAAnimationGroup {
                        group.animations?.forEach { add($0, group: group, hidden: !shown) }
                    } else {
                        add(animation, group: nil, hidden: !shown)
                    }
                }
            }
            if let root = webView?.layer { visit(root, hiddenAbove: false) }
            return found
        }

        private func watchForWebKitCommits() {
            guard !unsyncedMotions.isEmpty, commitObserver == nil else { return }
            let observer = CFRunLoopObserverCreateWithHandler(
                kCFAllocatorDefault,
                CFRunLoopActivity.beforeWaiting.rawValue,
                true,
                1_999_999
            ) { [weak self] _, _ in
                self?.checkWebKitCommit()
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            commitObserver = observer
        }

        private func checkWebKitCommit() {
            let waiting = unsyncedMotions.count
            if waiting > 0 { syncMotions() }
            if unsyncedMotions.count != waiting {
                placeIslands(at: motionLink.map(nextFrameTime) ?? CACurrentMediaTime())
            }
            if unsyncedMotions.isEmpty, let observer = commitObserver {
                CFRunLoopObserverInvalidate(observer)
                commitObserver = nil
            }
        }

        private func nextFrameTime(_ link: CADisplayLink) -> CFTimeInterval {
            let now = CACurrentMediaTime()
            let duration = link.targetTimestamp - link.timestamp
            guard duration > 0 else { return now }
            let time = link.targetTimestamp
            guard time <= now else { return time }
            return time + (((now - time) / duration).rounded(.down) + 1) * duration
        }

        func syncMotions() {
            guard !unsyncedMotions.isEmpty, let origin = pageClock?.pageTime(nativeSeconds: 0) else { return }
            let now = CACurrentMediaTime()
            let drawn = webKitAnimations()
            let window = (-motionBeginTolerance * 1000) ... (maxMotionSyncDelay * 1000)
            for (id, motion) in motions {
                guard let since = unsyncedMotions[motion.key] else { continue }
                let matches = motion.animations.flatMap { animation in
                    drawn.filter { animation.isDrawn(by: $0.drawn) }.map {
                        (found: $0, channel: animation.channel, correction: $0.drawn.begin * 1000 + origin - animation.startTime)
                    }
                }
                .filter { window.contains($0.correction) }
                let waited = now - since >= maxMotionSyncDelay
                if let best = matches.min(by: { abs($0.correction) < abs($1.correction) }) {
                    if best.found.drawn.hidden, motion.runs(after: now * 1000 + origin) { continue }
                    motions[id]?.shiftStart(byMilliseconds: best.correction)
                    motionStartCorrections[motion.key] = best.correction
                    motionTracks[motion.key] = matches
                        .filter { $0.channel == .translate && !$0.found.drawn.hidden }
                        .min { abs($0.correction) < abs($1.correction) }
                        .flatMap { $0.found.track }
                } else if !waited {
                    continue
                } else {
                    motionStartCorrections[motion.key] = 0
                }
                unsyncedMotions[motion.key] = nil
                motions[id]?.held = false
            }
        }

        private func placeIslands(at frameTime: CFTimeInterval) {
            motionFrameTime = frameTime
            defer { motionFrameTime = nil }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for id in components.keys where layoutRects[id] != nil {
                updateHostGeometry(id: id, updateStaticGeometry: false)
            }
            updatePaneGeometry()
            CATransaction.commit()
            notifyVisibility()
        }

        fileprivate func motionFrame(_ link: CADisplayLink) {
            syncMotions()
            let frameTime = nextFrameTime(link)
            placeIslands(at: frameTime)
            if unsyncedMotions.isEmpty,
               let time = pageClock?.pageTime(nativeSeconds: frameTime),
               !motions.values.contains(where: { $0.runs(after: time) }) {
                stopMotion()
            }
        }
    }

    struct WebKitAnimation {
        let drawn: NIWebKitAnimation
        let source: CAPropertyAnimation
        let group: CAAnimationGroup?

        var track: CAKeyframeAnimation? {
            if let group,
               group.speed != 1 || group.timeOffset != 0 ||
               group.repeatCount != 0 && group.repeatCount != 1 || group.autoreverses {
                return nil
            }
            if let function = source.valueFunction?.name, function != .translate { return nil }
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
    }

    extension NativeIslandsContainer {
        func trackedMoves(_ path: [String], within base: [String] = []) -> [(key: String, sign: CGFloat)] {
            func tracked(_ id: String) -> String? {
                guard let motion = motions[id], !motion.held, motionTracks[motion.key] != nil else { return nil }
                return motion.key
            }
            return path.filter { !base.contains($0) }.compactMap { tracked($0) }.map { ($0, 1) } +
                base.filter { !path.contains($0) }.compactMap { tracked($0) }.map { ($0, -1) }
        }

        func applyMotion(_ moves: [(key: String, sign: CGFloat)], scale: CGFloat, to layer: CALayer) {
            var wanted: [String: (track: CAKeyframeAnimation, factor: CGFloat)] = [:]
            var rebase = CGPoint.zero
            let time = motionTime
            for move in moves {
                guard let track = motionTracks[move.key] else { continue }
                wanted["ni.move.\(move.key).\(move.sign).\(scale)"] = (track, move.sign * scale)
                let pos = time.flatMap { time in motions.values.first { $0.key == move.key }?.translation(at: time) } ?? .zero
                rebase.x -= pos.x * move.sign * scale
                rebase.y -= pos.y * move.sign * scale
            }
            for key in layer.animationKeys() ?? [] where key.hasPrefix("ni.move.") && wanted[key] == nil {
                layer.removeAnimation(forKey: key)
            }
            for (key, move) in wanted where layer.animation(forKey: key) == nil {
                guard let copy = move.track.copy() as? CAKeyframeAnimation else { continue }
                copy.values = move.track.values?.compactMap { ($0 as? NSValue)?.cgPointValue }.map {
                    NSValue(cgPoint: CGPoint(x: $0.x * move.factor, y: $0.y * move.factor))
                }
                copy.beginTime = layer.convertTime(move.track.beginTime, from: nil)
                layer.add(copy, forKey: key)
            }
            guard !wanted.isEmpty else {
                layer.removeAnimation(forKey: "ni.rebase")
                return
            }
            let constant = CABasicAnimation(keyPath: "position")
            constant.fromValue = NSValue(cgPoint: rebase)
            constant.toValue = NSValue(cgPoint: rebase)
            constant.duration = .greatestFiniteMagnitude
            constant.isAdditive = true
            constant.fillMode = .both
            constant.isRemovedOnCompletion = false
            layer.add(constant, forKey: "ni.rebase")
        }
    }

    private let maxMotionSyncDelay: CFTimeInterval = 0.3
    private let motionBeginTolerance: CFTimeInterval = 0.012

    private final class NativeIslandsMotionTarget {
        weak var container: NativeIslandsContainer?

        init(_ container: NativeIslandsContainer) {
            self.container = container
        }

        @objc func tick(_ link: CADisplayLink) {
            guard let container else {
                link.invalidate()
                return
            }
            container.motionFrame(link)
        }
    }
#endif
