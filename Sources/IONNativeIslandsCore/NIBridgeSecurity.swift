import CoreFoundation
import Foundation

struct NIBridgeSecurityError: Error {
    let code: String
    let message: String

    init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

final class NIBridgeSecurity {
    init() {}

    func validateActivation(type: String) throws {
        try validateToken(type, kind: "native component type")
    }

    func validateCommand(
        island: String,
        type: String,
        method: String,
        params: [String: Any],
        instance: Int?
    ) throws {
        try validateToken(island, kind: "native component id")
        try validateToken(method, kind: "command")
        try validateActivation(type: type)
        guard method == "create" || method == "update" else {
            throw NIBridgeSecurityError(
                "unknown_command",
                "'\(method)' is not a supported native component command"
            )
        }
        guard method != "create" || (instance ?? 0) >= 1 else {
            throw NIBridgeSecurityError(
                "invalid_request",
                "command create must carry a positive integer instance"
            )
        }
        guard isJSONValue(params) else {
            throw NIBridgeSecurityError(
                "invalid_request",
                "command params must be JSON-compatible"
            )
        }
    }

    func validateOperation(
        _ operation: String,
        payload: [String: Any]
    ) throws {
        try validateToken(operation, kind: "operation")
        guard isJSONValue(payload) else {
            throw NIBridgeSecurityError(
                "invalid_request",
                "operation payload must be JSON-compatible"
            )
        }
    }

    func commandInstance(_ value: Any?) -> Int? {
        guard let instance = strictInteger(value), instance >= 1, instance <= Int(Int32.max) else { return nil }
        return instance
    }

    private func validateToken(
        _ value: String,
        kind: String
    ) throws {
        guard !value.isEmpty else {
            throw NIBridgeSecurityError("invalid_request", "malformed \(kind)")
        }
    }

    func strictInteger(_ value: Any?) -> Int? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let doubleValue = number.doubleValue
        guard
            doubleValue.isFinite,
            doubleValue.rounded(.towardZero) == doubleValue,
            doubleValue >= Double(Int.min),
            doubleValue <= Double(Int.max)
        else {
            return nil
        }
        return Int(doubleValue)
    }

    private func isJSONValue(_ value: Any) -> Bool {
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
