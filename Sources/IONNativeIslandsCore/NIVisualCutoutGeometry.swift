import CoreGraphics

enum NIVisualCutoutGeometry {
    static let edgeClearance: CGFloat = 1

    static func snappedOutward(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard scale > 0, !rect.isNull, !rect.isInfinite else { return rect }
        let minX = (rect.minX * scale).rounded(.down) / scale
        let minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale
        let maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func visiblePath(
        bounds: CGRect,
        cutouts: [(rect: CGRect, radii: NICornerRadii)]
    )
        -> CGPath {
        let shapes = cutouts
            .map { (rect: $0.rect.standardized, radii: $0.radii.fitted(to: $0.rect.size)) }
            .filter { $0.rect.intersects(bounds) }
        let kept = shapes.indices
            .filter { index in
                !shapes.indices.contains { other in
                    other != index &&
                        encloses(shapes[other], shapes[index].rect) &&
                        (other < index || !encloses(shapes[index], shapes[other].rect))
                }
            }
            .map { shapes[$0] }
        let rounded = kept.indices.filter { index in
            !kept[index].radii.isSquare && !kept.indices.contains {
                $0 != index && kept[$0].rect.intersects(kept[index].rect)
            }
        }

        let outer = bounds.insetBy(dx: -edgeClearance, dy: -edgeClearance)
        let path = CGMutablePath()
        path.addRect(outer)
        let square = kept.indices
            .filter { !rounded.contains($0) }
            .map { kept[$0].rect.intersection(outer) }
        for rect in union(square) {
            path.addRect(rect)
        }
        for index in rounded {
            path.addPath(kept[index].radii.path(in: kept[index].rect))
        }
        return path
    }

    private static func encloses(
        _ outer: (rect: CGRect, radii: NICornerRadii),
        _ inner: CGRect
    )
        -> Bool {
        [
            CGPoint(x: inner.minX, y: inner.minY),
            CGPoint(x: inner.maxX, y: inner.minY),
            CGPoint(x: inner.minX, y: inner.maxY),
            CGPoint(x: inner.maxX, y: inner.maxY),
        ].allSatisfy { outer.radii.contains($0, in: outer.rect) }
    }

    static func union(_ rects: [CGRect]) -> [CGRect] {
        let rects = rects
            .map(\.standardized)
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        let edges = Array(
            Set(rects.flatMap { [$0.minX, $0.maxX] })
        ).sorted()
        guard edges.count > 1 else { return [] }

        var output: [CGRect] = []
        var active: [YRange: Int] = [:]
        for index in 0..<(edges.count - 1) {
            let minX = edges[index]
            let maxX = edges[index + 1]
            guard maxX > minX else { continue }

            let intervals = mergedYRanges(
                rects
                    .filter { $0.minX < maxX && $0.maxX > minX }
                    .map { YRange(min: $0.minY, max: $0.maxY) }
            )
            var next: [YRange: Int] = [:]
            for interval in intervals {
                if let outputIndex = active[interval],
                   output[outputIndex].maxX == minX {
                    output[outputIndex].size.width = maxX - output[outputIndex].minX
                    next[interval] = outputIndex
                } else {
                    output.append(
                        CGRect(
                            x: minX,
                            y: interval.min,
                            width: maxX - minX,
                            height: interval.max - interval.min
                        )
                    )
                    next[interval] = output.count - 1
                }
            }
            active = next
        }
        return output
    }

    private static func mergedYRanges(_ ranges: [YRange]) -> [YRange] {
        let sorted = ranges.sorted {
            $0.min == $1.min ? $0.max < $1.max : $0.min < $1.min
        }
        var output: [YRange] = []
        for range in sorted {
            if let last = output.last, range.min <= last.max {
                output[output.count - 1] = YRange(
                    min: last.min,
                    max: max(last.max, range.max)
                )
            } else {
                output.append(range)
            }
        }
        return output
    }

    private struct YRange: Hashable {
        let min: CGFloat
        let max: CGFloat
    }
}
