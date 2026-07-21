// The core bridge contract, hand-written and pinned by NIBridgeContractFreezeTests.
// The web (src/contract.ts) and Android (NIBridgeContract.kt) carry the same values;
// change any of them only as a coordinated bump across the packages.

import Foundation

internal enum NIBridgeContract {
    static let protocolVersion = 6
    static let maxRequestBytes = 16384
    static let maxLayoutBytes = 1_048_576
    static let maxIdentifierBytes = 64
    static let maxCommandBytes = 128
    static let maxCoordinateMagnitudeCSSPixels = 16_777_216.0
    static let maxSizeCSSPixels = 65_536.0
    static let maxRadiusCSSPixels = 65_536.0
    static let errors: Set<String> = [
        "invalid_request", "unknown_command", "handler_failed",
        "payload_too_large", "unsupported_version", "internal_error"
    ]
}

internal enum NIHostPlane: String {
    case underlay
    case overlay
}

internal enum NICoordinateSpace: String {
    case document
    case viewport
}
