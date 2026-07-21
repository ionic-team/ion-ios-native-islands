// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IONNativeIslandsLib",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "IONNativeIslandsLib",
            targets: ["IONNativeIslandsLib"]
        )
    ],
    targets: [
        .target(
            name: "IONNativeIslandsLib",
            path: "Sources"
        ),
        .testTarget(
            name: "IONNativeIslandsLibTests",
            dependencies: ["IONNativeIslandsLib"],
            path: "Tests/IONNativeIslandsCoreTests"
        )
    ]
)
