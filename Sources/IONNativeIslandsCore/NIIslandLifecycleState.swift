struct NIPendingCommand<Payload> {
    let method: String
    let payload: Payload
}

enum NITypeRegistrationResult: Equatable {
    case registered
    case matched
    case typeMismatch
    case capacityExceeded
}

enum NIPendingCommandResult: Equatable {
    case buffered
    case pendingIDLimitExceeded
    case pendingCommandLimitExceeded
}

final class NIIslandLifecycleState<Payload> {
    static var maxTrackedTypes: Int {
        256
    }

    static var maxPendingIDs: Int {
        64
    }

    static var maxPendingCommandsPerID: Int {
        32
    }

    private var types: [String: String] = [:]
    private var pending: [String: [NIPendingCommand<Payload>]] = [:]
    private var errored: Set<String> = []

    func type(for id: String) -> String? {
        types[id]
    }

    func registerType(id: String, type: String) -> NITypeRegistrationResult {
        if let existing = types[id] {
            return existing == type ? .matched : .typeMismatch
        }
        guard types.count < Self.maxTrackedTypes else {
            return .capacityExceeded
        }
        types[id] = type
        return .registered
    }

    func removeType(id: String) {
        types[id] = nil
        pending[id] = nil
        errored.remove(id)
    }

    func retain(ids: Set<String>) {
        types = types.filter { ids.contains($0.key) }
        pending = pending.filter { ids.contains($0.key) }
        errored.formIntersection(ids)
    }

    func buffer(
        id: String,
        method: String,
        payload: Payload
    )
        -> NIPendingCommandResult {
        if pending[id] == nil, pending.count >= Self.maxPendingIDs {
            return .pendingIDLimitExceeded
        }
        if pending[id, default: []].count >= Self.maxPendingCommandsPerID {
            return .pendingCommandLimitExceeded
        }
        pending[id, default: []].append(
            NIPendingCommand(method: method, payload: payload)
        )
        return .buffered
    }

    func drain(id: String) -> [NIPendingCommand<Payload>] {
        defer { pending[id] = nil }
        return pending[id] ?? []
    }

    func markErrored(id: String) -> Bool {
        pending[id] = nil
        return errored.insert(id).inserted
    }

    func isErrored(id: String) -> Bool {
        errored.contains(id)
    }

    func reset() {
        types.removeAll()
        pending.removeAll()
        errored.removeAll()
    }

    func clear() {
        reset()
    }
}
