//
//  UITestSupport.swift
//  BackPlaner
//

import CoreData
import UIKit

/// Launch switches for the UI tests in BackPlanerUITests. They only exist in
/// DEBUG builds, so the shipped app ignores them whatever it is started with.
///
/// `-UITesting` runs the app on an empty in-memory store, so a test neither
/// sees nor changes the recipes on the simulator, and every launch starts from
/// the same state. `-UITestingSeedRecipe` adds one known recipe to that store:
/// saving a recipe through the form requires a photo, and the photo picker
/// cannot be driven reliably from a UI test.
///
/// `-UITestingPlanStart HH:mm` presets the date of the scheduling controls to
/// the next time the clock shows HH:mm (today, or tomorrow once it has
/// passed). The App Store previews use it on their way through the baking
/// tab: started at the time of the recording, a sourdough plan puts most of
/// its steps into the night and the schedule fills with warnings, while a
/// start at 20:00 lets the dough rest through the night. It works on the
/// simulator's real store, independent of `-UITesting`.
///
/// `-UITestingPlanFinish HH:mm` presets the controls to "fertig bis" instead,
/// at the first HH:mm that is at least a day away, so that a recipe of up to
/// a day's length starts in the future. The App Store screenshots use it:
/// the picture of the baking tab then shows what sets the app apart, a
/// finish time and the start times worked back from it. It wins over
/// `-UITestingPlanStart` when both are given.
enum UITestSupport {

    static let seededRecipeName = "UI-Test-Brot"

    /// Whether the app is only the host of a unit-test run (BackPlanerTests).
    /// XCTest sets this variable when it launches the host app; the UI tests
    /// drive the app from another process, so it is absent there. In a
    /// unit-test run the app skips its start-up work — store maintenance, the
    /// widget publisher, notifications, the backdrop blur, the anonymous
    /// sign-in — and shows an empty window: the tests build what they need
    /// themselves, and every piece left out is one that cannot hang the run.
    static var isUnitTestHost: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
        #else
        false
        #endif
    }

    static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting")
        #else
        false
        #endif
    }

    static var seedsRecipe: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-UITestingSeedRecipe")
    }

    /// The date asked for with `-UITestingPlanStart`, or nil when the switch
    /// is absent or malformed.
    static func planStart(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        clockTime(after: "-UITestingPlanStart", atLeast: 0, now: now, calendar: calendar)
    }

    /// The date asked for with `-UITestingPlanFinish`, or nil when the switch
    /// is absent or malformed.
    static func planFinish(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        clockTime(after: "-UITestingPlanFinish", atLeast: 24 * 60 * 60, now: now, calendar: calendar)
    }

    /// Whether the scheduling controls start on "fertig bis".
    static var plansToFinish: Bool {
        planFinish() != nil
    }

    /// `-UITestingScrollToPlanControls`: the baking tab of a public recipe
    /// scrolls its date controls to the top once it appears. The App Store
    /// screenshots ask for it, so the picture of the tab opens on the date
    /// and the schedule; dragging the page there from the test proved
    /// unreliable, with the drags now and then taken by the content.
    static var scrollsToPlanControls: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestingScrollToPlanControls")
        #else
        false
        #endif
    }

    /// What `-UITestingMonetization` fixes for a run: the configuration the
    /// Firestore document would otherwise supply, and the purchase state.
    struct MonetizationOverride: Equatable {
        var config: MonetizationConfig
        /// Whether the run counts as having bought Pro.
        var purchased: Bool
        /// Stands in for `AppTransaction.originalAppVersion` (a build number).
        var originalAppVersion: String?
    }

    /// `-UITestingMonetization <flags>`: fixes the Pro configuration for a
    /// test instead of reading `config/monetization`. The flags are a
    /// comma-separated list of `proRequired`, `storeVisible`, `purchased`,
    /// `freeImports=<n>`, `grandfatherBefore=<build>` and
    /// `originalBuild=<build>`; `-UITestingMonetization free` fixes the
    /// all-free configuration. The screenshots and the smoke tests use it so
    /// that a run never depends on what the console currently says.
    static var monetizationOverride: MonetizationOverride? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-UITestingMonetization"),
              index + 1 < arguments.count else { return nil }
        return monetizationOverride(from: arguments[index + 1])
        #else
        return nil
        #endif
    }

    /// Parses the flags of `-UITestingMonetization`; unknown flags are ignored.
    static func monetizationOverride(from flags: String) -> MonetizationOverride {
        var override = MonetizationOverride(config: .free, purchased: false, originalAppVersion: nil)
        for flag in flags.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let parts = flag.split(separator: "=", maxSplits: 1).map(String.init)
            switch parts.first {
            case "proRequired":  override.config.proRequired = true
            case "storeVisible": override.config.storeVisible = true
            case "purchased":    override.purchased = true
            case "freeImports":  override.config.freeImportsPerMonth = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
            case "grandfatherBefore" where parts.count == 2: override.config.grandfatherBeforeBuild = parts[1]
            case "originalBuild" where parts.count == 2:     override.originalAppVersion = parts[1]
            default: break
            }
        }
        return override
    }

    /// The first time the clock shows the HH:mm that follows `argument`,
    /// `distance` seconds or more from `now`; nil without the argument or
    /// with a malformed time.
    private static func clockTime(after argument: String, atLeast distance: TimeInterval,
                                  now: Date, calendar: Calendar) -> Date? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument),
              index + 1 < arguments.count else { return nil }
        let parts = arguments[index + 1].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]),
              var date = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)
        else { return nil }
        let earliest = now.addingTimeInterval(distance)
        // At most a few days: the loop ends once the time is far enough away.
        for _ in 0..<7 where date <= earliest {
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = next
        }
        return date
        #else
        return nil
        #endif
    }

    /// Stores a small recipe whose steps the plan test can find again in
    /// "Geplante Schritte".
    static func seedRecipe(into context: NSManagedObjectContext) {
        let recipe = RecipeFB()
        recipe.name = seededRecipeName
        recipe.summary = "Rezept für die UI-Tests."

        let mainDough = ComponentFB()
        mainDough.name = "Hauptteig"
        mainDough.number = 1
        mainDough.ingredients = [("Weizenmehl 550", 500.0), ("Wasser", 350.0), ("Salz", 10.0)]
            .enumerated()
            .map { index, entry in
                let ingredient = IngredientFB()
                ingredient.number = index + 1
                ingredient.name = entry.0
                ingredient.weight = entry.1
                ingredient.unit = "g"
                return ingredient
            }
        recipe.components = [mainDough]

        recipe.instructions = [(1.0, "Teig kneten", 10), (2.0, "Teig gehen lassen", 60), (3.0, "Bei 250 °C backen", 40)]
            .map { step, text, minutes in
                let instruction = InstructionFB()
                instruction.id = UUID().uuidString
                instruction.step = step
                instruction.instruction = text
                instruction.duration = minutes
                return instruction
            }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { canvas in
            UIColor.brown.setFill()
            canvas.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }

        do {
            _ = try RecipeModel().uploadRecipeIntoCoreData(recipeId: nil,
                                                           recipeFB: recipe,
                                                           context: context,
                                                           recipeImage: image)
        } catch {
            AppLog.data.error("UI test recipe could not be seeded: \(error.localizedDescription)")
        }
    }
}
