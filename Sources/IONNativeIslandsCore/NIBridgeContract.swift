// The core bridge contract, hand-written and pinned by NIBridgeContractFreezeTests.
// The web (src/contract.ts) and Android (NIBridgeContract.kt) carry the same values;
// change any of them only as a coordinated bump across the packages. Island types carry
// their own policy through the factory registry — only the internal `__page`
// pseudo-island lives here.

import Foundation

public enum NIBridgeContract {
    public static let protocolVersion = 2
    public static let contractDigest = "ni-core-1.0"
    public static let maxRequestBytes = 16384
    public static let maxResponseBytes = 2097152
    public static let maxIdentifierBytes = 64
    public static let maxCommandBytes = 128
    public static let errors: Set<String> = [
        "invalid_request", "unknown_command", "permission_denied", "handler_failed",
        "payload_too_large", "unsupported_version", "internal_error"
    ]
    public static let commands: [String: Set<String>] = [
        "__page": ["setBackdrop"]
    ]
    public static let capabilities: [String: String] = [
        "__page": "effects"
    ]
    public static let permissions: [String: String] = [
        "__page": "effects.overlay"
    ]
    public static let commandPermissions: [String: String] = [:]
    public static let accessibilityOwners: [String: String] = [:]
}
