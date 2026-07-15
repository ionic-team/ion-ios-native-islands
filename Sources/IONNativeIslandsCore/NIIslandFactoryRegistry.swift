import Foundation

public struct NIIslandFactoryRegistration<Factory> {
    public let allowedCommands: Set<String>
    public let capability: String
    /// Permission the app must grant for this type's commands (default `custom.<type>.command`).
    public let permission: String?
    /// Per-command permission overrides, keyed `<type>.<method>` (e.g. a capture that needs
    /// a stronger grant than ordinary control commands).
    public let commandPermissions: [String: String]
    public let accessibilityOwner: String?
    public let factory: Factory

    public init(
        allowedCommands: Set<String>,
        capability: String,
        permission: String? = nil,
        commandPermissions: [String: String] = [:],
        accessibilityOwner: String? = nil,
        factory: Factory
    ) {
        self.allowedCommands = allowedCommands
        self.capability = capability
        self.permission = permission
        self.commandPermissions = commandPermissions
        self.accessibilityOwner = accessibilityOwner
        self.factory = factory
    }
}

/// Process-lifetime registry whose factory and policy are replaced/read as one atomic entry.
public final class NIIslandFactoryRegistry<Factory> {
    private var entries: [String: NIIslandFactoryRegistration<Factory>] = [:]
    private let lock = NSLock()

    public init() {}

    public func register(
        type: String,
        allowedCommands: Set<String>,
        capability: String,
        permission: String? = nil,
        commandPermissions: [String: String] = [:],
        accessibilityOwner: String? = nil,
        factory: Factory
    ) {
        lock.lock()
        entries[type] = NIIslandFactoryRegistration(
            allowedCommands: allowedCommands,
            capability: capability,
            permission: permission,
            commandPermissions: commandPermissions,
            accessibilityOwner: accessibilityOwner,
            factory: factory
        )
        lock.unlock()
    }

    public func entry(for type: String) -> NIIslandFactoryRegistration<Factory>? {
        lock.lock()
        defer { lock.unlock() }
        return entries[type]
    }
}
