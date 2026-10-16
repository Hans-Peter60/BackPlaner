//
//  AppPreview.swift
//  BackPlanerUITests
//
//  Drives the app through the three scenes of the App Store previews while
//  scripts/appstore-previews.sh records the simulator's screen. Each scene is
//  a test of its own, so the script gets one movie per scene; the pauses are
//  there for the viewer, not for the app. Cutting, captions and the export in
//  App Store Connect's sizes are done afterwards in iMovie ("App-Vorschau").
//
//    PREVIEW_LANGUAGE   de, en or fr — required, otherwise the tests skip
//    SCREENSHOT_RECIPE  the public recipe to show (see StoreUITestCase)
//
//  The app is launched with `-UITestingPlanStart 20:00` (StoreUITestCase,
//  UITestSupport), so the baking tab opens with this evening as the plan's
//  start.
//
//  In a normal test run the tests skip themselves: they work on the
//  simulator's real data and need the recipe database online.
//

import XCTest

final class AppPreview: StoreUITestCase {

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let language = environment["PREVIEW_LANGUAGE"], !language.isEmpty else {
            throw XCTSkip("Only for scripts/appstore-previews.sh (PREVIEW_LANGUAGE is not set).")
        }
        prepare(language: language)
    }

    // MARK: - Preparation (not recorded)

    /// Clears what earlier runs left behind: the local copy of the recipe
    /// that setting the reminders stores on the device, so the recipe list
    /// shows the recipe once and not once from the device and once from the
    /// database; every planned step, so the plan scene shows one plan in the
    /// run's language and no "there is already a plan" dialog; and every
    /// shopping list, so the shopping scene's list holds the recipe once and
    /// not its amounts added up run after run. The preview script runs this
    /// before every scene, the screenshot script before every language,
    /// without recording — planning the recipe leaves the copy and the plan
    /// behind again.
    @MainActor
    func testPrepare() throws {
        launch()

        deleteLocalCopiesOfDemoRecipe()

        backToMenu()
        openMenu("scheduledSteps")
        let deleteSteps = app.buttons.matching(NSPredicate(format: "label IN %@",
            ["Geplante Schritte löschen", "Delete scheduled steps", "Supprimer les étapes planifiées"])).firstMatch
        if deleteSteps.waitForExistence(timeout: 5) {
            deleteSteps.tap()
            let all = app.buttons.matching(NSPredicate(format: "label IN %@",
                ["Alle löschen", "Delete all", "Tout supprimer"])).firstMatch
            if all.waitForExistence(timeout: 3) {
                all.tap()
            }
            settle(1)
        }

        backToMenu()
        openMenu("shoppingList")
        let deleteList = app.buttons.matching(NSPredicate(format: "label IN %@",
            ["Einkaufsliste löschen", "Delete shopping list", "Supprimer la liste de courses"])).firstMatch
        var lists = 0
        while deleteList.waitForExistence(timeout: 3), lists < 10 {
            tapRowButton(deleteList)
            let yes = app.buttons.matching(NSPredicate(format: "label IN %@",
                ["Ja, löschen", "Yes, delete", "Oui, supprimer"])).firstMatch
            guard yes.waitForExistence(timeout: 3) else { break }
            yes.tap()
            settle(1)
            lists += 1
        }
    }

    /// Swipes away every local recipe that is a copy of the demo recipe. The
    /// copy is found by the database id in its row identifier; its name is
    /// no help, since the copy keeps the name in whichever language the
    /// recipe was shown in when the reminders were set. Without a known id
    /// (a custom SCREENSHOT_RECIPE), the local row whose name begins with
    /// the recipe's is taken.
    @MainActor
    private func deleteLocalCopiesOfDemoRecipe() {
        openMenu("publicRecipes")
        // Wait for the list itself, not for the copy: usually there is none.
        _ = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'publicRecipe.row.'"))
            .firstMatch.waitForExistence(timeout: 20)

        let copy: XCUIElement
        if let recipeId {
            copy = app.descendants(matching: .any).matching(identifier: "localRecipe.row.\(recipeId)").firstMatch
        } else {
            copy = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'localRecipe.row.' AND label BEGINSWITH %@", recipeName))
                .firstMatch
        }

        let delete = NSPredicate(format: "label IN %@", ["Löschen", "Delete", "Supprimer"])
        var deleted = 0
        while copy.waitForExistence(timeout: 2), deleted < 5 {
            scrollUntilHittable(copy)
            copy.swipeLeft()
            let action = app.buttons.matching(delete).firstMatch
            guard action.waitForExistence(timeout: 3) else { break }
            action.tap()
            // The confirmation: a sheet on the iPhone, a popover on the iPad.
            let dialog = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.popovers.firstMatch
            let confirm = (dialog.waitForExistence(timeout: 3) ? dialog : app)
                .buttons.matching(delete).firstMatch
            guard confirm.waitForExistence(timeout: 3) else { break }
            confirm.tap()
            settle(1)
            deleted += 1
        }
    }

    // MARK: - Scene 1: from the recipe to the baking plan

    /// Recipe → baking tab → "finish by" → reminders → the "next step" card
    /// on the start screen → the timeline → the bake mode. About 30 seconds.
    @MainActor
    func testPlanScene() throws {
        launch()
        pause(1)

        openDemoRecipe()
        pause(2)

        tab(0, titled: ["de": "Rezept backen", "en": "Bake recipe", "fr": "Cuire la recette"]).tap()
        let controls = app.descendants(matching: .any)["plan.controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5), "The baking tab did not open")
        scrollToTop(controls)
        pause(2)

        // The plan starts ("Ab") at `StoreUITestCase.planStart` this evening,
        // preset through the launch argument, so the start screen afterwards
        // shows the first step as the next one and the schedule carries no
        // night warnings.
        // ("Bis" would keep that time as the finish and put the whole plan
        // into the past.) A look down the schedule.
        app.swipeUp(velocity: .slow)
        pause(2)

        let setReminders = app.buttons["plan.setReminders"]
        scrollUntilHittable(setReminders)
        tapReliably(setReminders)
        // After `testPrepare` there is no earlier plan; should one be there
        // all the same, replace it rather than stall.
        let replaceTitle = ["de": "Bestehenden Plan ersetzen", "en": "Replace existing plan",
                            "fr": "Remplacer le plan existant"][language] ?? ""
        let replace = app.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier == 'plan.replace' OR label == %@", replaceTitle))
            .firstMatch
        if replace.waitForExistence(timeout: 2) {
            replace.tap()
        }
        allowSystemAlertIfShown()
        // The summary of what was scheduled stays up for a moment.
        if app.alerts.firstMatch.waitForExistence(timeout: 5) {
            pause(2.5)
            acknowledgeAlertIfShown(timeout: 1)
        }

        backToMenu()
        pause(3) // the "next step" card

        openMenu("scheduledSteps")
        pause(2.5)
        tab(1, titled: ["de": "Timeline", "en": "Timeline", "fr": "Timeline"]).tap()
        pause(3)
        tab(0, titled: ["de": "Geplante Schritte", "en": "Scheduled steps", "fr": "Étapes planifiées"]).tap()
        pause(1)

        let bakeMode = app.buttons["scheduled.bakeMode"]
        XCTAssertTrue(bakeMode.waitForExistence(timeout: 5), "Scheduled steps show no bake mode button")
        bakeMode.tap()
        pause(4)
        let close = app.buttons["bakeMode.close"]
        if close.waitForExistence(timeout: 3) { close.tap() }
        pause(1)
    }

    // MARK: - Scene 2: the calculators

    /// Serving size ×2 → flour line → starter line with TA 220 → the dough
    /// temperature calculator. About 25 seconds.
    @MainActor
    func testCalculatorsScene() throws {
        launch()
        pause(1)

        openDemoRecipe()
        pause(2)

        // Double the amounts with one tap on the serving-size picker.
        let double = app.buttons[["en": "2.0"][language] ?? "2,0"]
        if double.waitForExistence(timeout: 3) {
            double.tap()
            pause(3)
        }

        // The flour line of the main dough opens "Mehl ersetzen".
        let flourLine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1050")).firstMatch
        if flourLine.waitForExistence(timeout: 3) {
            scrollUntilHittable(flourLine)
            tapReliably(flourLine)
            pause(4)
            cancelSheet()
            pause(1)
        }

        // The starter line opens "Anstellgut-TA anpassen"; pick TA 220.
        let starterLine = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "TA150")).firstMatch
        if starterLine.waitForExistence(timeout: 3) {
            scrollUntilHittable(starterLine)
            tapReliably(starterLine)
            pause(2.5)
            let ta220 = app.buttons["220"]
            if ta220.waitForExistence(timeout: 2) {
                ta220.tap()
                pause(3)
            }
            cancelSheet()
            pause(1)
        }

        backToMenu()
        openMenu("doughTemperature")
        pause(4)
    }

    // MARK: - Scene 3: recipes in, shopping list out, any language

    /// The new-recipe form with its imports → the recipe's shopping list,
    /// grouped by shelf → a public recipe in another language. About 25
    /// seconds.
    @MainActor
    func testShoppingAndTranslationScene() throws {
        launch()
        pause(1)

        openMenu("newRecipe")
        pause(3)
        backToMenu()

        openDemoRecipe()
        tab(2, titled: ["de": "Einkaufsliste", "en": "Shopping list", "fr": "Liste de courses"]).tap()
        pause(2)
        let create = app.buttons.matching(NSPredicate(format: "label IN %@",
            ["Einkaufsliste erstellen", "Create shopping list", "Créer une liste de courses"])).firstMatch
        if create.waitForExistence(timeout: 3) {
            scrollUntilHittable(create)
            tapRowButton(create)
            // The names are translated into the app's language first.
            if app.alerts.firstMatch.waitForExistence(timeout: 15) {
                pause(1.5)
                acknowledgeAlertIfShown(timeout: 1)
            }
        }

        backToMenu()
        openMenu("shoppingList")
        pause(4)

        // The same recipe, read in another language.
        backToMenu()
        openDemoRecipe()
        pause(1.5)
        chooseLanguage(named: language == "de" ? "English" : "Deutsch")
        pause(3)
    }

    // MARK: - Pacing

    /// A pause for the viewer: long enough to read the screen.
    private func pause(_ seconds: TimeInterval) {
        settle(seconds)
    }
}
