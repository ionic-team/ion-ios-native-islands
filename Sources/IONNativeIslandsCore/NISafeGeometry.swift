import CoreFoundation
import Foundation

struct NISafeRectValues: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let cornerRadius: Double
}

enum NISafeGeometry {
    /// CSS coordinates remain exact when converted through the Float-backed native
    /// rendering path up to 2^24. Extents use a smaller explicit allocation bound.
    static let maxCoordinateMagnitude =
        NIBridgeContract.maxCoordinateMagnitudeCSSPixels
    static let maxExtent = NIBridgeContract.maxSizeCSSPixels
    static let maxRadius = NIBridgeContract.maxRadiusCSSPixels

    static func parseRect(_ value: [String: Any]) -> NISafeRectValues? {
        guard
            let x = strictNumber(value["x"]),
            let y = strictNumber(value["y"]),
            let width = strictNumber(value["w"]),
            let height = strictNumber(value["h"])
        else {
            return nil
        }

        let cornerRadius: Double
        if let rawRadius = value["r"] {
            guard let radius = strictNumber(rawRadius) else { return nil }
            cornerRadius = radius
        } else {
            cornerRadius = 0
        }

        guard
            abs(x) <= maxCoordinateMagnitude,
            abs(y) <= maxCoordinateMagnitude,
            width > 0,
            width <= maxExtent,
            height > 0,
            height <= maxExtent,
            cornerRadius >= 0,
            cornerRadius <= maxRadius
        else {
            return nil
        }

        return NISafeRectValues(
            x: x,
            y: y,
            width: width,
            height: height,
            cornerRadius: cornerRadius
        )
    }

    static func strictNumber(_ value: Any?) -> Double? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        return number.doubleValue.isFinite ? number.doubleValue : nil
    }
}
