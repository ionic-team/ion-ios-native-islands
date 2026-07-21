import CoreGraphics

enum NIVisualCutoutGeometry {
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
