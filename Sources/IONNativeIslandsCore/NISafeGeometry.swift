import CoreFoundation
import CoreGraphics
import Foundation

struct IslandRect: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var cornerRadii: NICornerRadii

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Whether `point` falls inside this rect and its rounded corners.
    func contains(_ point: CGPoint) -> Bool {
        cornerRadii.contains(point, in: cgRect)
    }

    /// Whether this rounded rect covers a box of `size` at the origin, corners included.
    func containsBox(_ size: CGSize) -> Bool {
        let right = x + width
        let bottom = y + height
        guard x <= 0, y <= 0, right >= size.width, bottom >= size.height else { return false }
        let radii = cornerRadii
        return (radii.topLeft <= 0 || x + radii.topLeft <= 0 || y + radii.topLeft <= 0) &&
            (radii.topRight <= 0 || right - radii.topRight >= size.width || y + radii.topRight <= 0) &&
            (radii.bottomRight <= 0 || right - radii.bottomRight >= size.width || bottom - radii.bottomRight >= size.height) &&
            (radii.bottomLeft <= 0 || x + radii.bottomLeft <= 0 || bottom - radii.bottomLeft >= size.height)
    }
}

/// Strict readers for bridge JSON: a boolean is never a number, and numbers are finite.
enum NISafeGeometry {
    /// A rect with an area; `allowsEmpty` also takes one with none, as a sticky box sticks at no
    /// height of its own, carrying what overflows it.
    static func parseRect(_ value: [String: Any], allowsEmpty: Bool = false) -> IslandRect? {
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
            allowsEmpty ? width >= 0 : width > 0,
            allowsEmpty ? height >= 0 : height > 0,
            radii.allSatisfy({ $0 >= 0 })
        else {
            return nil
        }

        return IslandRect(
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

    /// `value` as an array of exactly `count` finite numbers.
    static func numbers(_ value: Any?, count: Int) -> [CGFloat]? {
        guard let list = value as? [Any], list.count == count else { return nil }
        let numbers = list.compactMap(strictNumber).map { CGFloat($0) }
        return numbers.count == count ? numbers : nil
    }

    static func strictInteger(_ value: Any?) -> Int? {
        guard
            let number = strictNumber(value),
            number.rounded(.towardZero) == number,
            number >= Double(Int.min),
            number <= Double(Int.max)
        else {
            return nil
        }
        return Int(number)
    }

    static func strictBool(_ value: Any?) -> Bool? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            return nil
        }
        return number.boolValue
    }
}
