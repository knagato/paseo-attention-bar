// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaseoAttentionBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PaseoAttentionBar",
            path: "Sources/PaseoAttentionBar",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
