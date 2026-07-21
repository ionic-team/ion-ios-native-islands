#if canImport(UIKit)
    import UIKit

    /// A native component hosted in a web document.
    public protocol NativeIsland: AnyObject {
        var view: UIView { get }
        func create(properties: [String: Any])
        func update(properties: [String: Any])
        func onResume()
        func onPause()
        func onDestroy()
        func setViewportVisible(_ visible: Bool)
    }

    extension NativeIsland {
        public func create(properties: [String: Any]) {}
        public func update(properties: [String: Any]) {}
        public func onResume() {}
        public func onPause() {}
        public func onDestroy() {}
        public func setViewportVisible(_ visible: Bool) {}
    }

    public protocol NativeIslandEventEmitting: AnyObject {
        var eventSink: ((_ event: String, _ payload: [String: Any]) -> Void)? { get set }
    }
#endif
