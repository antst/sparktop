// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SparkTop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SparkTopCore", targets: ["SparkTopCore"]),
    ],
    targets: [
        // Platform-neutral data layer: sparkDash models, WebSocket store,
        // server configuration. Compiled into the macOS app and shared with
        // the iOS app (see ios/project.yml).
        .target(name: "SparkTopCore", path: "Sources/Core"),
        .executableTarget(
            name: "SparkTop",
            dependencies: [.target(name: "SparkTopCore")],
            path: "Sources/SparkTop"
        )
    ]
)
