import CoreGraphics

struct NICornerRadii: Equatable {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottomRight: CGFloat
    var bottomLeft: CGFloat

    init(
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomRight: CGFloat,
        bottomLeft: CGFloat
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    init(uniform radius: CGFloat) {
        self.init(
            topLeft: radius,
            topRight: radius,
            bottomRight: radius,
            bottomLeft: radius
        )
    }

    private var all: [CGFloat] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    var isSquare: Bool {
        all.allSatisfy { $0 <= 0 }
    }

    func sharedRadius(in size: CGSize) -> CGFloat? {
        let rounded = all.filter { $0 > 0 }
        guard let radius = rounded.first else { return 0 }
        guard
            rounded.allSatisfy({ abs($0 - radius) < 0.01 }),
            radius <= min(size.width, size.height) / 2
        else {
            return nil
        }
        return radius
    }

    func scaled(by factor: CGFloat) -> NICornerRadii {
        NICornerRadii(
            topLeft: topLeft * factor,
            topRight: topRight * factor,
            bottomRight: bottomRight * factor,
            bottomLeft: bottomLeft * factor
        )
    }

    func fitted(to size: CGSize) -> NICornerRadii {
        let positive = NICornerRadii(
            topLeft: max(topLeft, 0),
            topRight: max(topRight, 0),
            bottomRight: max(bottomRight, 0),
            bottomLeft: max(bottomLeft, 0)
        )
        let fit = { (sum: CGFloat, side: CGFloat) in
            sum > 0 ? max(side, 0) / sum : 1
        }
        return positive.scaled(by: min(
            1,
            fit(positive.topLeft + positive.topRight, size.width),
            fit(positive.bottomLeft + positive.bottomRight, size.width),
            fit(positive.topLeft + positive.bottomLeft, size.height),
            fit(positive.topRight + positive.bottomRight, size.height)
        ))
    }

    func path(in rect: CGRect) -> CGPath {
        let radii = fitted(to: rect.size)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + radii.topLeft, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
            radius: radii.topRight
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
            radius: radii.bottomRight
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY),
            radius: radii.bottomLeft
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: radii.topLeft
        )
        path.closeSubpath()
        return path
    }

    func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        guard
            (rect.minX...rect.maxX).contains(point.x),
            (rect.minY...rect.maxY).contains(point.y)
        else {
            return false
        }
        let radii = fitted(to: rect.size)
        func insideCorner(_ radius: CGFloat, _ outward: CGVector) -> Bool {
            let deltaX = point.x - (outward.dx < 0 ? rect.minX + radius : rect.maxX - radius)
            let deltaY = point.y - (outward.dy < 0 ? rect.minY + radius : rect.maxY - radius)
            let inCorner = deltaX * outward.dx > 0 && deltaY * outward.dy > 0
            return radius <= 0 || !inCorner ||
                deltaX * deltaX + deltaY * deltaY <= radius * radius
        }
        return insideCorner(radii.topLeft, CGVector(dx: -1, dy: -1)) &&
            insideCorner(radii.topRight, CGVector(dx: 1, dy: -1)) &&
            insideCorner(radii.bottomRight, CGVector(dx: 1, dy: 1)) &&
            insideCorner(radii.bottomLeft, CGVector(dx: -1, dy: 1))
    }
}

#if canImport(UIKit)
    import UIKit

    extension NICornerRadii {
        var maskedCorners: CACornerMask {
            var corners: CACornerMask = []
            if topLeft > 0 {
                corners.insert(.layerMinXMinYCorner)
            }
            if topRight > 0 {
                corners.insert(.layerMaxXMinYCorner)
            }
            if bottomRight > 0 {
                corners.insert(.layerMaxXMaxYCorner)
            }
            if bottomLeft > 0 {
                corners.insert(.layerMinXMaxYCorner)
            }
            return corners
        }
    }
#endif
