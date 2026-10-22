// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentSessionNotifier",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentSessionNotifier",
            path: "Sources/AgentSessionNotifier"
        )
    ]
)
