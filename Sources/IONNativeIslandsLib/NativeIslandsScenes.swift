import Foundation

final class NIWeakReferenceRegistry<Key: AnyObject, Value: AnyObject> {
    private let values = NSMapTable<Key, Value>.weakToWeakObjects()

    func set(_ value: Value, for key: Key) {
        values.setObject(value, forKey: key)
    }

    func value(for key: Key) -> Value? {
        values.object(forKey: key)
    }

    func removeValue(for key: Key) {
        values.removeObject(forKey: key)
    }
}

#if canImport(UIKit)
    import UIKit
    import WebKit

    /// Finds the native scene that contains a WebView and all of its island planes.
    public enum NativeIslandsScenes {
        private static let scenes = NIWeakReferenceRegistry<WKWebView, UIView>()

        public static func find(webView: WKWebView) -> UIView? {
            scenes.value(for: webView)
        }

        static func register(webView: WKWebView, scene: UIView) {
            scenes.set(scene, for: webView)
        }

        static func unregister(webView: WKWebView) {
            scenes.removeValue(for: webView)
        }
    }
#endif
