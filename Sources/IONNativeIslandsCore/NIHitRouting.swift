import Foundation

public struct NIHitCandidate: Equatable {
    public let id: String
    public let overlay: Bool
    public let interactive: Bool
    public let excluded: Bool

    public init(id: String, overlay: Bool, interactive: Bool, excluded: Bool) {
        self.id = id
        self.overlay = overlay
        self.interactive = interactive
        self.excluded = excluded
    }
}

public struct NIHitDecision: Equatable {
    public let owner: String
    public let island: String?
    public let reason: String

    public init(owner: String, island: String? = nil, reason: String) {
        self.owner = owner
        self.island = island
        self.reason = reason
    }
}

public enum NIHitRouting {
    public static func decide(_ topmostFirst: [NIHitCandidate]) -> NIHitDecision {
        guard let top = topmostFirst.first else {
            return NIHitDecision(owner: "web", reason: "outside")
        }
        if top.overlay { return NIHitDecision(owner: "web", reason: "overlay_occlusion") }
        if !top.interactive { return NIHitDecision(owner: "web", reason: "non_interactive") }
        if top.excluded { return NIHitDecision(owner: "web", reason: "web_exclusion") }
        return NIHitDecision(owner: "island", island: top.id, reason: "interactive_island")
    }
}

/// A native observer may react only where its view is visible to the page. An exclusion is a web
/// layer above it (such as Tejo's duration sheet), so it prevents observation as well as ownership.
public enum NIObserverRouting {
    public static func shouldObserve(pointIsInHost: Bool, excludedByWeb: Bool) -> Bool {
        pointIsInHost && !excludedByWeb
    }
}
