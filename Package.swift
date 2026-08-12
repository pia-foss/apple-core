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
        ),
        // A product purely so Xcode generates a scheme for it: previews only run for a file the active
        // scheme compiles, and schemes come from products. Consumers never build this unless they
        // explicitly depend on it — it just appears in the product picker.
        .library(
            name: "SpaceshipDemo",
            targets: ["SpaceshipDemo"]
        )
    ],
    targets: [
        .target(
            name: "CoreArchitecture"
        ),
        .testTarget(
            name: "CoreArchitectureTests",
            dependencies: ["CoreArchitecture"]
        ),
        // A worked example. It builds and is tested with the package, so it cannot drift from the
        // library.
        .target(
            name: "SpaceshipDemo",
            dependencies: ["CoreArchitecture"]
        ),
        .testTarget(
            name: "SpaceshipDemoTests",
            dependencies: ["SpaceshipDemo", "CoreArchitecture"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
