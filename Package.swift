// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiteMD",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LiteMD", targets: ["LiteMD"])
    ],
    targets: [
        .executableTarget(
            name: "LiteMD",
            path: "Sources/LiteMD"
        )
    ]
)
