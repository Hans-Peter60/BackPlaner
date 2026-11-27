// swift-tools-version: 6.1
//
// The one-time purchase "Pro" through Google Play Billing, for both Android
// apps (BakePlanner and CookPlanner). A transpiled Skip module with
// bridging, built like CookPlannerMedia: its Swift becomes Kotlin on
// Android, the app's native Swift starts it and reads its state. The
// iPhone apps buy through StoreKit.

import PackageDescription

let package = Package(
    name: "PlayBilling",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlayBilling", targets: ["PlayBilling"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.2.17"),
        .package(url: "https://github.com/skiptools/skip-ui.git", from: "1.66.0"),
    ],
    targets: [
        .target(name: "PlayBilling", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation"),
            .product(name: "SkipUI", package: "skip-ui"),
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
