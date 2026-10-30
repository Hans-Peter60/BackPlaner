// swift-tools-version: 6.2
//
// The app's logic that does not depend on Apple-only frameworks, so it can
// be built for Android later (see docs/Android-Bestandsaufnahme.md). The
// app links the library; the tests run with ⌘U and with `swift test`.

import PackageDescription

let package = Package(
    name: "BakePlannerCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "BakePlannerCore", targets: ["BakePlannerCore"]),
        // A store in memory and the checks every store must pass, for the
        // package's tests and the app's.
        .library(name: "BakePlannerCoreTesting", targets: ["BakePlannerCoreTesting"]),
    ],
    targets: [
        .target(name: "BakePlannerCore"),
        .target(name: "BakePlannerCoreTesting", dependencies: ["BakePlannerCore"]),
        .testTarget(name: "BakePlannerCoreTests", dependencies: ["BakePlannerCore", "BakePlannerCoreTesting"]),
    ],
    // The same language mode as the app, so moved code compiles unchanged.
    swiftLanguageModes: [.v5]
)
