// swift-tools-version: 6.2
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "BakePlannerAndroid",
    defaultLocalization: "de",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "BakePlanner", type: .dynamic, targets: ["BakePlanner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0"),
        // BakePlanner's logic and the SQLite storage, from this repository.
        .package(path: "../BakePlannerCore"),
        .package(path: "../BakePlannerStorage"),
    ],
    targets: [
        .target(name: "BakePlanner", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "BakePlannerCore", package: "BakePlannerCore"),
            .product(name: "BakePlannerStorage", package: "BakePlannerStorage"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
