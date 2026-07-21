import Foundation

/// Platform-reported edge bands that must stay owned by system/web gesture handling.
struct NISystemGestureInsets: Equatable {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double

    init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    func contains(x: Double, y: Double, width: Double, height: Double) -> Bool {
        guard width > 0, height > 0, x >= 0, y >= 0, x < width, y < height else { return false }
        return (left > 0 && x < left) ||
            (top > 0 && y < top) ||
            (right > 0 && x >= width - right) ||
            (bottom > 0 && y >= height - bottom)
    }
}
