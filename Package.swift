// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSim",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OpenSimCore", targets: ["OpenSimCore"]),
        .library(name: "OpenSimBridge", targets: ["OpenSimBridge"]),
    ],
    targets: [
        .target(name: "OpenSimCore"),
        .target(name: "OpenSimBridge", dependencies: ["OpenSimCore"]),
        .testTarget(name: "OpenSimCoreTests", dependencies: ["OpenSimCore"]),
        .testTarget(name: "OpenSimBridgeTests", dependencies: ["OpenSimBridge", "OpenSimCore"]),
    ],
    swiftLanguageModes: [.v6]
)
