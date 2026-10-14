//
//  AppStoreScreenshots.swift
//  BackPlanerUITests
//
//  Walks through the screens shown in the App Store and saves a screenshot of
//  each. Run by scripts/appstore-screenshots.sh for every language and device;
//  in a normal test run it skips itself, since it works on the simulator's
//  real data and needs the recipe database online.
//
//  Settings come from the environment (xcodebuild hands TEST_RUNNER_<NAME> to
//  the test as <NAME>):
//    SCREENSHOT_LANGUAGE  de, en or fr — required, otherwise the test skips
//    SCREENSHOT_RECIPE    the public recipe to show, by the start of its name
//
//  The screenshots are attachments of the test result, named
//  "<language>-<number>-<screen>"; the script exports them from there. The
//  test runs inside the simulator and may not write to the Mac's folders.
//  The moves through the app live in StoreUITestCase, shared with the
//  App Store previews.
//

import XCTest

final class AppStoreScreenshots: StoreUITestCase {

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let language = environment["SCREENSHOT_LANGUAGE"], !language.isEmpty else {
            throw XCTSkip("Only for scripts/appstore-screenshots.sh (SCREENSHOT_LANGUAGE is not set).")
        }
        prepare(language: language)
    }

    @MainActor
    func testCaptureStoreScreenshots() throws {
        launch()

        // Recipe database, then the recipe's details and its baking tab.
        openMenu("publicRecipes")
        let row = recipeRow(named: recipeName, id: recipeId)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The recipe database shows no recipes")
        settle(3) // thumbnails load after the list
        capture("02-rezept-datenbank")

        tapReliably(row)
        translateIfNeeded()
        capture("03-rezept-details")

        tab(0, titled: ["de": "Rezept backen", "en": "Bake recipe", "fr": "Cuire la recette"]).tap()
        let controls = app.descendants(matching: .any)["plan.controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5), "The baking tab did not open")
        scrollToTop(controls)
        settle(1)
        capture("04-rezept-backen")

        // Plan it, so the start screen and the bake mode have a next step.
        let setReminders = app.buttons["plan.setReminders"]
        scrollUntilHittable(setReminders)
        tapReliably(setReminders)
        // From the second run on the recipe already has a plan; replace it.
        let replaceTitle = ["de": "Bestehenden Plan ersetzen", "en": "Replace existing plan",
                            "fr": "Remplacer le plan existant"][language] ?? ""
        let replace = app.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier == 'plan.replace' OR label == %@", replaceTitle))
            .firstMatch
        if replace.waitForExistence(timeout: 3) {
            replace.tap()
        }
        allowSystemAlertIfShown()
        acknowledgeAlertIfShown(timeout: 5)

        backToMenu()
        settle(1)
        capture("01-startbildschirm")

        // Bake mode and timeline of the planned steps.
        openMenu("scheduledSteps")
        let bakeMode = app.buttons["scheduled.bakeMode"]
        XCTAssertTrue(bakeMode.waitForExistence(timeout: 5), "Scheduled steps show no bake mode button")
        bakeMode.tap()
        settle(2)
        capture("05-backmodus")
        let close = app.buttons["bakeMode.close"]
        if close.waitForExistence(timeout: 3) { close.tap() }

        tab(1, titled: ["de": "Timeline", "en": "Timeline", "fr": "Timeline"]).tap()
        settle(2)
        capture("06-timeline")

        // The recipe's shopping list.
        backToMenu()
        openDemoRecipe()
        tab(2, titled: ["de": "Einkaufsliste", "en": "Shopping list", "fr": "Liste de courses"]).tap()
        settle(2)
        capture("07-einkaufsliste")

        // The starter TA calculator, new in 2.0.
        backToMenu()
        openMenu("starterYield")
        settle(1)
        capture("08-anstellgut-ta")

        // Two screens for the manuals only (numbers from 90 up are kept out
        // of the App Store folder by the script): the form for a new recipe
        // with its "Veröffentlichen" switch, and the top of the settings.
        backToMenu()
        openMenu("newRecipe")
        settle(1)
        capture("91-neues-rezept")

        backToMenu()
        openMenu("settings")
        settle(1)
        capture("92-einstellungen")
    }

    // MARK: - Screenshots

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
