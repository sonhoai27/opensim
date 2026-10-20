// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSim",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OpenSimCore", targets: ["OpenSimCore"]),
        .library(name: "OpenSimBridge", targets: ["OpenSimBridge"]),
        .library(name: "OpenSimBridgeUI", targets: ["OpenSimBridgeUI"]),
        .executable(name: "opensim", targets: ["OpenSimCLI"]),
        .executable(name: "OpenSimPreview", targets: ["OpenSimPreview"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(name: "OpenSimCore"),
        .target(name: "OpenSimBridge", dependencies: ["OpenSimCore"]),
        .target(name: "OpenSimBridgeUI", dependencies: ["OpenSimCore", "OpenSimBridge"]),
        .executableTarget(
            name: "OpenSimPreview",
            dependencies: ["OpenSimCore", "OpenSimBridge", "OpenSimBridgeUI"]
        ),
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
            name: "OpenSimBridgeUITests",
            dependencies: ["OpenSimBridgeUI", "OpenSimBridge", "OpenSimCore"]
        ),
        .testTarget(
            name: "OpenSimCLITests",
            dependencies: [
                "OpenSimCLI",
                "OpenSimCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["OpenSimCore", "OpenSimBridge", "OpenSimBridgeUI"],
            exclude: ["README.md"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
