#if canImport(UIKit)
import Foundation
import UIKit
#if canImport(IONNativeIslandsCore)
import IONNativeIslandsCore
#endif

/// How an island's accessibility face is owned: `web` mirrors the DOM host element as the
/// assistive-technology face; `native` keeps the island view's own semantic tree.
public enum NIAccessibilityOwner: String, Sendable {
    case web
    case native
}

/// Process-lifetime registry of island types. Plugins and apps register the native factory
/// plus the type's command/permission policy here; the islands controller consults it at
/// ledger and command time. Registration must precede the first web ledger that references
/// the type — anchor it in a Capacitor plugin's `load()`, a Cordova plugin's
/// `pluginInitialize`, or the app's `AppDelegate`. Late registration self-heals on the next
/// layout pass; a page whose element already degraded recovers on reload.
public enum NativeIslandsRegistry {
    static let factories = NIIslandFactoryRegistry<() throws -> NativeIsland>()
    static let persistentTypes = NIPersistentTypeRegistry()

    /// Register an island type. `type` is the value web elements carry (vendor-prefix custom
    /// types, e.g. `"os.locationButton"`). `allowedCommands` is the native command allowlist;
    /// `capability` (and `permission`, default `custom.<type>.command`) name the grants the
    /// host app must add to its plugin configuration for the type to activate.
    public static func register(
        type: String,
        allowedCommands: Set<String>,
        capability: String,
        permission: String? = nil,
        commandPermissions: [String: String] = [:],
        accessibilityOwner: NIAccessibilityOwner = .web,
        persistent: Bool = false,
        factory: @escaping () throws -> NativeIsland
    ) {
        factories.register(
            type: type,
            allowedCommands: allowedCommands,
            capability: capability,
            permission: permission,
            commandPermissions: commandPermissions,
            accessibilityOwner: accessibilityOwner.rawValue,
            factory: factory
        )
        if persistent { persistentTypes.register(type) }
    }

    /// Mark a type's engine as surviving web-document navigation (the next page adopts the
    /// same island id). Registerable independently of the factory — either order works.
    public static func registerPersistentType(_ type: String) {
        persistentTypes.register(type)
    }

    public static func entry(
        for type: String
    ) -> NIIslandFactoryRegistration<() throws -> NativeIsland>? {
        factories.entry(for: type)
    }

    public static func isPersistent(_ type: String?) -> Bool {
        persistentTypes.contains(type)
    }
}
#endif
