// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SessionNotifier",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SessionNotifier",
            path: "Sources/SessionNotifier"
        )
    ]
)
