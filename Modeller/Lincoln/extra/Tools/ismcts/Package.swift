// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ismcts",
    targets: [
        .executableTarget(
            name: "ismcts",
            path: "Sources/ismcts",
            swiftSettings: [.unsafeFlags(["-O"])]
        )
    ]
)
