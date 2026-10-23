#if canImport(UIKit)
    import QuartzCore
    import UIKit

    extension NativeIslandsController {
        static let fenceSentinelY: CGFloat = 0.6875
        static let fenceRange = 1024
        static let maxFenceWait: CFTimeInterval = 0.1

        static func fencePassed(committed: Int, fence: Int) -> Bool {
            ((committed - fence) % fenceRange + fenceRange) % fenceRange < fenceRange / 2
        }

        func inOrder(fence: Int? = nil, _ work: @escaping () -> Void) {
            onMain {
                self.heldCalls.append(HeldCall(fence: fence, since: CACurrentMediaTime(), run: work))
                if fence != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxFenceWait) { [weak self] in
                        self?.releaseHeldCalls()
                    }
                }
                self.releaseHeldCalls()
            }
        }

        func releaseHeldCalls() {
            let committed = committedFence()
            let now = CACurrentMediaTime()
            while let call = heldCalls.first {
                if let fence = call.fence, let committed,
                   !Self.fencePassed(committed: committed, fence: fence),
                   now - call.since < Self.maxFenceWait {
                    break
                }
                heldCalls.removeFirst()
                call.run()
            }
            watchForFenceCommits()
        }

        func dropHeldCalls() {
            heldCalls.removeAll()
            watchForFenceCommits()
        }

        private func watchForFenceCommits() {
            if heldCalls.isEmpty {
                if let observer = fenceObserver {
                    CFRunLoopObserverInvalidate(observer)
                    fenceObserver = nil
                }
                return
            }
            guard fenceObserver == nil else { return }
            let observer = CFRunLoopObserverCreateWithHandler(
                kCFAllocatorDefault,
                CFRunLoopActivity.beforeWaiting.rawValue,
                true,
                1_999_998
            ) { [weak self] _, _ in
                self?.releaseHeldCalls()
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            fenceObserver = observer
        }

        private func committedFence() -> Int? {
            if fenceSentinel?.superlayer == nil {
                fenceSentinel = webView.flatMap { findFenceSentinel(in: $0.layer) }
            }
            guard let sentinel = fenceSentinel else { return nil }
            return Int((sentinel.transform.m41 * CGFloat(Self.fenceRange)).rounded())
        }

        private func findFenceSentinel(in root: CALayer) -> CALayer? {
            var visited = 0
            func find(_ layer: CALayer) -> CALayer? {
                visited += 1
                guard visited <= 4000 else { return nil }
                if layer.bounds.size == CGSize(width: 1, height: 1), layer.transform.m42 == Self.fenceSentinelY {
                    return layer
                }
                for sublayer in layer.sublayers ?? [] {
                    if let found = find(sublayer) { return found }
                }
                return nil
            }
            return find(root)
        }
    }

    struct HeldCall {
        let fence: Int?
        let since: CFTimeInterval
        let run: () -> Void
    }
#endif
