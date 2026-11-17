#if canImport(UIKit)
    import UIKit

    /// The Core Animation motions moving an island's cutouts, by `key`, from page time `time`, which
    /// is native time `begin`, to `end`.
    struct NICutoutMotion {
        var key: String
        let time: Double
        let end: Double
        let begin: CFTimeInterval?
    }

    /// A cut path sampled along the motions that move it, as Core Animation plays it.
    private struct NICutoutTrack {
        let key: String
        let begin: Double
        let interval: Double
        let samples: [[IslandRect]]

        /// Whether the track draws `cutouts` at page time `time`, to within a point.
        func matches(_ cutouts: [IslandRect], at time: Double) -> Bool {
            guard interval > 0, !samples.isEmpty else { return false }
            let position = min(max((time - begin) / interval, 0), Double(samples.count - 1))
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, samples.count - 1)
            let fraction = CGFloat(position - Double(lower))
            let earlier = samples[lower]
            let later = samples[upper]
            guard earlier.count == cutouts.count, later.count == cutouts.count else { return false }
            let near = { (start: CGFloat, end: CGFloat, value: CGFloat) in abs(start + (end - start) * fraction - value) <= 1 }
            return cutouts.indices.allSatisfy { index in
                let start = earlier[index]
                let end = later[index]
                let cut = cutouts[index]
                return near(start.x, end.x, cut.x) && near(start.y, end.y, cut.y)
                    && near(start.width, end.width, cut.width) && near(start.height, end.height, cut.height)
            }
        }
    }

    /// One island's host view, square to the screen over what the page draws, and the clips, cuts
    /// and tints applied to it there. The island's own view sits in its body, which the page's
    /// transform draws into the host. Moving the host to another id (a portal) moves all of it.
    final class NativeIslandsHost {
        private struct CutoutMask {
            var bounds: CGRect
            var cutouts: [IslandRect]
            var layer: CAShapeLayer
        }

        private struct ClipMaskInput: Equatable {
            var bounds: CGRect
            var clip: IslandRect
        }

        private static let cutoutTrackKey = "ni.cutouts"
        /// A portal host moved or resized by less than this, in points, snaps instead of morphing.
        private static let morphThreshold: CGFloat = 4
        /// A short, nearly critically damped spring, so the morph settles without visible bounce.
        private static let morphDuration: TimeInterval = 0.28
        private static let morphDamping: CGFloat = 0.88
        /// Each cutout sample builds a cut path, so a cutout track holds fewer samples (two seconds).
        private static let cutoutSampleLimit = 240

        let view: UIView
        /// What is cut and tinted: the host's whole box, inside its clips.
        let content: UIView
        /// The island's own box, holding its view.
        let body: UIView
        /// Last viewport visibility reported for this island.
        var visible = false
        /// Where the host showed before it was handed to another id, which it morphs from next.
        private var portalOrigin: (frame: CGRect, radius: CGFloat)?

        /// Where the host shows and how round, unless it is hidden or too small to morph from.
        private var shownShape: (frame: CGRect, radius: CGFloat)? {
            guard !view.isHidden, view.bounds.width > 1, view.bounds.height > 1 else { return nil }
            return (frame: view.frame, radius: body.layer.cornerRadius)
        }

        /// The cut track playing on the cutout mask.
        private var cutoutTrack: NICutoutTrack?
        /// The last cut track that would not have drawn the cutouts where they were.
        private var refusedCutoutTrack: String?
        private var clipWrappers: [UIView] = []
        private var clipMasks: [CAShapeLayer] = []
        private var clipMaskInputs: [ClipMaskInput] = []
        /// Rounds the body when the layer cannot round its corners alike.
        private let bodyMask = CAShapeLayer()
        private var cutoutMask: CutoutMask?
        private var tintLayer: CALayer?

        /// A hidden host for `island`.
        init(island: UIView) {
            view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            view.isHidden = true
            content = UIView(frame: view.bounds)
            content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            body = UIView()
            body.layer.anchorPoint = .zero
            body.layer.position = .zero
            body.bounds = content.bounds
            view.addSubview(content)
            content.addSubview(body)
            hold(island)
        }

        /// Puts `island` in the body, in place of the view it held.
        func hold(_ island: UIView) {
            body.subviews.forEach { $0.removeFromSuperview() }
            island.frame = body.bounds
            island.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            body.addSubview(island)
        }

        /// Draws the body as `shape` says, in the host's points.
        func draw(_ shape: NIIslandBody) {
            let bounds = CGRect(origin: .zero, size: shape.size)
            body.layer.transform = Self.layerTransform(shape)
            body.bounds = bounds
            // Autoresizing rounds to whole pixels; a hairline island keeps its fractional size.
            body.subviews.forEach { $0.frame = bounds }
            let layer = body.layer
            layer.masksToBounds = true
            if let radius = shape.radii.sharedRadius(in: shape.size) {
                layer.cornerRadius = radius
                layer.maskedCorners = shape.radii.maskedCorners
                layer.mask = nil
                return
            }
            layer.cornerRadius = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bodyMask.frame = bounds
            bodyMask.path = shape.radii.path(in: bounds)
            layer.mask = bodyMask
            CATransaction.commit()
        }

        /// `shape`'s drawing as a Core Animation transform: its homography, for a layer that moves
        /// points as rows.
        private static func layerTransform(_ shape: NIIslandBody) -> CATransform3D {
            let affine = shape.transform
            var matrix = CATransform3DIdentity
            matrix.m11 = affine.a
            matrix.m12 = affine.b
            matrix.m21 = affine.c
            matrix.m22 = affine.d
            matrix.m41 = affine.tx
            matrix.m42 = affine.ty
            matrix.m14 = shape.perspective.x
            matrix.m24 = shape.perspective.y
            return matrix
        }

        func applyTints(_ tints: [(rect: IslandRect, color: CGColor)]) {
            guard !tints.isEmpty || tintLayer != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            guard !tints.isEmpty else {
                tintLayer?.removeFromSuperlayer()
                tintLayer = nil
                return
            }
            let container = tintLayer ?? {
                let layer = CALayer()
                layer.masksToBounds = true
                layer.compositingFilter = "sourceAtop"
                return layer
            }()
            tintLayer = container
            if container.superlayer !== content.layer || content.layer.sublayers?.last !== container {
                content.layer.addSublayer(container)
            }
            container.frame = content.bounds
            var shapes = container.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
            while shapes.count < tints.count {
                let shape = CAShapeLayer()
                container.addSublayer(shape)
                shapes.append(shape)
            }
            for (index, shape) in shapes.enumerated() {
                guard tints.indices.contains(index) else {
                    shape.removeFromSuperlayer()
                    continue
                }
                shape.path = tints[index].rect.cornerRadii.path(in: tints[index].rect.cgRect)
                shape.fillColor = tints[index].color
            }
        }

        /// The host goes to another id, whose first showing morphs from where the host shows here.
        func handOver() {
            if let shape = shownShape {
                portalOrigin = shape
            }
        }

        /// Runs `show`, which places the host and returns whether it shows. A host in a portal that
        /// `fixed` to the screen then springs from where it showed before (here or under the id it
        /// was handed from) when it moved or resized by more than `morphThreshold`.
        func show(inPortal: Bool, fixed: Bool, _ show: () -> Bool) {
            let origin = portalOrigin ?? (inPortal ? shownShape : nil)
            portalOrigin = nil
            guard show(), let origin, inPortal, fixed else { return }
            let targetFrame = view.frame
            let targetRadius = body.layer.cornerRadius
            // A body the page draws turned or scaled keeps its own box; one drawn square fills the host.
            let fills = CATransform3DIsIdentity(body.layer.transform)
            let delta = max(
                abs(origin.frame.minX - targetFrame.minX),
                abs(origin.frame.minY - targetFrame.minY),
                abs(origin.frame.width - targetFrame.width),
                abs(origin.frame.height - targetFrame.height)
            )
            guard delta > Self.morphThreshold, view.window != nil else { return }
            let view = view
            let content = content
            let body = body
            UIView.performWithoutAnimation {
                view.frame = origin.frame
                content.frame = view.bounds
                if fills { body.bounds = view.bounds }
                body.layer.cornerRadius = origin.radius
            }
            UIView.animate(
                withDuration: Self.morphDuration,
                delay: 0,
                usingSpringWithDamping: Self.morphDamping,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                view.frame = targetFrame
                content.frame = view.bounds
                if fills { body.bounds = view.bounds }
                body.layer.cornerRadius = targetRadius
            }
        }

        /// Cuts `cutouts` out of the island. While `moving` names the Core Animation motions that move
        /// them, they play as one Core Animation track sampled along those motions by `sample` (page
        /// time to cutouts), so the holes move on the frame WebKit's own Core Animation draws. A track
        /// that would not draw `cutouts` is not tried again for the same key.
        func cut(_ cutouts: [IslandRect], moving: NICutoutMotion?, sample: (Double) -> [IslandRect]) {
            if !playsCutoutTrack(cutouts, moving: moving, sample: sample) {
                applyCutouts(cutouts)
            }
        }

        private func playsCutoutTrack(_ now: [IslandRect], moving: NICutoutMotion?, sample: (Double) -> [IslandRect]) -> Bool {
            guard let moving else {
                stopCutoutTrack()
                return false
            }
            if let track = cutoutTrack, track.key == moving.key {
                guard track.matches(now, at: moving.time) else {
                    stopCutoutTrack(refusing: moving.key)
                    return false
                }
                return true
            }
            guard refusedCutoutTrack != moving.key, let begin = moving.begin else {
                stopCutoutTrack()
                return false
            }
            guard
                let sampled = sampleCutouts(moving, sample: sample),
                sampled.track.matches(now, at: moving.time)
            else {
                stopCutoutTrack(refusing: moving.key)
                return false
            }
            playCutoutTrack(sampled.track, paths: sampled.paths, begin: begin, duration: (moving.end - moving.time) / 1000)
            return true
        }

        /// The cutouts sampled evenly along `moving`, with the cut path of each sample, or nil when
        /// the path changes shape on the way.
        private func sampleCutouts(
            _ moving: NICutoutMotion,
            sample: (Double) -> [IslandRect]
        )
            -> (track: NICutoutTrack, paths: [CGPath])? {
            let begin = moving.time
            let count = NIMotionSamples.count(over: moving.end - begin, limit: Self.cutoutSampleLimit)
            let interval = (moving.end - begin) / Double(count - 1)
            let samples = (0..<count).map { index in sample(begin + interval * Double(index)) }
            let paths = samples.map { cutouts in
                NIVisualCutoutGeometry.visiblePath(
                    bounds: content.bounds,
                    cutouts: cutouts.map { (rect: $0.cgRect, radii: $0.cornerRadii) }
                )
            }
            // Core Animation moves between paths of the same shape; one that gains or loses a part on
            // the way (a hole leaving the island) is set frame by frame.
            let shape = paths.first.map(Self.elementCount)
            guard paths.allSatisfy({ Self.elementCount($0) == shape }) else { return nil }
            return (NICutoutTrack(key: moving.key, begin: begin, interval: interval, samples: samples), paths)
        }

        private static func elementCount(_ path: CGPath) -> Int {
            var count = 0
            path.applyWithBlock { _ in count += 1 }
            return count
        }

        private func applyCutouts(_ cutouts: [IslandRect]) {
            guard !cutouts.isEmpty else {
                content.layer.mask = nil
                cutoutMask = nil
                return
            }

            stopCutoutAnimation()
            let mask = content.layer.mask as? CAShapeLayer ?? CAShapeLayer()
            if let cached = cutoutMask,
               cached.bounds == content.bounds,
               cached.cutouts == cutouts,
               cached.layer === mask,
               mask.path != nil {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.frame = content.bounds
            mask.masksToBounds = true
            mask.path = NIVisualCutoutGeometry.visiblePath(
                bounds: content.bounds,
                cutouts: cutouts.map { (rect: $0.cgRect, radii: $0.cornerRadii) }
            )
            mask.fillRule = .evenOdd
            content.layer.mask = mask
            cutoutMask = CutoutMask(bounds: content.bounds, cutouts: cutouts, layer: mask)
            CATransaction.commit()
        }

        /// Stops the cut track, if one plays. A `refusing` key is not played until another is refused.
        private func stopCutoutTrack(refusing key: String? = nil) {
            if let key {
                refusedCutoutTrack = key
            }
            cutoutTrack = nil
            stopCutoutAnimation()
        }

        /// Plays `track` on Core Animation from its `paths`, the cut mask sampled evenly over `duration`
        /// from `begin` in media time, resting at the last.
        private func playCutoutTrack(_ track: NICutoutTrack, paths: [CGPath], begin: CFTimeInterval, duration: CFTimeInterval) {
            guard let last = paths.last else { return }
            cutoutTrack = track
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let mask = content.layer.mask as? CAShapeLayer ?? CAShapeLayer()
            mask.frame = content.bounds
            mask.masksToBounds = true
            mask.fillRule = .evenOdd
            mask.path = last
            let track = CAKeyframeAnimation(keyPath: "path")
            track.values = paths
            track.calculationMode = .linear
            track.duration = duration
            track.beginTime = mask.convertTime(begin, from: nil)
            track.fillMode = .both
            track.isRemovedOnCompletion = false
            mask.add(track, forKey: Self.cutoutTrackKey)
            content.layer.mask = mask
            // The path under the track is not what applyCutouts last set, so the next one is set whole.
            cutoutMask = nil
            CATransaction.commit()
        }

        private func stopCutoutAnimation() {
            guard let mask = content.layer.mask, mask.animation(forKey: Self.cutoutTrackKey) != nil else { return }
            mask.removeAnimation(forKey: Self.cutoutTrackKey)
        }

        /// Clips the island to each shape in `clips` (its scrollports and its ancestors' clips), in
        /// the host's points, one wrapper view per shape so rounded shapes intersect.
        func applyClips(_ clips: [IslandRect]) {
            if clipWrappers.count != clips.count {
                let previous = clipWrappers
                clipWrappers = clips.map { _ in
                    let wrapper = UIView(frame: view.bounds)
                    wrapper.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    return wrapper
                }
                var parent = view
                for wrapper in clipWrappers {
                    parent.addSubview(wrapper)
                    parent = wrapper
                }
                parent.addSubview(content)
                previous.forEach { $0.removeFromSuperview() }
                clipMasks = clips.map { _ in CAShapeLayer() }
                clipMaskInputs = []
            }
            content.frame = view.bounds
            guard !clips.isEmpty else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for wrapper in clipWrappers {
                wrapper.frame = view.bounds
            }
            let inputs = clips.indices.map { index in
                ClipMaskInput(bounds: clipWrappers[index].bounds, clip: clips[index])
            }
            let previousInputs = clipMaskInputs
            for (index, clip) in clips.enumerated() {
                let wrapper = clipWrappers[index]
                let mask = clipMasks[index]
                if clip.containsBox(wrapper.bounds.size) {
                    wrapper.layer.mask = nil
                    continue
                }
                mask.frame = wrapper.bounds
                if previousInputs.count != inputs.count || previousInputs[index] != inputs[index] || mask.path == nil {
                    mask.path = clip.cornerRadii.path(in: clip.cgRect)
                }
                wrapper.layer.mask = mask
            }
            clipMaskInputs = inputs
            CATransaction.commit()
        }
    }
#endif
