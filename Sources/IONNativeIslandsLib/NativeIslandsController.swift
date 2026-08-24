#if canImport(UIKit)
    import UIKit
    import WebKit

    public final class NativeIslandsController {
        private let container = NativeIslandsContainer()
        let security = NIBridgeSecurity()
        private let events: (_ event: String, _ payload: [String: Any]) -> Void
        let lifecycle = NIIslandLifecycleState<[String: Any]>()
        var islands: [String: NativeIsland] = [:]
        private var initializedIslands: Set<String> = []
        private weak var webView: WKWebView?
        private var containerInstalled = false
        private var hostResumed = false

        public init(
            events: @escaping (_ event: String, _ payload: [String: Any]) -> Void
        ) {
            self.events = events
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
            cutouts: [String: Any]
        )
            -> String? {
            NILayoutValidation.error(
                components: components,
                scrollContainers: scrollContainers,
                order: order,
                exclusions: exclusions,
                cutouts: cutouts
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
            do {
                try security.validateOperation(
                    "applyLayout",
                    payload: payload,
                    maxBytes: NIBridgeSecurity.maxLayoutBytes
                )
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

        public func applyLayout(
            components rawComponents: [[String: Any]],
            scrollContainers rawScrollContainers: [[String: Any]] = [],
            order: [String],
            exclusions rawExclusions: [String: Any],
            cutouts rawCutouts: [String: Any],
            failure: @escaping (_ code: String, _ message: String) -> Void = { _, _ in },
            completion: @escaping () -> Void = {}
        ) {
            let components = NativeIslandsLayoutParsing.components(
                from: rawComponents
            )
            let scrollContainers = NativeIslandsLayoutParsing.scrollContainers(
                from: rawScrollContainers
            )
            let exclusions = NativeIslandsLayoutParsing.regions(
                from: rawExclusions
            )
            let cutouts = NativeIslandsLayoutParsing.regions(
                from: rawCutouts
            )

            DispatchQueue.main.async {
                self.ensureContainer(webView: self.webView)
                guard self.canApplyLayout(components) else {
                    failure(
                        "internal_error",
                        "Native Islands could not install its native host because the WebView is not attached."
                    )
                    return
                }
                self.lifecycle.retain(ids: Set(components.map(\.0.id)))
                var accepted: [IslandComponent] = []
                for (component, type) in components {
                    switch self.lifecycle.registerType(
                        id: component.id,
                        type: type
                    ) {
                    case .registered, .matched:
                        break
                    case .typeMismatch:
                        self.reportError(
                            id: component.id,
                            reason: "invalid_request: component type does not match its registered layout type"
                        )
                        continue
                    case .capacityExceeded:
                        self.reportError(
                            id: component.id,
                            reason: "invalid_request: too many tracked component types"
                        )
                        continue
                    }
                    var acceptedComponent = component
                    if component.active,
                       !self.ensureIsland(id: component.id, type: type) {
                        acceptedComponent.active = false
                        acceptedComponent.rect = nil
                    }
                    accepted.append(acceptedComponent)
                }

                let liveIDs = Set(accepted.map(\.id))
                let staleIDs = self.islands.keys.filter { !liveIDs.contains($0) }
                for id in staleIDs {
                    self.container.removeIsland(id: id)
                    self.islands[id]?.onDestroy()
                    self.islands[id] = nil
                    self.initializedIslands.remove(id)
                    self.lifecycle.removeType(id: id)
                }
                self.lifecycle.retain(ids: liveIDs)
                let innerScrollFailures = self.container.applyLedger(
                    components: accepted,
                    scrollContainers: scrollContainers,
                    order: order,
                    exclusions: exclusions,
                    cutouts: cutouts
                )
                for (id, reason) in innerScrollFailures {
                    self.reportError(id: id, reason: reason)
                }
                self.container.setCompositingActive(
                    accepted.contains { $0.active }
                )
                completion()
            }
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

        public func reset() {
            DispatchQueue.main.async {
                self.container.removeAllIslands()
                self.islands.values.forEach { $0.onDestroy() }
                self.islands.removeAll()
                self.initializedIslands.removeAll()
                self.lifecycle.reset()
                self.container.setCompositingActive(false)
            }
        }

        public func dispatchCommand(
            version: Int,
            island: String,
            requestedType: String,
            method: String,
            params: [String: Any],
            completion: @escaping ([String: Any]) -> Void
        ) {
            DispatchQueue.main.async {
                self.dispatchCommandOnMain(
                    version: version,
                    island: island,
                    requestedType: requestedType,
                    method: method,
                    params: params,
                    completion: completion
                )
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
            container.removeAllIslands()
            islands.values.forEach { $0.onDestroy() }
            islands.removeAll()
            initializedIslands.removeAll()
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
            if let existing = islands[id] {
                for command in lifecycle.drain(id: id) {
                    deliver(
                        id: id,
                        existing,
                        method: command.method,
                        properties: command.payload
                    )
                }
                return true
            }
            let registration = NativeIslandsRegistry.entry(for: type)
            let component: NativeIsland
            switch NIFactoryConstruction.run(registration?.factory) {
            case .created(let created):
                component = created
            case .missing:
                reportError(id: id, reason: "unknown_type:\(type)")
                return false
            case .failed(let errorType):
                reportError(
                    id: id,
                    reason: "handler_failed: factory_failed:\(type):\(errorType)"
                )
                return false
            }
            islands[id] = component
            if let emitting = component as? NativeIslandEventEmitting {
                emitting.eventSink = { [weak self] event, payload in
                    var data = payload
                    data["island"] = id
                    self?.events(event, data)
                }
            }
            ensureContainer(webView: webView)
            container.registerIsland(
                id: id,
                view: component.view,
                accessibility: registration?.accessibility ?? .web
            )
            if hostResumed {
                component.onResume()
            } else {
                component.onPause()
            }
            for command in lifecycle.drain(id: id) {
                deliver(
                    id: id,
                    component,
                    method: command.method,
                    properties: command.payload
                )
            }
            return true
        }

        func deliver(id: String, _ island: NativeIsland, method: String, properties: [String: Any]) {
            switch method {
            case "create" where initializedIslands.contains(id):
                island.update(properties: properties)
            case "create":
                island.create(properties: properties)
                initializedIslands.insert(id)
            case "update":
                island.update(properties: properties)
            default:
                assertionFailure("unsupported native component command '\(method)'")
            }
        }

        private func reportError(
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
