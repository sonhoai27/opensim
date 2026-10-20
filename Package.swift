// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSim",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OpenSimCore", targets: ["OpenSimCore"]),
        .library(name: "OpenSimBridge", targets: ["OpenSimBridge"]),
        .library(name: "OpenSimBridgeUI", targets: ["OpenSimBridgeUI"]),
        .library(name: "OpenSimProtocol", targets: ["OpenSimProtocol"]),
        .library(name: "OpenSimDaemon", targets: ["OpenSimDaemon"]),
        .library(name: "OpenSimMCP", targets: ["OpenSimMCP"]),
        .executable(name: "opensim", targets: ["OpenSimCLI"]),
        .executable(name: "OpenSimPreview", targets: ["OpenSimPreview"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.60.0"),
    ],
    targets: [
        .target(name: "OpenSimCore"),
        .target(name: "OpenSimBridge", dependencies: ["OpenSimCore"]),
        .target(name: "OpenSimBridgeUI", dependencies: ["OpenSimCore", "OpenSimBridge"]),
        .target(name: "OpenSimProtocol", dependencies: ["OpenSimCore"]),
        .target(
            name: "OpenSimDaemon",
            dependencies: [
                "OpenSimCore",
                "OpenSimBridge",
                "OpenSimProtocol",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
        .target(
            name: "OpenSimMCP",
            dependencies: [
                "OpenSimCore",
                "OpenSimProtocol",
                "OpenSimDaemon",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "OpenSimPreview",
            dependencies: ["OpenSimCore", "OpenSimBridge", "OpenSimBridgeUI"]
        ),
        .executableTarget(
            name: "OpenSimCLI",
            dependencies: [
                "OpenSimCore",
                "OpenSimBridge",
                "OpenSimProtocol",
                "OpenSimDaemon",
                "OpenSimMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "OpenSimCoreTests", dependencies: ["OpenSimCore"]),
        .testTarget(name: "OpenSimProtocolTests", dependencies: ["OpenSimProtocol", "OpenSimCore"]),
        .testTarget(
            name: "OpenSimDaemonTests",
            dependencies: [
                "OpenSimDaemon",
                "OpenSimBridge",
                "OpenSimProtocol",
                "OpenSimCore",
                "OpenSimMCP",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(name: "OpenSimBridgeTests", dependencies: ["OpenSimBridge", "OpenSimCore"]),
        .testTarget(
            name: "OpenSimMCPTests",
            dependencies: ["OpenSimMCP", "OpenSimDaemon", "OpenSimProtocol", "OpenSimCore"]
        ),
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
