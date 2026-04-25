// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Wisp",
            path: "Sources/Wisp"
        )
    ]
)
