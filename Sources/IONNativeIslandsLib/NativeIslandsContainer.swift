#if canImport(UIKit)
import UIKit
import WebKit
#if canImport(IONNativeIslandsCore)
import IONNativeIslandsCore
#endif

/// Document-space rectangle (mirrors the web `Rect`): document coordinates + an
/// optional corner radius for the opaque-region path. Native derives the on-screen
/// position by subtracting the live scroll offset.
public struct IslandRect {
    public var x: CGFloat
    public var y: CGFloat
    public var w: CGFloat
    public var h: CGFloat
    public var r: CGFloat

    public init(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat = 0) {
        self.x = x; self.y = y; self.w = w; self.h = h; self.r = r
    }
}

public struct IslandComponent {
    public var id: String
    public var rect: IslandRect?
    public var z: Int
    public var interactive: Bool
    public var active: Bool
    /// Composites ABOVE the WebView (overlay island, e.g. the native glass sheet).
    public var overlay: Bool
    /// `rect` is in VIEWPORT coords (fixed/sticky web ancestry) — pin, never translate.
    public var fixedPos: Bool

    public init(id: String, rect: IslandRect?, z: Int, interactive: Bool, active: Bool,
                overlay: Bool = false, fixedPos: Bool = false) {
        self.id = id; self.rect = rect; self.z = z; self.interactive = interactive; self.active = active
        self.overlay = overlay; self.fixedPos = fixedPos
    }
}

public struct IslandAnimationFrame {
    public var at: CGFloat
    public var rect: IslandRect
}

public struct IslandAnimationTrack {
    public var id: String
    public var duration: TimeInterval
    public var frames: [IslandAnimationFrame]
    public var exclusionTargets: [(island: String, index: Int)]
}

/// The Native Islands web + native-host + input-routing container, ported from the
/// device-verified Gate-1 / WYWH prototypes into a reusable Capacitor host piece.
///
/// Layer order (back -> front): island host views (z-ordered by the ledger) -> the
/// transparent WKWebView -> (the app's own chrome). The container:
///   - positions island host views in document space and repositions them on scroll
///     by a **pure translation** (KVO on the public `scrollView.contentOffset` — the
///     only WKWebView internal we touch), so **scroll never crosses the bridge**;
///   - hit-tests touch-down to route a gesture to an island or the WebView (Sentinel).
public final class NativeIslandsContainer: UIView {

    /// Snap a point-value to the DEVICE PIXEL grid (fractional-pixel frames composite through
    /// resampling — the blur report). scale-aware: 1/3-point steps on 3x displays are fine.
    private func pxRound(_ v: CGFloat) -> CGFloat {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        return (v * scale).rounded() / scale
    }

    private weak var webView: WKWebView?
    /// island id -> native view (registered by island plugins, e.g. the map).
    private var hosts: [String: UIView] = [:]
    /// island id -> document rect (from the latest ledger).
    private var docRects: [String: IslandRect] = [:]
    /// island id -> document rects of web/native stacked above it (hit-test exclusions).
    private var excludeDoc: [String: [IslandRect]] = [:]
    /// ids of islands that own input; a non-interactive island (e.g. a camera viewfinder)
    /// passes touches to the WebView so web content over it (stickers/captions) is interactive.
    private var interactiveIds: Set<String> = []
    private var order: [String] = []
    /// Islands live HERE — inside webView.scrollView at index 0 (public API), anchored at
    /// DOCUMENT coordinates. They scroll with the page ON THE COMPOSITOR THREAD: no per-frame
    /// KVO chase, no ≤1-frame hole↔host lag, no scroll flash (iPhone report, 2026-07-04).
    /// Non-clipping 1×1 view so we never track contentSize.
    private let docLayer = UIView()
    /// OVERLAY islands live HERE — a container-level layer ABOVE the WebView. Touch-inert
    /// (glass is pass-through decoration); in-flow overlay hosts are translated per scroll tick
    /// (the demo1 glass mechanism), fixed ones are pinned to viewport coords and never move.
    private let overlayLayer = UIView()
    /// ids hosted in overlayLayer (set at registration from the island's type-level `overlay`).
    private var overlayIds: Set<String> = []
    /// overlay id -> DOC rect (in-flow overlays; translated in trackScroll).
    private var overlayDocRects: [String: IslandRect] = [:]
    /// overlay id -> VIEWPORT rect (fixedPos overlays; frame set once, no tracking).
    private var fixedRects: [String: IslandRect] = [:]
    private var scrollObservation: NSKeyValueObservation?
    private var zoomObservation: NSKeyValueObservation?
    private var glassView: UIVisualEffectView?
    private var glassDocRect: IslandRect?
    private weak var originalWebViewParent: UIView?
    private var originalWebViewIndex = 0
    private var originalWebViewFrame = CGRect.zero
    private var originalWebViewAutoresizing: UIView.AutoresizingMask = []
    private var originalWebViewOpaque = true
    private var originalWebViewBackground: UIColor?
    private var originalScrollBackground: UIColor?
    private var originalInsetAdjustment: UIScrollView.ContentInsetAdjustmentBehavior = .automatic
    private weak var touchTee: UILongPressGestureRecognizer?
    private var lastRoute: NIHitDecision?
    private var systemGestureInsets = NISystemGestureInsets()
    private var animationTracks: [String: (track: IslandAnimationTrack, started: CFTimeInterval)] = [:]
    private var animationDisplayLink: CADisplayLink?

    private func updateSystemGestureInsets() {
        // UIKit does not publish the interactive-pop edge width. Preserve the conventional
        // 20-point leading band plus the platform-reported home-indicator safe area.
        let leading: Double = 20
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        systemGestureInsets = NISystemGestureInsets(
            left: isRTL ? 0 : leading,
            right: isRTL ? leading : 0,
            bottom: Double(safeAreaInsets.bottom)
        )
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateSystemGestureInsets()
    }

    /// Mount the transparent WebView on top of the island hosts and start observing
    /// its scroll. Islands are inserted *below* the WebView as the ledger arrives.
    public func attach(webView: WKWebView) {
        self.webView = webView
        updateSystemGestureInsets()
        originalWebViewParent = webView.superview
        originalWebViewIndex = webView.superview?.subviews.firstIndex(of: webView) ?? 0
        originalWebViewFrame = webView.frame
        originalWebViewAutoresizing = webView.autoresizingMask
        originalWebViewOpaque = webView.isOpaque
        originalWebViewBackground = webView.backgroundColor
        originalScrollBackground = webView.scrollView.backgroundColor
        originalInsetAdjustment = webView.scrollView.contentInsetAdjustmentBehavior
        // Void color: any TRANSIENT hole↔host divergence (per-frame drag lag on the bridge, settle
        // windows) exposes the container behind the punched web — nil rendered BLACK boxes (owner
        // report). systemBackground tracks light/dark so the void reads as "page background" instead.
        backgroundColor = UIColor.systemBackground
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
        // OBSERVE-TEE: a zero-delay, non-cancelling recognizer tees touch coordinates to
        // observer islands while the WebView keeps gesture ownership (observation ≠ transfer).
        let tee = UILongPressGestureRecognizer(target: self, action: #selector(teeTouch(_:)))
        tee.minimumPressDuration = 0
        tee.cancelsTouchesInView = false
        tee.delegate = self
        addGestureRecognizer(tee)
        touchTee = tee

        docLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        docLayer.clipsToBounds = false
        docLayer.layer.anchorPoint = .zero
        docLayer.layer.position = .zero
        webView.scrollView.insertSubview(docLayer, at: 0)

        // The overlay layer sits ABOVE the WebView (the fourth layer). Touch-inert as a
        // whole: overlay islands are pass-through decoration, so hitTest falls to the WebView.
        overlayLayer.frame = bounds
        overlayLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayLayer.isUserInteractionEnabled = false
        overlayLayer.clipsToBounds = false
        addSubview(overlayLayer)

        // Scroll needs NO repositioning anymore (docLayer rides the scroll view) — the observer
        // remains only for viewport-visibility notifications (battery gating) and glass tracking.
        scrollObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            self?.trackScroll(scrollView.contentOffset)
        }
        // Q14 (pinch spike): zoom scales the WHOLE doc layer once per change (rare, not per-frame).
        zoomObservation = webView.scrollView.observe(\.zoomScale, options: [.new]) { [weak self] scrollView, _ in
            guard let self = self else { return }
            let z = scrollView.zoomScale
            self.docLayer.transform = CGAffineTransform(scaleX: z, y: z)
            self.trackScroll(scrollView.contentOffset)
        }
    }

    /// Terminal plugin teardown: remove observers/hosts and restore Capacitor's WebView to its
    /// original parent so destroying the plugin cannot strand the app inside a dead container.
    public func detachWebView() {
        stopLayoutAnimations()
        scrollObservation?.invalidate()
        zoomObservation?.invalidate()
        scrollObservation = nil
        zoomObservation = nil
        if let tee = touchTee { removeGestureRecognizer(tee) }
        touchTee = nil
        onIslandVisibility = nil
        removeAllIslands()
        docLayer.removeFromSuperview()
        overlayLayer.removeFromSuperview()

        guard let webView = webView else { return }
        webView.removeFromSuperview()
        if let parent = originalWebViewParent {
            parent.insertSubview(webView, at: min(originalWebViewIndex, parent.subviews.count))
        }
        webView.frame = originalWebViewFrame
        webView.autoresizingMask = originalWebViewAutoresizing
        webView.isOpaque = originalWebViewOpaque
        webView.backgroundColor = originalWebViewBackground
        webView.scrollView.backgroundColor = originalScrollBackground
        webView.scrollView.contentInsetAdjustmentBehavior = originalInsetAdjustment
        self.webView = nil
    }

    /// An island plugin registers its native view (created lazily on first `create`).
    /// The page's backdrop color (NativeIslands.setBackdrop). During the ≤1-frame scroll-KVO lag
    /// a moved knockout hole reveals this backing — page-colored, the flash disappears into the
    /// design instead of strobing black.
    public func setBackdrop(hex: String) {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&v), h.count == 6 else { return }
        backgroundColor = UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                                  green: CGFloat((v >> 8) & 0xFF) / 255,
                                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    public func registerIsland(
        id: String,
        view: UIView,
        overlay: Bool = false,
        accessibilityOwner: String = "web"
    ) {
        hosts[id]?.removeFromSuperview()
        hosts[id] = view
        if overlay {
            overlayIds.insert(id)
            overlayLayer.addSubview(view)
        } else {
            docLayer.addSubview(view)
        }
        view.isHidden = true
        // Single-control/decorative islands mirror semantics onto the DOM face. Multi-control
        // engines retain their real VoiceOver subtree instead of collapsing into one broad proxy.
        let nativeOwnsAccessibility = accessibilityOwner == "native"
        view.accessibilityElementsHidden = !nativeOwnsAccessibility
        if !nativeOwnsAccessibility { view.isAccessibilityElement = false }
        // Q14 zoom-tracking: scale about the top-left so translate∘scale keeps doc-coord frames valid.
        view.layer.anchorPoint = .zero
        view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        // Do not reparent here: docLayer already lives below WebKit's content inside the public
        // scroll view, while overlayLayer lives above the Canvas. applyOrder only reorders within
        // the selected layer. Reparenting to the container would break both contracts until the
        // next ledger and can expose a wrong-layer first frame.
    }

    public func island(id: String) -> UIView? {
        return hosts[id]
    }

    public func removeIsland(id: String) {
        hosts.removeValue(forKey: id)?.removeFromSuperview()
        visibleIds.remove(id)
        docRects[id] = nil
        excludeDoc[id] = nil
        interactiveIds.remove(id)
        order.removeAll { $0 == id }
        overlayIds.remove(id)
        overlayDocRects[id] = nil
        fixedRects[id] = nil
    }

    /// Stop managing an island in Path-A (it has been mounted same-layer / Path-B). The view itself is
    /// re-parented by the mounter; here we just drop our tracking so applyLedger/reposition ignore it.
    public func releaseIsland(id: String) {
        hosts[id] = nil
        docRects[id] = nil
        excludeDoc[id] = nil
        interactiveIds.remove(id)
        order.removeAll { $0 == id }
    }

    /// Page navigation/reload: tear down ordinary hosts and all page-local ledger state. A
    /// persistent engine remains parented but hidden until the next document adopts its id.
    public func removeAllIslands(keeping ids: Set<String> = []) {
        stopLayoutAnimations()
        for (id, host) in hosts {
            if ids.contains(id) {
                host.isHidden = true
            } else {
                host.removeFromSuperview()
            }
        }
        visibleIds.removeAll()
        hosts = hosts.filter { ids.contains($0.key) }
        docRects = docRects.filter { ids.contains($0.key) }
        excludeDoc.removeAll()
        interactiveIds.removeAll()
        order.removeAll()
        overlayIds.formIntersection(ids)
        overlayDocRects = overlayDocRects.filter { ids.contains($0.key) }
        fixedRects = fixedRects.filter { ids.contains($0.key) }
        glassView?.removeFromSuperview()
        glassView = nil
        glassDocRect = nil
    }

    /// Apply a recomputed occlusion ledger: size/position island hosts in document
    /// space, mirror the paint order, and store hit-test exclusions.
    public func applyLedger(components: [IslandComponent], order: [String], exclude: [String: [IslandRect]]) {
        stopLayoutAnimations()
        self.order = order
        self.excludeDoc = exclude
        self.interactiveIds = Set(components.filter { $0.interactive }.map { $0.id })

        // An island REMOVED from the page (element deleted) simply vanishes from the ledger — hide
        // its host or it ghosts at the last frame (the Inspector's delete-element beat needs this).
        let liveIds = Set(components.map { $0.id })
        for (id, host) in hosts where !liveIds.contains(id) {
            host.isHidden = true
            docRects[id] = nil
        }

        for component in components {
            guard let host = hosts[component.id] else { continue }
            guard component.active, let rect = component.rect, rect.w > 1 else {
                host.isHidden = true
                docRects[component.id] = nil
                overlayDocRects[component.id] = nil
                fixedRects[component.id] = nil
                continue
            }
            // OVERLAY hosts live above the WebView in container coords. Fixed ones pin to
            // the viewport rect the web sent and never move; in-flow ones store the doc rect and
            // ride trackScroll (the demo1 glass mechanism — interaction-rate, blur hides ≤1 frame).
            if overlayIds.contains(component.id) {
                host.isHidden = false
                host.transform = .identity
                if component.fixedPos {
                    fixedRects[component.id] = rect
                    overlayDocRects[component.id] = nil
                    host.frame = CGRect(x: pxRound(rect.x), y: pxRound(rect.y), width: pxRound(rect.w), height: pxRound(rect.h))
                } else {
                    overlayDocRects[component.id] = rect
                    fixedRects[component.id] = nil
                    host.frame = CGRect(x: pxRound(rect.x), y: pxRound(rect.y), width: pxRound(rect.w), height: pxRound(rect.h))
                }
                host.layer.cornerRadius = rect.r
                host.layer.masksToBounds = rect.r > 0
                host.setNeedsLayout()
                continue
            }
            docRects[component.id] = rect
            host.isHidden = false
            // Frame carries the DOCUMENT position — the host lives in docLayer inside the
            // scroll view, so scrolling needs no further work (compositor-synced).
            // bleed epsilon: the native host extends 1 CSS px past the ledger rect on every side,
            // so the anti-aliased edge of the web clip-hole never exposes the void as a hairline rim
            // (the "slight black margin" owner report). Hit-testing/reposition still use the exact rect.
            host.transform = .identity
            host.frame = CGRect(x: pxRound(rect.x) - 1, y: pxRound(rect.y) - 1, width: pxRound(rect.w) + 2, height: pxRound(rect.h) + 2)
            host.layer.cornerRadius = rect.r > 0 ? rect.r + 1 : 0
            host.layer.masksToBounds = rect.r > 0
            // Always run the host's layout pass, even when the frame is byte-identical: a forced
            // ledger re-emit (the web's first-paint recovery) must reach the hosted content's
            // layout (CMP Metal / SwiftUI hosting view) or a missed first frame stays missed.
            host.setNeedsLayout()
        }

        applyOrder()
        if let webView = webView {
            // A main-document navigation can make WebKit rebuild its private scroll hierarchy and
            // detach unfamiliar subviews. The hosts remain valid in our registry but have no
            // window, leaving correctly punched holes showing only the container backdrop. Re-adopt
            // the public scroll-view child on every genuine ledger application; this is idempotent
            // during ordinary layout and repairs route changes without touching private WebKit APIs.
            if docLayer.superview !== webView.scrollView {
                docLayer.removeFromSuperview()
                webView.scrollView.insertSubview(docLayer, at: 0)
            }
            // WebKit adds/removes its own scroll-view subviews; keep the doc layer at the BOTTOM
            // (below the content view) so islands stay behind the web pixels — and the overlay
            // layer at the TOP so glass sheets stay above the Canvas.
            webView.scrollView.sendSubviewToBack(docLayer)
            if !overlayIds.isEmpty { bringSubviewToFront(overlayLayer) }
            trackScroll(webView.scrollView.contentOffset)
        }
    }

    /// Drag fast-path: update only the given islands' doc positions + retranslate. No re-size /
    /// re-order / exclude recompute — keeps a finger-tracked island smooth.
    public func reposition(_ moves: [String: CGPoint]) {
        for (id, pos) in moves {
            guard var r = docRects[id], let host = hosts[id] else { continue }
            r.x = pos.x; r.y = pos.y
            docRects[id] = r
            host.transform = .identity
            // Same bleed as applyLedger (frames must agree between the two paths).
            host.frame = CGRect(x: pxRound(r.x) - 1, y: pxRound(r.y) - 1, width: pxRound(r.w) + 2, height: pxRound(r.h) + 2)
        }
        if let webView = webView { trackScroll(webView.scrollView.contentOffset) }
    }

    /// One-shot browser-sampled CSS/WAAPI replay. CADisplayLink advances document geometry and
    /// hit routing locally; no animation frame crosses the Capacitor bridge.
    public func animateLayout(_ tracks: [IslandAnimationTrack]) {
        let now = CACurrentMediaTime()
        for track in tracks where track.frames.count >= 2 && track.duration > 0 && !overlayIds.contains(track.id) {
            guard hosts[track.id] != nil else { continue }
            animationTracks[track.id] = (track, now)
        }
        guard !animationTracks.isEmpty, animationDisplayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepLayoutAnimations(_:)))
        link.add(to: .main, forMode: .common)
        animationDisplayLink = link
    }

    @objc private func stepLayoutAnimations(_ link: CADisplayLink) {
        var finished: [String] = []
        for (id, state) in animationTracks {
            let progress = min(1, max(0, (link.timestamp - state.started) / state.track.duration))
            let frames = state.track.frames
            let upper = frames.firstIndex { Double($0.at) >= progress } ?? (frames.count - 1)
            let left = frames[max(0, upper - 1)]
            let right = frames[upper]
            let span = max(0.000_001, right.at - left.at)
            let t = CGFloat((progress - Double(left.at)) / Double(span))
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
            let rect = IslandRect(
                x: mix(left.rect.x, right.rect.x), y: mix(left.rect.y, right.rect.y),
                w: mix(left.rect.w, right.rect.w), h: mix(left.rect.h, right.rect.h),
                r: mix(left.rect.r, right.rect.r))
            docRects[id] = rect
            for target in state.track.exclusionTargets {
                guard var rects = excludeDoc[target.island], rects.indices.contains(target.index) else { continue }
                rects[target.index] = rect
                excludeDoc[target.island] = rects
            }
            if let host = hosts[id] {
                host.transform = .identity
                host.frame = CGRect(x: pxRound(rect.x) - 1, y: pxRound(rect.y) - 1,
                                    width: pxRound(rect.w) + 2, height: pxRound(rect.h) + 2)
                host.layer.cornerRadius = rect.r > 0 ? rect.r + 1 : 0
                host.layer.masksToBounds = rect.r > 0
                host.setNeedsLayout()
            }
            if progress >= 1 { finished.append(id) }
        }
        for id in finished { animationTracks[id] = nil }
        if animationTracks.isEmpty { stopLayoutAnimations() }
    }

    private func stopLayoutAnimations() {
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
        animationTracks.removeAll()
    }

    /// Effects interlayer: insert/position a native blur BETWEEN the islands and the
    /// WebView, beneath a web effect layer (e.g. the frosted card), so it blurs the live
    /// island behind it — backdrop-blur over a real platform view. Tracks scroll like an island.
    public func applyGlass(_ rects: [IslandRect]) {
        guard let webView = webView, let rect = rects.first else {
            glassView?.removeFromSuperview()
            glassView = nil
            glassDocRect = nil
            return
        }
        glassDocRect = rect
        let gv: UIVisualEffectView
        if let existing = glassView {
            gv = existing
        } else {
            gv = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            gv.isUserInteractionEnabled = false
            gv.layer.cornerRadius = 18 // matches the example card's radius
            gv.layer.masksToBounds = true
            glassView = gv
        }
        insertSubview(gv, belowSubview: webView) // above the islands, below the Canvas
        gv.transform = .identity
        gv.frame = CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
        trackScroll(webView.scrollView.contentOffset)
    }

    /// Mirror the ledger's paint order among island hosts (all below the WebView).
    private func applyOrder() {
        // The ledger's order names EVERY island; hosts exist only for mounted ones (unknown types
        // degrade web-side, B5). Assign COMPACT subview indices — the raw ledger index overflows
        // the subview count when an errored island sits mid-order (Android hit the crash first,
        // 2026-07-04; iOS had survived only because its errored island was last).
        var childIndex = 0
        var overlayIndex = 0
        for id in order {
            guard let host = hosts[id] else { continue }
            // Overlay hosts order among THEMSELVES above the WebView; doc hosts below it.
            if overlayIds.contains(id) {
                overlayLayer.insertSubview(host, at: min(overlayIndex, overlayLayer.subviews.count))
                overlayIndex += 1
            } else {
                docLayer.insertSubview(host, at: min(childIndex, docLayer.subviews.count))
                childIndex += 1
            }
        }
    }

    /// Hot path: one transform write per visible island per scroll tick. The frame
    /// already holds the document position, so the transform is purely the scroll
    /// offset — it never reads `frame`, so transformed frames stay valid.
    /// BATTERY: islands with live sensors (camera/AR) pause them offscreen. The container
    /// is the one place that knows every host's on-screen rect each scroll frame; it reports CHANGES only.
    public var onIslandVisibility: ((String, Bool) -> Void)?
    private var visibleIds = Set<String>()

    private func notifyVisibility() {
        // Generous margin (hysteresis): pausing sensors is for islands scrolled WELL away — a pip
        // dragged along the edge must not flap the camera/AR session on/off per frame.
        let expanded = bounds.insetBy(dx: -bounds.height * 0.5, dy: -bounds.height * 0.5)
        for (id, host) in hosts {
            let vis = !host.isHidden && host.frame.intersects(expanded) // frame already reflects the transform
            if vis != visibleIds.contains(id) {
                if vis { visibleIds.insert(id) } else { visibleIds.remove(id) }
                onIslandVisibility?(id, vis)
            }
        }
    }

    /// C8 mitigation (council): a scene with ZERO active islands pays no transparent-WebView blend —
    /// flip the WebView back to opaque until an island appears.
    public func setCompositingActive(_ active: Bool) {
        guard let webView = webView, webView.isOpaque == active else { return }
        webView.isOpaque = !active
        webView.backgroundColor = active ? .clear : .systemBackground
        webView.scrollView.backgroundColor = webView.backgroundColor
    }

    private func trackScroll(_ offset: CGPoint) {
        // Hosts DON'T move here — they live in docLayer inside the scroll view and ride it on the
        // compositor thread. Only the container-level layers track by transform: the demo1 glass
        // view and IN-FLOW overlay islands (fixed overlays never move), plus battery visibility.
        let z = webView?.scrollView.zoomScale ?? 1
        if let g = glassDocRect {
            glassView?.transform = CGAffineTransform(
                translationX: g.x * z - offset.x - g.x,
                y: g.y * z - offset.y - g.y
            ).scaledBy(x: z, y: z)
        }
        for (id, r) in overlayDocRects {
            hosts[id]?.transform = CGAffineTransform(
                translationX: r.x * z - offset.x - r.x,
                y: r.y * z - offset.y - r.y
            ).scaledBy(x: z, y: z)
        }
        notifyVisibility()
    }

    private func screenRect(_ id: String, offset: CGPoint) -> CGRect? {
        guard let r = docRects[id] else { return nil }
        let z = webView?.scrollView.zoomScale ?? 1
        return NIContainerGeometry.screenRect(
            x: r.x, y: r.y, width: r.w, height: r.h, zoom: z, offset: offset
        )
    }

    /// Sentinel-lite: route touch-down. A point inside an interactive island's screen
    /// rect and NOT inside any of its exclusion rects (web/native stacked above it)
    /// goes to the island; everything else falls through to the WebView.
    @objc private func teeTouch(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began || g.state == .changed else { return }
        let offset = webView?.scrollView.contentOffset ?? .zero
        let zoom = webView?.scrollView.zoomScale ?? 1
        for (id, host) in hosts {
            guard let obs = host as? TouchObserverView, host.window != nil else { continue }
            for touchIndex in 0..<g.numberOfTouches {
                let point = g.location(ofTouch: touchIndex, in: host)
                // Observation follows visual ownership: a declared web layer above an island
                // (for example a bottom sheet) must not make the island react through it.
                let containerPoint = g.location(ofTouch: touchIndex, in: self)
                let excluded = (excludeDoc[id] ?? []).contains { ex in
                    NIContainerGeometry.screenRect(
                        x: ex.x, y: ex.y, width: ex.w, height: ex.h,
                        zoom: zoom, offset: offset
                    ).contains(containerPoint)
                }
                if NIObserverRouting.shouldObserve(pointIsInHost: host.bounds.contains(point), excludedByWeb: excluded) {
                    obs.observeTouch(point)
                }
            }
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let webView = webView else {
            lastRoute = NIHitDecision(owner: "web", reason: "container_detached")
            return super.hitTest(point, with: event)
        }
        if systemGestureInsets.contains(
            x: Double(point.x), y: Double(point.y),
            width: Double(bounds.width), height: Double(bounds.height)
        ) {
            lastRoute = NIHitDecision(owner: "web", reason: "system_gesture_edge")
            return super.hitTest(point, with: event)
        }
        let offset = webView.scrollView.contentOffset
        var candidates: [NIHitCandidate] = []
        for id in order.reversed() {
            guard let host = hosts[id], !host.isHidden else { continue }
            // Overlay islands (glass) are pass-through decoration ABOVE the web: topmost-decides
            // means a point inside one belongs to the WebView beneath it, and it occludes any
            // island below from receiving the touch.
            if overlayIds.contains(id) {
                let r: CGRect?
                if let f = fixedRects[id] {
                    r = NIContainerGeometry.screenRect(
                        x: f.x, y: f.y, width: f.w, height: f.h,
                        zoom: webView.scrollView.zoomScale, offset: offset, fixed: true
                    )
                } else if let d = overlayDocRects[id] {
                    let z = webView.scrollView.zoomScale
                    r = NIContainerGeometry.screenRect(
                        x: d.x, y: d.y, width: d.w, height: d.h, zoom: z, offset: offset
                    )
                } else {
                    r = nil
                }
                if let r = r, r.contains(point) {
                    candidates.append(NIHitCandidate(id: id, overlay: true,
                                                     interactive: false, excluded: false))
                    break
                }
                continue
            }
            guard let rect = screenRect(id, offset: offset), rect.contains(point) else { continue }
            // The topmost island here occludes those below, so we decide at it and stop.
            // A NON-interactive island (e.g. a camera viewfinder) passes the touch to the
            // WebView so web content above it (stickers/captions/buttons) stays interactive.
            let z = webView.scrollView.zoomScale
            let excluded = (excludeDoc[id] ?? []).contains { ex in
                NIContainerGeometry.screenRect(
                    x: ex.x, y: ex.y, width: ex.w, height: ex.h, zoom: z, offset: offset
                ).contains(point)
            }
            candidates.append(NIHitCandidate(id: id, overlay: false,
                                             interactive: interactiveIds.contains(id),
                                             excluded: excluded))
            break
        }
        let decision = NIHitRouting.decide(candidates)
        lastRoute = decision
        if decision.owner == "island", let id = decision.island, let host = hosts[id] {
            let converted = convert(point, to: host)
            return host.hitTest(converted, with: event) ?? host
        }
        return super.hitTest(point, with: event)
    }

    /// Content-free snapshot for copyable visual-order/input-routing bug reports.
    public func diagnosticSnapshot() -> [String: Any] {
        let excluded = Dictionary(uniqueKeysWithValues: excludeDoc.map { ($0.key, $0.value.count) })
        let route: Any
        if let lastRoute = lastRoute {
            var value: [String: Any] = [
                "owner": lastRoute.owner,
                "reason": lastRoute.reason,
                "active": false, // UIKit owns gesture continuation after hit-test; no manual route latch.
            ]
            if let island = lastRoute.island { value["island"] = island }
            route = value
        } else {
            route = NSNull()
        }
        let offset = webView?.scrollView.contentOffset ?? .zero
        return [
            "platform": "ios",
            "containerInstalled": webView != nil,
            "documentLayerAttached": docLayer.superview === webView?.scrollView,
            "mounted": hosts.keys.sorted(),
            "visible": hosts.filter { !$0.value.isHidden && $0.value.window != nil }.keys.sorted(),
            "order": order,
            "interactive": interactiveIds.sorted(),
            "overlay": overlayIds.sorted(),
            "fixed": fixedRects.keys.sorted(),
            "animations": animationTracks.keys.sorted(),
            "excludeCounts": excluded,
            "systemGestureInsets": [
                "left": systemGestureInsets.left,
                "top": systemGestureInsets.top,
                "right": systemGestureInsets.right,
                "bottom": systemGestureInsets.bottom,
            ],
            "route": route,
            "scroll": [
                "x": Double(offset.x),
                "y": Double(offset.y),
                "scale": Double(webView?.scrollView.zoomScale ?? 1),
            ],
        ]
    }

    deinit {
        animationDisplayLink?.invalidate()
        scrollObservation?.invalidate()
        zoomObservation?.invalidate()
    }
}


extension NativeIslandsContainer: UIGestureRecognizerDelegate {
    // The tee must coexist with the WebView's own pan/tap recognizers — it observes, never owns.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
