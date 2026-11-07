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
//  the app apart: the plan sheet planned to a finish time, the next-step bar,
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

    /// The plan sheet opens on "Fertig bis" (see StoreUITestCase.planFinish).
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

        // The recipe list (for the manuals), then the recipe's page and
        // its plan sheet, planned to a finish time.
        let row = recipeRow(named: recipeName, id: recipeId)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The recipe database shows no recipes")
        settle(3) // thumbnails load after the list
        // The simulator's iCloud prompt comes up a moment after launch;
        // cancelling it makes the list load once more, so wait for the
        // row and the thumbnails again.
        allowSystemAlertIfShown()
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The recipe database shows no recipes after the iCloud prompt")
        settle(3)
        capture("93-rezept-datenbank")

        tapReliably(row)
        waitForRecipeDetails()
        translateIfNeeded()
        capture("07-rezept-details")

        openPlan()
        let controls = app.descendants(matching: .any)["plan.controls"]
        // The sheet scrolls the controls to the top by itself (launch
        // argument -UITestingScrollToPlanControls, see
        // StoreUITestCase.prepare); scrollToTop only corrects what is left.
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
        // The confirmation's OK closes the plan sheet as well.
        acknowledgeAlertIfShown(timeout: 5)

        // The recipe list with the next-step bar over its bottom edge.
        backToRecipeList()
        settle(1)
        capture("02-startbildschirm")

        // Bake mode and timeline of the planned steps. The timeline opens
        // first; the bake mode button is on the list.
        openTab(.scheduledSteps)
        showScheduledSteps(as: .list)
        let bakeMode = app.buttons["scheduled.bakeMode"]
        if !bakeMode.waitForExistence(timeout: 5) {
            attachHierarchy()
            XCTFail("Scheduled steps show no bake mode button")
            return
        }
        bakeMode.tap()
        settle(2)
        capture("03-backmodus")
        let close = app.buttons["bakeMode.close"]
        if close.waitForExistence(timeout: 3) { close.tap() }

        showScheduledSteps(as: .timeline)
        settle(2)
        capture("04-timeline")

        // Back in the recipe: the flour line opens "Mehl ersetzen", filled
        // with the recipe's flour and water.
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
            // A recipe without such a line: the calculator from "Mehr".
            backToRecipeList()
            openScreen("flourSubstitution")
            settle(1)
            capture("06-mehl-ersetzen")
            openDemoRecipe()
        }

        // The recipe's ingredients on a shopping list, then the list itself,
        // grouped by shelf. testPrepare has cleared the earlier lists.
        openShoppingListSheet()
        // By identifier: the button's label joins the accessibility label
        // with its visible title on some systems, and the English run on the
        // folded iPhone Duo found no button named exactly "Create shopping
        // list". The names of a public recipe are translated into the app's
        // language before the sheet settles, so the wait is generous.
        let create = app.buttons["shoppingList.create"]
        if !create.waitForExistence(timeout: 20) { attachHierarchy(named: "98-shopping-sheet") }
        XCTAssertTrue(create.exists, "The shopping-list sheet shows no create button")
        scrollUntilHittable(create)
        tapRowButton(create)
        // The names are translated into the app's language first.
        acknowledgeAlertIfShown(timeout: 20)
        closeSheetIfShown()

        openTab(.shoppingLists)
        settle(2)
        capture("09-einkaufsliste")

        // The calculators from the recipe list's "Mehr" menu.
        backToRecipeList()
        openScreen("starterYield")
        settle(1)
        capture("05-anstellgut-ta")

        backToRecipeList()
        openScreen("doughTemperature")
        settle(1)
        capture("10-teigtemperatur")

        // The form for a new recipe with its two imports and the
        // "Veröffentlichen" switch: a store picture and a manual picture.
        backToRecipeList()
        openScreen("newRecipe")
        settle(1)
        capture("08-rezept-import")
        capture("91-neues-rezept")

        // The top of the settings, for the manuals only.
        backToRecipeList()
        openScreen("settings")
        settle(1)
        capture("92-einstellungen")
    }

    // MARK: - Screenshots

    private func capture(_ name: String) {
        let screenshot = screenshotOfAppScreen()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A screenshot of the screen the app is on. The iPhone Duo has two:
    /// unfolded, the app runs on the inner one while `XCUIScreen.main`
    /// still names the outer, which is dark then, and the pictures came
    /// out black. The screen is told by its size against the app's window.
    private func screenshotOfAppScreen() -> XCUIScreenshot {
        let window = app.windows.firstMatch.frame.size
        let screens = XCUIScreen.screens
        guard screens.count > 1 else { return XCUIScreen.main.screenshot() }
        let shots = screens.map { $0.screenshot() }
        return shots.first { shot in
            abs(shot.image.size.width - window.width) < 2 && abs(shot.image.size.height - window.height) < 2
        } ?? XCUIScreen.main.screenshot()
    }
}
