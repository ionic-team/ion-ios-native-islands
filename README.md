# IONNativeIslandsLib

The iOS runtime for Native Islands. It places app-owned native views in a web
document, attaches document islands to the public `WKWebView` scroll hierarchy,
clips their declared rounded shape, preserves CSS paint order, and assigns each
gesture to one owner at touch-down. Transparent rounded corners remain owned by the
web layer.

Capacitor and Cordova bridge packages consume this library. App and plugin authors
also use it to register their own native component factories.

## Installation

Swift Package Manager:

```swift
dependencies: [
    .package(
        url: "https://github.com/ionic-team/ion-ios-native-islands.git",
        from: "1.0.0"
    )
]
```

CocoaPods:

```ruby
pod 'IONNativeIslandsLib', '~> 1.0'
```

## Register a native component

Register before the first page mounts the component, such as from a Capacitor
plugin's `load()`, a Cordova plugin's `pluginInitialize()`, or app startup:

```swift
NativeIslandsRegistry.register(
    componentName: "app.badge",
    accessibility: .web
) {
    BadgeIsland()
}
```

`.web` keeps hidden web semantics as the accessibility owner. Use `.native` only when
the native view intentionally owns and exposes the accessible interface. The
matching `defineNativeIsland` call must use the same ownership (`web` is the
default; set `accessibility: "native"` for `.native`) so only one semantic face
exists.

Implement the small component contract:

```swift
final class BadgeIsland:
    NativeIsland,
    NativeIslandEventEmitting
{
    private let badge = BadgeView()

    var view: UIView { badge }
    var eventSink: ((String, [String: Any]) -> Void)?

    func create(properties: [String: Any]) {
        update(properties: properties)
    }

    func update(properties: [String: Any]) {
        if let count = properties["count"] as? Int {
            badge.count = count
        }
    }

    func onDestroy() {
        badge.release()
    }
}
```

The runtime accepts only `create` and `update`. It validates component identity and
JSON compatibility before calling the component. Each `create` call includes the web
instance ID. Matching the current instance updates the existing component, while a new
instance replaces it with a fresh component from the factory.
`NativeIslandEventEmitting` is optional and stamps emitted payloads with the island ID
and instance. Events from replaced or disposed components are ignored.

`applyLayout` passes the applied page-clock timestamp to its completion closure, or
`nil` if a newer layout superseded a pending retry.

`onResume`, `onPause`, `onDestroy`, and `setViewportVisible` have default
implementations. Components that own active resources should use those callbacks
to stop work while backgrounded, offscreen, or disposed.

## Whole-scene effects

Shell integrations can find the rigid native scene that contains the WebView and
every island plane:

```swift
let scene = NativeIslandsScenes.find(webView: webView)
```

Move or wrap `scene` for effects such as pull-to-refresh or a whole-page transition.
Do not move the WebView or individual island hosts separately.

## Errors

Command failures use the codes `invalid_request`, `unknown_command`, `handler_failed`,
and `internal_error`. A factory failure emits `islandError` for only the affected
component.

## Requirements

- iOS 15+
- Swift 5.9+
- Xcode 16+

## License

MIT. See [LICENSE](LICENSE).

## Support

Report issues on the
[issue tracker](https://github.com/ionic-team/ion-ios-native-islands/issues).
