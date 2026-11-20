import Foundation

public enum NativeIslandAccessibility: Sendable {
    case web
    case native
}

struct NIIslandFactoryRegistration<Factory> {
    let accessibility: NativeIslandAccessibility
    let factory: Factory
}

final class NIIslandFactoryRegistry<Factory> {
    private var entries: [String: NIIslandFactoryRegistration<Factory>] = [:]
    private let lock = NSLock()

    func register(
        type: String,
        accessibility: NativeIslandAccessibility,
        factory: Factory
    ) {
        lock.lock()
        defer { lock.unlock() }
        let incoming = NIIslandFactoryRegistration(
            accessibility: accessibility,
            factory: factory
        )
        if let existing = entries[type] {
            precondition(
                existing.accessibility == incoming.accessibility,
                "native component '\(type)' is already registered with different options"
            )
        }
        entries[type] = incoming
    }

    func entry(for type: String) -> NIIslandFactoryRegistration<Factory>? {
        lock.lock()
        defer { lock.unlock() }
        return entries[type]
    }
}
