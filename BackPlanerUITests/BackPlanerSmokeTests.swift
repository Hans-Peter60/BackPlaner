//
//  BackPlanerSmokeTests.swift
//  BackPlanerUITests
//
//  End-to-end checks of the paths every baker takes: the app starts, a recipe
//  can be entered, a plan can be made. They catch what the unit tests cannot
//  see — a screen that no longer opens, a field hidden behind the keyboard.
//
//  The app is launched with -UITesting, which gives it an empty in-memory
//  store (see UITestSupport in the app), and in German, so labels match.
//

import XCTest

final class BackPlanerSmokeTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-UITesting",
            "-AppleLanguages", "(de)",
            "-AppleLocale", "de_DE",
            // The in-app language picker overrides the system language.
            "-settings.selectedLanguage", "de"
        ]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tests

    @MainActor
    func testLaunchShowsEveryMenuEntry() throws {
        launch()

        for destination in Self.menuDestinations {
            XCTAssertTrue(menuEntry(destination).waitForExistence(timeout: 5),
                          "Menu entry \(destination) is missing")
        }
    }

    /// Opens each local screen from the menu and returns. The public database is
    /// left out: it depends on the network, not on the app.
    @MainActor
    func testEveryLocalScreenOpensFromTheMenu() throws {
        launch()

        for destination in Self.menuDestinations where destination != "publicRecipes" {
            let entry = menuEntry(destination)
            scrollUntilHittable(entry)
            entry.tap()

            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5),
                          "\(destination) did not open a screen with a back button")
            back.tap()

            XCTAssertTrue(menuEntry(destination).waitForExistence(timeout: 5),
                          "Could not return to the menu from \(destination)")
        }
    }

    /// The case behind 90b0808: the duration field of a new instruction must
    /// stay above the number pad, and "Fertig" must close the pad.
    @MainActor
    func testNewRecipeDurationFieldStaysAboveTheNumberPad() throws {
        launch()
        openMenu("newRecipe")

        let name = app.textFields["Name"]
        scrollUntilHittable(name)
        name.tap()
        // Return closes the keyboard, so the swipe back up reaches the form.
        name.typeText("Testbrot\n")

        // The save section sits above the name; on a small screen it has
        // scrolled away, and a Form keeps rows out of view out of reach.
        let save = app.buttons["Rezept speichern"]
        scrollUntilHittable(save, towards: .top)
        XCTAssertTrue(save.isEnabled, "A named recipe should be savable")

        let duration = app.textFields["Dauer in Minuten"].firstMatch
        scrollUntilHittable(duration)
        duration.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "The number pad did not appear")

        // The form centres the focused row once the keyboard has settled.
        let settled = expectation(for: NSPredicate { _, _ in
            duration.isHittable && duration.frame.maxY <= keyboard.frame.minY
        }, evaluatedWith: nil)
        wait(for: [settled], timeout: 3)

        duration.typeText("45")

        let done = app.buttons["Fertig"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 2), "The keyboard has no Fertig button")
        done.tap()

        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: keyboard)
        wait(for: [gone], timeout: 3)
    }

    /// Plans the seeded recipe and finds its steps under "Geplante Schritte".
    @MainActor
    func testPlanningARecipeListsItsSteps() throws {
        app.launchArguments.append("-UITestingSeedRecipe")
        launch()

        openMenu("ownRecipes")

        let recipeName = "UI-Test-Brot"
        let row = element(labelBeginningWith: recipeName)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The seeded recipe is not listed")
        row.tap()

        // A recipe opens on its details; planning happens in "Backen".
        let bakingTab = app.tabBars.buttons["Backen"]
        XCTAssertTrue(bakingTab.waitForExistence(timeout: 5), "The recipe has no Backen tab")
        bakingTab.tap()

        let setReminders = app.buttons["Reminder setzen"]
        scrollUntilHittable(setReminders)
        tapReliably(setReminders)
        allowSystemAlertIfShown()

        let confirmation = app.alerts["Reminder wurden gesetzt"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5),
                      "Setting the reminders was not confirmed")
        confirmation.buttons["OK"].tap()

        // Back out of the recipe to the menu.
        while !menuEntry("scheduledSteps").exists,
              app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        openMenu("scheduledSteps")

        XCTAssertFalse(app.staticTexts["Keine geplanten Schritte"].waitForExistence(timeout: 2),
                       "The plan left no steps behind")
        XCTAssertTrue(element(labelContaining: "Teig kneten").waitForExistence(timeout: 5),
                      "The first step of the plan is not listed")
        XCTAssertTrue(element(labelContaining: "Details zu \(recipeName)").exists,
                      "The planned steps do not name the recipe")
    }

    // MARK: - Helpers

    /// Raw values of MenuDestination, which the app uses as identifiers.
    private static let menuDestinations = [
        "publicRecipes", "ownRecipes", "newRecipe", "scheduledSteps",
        "bakeHistory", "hitList", "shoppingList", "settings"
    ]

    private func launch() {
        // The app asks for permission to send notifications on its first start.
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            Self.allow(alert)
        }
        app.launch()
        allowSystemAlertIfShown()
    }

    private func menuEntry(_ destination: String) -> XCUIElement {
        app.buttons["menu.\(destination)"]
    }

    private func openMenu(_ destination: String) {
        let entry = menuEntry(destination)
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Menu entry \(destination) is missing")
        scrollUntilHittable(entry)
        entry.tap()
    }

    private func element(labelBeginningWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }

    private func element(labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    private enum ScrollTarget { case top, bottom }

    /// Swipes until the element can be tapped. Forms build their rows lazily,
    /// so an element out of view may not exist before that. Slow swipes keep
    /// the list from flinging past it. Only existence is required in the end:
    /// at the bottom of a screen an element can sit under the floating tab
    /// bar and count as not hittable although it is there (see tapReliably).
    private func scrollUntilHittable(_ element: XCUIElement, towards target: ScrollTarget = .bottom,
                                     maxSwipes: Int = 10) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            switch target {
            case .bottom: app.swipeUp(velocity: .slow)
            case .top:    app.swipeDown(velocity: .slow)
            }
            swipes += 1
        }
        XCTAssertTrue(element.exists, "\(element) did not appear")
    }

    /// Taps an element even where the floating tab bar covers its centre: then
    /// its upper edge, which stays clear, takes the tap.
    private func tapReliably(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
    }

    /// The interruption monitor only fires on the next interaction with the
    /// app; an alert from SpringBoard that is already up is handled here.
    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            Self.allow(alert)
        }
    }

    @discardableResult
    private static func allow(_ alert: XCUIElement) -> Bool {
        for title in ["Erlauben", "Allow", "OK"] where alert.buttons[title].exists {
            alert.buttons[title].tap()
            return true
        }
        return false
    }
}
