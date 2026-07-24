// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iCanDoIt",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "iCanDoIt",
            path: "Sources/iCanDoIt",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
