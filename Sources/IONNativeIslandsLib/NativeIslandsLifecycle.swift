#if canImport(UIKit)
    import UIKit

    /// The islands native keeps for a page, by id: each one's component, pinned type, web instance and
    /// commands sent before it mounted, its view in the container, handover between ids, and the
    /// launch frame. Main thread only.
    final class NativeIslandsLifecycle {
        private static let typeMismatch = "component type does not match its registered layout type"

        private let container: NativeIslandsContainer
        private let launch: NativeIslandsLaunchFrame
        private let events: (_ event: String, _ payload: [String: Any]) -> Void
        private let state = NIIslandLifecycleState<[String: Any]>()
        private var islands: [String: NativeIsland] = [:]
        private var resumed = false
        /// Saves the launch frame once before the main run loop next waits, however many layouts and
        /// commands ask in that turn.
        private var launchSave: NativeIslandsCommitObserver?
        /// Installs the container, if it is not yet, before an island's view is put in it.
        var installContainer: () -> Void = {}

        init(
            container: NativeIslandsContainer,
            launch: NativeIslandsLaunchFrame,
            events: @escaping (_ event: String, _ payload: [String: Any]) -> Void
        ) {
            self.container = container
            self.launch = launch
            self.events = events
        }

        /// Runs a `command` for island `island`, or buffers it until the island mounts. Returns why it
        /// is refused, or nil.
        func command(
            island: String,
            type requestedType: String,
            method: String,
            params: [String: Any],
            instance: Int?
        )
            -> NIBridgeError? {
            // Checked before the command is validated, so a refused command never pins a type.
            if let registered = state.type(for: island), registered != requestedType {
                return NIBridgeError("invalid_request", Self.typeMismatch)
            }
            let command: NIIslandCommand
            switch NIBridgeSecurity.command(
                island: island,
                type: requestedType,
                method: method,
                params: params,
                instance: instance
            ) {
            case .success(let valid):
                command = valid
            case .failure(let refusal):
                return refusal
            }
            _ = state.registerType(id: island, type: requestedType)

            if let target = islands[island] {
                deliver(id: island, target, command: command, properties: params)
            } else if state.isErrored(id: island) {
                return NIBridgeError("handler_failed", "native component failed to mount")
            } else {
                state.buffer(id: island, command: command, payload: params)
            }
            return nil
        }

        /// Takes a layout's components, as the page lays out (the launch frame stops standing in for it):
        /// pins each one's type, hands portal and launch-frame views to the ids that take them over,
        /// mounts what is shown, and destroys islands the layout no longer names.
        func accept(_ components: [(IslandComponent, String)], canvasColor: String?) -> [IslandComponent] {
            handOverIslands(to: components, launchFrameShowing: launch.pageLaidOut(canvasColor: canvasColor))
            var accepted: [IslandComponent] = []
            for (component, type) in components {
                guard state.registerType(id: component.id, type: type) else {
                    reportError(id: component.id, reason: "invalid_request: \(Self.typeMismatch)")
                    continue
                }
                var acceptedComponent = component
                if component.active,
                   !ensureIsland(id: component.id, type: type) {
                    acceptedComponent.active = false
                    acceptedComponent.rect = nil
                }
                accepted.append(acceptedComponent)
            }

            let liveIDs = Set(accepted.map(\.id))
            let staleIDs = islands.keys.filter { !liveIDs.contains($0) }
            for id in staleIDs {
                container.removeIsland(id: id)
                islands[id]?.onDestroy()
                islands[id] = nil
                launch.forget(id)
                state.removeType(id: id)
            }
            state.retain(ids: liveIDs)
            return accepted
        }

        /// Reports island `id` failed, once until it mounts again, with the instance its view was
        /// created for so the page can tell an error about a view it has since replaced.
        func reportError(
            id: String,
            reason: String
        ) {
            let instance = state.instance(for: id)
            guard state.markErrored(id: id) else { return }
            var payload: [String: Any] = ["island": id, "reason": reason]
            payload["instance"] = instance
            events("islandError", payload)
        }

        func setResumed(_ resumed: Bool) {
            self.resumed = resumed
            islands.values.forEach { resumed ? $0.onResume() : $0.onPause() }
        }

        func setViewportVisible(_ visible: Bool, id: String) {
            islands[id]?.setViewportVisible(visible)
        }

        /// Forgets every island, unless the launch frame shows: then its islands and their types stay
        /// for the page's layout. Returns whether the launch frame still shows.
        func reset() -> Bool {
            flushLaunchSave()
            guard launch.showing else {
                destroyIslands()
                return false
            }
            let preservedTypes: [(String, String)] = islands.keys.compactMap { id in
                guard let type = state.type(for: id) else { return nil }
                return (id, type)
            }
            state.reset()
            for (id, type) in preservedTypes {
                _ = state.registerType(id: id, type: type)
            }
            return true
        }

        /// Destroys every island. A launch frame showing shows again when the container is next installed.
        func dispose() {
            flushLaunchSave()
            destroyIslands()
            launch.rewind()
        }

        /// Shows the cached launch frame when the container is installed before the page lays out.
        func showLaunchFrame() {
            guard
                islands.isEmpty,
                let snapshot = launch.cached(),
                snapshot.entries.allSatisfy({ NativeIslandsRegistry.factories.entry(for: $0.type) != nil })
            else {
                return
            }
            var shown: [NativeIslandsLaunchCache.Entry] = []
            for entry in snapshot.entries {
                let id = entry.component.id
                _ = state.registerType(id: id, type: entry.type)
                guard let island = constructIsland(id: id, type: entry.type) else { continue }
                island.create(properties: entry.properties)
                shown.append(entry)
            }
            guard !shown.isEmpty else { return }
            let ids = Set(shown.map(\.component.id))
            _ = container.applyLedger(
                components: shown.map(\.component),
                scrollContainers: [],
                order: snapshot.order.filter { ids.contains($0) },
                exclusions: [:],
                cutouts: [:]
            )
            container.setCompositingActive(
                shown.contains { $0.component.plane == .underlay },
                canvasColor: NICanvasColor(snapshot.canvasColor)?.uiColor
            )
            launch.show(shown, canvasColor: snapshot.canvasColor)
        }

        func saveLaunchFrame() {
            guard launchSave == nil, launch.saving else { return }
            launchSave = NativeIslandsCommitObserver(order: NativeIslandsCommitObserver.launchSaveOrder) { [weak self] in
                self?.flushLaunchSave()
            }
        }

        /// Saves the launch frame now, if a save is waiting.
        private func flushLaunchSave() {
            guard launchSave != nil else { return }
            launch.save(order: container.order, components: container.components, type: state.type(for:))
            // Released last: its observer can be what runs this.
            launchSave = nil
        }

        private func destroyIslands() {
            container.removeAllIslands()
            islands.values.forEach { $0.onDestroy() }
            islands.removeAll()
            launch.forgetAll()
            state.reset()
        }

        /// Mounts island `id` if it is not yet, then delivers the commands sent before it was.
        private func ensureIsland(
            id: String,
            type: String
        )
            -> Bool {
            guard let island = islands[id] ?? constructIsland(id: id, type: type) else { return false }
            for pending in state.drain(id: id) {
                deliver(id: id, islands[id] ?? island, command: pending.command, properties: pending.payload)
            }
            return true
        }

        private func constructIsland(id: String, type: String, replacing: Bool = false) -> NativeIsland? {
            guard let registration = NativeIslandsRegistry.factories.entry(for: type) else {
                reportError(id: id, reason: "unknown_type:\(type)")
                return nil
            }
            let component: NativeIsland
            do {
                component = try registration.factory()
            } catch {
                reportError(id: id, reason: "handler_failed: factory_failed:\(type):\(String(describing: Swift.type(of: error)))")
                return nil
            }
            islands[id] = component
            bindEventSink(id: id, component: component)
            installContainer()
            if replacing {
                container.replaceIslandView(id: id, view: component.view)
            } else {
                container.registerIsland(id: id, view: component.view, accessibility: registration.accessibility)
            }
            if resumed {
                component.onResume()
            } else {
                component.onPause()
            }
            return component
        }

        private func bindEventSink(id: String, component: NativeIsland) {
            guard let emitting = component as? NativeIslandEventEmitting else { return }
            emitting.eventSink = { [weak self, weak component] event, payload in
                guard let self, let component else { return }
                onMain {
                    // A replaced or moved island's view must not speak for the one now at `id`.
                    guard self.islands[id] === component else { return }
                    var data = payload
                    data["island"] = id
                    if let instance = self.state.instance(for: id) {
                        data["instance"] = instance
                    }
                    self.events(event, data)
                }
            }
        }

        private func deliver(
            id: String,
            _ island: NativeIsland,
            command: NIIslandCommand,
            properties: [String: Any]
        ) {
            switch command {
            case .create(let instance):
                if launch.created(id, properties: properties) {
                    // The launch frame already created this view; the page's create updates it.
                    _ = state.create(id: id, instance: instance)
                    island.update(properties: properties)
                    saveLaunchFrame()
                    return
                }
                switch state.create(id: id, instance: instance) {
                case .create:
                    island.create(properties: properties)
                case .update:
                    island.update(properties: properties)
                case .recreate:
                    (island as? NativeIslandEventEmitting)?.eventSink = nil
                    guard let type = state.type(for: id),
                          let replacement = constructIsland(id: id, type: type, replacing: true)
                    else {
                        container.removeIsland(id: id)
                        islands[id] = nil
                        launch.forget(id)
                        island.onDestroy()
                        return
                    }
                    island.onDestroy()
                    replacement.create(properties: properties)
                }
            case .update:
                launch.merge(id, properties: properties)
                island.update(properties: properties)
            }
            saveLaunchFrame()
        }

        /// Gives a component with no island yet the view of an island of its type the layout no longer
        /// shows: one in the same portal, or one the launch frame made.
        private func handOverIslands(
            to components: [(IslandComponent, String)],
            launchFrameShowing: Bool
        ) {
            let activeIncomingIDs = Set(
                components.filter(\.0.active).map(\.0.id)
            )
            for (component, type) in components {
                guard component.active, islands[component.id] == nil else { continue }
                let donorID = findDonorID(
                    for: component,
                    type: type,
                    activeIncomingIDs: activeIncomingIDs,
                    launchFrameShowing: launchFrameShowing
                )
                guard
                    let donorID,
                    let donorIsland = islands.removeValue(forKey: donorID)
                else {
                    continue
                }
                islands[component.id] = donorIsland
                bindEventSink(id: component.id, component: donorIsland)
                state.transfer(from: donorID, to: component.id)
                launch.transfer(from: donorID, to: component.id)
                container.transferIsland(from: donorID, to: component.id)
            }
        }

        private func findDonorID(
            for component: IslandComponent,
            type: String,
            activeIncomingIDs: Set<String>,
            launchFrameShowing: Bool
        )
            -> String? {
            let candidates = islands.keys.sorted().filter { id in
                id != component.id &&
                    !activeIncomingIDs.contains(id) &&
                    state.type(for: id) == type
            }
            if let portal = component.portal,
               let match = candidates.first(where: { container.components[$0]?.portal == portal }) {
                return match
            }
            if launchFrameShowing,
               let match = candidates.first(where: launch.isUnclaimed) {
                return match
            }
            return nil
        }
    }
#endif
