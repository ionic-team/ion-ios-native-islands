#if canImport(UIKit)
    import Foundation

    extension NativeIslandsController {
        func dispatchCommandOnMain(
            version: Int,
            island: String,
            requestedType: String,
            method: String,
            params: [String: Any],
            completion: ([String: Any]) -> Void
        ) {
            if let failure = commandValidationFailure(
                version: version,
                island: island,
                requestedType: requestedType,
                method: method,
                params: params
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
                deliver(id: island, target, method: method, properties: params)
            } else if lifecycle.isErrored(id: island) {
                completion(
                    error(
                        code: "handler_failed",
                        message: "native component failed to mount"
                    )
                )
                return
            } else {
                let result = lifecycle.buffer(
                    id: island,
                    method: method,
                    payload: params
                )
                if let message = pendingErrorMessage(for: result) {
                    if registration == .registered {
                        lifecycle.removeType(id: island)
                    }
                    completion(error(code: "invalid_request", message: message))
                    return
                }
            }
            completion(["value": NSNull()])
        }

        private func commandValidationFailure(
            version: Int,
            island: String,
            requestedType: String,
            method: String,
            params: [String: Any]
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
                    version: version,
                    island: island,
                    type: requestedType,
                    method: method,
                    params: params
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
            case .capacityExceeded:
                error(
                    code: "invalid_request",
                    message: "too many tracked component types"
                )
            }
        }

        private func pendingErrorMessage(
            for result: NIPendingCommandResult
        )
            -> String? {
            switch result {
            case .buffered:
                nil
            case .pendingIDLimitExceeded:
                "too many components have pending commands"
            case .pendingCommandLimitExceeded:
                "too many pending commands for component"
            }
        }
    }
#endif
