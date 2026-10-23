struct NIPendingCommand<Payload> {
    let method: String
    let payload: Payload
    var instance: Int?
}

enum NICreation: Equatable {
    case create
    case update
    case recreate
}

enum NITypeRegistrationResult: Equatable {
    case registered
    case matched
    case typeMismatch
}

final class NIIslandLifecycleState<Payload> {
    private var types: [String: String] = [:]
    private var pending: [String: [NIPendingCommand<Payload>]] = [:]
    private var errored: Set<String> = []
    private var instances: [String: Int] = [:]

    func type(for id: String) -> String? {
        types[id]
    }

    func registerType(id: String, type: String) -> NITypeRegistrationResult {
        if let existing = types[id] {
            return existing == type ? .matched : .typeMismatch
        }
        types[id] = type
        return .registered
    }

    func removeType(id: String) {
        types[id] = nil
        pending[id] = nil
        errored.remove(id)
        instances[id] = nil
    }

    func retain(ids: Set<String>) {
        types = types.filter { ids.contains($0.key) }
        pending = pending.filter { ids.contains($0.key) }
        errored.formIntersection(ids)
        instances = instances.filter { ids.contains($0.key) }
    }

    func create(id: String, instance: Int) -> NICreation {
        defer { instances[id] = instance }
        switch instances[id] {
        case nil: return .create
        case instance: return .update
        default: return .recreate
        }
    }

    func instance(for id: String) -> Int? {
        instances[id]
    }

    func buffer(
        id: String,
        method: String,
        payload: Payload,
        instance: Int? = nil
    ) {
        pending[id, default: []].append(
            NIPendingCommand(method: method, payload: payload, instance: instance)
        )
    }

    func drain(id: String) -> [NIPendingCommand<Payload>] {
        defer { pending[id] = nil }
        return pending[id] ?? []
    }

    func markErrored(id: String) -> Bool {
        pending[id] = nil
        instances[id] = nil
        return errored.insert(id).inserted
    }

    func isErrored(id: String) -> Bool {
        errored.contains(id)
    }

    func reset() {
        types.removeAll()
        pending.removeAll()
        errored.removeAll()
        instances.removeAll()
    }

    func clear() {
        reset()
    }
}
