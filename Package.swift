// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IONNativeIslandsLib",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "IONNativeIslandsLib",
            type: .dynamic,
            targets: ["IONNativeIslandsLib"]
        )
    ],
    targets: [
        // Pure logic: security gate, wire codec, registries, geometry — no UIKit.
        // Builds and tests on macOS, so `swift test` gives host-speed feedback.
        .target(
            name: "IONNativeIslandsCore"
        ),
        // The iOS runtime: container, controller, island protocols, probe island.
        // Sources are UIKit-gated, so the package still resolves on macOS.
        .target(
            name: "IONNativeIslandsLib",
            dependencies: ["IONNativeIslandsCore"]
        ),
        .testTarget(
            name: "IONNativeIslandsCoreTests",
            dependencies: ["IONNativeIslandsCore"]
        )
    ]
)
