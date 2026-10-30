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
    ],
    targets: [
        .target(name: "BakePlannerCore"),
        .testTarget(name: "BakePlannerCoreTests", dependencies: ["BakePlannerCore"]),
    ],
    // The same language mode as the app, so moved code compiles unchanged.
    swiftLanguageModes: [.v5]
)
