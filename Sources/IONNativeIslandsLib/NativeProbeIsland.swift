#if canImport(UIKit)
import UIKit

/// `<native-probe>` — the one island the runtime ships: a solid-color native view with a
/// text label. It exists so an integration can be proven end to end before any real
/// island is written: mount (`create`), attribute → command flow (`setColor`), native →
/// web events (`tap`), and the theme broadcast (`setTheme`) all cross the real bridge,
/// with zero native dependencies beyond UIKit.
public final class NativeProbeIsland: NativeIsland, NativeIslandEventEmitting {
    private let host = IslandHostView()
    private let title = UILabel()
    public var view: UIView { host }
    public var eventSink: ((String, [String: Any]) -> Void)?

    public init() {
        title.textColor = .white
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(title)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: 4)
        ])
        host.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @objc private func tapped() {
        eventSink?("tap", [:])
    }

    public func command(_ method: String, _ params: [String: Any]) {
        switch method {
        case "create", "setColor":
            if let hex = params["color"] as? String { host.backgroundColor = Self.color(hex) }
            if let label = params["label"] as? String { title.text = label }
        case "setTheme":
            break // the probe's color is author-driven; the broadcast is accepted, not styled
        default:
            break
        }
    }

    private static func color(_ hex: String) -> UIColor {
        var value: UInt64 = 0
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            return .systemBlue
        }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
}
#endif
