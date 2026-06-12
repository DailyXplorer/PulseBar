// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PulseBarCore",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "PulseBarCore", targets: ["PulseBarCore"])
    ],
    targets: [
        .target(name: "PulseBarCore"),
        .testTarget(name: "PulseBarCoreTests", dependencies: ["PulseBarCore"])
    ]
)
