#if canImport(UIKit)
    import UIKit

    public enum NativeIslandsRegistry {
        static let factories =
            NIIslandFactoryRegistry<() throws -> NativeIsland>()

        /// Registers a native component type before its custom element is mounted. A name registered
        /// again replaces its factory.
        public static func register(
            componentName: String,
            accessibility: NativeIslandAccessibility = .web,
            factory: @escaping () throws -> NativeIsland
        ) {
            precondition(
                NILayoutValidation.validIdentifier(componentName),
                "componentName must be a valid native component identifier"
            )
            factories.register(
                type: componentName,
                accessibility: accessibility,
                factory: factory
            )
        }

        /// Makes a registered component for a native host that places it itself (a native list's cells),
        /// which then owns its lifecycle. Nil when the name is unknown or the factory throws.
        public static func make(componentName: String) -> NativeIsland? {
            guard let entry = factories.entry(for: componentName) else { return nil }
            return try? entry.factory()
        }
    }
#endif
