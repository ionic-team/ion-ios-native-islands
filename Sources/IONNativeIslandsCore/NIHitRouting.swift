import Foundation

internal struct NIHitCandidate: Equatable {
    let id: String
    let interactive: Bool
    let excluded: Bool
}

internal struct NIHitDecision: Equatable {
    let owner: String
    let island: String?
    let reason: String

    init(owner: String, island: String? = nil, reason: String) {
        self.owner = owner
        self.island = island
        self.reason = reason
    }
}

internal enum NIHitRouting {
    static func decide(_ topmostFirst: [NIHitCandidate]) -> NIHitDecision {
        guard let top = topmostFirst.first else {
            return NIHitDecision(owner: "web", reason: "outside")
        }
        if !top.interactive {
            return NIHitDecision(owner: "web", reason: "non_interactive")
        }
        if top.excluded {
            return NIHitDecision(owner: "web", reason: "web_exclusion")
        }
        return NIHitDecision(
            owner: "island",
            island: top.id,
            reason: "interactive_island"
        )
    }
}
