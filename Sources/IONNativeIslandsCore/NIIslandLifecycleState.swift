struct NIPendingCommand<Payload> {
    let command: NIIslandCommand
    let payload: Payload
}

enum NICreation: Equatable {
    case create
    case update
    case recreate
}

/// Per island id: its pinned component type, commands sent before it mounted, whether mounting
/// failed, and the web instance its view belongs to.
final class NIIslandLifecycleState<Payload> {
    private var types: [String: String] = [:]
    private var pending: [String: [NIPendingCommand<Payload>]] = [:]
    private var errored: Set<String> = []
    private var instances: [String: Int] = [:]

    func type(for id: String) -> String? {
        types[id]
    }

    /// Pins `type` to `id`; false when `id` already has another type.
    func registerType(id: String, type: String) -> Bool {
        if let existing = types[id] {
            return existing == type
        }
        types[id] = type
        return true
    }

    func removeType(id: String) {
        types[id] = nil
        pending[id] = nil
        errored.remove(id)
        instances[id] = nil
    }

    func transfer(from oldID: String, to newID: String) {
        if let type = types.removeValue(forKey: oldID) {
            types[newID] = type
        }
        if let existingPending = pending.removeValue(forKey: oldID) {
            pending[newID] = existingPending + (pending[newID] ?? [])
        }
        if errored.remove(oldID) != nil {
            errored.insert(newID)
        }
        if let existingInstance = instances.removeValue(forKey: oldID) {
            instances[newID] = instances[newID] ?? existingInstance
        }
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

    /// The web instance island `id` stands for: the one its view was created for, else the one a
    /// create waiting for it to mount carries.
    func instance(for id: String) -> Int? {
        instances[id] ?? pending[id]?.compactMap { pending -> Int? in
            if case .create(let instance) = pending.command { return instance }
            return nil
        }.last
    }

    func buffer(id: String, command: NIIslandCommand, payload: Payload) {
        pending[id, default: []].append(NIPendingCommand(command: command, payload: payload))
    }

    func drain(id: String) -> [NIPendingCommand<Payload>] {
        defer { pending[id] = nil }
        return pending[id] ?? []
    }

    /// Records a failed mount; true only the first time, so the failure is reported once.
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
}
