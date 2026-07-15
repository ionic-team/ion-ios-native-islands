// Wire-codec golden vectors (test fixture; regenerate via codegen/golden-vectors.json).

import Foundation

public struct NIGoldenVector: Sendable {
    public let name: String
    public let input: String
    public let canonical: String
}

public enum NIGoldenVectors {
    public static let all: [NIGoldenVector] = [
        NIGoldenVector(name: "empty", input: "{}", canonical: "{}"),
        NIGoldenVector(name: "command", input: "{\"type\":\"command\",\"protocolVersion\":2,\"island\":\"map-1\",\"islandType\":\"map\",\"method\":\"setCamera\",\"params\":{\"zoom\":13,\"lng\":56.78,\"lat\":12.34}}", canonical: "{\"island\":\"map-1\",\"islandType\":\"map\",\"method\":\"setCamera\",\"params\":{\"lat\":12.34,\"lng\":56.78,\"zoom\":13},\"protocolVersion\":2,\"type\":\"command\"}"),
        NIGoldenVector(name: "nested-unicode", input: "{\"label\":\"Harbor 🌊\",\"enabled\":true,\"nothing\":null,\"items\":[3,0.125,\"line\\nbreak\",{\"z\":false,\"a\":\"quote \\\" slash /\"}]}", canonical: "{\"enabled\":true,\"items\":[3,0.125,\"line\\nbreak\",{\"a\":\"quote \\\" slash /\",\"z\":false}],\"label\":\"Harbor 🌊\",\"nothing\":null}")
    ]
}
