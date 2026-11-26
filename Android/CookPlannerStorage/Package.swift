// swift-tools-version: 6.2
//
// CookPlannerStorage for the Android app: the same sources as
// CookPlanner/CookPlannerStorage (linked, not copied), under a manifest
// that finds BakePlannerCore as "../BakePlannerCore". Skip's export links
// every local package into one Packages folder, where the iPhone
// manifest's "../../BakePlannerCore" points nowhere. Tests stay with the
// iPhone package (`swift test` in CookPlanner/CookPlannerStorage).

import PackageDescription

let package = Package(
    name: "CookPlannerStorage",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "CookPlannerStorage", targets: ["CookPlannerStorage"]),
    ],
    dependencies: [
        .package(path: "../BakePlannerCore"),
        .package(url: "https://github.com/skiptools/skip-sql.git", from: "0.16.1"),
    ],
    targets: [
        .target(name: "CookPlannerStorage", dependencies: [
            .product(name: "BakePlannerCore", package: "BakePlannerCore"),
            .product(name: "SkipSQLPlus", package: "skip-sql"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
