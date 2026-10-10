// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SparkTop",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SparkTop",
            path: "Sources/SparkTop"
        )
    ]
)
