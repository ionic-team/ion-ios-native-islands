import CoreGraphics

/// How the page draws an island's own box, `size` px: a point of that box is drawn at `matrix`
/// applied to it, from the top-left corner of the rect the island covers.
struct NIIslandTransform: Equatable {
    let size: CGSize
    let matrix: CGAffineTransform

    init(size: CGSize, matrix: CGAffineTransform) {
        self.size = size
        self.matrix = matrix
    }

    /// The transform a component's `transform` sends, or nil when it is not one.
    init?(_ value: Any?) {
        guard
            let value = value as? [String: Any],
            let size = NISafeGeometry.numbers(value["size"], count: 2),
            size.allSatisfy({ $0 > 0 }),
            let matrix = NISafeGeometry.numbers(value["matrix"], count: 6)
        else {
            return nil
        }
        self.init(
            size: CGSize(width: size[0], height: size[1]),
            matrix: CGAffineTransform(a: matrix[0], b: matrix[1], c: matrix[2], d: matrix[3], tx: matrix[4], ty: matrix[5])
        )
    }
}

/// The view an island is drawn in: its own box at `zoom` points per page px, rounded by its own
/// radii, and drawn into its host by `transform`. The host is axis-aligned and covers what the
/// page draws, so whatever else scales it (a motion) scales the body by as much.
struct NIIslandBody: Equatable {
    let size: CGSize
    let radii: NICornerRadii
    let transform: CGAffineTransform

    /// The body of an island the page draws over `rect` (its radii its own when `transform` is
    /// sent), in a host `placed` points across at `zoom`.
    init(rect: IslandRect, placed: CGSize, zoom: CGFloat, transform: NIIslandTransform?) {
        let own = transform?.size ?? rect.cgRect.size
        let matrix = transform?.matrix ?? .identity
        let scaleX = rect.width * zoom > 0 ? placed.width / (rect.width * zoom) : 1
        let scaleY = rect.height * zoom > 0 ? placed.height / (rect.height * zoom) : 1
        size = CGSize(width: own.width * zoom, height: own.height * zoom)
        radii = rect.cornerRadii.scaled(by: zoom).fitted(to: size)
        self.transform = CGAffineTransform(
            a: matrix.a * scaleX,
            b: matrix.b * scaleY,
            c: matrix.c * scaleX,
            d: matrix.d * scaleY,
            tx: matrix.tx * zoom * scaleX,
            ty: matrix.ty * zoom * scaleY
        )
    }

    /// Whether the body covers `point`, in its host's points.
    func contains(_ point: CGPoint) -> Bool {
        guard transform.a * transform.d - transform.b * transform.c != 0 else { return false }
        let local = point.applying(transform.inverted())
        return IslandRect(x: 0, y: 0, width: size.width, height: size.height, cornerRadii: radii).contains(local)
    }
}
