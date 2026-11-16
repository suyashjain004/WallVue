// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallVue",
    platforms: [.macOS(.v14)],
    targets: [
        // UI-free core: models, library, settings, playback rules, schedule.
        .target(name: "WallVueCore", path: "Sources/WallVueCore"),
        // The macOS app: desktop video engine + SwiftUI interface.
        .executableTarget(name: "WallVueApp", dependencies: ["WallVueCore"], path: "Sources/WallVueApp"),
        .testTarget(name: "WallVueCoreTests", dependencies: ["WallVueCore"], path: "Tests/WallVueCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
