import Foundation

/// Process-lifetime registry for island types whose native engine cannot tolerate
/// removal from the view hierarchy during a web-document navigation.
public final class NIPersistentTypeRegistry {
    private let lock = NSLock()
    private var types: Set<String> = []

    public init() {}

    public func register(_ type: String) {
        lock.lock()
        types.insert(type)
        lock.unlock()
    }

    public func contains(_ type: String?) -> Bool {
        guard let type else { return false }
        lock.lock()
        defer { lock.unlock() }
        return types.contains(type)
    }
}
