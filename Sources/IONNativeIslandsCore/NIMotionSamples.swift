import Foundation

/// When, in page time, an animation draws its first frame and how long it draws: to its last
/// frame, or one cycle of an endless one.
struct NIMotionSpan {
    let begin: Double
    let duration: Double
    let repeats: Bool
}

/// An animation's values sampled evenly over its span, so Core Animation can run it.
struct NIMotionSamples {
    let span: NIMotionSpan
    let values: [[Double]]

    /// Samples per second in the Core Animation tracks native builds from page motions.
    static let perSecond = 120.0
    /// Samples in one track at most (five seconds); a longer track is sampled more coarsely.
    static let limit = 600

    /// How many evenly spaced samples cover `milliseconds`, both ends included.
    static func count(over milliseconds: Double, limit: Int = limit) -> Int {
        min(limit, max(2, Int((milliseconds / (1000 / perSecond)).rounded(.up)) + 1))
    }
}

extension NIMotionAnimation {
    func pageSpan() -> NIMotionSpan? {
        guard playbackRate.isFinite, playbackRate != 0, duration > 0, keyframes.count >= 2 else { return nil }
        let repeats = iterations.isInfinite
        let begin: Double
        let length: Double
        if repeats {
            guard playbackRate > 0 else { return nil }
            begin = startTime + delay / playbackRate
            length = duration * (direction == .alternate || direction == .alternateReverse ? 2 : 1) / playbackRate
        } else {
            let end = (delay + duration * iterations) / playbackRate
            begin = startTime + min(0, end)
            length = abs(end)
        }
        guard length > 0, length.isFinite else { return nil }
        return NIMotionSpan(begin: begin, duration: length, repeats: repeats)
    }

    /// A cycle's samples end just short of its last instant, where it wraps.
    func samples() -> NIMotionSamples? {
        guard let span = pageSpan() else { return nil }
        let count = NIMotionSamples.count(over: span.duration)
        let values = (0 ..< count).map { index in
            let fraction = Double(index) / Double(count - 1)
            let offset = span.repeats && index == count - 1 ? span.duration - 1e-6 : span.duration * fraction
            return value(at: localTime(span.begin + offset))
        }
        return NIMotionSamples(span: span, values: values)
    }
}

extension NIMotion {
    /// The page time its last animation draws its last frame, or nil for one that never ends.
    var pageEnd: Double? {
        let spans = animations.map { $0.pageSpan() }
        guard !spans.isEmpty, spans.allSatisfy({ $0.map { !$0.repeats } ?? false }) else { return nil }
        return spans.compactMap { $0.map { $0.begin + $0.duration } }.max()
    }
}
