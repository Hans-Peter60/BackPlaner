//
//  StoreUITestCase.swift
//  BackPlanerUITests
//
//  What the App Store screenshots and the App Store previews share: the way
//  the app is launched in a given language, and the moves through its
//  screens — opening a menu card, finding the demo recipe, switching tabs,
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
    static let defaultRecipeName = "Kartoffelnbrot mit Saaten"
    static let defaultRecipeId = "F5801F3E-DA33-48EA-807D-0C15E187F7F6"

    /// The clock time at which the recipe's plan begins, in the screenshots
    /// and the previews alike (launch argument `-UITestingPlanStart`, see
    /// UITestSupport). Started at the time of the run, the sourdough plan put
    /// most of its steps into the night and the schedule was a column of
    /// warnings; from the evening on, the dough rests through the night and
    /// the steps fall into the day.
    static let planStart = "20:00"

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

    func openMenu(_ destination: String) {
        let entry = app.buttons["menu.\(destination)"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Menu entry \(destination) is missing")
        scrollUntilHittable(entry)
        entry.tap()
    }

    func backToMenu() {
        var attempts = 0
        while !app.buttons["menu.publicRecipes"].exists,
              app.navigationBars.buttons.element(boundBy: 0).exists,
              attempts < 6 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            attempts += 1
        }
    }

    /// Opens the demo recipe from the recipe database, translated into the
    /// run's language.
    func openDemoRecipe() {
        openMenu("publicRecipes")
        let row = recipeRow(named: recipeName, id: recipeId)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The recipe database shows no recipes")
        settle(1)
        tapReliably(row)
        translateIfNeeded()
    }

    /// A tab of the recipe or scheduled-steps screen. On the iPhone the tabs
    /// form a tab bar at the bottom and are found by position; on the iPad
    /// they float at the top as plain buttons and are found by their title in
    /// the language of the run.
    func tab(_ index: Int, titled titles: [String: String]) -> XCUIElement {
        let bar = app.tabBars.firstMatch
        if bar.waitForExistence(timeout: 3), bar.buttons.count > index {
            return bar.buttons.element(boundBy: index)
        }
        let title = titles[language] ?? titles["de"] ?? ""
        let button = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if button.waitForExistence(timeout: 5) { return button }

        // Something covers the screen, most likely a system sheet. Try to
        // close it once, then look again.
        dismissCoveringSheet()
        if bar.waitForExistence(timeout: 3), bar.buttons.count > index {
            return bar.buttons.element(boundBy: index)
        }
        if button.waitForExistence(timeout: 3) { return button }

        // Leave the screen's structure behind, so the cause can be read.
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(language)-99-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("There is no tab \(index) („\(title)“)")
        return button
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

    func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 12) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    /// Scrolls until `element` sits in the upper part of the screen, as the
    /// baking view is shown in the store: the date controls at the top and
    /// the schedule underneath.
    func scrollToTop(_ element: XCUIElement, maxSwipes: Int = 8) {
        let screen = app.windows.firstMatch.frame
        let target = screen.minY + screen.height * 0.15
        // Below the floating navigation bar, which the content scrolls under.
        let lowest = screen.minY + screen.height * 0.12
        var swipes = 0
        while element.exists, element.frame.minY > screen.minY + screen.height * 0.18, swipes < maxSwipes {
            let distance = min(element.frame.minY - target, screen.height * 0.5)
            drag(by: -distance)
            swipes += 1
        }
        // A drag can carry on a little once the finger lifts, and the page
        // is shorter without a list of warnings: the date controls then came
        // to rest under the navigation bar, where the picture cut them off.
        // Pull them back down.
        swipes = 0
        while element.exists, element.frame.minY < lowest, swipes < 3 {
            drag(by: target - element.frame.minY)
            swipes += 1
        }
    }

    /// Drags the screen's content by `distance` points (negative moves it
    /// up), holding the finger still at the end so the scroll view does not
    /// keep rolling with the momentum of a flick.
    private func drag(by distance: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
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
        if element.isHittable {
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

    @discardableResult
    static func allow(_ alert: XCUIElement) -> Bool {
        for title in ["Erlauben", "Allow", "Autoriser", "OK"] where alert.buttons[title].exists {
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
