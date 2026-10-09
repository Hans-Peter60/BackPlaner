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
//

import XCTest

final class AppStoreScreenshots: XCTestCase {

    private var app: XCUIApplication!
    private var language = "de"

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let language = environment["SCREENSHOT_LANGUAGE"], !language.isEmpty else {
            throw XCTSkip("Only for scripts/appstore-screenshots.sh (SCREENSHOT_LANGUAGE is not set).")
        }
        self.language = language

        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", Self.locale(for: language),
            // The in-app language picker overrides the system language.
            "-settings.selectedLanguage", language,
            // Off, so the recipe list never translates the screenshot
            // recipe's name out from under `recipeRow`'s German match, and
            // the recipe itself only changes language when this test asks
            // for it explicitly through the globe menu (see
            // `translateIfNeeded`), where a failure surfaces as a failed
            // assertion instead of a German recipe sitting in an English
            // screenshot.
            "-settings.automaticTranslation", "NO"
        ]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testCaptureStoreScreenshots() throws {
        let recipeName = ProcessInfo.processInfo.environment["SCREENSHOT_RECIPE"]
            ?? Self.defaultRecipeName
        // The database's own id for the default recipe, read once from a
        // hierarchy dump; only used when no other recipe was asked for, so a
        // custom SCREENSHOT_RECIPE still falls back to matching by name.
        let recipeId = ProcessInfo.processInfo.environment["SCREENSHOT_RECIPE_ID"]
            ?? (recipeName == Self.defaultRecipeName ? Self.defaultRecipeId : nil)

        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            Self.allow(alert)
        }
        app.launch()
        allowSystemAlertIfShown()

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
        let confirmation = app.alerts.firstMatch
        if confirmation.waitForExistence(timeout: 5) {
            let ok = confirmation.buttons["OK"]
            (ok.exists ? ok : confirmation.buttons.firstMatch).tap()
        }

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
        openMenu("publicRecipes")
        let rowAgain = recipeRow(named: recipeName, id: recipeId)
        XCTAssertTrue(rowAgain.waitForExistence(timeout: 20))
        tapReliably(rowAgain)
        translateIfNeeded()
        tab(2, titled: ["de": "Einkaufsliste", "en": "Shopping list", "fr": "Liste de courses"]).tap()
        settle(2)
        capture("07-einkaufsliste")
    }

    // MARK: - Screenshots

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Lets images, animations and the keyboard come to rest.
    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Navigation

    private func openMenu(_ destination: String) {
        let entry = app.buttons["menu.\(destination)"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Menu entry \(destination) is missing")
        scrollUntilHittable(entry)
        entry.tap()
    }

    private func backToMenu() {
        var attempts = 0
        while !app.buttons["menu.publicRecipes"].exists,
              app.navigationBars.buttons.element(boundBy: 0).exists,
              attempts < 6 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            attempts += 1
        }
    }

    /// A tab of the recipe or scheduled-steps screen. On the iPhone the tabs
    /// form a tab bar at the bottom and are found by position; on the iPad
    /// they float at the top as plain buttons and are found by their title in
    /// the language of the run.
    private func tab(_ index: Int, titled titles: [String: String]) -> XCUIElement {
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
    private func dismissCoveringSheet() {
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

    /// The recipe used for the screenshots, and its database id (read once
    /// from a hierarchy dump). Matching by id is what `recipeRow` prefers:
    /// the list may already show this recipe under a cached translation of
    /// its name by the time this runs, which a name match would miss.
    private static let defaultRecipeName = "Sauerteigbrot mit Kartoffeln und Saaten"
    private static let defaultRecipeId = "F5801F3E-DA33-48EA-807D-0C15E187F7F6"

    /// The row for `id` (each row's identifier is "publicRecipe.row.<id>"),
    /// or — without an id, or if it is not found — the row whose name begins
    /// with `name`, or the first row when there is no such recipe either. A
    /// row is one combined element whose label starts with the name
    /// ("Name, Bewertung 4 von 5 Sternen").
    private func recipeRow(named name: String, id: String?) -> XCUIElement {
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

    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 12) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    /// Scrolls until `element` sits in the upper part of the screen, as the
    /// baking view is shown in the store: the date controls at the top and
    /// the schedule underneath.
    private func scrollToTop(_ element: XCUIElement, maxSwipes: Int = 8) {
        let screen = app.windows.firstMatch.frame
        var swipes = 0
        while element.exists, element.frame.minY > screen.minY + screen.height * 0.18, swipes < maxSwipes {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let distance = min(element.frame.minY - screen.height * 0.15, screen.height * 0.5)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)))
            swipes += 1
        }
    }

    private func tapReliably(_ element: XCUIElement) {
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

    /// Picks the run's language through the globe menu and waits for the
    /// translation to finish. Automatic translation is off for this run (see
    /// `setUpWithError`), so the recipe stays in German — and the list never
    /// silently translates its name out from under `recipeRow`'s match —
    /// until this asks for the target language explicitly. A translation
    /// that fails then shows up as a failed assertion, not as a German
    /// recipe quietly sitting in an English or French screenshot.
    private func translateIfNeeded() {
        guard language != "de" else { return }

        let globe = app.buttons.containing(.image, identifier: "globe").firstMatch
        guard globe.waitForExistence(timeout: 5) else {
            XCTFail("No globe button to choose a language")
            return
        }
        globe.tap()

        // The language menu's entries are the language names themselves
        // ("Deutsch", "English", "Français"), not localized strings.
        let targetName = ["en": "English", "fr": "Français"][language] ?? ""
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
    private func acceptTranslationDownloadIfAsked() {
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

    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            Self.allow(alert)
        }
    }

    @discardableResult
    private static func allow(_ alert: XCUIElement) -> Bool {
        for title in ["Erlauben", "Allow", "Autoriser", "OK"] where alert.buttons[title].exists {
            alert.buttons[title].tap()
            return true
        }
        return false
    }

    private static func locale(for language: String) -> String {
        switch language {
        case "en": return "en_US"
        case "fr": return "fr_FR"
        default:   return "de_DE"
        }
    }
}
