#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    @testable import IONNativeIslandsLib

    /// The bridge operations as a page sends them, through the controller's public entry points.
    extension NativeIslandsController {
        /// Sends an `applyLayout` payload with these fields. `completion` gets the page time it
        /// applied at, or nil when a newer layout superseded it.
        func applyLayout(
            components: [[String: Any]],
            scrollContainers: [[String: Any]] = [],
            order: [String],
            exclusions: [String: Any],
            cutouts: [String: Any],
            canvasColor: String? = nil,
            sentAt: Double? = nil,
            fence: Any? = nil,
            failure: @escaping (_ code: String, _ message: String) -> Void = { _, _ in },
            completion: @escaping (Double?) -> Void = { _ in }
        ) {
            var payload: [String: Any] = [
                "components": components,
                "scrollContainers": scrollContainers,
                "order": order,
                "exclusions": exclusions,
                "cutouts": cutouts,
            ]
            payload["canvasColor"] = canvasColor
            payload["sentAt"] = sentAt
            payload["fence"] = fence
            applyLayout(payload, failure: failure) { completion($0["appliedAt"] as? Double) }
        }

        /// Sends a `command` payload. `completion` gets the code it was refused with, or nil.
        func command(
            island: String,
            type: String,
            method: String,
            params: [String: Any] = [:],
            instance: Int? = nil,
            completion: @escaping (_ refusal: String?) -> Void
        ) {
            var payload: [String: Any] = ["island": island, "islandType": type, "method": method, "params": params]
            payload["instance"] = instance
            command(payload, failure: { code, _ in completion(code) }, completion: { completion(nil) })
        }
    }
#endif
