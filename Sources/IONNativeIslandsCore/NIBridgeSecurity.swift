import CoreFoundation
import Foundation

struct NIBridgeError: Error, Equatable {
    let code: String
    let message: String

    init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

/// A component command the page may send, read from its wire `method`.
enum NIIslandCommand: Equatable {
    case create(instance: Int)
    case update
}

/// Shape checks on what the page sends before native acts on it.
enum NIBridgeSecurity {
    static func command(
        island: String,
        type: String,
        method: String,
        params: [String: Any],
        instance: Int?
    )
        -> Result<NIIslandCommand, NIBridgeError> {
        if let error = tokenError(island, kind: "native component id") ??
            tokenError(method, kind: "command") ??
            tokenError(type, kind: "native component type") {
            return .failure(error)
        }
        let command: NIIslandCommand
        switch method {
        case "create":
            guard let instance, instance >= 1 else {
                return .failure(NIBridgeError("invalid_request", "command create must carry a positive integer instance"))
            }
            command = .create(instance: instance)
        case "update":
            command = .update
        default:
            return .failure(NIBridgeError("unknown_command", "'\(method)' is not a supported native component command"))
        }
        guard isJSONValue(params) else {
            return .failure(NIBridgeError("invalid_request", "command params must be JSON-compatible"))
        }
        return .success(command)
    }

    static func operationError(
        _ operation: String,
        payload: [String: Any]
    )
        -> NIBridgeError? {
        if let error = tokenError(operation, kind: "operation") { return error }
        guard isJSONValue(payload) else {
            return NIBridgeError("invalid_request", "operation payload must be JSON-compatible")
        }
        return nil
    }

    static func commandInstance(_ value: Any?) -> Int? {
        guard let instance = NISafeGeometry.strictInteger(value), instance >= 1, instance <= Int(Int32.max) else { return nil }
        return instance
    }

    private static func tokenError(_ value: String, kind: String) -> NIBridgeError? {
        NILayoutValidation.validIdentifier(value) ? nil : NIBridgeError("invalid_request", "malformed \(kind)")
    }

    private static func isJSONValue(_ value: Any) -> Bool {
        if value is NSNull || value is String {
            return true
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return true
            }
            return number.doubleValue.isFinite
        }
        if let array = value as? [Any] {
            return array.allSatisfy { isJSONValue($0) }
        }
        if let object = value as? [String: Any] {
            return object.values.allSatisfy { isJSONValue($0) }
        }
        if let dictionary = value as? NSDictionary {
            return dictionary.allSatisfy { key, child in
                key is String && isJSONValue(child)
            }
        }
        return false
    }
}
