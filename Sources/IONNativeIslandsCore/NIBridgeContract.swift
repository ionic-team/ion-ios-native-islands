import Foundation

enum NIBridgeContract {
    static let protocolVersion = 6
    static let maxRequestBytes = 16384
    static let maxLayoutBytes = 1_048_576
    static let maxIdentifierBytes = 64
    static let maxCommandBytes = 128
    static let maxCoordinateMagnitudeCSSPixels = 16_777_216.0
    static let maxSizeCSSPixels = 65536.0
    static let maxRadiusCSSPixels = 65536.0
    static let errors: Set = [
        "invalid_request", "unknown_command", "handler_failed",
        "payload_too_large", "unsupported_version", "internal_error",
    ]
}

enum NIHostPlane: String {
    case underlay
    case overlay
}

enum NICoordinateSpace: String {
    case document
    case viewport
}
