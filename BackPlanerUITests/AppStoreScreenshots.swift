//
//  AppStoreScreenshots.swift
//  BackPlanerUITests
//
//  Walks through the screens shown in the App Store and saves a screenshot of
//  each. Run by scripts/appstore-screenshots.sh for every language and device;
//  in a normal test run it skips itself, since it works on the simulator's
//  real data and needs the recipe database online.
//
//  The numbers are the order on the product page, which opens with what sets
//  the app apart: the baking tab planned to a finish time, the next-step card,
//  the bake mode. The screens the app shares with every recipe app (the recipe
//  list, the settings) come last or only serve the manuals (numbers from 90
//  up, which the script keeps out of the App Store folder). The headline of
//  each picture is in docs/appstore/captions.json, keyed by the name after
//  the number; the script sets it over the picture.
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

    /// The baking tab opens on "Fertig bis" (see StoreUITestCase.planFinish).
    override var plansToFinish: Bool { true }

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

        // Recipe database (for the manuals), then the recipe's details and
        // its baking tab, planned to a finish time.
        openMenu("publicRecipes")
        let row = recipeRow(named: recipeName, id: recipeId)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The recipe database shows no recipes")
        settle(3) // thumbnails load after the list
        capture("93-rezept-datenbank")

        tapReliably(row)
        waitForRecipeDetails()
        translateIfNeeded()
        capture("07-rezept-details")

        tab(0, titled: ["de": "Rezept backen", "en": "Bake recipe", "fr": "Cuire la recette"]).tap()
        let controls = app.descendants(matching: .any)["plan.controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5), "The baking tab did not open")
        // The tab scrolls the controls to the top by itself (launch argument
        // -UITestingScrollToPlanControls, see StoreUITestCase.prepare);
        // scrollToTop only corrects what is left.
        settle(2.5)
        scrollToTop(controls)
        settle(1)
        capture("01-rezept-backen")

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
        capture("02-startbildschirm")

        // Bake mode and timeline of the planned steps.
        openMenu("scheduledSteps")
        let bakeMode = app.buttons["scheduled.bakeMode"]
        XCTAssertTrue(bakeMode.waitForExistence(timeout: 5), "Scheduled steps show no bake mode button")
        bakeMode.tap()
        settle(2)
        capture("03-backmodus")
        let close = app.buttons["bakeMode.close"]
        if close.waitForExistence(timeout: 3) { close.tap() }

        tab(1, titled: ["de": "Timeline", "en": "Timeline", "fr": "Timeline"]).tap()
        settle(2)
        capture("04-timeline")

        // Back in the recipe: the flour line opens "Mehl ersetzen", filled
        // with the recipe's flour and water.
        backToMenu()
        openDemoRecipe()
        let flourLine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1050")).firstMatch
        if flourLine.waitForExistence(timeout: 5) {
            scrollUntilHittable(flourLine)
            tapReliably(flourLine)
            let sheetTitle = ["de": "Mehl ersetzen", "en": "Replace flour", "fr": "Remplacer la farine"][language] ?? ""
            _ = app.staticTexts[sheetTitle].waitForExistence(timeout: 5)
            settle(1.5)
            capture("06-mehl-ersetzen")
            cancelSheet()
            settle(1)
        } else {
            // A recipe without such a line: the calculator from the main menu.
            backToMenu()
            openMenu("flourSubstitution")
            settle(1)
            capture("06-mehl-ersetzen")
            backToMenu()
            openDemoRecipe()
        }

        // The recipe's ingredients on a shopping list, then the list itself,
        // grouped by shelf. testPrepare has cleared the earlier lists.
        tab(2, titled: ["de": "Einkaufsliste", "en": "Shopping list", "fr": "Liste de courses"]).tap()
        settle(1)
        let create = app.buttons.matching(NSPredicate(format: "label IN %@",
            ["Einkaufsliste erstellen", "Create shopping list", "Créer une liste de courses"])).firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5), "The shopping-list tab shows no create button")
        scrollUntilHittable(create)
        tapRowButton(create)
        // The names are translated into the app's language first.
        acknowledgeAlertIfShown(timeout: 20)

        backToMenu()
        openMenu("shoppingList")
        settle(2)
        capture("09-einkaufsliste")

        // The calculators from the main menu.
        backToMenu()
        openMenu("starterYield")
        settle(1)
        capture("05-anstellgut-ta")

        backToMenu()
        openMenu("doughTemperature")
        settle(1)
        capture("10-teigtemperatur")

        // The form for a new recipe with its two imports and the
        // "Veröffentlichen" switch: a store picture and a manual picture.
        backToMenu()
        openMenu("newRecipe")
        settle(1)
        capture("08-rezept-import")
        capture("91-neues-rezept")

        // The top of the settings, for the manuals only.
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
