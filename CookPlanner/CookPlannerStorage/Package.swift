// swift-tools-version: 6.2
//
// The cook's own dishes kept in SQLite, for the CookPlanner app (see
// docs/cookplanner/Idee-Gegen-die-Uhr.md). A package of its own, apart from
// BakePlannerStorage: the two apps share the planner and the types in
// BakePlannerCore, not their data. SkipSQLPlus brings its own SQLite build
// and runs on iOS, macOS (swift test) and, in Skip's native mode, Android.

import PackageDescription

let package = Package(
    name: "CookPlannerStorage",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "CookPlannerStorage", targets: ["CookPlannerStorage"]),
    ],
    dependencies: [
        .package(path: "../../BakePlannerCore"),
        .package(url: "https://github.com/skiptools/skip-sql.git", from: "0.16.1"),
    ],
    targets: [
        .target(name: "CookPlannerStorage", dependencies: [
            .product(name: "BakePlannerCore", package: "BakePlannerCore"),
            .product(name: "SkipSQLPlus", package: "skip-sql"),
        ]),
        .testTarget(name: "CookPlannerStorageTests", dependencies: ["CookPlannerStorage"]),
    ],
    swiftLanguageModes: [.v5]
)
