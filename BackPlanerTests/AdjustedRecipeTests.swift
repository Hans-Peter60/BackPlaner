//
//  AdjustedRecipeTests.swift
//  BackPlanerTests
//
//  The name a flour substitution or a starter adjustment gives its copy,
//  and how a second adjustment extends it instead of nesting.
//

import BakePlannerCore
import Foundation
import Testing
@testable import BackPlaner

@Suite("Adjusted recipes: naming the copy")
struct AdjustedRecipeTests {

    private let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 14))!

    private var stamp: String {
        date.formatted(.dateTime.day().month().year().locale(AppSettings.locale))
    }

    @Test("The first adjustment joins the name with a dash and today's date")
    func firstAdjustment() {
        let name = AdjustedRecipe.name(original: "Landbrot", adjustment: "Dinkelmehl 630", on: date)
        #expect(name == "Landbrot – Dinkelmehl 630 (\(stamp))")
        #expect(AdjustedRecipe.hasDatedSuffix(name))
        #expect(!AdjustedRecipe.hasDatedSuffix("Landbrot"))
    }

    @Test("A further adjustment of a copy is listed after the first, with a fresh date")
    func secondAdjustment() {
        let first = AdjustedRecipe.name(original: "Landbrot", adjustment: "Dinkelmehl 630", on: date)
        let later = date.addingTimeInterval(3 * 24 * 60 * 60)
        let second = AdjustedRecipe.name(original: first, adjustment: "TA 210", on: later)
        let laterStamp = later.formatted(.dateTime.day().month().year().locale(AppSettings.locale))
        #expect(second == "Landbrot – Dinkelmehl 630, TA 210 (\(laterStamp))")
    }

    @Test("A dash in the original name is left alone; only the dated suffix is recognised")
    func dashInOriginal() {
        let name = AdjustedRecipe.name(original: "Brot – Sonntag", adjustment: "TA 210", on: date)
        #expect(name == "Brot – Sonntag – TA 210 (\(stamp))")
    }

    @Test("Brackets without a year are part of the name, not a date")
    func bracketsWithoutYear() {
        #expect(!AdjustedRecipe.hasDatedSuffix("Pizza (dünn)"))
        let name = AdjustedRecipe.name(original: "Pizza (dünn)", adjustment: "Weizenmehl 550", on: date)
        #expect(name == "Pizza (dünn) – Weizenmehl 550 (\(stamp))")
    }

    @Test("The flour substitution and the starter adjustment both name their copies this way")
    func adjustmentsUseTheName() throws {
        let recipe = RecipeExportData(
            name: "Landbrot", summary: "", urlLink: nil, prepTime: 0, totalWeight: 900, tags: [], rating: 0,
            recurrenceIntervalDays: 0, image: nil,
            components: [RecipeExportComponent(name: "Hauptteig", number: 1, ingredients: [
                RecipeExportIngredient(name: "Weizenmehl 550", number: 1, unit: "g", weight: 500, normWeight: 500, num: 0, denom: 0),
                RecipeExportIngredient(name: "Wasser", number: 2, unit: "g", weight: 340, normWeight: 340, num: 0, denom: 0),
                RecipeExportIngredient(name: "Anstellgut TA 200", number: 3, unit: "g", weight: 60, normWeight: 60, num: 0, denom: 0)
            ])],
            instructions: [])

        let flour = try #require(FlourSubstitution.apply(to: recipe, componentIndex: 0, ingredientIndex: 0,
                                                         target: FlourSubstitution.wheat550, on: date))
        #expect(flour.recipe.name.hasSuffix("(\(stamp))"))

        let starter = try #require(StarterYieldAdjustment.apply(to: recipe, componentIndex: 0, ingredientIndex: 2,
                                                                targetYield: 210, on: date))
        #expect(starter.recipe.name == "Landbrot – TA 210 (\(stamp))")
    }
}
