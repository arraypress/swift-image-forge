// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-image-forge",
    // ImageIO, CoreGraphics, Vision and VideoGrade — no UI framework, so this
    // runs headless. The floor was macOS 15, set by the HDR gain-map encode
    // keys and the Swift-native Vision requests; it is macOS 26 because
    // VideoGrade is, and grading belongs in the same recipe as everything
    // else rather than in a second library a caller has to wire up.
    platforms: [
        .macOS(.v26), .iOS(.v26)
    ],
    products: [
        .library(name: "ImageForge", targets: ["ImageForge"]),
    ],
    dependencies: [
        // The colour and tone engine. Pure Core Image, no dependencies of its
        // own; this library calls it rather than reimplementing it.
        .package(url: "https://github.com/arraypress/swift-video-grade.git", from: "0.1.1"),
    ],
    targets: [
        .target(
            name: "ImageForge",
            dependencies: [.product(name: "VideoGrade", package: "swift-video-grade")]
        ),
        .testTarget(name: "ImageForgeTests", dependencies: ["ImageForge"]),
    ]
)
