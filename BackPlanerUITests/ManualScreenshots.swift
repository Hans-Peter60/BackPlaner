//
//  ManualScreenshots.swift
//  BackPlanerUITests
//
//  The manuals' pictures that need a device full of own recipes and a
//  baking history: the recipe list showing only the local recipes
//  ("Eigene Rezepte") and the photo cloud of the baking history. Run by
//  scripts/manual-screenshots.sh on a simulator that holds such data; the
//  store run (AppStoreScreenshots) cannot take them, it clears the
//  simulator's data first. Skips itself in a normal test run.
//
//  Settings come from the environment (xcodebuild hands TEST_RUNNER_<NAME>
//  to the test as <NAME>):
//    MANUAL_SCREENSHOT_LANGUAGE  de, en or fr — required, otherwise the test skips
//
//  The screenshots are attachments of the test result, named
//  "<language>-<number>-<screen>" like the store pictures; the script
//  exports and scales them.
//

import XCTest

final class ManualScreenshots: StoreUITestCase {

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let language = environment["MANUAL_SCREENSHOT_LANGUAGE"], !language.isEmpty else {
            throw XCTSkip("Only for scripts/manual-screenshots.sh (MANUAL_SCREENSHOT_LANGUAGE is not set).")
        }
        prepare(language: language)
        // Only the local recipes in the list: the two cloud chips off for
        // this run, without touching the simulator's own setting.
        app.launchArguments += ["-settings.recipeList.showLocal", "YES",
                                "-settings.recipeList.showOwnPublished", "NO",
                                "-settings.recipeList.showPublicCloud", "NO"]
    }

    @MainActor
    func testCaptureManualScreenshots() throws {
        launch()
        settle(3) // thumbnails
        allowSystemAlertIfShown()
        settle(1)
        capture("95-eigene-rezepte")

        // The baking history as a photo cloud: the fourth of the five
        // layouts under the title.
        openTab(.bakeHistory)
        let layouts = app.segmentedControls.firstMatch
        XCTAssertTrue(layouts.waitForExistence(timeout: 5), "The baking history shows no layout switch")
        XCTAssertTrue(layouts.buttons.count >= 4, "The baking history has fewer than four layouts")
        layouts.buttons.element(boundBy: 3).tap()
        settle(3) // the cloud lays itself out and loads its pictures
        capture("96-backhistorie-fotowolke")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
