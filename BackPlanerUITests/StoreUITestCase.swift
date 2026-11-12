//
//  StoreUITestCase.swift
//  BackPlanerUITests
//
//  What the App Store screenshots and the App Store previews share: the way
//  the app is launched in a given language, and the moves through its
//  screens — switching a root tab, opening a screen of the recipe list's
//  "Mehr" menu, finding the demo recipe, opening its plan sheet,
//  translating the recipe through the globe menu. Both tests work on the
//  simulator's real data and the live recipe database, and both skip
//  themselves in an ordinary test run (the subclasses decide on what).
//
//  Settings come from the environment (xcodebuild hands TEST_RUNNER_<NAME> to
//  the test as <NAME>):
//    SCREENSHOT_RECIPE     the public recipe to show, by the start of its name
//    SCREENSHOT_RECIPE_ID  its database id, when a recipe other than the
//                          default is asked for and its id is known
//

import XCTest

class StoreUITestCase: XCTestCase {

    var app: XCUIApplication!
    var language = "de"

    /// The recipe used for the screenshots, and its database id (read once
    /// from a hierarchy dump). Matching by id is what `recipeRow` prefers:
    /// the list may already show this recipe under a cached translation of
    /// its name by the time this runs, which a name match would miss.
    static let defaultRecipeName = "Kartoffelbrot mit Saaten"
    static let defaultRecipeId = "F5801F3E-DA33-48EA-807D-0C15E187F7F6"

    /// The clock time at which the recipe's plan begins, in the screenshots
    /// and the previews alike (launch argument `-UITestingPlanStart`, see
    /// UITestSupport). Started at the time of the run, the sourdough plan put
    /// most of its steps into the night and the schedule was a column of
    /// warnings; from the evening on, the dough rests through the night and
    /// the steps fall into the day.
    static let planStart = "20:00"

    /// The clock time at which the plan ends when a subclass plans to a
    /// finish (`plansToFinish`, launch argument `-UITestingPlanFinish`): the
    /// first 15:00 that is at least a day away. Worked back over the demo
    /// recipe's 19 hours, the plan begins around 20:00 the evening before,
    /// so the steps fall as with `planStart`.
    static let planFinish = "15:00"

    /// Whether the plan sheet opens on "Fertig bis" with `planFinish` rather
    /// than on "Starten ab" with `planStart`. The screenshots do, so the
    /// picture of the plan shows a finish time and the start times worked
    /// back from it; the previews keep the start.
    var plansToFinish: Bool { false }

    var recipeName: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_RECIPE"] ?? Self.defaultRecipeName
    }

    /// Only used when no other recipe was asked for, so a custom
    /// SCREENSHOT_RECIPE still falls back to matching by name.
    var recipeId: String? {
        ProcessInfo.processInfo.environment["SCREENSHOT_RECIPE_ID"]
            ?? (recipeName == Self.defaultRecipeName ? Self.defaultRecipeId : nil)
    }

    /// Prepares the app for a run in `language`; the subclass calls this
    /// from its setUp once it has decided not to skip.
    func prepare(language: String) {
        self.language = language

        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", Self.locale(for: language),
            // The in-app language picker overrides the system language.
            "-settings.selectedLanguage", language,
            // Off, so the recipe list never translates the demo recipe's
            // name out from under `recipeRow`'s German match, and the recipe
            // itself only changes language when the test asks for it
            // explicitly through the globe menu (see `translateIfNeeded`),
            // where a failure surfaces as a failed assertion instead of a
            // German recipe sitting in an English or French picture.
            "-settings.automaticTranslation", "NO",
            "-UITestingPlanStart", Self.planStart
        ]
        if plansToFinish {
            // The baking tab also scrolls its date controls to the top by
            // itself (UITestSupport.scrollsToPlanControls): dragging the
            // page there from here worked in one language and not in the
            // next, the drags now and then taken by the content.
            app.launchArguments += ["-UITestingPlanFinish", Self.planFinish,
                                    "-UITestingScrollToPlanControls"]
        }
        // The App Check debug token of a simulator that is registered in
        // the Firebase console, so a simulator the app has never run on
        // (the iPhone Duo) reads the recipe database too. The Firebase
        // debug provider takes it from this environment variable.
        if let token = ProcessInfo.processInfo.environment["APP_CHECK_DEBUG_TOKEN"], !token.isEmpty {
            app.launchEnvironment["FIRAAppCheckDebugToken"] = token
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Launches the app and clears the notification permission alert.
    func launch() {
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            Self.allow(alert)
        }
        app.launch()
        allowSystemAlertIfShown()
    }

    /// Lets images, animations and the keyboard come to rest.
    func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Navigation

    /// The tabs of the app's root, with their titles in the three languages
    /// (the tab bar's buttons carry no identifier of their own).
    enum RootTab {
        case recipes, shoppingLists, bakeHistory, scheduledSteps

        var titles: [String: String] {
            switch self {
            case .recipes:        return ["de": "Rezepte", "en": "Recipes", "fr": "Recettes"]
            case .shoppingLists:  return ["de": "Einkaufslisten", "en": "Shopping lists", "fr": "Courses"]
            case .bakeHistory:    return ["de": "Backhistorie", "en": "Baking history", "fr": "Historique"]
            case .scheduledSteps: return ["de": "Zeitleiste", "en": "Timeline", "fr": "Timeline"]
            }
        }
    }

    /// The button of a root tab: in the tab bar at the bottom on the iPhone,
    /// in the bar at the top on the iPad.
    func rootTab(_ tab: RootTab) -> XCUIElement {
        let title = tab.titles[language] ?? tab.titles["de"] ?? ""
        let inBar = app.tabBars.buttons[title]
        if inBar.waitForExistence(timeout: 3) { return inBar }
        // On the iPad the tab bar is not exposed as one, and the back button
        // of a pushed recipe carries the same label as the tab ("Rezepte");
        // take the first button with that label that is not the back button.
        return app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'BackButton'", title)).firstMatch
    }

    /// Switches to a root tab.
    func openTab(_ tab: RootTab) {
        let button = rootTab(tab)
        if !button.waitForExistence(timeout: 5) {
            attachHierarchy()
            XCTFail("There is no \(tab) tab")
            return
        }
        button.tap()
        settle(0.5)
        // On a narrow screen (the folded iPhone Duo in English) the tab
        // items' frames overlap and the tap can land on the neighbour; tap
        // the left part of the item until it is the selected one.
        var attempts = 0
        while !button.isSelected, attempts < 3 {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            settle(0.5)
            attempts += 1
        }
        // Still not selected (the unfolded Duo in English): the item's icon
        // takes the tap where the item's own frame did not.
        if !button.isSelected {
            let icon = button.images.firstMatch
            if icon.exists { icon.tap() } else { button.tap() }
            settle(0.7)
        }
        // Silently staying on the old tab made every later picture show
        // the wrong screen; say so instead.
        if !button.isSelected {
            attachHierarchy()
            XCTFail("The \(tab) tab did not open")
        }
    }

    /// Opens a screen reached from the recipe list: "newRecipe" behind "+",
    /// the calculators and "settings" behind "Mehr". The recipe list has to
    /// be on screen (see `backToRecipeList`).
    func openScreen(_ destination: String) {
        // When the title bar is short of room (the iPad's top tab bar with
        // French titles), the toolbar folds "Mehr" and "+" into an overflow
        // menu; its items carry the labels, not the identifiers.
        let overflow = app.buttons["OverflowBarButtonItem"]
        let more = app.buttons["menu.more"]
        if destination != "newRecipe" {
            if more.waitForExistence(timeout: 10) {
                more.tap()
            } else if overflow.waitForExistence(timeout: 3) {
                // The menu's entries are not buttons on every system, so any
                // element with the label counts, except the overflow button.
                let folded = app.buttons.matching(
                    NSPredicate(format: "(identifier == 'menu.more' OR label IN %@) AND identifier != 'OverflowBarButtonItem'",
                                ["Mehr", "More", "Plus"])).firstMatch
                var tries = 0
                repeat {
                    settle(1)
                    overflow.tap()
                    tries += 1
                } while !folded.waitForExistence(timeout: 4) && tries < 3
                guard folded.exists else {
                    attachHierarchy()
                    XCTFail("The overflow menu shows no Mehr entry")
                    return
                }
                folded.tap()
                settle(0.5)
            } else {
                attachHierarchy()
                XCTFail("The recipe list's Mehr menu is missing")
                return
            }
        } else if !app.buttons["menu.newRecipe"].waitForExistence(timeout: 10), overflow.exists {
            overflow.tap()
        }
        let byIdentifier = app.buttons["menu.\(destination)"]
        if byIdentifier.waitForExistence(timeout: 10) {
            byIdentifier.tap()
            return
        }
        // A menu taller than the screen scrolls; entries past its edge are
        // not in the hierarchy until it is scrolled.
        for _ in 0..<3 where !byIdentifier.exists {
            app.swipeUp()
            settle(0.5)
        }
        if byIdentifier.exists {
            byIdentifier.tap()
            return
        }
        let labels = Self.menuLabels[destination] ?? []
        let byLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        if byLabel.waitForExistence(timeout: 5) {
            byLabel.tap()
            return
        }
        attachHierarchy()
        XCTFail("Menu entry \(destination) is missing")
    }

    /// The titles of the entries behind "Mehr" and of "+", for the case
    /// that the toolbar folded them into an overflow menu.
    static let menuLabels: [String: [String]] = [
        "settings": ["Einstellungen", "Settings", "Réglages"],
        "exportRecipes": ["Rezepte exportieren", "Export recipes", "Exporter des recettes"],
        "doughTemperature": ["Teigtemperatur", "Dough temperature", "Température de la pâte"],
        "flourSubstitution": ["Mehl ersetzen", "Replace flour", "Remplacer la farine"],
        "starterYield": ["Anstellgut-TA", "Starter TA", "TA du levain chef"],
        "newRecipe": ["Neues Rezept anlegen", "Create new recipe", "Créer une nouvelle recette"],
    ]

    /// Leaves the screen's structure behind in the test result, so the
    /// cause of a failure can be read (the screenshot script exports it as
    /// 99-hierarchy.txt).
    func attachHierarchy(named name: String = "99-hierarchy") {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(language)-\(name)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    /// Returns to the recipe list, the root of the recipe tab: closes a
    /// sheet over the recipe (the plan, the shopping list), switches to the
    /// tab and pops whatever the tab has pushed.
    func backToRecipeList() {
        closeSheetIfShown()
        openTab(.recipes)
        var attempts = 0
        while !app.buttons["menu.more"].exists, attempts < 6 {
            // The back button sits in a navigation bar on the iPhone and
            // iPad; on the unfolded iPhone Duo (regular width, compact
            // height) the bar is not exposed as one, and the button is
            // found by its identifier instead.
            let inBar = app.navigationBars.buttons.element(boundBy: 0)
            let loose = app.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label IN %@",
                                                         ["Zurück", "Back", "Retour"])).firstMatch
            let back = inBar.exists ? inBar : loose
            guard back.exists else { return }
            back.tap()
            settle(0.5)
            attempts += 1
        }
    }

    /// Taps the "Schließen" of a sheet of the recipe page, if one is up.
    func closeSheetIfShown() {
        let close = app.buttons.matching(NSPredicate(format: "identifier == 'plan.close' OR label IN %@",
                                                     ["Schließen", "Close", "Fermer"])).firstMatch
        if close.exists, close.isHittable {
            close.tap()
            settle(0.7)
        }
    }

    /// Opens the demo recipe from the recipe list, translated into the
    /// run's language.
    func openDemoRecipe() {
        backToRecipeList()
        let row = recipeRow(named: recipeName, id: recipeId)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The recipe database shows no recipes")
        settle(1)
        tapReliably(row)
        waitForRecipeDetails()
        translateIfNeeded()
    }

    /// Waits until the recipe's page has slid in: its "Planen" button
    /// exists, and the push animation has had its time. A screenshot taken
    /// straight after the tap caught the page half-way in from the right.
    func waitForRecipeDetails() {
        let plan = app.buttons["recipe.plan"]
        if !plan.waitForExistence(timeout: 10) {
            // Something covers the screen, most likely a system sheet. Try
            // to close it once, then look again.
            dismissCoveringSheet()
            if !plan.waitForExistence(timeout: 5) {
                attachHierarchy()
                XCTFail("The recipe did not open")
                return
            }
        }
        settle(1.5)
    }

    /// Opens the plan sheet of the recipe on screen and waits for its date
    /// controls.
    func openPlan() {
        let plan = app.buttons["recipe.plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5), "The recipe page has no Planen button")
        scrollUntilHittable(plan, towards: .top)
        tapReliably(plan)
        let controls = app.descendants(matching: .any)["plan.controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5), "The plan sheet did not open")
    }

    /// Opens the shopping-list sheet of the recipe on screen.
    func openShoppingListSheet() {
        let button = app.buttons["recipe.shoppingList"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The recipe page has no Einkaufsliste button")
        scrollUntilHittable(button, towards: .top)
        tapReliably(button)
        settle(1)
    }

    /// The two views of the planned steps behind one segmented control.
    enum ScheduledDisplay: Int {
        case timeline = 0, list = 1
    }

    /// Shows the timeline or the list of the planned steps.
    func showScheduledSteps(as display: ScheduledDisplay) {
        let control = app.segmentedControls["scheduled.display"]
        if control.waitForExistence(timeout: 5), control.buttons.count > display.rawValue {
            control.buttons.element(boundBy: display.rawValue).tap()
        } else {
            let titles = display == .timeline
                ? ["Timeline"]
                : ["Liste", "List"]
            let button = app.buttons.matching(NSPredicate(format: "label IN %@", titles)).firstMatch
            if !button.waitForExistence(timeout: 5) {
                attachHierarchy()
                XCTFail("The planned steps show no \(display) switch")
                return
            }
            button.tap()
        }
        settle(0.7)
    }

    /// Closes a sheet or alert that covers the app: a button that says so,
    /// in the app or in a system process, else a swipe down.
    func dismissCoveringSheet() {
        let titles = ["Done", "Not Now", "Close", "Cancel", "OK", "Continue",
                      "Fertig", "Nicht jetzt", "Schließen", "Abbrechen", "Weiter",
                      "OK", "Plus tard", "Fermer", "Annuler", "Continuer", "Terminé"]
        let predicate = NSPredicate(format: "label IN %@", titles)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for source in [app!, springboard] {
            let button = source.buttons.matching(predicate).firstMatch
            if button.exists {
                button.tap()
                settle(1)
                return
            }
        }
        app.swipeDown(velocity: .fast)
        settle(1)
    }

    /// The "Abbrechen" of a sheet, in the run's language.
    func cancelSheet() {
        let titles = ["Abbrechen", "Cancel", "Annuler"]
        let button = app.buttons.matching(NSPredicate(format: "label IN %@", titles)).firstMatch
        if button.waitForExistence(timeout: 3) {
            button.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
    }

    /// Taps OK on an alert of the app, if one is up.
    func acknowledgeAlertIfShown(timeout: TimeInterval = 3) {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: timeout) {
            let ok = alert.buttons["OK"]
            (ok.exists ? ok : alert.buttons.firstMatch).tap()
        }
    }

    /// The row for `id` (each row's identifier is "publicRecipe.row.<id>"),
    /// or — without an id, or if it is not found — the row whose name begins
    /// with `name`, or the first row when there is no such recipe either. A
    /// row is one combined element whose label starts with the name
    /// ("Name, Bewertung 4 von 5 Sternen").
    func recipeRow(named name: String, id: String?) -> XCUIElement {
        if let id {
            let byId = app.descendants(matching: .any).matching(identifier: "publicRecipe.row.\(id)").firstMatch
            if byId.waitForExistence(timeout: 20) { return byId }
        }

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'publicRecipe.row.'"))
        guard rows.firstMatch.waitForExistence(timeout: 30) else { return rows.firstMatch }
        let named = rows.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        if named.exists { return named }
        // Further down the list: scroll a little, then fall back to the first.
        for _ in 0..<4 where !named.exists {
            app.swipeUp(velocity: .slow)
        }
        if named.exists { return named }
        for _ in 0..<4 { app.swipeDown(velocity: .slow) }
        return rows.firstMatch
    }

    enum ScrollTarget { case top, bottom }

    /// Scrolls the page towards its bottom (or its top) until `element` can
    /// be tapped.
    func scrollUntilHittable(_ element: XCUIElement, towards target: ScrollTarget = .bottom, maxSwipes: Int = 12) {
        let screen = app.windows.firstMatch.frame
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            // A measured drag rather than a flick: on the iPhone Duo a
            // `swipeUp` left the page where it was, while the drag from the
            // right-hand margin (see `drag`) moved it.
            drag(by: target == .bottom ? -screen.height * 0.5 : screen.height * 0.5)
            swipes += 1
        }
    }

    /// Scrolls until `element` sits in the upper part of the screen, as the
    /// baking view is shown in the store: the date controls at the top and
    /// the schedule underneath.
    func scrollToTop(_ container: XCUIElement, maxSwipes: Int = 8) {
        // Measured on a control inside, when there is one: the frame of a
        // container that merely contains its children came out higher than
        // the controls stood on screen, and the page was pulled back down
        // until they sat halfway down the picture.
        let control = container.segmentedControls.firstMatch
        let element = control.exists ? control : container
        let screen = app.windows.firstMatch.frame
        let target = screen.minY + screen.height * 0.15
        let highest = screen.minY + screen.height * 0.18
        // Below the floating navigation bar, which the content scrolls under.
        let lowest = screen.minY + screen.height * 0.12
        // Two passes: the page may still be laying out its schedule during
        // the first, so that a drag runs into a bottom that is not there yet
        // and bounces back.
        for pass in 0..<2 {
            if pass > 0 {
                guard element.exists, element.frame.minY > highest || element.frame.minY < lowest else { return }
                settle(1)
            }
            var swipes = 0
            while element.exists, element.frame.minY > highest, swipes < maxSwipes {
                let distance = min(element.frame.minY - target, screen.height * 0.5)
                drag(by: -distance, avoiding: element.frame)
                swipes += 1
            }
            // A drag can carry on a little once the finger lifts, and the
            // page is shorter without a list of warnings: the date controls
            // then came to rest under the navigation bar, where the picture
            // cut them off. Pull them back down.
            swipes = 0
            while element.exists, element.frame.minY < lowest, swipes < 3 {
                drag(by: target - element.frame.minY, avoiding: element.frame)
                swipes += 1
            }
        }
    }

    /// Drags the screen's content by `distance` points (negative moves it
    /// up), holding the finger still at the end so the scroll view does not
    /// keep rolling with the momentum of a flick. The finger goes down in
    /// the right-hand margin of the page, where no control sits, and
    /// outside `avoiding`: a press that lands on a control (the date
    /// picker, a step's row) is taken by the control, not by the scroll
    /// view, and the page stayed where it was.
    private func drag(by distance: CGFloat, avoiding: CGRect = .null) {
        let screen = app.windows.firstMatch.frame
        let x = screen.minX + screen.width * 0.96
        let startY = [0.6, 0.8, 0.4, 0.9].first { fraction in
            !avoiding.contains(CGPoint(x: x, y: screen.minY + screen.height * fraction))
        } ?? 0.6
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: startY))
        start.press(forDuration: 0.1,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                    withVelocity: .default,
                    thenHoldForDuration: 0.3)
        settle(0.3)
    }

    /// Taps a bordered button that sits alone in a Form row. Such a button
    /// reports the whole row as its frame, while only the bordered part on
    /// the left reacts; a tap at the row's centre lands beside it and does
    /// nothing. The title is inside the bordered part, so that is tapped.
    func tapRowButton(_ button: XCUIElement) {
        let title = button.staticTexts.firstMatch
        if title.exists {
            title.tap()
        } else {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        }
    }

    func tapReliably(_ element: XCUIElement) {
        // A list may still be settling after a scroll; give it a moment.
        let deadline = Date().addingTimeInterval(2)
        while !element.isHittable, Date() < deadline {
            settle(0.2)
        }
        // Under the tab bar: a tap at its spot would switch tabs; bring it
        // up first.
        let tabBar = app.tabBars.firstMatch
        if !element.isHittable, tabBar.exists, element.frame.intersects(tabBar.frame) {
            app.swipeUp(velocity: .slow)
            settle(0.5)
        }
        if element.isHittable {
            element.tap()
        } else if element.frame.minY > app.windows.firstMatch.frame.maxY || element.frame.maxY < 0 {
            // Off the screen: a plain tap lets XCTest scroll the element
            // into view through accessibility first. On the iPhone Duo
            // neither a swipe nor a drag moved the page, this did.
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
    }

    // MARK: - Translation

    /// The globe menu of a public recipe.
    var globeButton: XCUIElement {
        app.buttons.containing(.image, identifier: "globe").firstMatch
    }

    /// Picks the run's language through the globe menu and waits for the
    /// translation to finish. Automatic translation is off for this run (see
    /// `prepare`), so the recipe stays in German — and the list never
    /// silently translates its name out from under `recipeRow`'s match —
    /// until this asks for the target language explicitly. A translation
    /// that fails then shows up as a failed assertion, not as a German
    /// recipe quietly sitting in an English or French picture.
    func translateIfNeeded() {
        guard language != "de" else { return }
        chooseLanguage(named: ["en": "English", "fr": "Français"][language] ?? "")
    }

    /// Chooses an entry of the globe menu by its name ("Deutsch", "English",
    /// "Français" — the names are not localized) and waits for the result.
    func chooseLanguage(named targetName: String) {
        let globe = globeButton
        guard globe.waitForExistence(timeout: 5) else {
            XCTFail("No globe button to choose a language")
            return
        }
        globe.tap()

        let languageButton = app.buttons[targetName]
        guard languageButton.waitForExistence(timeout: 3) else {
            XCTFail("No „\(targetName)“ entry in the language menu")
            return
        }
        languageButton.tap()

        acceptTranslationDownloadIfAsked()

        // The globe shows a spinner while translating; wait for it to finish.
        let progress = app.activityIndicators.firstMatch
        if progress.waitForExistence(timeout: 2) {
            let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: progress)
            _ = XCTWaiter.wait(for: [gone], timeout: 30)
        }

        let failureAlert = app.alerts.firstMatch
        if failureAlert.waitForExistence(timeout: 2) {
            let message = failureAlert.staticTexts.element(boundBy: 1).label
            failureAlert.buttons.firstMatch.tap()
            XCTFail("Translating into \(targetName) failed: \(message)")
            return
        }
        settle(1)
    }

    /// On the simulator, a live translation request may be answered with a
    /// sheet saying translation is not supported ("Übersetzen" …
    /// "nicht unterstützt", button "Fertig"/"Done"), which this closes. On a
    /// real device iOS may instead ask to download the language, which this
    /// accepts.
    func acceptTranslationDownloadIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let download = NSPredicate(format: "label IN %@", ["Download", "Herunterladen", "Télécharger"])
        let done = NSPredicate(format: "label IN %@", ["Fertig", "Done", "Terminé", "OK"])
        let sheetTitle = NSPredicate(format: "label IN %@", ["Übersetzen", "Translate", "Traduire"])

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            for source in [app!, springboard] {
                let button = source.buttons.matching(download).firstMatch
                if button.exists {
                    button.tap()
                    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: button)
                    _ = XCTWaiter.wait(for: [gone], timeout: 120)
                    return
                }
                if source.staticTexts.matching(sheetTitle).firstMatch.exists {
                    let close = source.buttons.matching(done).firstMatch
                    if close.exists {
                        close.tap()
                        settle(1)
                        return
                    }
                }
            }
            settle(0.5)
        }
    }

    // MARK: - System alerts

    func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            Self.allow(alert)
        }
    }

    /// Permission prompts are allowed. The simulator's iCloud sign-in
    /// prompt ("Du musst deinen Apple Account und dein Passwort eingeben",
    /// with "Erneut versuchen" and "Abbrechen") has nothing to allow and
    /// is cancelled, so that it does not sit over the recipe list in the
    /// manual's picture.
    @discardableResult
    static func allow(_ alert: XCUIElement) -> Bool {
        for title in ["Erlauben", "Allow", "Autoriser", "OK"] where alert.buttons[title].exists {
            alert.buttons[title].tap()
            return true
        }
        for title in ["Abbrechen", "Cancel", "Annuler", "Nicht jetzt", "Not Now", "Plus tard"] where alert.buttons[title].exists {
            alert.buttons[title].tap()
            return true
        }
        return false
    }

    static func locale(for language: String) -> String {
        switch language {
        case "en": return "en_US"
        case "fr": return "fr_FR"
        default:   return "de_DE"
        }
    }
}
