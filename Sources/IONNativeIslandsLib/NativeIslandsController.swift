#if canImport(UIKit)
    import UIKit
    import WebKit

    public final class NativeIslandsController {
        let container = NativeIslandsContainer()
        let security = NIBridgeSecurity()
        let events: (_ event: String, _ payload: [String: Any]) -> Void
        let lifecycle = NIIslandLifecycleState<[String: Any]>()
        var islands: [String: NativeIsland] = [:]
        weak var webView: WKWebView?
        private var containerInstalled = false
        var hostResumed = false
        private var layoutRevision = 0
        private let pageClock = NIPageClock()
        var heldCalls: [HeldCall] = []
        var fenceObserver: CFRunLoopObserver?
        weak var fenceSentinel: CALayer?

        public private(set) var lastLayoutAppliedAt: Double?

        public static let sessionCapabilities: [String: Any] = [
            "paneColor": true,
            "motionStartsAtCommit": true,
            "paintFence": true,
        ]

        public init(
            events: @escaping (_ event: String, _ payload: [String: Any]) -> Void
        ) {
            self.events = events
            container.pageClock = pageClock
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
            parent.insertSubview(
                container,
                at: min(index, parent.subviews.count)
            )
            containerInstalled = true
            NativeIslandsScenes.register(webView: webView, scene: container)
            container.onIslandVisibility = { [weak self] id, visible in
                self?.islands[id]?.setViewportVisible(visible)
            }
        }

        public func validateLayout(
            components: [[String: Any]],
            scrollContainers: [[String: Any]] = [],
            order: [String],
            exclusions: [String: Any],
            cutouts: [String: Any],
            tints: [String: Any] = [:],
            canvasColor: Any? = nil,
            panes: Any? = nil,
            motions: Any? = nil,
            sentAt: Any? = nil,
            fence: Any? = nil
        )
            -> String? {
            if canvasColor != nil, NICanvasColor(canvasColor) == nil {
                return "applyLayout canvasColor must be an opaque hex color"
            }
            if NativeIslandsLayoutParsing.panes(from: panes) == nil {
                return "applyLayout panes must map scroll container ids to an opaque hex color and an optional island id"
            }
            if sentAt != nil, (NISafeGeometry.strictNumber(sentAt) ?? -1) < 0 {
                return "applyLayout sentAt must be a non-negative number"
            }
            if motions != nil, sentAt == nil {
                return "applyLayout motions require sentAt"
            }
            if fence != nil, !(0 ..< Self.fenceRange).contains(security.strictInteger(fence) ?? -1) {
                return "applyLayout fence must be an integer from 0 to \(Self.fenceRange - 1)"
            }
            return NILayoutValidation.error(
                components: components,
                scrollContainers: scrollContainers,
                order: order,
                exclusions: exclusions,
                cutouts: cutouts,
                tints: tints,
                motions: motions
            )
        }

        public func validateOperation(
            _ operation: String,
            payload: [String: Any]
        )
            -> [String: Any]? {
            do {
                try security.validateOperation(operation, payload: payload)
                return nil
            } catch let exception as NIBridgeSecurityError {
                return error(code: exception.code, message: exception.message)
            } catch {
                return self.error(
                    code: "internal_error",
                    message: "operation validation failed"
                )
            }
        }

        public func validateLayoutOperation(
            _ payload: [String: Any]
        )
            -> [String: Any]? {
            validateOperation("applyLayout", payload: payload)
        }

        public func applyLayout(
            components rawComponents: [[String: Any]],
            scrollContainers rawScrollContainers: [[String: Any]] = [],
            order: [String],
            exclusions rawExclusions: [String: Any],
            cutouts rawCutouts: [String: Any],
            tints rawTints: [String: Any] = [:],
            canvasColor: String? = nil,
            panes rawPanes: Any? = nil,
            motions rawMotions: Any? = nil,
            sentAt: Double? = nil,
            fence: Int? = nil,
            failure: @escaping (_ code: String, _ message: String) -> Void = { _, _ in },
            completion: @escaping (Double?) -> Void = { _ in }
        ) {
            if let sentAt {
                pageClock.sample(pageMilliseconds: sentAt, nativeSeconds: CACurrentMediaTime())
            }
            let motions = NIMotionPayload.parse(rawMotions)
            let canvas = NICanvasColor(canvasColor).map {
                UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
            }
            let components = NativeIslandsLayoutParsing.components(from: rawComponents)
            let scrollContainers = NativeIslandsLayoutParsing.scrollContainers(from: rawScrollContainers)
            let exclusions = NativeIslandsLayoutParsing.regions(from: rawExclusions)
            let cutouts = NativeIslandsLayoutParsing.regions(from: rawCutouts)
            let tints = NativeIslandsLayoutParsing.regions(from: rawTints)
            let panes = NativeIslandsLayoutParsing.panes(from: rawPanes) ?? [:]

            inOrder(fence: fence) {
                self.lastLayoutAppliedAt = nil
                self.layoutRevision &+= 1
                let layoutRevision = self.layoutRevision
                self.ensureContainer(webView: self.webView)
                guard self.canApplyLayout(components) else {
                    failure(
                        "internal_error",
                        "Native Islands could not install its native host because the WebView is not attached."
                    )
                    return
                }
                let accepted = self.acceptComponents(components)
                let applyLedger = {
                    self.container.applyLedger(
                        components: accepted,
                        scrollContainers: scrollContainers,
                        order: order,
                        exclusions: exclusions,
                        cutouts: cutouts,
                        tints: tints,
                        motions: motions,
                        panes: panes
                    )
                }
                let finish = { (innerScrollFailures: [String: String]) in
                    let missing = innerScrollFailures.filter { $0.value.hasSuffix(":missing") }
                    for (id, reason) in innerScrollFailures where missing[id] == nil {
                        self.reportError(id: id, reason: reason)
                    }
                    self.container.setCompositingActive(accepted.contains { $0.active }, canvasColor: canvas)
                    guard missing.isEmpty else {
                        let reasons = Set(missing.values).sorted().joined(separator: ", ")
                        let ids = missing.keys.sorted().map { "'\($0)'" }.joined(separator: ", ")
                        failure("invalid_request", "\(reasons) for \(ids)")
                        return
                    }
                    self.lastLayoutAppliedAt = self.pageClock.pageTime(nativeSeconds: CACurrentMediaTime())
                    completion(self.lastLayoutAppliedAt)
                }
                let innerScrollFailures = applyLedger()
                guard innerScrollFailures.values.contains(where: { $0.hasSuffix(":missing") }) else {
                    finish(innerScrollFailures)
                    return
                }
                DispatchQueue.main.async {
                    guard self.layoutRevision == layoutRevision else { return completion(nil) }
                    let retried = applyLedger()
                    guard retried.values.contains(where: { $0.hasSuffix(":missing") }) else {
                        finish(retried)
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
                        guard self.layoutRevision == layoutRevision else { return completion(nil) }
                        finish(applyLedger())
                    }
                }
            }
        }

        /// Registers each component's layout type, drops islands that failed to
        /// materialize, and tears down the ones the new ledger no longer names.
        private func acceptComponents(
            _ components: [(IslandComponent, String)]
        )
            -> [IslandComponent] {
            lifecycle.retain(ids: Set(components.map(\.0.id)))
            var accepted: [IslandComponent] = []
            for (component, type) in components {
                switch lifecycle.registerType(id: component.id, type: type) {
                case .registered, .matched:
                    break
                case .typeMismatch:
                    reportError(
                        id: component.id,
                        reason: "invalid_request: component type does not match its registered layout type"
                    )
                    continue
                }
                var acceptedComponent = component
                if component.active,
                   !ensureIsland(id: component.id, type: type) {
                    acceptedComponent.active = false
                    acceptedComponent.rect = nil
                }
                accepted.append(acceptedComponent)
            }

            let liveIDs = Set(accepted.map(\.id))
            let staleIDs = islands.keys.filter { !liveIDs.contains($0) }
            for id in staleIDs {
                container.removeIsland(id: id)
                islands[id]?.onDestroy()
                islands[id] = nil
                lifecycle.removeType(id: id)
            }
            lifecycle.retain(ids: liveIDs)
            return accepted
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

        public func reset(completion: @escaping () -> Void = {}) {
            let performReset = {
                self.dropHeldCalls()
                self.layoutRevision &+= 1
                self.container.removeAllIslands()
                self.islands.values.forEach { $0.onDestroy() }
                self.islands.removeAll()
                self.lifecycle.reset()
                self.container.setCompositingActive(false)
                self.pageClock.clear()
                completion()
            }
            if Thread.isMainThread {
                performReset()
            } else {
                DispatchQueue.main.async(execute: performReset)
            }
        }

        public func dispatchCommand(
            island: String,
            requestedType: String,
            method: String,
            params: [String: Any],
            instance: Any?,
            completion: @escaping ([String: Any]) -> Void
        ) {
            inOrder {
                self.dispatchCommandOnMain(
                    island: island,
                    requestedType: requestedType,
                    method: method,
                    params: params,
                    instance: self.security.commandInstance(instance),
                    completion: completion
                )
            }
        }

        func onMain(_ work: @escaping () -> Void) {
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.async(execute: work)
            }
        }

        public func onHostResume() {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.onHostResume()
                }
                return
            }
            hostResumed = true
            islands.values.forEach { $0.onResume() }
        }

        public func onHostPause() {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.onHostPause()
                }
                return
            }
            hostResumed = false
            islands.values.forEach { $0.onPause() }
        }

        public func dispose() {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [self] in
                    dispose()
                }
                return
            }
            dropHeldCalls()
            layoutRevision &+= 1
            container.removeAllIslands()
            islands.values.forEach { $0.onDestroy() }
            islands.removeAll()
            lifecycle.clear()
            if let webView {
                NativeIslandsScenes.unregister(webView: webView)
            }
            container.detachWebView()
            container.removeFromSuperview()
            containerInstalled = false
        }

        private func ensureIsland(
            id: String,
            type: String
        )
            -> Bool {
            guard let island = islands[id] ?? constructIsland(id: id, type: type) else { return false }
            for command in lifecycle.drain(id: id) {
                deliver(
                    id: id,
                    islands[id] ?? island,
                    method: command.method,
                    properties: command.payload,
                    instance: command.instance
                )
            }
            return true
        }

        func reportError(
            id: String,
            reason: String
        ) {
            if lifecycle.markErrored(id: id) {
                events("islandError", ["island": id, "reason": reason])
            }
        }

        func error(
            code: String,
            message: String
        )
            -> [String: Any] {
            ["code": code, "error": message]
        }
    }
#endif
