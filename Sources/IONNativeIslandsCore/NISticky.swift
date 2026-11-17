import CoreGraphics

struct NISticky: Equatable {
    let scroller: String?
    let natural: CGRect
    let bounds: CGRect
    var top: CGFloat?
    var right: CGFloat?
    var bottom: CGFloat?
    var left: CGFloat?
    /// The sticky box, in the same scroller, the block this one sticks inside moves with.
    var within: NISticky? {
        get { outer?.sticky }
        set { outer = newValue.map(Outer.init) }
    }

    private var outer: Outer?

    /// Holds the outer box: a struct cannot hold one of its own type.
    private final class Outer: Equatable {
        let sticky: NISticky

        init(_ sticky: NISticky) {
            self.sticky = sticky
        }

        static func == (lhs: Outer, rhs: Outer) -> Bool {
            lhs.sticky == rhs.sticky
        }
    }

    init?(_ value: Any?) {
        guard
            let value = value as? [String: Any],
            let natural = (value["natural"] as? [String: Any]).flatMap({ NISafeGeometry.parseRect($0, allowsEmpty: true) }),
            let bounds = (value["bounds"] as? [String: Any]).flatMap({ NISafeGeometry.parseRect($0, allowsEmpty: true) })
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
        var within: NISticky?
        if value["within"] != nil {
            guard let outer = NISticky(value["within"]) else { return nil }
            within = outer
        }
        self.init(
            scroller: value["scroller"] as? String,
            natural: natural.cgRect,
            bounds: bounds.cgRect,
            top: insets["top"],
            right: insets["right"],
            bottom: insets["bottom"],
            left: insets["left"],
            within: within
        )
    }

    init(
        scroller: String?,
        natural: CGRect,
        bounds: CGRect,
        top: CGFloat? = nil,
        right: CGFloat? = nil,
        bottom: CGFloat? = nil,
        left: CGFloat? = nil,
        within: NISticky? = nil
    ) {
        self.scroller = scroller
        self.natural = natural
        self.bounds = bounds
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        self.within = within
    }

    func fits(scrollPath: [String], coordinateSpace: NICoordinateSpace) -> Bool {
        guard within?.fits(scrollPath: scrollPath, coordinateSpace: coordinateSpace) ?? true else { return false }
        if let scroller { return scroller == scrollPath.last }
        return scrollPath.isEmpty && coordinateSpace == .document
    }

    /// How far the box has stuck, with what holds it, in `view`, what its scroller shows.
    func offset(in view: CGRect) -> CGVector {
        let outer = within?.offset(in: view) ?? .zero
        let natural = self.natural.offsetBy(dx: outer.dx, dy: outer.dy)
        let bounds = self.bounds.offsetBy(dx: outer.dx, dy: outer.dy)
        return CGVector(
            dx: outer.dx + Self.axis(
                start: natural.minX,
                end: natural.maxX,
                boundsStart: bounds.minX,
                boundsEnd: bounds.maxX,
                viewStart: view.minX + (left ?? 0),
                viewEnd: view.maxX - (right ?? 0),
                leading: left != nil,
                trailing: right != nil
            ),
            dy: outer.dy + Self.axis(
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
