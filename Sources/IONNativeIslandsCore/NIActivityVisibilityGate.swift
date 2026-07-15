import Foundation

/// A live renderer runs only while its app and viewport gates are both open.
public final class NIActivityVisibilityGate {
    public private(set) var appActive = true
    public private(set) var viewportVisible = true
    public private(set) var destroyed = false

    public init() {}

    public var shouldRun: Bool { appActive && viewportVisible && !destroyed }

    @discardableResult
    public func setAppActive(_ active: Bool) -> Bool {
        appActive = active
        return shouldRun
    }

    @discardableResult
    public func setViewportVisible(_ visible: Bool) -> Bool {
        viewportVisible = visible
        return shouldRun
    }

    @discardableResult
    public func destroy() -> Bool {
        destroyed = true
        return shouldRun
    }
}
