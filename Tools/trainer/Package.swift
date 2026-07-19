// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "trainer",
    targets: [
        .executableTarget(
            name: "trainer",
            path: "Sources/trainer",
            swiftSettings: [.unsafeFlags(["-O"])]
        )
    ]
)
