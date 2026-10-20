// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSim",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OpenSimCore", targets: ["OpenSimCore"]),
    ],
    targets: [
        .target(name: "OpenSimCore"),
        .testTarget(name: "OpenSimCoreTests", dependencies: ["OpenSimCore"]),
    ],
    swiftLanguageModes: [.v6]
)
