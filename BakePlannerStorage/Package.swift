// swift-tools-version: 6.2
//
// The user's own data kept in SQLite, for the Android app (see
// docs/Android-Bestandsaufnahme.md). A package of its own so the iOS app,
// which keeps its data in Core Data, does not resolve or link SQLite.
// SkipSQLPlus brings its own SQLite build: in Skip's native mode Android's
// system SQLite cannot be reached from Swift.

import PackageDescription

let package = Package(
    name: "BakePlannerStorage",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "BakePlannerStorage", targets: ["BakePlannerStorage"]),
    ],
    dependencies: [
        .package(path: "../BakePlannerCore"),
        .package(url: "https://github.com/skiptools/skip-sql.git", from: "0.16.1"),
    ],
    targets: [
        .target(name: "BakePlannerStorage", dependencies: [
            .product(name: "BakePlannerCore", package: "BakePlannerCore"),
            .product(name: "SkipSQLPlus", package: "skip-sql"),
        ]),
        .testTarget(name: "BakePlannerStorageTests", dependencies: ["BakePlannerStorage"]),
    ],
    swiftLanguageModes: [.v5]
)
