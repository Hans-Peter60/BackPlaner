// swift-tools-version: 6.2
// This is a Skip (https://skip.dev) package: CookPlanner for Android.
// The planner and the dish types come from BakePlannerCore, the cook's
// dishes live in CookPlannerStorage (SQLite through SkipSQLPlus), both
// shared with the iPhone app (CookPlanner/). See
// docs/cookplanner/Android-CookPlanner.md.
import PackageDescription

let package = Package(
    name: "CookPlannerAndroid",
    defaultLocalization: "de",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "CookPlanner", type: .dynamic, targets: ["CookPlanner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0"),
        // The system's file picker and "save as" (SwiftUI's fileImporter is
        // a placeholder on Android).
        .package(url: "https://github.com/skiptools/skip-kit.git", from: "1.1.6"),
        // Symlinks next to this folder, as for BakePlanner: Skip's export
        // resolves "../../" in the generated package wrongly.
        .package(path: "../BakePlannerCore"),
        .package(path: "../CookPlannerStorage"),
        // Reading camera photos behind content:// addresses (BakePlanner's
        // transpiled module, shared).
        .package(path: "../BakePlannerMedia"),
        // Reading steps aloud (Android's TextToSpeech), BakePlanner's module.
        .package(path: "../BakePlannerSpeech"),
        // The plan and the yearbook as PDF (Android's PdfDocument).
        .package(path: "../CookPlannerMedia"),
    ],
    targets: [
        .target(name: "CookPlanner", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipKit", package: "skip-kit"),
            .product(name: "BakePlannerCore", package: "BakePlannerCore"),
            .product(name: "CookPlannerStorage", package: "CookPlannerStorage"),
            .product(name: "BakePlannerMedia", package: "BakePlannerMedia"),
            .product(name: "BakePlannerSpeech", package: "BakePlannerSpeech"),
            .product(name: "CookPlannerMedia", package: "CookPlannerMedia"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
