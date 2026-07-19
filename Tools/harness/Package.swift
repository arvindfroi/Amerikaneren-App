// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "harness",
    targets: [
        .executableTarget(
            name: "harness",
            path: "Sources/harness",
            swiftSettings: [.unsafeFlags(["-O"])]
        )
    ]
)
