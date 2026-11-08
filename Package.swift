// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Daily",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "daily", path: "Sources/Daily"),
        .testTarget(name: "DailyTests", dependencies: ["daily"])
    ]
)
