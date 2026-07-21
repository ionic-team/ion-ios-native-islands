import Foundation

struct NIScrollContainerGeometry: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let contentWidth: Double
    let contentHeight: Double
    let offsetX: Double
    let offsetY: Double
}

struct NIScrollContainerCandidate: Equatable {
    let key: Int
    let geometry: NIScrollContainerGeometry
    let ancestorKeys: [Int]

    init(
        key: Int,
        geometry: NIScrollContainerGeometry,
        ancestorKeys: [Int] = []
    ) {
        self.key = key
        self.geometry = geometry
        self.ancestorKeys = ancestorKeys
    }
}

struct NIScrollContainerDescriptor: Equatable {
    let geometry: NIScrollContainerGeometry
    let scrollPath: [String]

    init(
        geometry: NIScrollContainerGeometry,
        scrollPath: [String] = []
    ) {
        self.geometry = geometry
        self.scrollPath = scrollPath
    }
}

enum NIScrollContainerMatchFailure: Equatable {
    case missing
    case ambiguous
    case sharedCandidate
}

struct NIScrollContainerMatchResult: Equatable {
    let matches: [String: Int]
    let failures: [String: NIScrollContainerMatchFailure]
}

enum NIScrollContainerMatching {
    static func match(
        descriptors: [String: NIScrollContainerDescriptor],
        candidates: [NIScrollContainerCandidate],
        tolerance: Double
    )
        -> NIScrollContainerMatchResult {
        var matches: [String: Int] = [:]
        var failures: [String: NIScrollContainerMatchFailure] = [:]
        let depths = Set(descriptors.values.map(\.scrollPath.count)).sorted()

        for depth in depths {
            var proposed: [String: NIScrollContainerCandidate] = [:]
            let current = descriptors
                .filter { $0.value.scrollPath.count == depth }
                .sorted { $0.key < $1.key }

            for (id, descriptor) in current {
                let ancestorKeys = descriptor.scrollPath.compactMap {
                    matches[$0]
                }
                guard ancestorKeys.count == descriptor.scrollPath.count else {
                    failures[id] = .missing
                    continue
                }
                let geometricMatches = candidates.filter { candidate in
                    geometriesMatch(
                        descriptor.geometry,
                        candidate.geometry,
                        tolerance: tolerance
                    )
                }
                let matchedKeys = Set(matches.values)
                let topologyMatches = geometricMatches.filter { candidate in
                    candidate.ancestorKeys.filter(matchedKeys.contains) ==
                        ancestorKeys
                }
                let eligible = topologyMatches.count == 1
                    ? topologyMatches
                    : geometricMatches.count == 1
                    ? geometricMatches
                    : topologyMatches
                guard eligible.count == 1 else {
                    failures[id] = eligible.isEmpty ? .missing : .ambiguous
                    continue
                }
                proposed[id] = eligible[0]
            }

            var claims: [Int: [String]] = [:]
            for (id, candidate) in proposed {
                claims[candidate.key, default: []].append(id)
            }
            for (id, candidate) in proposed {
                guard claims[candidate.key]?.count == 1 else {
                    failures[id] = .sharedCandidate
                    continue
                }
                matches[id] = candidate.key
            }
        }
        return NIScrollContainerMatchResult(
            matches: matches,
            failures: failures
        )
    }

    private static func geometriesMatch(
        _ lhs: NIScrollContainerGeometry,
        _ rhs: NIScrollContainerGeometry,
        tolerance: Double
    )
        -> Bool {
        close(lhs.x, rhs.x, tolerance: tolerance) &&
            close(lhs.y, rhs.y, tolerance: tolerance) &&
            close(lhs.width, rhs.width, tolerance: tolerance) &&
            close(lhs.height, rhs.height, tolerance: tolerance) &&
            close(
                lhs.contentWidth,
                rhs.contentWidth,
                tolerance: tolerance
            ) &&
            close(
                lhs.contentHeight,
                rhs.contentHeight,
                tolerance: tolerance
            ) &&
            close(lhs.offsetX, rhs.offsetX, tolerance: tolerance) &&
            close(lhs.offsetY, rhs.offsetY, tolerance: tolerance)
    }

    private static func close(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double
    )
        -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
