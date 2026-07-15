import Foundation

/// Stable bridge-error to virtual-HTTP status mapping shared by dispatch and tests.
public enum NIHttpStatus {
    public static func forCode(_ code: String?) -> Int {
        switch code {
        case nil, "": return 200
        case "invalid_request": return 400
        case "permission_denied": return 403
        case "unknown_command": return 404
        case "payload_too_large": return 413
        case "unsupported_version": return 426
        default: return 500
        }
    }
}
