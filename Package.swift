// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-image-forge",
    // ImageIO, CoreGraphics and Vision only — no UI framework, so this runs
    // on every Apple platform and in a headless process. The floor is set by
    // the HDR gain-map encode keys and the Swift-native Vision request API,
    // both of which arrived in the macOS 15 / iOS 18 SDKs.
    platforms: [
        .macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)
    ],
    products: [
        .library(name: "ImageForge", targets: ["ImageForge"]),
    ],
    targets: [
        .target(name: "ImageForge"),
        .testTarget(name: "ImageForgeTests", dependencies: ["ImageForge"]),
    ]
)
