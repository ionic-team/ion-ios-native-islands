import CoreGraphics

struct NISticky: Equatable {
    let scroller: String?
    let natural: CGRect
    let bounds: CGRect
    var top: CGFloat?
    var right: CGFloat?
    var bottom: CGFloat?
    var left: CGFloat?

    init?(_ value: Any?) {
        guard
            let value = value as? [String: Any],
            let natural = (value["natural"] as? [String: Any]).flatMap(NISafeGeometry.parseRect),
            let bounds = (value["bounds"] as? [String: Any]).flatMap(NISafeGeometry.parseRect)
        else {
            return nil
        }
        var insets: [String: CGFloat] = [:]
        for name in ["top", "right", "bottom", "left"] where value[name] != nil {
            guard let inset = NISafeGeometry.strictNumber(value[name]) else {
                return nil
            }
            insets[name] = CGFloat(inset)
        }
        if value["scroller"] != nil, !(value["scroller"] is String) { return nil }
        self.init(
            scroller: value["scroller"] as? String,
            natural: CGRect(x: natural.x, y: natural.y, width: natural.width, height: natural.height),
            bounds: CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height),
            top: insets["top"],
            right: insets["right"],
            bottom: insets["bottom"],
            left: insets["left"]
        )
    }

    init(
        scroller: String?,
        natural: CGRect,
        bounds: CGRect,
        top: CGFloat? = nil,
        right: CGFloat? = nil,
        bottom: CGFloat? = nil,
        left: CGFloat? = nil
    ) {
        self.scroller = scroller
        self.natural = natural
        self.bounds = bounds
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    func fits(scrollPath: [String], coordinateSpace: NICoordinateSpace) -> Bool {
        if let scroller { return scroller == scrollPath.last }
        return scrollPath.isEmpty && coordinateSpace == .document
    }

    func offset(in view: CGRect) -> CGVector {
        CGVector(
            dx: Self.axis(
                start: natural.minX,
                end: natural.maxX,
                boundsStart: bounds.minX,
                boundsEnd: bounds.maxX,
                viewStart: view.minX + (left ?? 0),
                viewEnd: view.maxX - (right ?? 0),
                leading: left != nil,
                trailing: right != nil
            ),
            dy: Self.axis(
                start: natural.minY,
                end: natural.maxY,
                boundsStart: bounds.minY,
                boundsEnd: bounds.maxY,
                viewStart: view.minY + (top ?? 0),
                viewEnd: view.maxY - (bottom ?? 0),
                leading: top != nil,
                trailing: bottom != nil
            )
        )
    }

    private static func axis(
        start: CGFloat,
        end: CGFloat,
        boundsStart: CGFloat,
        boundsEnd: CGFloat,
        viewStart: CGFloat,
        viewEnd: CGFloat,
        leading: Bool,
        trailing: Bool
    )
        -> CGFloat {
        if leading, viewStart > start {
            return min(viewStart - start, max(0, boundsEnd - end))
        }
        if trailing, viewEnd < end {
            return max(viewEnd - end, min(0, boundsStart - start))
        }
        return 0
    }
}
