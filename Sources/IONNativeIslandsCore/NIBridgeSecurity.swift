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
    static let protocolVersion = NIBridgeContract.protocolVersion
    static let maxRequestBytes = NIBridgeContract.maxRequestBytes
    static let maxLayoutBytes = NIBridgeContract.maxLayoutBytes
    static let maxIdentifierBytes = NIBridgeContract.maxIdentifierBytes
    static let maxCommandBytes = NIBridgeContract.maxCommandBytes

    init() {}

    func validateActivation(type: String) throws {
        try validateToken(
            type,
            kind: "native component type",
            maxBytes: Self.maxIdentifierBytes,
            pattern: "^[A-Za-z_][A-Za-z0-9._:-]*$"
        )
    }

    func validateCommand(
        version: Int,
        island: String,
        type: String,
        method: String,
        params: [String: Any]
    ) throws {
        try validateVersion(version)
        try validateToken(
            island,
            kind: "native component id",
            maxBytes: Self.maxIdentifierBytes,
            pattern: "^[A-Za-z_][A-Za-z0-9._:-]*$"
        )
        try validateToken(
            method,
            kind: "command",
            maxBytes: Self.maxCommandBytes,
            pattern: "^[A-Za-z][A-Za-z0-9._-]*$"
        )
        try validateActivation(type: type)
        guard method == "create" || method == "update" else {
            throw NIBridgeSecurityError(
                "unknown_command",
                "'\(method)' is not a supported native component command"
            )
        }
        guard isJSONValue(params) else {
            throw NIBridgeSecurityError(
                "invalid_request",
                "command params must be JSON-compatible"
            )
        }
        let data = try JSONSerialization.data(withJSONObject: params)
        guard data.count <= Self.maxRequestBytes else {
            throw NIBridgeSecurityError(
                "payload_too_large",
                "payload \(data.count)B exceeds \(Self.maxRequestBytes)B"
            )
        }
    }

    func validateOperation(
        _ operation: String,
        payload: [String: Any],
        maxBytes: Int = maxRequestBytes
    ) throws {
        guard let version = strictInteger(payload["protocolVersion"]) else {
            throw NIBridgeSecurityError(
                "unsupported_version",
                "bridge protocol is invalid; native expects \(Self.protocolVersion)"
            )
        }
        try validateVersion(version)
        try validateToken(
            operation,
            kind: "operation",
            maxBytes: Self.maxCommandBytes,
            pattern: "^[A-Za-z][A-Za-z0-9._-]*$"
        )
        guard isJSONValue(payload) else {
            throw NIBridgeSecurityError(
                "invalid_request",
                "operation payload must be JSON-compatible"
            )
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard data.count <= maxBytes else {
            throw NIBridgeSecurityError(
                "payload_too_large",
                "payload \(data.count)B exceeds \(maxBytes)B"
            )
        }
    }

    func validateVersion(_ version: Int) throws {
        guard version == Self.protocolVersion else {
            throw NIBridgeSecurityError(
                "unsupported_version",
                "bridge protocol \(version) is unsupported; native expects \(Self.protocolVersion)"
            )
        }
    }

    private func validateToken(
        _ value: String,
        kind: String,
        maxBytes: Int,
        pattern: String
    ) throws {
        guard
            !value.isEmpty,
            value.utf8.count <= maxBytes,
            value.range(of: pattern, options: .regularExpression) != nil
        else {
            throw NIBridgeSecurityError("invalid_request", "malformed \(kind)")
        }
    }

    private func strictInteger(_ value: Any?) -> Int? {
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

    private func isJSONValue(
        _ value: Any,
        depth: Int = 0
    )
        -> Bool {
        guard depth <= 32 else { return false }
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
            return array.allSatisfy {
                isJSONValue($0, depth: depth + 1)
            }
        }
        if let object = value as? [String: Any] {
            return object.values.allSatisfy {
                isJSONValue($0, depth: depth + 1)
            }
        }
        if let dictionary = value as? NSDictionary {
            return dictionary.allSatisfy { key, child in
                key is String && isJSONValue(child, depth: depth + 1)
            }
        }
        return false
    }
}
