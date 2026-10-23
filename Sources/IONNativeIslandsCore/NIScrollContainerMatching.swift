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
    let order: Int

    init(
        geometry: NIScrollContainerGeometry,
        scrollPath: [String] = [],
        order: Int = 0
    ) {
        self.geometry = geometry
        self.scrollPath = scrollPath
        self.order = order
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
        tolerance: Double,
        optional: Set<String> = []
    )
        -> NIScrollContainerMatchResult {
        var matches: [String: Int] = [:]
        var failures: [String: NIScrollContainerMatchFailure] = [:]
        var unbound: Set<String> = []
        let depths = Set(descriptors.values.map(\.scrollPath.count)).sorted()

        for depth in depths {
            var wanting: [Claim] = []
            let current = descriptors
                .filter { $0.value.scrollPath.count == depth }
                .sorted { $0.key < $1.key }

            for (id, descriptor) in current {
                let ancestorKeys = descriptor.scrollPath.compactMap {
                    matches[$0]
                }
                guard descriptor.scrollPath.allSatisfy({
                    matches[$0] != nil || unbound.contains($0)
                }) else {
                    failures[id] = .missing
                    continue
                }
                let eligible = eligibleCandidates(
                    for: descriptor.geometry,
                    ancestorKeys: ancestorKeys,
                    matchedKeys: Set(matches.values),
                    candidates: candidates,
                    tolerance: tolerance
                )
                if eligible.isEmpty, optional.contains(id) {
                    unbound.insert(id)
                    continue
                }
                guard !eligible.isEmpty else {
                    failures[id] = .missing
                    continue
                }
                guard lookalikes(eligible, tolerance: tolerance) else {
                    failures[id] = .ambiguous
                    continue
                }
                wanting.append(
                    Claim(
                        id: id,
                        descriptor: descriptor,
                        candidates: eligible.sorted { $0.key > $1.key }
                    )
                )
            }

            let paired = pair(wanting, tolerance: tolerance)
            failures.merge(paired.failures) { $1 }
            let proposed = paired.proposed
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

    private static func eligibleCandidates(
        for geometry: NIScrollContainerGeometry,
        ancestorKeys: [Int],
        matchedKeys: Set<Int>,
        candidates: [NIScrollContainerCandidate],
        tolerance: Double
    )
        -> [NIScrollContainerCandidate] {
        let exactMatches = candidates.filter {
            geometriesMatch(geometry, $0.geometry, tolerance: tolerance)
        }
        let geometricMatches = exactMatches.isEmpty
            ? candidates.filter {
                geometriesMatch(
                    geometry,
                    $0.geometry,
                    tolerance: tolerance,
                    includingOffset: false
                )
            }
            : exactMatches
        let topologyMatches = geometricMatches.filter {
            $0.ancestorKeys.filter(matchedKeys.contains) == ancestorKeys
        }
        return topologyMatches.count == 1
            ? topologyMatches
            : geometricMatches.count == 1
            ? geometricMatches
            : topologyMatches
    }

    private struct Claim {
        let id: String
        let descriptor: NIScrollContainerDescriptor
        let candidates: [NIScrollContainerCandidate]
    }

    private static func pair(
        _ claims: [Claim],
        tolerance: Double
    )
        -> (
            proposed: [String: NIScrollContainerCandidate],
            failures: [String: NIScrollContainerMatchFailure]
        ) {
        var proposed: [String: NIScrollContainerCandidate] = [:]
        var failures: [String: NIScrollContainerMatchFailure] = [:]
        for group in Dictionary(grouping: claims, by: { $0.candidates.map(\.key) }).values {
            let ordered = group.sorted { $0.descriptor.order < $1.descriptor.order }
            let top = ordered[0].descriptor
            let alike = ordered.allSatisfy {
                $0.descriptor.scrollPath == top.scrollPath &&
                    geometriesMatch(
                        $0.descriptor.geometry,
                        top.geometry,
                        tolerance: tolerance
                    )
            }
            for (index, claim) in ordered.enumerated() {
                if alike, claim.candidates.indices.contains(index) {
                    proposed[claim.id] = claim.candidates[index]
                } else {
                    failures[claim.id] = .sharedCandidate
                }
            }
        }
        return (proposed, failures)
    }

    private static func lookalikes(
        _ candidates: [NIScrollContainerCandidate],
        tolerance: Double
    )
        -> Bool {
        candidates.allSatisfy { candidate in
            candidate.ancestorKeys == candidates[0].ancestorKeys &&
                geometriesMatch(
                    candidate.geometry,
                    candidates[0].geometry,
                    tolerance: tolerance
                )
        }
    }

    static func offsetsMatch(
        _ lhs: NIScrollContainerGeometry,
        _ rhs: NIScrollContainerGeometry,
        tolerance: Double
    )
        -> Bool {
        close(lhs.offsetX, rhs.offsetX, tolerance: tolerance) &&
            close(lhs.offsetY, rhs.offsetY, tolerance: tolerance)
    }

    private static func geometriesMatch(
        _ lhs: NIScrollContainerGeometry,
        _ rhs: NIScrollContainerGeometry,
        tolerance: Double,
        includingOffset: Bool = true
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
            (!includingOffset || offsetsMatch(lhs, rhs, tolerance: tolerance))
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
