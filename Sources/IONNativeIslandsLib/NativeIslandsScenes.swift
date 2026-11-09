#if canImport(UIKit)
    import UIKit
    import WebKit

    /// Finds the native scene that contains a WebView and all of its island planes.
    public enum NativeIslandsScenes {
        private static let scenes = NSMapTable<WKWebView, UIView>.weakToWeakObjects()

        public static func find(webView: WKWebView) -> UIView? {
            scenes.object(forKey: webView)
        }

        static func register(webView: WKWebView, scene: UIView) {
            scenes.setObject(scene, forKey: webView)
        }

        static func unregister(webView: WKWebView) {
            scenes.removeObject(forKey: webView)
        }
    }
#endif
