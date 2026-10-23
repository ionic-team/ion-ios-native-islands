import CoreGraphics

enum NIContainerGeometry {
    static func calibratedScrollOffset(
        nativeOffset: CGPoint,
        zoom: CGFloat,
        bias: CGPoint
    )
        -> CGPoint {
        guard zoom > 0 else { return .zero }
        return CGPoint(
            x: nativeOffset.x / zoom - bias.x,
            y: nativeOffset.y / zoom - bias.y
        )
    }

    static func screenRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        zoom: CGFloat,
        offset: CGPoint
    )
        -> CGRect {
        CGRect(
            x: x * zoom - offset.x,
            y: y * zoom - offset.y,
            width: width * zoom,
            height: height * zoom
        )
    }

    static func screenRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        coordinateSpace: NICoordinateSpace,
        nestedOffset: CGPoint,
        zoom: CGFloat,
        rootOffset: CGPoint
    )
        -> CGRect {
        screenRect(
            x: x - nestedOffset.x,
            y: y - nestedOffset.y,
            width: width,
            height: height,
            zoom: zoom,
            offset: coordinateSpace == .document ? rootOffset : .zero
        )
    }
}
