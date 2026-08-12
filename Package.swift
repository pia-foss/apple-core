// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CoreArchitecture",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
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
