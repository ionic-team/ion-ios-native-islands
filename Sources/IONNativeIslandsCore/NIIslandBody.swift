import CoreGraphics

/// How the page draws an island's own box, `size` px: a point of that box is drawn at `matrix`
/// applied to it, from the top-left corner of the rect the island covers, divided by
/// `perspective.x` x + `perspective.y` y + 1 when the page turns it in perspective.
struct NIIslandTransform: Equatable {
    let size: CGSize
    let matrix: CGAffineTransform
    let perspective: CGPoint

    init(size: CGSize, matrix: CGAffineTransform, perspective: CGPoint = .zero) {
        self.size = size
        self.matrix = matrix
        self.perspective = perspective
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
        var row: [CGFloat] = [0, 0]
        if value["perspective"] != nil {
            guard let sent = NISafeGeometry.numbers(value["perspective"], count: 2) else { return nil }
            row = sent
        }
        self.init(
            size: CGSize(width: size[0], height: size[1]),
            matrix: CGAffineTransform(a: matrix[0], b: matrix[1], c: matrix[2], d: matrix[3], tx: matrix[4], ty: matrix[5]),
            perspective: CGPoint(x: row[0], y: row[1])
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
    /// The body's perspective row, in its own points: (x, y) is drawn at `transform` applied to it,
    /// divided by `perspective.x` x + `perspective.y` y + 1.
    let perspective: CGPoint

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
        let row = transform?.perspective ?? .zero
        perspective = zoom > 0 ? CGPoint(x: row.x / zoom, y: row.y / zoom) : .zero
    }

    /// Where the body draws `point` of its own box, in its host's points.
    func drawn(_ point: CGPoint) -> CGPoint {
        let affine = point.applying(transform)
        let depth = perspective.x * point.x + perspective.y * point.y + 1
        return CGPoint(x: affine.x / depth, y: affine.y / depth)
    }

    /// Whether the body covers `point`, in its host's points.
    func contains(_ point: CGPoint) -> Bool {
        guard let local = local(point) else { return false }
        return IslandRect(x: 0, y: 0, width: size.width, height: size.height, cornerRadii: radii).contains(local)
    }

    /// The point of its own box the body draws at `point`, in its host's points; nil where it
    /// draws none.
    private func local(_ point: CGPoint) -> CGPoint? {
        // The inverse of [[a, c, tx], [b, d, ty], [row.x, row.y, 1]], by its adjugate.
        let map = transform
        let row = perspective
        let x = (map.d - map.ty * row.y) * point.x + (map.tx * row.y - map.c) * point.y + (map.c * map.ty - map.d * map.tx)
        let y = (map.ty * row.x - map.b) * point.x + (map.a - map.tx * row.x) * point.y + (map.b * map.tx - map.a * map.ty)
        let depth = (map.b * row.y - map.d * row.x) * point.x + (map.c * row.x - map.a * row.y) * point.y + (map.a * map.d - map.b * map.c)
        let determinant = map.a * (map.d - map.ty * row.y) - map.c * (map.b - map.ty * row.x) + map.tx * (map.b * row.y - map.d * row.x)
        guard depth != 0, determinant != 0 else { return nil }
        return CGPoint(x: x / depth, y: y / depth)
    }
}
