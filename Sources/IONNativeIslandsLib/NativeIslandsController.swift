#if canImport(UIKit)
import Foundation
import UIKit
import WebKit
#if canImport(IONNativeIslandsCore)
import IONNativeIslandsCore
#endif

/// The islands runtime behind any bridge: owns the container, island instances, and
/// lifecycle state; parses layout/animation/reposition payloads; dispatches commands with
/// the security policy; and emits native→web events through the injected sink. The
/// Capacitor and Cordova plugin classes are thin marshalling shells over this type — one
/// runtime, two transports.
public final class NativeIslandsController {
    private let container = NativeIslandsContainer()
    private var islands: [String: NativeIsland] = [:]
    private let lifecycleState = NIIslandLifecycleState<[String: Any]>()
    private let security: NIBridgeSecurity
    /// Native→web event sink (the plugin's `notifyListeners`).
    private let events: (_ event: String, _ payload: [String: Any]) -> Void

    private var containerInstalled = false
    private weak var webView: WKWebView?
    private var memoryWarningObserver: NSObjectProtocol?
    private var lifecycleObservers: [NSObjectProtocol] = []

    public init(
        security: NIBridgeSecurity,
        events: @escaping (_ event: String, _ payload: [String: Any]) -> Void
    ) {
        self.security = security
        self.events = events
    }

    // MARK: container

    /// Idempotent Path-A install: re-parents the WebView into the container (above the
    /// island hosts) and makes it transparent so islands behind composite through.
    /// Self-no-ops until the WebView is in a view hierarchy; retried from applyLayout.
    public func ensureContainer(webView: WKWebView?) {
        if let webView { self.webView = webView }
        guard !containerInstalled, let webView = self.webView, let parent = webView.superview else { return }
        containerInstalled = true
        container.frame = parent.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(container)
        container.attach(webView: webView)
        // BATTERY: islands pause live sensors while scrolled offscreen (container reports changes).
        container.onIslandVisibility = { [weak self] id, visible in
            self?.islands[id]?.setViewportVisible(visible)
        }
        // Memory pressure reaches the web as an EVENT; policy is app-level
        // (NativeIslands.listen('memoryPressure') → degradeIsland of the app's choosing).
        if memoryWarningObserver == nil {
            memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.events("memoryPressure", ["level": "critical"])
            }
        }
        if lifecycleObservers.isEmpty {
            lifecycleObservers = [
                NotificationCenter.default.addObserver(
                    forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    self?.islands.values.forEach { $0.onPause() }
                },
                NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    self?.islands.values.forEach { $0.onResume() }
                }
            ]
        }
        NIStartupTrace.mark("containerInstalled")
        installT1Router()
        installDebugBootHooks(webView: webView)
        NSLog("NI: container installed; webView.isOpaque=\(webView.isOpaque) parent=\(type(of: parent))")
    }

    public func dispose() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
        if NIVirtualHttp.router != nil {
            NIVirtualHttp.router = nil
            NIVirtualHttp.allowedOrigins = []
        }
        for island in islands.values { island.destroy() }
        islands.removeAll()
        lifecycleState.clear()
        container.detachWebView()
        container.removeFromSuperview()
    }

    // MARK: layout operations (inputs are bridge-decoded [String: Any] payloads)

    public func applyLayout(
        components componentsRaw: [[String: Any]],
        order: [String],
        exclude excludeRaw: [String: Any],
        glass glassRaw: [[String: Any]]
    ) {
        NIStartupTrace.mark("firstApplyLayout")
        var parsedComponents: [(component: IslandComponent, type: String)] = []
        for item in componentsRaw {
            guard let id = item["id"] as? String else { continue }
            let type = item["type"] as? String ?? ""
            parsedComponents.append((IslandComponent(
                id: id,
                rect: Self.rect(from: item["rect"] as? [String: Any]),
                z: (item["z"] as? Int) ?? 0,
                interactive: (item["interactive"] as? Bool) ?? false,
                active: (item["active"] as? Bool) ?? false,
                overlay: (item["overlay"] as? Bool) ?? false,
                fixedPos: (item["fixedPos"] as? Bool) ?? false), type))
        }
        var exclude: [String: [IslandRect]] = [:]
        for (id, value) in excludeRaw {
            if let arr = value as? [[String: Any]] {
                exclude[id] = arr.compactMap { Self.rect(from: $0) }
            }
        }
        let glass: [IslandRect] = glassRaw.compactMap { Self.rect(from: $0) }

        DispatchQueue.main.async {
            var components: [IslandComponent] = []
            for parsed in parsedComponents {
                let component = parsed.component
                let type = parsed.type
                guard self.lifecycleState.registerType(id: component.id, type: type) else {
                    self.reportIslandErrorOnMain(
                        id: component.id,
                        reason: "invalid_request: ledger type does not match the command registration")
                    continue
                }
                if component.active {
                    do {
                        let custom = NativeIslandsRegistry.entry(for: type)
                        try self.security.validateActivation(
                            type: type,
                            origin: self.currentOrigin(),
                            customCapability: custom?.capability)
                        self.ensureIslandOnMain(id: component.id, type: type, custom: custom)
                    } catch let error as NIBridgeSecurityError {
                        self.reportIslandErrorOnMain(id: component.id, reason: "\(error.code): \(error.message)")
                    } catch {
                        self.reportIslandErrorOnMain(
                            id: component.id, reason: "internal_error: activation validation failed")
                    }
                }
                components.append(component)
            }
            let liveIds = Set(components.map(\.id))
            let staleIds = self.islands.keys.filter { !liveIds.contains($0) }
            for id in staleIds {
                guard let island = self.islands[id] else { continue }
                if NativeIslandsRegistry.isPersistent(self.lifecycleState.type(for: id)) {
                    if !self.lifecycleState.isAwaitingAdoption(id: id) { island.onPause() }
                    self.lifecycleState.markAwaitingAdoption(id: id)
                } else {
                    island.destroy()
                    self.islands[id] = nil
                    self.lifecycleState.removeType(id: id)
                    self.container.removeIsland(id: id)
                }
            }
            self.ensureContainer(webView: self.webView)
            self.container.applyLedger(components: components, order: order, exclude: exclude)
            // Zero active islands → opaque WebView (no full-screen alpha blend to pay).
            self.container.setCompositingActive(components.contains { $0.active })
            self.container.applyGlass(glass)
        }
    }

    public func animateLayout(animations: [[String: Any]]) {
        var tracks: [IslandAnimationTrack] = []
        for item in animations {
            guard let id = item["id"] as? String,
                  let duration = Self.num(item["durationMs"]), duration > 0, duration <= 30_000,
                  let frameObjects = item["frames"] as? [[String: Any]] else { continue }
            let frames = frameObjects.compactMap { frame -> IslandAnimationFrame? in
                guard let at = Self.num(frame["at"]),
                      let rect = Self.rect(from: frame["rect"] as? [String: Any]) else { return nil }
                return IslandAnimationFrame(at: at, rect: rect)
            }
            let exclusionTargets: [(island: String, index: Int)] =
                (item["exclusionTargets"] as? [[String: Any]] ?? []).compactMap { target in
                    guard let island = target["island"] as? String,
                          let index = (target["index"] as? NSNumber)?.intValue,
                          index >= 0 else { return nil }
                    return (island, index)
                }
            if frames.count >= 2 && frames.count <= 121 {
                tracks.append(IslandAnimationTrack(
                    id: id, duration: TimeInterval(duration / 1000), frames: frames,
                    exclusionTargets: exclusionTargets))
            }
        }
        DispatchQueue.main.async { self.container.animateLayout(tracks) }
    }

    /// Drag fast-path: reposition islands by pure translation, no full ledger re-apply.
    public func reposition(moves movesRaw: [String: Any]) {
        var moves: [String: CGPoint] = [:]
        for (id, value) in movesRaw {
            if let o = value as? [String: Any], let x = Self.num(o["x"]), let y = Self.num(o["y"]) {
                moves[id] = CGPoint(x: x, y: y)
            }
        }
        DispatchQueue.main.async { self.container.reposition(moves) }
    }

    /// Page navigation/reload: the incoming page's runtime calls this FIRST (and the outgoing
    /// page best-effort on pagehide) so islands from the previous document never linger behind
    /// the new one. Persistent-type engines pause and await adoption instead of dying.
    public func reset() {
        DispatchQueue.main.async {
            var kept: Set<String> = []
            var removed: [String] = []
            for (id, island) in self.islands {
                if NativeIslandsRegistry.isPersistent(self.lifecycleState.type(for: id)) {
                    island.onPause()
                    kept.insert(id)
                } else {
                    island.destroy()
                    island.view.removeFromSuperview()
                    removed.append(id)
                }
            }
            for id in removed {
                self.islands[id] = nil
                self.lifecycleState.removeType(id: id)
            }
            // The runtime outlives page navigations; the new document must re-evaluate every
            // island fresh or a type that errored once stays silent forever.
            self.lifecycleState.reset(keeping: kept)
            self.container.removeAllIslands(keeping: kept)
        }
    }

    // MARK: command dispatch

    /// The one command dispatcher — shared by every transport (Capacitor call, T1 virtual
    /// HTTP, Cordova exec), so a command behaves identically whichever carried it.
    /// Always completes on main.
    public func dispatchCommand(version: Int, contractDigest: String, island: String,
                                requestedType: String, method: String,
                                params: [String: Any], origin: String?,
                                completion: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            if let type = self.lifecycleState.type(for: island), type != requestedType {
                completion(["code": "invalid_request", "error": "island type does not match registered ledger type"])
                return
            }
            let type = requestedType
            let custom = NativeIslandsRegistry.entry(for: type)
            do {
                try self.security.validateCommand(
                    version: version, contractDigest: contractDigest,
                    island: island, type: type, method: method, params: params, origin: origin,
                    customCommands: custom?.allowedCommands,
                    customCapability: custom?.capability,
                    customPermission: custom?.permission,
                    customCommandPermissions: custom?.commandPermissions)
            } catch let error as NIBridgeSecurityError {
                completion(["code": error.code, "error": error.message])
                return
            } catch {
                completion(["code": "internal_error", "error": "command validation failed"])
                return
            }
            // Rejected commands must not reserve/poison an id used by a later valid ledger.
            self.lifecycleState.registerType(id: island, type: requestedType)

            if island == "__page", type == "__page", method == "setBackdrop", let hex = params["color"] as? String {
                self.container.setBackdrop(hex: hex)
                completion(["value": true])
                return
            }
            let target = self.islands[island]
            // Value-returning commands (a capture, a measurement) resolve when ready.
            if let responding = target as? NativeIslandResponding {
                let handled = responding.command(method, params) { result in
                    let payload: [String: Any] = result ?? [:]
                    do {
                        try self.security.validateResponse(payload)
                        completion(payload)
                    } catch let error as NIBridgeSecurityError {
                        completion(["code": error.code, "error": error.message])
                    } catch {
                        completion(["code": "internal_error", "error": "response validation failed"])
                    }
                }
                if handled { return }
            }
            if let target = target {
                target.command(method, params)
            } else if self.lifecycleState.isErrored(id: island) {
                // This island's mount already failed. Answering the command with an error makes
                // the failure DETERMINISTIC for the caller: the element's mountCommand rejects →
                // degradeToFallback, independent of whether the one-shot `islandError` event
                // found a listener (it races page navigation and listener install).
                completion(["code": "handler_failed", "error": "mount_failed: island \(island) has no native side"])
                return
            } else {
                self.lifecycleState.buffer(id: island, method: method, payload: params)
            }
            completion(["value": NSNull()])
        }
    }

    // MARK: island creation

    private func ensureIslandOnMain(
        id: String,
        type: String,
        custom: NIIslandFactoryRegistration<() throws -> NativeIsland>?
    ) {
        if let existing = islands[id] {
            if lifecycleState.consumeAdoption(id: id), UIApplication.shared.applicationState == .active {
                existing.onResume()
            }
            for command in lifecycleState.drain(id: id) {
                existing.command(command.method, command.payload)
            }
            return
        }
        let construction = NIFactoryConstruction.run(custom?.factory)
        let island: NativeIsland
        switch construction {
        case let .created(created):
            island = created
        case .missing:
            // B5 native half: version-skew/unknown types become explicit web fallback.
            reportIslandErrorOnMain(id: id, reason: "unknown_type:\(type)")
            return
        case let .failed(errorType):
            // Expose only the stable error type. A fallible factory may log private detail
            // natively before throwing.
            reportIslandErrorOnMain(
                id: id,
                reason: "handler_failed: factory_failed:\(type):\(errorType)"
            )
            return
        }
        islands[id] = island
        if UIApplication.shared.applicationState != .active {
            island.onPause()
        }
        // Native→web events: the sink injects the island id, so every payload satisfies the
        // `{island, ...payload}` envelope regardless of what the island emits.
        if let emitting = island as? NativeIslandEventEmitting {
            emitting.eventSink = { [weak self] event, payload in
                var enveloped = payload
                enveloped["island"] = id
                self?.events(event, enveloped)
            }
        }
        let accessibilityOwner = custom?.accessibilityOwner
            ?? NIBridgeContract.accessibilityOwners[type]
            ?? "web"
        container.registerIsland(
            id: id,
            view: island.view,
            overlay: island.overlay,
            accessibilityOwner: accessibilityOwner
        )
        // Replay commands buffered before the island existed (e.g. the initial camera).
        for command in lifecycleState.drain(id: id) {
            island.command(command.method, command.payload)
        }
    }

    private func reportIslandErrorOnMain(id: String, reason: String) {
        if lifecycleState.markErrored(id: id) {
            events("islandError", ["island": id, "reason": reason])
        }
    }

    // MARK: captures + diagnostics

    /// Capture the COMPOSED scene — islands + transparent WebView as actually rendered.
    /// drawHierarchy(afterScreenUpdates:false) snapshots the container from the render server,
    /// so video previews / Metal surfaces / the alpha-blended web all land in ONE image.
    public func captureScene(_ completion: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            let bounds = self.container.bounds
            guard bounds.width > 1, bounds.height > 1 else { completion([:]); return }
            // ~800px longest side, quality 0.55, encode OFF-MAIN — the render-server snapshot
            // is the only main-thread work.
            let maxDim: CGFloat = 800
            let scale = min(1, maxDim / max(bounds.width, bounds.height))
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
                self.container.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let jpeg = image.jpegData(compressionQuality: 0.55) else { completion([:]); return }
                completion(["value": "data:image/jpeg;base64," + jpeg.base64EncodedString()])
            }
        }
    }

    /// Per-island view snapshots — reads island VIEWS, never the window.
    public func captureIslands(_ completion: @escaping ([[String: String]]) -> Void) {
        DispatchQueue.main.async {
            let targets = Array(self.islands)
            guard !targets.isEmpty else { completion([]); return }
            var out: [[String: String]] = []
            var remaining = targets.count
            let finish = {
                remaining -= 1
                if remaining == 0 { completion(out) }
            }
            for (id, island) in targets {
                island.captureFrame { image in
                    DispatchQueue.global(qos: .userInitiated).async {
                        if let image = image, let jpeg = image.jpegData(compressionQuality: 0.6) {
                            let frame = "data:image/jpeg;base64," + jpeg.base64EncodedString()
                            DispatchQueue.main.async {
                                out.append(["island": id, "frame": frame])
                                finish()
                            }
                        } else {
                            DispatchQueue.main.async { finish() }
                        }
                    }
                }
            }
        }
    }

    /// Content-free native paint/input state for the async web diagnostic report.
    public func diagnosticSnapshot(_ completion: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            completion(self.container.diagnosticSnapshot())
        }
    }

    public func currentOrigin() -> String? {
        var currentURL: URL?
        if Thread.isMainThread {
            currentURL = webView?.url
        } else {
            DispatchQueue.main.sync { currentURL = self.webView?.url }
        }
        guard let url = currentURL, let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    // MARK: virtual HTTP (opt-in)

    /// Route `fetch('ni://bridge/v1/…')` into the dispatcher. Command params ride HEADERS
    /// (base64 JSON) because Android's interceptor cannot read bodies — one protocol, two
    /// backends. `/v1/ping` echoes what the scheme handler actually delivered.
    private func installT1Router() {
        NIVirtualHttp.router = { [weak self] method, path, headers, body, respond in
            func json(_ obj: [String: Any], status: Int = 200) {
                let data = (try? NIWireCodec.encode(obj)) ?? Data("{}".utf8)
                respond(status, [:], data)
            }
            guard let self = self else { json(["error": "islands runtime gone"], status: 503); return }
            switch path {
            case "/v1/ping":
                NSLog("NI T1 ping: method=%@ headers=%d echo=%@ bodyBytes=%d",
                      method, headers.count, headers["x-ni-echo"] ?? "", body?.count ?? -1)
                json([
                    "ok": true,
                    "transport": "t1-scheme-handler",
                    "headersDelivered": headers.count,
                    "echo": headers["x-ni-echo"] ?? "",
                    "bodyBytes": body?.count ?? -1,
                ])
            case "/v1/command":
                guard let island = headers["x-ni-island"], let type = headers["x-ni-type"],
                      let version = Int(headers["x-ni-version"] ?? ""),
                      let contractDigest = headers["x-ni-contract"],
                      let method2 = headers["x-ni-method"] else {
                    json(["code": "invalid_request", "error": "x-ni-version, x-ni-contract, x-ni-island, x-ni-type and x-ni-method headers required"], status: 400)
                    return
                }
                var params: [String: Any] = [:]
                if let b64 = headers["x-ni-params"] {
                    guard let d = Data(base64Encoded: b64),
                          let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
                        json(["code": "invalid_request", "error": "x-ni-params must be base64 JSON object"], status: 400)
                        return
                    }
                    params = o
                }
                let origin = headers["origin"] ?? self.currentOrigin()
                self.dispatchCommand(version: version, contractDigest: contractDigest,
                                     island: island, requestedType: type, method: method2,
                                     params: params, origin: origin) { result in
                    json(result.isEmpty ? ["value": NSNull()] : result,
                         status: NIHttpStatus.forCode(result["code"] as? String))
                }
            default:
                json(["error": "no route for \(path)"], status: 404)
            }
        }
    }

    /// Simulator-agent debug hooks (launch env isn't settable on normal installs):
    /// NI_BOOT_JS evaluates once after boot; NI_AFTER_BOOT_JS after its navigation settles;
    /// NI_T1_SPIKE drives the T1 transport proof through the DevTools Network panel.
    private func installDebugBootHooks(webView: WKWebView) {
        if ProcessInfo.processInfo.environment["NI_T1_SPIKE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak webView] in
                let js = """
                (async () => {
                  const out = [];
                  try {
                    const p = await (await fetch('ni://bridge/v1/ping', {headers: {'x-ni-echo': 'hdr-check'}})).json();
                    out.push('ping.ok=' + p.ok, 'ping.echo=' + p.echo, 'ping.headers=' + p.headersDelivered);
                    const pb = await (await fetch('ni://bridge/v1/ping', {method: 'POST', body: '0123456789'})).json();
                    out.push('postBodyBytes=' + pb.bodyBytes);
                    const c = await fetch('ni://bridge/v1/command', {method: 'POST', headers: {
                      'x-ni-version': '2', 'x-ni-contract': '\(NIBridgeSecurity.contractDigest)',
                      'x-ni-island': 'map', 'x-ni-type': 'map', 'x-ni-method': 'setCamera',
                      'x-ni-params': btoa(JSON.stringify({lat: 41.9, lng: 12.49, zoom: 6}))
                    }});
                    out.push('command.status=' + c.status);
                    const ok = await NativeIslands.transport('t1');
                    out.push('transport.switch=' + ok);
                    const v = await NativeIslands.command('map', 'setCamera', {lat: 48.85, lng: 2.29, zoom: 5});
                    out.push('runtimeCommand=ok');
                  } catch (e) { out.push('ERR=' + (e && e.message)); }
                  await fetch('ni://bridge/v1/ping', {headers: {'x-ni-echo': 'RESULTS ' + out.join(' | ')}});
                })()
                """
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
        if let bootJS = ProcessInfo.processInfo.environment["NI_BOOT_JS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak webView] in
                webView?.evaluateJavaScript(bootJS, completionHandler: nil)
            }
        }
        if let afterBootJS = ProcessInfo.processInfo.environment["NI_AFTER_BOOT_JS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak webView] in
                webView?.evaluateJavaScript(afterBootJS) { _, error in
                    if let error = error { NSLog("NI after-boot JS failed: %@", error.localizedDescription) }
                }
            }
        }
    }

    // MARK: payload helpers

    private static func rect(from obj: [String: Any]?) -> IslandRect? {
        guard let o = obj, let x = num(o["x"]), let y = num(o["y"]),
              let w = num(o["w"]), let h = num(o["h"]) else { return nil }
        return IslandRect(x: x, y: y, w: w, h: h, r: num(o["r"]) ?? 0)
    }

    private static func num(_ value: Any?) -> CGFloat? {
        if let n = value as? NSNumber { return CGFloat(n.doubleValue) }
        return nil
    }
}
#endif
