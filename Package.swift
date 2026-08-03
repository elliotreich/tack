// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tack",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TackCore", targets: ["TackCore"]),
        .library(name: "TackFormat", targets: ["TackFormat"]),
        .library(name: "TackCapture", targets: ["TackCapture"]),
        .library(name: "TackInterop", targets: ["TackInterop"]),
        .executable(name: "Tack", targets: ["TackApp"]),
        .executable(name: "tackkit", targets: ["tackkit"])
    ],
    targets: [
        .target(name: "TackCore"),
        .target(name: "TackFormat", dependencies: ["TackCore"]),
        .target(name: "TackCapture", dependencies: ["TackCore"]),
        .target(name: "TackInterop", dependencies: ["TackCore", "TackFormat"]),
        .executableTarget(name: "TackApp", dependencies: ["TackCore", "TackFormat", "TackCapture", "TackInterop"]),
        .executableTarget(name: "tackkit", dependencies: ["TackCore", "TackFormat", "TackCapture", "TackInterop"]),
        .testTarget(name: "TackTests", dependencies: ["TackCore", "TackFormat", "TackCapture", "TackInterop"])
    ]
)
