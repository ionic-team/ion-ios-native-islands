import CoreGraphics

internal enum NIContainerGeometry {
    static func calibratedScrollOffset(
        nativeOffset: CGPoint,
        zoom: CGFloat,
        bias: CGPoint
    ) -> CGPoint {
        guard zoom > 0 else { return .zero }
        return CGPoint(
            x: nativeOffset.x / zoom - bias.x,
            y: nativeOffset.y / zoom - bias.y
        )
    }

    static func clampedCornerRadius(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat
    ) -> CGFloat {
        min(max(cornerRadius, 0), min(width, height) / 2)
    }

    static func screenRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        zoom: CGFloat,
        offset: CGPoint
    ) -> CGRect {
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
    ) -> CGRect {
        let scrollsWithDocument = coordinateSpace == .document
        return screenRect(
            x: x - (scrollsWithDocument ? nestedOffset.x : 0),
            y: y - (scrollsWithDocument ? nestedOffset.y : 0),
            width: width,
            height: height,
            zoom: zoom,
            offset: scrollsWithDocument ? rootOffset : .zero
        )
    }

    static func contains(
        point: CGPoint,
        in rect: CGRect,
        cornerRadius: CGFloat
    ) -> Bool {
        guard rect.contains(point) else { return false }
        let radius = clampedCornerRadius(
            width: rect.width,
            height: rect.height,
            cornerRadius: cornerRadius
        )
        guard radius > 0 else { return true }

        let closestX = min(
            max(point.x, rect.minX + radius),
            rect.maxX - radius
        )
        let closestY = min(
            max(point.y, rect.minY + radius),
            rect.maxY - radius
        )
        let deltaX = point.x - closestX
        let deltaY = point.y - closestY
        return deltaX * deltaX + deltaY * deltaY <= radius * radius
    }
}
