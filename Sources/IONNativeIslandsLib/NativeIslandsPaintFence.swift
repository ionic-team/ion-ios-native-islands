#if canImport(UIKit)
    import QuartzCore
    import UIKit

    /// Runs bridge calls in the order they came, holding a fenced layout and every call after it until
    /// WebKit commits the page paint it belongs with. The page numbers its fences and writes the latest
    /// into the transform of a 1x1 sentinel element, which WebKit commits with that paint.
    final class NativeIslandsPaintFence {
        // Must match the web runtime's fence sentinel.
        static let sentinelY: CGFloat = 0.6875
        static let range = 1024
        static let maxWait: CFTimeInterval = 0.1

        private struct Call {
            let fence: Int?
            let since: CFTimeInterval
            let run: () -> Void
            let cancel: () -> Void
        }

        /// The layer WebKit draws the page in.
        weak var webKitLayer: CALayer?
        private var held: [Call] = []
        private var observer: NativeIslandsCommitObserver?
        private weak var sentinel: CALayer?
        private var sentinelObservation: NSKeyValueObservation?

        static func passed(committed: Int, fence: Int) -> Bool {
            ((committed - fence) % range + range) % range < range / 2
        }

        /// Runs `work` after earlier calls and, with a fence, after its web commit, at most `maxWait`
        /// later. `cancel` answers the call instead if `drop` comes first. Main thread only.
        func enqueue(fence: Int?, cancel: @escaping () -> Void, _ work: @escaping () -> Void) {
            held.append(Call(fence: fence, since: CACurrentMediaTime(), run: work, cancel: cancel))
            if fence != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxWait) { [weak self] in
                    self?.release()
                }
            }
            release()
        }

        func drop() {
            let dropped = held
            held.removeAll()
            dropped.forEach { $0.cancel() }
            sentinelObservation = nil
            sentinel = nil
            watchForCommits()
        }

        private func release() {
            let now = CACurrentMediaTime()
            while let call = held.first {
                // With no sentinel to read, the fence is not known to have passed.
                if let fence = call.fence,
                   !(committedFence(expecting: fence).map { Self.passed(committed: $0, fence: fence) } ?? false) {
                    guard now - call.since >= Self.maxWait else { break }
                }
                held.removeFirst()
                call.run()
            }
            watchForCommits()
        }

        /// Held calls are released when WebKit sets the sentinel's transform, inside the transaction that
        /// applies the web commit, since WebKit can commit it before the run loop's commit does.
        private func watchForCommits() {
            if !held.isEmpty, sentinelObservation == nil, let sentinel = currentSentinel() {
                sentinelObservation = sentinel.observe(\.transform) { [weak self] _, _ in
                    self?.release()
                }
            }
            if held.isEmpty {
                observer = nil
            } else if observer == nil {
                observer = NativeIslandsCommitObserver(order: NativeIslandsCommitObserver.paintFenceOrder) { [weak self] in
                    self?.release()
                }
            }
        }

        private func committedFence(expecting fence: Int) -> Int? {
            guard let sentinel = currentSentinel() else { return nil }
            let committed = Self.readFence(from: sentinel)
            if !Self.passed(committed: committed, fence: fence),
               let root = webKitLayer,
               let refreshed = Self.findSentinel(in: root),
               refreshed !== sentinel {
                sentinelObservation = nil
                self.sentinel = refreshed
                return Self.readFence(from: refreshed)
            }
            return committed
        }

        private static func readFence(from sentinel: CALayer) -> Int {
            Int((sentinel.transform.m41 * CGFloat(range)).rounded())
        }

        private func currentSentinel() -> CALayer? {
            guard let root = webKitLayer else {
                sentinelObservation = nil
                sentinel = nil
                return nil
            }
            if !Self.isDescendant(sentinel, of: root) {
                sentinelObservation = nil
                sentinel = Self.findSentinel(in: root)
            }
            return sentinel
        }

        private static func isDescendant(_ layer: CALayer?, of root: CALayer) -> Bool {
            var current = layer
            while let superlayer = current?.superlayer {
                if superlayer === root {
                    return true
                }
                current = superlayer
            }
            return false
        }

        /// The sentinel among WebKit's layers under `root`, within `CALayer.webKitScanLimit` layers.
        private static func findSentinel(in root: CALayer) -> CALayer? {
            var visited = 0
            func find(_ layer: CALayer) -> CALayer? {
                guard !layer.isIslandPlane else { return nil }
                visited += 1
                guard visited <= CALayer.webKitScanLimit else { return nil }
                if layer.bounds.size == CGSize(width: 1, height: 1), layer.transform.m42 == sentinelY {
                    return layer
                }
                // The sentinel paints over everything, so its layer is among the last: look there first.
                for sublayer in (layer.sublayers ?? []).reversed() {
                    if let found = find(sublayer) {
                        return found
                    }
                }
                return nil
            }
            return find(root)
        }
    }
#endif
