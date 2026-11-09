import CoreGraphics

enum NIContainerGeometry {
    static func calibratedScrollOffset(
        nativeOffset: CGPoint,
        zoom: CGFloat,
        bias: CGPoint,
        maxDomOffset: CGPoint,
        maxNativeOffset: CGPoint
    )
        -> CGPoint {
        guard zoom > 0 else { return .zero }
        return CGPoint(
            x: clampCeilingSlack(
                calibrated: nativeOffset.x / zoom - bias.x,
                bias: bias.x,
                maxDom: maxDomOffset.x,
                maxNative: maxNativeOffset.x
            ),
            y: clampCeilingSlack(
                calibrated: nativeOffset.y / zoom - bias.y,
                bias: bias.y,
                maxDom: maxDomOffset.y,
                maxNative: maxNativeOffset.y
            )
        )
    }

    /// A native scroll range at most 2.5 points longer than the page's is rounding, not content, so
    /// past the page's last offset the difference is taken back.
    private static func clampCeilingSlack(
        calibrated: CGFloat,
        bias: CGFloat,
        maxDom: CGFloat,
        maxNative: CGFloat
    )
        -> CGFloat {
        let slack = maxNative - maxDom
        guard slack > 0, slack <= 2.5, calibrated > maxDom else {
            return calibrated
        }
        let unabsorbed = max(0, min(slack - bias, slack))
        return max(maxDom, calibrated - unabsorbed)
    }

    /// `rect` in the WebView's points: moved back by the scrollers it sits in, zoomed, and moved back
    /// by the document's scroll when it is in document coordinates.
    static func screenRect(
        _ rect: IslandRect,
        coordinateSpace: NICoordinateSpace,
        nestedOffset: CGPoint,
        zoom: CGFloat,
        rootOffset: CGPoint
    )
        -> IslandRect {
        let offset = coordinateSpace == .document ? rootOffset : .zero
        return IslandRect(
            x: (rect.x - nestedOffset.x) * zoom - offset.x,
            y: (rect.y - nestedOffset.y) * zoom - offset.y,
            width: rect.width * zoom,
            height: rect.height * zoom,
            cornerRadii: rect.cornerRadii.scaled(by: zoom)
        )
    }
}
