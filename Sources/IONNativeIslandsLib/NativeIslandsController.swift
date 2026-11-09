#if canImport(UIKit)
    import UIKit
    import WebKit

    /// Native Islands for one WebView, driven by the bridge operations as a carrier receives them:
    /// each payload is checked here, so carriers only pass it on and answer with what comes back.
    public final class NativeIslandsController {
        private static let sessionCapabilities: [String: Any] = [
            "paneColor": true,
            "motionStartsAtCommit": true,
            "paintFence": true,
            "motionScale": true,
        ]

        private let pageClock = NIPageClock()
        private let container: NativeIslandsContainer
        private let launch = NativeIslandsLaunchFrame()
        private let islands: NativeIslandsLifecycle
        private let paintFence = NativeIslandsPaintFence()
        private weak var webView: WKWebView? {
            didSet { paintFence.webKitLayer = webView?.layer }
        }

        private var containerInstalled = false
        /// A layout placed again on each pass WebKit can commit in, while a scroll view it needs is
        /// missing, and how to end it: `true` when a reset cancels it, `false` when a newer layout
        /// supersedes it.
        private var retry: (observer: NativeIslandsCommitObserver, end: (_ cancelled: Bool) -> Void)?

        /// How many main run-loop passes a layout waits for a scroll view WebKit makes after the
        /// paint that shows its scroller.
        private static let scrollViewWaitPasses = 8

        /// Whether the islands a page shows first are cached and shown at the next launch before the
        /// page lays out.
        public var launchCacheEnabled: Bool {
            get { launch.enabled }
            set { launch.enabled = newValue }
        }

        public var launchCacheStore: UserDefaults {
            get { launch.store }
            set { launch.store = newValue }
        }

        public private(set) var lastLayoutAppliedAt: Double?

        public init(
            events: @escaping (_ event: String, _ payload: [String: Any]) -> Void
        ) {
            self.container = NativeIslandsContainer(pageClock: pageClock)
            self.islands = NativeIslandsLifecycle(container: container, launch: launch, events: events)
            islands.installContainer = { [weak self] in
                self?.ensureContainer(webView: nil)
            }
        }

        public func ensureContainer(webView: WKWebView?) {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self, weak webView] in
                    self?.ensureContainer(webView: webView)
                }
                return
            }
            if let webView {
                self.webView = webView
            }
            guard
                !containerInstalled,
                let webView = self.webView,
                let parent = webView.superview
            else {
                return
            }
            let index = parent.subviews.firstIndex(of: webView) ?? parent.subviews.count
            container.frame = webView.frame
            container.autoresizingMask = webView.autoresizingMask
            container.attach(webView: webView)
            parent.insertSubview(container, at: min(index, parent.subviews.count))
            containerInstalled = true
            NativeIslandsScenes.register(webView: webView, scene: container)
            container.onIslandVisibility = { [weak islands] id, visible in
                islands?.setViewportVisible(visible, id: id)
            }
            islands.showLaunchFrame()
        }

        /// Checks and applies an `applyLayout` payload, in order and with its `fence` in its page's
        /// commit. `completion` gets its acknowledgement: the page time it applied at, or nothing when
        /// a newer layout superseded it.
        public func applyLayout(
            _ payload: Any?,
            failure: @escaping (_ code: String, _ message: String) -> Void,
            completion: @escaping ([String: Any]) -> Void
        ) {
            guard let payload = validatedPayload(for: "applyLayout", payload, failure: failure) else { return }
            let layout: NativeIslandsLayout
            switch NativeIslandsLayoutParsing.layout(payload) {
            case .success(let read):
                layout = read
            case .failure(let refusal):
                return failure(refusal.code, refusal.message)
            }
            if let sentAt = layout.sentAt {
                pageClock.sample(pageMilliseconds: sentAt, nativeSeconds: CACurrentMediaTime())
            }
            let cancel = { failure("cancelled", "Native Islands was reset before this layout applied.") }
            inOrder(fence: layout.fence, cancel: cancel) {
                self.apply(layout, failure: failure, cancel: cancel) { appliedAt in
                    completion(appliedAt.map { ["appliedAt": $0] } ?? [:])
                }
            }
        }

        /// Checks a `command` payload and runs the command in order.
        public func command(
            _ payload: Any?,
            failure: @escaping (_ code: String, _ message: String) -> Void,
            completion: @escaping () -> Void
        ) {
            guard let payload = validatedPayload(for: "command", payload, failure: failure) else { return }
            guard
                let island = payload["island"] as? String,
                let type = payload["islandType"] as? String,
                let method = payload["method"] as? String
            else {
                return failure("invalid_request", "command envelope is incomplete")
            }
            guard let params = payload["params"] == nil ? [:] : payload["params"] as? [String: Any] else {
                return failure("invalid_request", "command params must be an object")
            }
            let instance = payload["instance"]
            let cancel = { failure("cancelled", "Native Islands was reset before this command ran.") }
            inOrder(cancel: cancel) {
                if let refusal = self.islands.command(
                    island: island,
                    type: type,
                    method: method,
                    params: params,
                    instance: NIBridgeSecurity.commandInstance(instance)
                ) {
                    failure(refusal.code, refusal.message)
                } else {
                    completion()
                }
            }
        }

        /// Checks a `reset` payload and resets. `completion` gets the session's platform capabilities.
        public func reset(
            _ payload: Any?,
            failure: (_ code: String, _ message: String) -> Void,
            completion: @escaping ([String: Any]) -> Void
        ) {
            guard validatedPayload(for: "reset", payload, failure: failure) != nil else { return }
            reset { completion(Self.sessionCapabilities) }
        }

        /// `payload` as an object, when it and its `operation` pass the bridge's shape checks;
        /// otherwise nil, after `failure` is told why.
        public func validatedPayload(
            for operation: String,
            _ payload: Any?,
            failure: (_ code: String, _ message: String) -> Void
        )
            -> [String: Any]? {
            guard let object = payload as? [String: Any] else {
                failure("invalid_request", "operation payload must be an object")
                return nil
            }
            if let refusal = NIBridgeSecurity.operationError(operation, payload: object) {
                failure(refusal.code, refusal.message)
                return nil
            }
            return object
        }

        public func reset(completion: @escaping () -> Void = {}) {
            onMain {
                self.dropQueuedWork()
                self.pageClock.clear()
                if !self.islands.reset() {
                    self.container.setCompositingActive(false)
                }
                completion()
            }
        }

        public func onHostResume() {
            onMain { [weak self] in
                self?.islands.setResumed(true)
            }
        }

        public func onHostPause() {
            onMain { [weak self] in
                self?.islands.setResumed(false)
            }
        }

        public func dispose() {
            onMain {
                self.dropQueuedWork()
                self.islands.dispose()
                if let webView = self.webView {
                    NativeIslandsScenes.unregister(webView: webView)
                }
                self.container.detachWebView()
                self.container.removeFromSuperview()
                self.containerInstalled = false
            }
        }

        private func apply(
            _ layout: NativeIslandsLayout,
            failure: @escaping (_ code: String, _ message: String) -> Void,
            cancel: @escaping () -> Void,
            completion: @escaping (Double?) -> Void
        ) {
            lastLayoutAppliedAt = nil
            endRetry(cancelled: false)
            ensureContainer(webView: webView)
            guard canApplyLayout(layout.components) else {
                failure("internal_error", "Native Islands could not install its native host because the WebView is not attached.")
                return
            }
            let accepted = islands.accept(layout.components, canvasColor: layout.canvasColor)
            let place = {
                self.container.applyLedger(
                    components: accepted,
                    scrollContainers: layout.scrollContainers,
                    order: layout.order,
                    exclusions: layout.exclusions,
                    cutouts: layout.cutouts,
                    tints: layout.tints,
                    motions: layout.motions,
                    panes: layout.panes
                )
            }
            let finish = { self.finish(layout, accepted: accepted, failures: $0, failure: failure, completion: completion) }
            let failures = place()
            guard failures.values.contains(where: { $0.kind == .missing }) else { return finish(failures) }
            // WebKit can build an inner scroller's scroll view in a commit after the paint that shows it.
            var passes = 0
            let observer = NativeIslandsCommitObserver(order: NativeIslandsCommitObserver.paintFenceOrder) { [weak self] in
                passes += 1
                let failures = place()
                guard passes >= Self.scrollViewWaitPasses || !failures.values.contains(where: { $0.kind == .missing }) else { return }
                finish(failures)
                // Released last: the observer runs this closure.
                self?.retry = nil
            }
            retry = (observer, { $0 ? cancel() : completion(nil) })
        }

        /// Ends the layout waiting for a scroll view, if one is.
        private func endRetry(cancelled: Bool) {
            guard let retry else { return }
            self.retry = nil
            retry.end(cancelled)
        }

        /// Fails the islands whose scrollers cannot be followed, and acknowledges the layout unless a
        /// scroller it needs has no scroll view yet: then the page is told which, and sends it again.
        private func finish(
            _ layout: NativeIslandsLayout,
            accepted: [IslandComponent],
            failures: [String: NIInnerScrollFailure],
            failure: (_ code: String, _ message: String) -> Void,
            completion: (Double?) -> Void
        ) {
            let missing = failures.filter { $0.value.kind == .missing }
            for (id, scrollFailure) in failures where scrollFailure.kind != .missing {
                islands.reportError(id: id, reason: scrollFailure.reason)
            }
            container.setCompositingActive(accepted.contains { $0.active }, canvasColor: NICanvasColor(layout.canvasColor)?.uiColor)
            guard missing.isEmpty else {
                let reasons = Set(missing.values.map(\.reason)).sorted().joined(separator: ", ")
                let ids = missing.keys.sorted().map { "'\($0)'" }.joined(separator: ", ")
                failure("invalid_request", "\(reasons) for \(ids)")
                return
            }
            islands.saveLaunchFrame()
            lastLayoutAppliedAt = pageClock.pageTime(nativeSeconds: CACurrentMediaTime())
            completion(lastLayoutAppliedAt)
        }

        private func canApplyLayout(
            _ components: [(IslandComponent, String)]
        )
            -> Bool {
            !components.contains { $0.0.active && $0.0.rect != nil } ||
                (containerInstalled &&
                    container.superview != nil &&
                    webView?.superview === container)
        }

        /// Runs `work` on the main thread after earlier calls and, with a fence, after its web commit.
        /// `cancel` answers the call instead if a reset drops it first.
        private func inOrder(fence: Int? = nil, cancel: @escaping () -> Void, _ work: @escaping () -> Void) {
            onMain { self.paintFence.enqueue(fence: fence, cancel: cancel, work) }
        }

        private func dropQueuedWork() {
            paintFence.drop()
            endRetry(cancelled: true)
        }
    }

    /// Runs `work` at once on the main thread, or next on the main queue from any other.
    func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
#endif
