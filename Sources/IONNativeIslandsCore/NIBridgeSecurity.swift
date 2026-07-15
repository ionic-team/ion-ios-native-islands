import Foundation

public struct NIBridgeSecurityError: Error {
    public let code: String
    public let message: String

    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

/// Authoritative native command gate. Web validation is useful feedback; this gate is the
/// security boundary because page JavaScript is not trusted to police itself.
public final class NIBridgeSecurity {
    public static let protocolVersion = NIBridgeContract.protocolVersion
    public static let contractDigest = NIBridgeContract.contractDigest
    public static let maxRequestBytes = NIBridgeContract.maxRequestBytes
    public static let maxResponseBytes = NIBridgeContract.maxResponseBytes
    public static let maxIdentifierBytes = NIBridgeContract.maxIdentifierBytes
    public static let maxCommandBytes = NIBridgeContract.maxCommandBytes

    private static let identifier = try! NSRegularExpression(pattern: "^[A-Za-z_][A-Za-z0-9._:-]*$")
    private static let command = try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9._-]*$")

    private let origins: Set<String>
    private let capabilities: Set<String>
    private let permissions: Set<String>

    public init(origins: [String], capabilities: [String], permissions: [String]) {
        self.origins = Set(origins)
        self.capabilities = Set(capabilities)
        self.permissions = Set(permissions)
    }

    public func validateActivation(type: String, origin: String?, customCapability: String? = nil) throws {
        try validateToken(type, kind: "island type", maxBytes: Self.maxIdentifierBytes, expression: Self.identifier)
        try validateOrigin(origin)
        let capability = customCapability ?? NIBridgeContract.capabilities[type] ?? "custom.\(type)"
        guard capabilities.contains(capability) else {
            throw NIBridgeSecurityError("permission_denied", "capability '\(capability)' is not enabled")
        }
    }

    public func validateCommand(version: Int, contractDigest: String, island: String, type: String, method: String, params: [String: Any],
                         origin: String?, customCommands: Set<String>? = nil,
                         customCapability: String? = nil,
                         customPermission: String? = nil,
                         customCommandPermissions: [String: String]? = nil) throws {
        try validateVersion(version)
        try validateContract(contractDigest)
        try validateToken(island, kind: "island id", maxBytes: Self.maxIdentifierBytes, expression: Self.identifier)
        try validateToken(method, kind: "command", maxBytes: Self.maxCommandBytes, expression: Self.command)
        try validateActivation(type: type, origin: origin, customCapability: customCapability)

        let allowed = customCommands ?? NIBridgeContract.commands[type]
        guard allowed?.contains(method) == true else {
            throw NIBridgeSecurityError("unknown_command", "'\(method)' is not registered for island type '\(type)'")
        }

        let permission = customCommandPermissions?["\(type).\(method)"]
            ?? NIBridgeContract.commandPermissions["\(type).\(method)"]
            ?? customPermission
            ?? NIBridgeContract.permissions[type]
            ?? "custom.\(type).command"
        guard permissions.contains(permission) else {
            throw NIBridgeSecurityError("permission_denied", "command '\(type).\(method)' requires '\(permission)'")
        }

        guard JSONSerialization.isValidJSONObject(params) else {
            throw NIBridgeSecurityError("invalid_request", "command params must be JSON-compatible")
        }
        let data: Data
        do { data = try JSONSerialization.data(withJSONObject: params) }
        catch { throw NIBridgeSecurityError("invalid_request", "command params could not be encoded") }
        guard data.count <= Self.maxRequestBytes else {
            throw NIBridgeSecurityError("payload_too_large", "payload \(data.count)B exceeds \(Self.maxRequestBytes)B")
        }
    }

    public func validateResponse(_ result: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(result),
              let data = try? JSONSerialization.data(withJSONObject: result) else {
            throw NIBridgeSecurityError("internal_error", "native response is not JSON-compatible")
        }
        guard data.count <= Self.maxResponseBytes else {
            throw NIBridgeSecurityError("payload_too_large", "response \(data.count)B exceeds \(Self.maxResponseBytes)B")
        }
    }

    public func validateOperation(_ operation: String, payload: [String: Any], origin: String?,
                           permission: String, maxBytes: Int = maxRequestBytes) throws {
        try validateVersion((payload["protocolVersion"] as? NSNumber)?.intValue ?? -1)
        try validateContract(payload["contractDigest"] as? String ?? "")
        try validateToken(operation, kind: "operation", maxBytes: Self.maxCommandBytes, expression: Self.command)
        try validateOrigin(origin)
        guard permissions.contains(permission) else {
            throw NIBridgeSecurityError("permission_denied", "operation '\(operation)' requires '\(permission)'")
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw NIBridgeSecurityError("invalid_request", "operation payload must be JSON-compatible")
        }
        guard data.count <= maxBytes else {
            throw NIBridgeSecurityError("payload_too_large", "payload \(data.count)B exceeds \(maxBytes)B")
        }
    }

    public func validateVersion(_ version: Int) throws {
        guard version == Self.protocolVersion else {
            throw NIBridgeSecurityError(
                "unsupported_version",
                "bridge protocol \(version) is unsupported; native expects \(Self.protocolVersion)")
        }
    }

    public func validateContract(_ digest: String) throws {
        guard digest == Self.contractDigest else {
            throw NIBridgeSecurityError(
                "unsupported_version",
                "bridge contract digest mismatch; run cap sync with matching web and native packages")
        }
    }

    private func validateOrigin(_ origin: String?) throws {
        guard let origin = origin, !origin.isEmpty else {
            throw NIBridgeSecurityError("permission_denied", "missing web origin")
        }
        guard origins.contains(origin) else {
            throw NIBridgeSecurityError("permission_denied", "origin '\(origin)' is not allowed")
        }
    }

    private func validateToken(_ value: String, kind: String, maxBytes: Int,
                               expression: NSRegularExpression) throws {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard !value.isEmpty, value.utf8.count <= maxBytes,
              expression.firstMatch(in: value, range: range)?.range == range else {
            throw NIBridgeSecurityError("invalid_request", "malformed \(kind)")
        }
    }
}
