// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BadmintonCore",
    platforms: [
        .watchOS("11.0"),
        .iOS("17.0"),
        .macOS("14.0")
    ],
    products: [
        .library(name: "BadmintonCore", targets: ["BadmintonCore"])
    ],
    targets: [
        .target(name: "BadmintonCore"),
        .testTarget(name: "BadmintonCoreTests", dependencies: ["BadmintonCore"])
    ]
)
