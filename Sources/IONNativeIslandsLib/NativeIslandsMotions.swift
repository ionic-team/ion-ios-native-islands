#if canImport(UIKit)
    import QuartzCore
    import UIKit

    /// How a motion, by key, is matched to the animation WebKit commits for it.
    private enum MotionSync {
        /// No WebKit animation has been matched yet, and the motion stays where the layout measured it.
        case held(since: CFTimeInterval)
        /// No WebKit animation has been matched yet, and the motion runs on the page clock as sent
        /// while a match can still correct it.
        case released(since: CFTimeInterval)
        /// WebKit runs the motion on Core Animation. Its start moved `correction` milliseconds to meet
        /// WebKit's committed one, and `track` is WebKit's translation, replayed on the island.
        case coreAnimated(correction: Double, track: CAKeyframeAnimation?)
        /// No match came in time, so the motion runs on the page clock as sent.
        case pageClock

        var waitingSince: CFTimeInterval? {
            switch self {
            case .held(let since), .released(let since): since
            case .coreAnimated, .pageClock: nil
            }
        }

        var correction: Double? {
            switch self {
            case .held, .released: nil
            case .coreAnimated(let correction, _): correction
            case .pageClock: 0
            }
        }

        var track: CAKeyframeAnimation? {
            if case .coreAnimated(_, let track) = self {
                return track
            }
            return nil
        }

        var isHeld: Bool {
            if case .held = self {
                return true
            }
            return false
        }

        var isCoreAnimated: Bool {
            if case .coreAnimated = self {
                return true
            }
            return false
        }
    }

    /// The motions of the last layout, matched to the animations WebKit commits for them and played
    /// every display frame while any runs.
    final class NativeIslandsMotions {
        private let pageClock: NIPageClock
        /// The layer WebKit draws the page in.
        weak var webKitLayer: CALayer?
        /// Places the islands for the display frame shown at a native time.
        var onFrame: ((CFTimeInterval) -> Void)?
        /// Where the scrollers that time scroll-driven motions are scrolled to.
        var scrolled: NIScrollOffsets?
        /// Keyed by id.
        private var motions: [String: NIMotion] = [:]
        /// Keyed by `NIMotion.key`.
        private var syncs: [String: MotionSync] = [:]
        private var link: CADisplayLink?
        private var commitObserver: NativeIslandsCommitObserver?
        /// The page time of the last frame `placing` was asked about.
        private var placedTime: Double?

        /// `pageClock` maps the page's time to native time; the controller samples it.
        init(pageClock: NIPageClock) {
            self.pageClock = pageClock
        }

        deinit {
            stop()
        }

        private var unsyncedCount: Int {
            syncs.values.filter { $0.waitingSince != nil }.count
        }

        private var heldKeys: Set<String> {
            Set(syncs.filter(\.value.isHeld).keys)
        }

        /// The motions for the frame shown at native time `nativeTime`, by default the next one.
        func frame(at nativeTime: CFTimeInterval? = nil) -> NIMotionFrame {
            frame(atPageTime: motions.isEmpty ? nil : pageClock.pageTime(
                nativeSeconds: nativeTime ?? link.map(Self.nextFrameTime) ?? CACurrentMediaTime()
            ))
        }

        /// The motions at page time `time`, held as they are now.
        func frame(atPageTime time: Double?) -> NIMotionFrame {
            NIMotionFrame(motions: motions, held: heldKeys, time: time, scrolled: scrolled)
        }

        /// Ids of the motions scrolling `scroller` (the document when nil) moves.
        func following(_ scroller: String?) -> Set<String> {
            Set(motions.compactMap { $0.value.followsScroll(scroller) ? $0.key : nil })
        }

        /// Takes the layout's motions. One already matched keeps its correction; a new one is held
        /// until WebKit's animation for it is found. Scrolling, not the clock, moves a scroll-driven
        /// one, so it waits for nothing.
        func adopt(_ incoming: [String: NIMotion]) {
            let now = CACurrentMediaTime()
            var adopted = incoming
            for (id, motion) in incoming {
                if motion.isScrollDriven {
                    syncs[motion.key] = .pageClock
                } else if let correction = syncs[motion.key]?.correction {
                    adopted[id]?.shiftStart(byMilliseconds: correction)
                } else if syncs[motion.key] == nil {
                    syncs[motion.key] = .held(since: now)
                }
            }
            let keys = Set(incoming.values.map(\.key))
            syncs = syncs.filter { keys.contains($0.key) }
            motions = adopted
            watchForWebKitCommits()
        }

        func reset() {
            motions.removeAll()
            syncs.removeAll()
            placedTime = nil
            stop()
        }

        /// Ids of the motions whose islands must be placed for `frame`: those still waiting for WebKit,
        /// and those running at the previous frame, so each is placed once more where it ends.
        func placing(_ frame: NIMotionFrame) -> Set<String> {
            let since = [placedTime, frame.time].compactMap { $0 }.min()
            placedTime = frame.time
            return Set(motions.compactMap { id, motion in
                syncs[motion.key]?.waitingSince != nil || since.map(motion.runs(after:)) ?? true ? id : nil
            })
        }

        func scheduleFrames() {
            guard
                let now = pageClock.pageTime(nativeSeconds: CACurrentMediaTime()),
                unsyncedCount > 0 || motions.values.contains(where: { $0.runs(after: now) })
            else {
                return
            }
            guard link == nil else { return }
            let link = CADisplayLink(target: NativeIslandsMotionTarget(self), selector: #selector(NativeIslandsMotionTarget.tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        private func stop() {
            link?.invalidate()
            link = nil
            commitObserver = nil
        }

        private func watchForWebKitCommits() {
            guard unsyncedCount > 0, commitObserver == nil else { return }
            commitObserver = NativeIslandsCommitObserver(order: NativeIslandsCommitObserver.motionSyncOrder) { [weak self] in
                self?.checkWebKitCommit()
            }
        }

        private func checkWebKitCommit() {
            let waiting = unsyncedCount
            if waiting > 0 {
                sync()
            }
            if unsyncedCount != waiting {
                onFrame?(link.map(Self.nextFrameTime) ?? CACurrentMediaTime())
            }
            if unsyncedCount == 0 {
                commitObserver = nil
            }
        }

        fileprivate func tick(_ link: CADisplayLink) {
            sync()
            let frameTime = Self.nextFrameTime(link)
            onFrame?(frameTime)
            if unsyncedCount == 0,
               let time = pageClock.pageTime(nativeSeconds: frameTime),
               !motions.values.contains(where: { $0.runs(after: time) }) {
                stop()
            }
        }

        /// How long the display link's frames last, once it has drawn one.
        private var frameDuration: CFTimeInterval? {
            link.map { $0.targetTimestamp - $0.timestamp }.flatMap { $0 > 0 ? $0 : nil }
        }

        /// The display frame the link's callback draws for: its target, or the next one when the
        /// callback runs after the target began.
        private static func nextFrameTime(_ link: CADisplayLink) -> CFTimeInterval {
            let now = CACurrentMediaTime()
            let duration = link.targetTimestamp - link.timestamp
            guard duration > 0 else { return now }
            let time = link.targetTimestamp
            guard time <= now else { return time }
            return time + (((now - time) / duration).rounded(.down) + 1) * duration
        }

        /// Matches each waiting motion to the animation WebKit committed for it, moving its start to
        /// WebKit's. A match can come late or never, so after a frame a waiting motion runs on the page
        /// clock rather than standing still, and after `maxSyncDelay` it stops waiting.
        private func sync() {
            guard unsyncedCount > 0, let origin = pageClock.pageTime(nativeSeconds: 0) else { return }
            let now = CACurrentMediaTime()
            let drawn = webKitLayer.map(WebKitAnimation.committed(under:)) ?? []
            let window = (-beginTolerance * 1000)...(maxSyncDelay * 1000)
            for (id, motion) in motions {
                guard let sync = syncs[motion.key], let since = sync.waitingSince else { continue }
                let matches = motion.animations.flatMap { animation in
                    drawn.filter { animation.isDrawn(by: $0.drawn) }.map {
                        (found: $0, channel: animation.channel, correction: $0.drawn.begin * 1000 + origin - animation.startTime)
                    }
                }
                .filter { window.contains($0.correction) }
                guard let best = matches.min(by: { abs($0.correction) < abs($1.correction) }) else {
                    if now - since >= maxSyncDelay {
                        syncs[motion.key] = .pageClock
                    } else if sync.isHeld, let frame = frameDuration, now - since >= frame {
                        syncs[motion.key] = .released(since: since)
                    }
                    continue
                }
                if best.found.drawn.hidden, motion.runs(after: now * 1000 + origin) {
                    continue
                }
                motions[id]?.shiftStart(byMilliseconds: best.correction)
                // A motion that scales is placed frame by frame: a track carries only its move.
                let track: CAKeyframeAnimation? = motion.scaleAnimation != nil ? nil : matches
                    .filter { $0.channel == .translate && !$0.found.drawn.hidden }
                    .min { abs($0.correction) < abs($1.correction) }
                    .flatMap(\.found.track) ?? motions[id].flatMap(pageClockTrack)
                syncs[motion.key] = .coreAnimated(correction: best.correction, track: track)
            }
        }

        // Core Animation tracks that keep islands moving and fading with the page on the render server,
        // for motions WebKit runs there too, so they keep pace while the main thread is busy.

        private static let movePrefix = "ni.move."
        private static let rebaseKey = "ni.rebase"
        private static let fadePrefix = "ni.fade."

        /// Gives `layer` the track of each motion on `path` WebKit runs on Core Animation, scaled to the
        /// layer's units, and a constant that cancels where those motions put the layer's model in
        /// `frame`. The model can then be written at any time without moving pixels.
        func applyMoves(_ path: [String], scale: CGFloat, to layer: CALayer, in frame: NIMotionFrame) {
            var wanted: [String: (track: CAKeyframeAnimation, factor: CGFloat)] = [:]
            var rebase = CGPoint.zero
            for id in path {
                guard let motion = motions[id], let track = syncs[motion.key]?.track else { continue }
                wanted["\(Self.movePrefix)\(motion.key).\(scale)"] = (track, scale)
                let position = frame.time.flatMap(motion.translation) ?? .zero
                rebase.x -= position.x * scale
                rebase.y -= position.y * scale
            }
            for key in layer.animationKeys() ?? [] where key.hasPrefix(Self.movePrefix) && wanted[key] == nil {
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
                layer.removeAnimation(forKey: Self.rebaseKey)
                return
            }
            let constant = CABasicAnimation(keyPath: "position")
            constant.fromValue = NSValue(cgPoint: rebase)
            constant.toValue = NSValue(cgPoint: rebase)
            constant.duration = .greatestFiniteMagnitude
            constant.isAdditive = true
            constant.fillMode = .both
            constant.isRemovedOnCompletion = false
            layer.add(constant, forKey: Self.rebaseKey)
        }

        /// Runs the fades on `path` as one Core Animation track on the island's alpha, kept while the
        /// same fades run, when WebKit runs every one of them on Core Animation too.
        func applyFade(_ path: [String], opacity: CGFloat, to layer: CALayer, in frame: NIMotionFrame) {
            let fades = path.compactMap { motions[$0] }.filter { $0.fadeAnimation != nil }
            let running = fades.filter { !frame.held.contains($0.key) }
            let coreAnimated = !running.isEmpty && running.allSatisfy { syncs[$0.key]?.isCoreAnimated == true }
            let name = !coreAnimated ? nil : "\(Self.fadePrefix)\(opacity)." + fades
                .map { "\($0.key)\(frame.held.contains($0.key) ? "h" : ""):\($0.fadeAnimation?.startTime ?? 0)" }
                .joined(separator: "|")
            for key in layer.animationKeys() ?? [] where key.hasPrefix(Self.fadePrefix) && key != name {
                layer.removeAnimation(forKey: key)
            }
            guard let name, layer.animation(forKey: name) == nil else { return }
            let spans = running.compactMap { $0.fadeAnimation?.pageSpan() }
            guard
                spans.count == running.count, !spans.contains(where: \.repeats),
                let begin = spans.map(\.begin).min(),
                let end = spans.map({ $0.begin + $0.duration }).max(),
                let nativeBegin = pageClock.nativeSeconds(pageTime: begin)
            else {
                return
            }
            let count = NIMotionSamples.count(over: end - begin)
            let track = CAKeyframeAnimation(keyPath: "opacity")
            track.values = (0..<count).map { index in
                let time = begin + (end - begin) * Double(index) / Double(count - 1)
                return Double(opacity) * fades.reduce(1.0) { $0 * (frame.opacity(of: $1, at: time) ?? 1) }
            }
            track.calculationMode = .linear
            track.duration = (end - begin) / 1000
            track.beginTime = layer.convertTime(nativeBegin, from: nil)
            track.fillMode = .both
            track.isRemovedOnCompletion = false
            layer.add(track, forKey: name)
        }

        /// The motion's translation as a Core Animation track, for one WebKit runs on Core Animation
        /// with no track to copy, so the island keeps moving with the page while the main thread is busy.
        private func pageClockTrack(for motion: NIMotion) -> CAKeyframeAnimation? {
            guard
                let samples = motion.translationAnimation?.samples(),
                let begin = pageClock.nativeSeconds(pageTime: samples.span.begin)
            else {
                return nil
            }
            let track = CAKeyframeAnimation(keyPath: "position")
            track.values = samples.values.map { NSValue(cgPoint: CGPoint(x: $0[0], y: $0[1])) }
            track.calculationMode = .linear
            track.duration = samples.span.duration / 1000
            track.beginTime = begin
            track.repeatCount = samples.span.repeats ? .infinity : 0
            track.isAdditive = true
            track.fillMode = .both
            track.isRemovedOnCompletion = false
            return track
        }

        /// When the motions moving `regions` alone move them, WebKit runs every one on Core Animation
        /// and all of them end: their keys with the corrections that started them, and when they run
        /// from and to. `path` is the island's own motion path, which must not be running.
        func cutoutMotion(of regions: [IslandRegion], under path: [String], in frame: NIMotionFrame) -> NICutoutMotion? {
            guard let time = frame.time else { return nil }
            var seen = Set<String>()
            let moving = regions.flatMap(\.motionPath).filter { seen.insert($0).inserted }.compactMap(frame.running)
            let ends = moving.map(\.pageEnd)
            guard
                !moving.isEmpty,
                path.allSatisfy({ frame.running($0) == nil }),
                moving.allSatisfy({ syncs[$0.key]?.isCoreAnimated == true }),
                !ends.contains(where: { $0 == nil }),
                let end = ends.compactMap({ $0 }).max(),
                end > time
            else { return nil }
            let key = moving.map { "\($0.key)+\(syncs[$0.key]?.correction ?? 0)" }.sorted().joined(separator: ",")
            return NICutoutMotion(key: key, time: time, end: end, begin: pageClock.nativeSeconds(pageTime: time))
        }
    }

    /// How long a motion waits for WebKit's animation, and how late WebKit's start may be and still match.
    private let maxSyncDelay: CFTimeInterval = 0.3
    /// How early WebKit's start may be and still match: under one 60 Hz frame.
    private let beginTolerance: CFTimeInterval = 0.012

    private final class NativeIslandsMotionTarget {
        weak var motions: NativeIslandsMotions?

        init(_ motions: NativeIslandsMotions) {
            self.motions = motions
        }

        @objc
        func tick(_ link: CADisplayLink) {
            guard let motions else {
                link.invalidate()
                return
            }
            motions.tick(link)
        }
    }
#endif
