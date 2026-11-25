// swift-tools-version: 6.1
//
// Reading a text aloud for the Android app's bake mode. A transpiled Skip
// module with bridging, built like skip-device: its Swift becomes Kotlin
// on Android, where it drives the system's TextToSpeech, and the app's
// native Swift calls it across the bridge. On Apple platforms it uses
// AVSpeechSynthesizer. The iOS app does not use this package.

import PackageDescription

let package = Package(
    name: "BakePlannerSpeech",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BakePlannerSpeech", targets: ["BakePlannerSpeech"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.2.17"),
    ],
    targets: [
        .target(name: "BakePlannerSpeech", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)

if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
    package.dependencies += [.package(url: "https://github.com/skiptools/skip-bridge.git", "0.0.0"..<"2.0.0")]
    package.targets.forEach({ target in
        target.dependencies += [.product(name: "SkipBridge", package: "skip-bridge")]
        target.swiftSettings = (target.swiftSettings ?? []) + [.define("SKIP_BRIDGE")]
    })
    // all library types must be dynamic to support bridging
    package.products = package.products.map({ product in
        guard let libraryProduct = product as? Product.Library else { return product }
        return .library(name: libraryProduct.name, type: .dynamic, targets: libraryProduct.targets)
    })
}
