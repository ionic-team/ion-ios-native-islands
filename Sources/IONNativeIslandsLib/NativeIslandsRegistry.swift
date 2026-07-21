#if canImport(UIKit)
import UIKit

public enum NativeIslandsRegistry {
    internal static let factories =
        NIIslandFactoryRegistry<() throws -> NativeIsland>()

    /// Registers a native component type before its custom element is mounted.
    public static func register(
        componentName: String,
        accessibility: NativeIslandAccessibility = .web,
        factory: @escaping () throws -> NativeIsland
    ) {
        precondition(
            componentName.range(
                of: "^[A-Za-z_][A-Za-z0-9._:-]{0,63}$",
                options: .regularExpression
            ) != nil,
            "componentName must be a valid native component identifier"
        )
        factories.register(
            type: componentName,
            accessibility: accessibility,
            factory: factory
        )
    }

    internal static func entry(
        for type: String
    ) -> NIIslandFactoryRegistration<() throws -> NativeIsland>? {
        factories.entry(for: type)
    }
}
#endif
