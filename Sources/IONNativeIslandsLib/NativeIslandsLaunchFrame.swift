#if canImport(UIKit)
    import Foundation
    import UIKit

    enum NativeIslandsLaunchCache {
        static let storageKey = "io.ionic.nativeislands.launchCache.v1"

        /// Only layouts from the first moments after launch write the cache: it stands for the screen
        /// the app opens on, not a page the person moved to later.
        static let launchWindow: CFTimeInterval = 3

        struct Entry {
            var component: IslandComponent
            var type: String
            var properties: [String: Any]
        }

        struct Snapshot {
            var canvasColor: String?
            var order: [String]
            var entries: [Entry]
        }

        static func save(
            _ snapshot: Snapshot,
            to defaults: UserDefaults
        ) {
            let serializedEntries: [[String: Any]] = snapshot.entries.compactMap { entry in
                guard
                    let rect = entry.component.rect,
                    JSONSerialization.isValidJSONObject(entry.properties)
                else {
                    return nil
                }
                var item: [String: Any] = [
                    "id": entry.component.id,
                    "type": entry.type,
                    "plane": entry.component.plane.rawValue,
                    "coordinateSpace": entry.component.coordinateSpace.rawValue,
                    "opacity": Double(entry.component.opacity),
                    "rect": [
                        "x": Double(rect.x),
                        "y": Double(rect.y),
                        "w": Double(rect.width),
                        "h": Double(rect.height),
                        "r": [
                            Double(rect.cornerRadii.topLeft),
                            Double(rect.cornerRadii.topRight),
                            Double(rect.cornerRadii.bottomRight),
                            Double(rect.cornerRadii.bottomLeft),
                        ],
                    ],
                    "properties": entry.properties,
                ]
                if let portal = entry.component.portal {
                    item["portal"] = portal
                }
                return item
            }
            guard !serializedEntries.isEmpty else { return }
            var root: [String: Any] = [
                "version": 1,
                "order": snapshot.order,
                "entries": serializedEntries,
            ]
            if let canvasColor = snapshot.canvasColor {
                root["canvasColor"] = canvasColor
            }
            guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
            defaults.set(data, forKey: storageKey)
        }

        static func load(from defaults: UserDefaults) -> Snapshot? {
            guard
                let data = defaults.data(forKey: storageKey),
                let object = try? JSONSerialization.jsonObject(with: data),
                let root = object as? [String: Any],
                (root["version"] as? Int) == 1,
                let rawOrder = root["order"] as? [String],
                let rawEntries = root["entries"] as? [[String: Any]]
            else {
                return nil
            }
            let entries: [Entry] = rawEntries.compactMap { raw in
                guard
                    let id = raw["id"] as? String,
                    !id.isEmpty,
                    let type = raw["type"] as? String,
                    !type.isEmpty,
                    let rawPlane = raw["plane"] as? String,
                    let plane = NIHostPlane(rawValue: rawPlane),
                    let rawSpace = raw["coordinateSpace"] as? String,
                    let space = NICoordinateSpace(rawValue: rawSpace),
                    let rawRect = raw["rect"] as? [String: Any],
                    let rect = NISafeGeometry.parseRect(rawRect)
                else {
                    return nil
                }
                let opacity = NISafeGeometry.strictNumber(raw["opacity"]).map { CGFloat($0) } ?? 1
                let portal = (raw["portal"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let properties = raw["properties"] as? [String: Any] ?? [:]
                let component = IslandComponent(
                    id: id,
                    rect: rect,
                    scrollPath: [],
                    plane: plane,
                    coordinateSpace: space,
                    interactive: false,
                    active: true,
                    opacity: opacity,
                    portal: portal
                )
                return Entry(component: component, type: type, properties: properties)
            }
            guard !entries.isEmpty else { return nil }
            let validIDs = Set(entries.map(\.component.id))
            let order = rawOrder.filter { validIDs.contains($0) }
            guard !order.isEmpty else { return nil }
            return Snapshot(
                canvasColor: root["canvasColor"] as? String,
                order: order,
                entries: entries
            )
        }
    }

    /// Whether the launch frame cached by an earlier run is showing, and since when the page's own
    /// layouts apply.
    private enum LaunchPhase: Equatable {
        case waiting
        case frozen
        case live(since: CFTimeInterval)
    }

    /// The launch frame: the islands an earlier run showed first, shown again as soon as the host is
    /// installed and kept until the page's own layout and creates take them over.
    final class NativeIslandsLaunchFrame {
        var enabled = true
        var store: UserDefaults = .standard
        private var phase = LaunchPhase.waiting
        /// Islands the launch frame created that the page has not created yet.
        private var unclaimed: Set<String> = []
        /// Each island's properties as last created or updated, cached with it.
        private var properties: [String: [String: Any]] = [:]
        private var canvasColor: String?

        /// Whether the launch frame shows, until the page lays out.
        var showing: Bool {
            phase == .frozen
        }

        /// The frame to show, while the cache is on and the page has shown nothing yet.
        func cached() -> NativeIslandsLaunchCache.Snapshot? {
            guard enabled, phase == .waiting else { return nil }
            return NativeIslandsLaunchCache.load(from: store)
        }

        /// The launch frame is showing `entries`, created with their cached properties.
        func show(_ entries: [NativeIslandsLaunchCache.Entry], canvasColor: String?) {
            for entry in entries {
                properties[entry.component.id] = entry.properties
                unclaimed.insert(entry.component.id)
            }
            self.canvasColor = canvasColor
            phase = .frozen
        }

        /// The page laid out: its layouts apply from now. Returns whether the launch frame was showing.
        func pageLaidOut(canvasColor: String?) -> Bool {
            let wasFrozen = phase == .frozen
            if wasFrozen || phase == .waiting {
                phase = .live(since: CACurrentMediaTime())
            }
            self.canvasColor = canvasColor
            return wasFrozen
        }

        /// A host disposed while the launch frame shows shows it again when next installed.
        func rewind() {
            if phase == .frozen {
                phase = .waiting
            }
        }

        /// The page created island `id` with `properties`. True when the launch frame made it, so the
        /// page's create updates that view rather than creating another.
        func created(_ id: String, properties: [String: Any]) -> Bool {
            self.properties[id] = properties
            return unclaimed.remove(id) != nil
        }

        func merge(_ id: String, properties: [String: Any]) {
            self.properties[id, default: [:]].merge(properties) { _, new in new }
        }

        func isUnclaimed(_ id: String) -> Bool {
            unclaimed.contains(id)
        }

        func transfer(from oldID: String, to newID: String) {
            if let moved = properties.removeValue(forKey: oldID) {
                properties[newID] = moved
            }
            if unclaimed.remove(oldID) != nil {
                unclaimed.insert(newID)
            }
        }

        func forget(_ id: String) {
            properties[id] = nil
            unclaimed.remove(id)
        }

        func forgetAll() {
            properties.removeAll()
            unclaimed.removeAll()
        }

        /// Whether the cache is on and the page laid out within `launchWindow`, so a layout is cached.
        var saving: Bool {
            guard enabled, case .live(let since) = phase else { return false }
            return CACurrentMediaTime() - since <= NativeIslandsLaunchCache.launchWindow
        }

        /// Caches the `components` shown fixed to the screen, in paint `order`, for the next launch,
        /// while `saving`.
        func save(order: [String], components: [String: IslandComponent], type: (String) -> String?) {
            guard saving else { return }
            let entries: [NativeIslandsLaunchCache.Entry] = order.compactMap { id in
                guard
                    let component = components[id],
                    component.active,
                    component.scrollPath.isEmpty,
                    // The cache draws an island square at its rect, unclipped and unstuck.
                    component.transform == nil,
                    component.sticky == nil,
                    component.clips.isEmpty,
                    let rect = component.rect,
                    rect.width > 0,
                    rect.height > 0,
                    let type = type(id)
                else {
                    return nil
                }
                return NativeIslandsLaunchCache.Entry(component: component, type: type, properties: properties[id] ?? [:])
            }
            guard !entries.isEmpty else {
                // A launch screen without islands to show first must not show another screen's.
                store.removeObject(forKey: NativeIslandsLaunchCache.storageKey)
                return
            }
            NativeIslandsLaunchCache.save(
                NativeIslandsLaunchCache.Snapshot(canvasColor: canvasColor, order: entries.map(\.component.id), entries: entries),
                to: store
            )
        }
    }
#endif
