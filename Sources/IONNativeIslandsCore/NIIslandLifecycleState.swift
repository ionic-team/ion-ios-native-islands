import Foundation

public struct NIPendingCommand<Payload> {
    public let method: String
    public let payload: Payload

    public init(method: String, payload: Payload) {
        self.method = method
        self.payload = payload
    }
}

/// Main-queue-confined island identity and pre-mount command state.
///
/// The policy lives outside the Capacitor bridge so navigation/reset behavior is deterministic and
/// testable without UIKit or a WebView.
public final class NIIslandLifecycleState<Payload> {
    private var types: [String: String] = [:]
    private var pending: [String: [NIPendingCommand<Payload>]] = [:]
    private var errored: Set<String> = []
    private var awaitingAdoption: Set<String> = []

    public init() {}

    public func type(for id: String) -> String? { types[id] }

    /// Registers an id/type pair without ever allowing an existing id to change type.
    @discardableResult
    public func registerType(id: String, type: String) -> Bool {
        if let existing = types[id] { return existing == type }
        types[id] = type
        return true
    }

    public func removeType(id: String) {
        types[id] = nil
        pending[id] = nil
        errored.remove(id)
        awaitingAdoption.remove(id)
    }

    public func buffer(id: String, method: String, payload: Payload) {
        pending[id, default: []].append(NIPendingCommand(method: method, payload: payload))
    }

    public func drain(id: String) -> [NIPendingCommand<Payload>] {
        defer { pending[id] = nil }
        return pending[id] ?? []
    }

    /// Returns true only for the first report in the current page lifetime.
    @discardableResult
    public func markErrored(id: String) -> Bool {
        pending[id] = nil
        return errored.insert(id).inserted
    }

    public func isErrored(id: String) -> Bool { errored.contains(id) }

    public func markAwaitingAdoption(id: String) {
        if types[id] != nil { awaitingAdoption.insert(id) }
    }

    /// Returns true once when a paused persistent island is adopted by a new ledger.
    public func consumeAdoption(id: String) -> Bool {
        awaitingAdoption.remove(id) != nil
    }

    public func isAwaitingAdoption(id: String) -> Bool { awaitingAdoption.contains(id) }

    public func reset(keeping ids: Set<String> = []) {
        types = types.filter { ids.contains($0.key) }
        pending.removeAll()
        errored.removeAll()
        awaitingAdoption = ids.intersection(Set(types.keys))
    }

    public func clear() {
        types.removeAll()
        pending.removeAll()
        errored.removeAll()
        awaitingAdoption.removeAll()
    }
}
