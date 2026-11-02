// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "manotify",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")],
    targets: [
        .target(name: "ManotifyKit", dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "manotify", dependencies: ["ManotifyKit"]),
        .testTarget(name: "ManotifyKitTests", dependencies: ["ManotifyKit"]),
    ]
)
