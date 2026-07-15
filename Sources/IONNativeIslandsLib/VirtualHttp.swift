#if canImport(UIKit)
import Foundation
import WebKit

/// T1 — virtual HTTP (docs/ARCHITECTURE.md §5.5): the web calls standard `fetch()`, native intercepts in-process
/// via a custom scheme handler. No socket, no port, request/response-native — and every call shows up
/// in the DevTools/Web-Inspector **Network panel** with status, timing, and response body (the
/// debuggability the message-handler bridge can never give you).
///
/// v1 protocol (identical on Android, where `shouldInterceptRequest` CANNOT read request bodies —
/// that asymmetry, not iOS, sets the floor):
///   POST ni://bridge/v1/command     headers: x-ni-island, x-ni-method, x-ni-params (base64 UTF-8 JSON)
///                                   → 200 {"value": …}
///   GET  ni://bridge/v1/ping        → 200 echo diagnostics: header/body delivery evidence (the §5.5
///                                   spike data: does the scheme handler deliver headers? POST bodies?)
///   OPTIONS *                       → 204 + CORS (the page origin is capacitor://localhost, so every
///                                   fetch here is cross-origin and preflights)
///
/// The handler must be registered on the WKWebViewConfiguration BEFORE the WebView exists, which is
/// before the plugin exists — so the handler is inert plumbing that routes through `NIVirtualHttp.router`,
/// installed later by the plugin's load(). Requests before that get 503 (the page retries or falls back).
public enum NIVirtualHttp {
    public static let scheme = "ni"
    public static var allowedOrigins: Set<String> = []

    /// Installed by NativeIslandsPlugin.load(). (method, path, headers, body, respond) — respond may be
    /// called async from any thread.
    public static var router: ((_ method: String, _ path: String, _ headers: [String: String],
                                _ body: Data?, _ respond: @escaping (Int, [String: String], Data) -> Void) -> Void)?
}

public final class NIVirtualHttpHandler: NSObject, WKURLSchemeHandler {

    /// Tasks WebKit has stopped — responding to one crashes; every async respond checks first.
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let req = urlSchemeTask.request
        guard let url = req.url else { return }
        let method = req.httpMethod ?? "GET"
        var headers: [String: String] = [:]
        for (k, v) in req.allHTTPHeaderFields ?? [:] { headers[k.lowercased()] = v }
        let body = req.httpBody // §5.5 spike: observe whether WebKit delivers this at all

        if let origin = headers["origin"], !NIVirtualHttp.allowedOrigins.contains(origin) {
            respond(urlSchemeTask, status: 403, headers: ["Content-Type": "application/json"],
                    data: Data(#"{"code":"permission_denied","error":"origin not allowed"}"#.utf8))
            return
        }

        if method == "OPTIONS" {
            respond(urlSchemeTask, status: 204, headers: [:], data: Data())
            return
        }
        guard let router = NIVirtualHttp.router else {
            respond(urlSchemeTask, status: 503, headers: ["Content-Type": "application/json"],
                    data: Data(#"{"error":"bridge not ready"}"#.utf8))
            return
        }
        let taskId = ObjectIdentifier(urlSchemeTask)
        router(method, url.path, headers, body) { [weak self, weak urlSchemeTask] status, extra, data in
            DispatchQueue.main.async {
                guard let self = self, let task = urlSchemeTask else { return }
                self.lock.lock()
                let dead = self.stopped.remove(taskId) != nil
                self.lock.unlock()
                if dead { return }
                var h = extra
                if h["Content-Type"] == nil { h["Content-Type"] = "application/json" }
                self.respond(task, status: status, headers: h, data: data)
            }
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        stopped.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }

    private func respond(_ task: WKURLSchemeTask, status: Int, headers: [String: String], data: Data) {
        var h = headers
        // CORS is restricted to the same configured origin policy as command dispatch.
        if let origin = task.request.value(forHTTPHeaderField: "Origin"),
           NIVirtualHttp.allowedOrigins.contains(origin) {
            h["Access-Control-Allow-Origin"] = origin
            h["Vary"] = "Origin"
        }
        h["Access-Control-Allow-Headers"] = "*"
        h["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
        h["Access-Control-Max-Age"] = "600"
        h["Content-Length"] = String(data.count)
        guard let url = task.request.url,
              let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: h) else { return }
        task.didReceive(resp)
        if !data.isEmpty { task.didReceive(data) }
        task.didFinish()
    }
}
#endif
