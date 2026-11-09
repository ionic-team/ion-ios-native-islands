#if canImport(UIKit)
    import QuartzCore

    /// Calls `handler` each time the main run loop is about to wait, in `order` relative to Core
    /// Animation's commit at 2_000_000, until released.
    final class NativeIslandsCommitObserver {
        /// A fenced layout is released before motions are matched to what WebKit committed in the
        /// same pass.
        static let paintFenceOrder: CFIndex = 1_999_998
        static let motionSyncOrder: CFIndex = 1_999_999
        /// The launch frame is cached after the commit: nothing on screen waits for it.
        static let launchSaveOrder: CFIndex = 2_000_001

        private let observer: CFRunLoopObserver

        init(order: CFIndex, _ handler: @escaping () -> Void) {
            self.observer = CFRunLoopObserverCreateWithHandler(
                kCFAllocatorDefault,
                CFRunLoopActivity.beforeWaiting.rawValue,
                true,
                order
            ) { _, _ in
                handler()
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        deinit {
            CFRunLoopObserverInvalidate(observer)
        }
    }
#endif
