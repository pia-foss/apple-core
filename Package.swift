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
        // A worked example. One target, with `SpaceshipFeature/` and `SpaceshipUI/` holding the two layers
        // ADR 0010 separates: shared logic and per-app views. `SpaceshipNavigation/` holds the UIKit
        // coordinators, which are per-app for the same reason the views are.
        //
        // The folders are a convention, not a boundary the compiler checks — a view and a reducer in one
        // target can reference each other freely. Splitting them into two targets would make the
        // dependency direction a build error; keeping one keeps the demo to a single scheme.
        .target(
            name: "SpaceshipDemo",
            dependencies: ["CoreArchitecture"],
            // The walkthrough lives beside the code it describes; it is documentation, not a resource.
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "SpaceshipDemoTests",
            dependencies: ["SpaceshipDemo", "CoreArchitecture"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
