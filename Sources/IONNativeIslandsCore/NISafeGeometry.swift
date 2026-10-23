import CoreFoundation
import Foundation

struct NISafeRectValues: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let cornerRadii: NICornerRadii
}

enum NISafeGeometry {
    static func parseRect(_ value: [String: Any]) -> NISafeRectValues? {
        guard
            let x = strictNumber(value["x"]),
            let y = strictNumber(value["y"]),
            let width = strictNumber(value["w"]),
            let height = strictNumber(value["h"])
        else {
            return nil
        }

        let radii: [Double]
        if let rawRadii = value["r"] {
            guard
                let list = rawRadii as? [Any],
                list.count == 4
            else {
                return nil
            }
            radii = list.compactMap(strictNumber)
            guard radii.count == 4 else { return nil }
        } else {
            radii = [0, 0, 0, 0]
        }

        guard
            width > 0,
            height > 0,
            radii.allSatisfy({ $0 >= 0 })
        else {
            return nil
        }

        return NISafeRectValues(
            x: x,
            y: y,
            width: width,
            height: height,
            cornerRadii: NICornerRadii(
                topLeft: radii[0],
                topRight: radii[1],
                bottomRight: radii[2],
                bottomLeft: radii[3]
            )
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
