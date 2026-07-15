#if canImport(UIKit)
import UIKit

/// A native island: a platform view the container hosts + positions. Islands are
/// created lazily by `type` as the ledger first references them, and receive scoped
/// `command`s from the web side (e.g. `setCamera`) through the islands controller.
public protocol NativeIsland: AnyObject {
    var view: UIView { get }
    func command(_ method: String, _ params: [String: Any])
}

/// Commands that answer with a value (a captured photo, a measurement). The controller
/// tries this first; returning `false` falls through to plain `command(_:_:)`. The
/// completion's dictionary is response-validated before it reaches the web.
public protocol NativeIslandResponding: AnyObject {
    func command(
        _ method: String,
        _ params: [String: Any],
        completion: @escaping ([String: Any]?) -> Void
    ) -> Bool
}

/// Native→web events. The controller installs the sink when the island is created and
/// adds `island: <id>` to every payload, so emitted events always satisfy the
/// `{island, ...payload}` envelope — islands cannot forge or omit their identity.
public protocol NativeIslandEventEmitting: AnyObject {
    var eventSink: ((_ event: String, _ payload: [String: Any]) -> Void)? { get set }
}

/// OBSERVE-TEE (Sentinel corollary): ownership routes a gesture to ONE layer; OBSERVATION may
/// tee to any island view conforming to this — the container forwards coordinates at native
/// event rate via a non-cancelling recognizer, zero bridge. Observation is not transfer: the
/// touch-ownership rule is untouched, so a page scroll stays a page scroll while the island
/// reacts under the finger crossing it.
public protocol TouchObserverView: AnyObject {
    func observeTouch(_ point: CGPoint)
}

public extension NativeIsland {
    /// OVERLAY island (§6.1): the view composites ABOVE the WebView (glass sheet) instead of
    /// behind it. A TYPE-level property — the container places the host at registration.
    var overlay: Bool { false }
    /// BATTERY: the container reports when the island's rect enters/leaves the viewport — islands
    /// with live sensors (camera/AR) pause them offscreen. Default: no-op.
    func setViewportVisible(_ visible: Bool) {}
    /// App lifecycle mirrors Android's NativeIsland contract. Live engines override these to
    /// suspend work while the host app is inactive; ordinary views inherit no-op behavior.
    func onResume() {}
    func onPause() {}
    /// Terminal teardown (page-navigation reset / removal): stop sessions explicitly instead of
    /// relying on ARC dealloc timing. Default: no-op.
    func destroy() {}

    /// Capture THIS island's own view (never the window — feedback-immune).
    /// Default: render-server snapshot of the host view. Metal-backed islands override.
    func captureFrame(_ completion: @escaping (UIImage?) -> Void) {
        let v = view
        guard v.bounds.width > 1, v.bounds.height > 1, v.window != nil else { completion(nil); return }
        // Half-res debug frame: quarter the pixels for the whole downstream chain.
        let size = CGSize(width: v.bounds.width / 2, height: v.bounds.height / 2)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            ctx.cgContext.scaleBy(x: 0.5, y: 0.5)
            v.drawHierarchy(in: v.bounds, afterScreenUpdates: false)
        }
        completion(image)
    }
}

/// A host view that reports layout passes, so geometry-dependent island props (a map
/// camera) can be applied only after the island has a real size — the `firstLayout`
/// phase (a camera set on a 0-size map clamps to a wrong region).
public final class IslandHostView: UIView {
    public var onLayout: (() -> Void)?
    override public func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
#endif
