// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CoreArchitecture",
    // The sources import only Foundation and Combine, so every Apple platform is supported.
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "CoreArchitecture",
            targets: ["CoreArchitecture"]
        )
    ],
    targets: [
        .target(
            name: "CoreArchitecture"
        ),
        .testTarget(
            name: "CoreArchitectureTests",
            dependencies: ["CoreArchitecture"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
