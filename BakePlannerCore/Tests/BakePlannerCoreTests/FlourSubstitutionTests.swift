//
//  FlourSubstitutionTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Flour substitution: recognition, water, hints, applying to a recipe")
struct FlourSubstitutionTests {

    typealias Flour = FlourSubstitution.Flour
    typealias Grain = FlourSubstitution.Grain
    typealias Milling = FlourSubstitution.Milling

    private func flour(_ grain: Grain, _ milling: Milling) -> Flour {
        FlourSubstitution.flours(of: grain).first { $0.milling == milling }!
    }

    // MARK: Recognition

    @Test("Grain and type are read off the ingredient line", arguments: [
        ("Weizenmehl 550",            Grain.wheat,   Milling.type(550)),
        ("Weizenmehl Type 1050",      Grain.wheat,   Milling.type(1050)),
        ("Weizenvollkornmehl",        Grain.wheat,   Milling.wholeGrain),
        ("Farine de blé T65",         Grain.wheat,   Milling.french(65)),
        ("Dinkelmehl 630",            Grain.spelt,   Milling.type(630)),
        ("Dinkelvollkornmehl",        Grain.spelt,   Milling.wholeGrain),
        ("Roggenmehl 1150",           Grain.rye,     Milling.type(1150)),
        ("Farine de seigle T130",     Grain.rye,     Milling.type(1370)),
        ("Emmermehl hell",            Grain.emmer,   Milling.light),
        ("Einkornvollkornmehl",       Grain.einkorn, Milling.wholeGrain),
        ("Petit épeautre (farine)",   Grain.einkorn, Milling.light),
        ("Hartweizengrieß",           Grain.durum,   Milling.semolina),
        ("Semola rimacinata di grano duro", Grain.durum, Milling.semolina),
        ("Ruchmehl",                  Grain.wheat,   Milling.type(1050))
    ])
    func recognizes(line: String, grain: Grain, milling: Milling) throws {
        let found = try #require(FlourSubstitution.recognize(line))
        #expect(found.grain == grain)
        #expect(found.milling == milling)
    }

    @Test("A type the grain is not sold in lands on the nearest one")
    func nearestType() throws {
        let found = try #require(FlourSubstitution.recognize("Dinkelmehl 550"))
        #expect(found.grain == .spelt)
        #expect(found.milling == .type(630))
    }

    @Test("A grain without a type gets its everyday flour")
    func defaultType() throws {
        #expect(try #require(FlourSubstitution.recognize("Mehl")).milling == .type(550))
        #expect(try #require(FlourSubstitution.recognize("Roggenmehl")).milling == .type(1150))
    }

    @Test("Non-flours are not recognised", arguments: ["Wasser", "Salz", "Leinsamenschrot", "Mandelmehl", "Anstellgut"])
    func notFlour(line: String) {
        #expect(FlourSubstitution.recognize(line) == nil)
    }

    // MARK: Water

    @Test("Water moves by the difference in what the flours bind")
    func waterDelta() {
        let delta = FlourSubstitution.waterDelta(grams: 500, from: flour(.wheat, .type(550)), to: flour(.wheat, .wholeGrain))
        #expect(delta == 50)

        let less = FlourSubstitution.waterDelta(grams: 500, from: flour(.wheat, .type(550)), to: flour(.spelt, .type(630)))
        #expect(less == -20)
    }

    @Test("Swapping a flour for itself changes nothing")
    func identity() {
        let wheat = flour(.wheat, .type(550))
        #expect(FlourSubstitution.waterDelta(grams: 500, from: wheat, to: wheat) == 0)
        #expect(FlourSubstitution.hints(from: wheat, to: wheat, ryeShareAfter: nil).isEmpty)
    }

    // MARK: Hints

    @Test("Spelt brings its kneading and soaker advice, wholegrain its soaking advice")
    func speltHints() {
        let hints = FlourSubstitution.hints(from: flour(.wheat, .type(550)), to: flour(.spelt, .wholeGrain), ryeShareAfter: 0)
        #expect(hints.contains(.speltHandling))
        #expect(hints.contains(.speltSoaker))
        #expect(hints.contains(.wholeGrainSoak))
    }

    @Test("Rye above half the flour asks for mixing only, below for acidifying")
    func ryeHints() {
        let toRye = flour(.rye, .type(1150))
        #expect(FlourSubstitution.hints(from: flour(.wheat, .type(550)), to: toRye, ryeShareAfter: 0.7).contains(.ryeMixOnly))
        #expect(FlourSubstitution.hints(from: flour(.wheat, .type(550)), to: toRye, ryeShareAfter: 0.3).contains(.ryeAcidify))
    }

    // MARK: Applying to a recipe

    private func recipe() -> RecipeExportData {
        RecipeExportData(
            name: "Landbrot", summary: "", urlLink: nil, prepTime: 0, totalWeight: 850,
            tags: [], rating: 0, recurrenceIntervalDays: 0, image: nil,
            components: [
                RecipeExportComponent(name: "Hauptteig", number: 0, ingredients: [
                    RecipeExportIngredient(name: "Weizenmehl 550", number: 0, unit: "g", weight: 500, normWeight: 500, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Wasser",         number: 1, unit: "g", weight: 340, normWeight: 340, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Salz",           number: 2, unit: "g", weight: 10,  normWeight: 10,  num: 0, denom: 0)
                ])
            ],
            instructions: []
        )
    }

    @Test("The flour line is renamed and the component's water moved")
    func applySwapsFlourAndWater() throws {
        let applied = try #require(FlourSubstitution.apply(to: recipe(), componentIndex: 0, ingredientIndex: 0, target: flour(.wheat, .wholeGrain)))

        #expect(applied.waterDelta == 50)
        #expect(applied.waterAdjusted)
        let ingredients = applied.recipe.components[0].ingredients
        #expect(ingredients[0].weight == 500)
        #expect(ingredients[0].name == flour(.wheat, .wholeGrain).ingredientName)
        #expect(ingredients[1].weight == 390)
        #expect(ingredients[1].normWeight == 390)
        #expect(ingredients[2].weight == 10)
        #expect(applied.recipe.totalWeight == 900)
        #expect(applied.recipe.name.hasPrefix("Landbrot – "))
    }

    @Test("Without a water line the swap is made but nothing else moves")
    func applyWithoutWater() throws {
        var dry = recipe()
        dry.components[0].ingredients.remove(at: 1)

        let applied = try #require(FlourSubstitution.apply(to: dry, componentIndex: 0, ingredientIndex: 0, target: flour(.rye, .type(1150))))

        #expect(applied.waterDelta == 60)
        #expect(!applied.waterAdjusted)
        #expect(applied.recipe.totalWeight == 850)
    }

    @Test("Without water the component's milk stands in for it")
    func milkStandsInForWater() throws {
        var milky = recipe()
        milky.components[0].ingredients[1].name = "Milch"

        let applied = try #require(FlourSubstitution.apply(to: milky, componentIndex: 0, ingredientIndex: 0, target: flour(.wheat, .wholeGrain)))

        #expect(applied.waterAdjusted)
        #expect(applied.adjustedLiquidName == "Milch")
        #expect(applied.recipe.components[0].ingredients[1].weight == 390)
    }

    @Test("Water is preferred over milk when the component has both")
    func waterPreferredOverMilk() throws {
        var both = recipe()
        both.components[0].ingredients.insert(
            RecipeExportIngredient(name: "Milch", number: 1, unit: "g", weight: 100, normWeight: 100, num: 0, denom: 0),
            at: 1)

        let applied = try #require(FlourSubstitution.apply(to: both, componentIndex: 0, ingredientIndex: 0, target: flour(.wheat, .wholeGrain)))

        #expect(applied.adjustedLiquidName == "Wasser")
        #expect(applied.recipe.components[0].ingredients[1].weight == 100)
        #expect(applied.recipe.components[0].ingredients[2].weight == 390)
    }

    @Test("A line that is not a flour cannot be swapped")
    func applyRejectsNonFlour() {
        #expect(FlourSubstitution.apply(to: recipe(), componentIndex: 0, ingredientIndex: 1, target: flour(.spelt, .type(630))) == nil)
    }

    @Test("The rye share counts rye against all recognised flour")
    func ryeShare() throws {
        let applied = try #require(FlourSubstitution.apply(to: recipe(), componentIndex: 0, ingredientIndex: 0, target: flour(.rye, .type(1150))))
        #expect(FlourSubstitution.ryeShare(in: applied.recipe) == 1)
        #expect(FlourSubstitution.ryeShare(in: recipe()) == 0)
    }

    @Test("The original is left untouched")
    func originalUntouched() throws {
        let original = recipe()
        _ = try #require(FlourSubstitution.apply(to: original, componentIndex: 0, ingredientIndex: 0, target: flour(.spelt, .type(630))))
        #expect(original == recipe())
    }
}
