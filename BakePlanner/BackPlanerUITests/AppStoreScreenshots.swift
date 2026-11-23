//
//  AppStoreScreenshots.swift
//  BackPlanerUITests
//
//  Walks through the screens shown in the App Store and saves a screenshot of
//  each. Run by scripts/bakeplanner/appstore-screenshots.sh for every language and device;
//  in a normal test run it skips itself, since it works on the simulator's
//  real data and needs the recipe database online.
//
//  The numbers are the order on the product page, which opens with what sets
//  the app apart: the plan sheet planned to a finish time, the next-step bar,
//  the bake mode. The screens the app shares with every recipe app (the recipe
//  list, the settings) come last or only serve the manuals (numbers from 90
//  up, which the script keeps out of the App Store folder). The headline of
//  each picture is in docs/bakeplanner/appstore/captions.json, keyed by the name after
//  the number; the script sets it over the picture.
//
//  Settings come from the environment (xcodebuild hands TEST_RUNNER_<NAME> to
//  the test as <NAME>):
//    SCREENSHOT_LANGUAGE     de, en or fr — required, otherwise the test skips
//    SCREENSHOT_RECIPE       the public recipe to show, by the start of its name
//    SCREENSHOT_EXTRAS       1 takes the extra pictures beyond the store set —
//                            the photo cloud, the starter chart and the
//                            purchase sheet — which the script asks for on
//                            the iPhone only; they cost minutes per run, and
//                            the French run on the folded iPhone Duo did not
//                            finish inside its allowance with them.
//    SCREENSHOT_DEMO_BACKUP  the demo backup of scripts/bakeplanner/appstore-demo-data.py
//                            for this language; the app reads it at launch
//                            (-UITestingRestoreBackup), and the pictures of
//                            the Pro features — baking day, pantry,
//                            statistics, starter chart — need it. Without
//                            it those pictures are skipped.
//    SCREENSHOT_STOP_AFTER   a picture's number, e.g. 01: the run ends after
//                            it, for renewing one picture without the others
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
            throw XCTSkip("Only for scripts/bakeplanner/appstore-screenshots.sh (SCREENSHOT_LANGUAGE is not set).")
        }
        prepare(language: language)
        takesExtras = environment["SCREENSHOT_EXTRAS"] == "1"
        if let backup = environment["SCREENSHOT_DEMO_BACKUP"], !backup.isEmpty {
            demoBackup = backup
            app.launchArguments += ["-UITestingRestoreBackup", backup]
            // One oven profile, so the plan sheet shows its "Ofen" row and
            // the oven steps carry the dial setting (UITestSupport makes it).
            let ovenName = ["de": "Backofen Küche", "en": "Kitchen oven", "fr": "Four de la cuisine"][language] ?? "Backofen"
            app.launchArguments += ["-UITestingOvenProfile", ovenName]
        }
        // The iPad took the ten pictures and ran out of the plan's five
        // minutes on the last manual one; the Pro pictures and the second
        // launch for the purchase sheet need more, and the French run on
        // the folded iPhone Duo passed fifteen minutes.
        executionTimeAllowance = 1500
    }

    /// The demo backup's path, when the run has one (see setUp).
    private var demoBackup: String?

    /// Whether the run takes the extra pictures (SCREENSHOT_EXTRAS).
    private var takesExtras = false

    /// Whether the run ends after the picture of this number
    /// (SCREENSHOT_STOP_AFTER).
    private func stopsAfter(_ number: String) -> Bool {
        ProcessInfo.processInfo.environment["SCREENSHOT_STOP_AFTER"] == number
    }

    /// The start of the demo starter's name, as the recipe list shows it.
    private var starterName: String {
        ["de": "Weizenanstellgut", "en": "Wheat starter", "fr": "Levain chef"][language] ?? "Weizenanstellgut"
    }

    /// The three demo breads of the baking day: sourdough breads of 16 to
    /// 20 hours, so that with the finish preset to tomorrow afternoon
    /// (StoreUITestCase.planFinish) every start lies after the run began
    /// and the levains rest through the night; their flours are in the
    /// demo pantry, so no shortfall pushes the schedule down the page.
    /// Typed into the planner's search field, so each is a plain part of
    /// one bread's name (no accents for the keyboard).
    private var bakingDayBreads: [String] {
        switch language {
        case "en": return ["Emmer", "Potato sourdough", "Rye crust"]
        case "fr": return ["amidonnier", "pommes de terre", "seigle en"]
        default:   return ["Emmer", "Kartoffel-Sauer", "Roggenkrusten"]
        }
    }

    /// The price on the purchase sheet (App Store tier of 9,99 €).
    private var previewPrice: String {
        language == "en" ? "$9.99" : "9,99 €"
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

        liftAboveBottomBars(row)
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
        if stopsAfter("01") { return }

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

        // The recipe list with the next-step bar over its bottom edge, from
        // its top: finding the recipe may have scrolled it.
        backToRecipeList()
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        settle(1.5)
        capture("02-startbildschirm")

        // Pro: a baking day of three own breads worked back from one finish
        // time, and the pantry. Both need the demo data.
        if demoBackup != nil {
            openScreen("bakingDay")
            let breads = app.buttons.matching(identifier: "bakingDay.recipe")
            let search = app.textFields["bakingDay.search"]
            if breads.firstMatch.waitForExistence(timeout: 8), search.exists {
                // Through the search field: a row further down the form is
                // not in the hierarchy until scrolled to, and a row dragged
                // up under the floating title bar took no tap.
                for name in bakingDayBreads {
                    search.tap()
                    search.typeText(name)
                    settle(0.5)
                    let bread = breads.firstMatch
                    if bread.waitForExistence(timeout: 3) {
                        bread.tap()
                        settle(0.3)
                    }
                    search.tap()
                    search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count + 2))
                }
                search.typeText("\n") // the keyboard away
                settle(0.5)
                let compute = app.buttons["bakingDay.compute"]
                // On the unfolded Duo the button was not in the hierarchy
                // until the form was scrolled; asking a missing element
                // whether it is hittable fails the test.
                for _ in 0..<4 where !compute.exists {
                    scrollHalfScreenDown()
                }
                // The unfolded iPhone Duo scrolls for no gesture at all;
                // narrowing the list to the last bread brings the button up.
                if !compute.exists, let last = bakingDayBreads.last {
                    search.tap()
                    search.typeText(last + "\n")
                    settle(0.7)
                }
                if compute.waitForExistence(timeout: 3) {
                    scrollUntilHittable(compute)
                    tapReliably(compute)
                    settle(2)
                    // The schedule comes in under the list; the picture
                    // shows the bottom of the form, with the start times.
                    let planAll = app.buttons["bakingDay.planAll"]
                    _ = planAll.waitForExistence(timeout: 5)
                    for _ in 0..<4 where !(planAll.exists && planAll.isHittable) {
                        scrollHalfScreenDown()
                    }
                    settle(1)
                    capture("05-backtag")
                } else {
                    attachHierarchy(named: "98-backtag-compute")
                }
            } else {
                attachHierarchy(named: "98-backtag")
            }
            backToRecipeList()

            openTab(.pantry)
            settle(2)
            capture("06-vorrat")
            backToRecipeList()
        }

        // Bake mode and timeline of the planned steps. The timeline opens
        // first; the bake mode button is on the list.
        openTab(.scheduledSteps)
        showScheduledSteps(as: .list)
        settle(1.5)
        capture("94-geplante-schritte-liste")
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

        // Back in the recipe for its shopping list.
        openDemoRecipe()
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
        // The names are translated into the app's language first; on the
        // simulator the system may answer with its "not supported" sheet.
        acceptTranslationDownloadIfAsked()
        acknowledgeAlertIfShown(timeout: 20)
        closeSheetIfShown()

        openTab(.shoppingLists)
        settle(2)
        capture("09-einkaufsliste")

        // Pro, from the demo data: the baking history as statistics, as the
        // yearbook and as the photo cloud, then the starter's chart.
        if demoBackup != nil {
            openTab(.bakeHistory)
            let layouts = app.segmentedControls.firstMatch
            if layouts.waitForExistence(timeout: 5), layouts.buttons.count >= 5 {
                layouts.buttons.element(boundBy: 4).tap()
                settle(3) // the charts animate in
                capture("10-backstatistik")

                if takesExtras {
                    layouts.buttons.element(boundBy: 3).tap()
                    settle(3) // the cloud lays itself out and loads its pictures
                    capture("97-backhistorie-fotowolke")
                }
                layouts.buttons.element(boundBy: 0).tap()
                settle(0.5)
            } else {
                attachHierarchy(named: "98-backhistorie")
            }

            backToRecipeList()
            if !takesExtras {
                // No starter chart: the list cannot be scrolled to the
                // starter on the unfolded Duo, and the search took the
                // folded Duo past its time allowance in French.
            } else if let starter = localRecipeRow(startingWith: starterName) {
                liftAboveBottomBars(starter)
                tapReliably(starter)
                waitForRecipeDetails()
                let diary = app.buttons["recipe.feedingDiary"]
                if diary.waitForExistence(timeout: 5) {
                    scrollUntilHittable(diary)
                    tapReliably(diary)
                    let chart = app.buttons["starter.chart"]
                    if chart.waitForExistence(timeout: 8) {
                        scrollUntilHittable(chart)
                        chart.tap()
                        settle(3) // the curve and the trend draw themselves
                        capture("98-anstellgut-diagramm")
                        // Back to the diary first: the sheet's "Schließen"
                        // belongs to the diary, not to the pushed chart, and
                        // on the folded Duo the sheet stayed up without it.
                        let back = app.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label IN %@",
                                                                    ["Zurück", "Back", "Retour"])).firstMatch
                        if back.waitForExistence(timeout: 3) {
                            back.tap()
                            settle(0.7)
                        }
                    } else {
                        attachHierarchy(named: "98-anstellgut")
                    }
                    closeSheetIfShown()
                    if app.buttons["starter.chart"].exists { dismissCoveringSheet() }
                }
            } else {
                attachHierarchy(named: "98-starter-row")
            }
        }

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

        // The purchase sheet of BakePlanner Pro, the picture App Store
        // Connect asks for when the in-app purchase is set up. It needs a
        // run in which Pro is for sale and not bought — with Pro required,
        // which would have locked the pictures above — so the app is
        // started once more for it.
        guard takesExtras else { return }
        app.terminate()
        app.launchArguments += ["-UITestingMonetization", "storeVisible,proRequired,price=\(previewPrice)"]
        launch()
        backToRecipeList()
        openScreen("settings")
        settle(1.5) // the settings slide in
        let pro = app.buttons["settings.pro"]
        // The sheet's title bar: its buy button sits under the list of
        // features, off screen and not in the hierarchy.
        let sheet = app.navigationBars["BakePlanner Pro"]
        if pro.waitForExistence(timeout: 8) {
            tapReliably(pro)
            if !sheet.waitForExistence(timeout: 4) {
                tapRowButton(pro) // a tap during the push animation is lost
            }
            if sheet.waitForExistence(timeout: 5) {
                settle(2)
                capture("90-pro-kaufseite")
                closeSheetIfShown()
            } else {
                attachHierarchy(named: "98-paywall")
            }
        } else {
            attachHierarchy(named: "98-settings-pro")
        }
    }

    // MARK: - Demo data screens

    /// The row of an own recipe whose name starts with `name`, scrolled
    /// into view; nil when the list has no such recipe. Rows off screen
    /// are not in the hierarchy until the list is scrolled to them.
    private func localRecipeRow(startingWith name: String) -> XCUIElement? {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'localRecipe.row.' AND label BEGINSWITH %@", name))
            .firstMatch
        if row.waitForExistence(timeout: 5), row.isHittable { return row }
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            scrollHalfScreenDown()
        }
        if row.exists {
            scrollUntilHittable(row)
            return row
        }
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        return nil
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
        let screens = XCUIScreen.screens
        guard screens.count > 1 else { return XCUIScreen.main.screenshot() }
        // With two displays the app itself is asked, not a screen: on iOS
        // 27.3 a screenshot of the inactive display fails the test ("Cannot
        // screenshot inactive display"), and the app's window covers the
        // display it is on, status bar included.
        return app.screenshot()
    }
}
