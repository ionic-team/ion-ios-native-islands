#if canImport(UIKit)
    import UIKit

    extension NativeIslandsController {
        func dispatchCommandOnMain(
            island: String,
            requestedType: String,
            method: String,
            params: [String: Any],
            instance: Int?,
            completion: ([String: Any]) -> Void
        ) {
            if let failure = commandValidationFailure(
                island: island,
                requestedType: requestedType,
                method: method,
                params: params,
                instance: instance
            ) {
                completion(failure)
                return
            }

            let registration = lifecycle.registerType(
                id: island,
                type: requestedType
            )
            if let failure = registrationFailure(registration) {
                completion(failure)
                return
            }

            if let target = islands[island] {
                deliver(id: island, target, method: method, properties: params, instance: instance)
            } else if lifecycle.isErrored(id: island) {
                completion(
                    error(
                        code: "handler_failed",
                        message: "native component failed to mount"
                    )
                )
                return
            } else {
                lifecycle.buffer(
                    id: island,
                    method: method,
                    payload: params,
                    instance: instance
                )
            }
            completion(["value": NSNull()])
        }

        private func commandValidationFailure(
            island: String,
            requestedType: String,
            method: String,
            params: [String: Any],
            instance: Int?
        )
            -> [String: Any]? {
            if let registered = lifecycle.type(for: island),
               registered != requestedType {
                return error(
                    code: "invalid_request",
                    message: "component type does not match its registered layout type"
                )
            }
            do {
                try security.validateCommand(
                    island: island,
                    type: requestedType,
                    method: method,
                    params: params,
                    instance: instance
                )
                return nil
            } catch let exception as NIBridgeSecurityError {
                return error(code: exception.code, message: exception.message)
            } catch {
                return self.error(
                    code: "internal_error",
                    message: "command validation failed"
                )
            }
        }

        private func registrationFailure(
            _ registration: NITypeRegistrationResult
        )
            -> [String: Any]? {
            switch registration {
            case .registered, .matched:
                nil
            case .typeMismatch:
                error(
                    code: "invalid_request",
                    message: "component type does not match its registered layout type"
                )
            }
        }

        func constructIsland(id: String, type: String, replacing: Bool = false) -> NativeIsland? {
            let registration = NativeIslandsRegistry.entry(for: type)
            let component: NativeIsland
            switch NIFactoryConstruction.run(registration?.factory) {
            case .created(let created):
                component = created
            case .missing:
                reportError(id: id, reason: "unknown_type:\(type)")
                return nil
            case .failed(let errorType):
                reportError(
                    id: id,
                    reason: "handler_failed: factory_failed:\(type):\(errorType)"
                )
                return nil
            }
            islands[id] = component
            if let emitting = component as? NativeIslandEventEmitting {
                emitting.eventSink = { [weak self, weak component] event, payload in
                    guard let self, let component else { return }
                    self.onMain {
                        guard self.islands[id] === component else { return }
                        var data = payload
                        data["island"] = id
                        if let instance = self.lifecycle.instance(for: id) { data["instance"] = instance }
                        self.events(event, data)
                    }
                }
            }
            ensureContainer(webView: webView)
            if replacing {
                container.replaceIslandView(id: id, view: component.view)
            } else {
                container.registerIsland(
                    id: id,
                    view: component.view,
                    accessibility: registration?.accessibility ?? .web
                )
            }
            if hostResumed {
                component.onResume()
            } else {
                component.onPause()
            }
            return component
        }

        func deliver(
            id: String,
            _ island: NativeIsland,
            method: String,
            properties: [String: Any],
            instance: Int?
        ) {
            switch method {
            case "create":
                guard let instance else {
                    return assertionFailure("validation guarantees a create names its instance")
                }
                switch lifecycle.create(id: id, instance: instance) {
                case .create:
                    island.create(properties: properties)
                case .update:
                    island.update(properties: properties)
                case .recreate:
                    (island as? NativeIslandEventEmitting)?.eventSink = nil
                    guard let type = lifecycle.type(for: id),
                          let replacement = constructIsland(id: id, type: type, replacing: true)
                    else {
                        container.removeIsland(id: id)
                        islands[id] = nil
                        island.onDestroy()
                        return
                    }
                    island.onDestroy()
                    replacement.create(properties: properties)
                }
            case "update":
                island.update(properties: properties)
            default:
                assertionFailure("unsupported native component command '\(method)'")
            }
        }
    }
#endif
