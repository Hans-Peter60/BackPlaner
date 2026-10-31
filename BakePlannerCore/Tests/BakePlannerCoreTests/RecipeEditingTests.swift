//
//  RecipeEditingTests.swift
//  BakePlannerCoreTests
//
//  Amounts as typed in an editor, and the weights and times worked out
//  again after editing.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Amounts as typed in an editor")
struct IngredientAmountTextTests {

    @Test("A number is a weight, with comma or point")
    func weights() {
        #expect(IngredientAmountText.parse("250") == IngredientAmountText(weight: 250, numerator: 0, denominator: 0))
        #expect(IngredientAmountText.parse("1,5") == IngredientAmountText(weight: 1.5, numerator: 0, denominator: 0))
        #expect(IngredientAmountText.parse(" 12.5 ") == IngredientAmountText(weight: 12.5, numerator: 0, denominator: 0))
    }

    @Test("A fraction, also with a whole number in front")
    func fractions() {
        #expect(IngredientAmountText.parse("1/4") == IngredientAmountText(weight: 0, numerator: 1, denominator: 4))
        #expect(IngredientAmountText.parse("1 1/2") == IngredientAmountText(weight: 0, numerator: 3, denominator: 2))
        #expect(IngredientAmountText.parse("1/1") == IngredientAmountText(weight: 0, numerator: 1, denominator: 1))
    }

    @Test("Nothing typed is no amount, nonsense is refused")
    func emptyAndInvalid() {
        #expect(IngredientAmountText.parse("") == IngredientAmountText(weight: 0, numerator: 0, denominator: 0))
        #expect(IngredientAmountText.parse("viel") == nil)
        #expect(IngredientAmountText.parse("1/0") == nil)
        #expect(IngredientAmountText.parse("-5") == nil)
    }

    @Test("Written out, an amount reads back as itself")
    func roundTrip() {
        let amounts = [
            IngredientAmountText(weight: 250, numerator: 0, denominator: 0),
            IngredientAmountText(weight: 1.5, numerator: 0, denominator: 0),
            IngredientAmountText(weight: 0, numerator: 1, denominator: 4),
            IngredientAmountText(weight: 0, numerator: 3, denominator: 2),
            IngredientAmountText(weight: 0, numerator: 1, denominator: 1),
            IngredientAmountText(weight: 0, numerator: 0, denominator: 0),
        ]
        for amount in amounts {
            let text = IngredientAmountText.text(weight: amount.weight, numerator: amount.numerator,
                                                 denominator: amount.denominator, decimalSeparator: ",")
            #expect(IngredientAmountText.parse(text) == amount, "\(text)")
        }
        #expect(IngredientAmountText.text(weight: 1.5, numerator: 0, denominator: 0, decimalSeparator: ",") == "1,5")
        #expect(IngredientAmountText.text(weight: 0, numerator: 3, denominator: 2, decimalSeparator: ",") == "1 1/2")
    }
}

@Suite("Weights and times after editing a recipe")
struct RecipeRecalculationTests {

    private func recipe() -> RecipeExportData {
        RecipeExportData(
            name: "Brot", summary: "", urlLink: nil, prepTime: 0, totalWeight: 0, tags: [], rating: 0,
            recurrenceIntervalDays: 0, image: nil,
            components: [
                RecipeExportComponent(name: "Teig", number: 1, ingredients: [
                    RecipeExportIngredient(name: "Weizenmehl 550", number: 1, unit: "g", weight: 500, normWeight: 0, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Wasser", number: 2, unit: "g", weight: 350, normWeight: 0, num: 0, denom: 0),
                ]),
            ],
            instructions: [
                RecipeExportInstruction(instruction: "Kneten", step: 1, duration: 10, startTime: 99, bakeFlag: false, componentName: nil),
                RecipeExportInstruction(instruction: "Gehen lassen", step: 2, duration: 60, startTime: 99, bakeFlag: false, componentName: nil),
                RecipeExportInstruction(instruction: "Backen", step: 3, duration: 40, startTime: 99, bakeFlag: true, componentName: nil),
            ])
    }

    // Grams only: in the package's own tests the unit table is the test
    // runner's bundle, which has none (the app's tests cover the units).
    @Test("Each ingredient's grams and the total are worked out")
    func weights() {
        let recalculated = recipe().recalculated()
        #expect(recalculated.components[0].ingredients.map(\.normWeight) == [500, 350])
        #expect(recalculated.totalWeight == 850)
    }

    @Test("Steps follow one another, and the preparation lasts until the last ends")
    func times() {
        let recalculated = recipe().recalculated()
        #expect(recalculated.instructions.map(\.startTime) == [0, 10, 70])
        #expect(recalculated.prepTime == 110)
    }
}
