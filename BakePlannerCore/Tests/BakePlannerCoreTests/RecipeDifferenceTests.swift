//
//  RecipeDifferenceTests.swift
//  BakePlannerCoreTests
//
//  What is different between a variant and its origin.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Differences between two recipes")
struct RecipeDifferenceTests {

    private func ingredient(_ name: String, _ weight: Double, unit: String = "g", num: Int = 0, denom: Int = 0) -> RecipeExportIngredient {
        RecipeExportIngredient(name: name, number: 1, unit: unit, weight: weight, normWeight: unit == "g" ? weight : 0, num: num, denom: denom)
    }

    private func step(_ number: Double, _ text: String, minutes: Int) -> RecipeExportInstruction {
        RecipeExportInstruction(instruction: text, step: number, duration: minutes, startTime: 0, bakeFlag: false, componentName: nil)
    }

    /// A country loaf with a sourdough and a main dough.
    private func landbrot() -> RecipeExportData {
        RecipeExportData(
            name: "Landbrot", summary: "", prepTime: 0, totalWeight: 1010, tags: [], rating: 0, recurrenceIntervalDays: 0,
            components: [
                RecipeExportComponent(name: "Sauerteig", number: 1, ingredients: [
                    ingredient("Roggenmehl 1150", 100), ingredient("Wasser", 100), ingredient("Anstellgut", 10),
                ]),
                RecipeExportComponent(name: "Hauptteig", number: 2, ingredients: [
                    ingredient("gesamter Sauerteig", 0), ingredient("Weizenmehl 1050", 400),
                    ingredient("Wasser", 250), ingredient("Salz", 12), ingredient("Hefe", 2),
                ]),
            ],
            instructions: [
                step(1, "Sauerteig: Zutaten mischen und 16 Stunden reifen lassen.", minutes: 960),
                step(2, "Alle Zutaten 8 Minuten kneten.", minutes: 8),
                step(3, "90 Minuten Stockgare.", minutes: 90),
                step(4, "Rundwirken und 60 Minuten Stückgare.", minutes: 60),
                step(5, "50 Minuten bei 250 °C fallend backen.", minutes: 50),
            ]
        )
    }

    @Test("A flour substitution reads as 'statt', with the water that changed with it")
    func flourSubstitution() {
        let original = landbrot()
        var variant = original
        variant.components[1].ingredients[1] = ingredient("Dinkelmehl 630", 400)
        variant.components[1].ingredients[2] = ingredient("Wasser", 235)
        variant.totalWeight = 995

        let difference = RecipeDifference.between(original, variant)
        #expect(difference.components.isEmpty)
        #expect(difference.ingredients == [
            .amountChanged(component: "Hauptteig", name: "Wasser", from: "250 g", to: "235 g"),
            .replaced(component: "Hauptteig", from: "Weizenmehl 1050", to: "Dinkelmehl 630", amount: "400 g"),
        ])
        #expect(difference.dough.totalWeight?.from == 1010)
        #expect(difference.dough.totalWeight?.to == 995)
        #expect(difference.dough.hydration != nil)
        #expect(difference.steps.isEmpty)
        #expect(!difference.isEmpty)
    }

    @Test("Added and removed ingredients, and a different amount")
    func ingredients() {
        let original = landbrot()
        var variant = original
        variant.components[1].ingredients.removeAll { $0.name == "Hefe" }
        variant.components[1].ingredients.append(ingredient("Honig", 15))
        variant.components[1].ingredients.append(ingredient("Kümmel", 0, unit: "TL", num: 1, denom: 2))
        variant.components[1].ingredients[3] = ingredient("Salz", 14)

        let difference = RecipeDifference.between(original, variant)
        // Honey came where the yeast went: that reads as a replacement, the
        // caraway as new.
        #expect(difference.ingredients == [
            .amountChanged(component: "Hauptteig", name: "Salz", from: "12 g", to: "14 g"),
            .replaced(component: "Hauptteig", from: "Hefe", to: "Honig", amount: "2 g → 15 g"),
            .added(component: "Hauptteig", amount: "1/2 TL", name: "Kümmel"),
        ])
    }

    @Test("Components that come, go or are renamed")
    func components() {
        let original = landbrot()
        var variant = original
        variant.components[0].name = "Roggensauerteig"
        variant.components.append(RecipeExportComponent(name: "Brühstück", number: 3, ingredients: [
            ingredient("Altbrot", 50), ingredient("Wasser", 100),
        ]))

        let difference = RecipeDifference.between(original, variant)
        #expect(difference.components == [.renamed(from: "Sauerteig", to: "Roggensauerteig"), .added("Brühstück")])
        // The renamed component's ingredients are compared, not reported as new.
        #expect(difference.ingredients.isEmpty)

        var fewer = original
        fewer.components.removeFirst()
        #expect(RecipeDifference.between(original, fewer).components == [.removed("Sauerteig")])
    }

    @Test("Steps: another duration, another wording, a step more and one less")
    func steps() {
        let original = landbrot()
        var variant = original
        variant.instructions[2] = step(3, "90 Minuten Stockgare.", minutes: 120)
        variant.instructions[3] = step(4, "Langwirken und 75 Minuten Stückgare.", minutes: 75)
        variant.instructions.insert(step(3.1, "Nach 30 Minuten dehnen und falten.", minutes: 1), at: 3)
        variant.instructions.removeLast()

        let difference = RecipeDifference.between(original, variant)
        #expect(difference.steps == [
            .durationChanged(step: 3, text: "90 Minuten Stockgare.", fromMinutes: 90, toMinutes: 120),
            .added(step: 3.1, text: "Nach 30 Minuten dehnen und falten."),
            .textChanged(step: 4, from: "Rundwirken und 60 Minuten Stückgare.", to: "Langwirken und 75 Minuten Stückgare."),
            .durationChanged(step: 4, text: "Langwirken und 75 Minuten Stückgare.", fromMinutes: 60, toMinutes: 75),
            .removed(step: 5, text: "50 Minuten bei 250 °C fallend backen."),
        ])
    }

    @Test("Identical recipes differ in nothing; whitespace and case in steps do not count")
    func identical() {
        let original = landbrot()
        var same = original
        same.instructions[1].instruction = "  Alle Zutaten 8 Minuten  kneten. "
        let difference = RecipeDifference.between(original, same)
        #expect(difference.isEmpty)
        #expect(difference.lines().isEmpty)
        #expect(difference.summary().isEmpty)
    }

    @Test("The lines name the component only in a recipe with several, and the summary cuts off")
    func lines() {
        let original = landbrot()
        var variant = original
        variant.components[1].ingredients[1] = ingredient("Dinkelmehl 630", 400)
        variant.components[1].ingredients[3] = ingredient("Salz", 14)
        variant.instructions[2] = step(3, "90 Minuten Stockgare.", minutes: 120)

        let lines = RecipeDifference.between(original, variant).lines()
        #expect(lines.first == "Hauptteig: Salz 12 g → 14 g")
        #expect(lines.contains("Hauptteig: Dinkelmehl 630 statt Weizenmehl 1050 (400 g)"))
        #expect(lines.contains { $0.hasPrefix("Schritt 3: 1 h 30 min → 2 h") })
        let summary = RecipeDifference.between(original, variant).summary(maximumItems: 2)
        #expect(summary.hasPrefix("Hauptteig: Salz 12 g → 14 g · Hauptteig: Dinkelmehl 630 statt Weizenmehl 1050 (400 g) · "))
        #expect(summary.hasSuffix("weitere"))

        var single = RecipeExportData(
            name: "Weißbrot", summary: "", prepTime: 0, totalWeight: 830, tags: [], rating: 0, recurrenceIntervalDays: 0,
            components: [RecipeExportComponent(name: "Teig", number: 1, ingredients: [
                ingredient("Weizenmehl 550", 500), ingredient("Wasser", 320), ingredient("Salz", 10),
            ])],
            instructions: [step(1, "Kneten.", minutes: 10)]
        )
        let moreWater = { () -> RecipeExportData in var copy = single; copy.components[0].ingredients[1] = self.ingredient("Wasser", 340); copy.totalWeight = 850; return copy }()
        let singleLines = RecipeDifference.between(single, moreWater).lines()
        #expect(singleLines.first == "Wasser 320 g → 340 g")
        #expect(singleLines.contains("Hydration 64 % → 68 %"))
        #expect(singleLines.contains("TA 164 → 168"))
        #expect(singleLines.contains("Teiggewicht 830 g → 850 g"))
        single.totalWeight = 830
    }
}
