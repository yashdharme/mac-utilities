// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacUtilities",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacSpeed", targets: ["MacSpeed"]),
        .executable(name: "MacClip", targets: ["MacClip"])
    ],
    targets: [
        .executableTarget(name: "MacSpeed"),
        .executableTarget(name: "MacClip")
    ]
)
