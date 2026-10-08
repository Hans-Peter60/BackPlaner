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
//    SCREENSHOT_DIR       where the PNG files go; they are attached to the
//                         test result as well
//    SCREENSHOT_RECIPE    the public recipe to show, by the start of its name
//

import XCTest

final class AppStoreScreenshots: XCTestCase {

    private var app: XCUIApplication!
    private var language = "de"
    private var outputDirectory: URL?

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let language = environment["SCREENSHOT_LANGUAGE"], !language.isEmpty else {
            throw XCTSkip("Only for scripts/appstore-screenshots.sh (SCREENSHOT_LANGUAGE is not set).")
        }
        self.language = language
        outputDirectory = environment["SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }

        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", Self.locale(for: language),
            // The in-app language picker overrides the system language.
            "-settings.selectedLanguage", language
        ]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testCaptureStoreScreenshots() throws {
        let recipeName = ProcessInfo.processInfo.environment["SCREENSHOT_RECIPE"]
            ?? "Sauerteigbrot mit Kartoffeln und Saaten"

        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            Self.allow(alert)
        }
        app.launch()
        allowSystemAlertIfShown()

        // Recipe database, then the recipe's details and its baking tab.
        openMenu("publicRecipes")
        let row = recipeRow(named: recipeName)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The recipe database shows no recipes")
        settle(3) // thumbnails load after the list
        capture("02-rezept-datenbank")

        row.tap()
        settle(2)
        capture("03-rezept-details")

        tab(0).tap()
        let controls = app.descendants(matching: .any)["plan.controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5), "The baking tab did not open")
        scrollToTop(controls)
        settle(1)
        capture("04-rezept-backen")

        // Plan it, so the start screen and the bake mode have a next step.
        let setReminders = app.buttons["plan.setReminders"]
        scrollUntilHittable(setReminders)
        tapReliably(setReminders)
        let replace = app.buttons["plan.replace"]
        if replace.waitForExistence(timeout: 2) {
            replace.tap()
        }
        allowSystemAlertIfShown()
        let confirmation = app.alerts.firstMatch
        if confirmation.waitForExistence(timeout: 5) {
            confirmation.buttons.firstMatch.tap()
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

        tab(1).tap()
        settle(2)
        capture("06-timeline")

        // The recipe's shopping list.
        backToMenu()
        openMenu("publicRecipes")
        let rowAgain = recipeRow(named: recipeName)
        XCTAssertTrue(rowAgain.waitForExistence(timeout: 20))
        rowAgain.tap()
        tab(2).tap()
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

        guard let outputDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        } catch {
            XCTFail("Could not save \(name).png to \(outputDirectory.path): \(error)")
        }
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

    /// The tab at `index` in the recipe or scheduled-steps tab bar. By
    /// position, since the titles change with the language.
    private func tab(_ index: Int) -> XCUIElement {
        let button = app.tabBars.buttons.element(boundBy: index)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "There is no tab \(index)")
        return button
    }

    /// The row of the recipe whose name begins with `name`, or the first row
    /// when there is no such recipe.
    private func recipeRow(named name: String) -> XCUIElement {
        let named = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        if named.waitForExistence(timeout: 20) { return named }
        return app.cells.firstMatch
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
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
    }

    // MARK: - System alerts

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
