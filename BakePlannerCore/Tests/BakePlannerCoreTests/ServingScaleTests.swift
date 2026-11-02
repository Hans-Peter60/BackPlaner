//
//  ServingScaleTests.swift
//  BakePlannerCoreTests
//

import Testing
@testable import BakePlannerCore

@Suite("The scale a recipe is shown at, and the baker's percentages")
struct ServingScaleTests {

    @Test("Without a target weight the picker's half steps decide")
    func pickerHalvesWithoutWeight() {
        #expect(ServingScale.factor(servingSize: 2, targetWeight: nil, baseWeight: 1000) == 1)
        #expect(ServingScale.factor(servingSize: 3, targetWeight: nil, baseWeight: 1000) == 1.5)
        #expect(ServingScale.factor(servingSize: 1, targetWeight: 0, baseWeight: 1000) == 0.5)
    }

    @Test("A target weight scales to it, whatever the picker says")
    func targetWeightWins() {
        #expect(ServingScale.factor(servingSize: 4, targetWeight: 1500, baseWeight: 1000) == 1.5)
    }

    @Test("A recipe without weight cannot be scaled to a target weight")
    func noBaseWeightFallsBackToPicker() {
        #expect(ServingScale.factor(servingSize: 2, targetWeight: 800, baseWeight: 0) == 1)
    }

    @Test("Percentages relate every weighed ingredient to the component's flour")
    func percentagesOfTheFlour() {
        let ingredients = [
            TotalIngredientData(name: "Weizenmehl 550", unit: "g", weight: 400, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Roggenmehl 1150", unit: "g", weight: 100, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Wasser", unit: "g", weight: 310, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Salz", unit: "g", weight: 10, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Ei", unit: "St", weight: 0, numerator: 1, denominator: 1),
            TotalIngredientData(name: "gesamtes Brühstück", unit: "", weight: 200, numerator: 1, denominator: 1)
        ]
        let flour = BakersPercentage.flourWeight(of: ingredients)
        #expect(flour == 500)
        #expect(BakersPercentage.suffix(for: ingredients[0], flourWeight: flour) == " ·\u{00A0}80\u{00A0}%")
        #expect(BakersPercentage.suffix(for: ingredients[2], flourWeight: flour) == " ·\u{00A0}62\u{00A0}%")
        #expect(BakersPercentage.suffix(for: ingredients[3], flourWeight: flour) == " ·\u{00A0}2\u{00A0}%")
        // Pieces and a whole component as an ingredient carry no percentage.
        #expect(BakersPercentage.suffix(for: ingredients[4], flourWeight: flour) == "")
        #expect(BakersPercentage.suffix(for: ingredients[5], flourWeight: flour) == "")
    }

    @Test("A component without flour shows no percentages")
    func noFlourNoPercentages() {
        let ingredients = [
            TotalIngredientData(name: "Wasser", unit: "g", weight: 200, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Leinsamenschrot", unit: "g", weight: 100, numerator: 0, denominator: 0)
        ]
        #expect(BakersPercentage.flourWeight(of: ingredients) == 0)
        #expect(BakersPercentage.suffix(for: ingredients[0], flourWeight: 0) == "")
    }

    @Test("The recipe page carries the percentages only when asked, and they ignore the scale")
    func printDataLinesWithPercentages() {
        let recipe = RecipeExportData(
            name: "Weißbrot", summary: "", prepTime: 0, totalWeight: 810, tags: [], rating: 0, recurrenceIntervalDays: 0,
            components: [RecipeExportComponent(name: "Hauptteig", number: 1, ingredients: [
                RecipeExportIngredient(name: "Weizenmehl 550", number: 1, unit: "g", weight: 500, normWeight: 500, num: 0, denom: 0),
                RecipeExportIngredient(name: "Wasser", number: 2, unit: "g", weight: 300, normWeight: 300, num: 0, denom: 0),
                RecipeExportIngredient(name: "Salz", number: 3, unit: "g", weight: 10, normWeight: 10, num: 0, denom: 0)
            ])],
            instructions: []
        )
        let plain = RecipePrintData(data: recipe, scale: 1)
        #expect(plain.components[0].lines[1] == "• 300 g Wasser")

        let withPercentages = RecipePrintData(data: recipe, scale: 2, bakersPercentages: true)
        #expect(withPercentages.components[0].lines[0] == "• 1000 g Weizenmehl 550 ·\u{00A0}100\u{00A0}%")
        #expect(withPercentages.components[0].lines[1] == "• 600 g Wasser ·\u{00A0}60\u{00A0}%")
        #expect(withPercentages.components[0].lines[2] == "• 20 g Salz ·\u{00A0}2\u{00A0}%")
    }
}
