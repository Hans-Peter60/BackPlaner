// swift-tools-version: 6.1
//
// CookPlanner's printed pages on Android – the plan and the cooking
// yearbook as PDF, drawn with Android's PdfDocument. A transpiled Skip
// module with bridging, built like BakePlannerMedia: its Swift becomes
// Kotlin on Android, the app's native Swift calls it across the bridge
// with the pages described as JSON. The iPhone app has its own renderers.

import PackageDescription

let package = Package(
    name: "CookPlannerMedia",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CookPlannerMedia", targets: ["CookPlannerMedia"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.2.17"),
    ],
    targets: [
        .target(name: "CookPlannerMedia", dependencies: [
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
