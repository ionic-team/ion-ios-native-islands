import CoreGraphics

/// The page's motions at one page time, as the islands, regions and scrollers on them are drawn.
/// A held motion has not started for native yet and stays where the layout measured it.
struct NIMotionFrame {
    let motions: [String: NIMotion]
    /// Keys of the held motions.
    let held: Set<String>
    /// Page milliseconds, or nil when nothing moves or the page clock is not known yet.
    let time: Double?

    /// The motion `id` names with the time it is drawn at, unless it is held or nothing moves.
    private func live(_ id: String) -> (motion: NIMotion, time: Double)? {
        guard let time, let motion = motions[id], !held.contains(motion.key) else { return nil }
        return (motion, time)
    }

    /// The motion `id` names when it is live and still running.
    func running(_ id: String) -> NIMotion? {
        guard let (motion, time) = live(id), motion.runs(after: time) else { return nil }
        return motion
    }

    /// `rect` as the motions in `path` (outermost first) draw it. Inner motions apply first, each
    /// scaling about its origin (from `rect`'s corner) and then moving.
    func moved(_ rect: IslandRect, path: [String], origins: [CGPoint] = []) -> IslandRect {
        var moved = rect
        var radius: CGFloat = 1
        for index in path.indices.reversed() {
            guard let (motion, time) = live(path[index]) else { continue }
            if index < origins.count, motion.scaleAnimation != nil {
                let scale = motion.scale(at: time)
                let origin = CGPoint(x: rect.x + origins[index].x, y: rect.y + origins[index].y)
                moved.x = origin.x + scale.width * (moved.x - origin.x)
                moved.y = origin.y + scale.height * (moved.y - origin.y)
                moved.width *= scale.width
                moved.height *= scale.height
                radius *= min(scale.width, scale.height)
            }
            let offset = motion.offset(at: time)
            moved.x += offset.x
            moved.y += offset.y
        }
        if radius != 1 {
            moved.cornerRadii = moved.cornerRadii.scaled(by: radius)
        }
        return moved
    }

    /// How much the motions in `path` scale what travels with them, relative to the plan.
    func scale(_ path: [String]) -> CGSize {
        path.reduce(CGSize(width: 1, height: 1)) { scale, id in
            guard let (motion, time) = live(id), motion.scaleAnimation != nil else { return scale }
            let next = motion.scale(at: time)
            return CGSize(width: scale.width * next.width, height: scale.height * next.height)
        }
    }

    func opacity(_ path: [String]) -> Double {
        guard let time else { return 1 }
        return path.reduce(1.0) { product, id in
            product * (motions[id].flatMap { opacity(of: $0, at: time) } ?? 1)
        }
    }

    func opacity(of motion: NIMotion, at time: Double) -> Double? {
        held.contains(motion.key) ? motion.measuredOpacity : motion.opacity(at: time)
    }

    /// Paint faded below half its opacity no longer cuts or covers an island.
    func fadedOut(_ path: [String]) -> Bool {
        opacity(path) < 0.5
    }
}
