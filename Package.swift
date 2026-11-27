// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The app, the widget and the XCTest suite need full Xcode (SwiftUI macros,
// XCTest). On a Mac with only the Command Line Tools, set TACK_CLT_ONLY=1 to
// build tackkit and run the swift-testing suite alone; see Docs/TESTING.md.
let cltOnly = ProcessInfo.processInfo.environment["TACK_CLT_ONLY"] != nil

let package = Package(
    name: "Tack",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TackCore", targets: ["TackCore"]),
        .library(name: "TackFormat", targets: ["TackFormat"]),
        .library(name: "TackCapture", targets: ["TackCapture"]),
        .library(name: "TackInterop", targets: ["TackInterop"]),
        .library(name: "TackAgent", targets: ["TackAgent"]),
        .executable(name: "tackkit", targets: ["tackkit"])
    ] + (cltOnly ? [] : [
        .executable(name: "Tack", targets: ["TackApp"]),
        .executable(name: "TackWidgets", targets: ["TackWidgets"])
    ]),
    targets: [
        .target(name: "TackCore"),
        .target(name: "TackFormat", dependencies: ["TackCore"]),
        .target(name: "TackCapture", dependencies: ["TackCore"]),
        .target(name: "TackInterop", dependencies: ["TackCore", "TackFormat"]),
        .target(name: "TackAgent", dependencies: ["TackCore", "TackFormat", "TackCapture"]),
        .executableTarget(name: "tackkit", dependencies: ["TackCore", "TackFormat", "TackCapture", "TackInterop", "TackAgent"]),
        .testTarget(name: "TackAgentTests", dependencies: ["TackCore", "TackFormat", "TackInterop", "TackAgent"])
    ] + (cltOnly ? [] : [
        .executableTarget(name: "TackApp", dependencies: ["TackCore", "TackFormat", "TackCapture", "TackInterop"]),
        // SwiftPM does not create an Xcode Widget Extension target for us. The
        // WidgetKit runtime therefore needs the same extension entry point that
        // Xcode supplies when it links a real .appex target.
        .executableTarget(
            name: "TackWidgets",
            dependencies: ["TackCore", "TackFormat"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .testTarget(name: "TackTests", dependencies: ["TackCore", "TackFormat", "TackCapture", "TackInterop"])
    ])
)
