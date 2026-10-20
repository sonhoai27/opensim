// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSim",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OpenSimCore", targets: ["OpenSimCore"]),
        .library(name: "OpenSimBridge", targets: ["OpenSimBridge"]),
        .executable(name: "opensim", targets: ["OpenSimCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(name: "OpenSimCore"),
        .target(name: "OpenSimBridge", dependencies: ["OpenSimCore"]),
        .executableTarget(
            name: "OpenSimCLI",
            dependencies: [
                "OpenSimCore",
                "OpenSimBridge",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "OpenSimCoreTests", dependencies: ["OpenSimCore"]),
        .testTarget(name: "OpenSimBridgeTests", dependencies: ["OpenSimBridge", "OpenSimCore"]),
        .testTarget(
            name: "OpenSimCLITests",
            dependencies: [
                "OpenSimCLI",
                "OpenSimCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
