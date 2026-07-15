import Foundation
import CoreGraphics

/// Pure CSS-document to native-view geometry shared by positioning and hit testing.
public enum NIContainerGeometry {
    public static func screenRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        zoom: CGFloat,
        offset: CGPoint,
        fixed: Bool = false
    ) -> CGRect {
        let scroll = fixed ? .zero : offset
        return CGRect(
            x: x * zoom - scroll.x,
            y: y * zoom - scroll.y,
            width: width * zoom,
            height: height * zoom
        )
    }
}
