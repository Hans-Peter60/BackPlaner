//
//  ScheduledStepComponentTests.swift
//  BackPlanerTests
//

import BakePlannerCore
import Testing
@testable import BackPlaner

@Suite("Component of a planned step")
struct ScheduledStepComponentTests {

    private let ciabatta = ["Vorteig A", "Vorteig B", "Weizensauerteig", "Hauptteig"]

    @Test("A stored component name wins over the wording")
    func storedNameWins() {
        #expect(ScheduledStepComponent.componentName(
            stored: "Hauptteig",
            instructionText: "Vorteig A herstellen",
            among: ciabatta
        ) == "Hauptteig")
    }

    @Test("A stored name the recipe no longer has falls back to the wording")
    func unknownStoredNameFallsBack() {
        #expect(ScheduledStepComponent.componentName(
            stored: "Poolish",
            instructionText: "Vorteig B herstellen",
            among: ciabatta
        ) == "Vorteig B")
    }

    @Test("Hand-typed steps are matched by the component they name",
          arguments: [
            ("Vorteig A herstellen", "Vorteig A"),
            ("Vorteig B herstellen", "Vorteig B"),
            ("Hauptteig herstellen", "Hauptteig"),
            ("WEIZENSAUERTEIG ansetzen", "Weizensauerteig"),
            ("Teig falten und ruhen lassen", nil)
          ])
    func matchesByWording(text: String, expected: String?) {
        #expect(ScheduledStepComponent.componentName(
            stored: nil,
            instructionText: text,
            among: ciabatta
        ) == expected)
    }

    @Test("The component mentioned first wins, the longer name at the same spot")
    func firstMentionWins() {
        #expect(ScheduledStepComponent.componentName(
            stored: nil,
            instructionText: "Hauptteig herstellen: Vorteig A und Vorteig B zugeben",
            among: ciabatta
        ) == "Hauptteig")

        #expect(ScheduledStepComponent.componentName(
            stored: nil,
            instructionText: "Vorteig A herstellen",
            among: ["Vorteig", "Vorteig A"]
        ) == "Vorteig A")
    }

    // MARK: - One component

    /// A starter: one component, mixed in the first step and left to ripen
    /// in the second, which repeats the component's name.
    private let starter = RecipeExportData(
        name: "Roggenanstellgut 1150", summary: "", prepTime: 730, totalWeight: 210, tags: [], rating: 0,
        recurrenceIntervalDays: 7,
        components: [RecipeExportComponent(name: "Anstellgut", number: 1, ingredients: [
            RecipeExportIngredient(name: "Anstellgut", number: 1, unit: "g", weight: 10, normWeight: 10, num: 0, denom: 0),
            RecipeExportIngredient(name: "Roggenmehl 1150", number: 2, unit: "g", weight: 100, normWeight: 100, num: 0, denom: 0),
            RecipeExportIngredient(name: "Wasser", number: 3, unit: "g", weight: 100, normWeight: 100, num: 0, denom: 0)
        ])],
        instructions: [
            RecipeExportInstruction(instruction: "Zutaten verrühren", step: 1, duration: 10, startTime: 0, bakeFlag: false),
            RecipeExportInstruction(instruction: "Anstellgut bei 26 °C 12 Stunden reifen lassen", step: 2, duration: 720, startTime: 10, bakeFlag: false)
        ])

    @Test("A single-component recipe shows its ingredients at the first working step, not where the name recurs")
    func singleComponentAtTheFirstStep() {
        #expect(ScheduledStepComponent.column(for: starter, step: 1, instructionText: "Zutaten verrühren")?.name == "Anstellgut")
        #expect(ScheduledStepComponent.column(for: starter, step: 2,
                                              instructionText: "Anstellgut bei 26 °C 12 Stunden reifen lassen") == nil)
        // The reminder and the scheduling pass hand the step in too.
        #expect(ScheduledStepComponent.column(for: starter, storedComponentName: nil,
                                              instructionText: "Zutaten verrühren", step: 1) != nil)
        // The oven's steps are skipped: a bread of one component weighs out at the kneading.
        #expect(ScheduledStepComponent.singleComponentStep([
            (step: 1, instruction: "Backofen auf 250 °C vorheizen"),
            (step: 2, instruction: "Teig kneten"),
            (step: 3, instruction: "Bei 250 °C backen")
        ]) == 2)
    }

    // MARK: - Reminder text

    private let vorteigA = ComponentColumn(
        id: "vorteig-a",
        name: "Vorteig A",
        ingredients: [
            TotalIngredientData(name: "Weizenmehl 550", unit: "g", weight: 200, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Wasser", unit: "g", weight: 200, numerator: 0, denominator: 0)
        ]
    )

    @Test("The ingredient list is headed by the component and lists every ingredient")
    func ingredientsTextListsEveryIngredient() throws {
        let text = try #require(ScheduledStepComponent.ingredientsText(for: vorteigA, scale: 1.0))
        let lines = text.split(separator: "\n")

        #expect(lines.count == 3)
        #expect(lines[0].contains("Vorteig A"))
        #expect(lines[1].hasPrefix("• "))
        #expect(lines[1].hasSuffix("Weizenmehl 550"))
        #expect(lines[2].hasSuffix("Wasser"))
    }

    @Test("A component without ingredients adds no text to the reminder")
    func emptyComponentHasNoText() {
        let empty = ComponentColumn(id: "empty", name: "Hauptteig", ingredients: [])
        #expect(ScheduledStepComponent.ingredientsText(for: empty, scale: 1.0) == nil)
    }

    // MARK: - Scaling

    @Test("Weights scale by any factor, fractions only by half steps")
    func portionsAtFreeScale() {
        // 1,370 g target on a 1,000 g recipe: whole grams from 10 upwards.
        #expect(Rational.getPortion(unit: "g", weight: 200, num: 0, denom: 0, scale: 1.37) == "274 g ")
        #expect(Rational.getPortion(unit: "g", weight: 55, num: 0, denom: 0, scale: 1.5015) == "83 g ")
        // Below 10 one decimal survives; the separator follows the locale.
        let yeast = Rational.getPortion(unit: "g", weight: 2, num: 0, denom: 0, scale: 1.37)
        #expect(yeast.hasSuffix(" g ") && (yeast.hasPrefix("2.7") || yeast.hasPrefix("2,7")))
        // A half step keeps the fraction wording.
        #expect(Rational.getPortion(unit: "Würfel", weight: 0, num: 1, denom: 2, scale: 1.5) == "3/4 Würfel ")
        // Any other scale turns the fraction into a decimal.
        let cube = Rational.getPortion(unit: "Würfel", weight: 0, num: 1, denom: 2, scale: 1.37)
        #expect(cube.hasSuffix(" Würfel ") && !cube.contains("/"))
        // The half-step entry point still means the same thing.
        #expect(Rational.getPortion(unit: "g", weight: 200, num: 0, denom: 0, targetServings: 3)
                == Rational.getPortion(unit: "g", weight: 200, num: 0, denom: 0, scale: 1.5))
    }

    @Test("A target weight wins over the picker; without one the picker's half steps apply")
    func servingScaleFactor() {
        #expect(ServingScale.factor(servingSize: 2, targetWeight: nil, baseWeight: 1000) == 1.0)
        #expect(ServingScale.factor(servingSize: 3, targetWeight: nil, baseWeight: 1000) == 1.5)
        #expect(ServingScale.factor(servingSize: 2, targetWeight: 1370, baseWeight: 1000) == 1.37)
        #expect(ServingScale.factor(servingSize: 4, targetWeight: 0, baseWeight: 1000) == 2.0)
    }

    @Test("Baker's percentages relate every weight to the component's flour")
    func bakersPercentages() {
        let ingredients = [
            TotalIngredientData(name: "Weizenmehl 550", unit: "g", weight: 400, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Roggenvollkornschrot", unit: "g", weight: 100, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Wasser", unit: "g", weight: 350, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Hefe", unit: "Würfel", weight: 0, numerator: 1, denominator: 2),
            TotalIngredientData(name: "gesamtes Brühstück", unit: "", weight: 1, numerator: 0, denominator: 0)
        ]
        let flour = BakersPercentage.flourWeight(of: ingredients)
        #expect(flour == 500)
        #expect(BakersPercentage.suffix(for: ingredients[2], flourWeight: flour) == " ·\u{00A0}70\u{00A0}%")
        #expect(BakersPercentage.suffix(for: ingredients[0], flourWeight: flour) == " ·\u{00A0}80\u{00A0}%")
        // Pieces carry no weight and get no percentage.
        #expect(BakersPercentage.suffix(for: ingredients[3], flourWeight: flour) == "")
        // A whole component used as an ingredient has no unit and no share.
        #expect(BakersPercentage.suffix(for: ingredients[4], flourWeight: flour) == "")
        // No flour, no percentages at all.
        #expect(BakersPercentage.suffix(for: ingredients[2], flourWeight: 0) == "")
    }

    @Test("The reminder body keeps the bare instruction when there are no details")
    func reminderBodyWithoutDetails() {
        #expect(NotificationActions.reminderBody(instruction: "Teig falten", details: nil) == "Teig falten")
        #expect(NotificationActions.reminderBody(instruction: "Teig falten", details: "") == "Teig falten")
    }

    @Test("The reminder body puts the details under the instruction")
    func reminderBodyWithDetails() {
        #expect(NotificationActions.reminderBody(instruction: "Vorteig A herstellen", details: "Zutaten:\n• 200 g Mehl")
                == "Vorteig A herstellen\n\nZutaten:\n• 200 g Mehl")
    }
}
