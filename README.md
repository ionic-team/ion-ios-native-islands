# IONNativeIslandsLib

The iOS native library for Native Islands: real platform views composited into web
content at arbitrary z-index. It hosts island views behind (or above) a transparent
WKWebView, keeps them glued to the page through compositor-side scroll riding, routes
touches to whichever layer owns them, and enforces a per-type command/permission policy
for every island an app or plugin registers.

This library is consumed by the bridge plugins (`@capacitor/native-islands`,
`cordova-outsystems-native-islands`). Depend on it directly when a native plugin
registers its own island types.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/ionic-team/ion-ios-native-islands.git", from: "1.0.0")
]
```

### CocoaPods

```ruby
pod 'IONNativeIslandsLib', '~> 1.0'
```

## Usage

### Registering an island

An island type is a native view factory plus its command policy. Register it before the
first page that uses it lays out — a Capacitor plugin's `load()`, a Cordova plugin's
`pluginInitialize`, or the app delegate are all early enough:

```swift
NativeIslandsRegistry.register(
    type: "acme.badge",
    allowedCommands: ["create", "setCount", "setTheme"],
    capability: "acme.badge",
    permission: "acme.badge.view"
) { AcmeBadgeIsland() }
```

The web side references the type from markup (`defineIsland` in the JS package); the
host app grants `capability` and `permission` in its plugin configuration. A type whose
permission the app has not granted degrades to its web fallback at mount — nothing
crashes and nothing renders half-native.

### Island protocol

```swift
final class AcmeBadgeIsland: NativeIsland, NativeIslandEventEmitting {
    private let badge = BadgeView()
    var view: UIView { badge }
    var eventSink: ((String, [String: Any]) -> Void)?

    func command(_ method: String, _ params: [String: Any]) {
        switch method {
        case "create", "setCount":
            if let count = params["count"] as? Int { badge.count = count }
        default:
            break
        }
    }
}
```

- `NativeIslandResponding` — implement for commands that answer with a value; the
  controller tries it first and falls through to `command` when it returns `false`.
- `NativeIslandEventEmitting` — the controller installs `eventSink` and stamps every
  payload with the island id, so events always reach the web as `{island, ...payload}`.
- `TouchObserverView` — receive touch coordinates at native event rate without taking
  ownership of the gesture (a page scroll stays a page scroll).
- `IslandHostView` — a host view that reports layout passes, so geometry-dependent
  props apply only once the island has a real size.

### Container integration

The bridge plugins own container installation. An embedder wiring the library directly
creates the controller against its security policy and hands it the WKWebView:

```swift
let controller = NativeIslandsController(security: security) { event, payload in
    // deliver to web
}
controller.ensureContainer(webView: webView)
```

## Error handling

Command dispatch answers with typed codes rather than exceptions: `invalid_request`,
`unknown_command`, `permission_denied`, `handler_failed`, `payload_too_large`,
`unsupported_version`, `internal_error`. A failed island mount reports `islandError`
to the web and degrades only that island.

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 16+

## License

`IONNativeIslandsLib` is available under the MIT license. See the [LICENSE](LICENSE)
file for more info.

## Support

- Report issues on the [issue tracker](https://github.com/ionic-team/ion-ios-native-islands/issues)
