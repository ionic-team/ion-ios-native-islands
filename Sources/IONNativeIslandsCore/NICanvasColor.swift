struct NITintColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init?(_ value: Any?) {
        guard
            let channels = value as? [Any],
            channels.count == 4
        else {
            return nil
        }
        let numbers = channels.compactMap { NISafeGeometry.strictNumber($0) }
        guard
            numbers.count == 4,
            numbers.prefix(3).allSatisfy({ (0 ... 255).contains($0) && $0.rounded() == $0 }),
            (0 ... 1).contains(numbers[3])
        else {
            return nil
        }
        red = numbers[0] / 255
        green = numbers[1] / 255
        blue = numbers[2] / 255
        alpha = numbers[3]
    }
}

struct NICanvasColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init?(_ value: Any?) {
        guard
            let hex = value as? String,
            hex.count == 7,
            hex.first == "#",
            hex.dropFirst().allSatisfy(\.isHexDigit),
            let rgb = UInt32(hex.dropFirst(), radix: 16)
        else {
            return nil
        }
        red = Double((rgb >> 16) & 0xFF) / 255
        green = Double((rgb >> 8) & 0xFF) / 255
        blue = Double(rgb & 0xFF) / 255
    }
}
