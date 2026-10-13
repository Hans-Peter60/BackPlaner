//
//  StarterYieldAdjustmentTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Starter TA adjustment: recognition, arithmetic, applying to a recipe")
struct StarterYieldAdjustmentTests {

    private let yields = DoughComposition.StarterYields(sourdough: 200, lievitoMadre: 150)

    // MARK: Arithmetic

    @Test("More of a softer starter carries the same flour; the extra water comes off the dough")
    func softerStarter() {
        // 100 g at TA 150 = 66.7 g flour + 33.3 g water. The same flour at
        // TA 210 weighs 140 g and brings 73.3 g water: 40 g more.
        #expect(StarterYieldAdjustment.starterGrams(grams: 100, from: 150, to: 210) == 140)
        #expect(StarterYieldAdjustment.waterDelta(grams: 100, from: 150, to: 210) == -40)
    }

    @Test("Less of a firmer starter; the missing water goes into the dough")
    func firmerStarter() {
        #expect(StarterYieldAdjustment.starterGrams(grams: 100, from: 200, to: 150) == 75)
        #expect(StarterYieldAdjustment.waterDelta(grams: 100, from: 200, to: 150) == 25)
    }

    @Test("The same TA changes nothing")
    func identity() {
        #expect(StarterYieldAdjustment.starterGrams(grams: 100, from: 200, to: 200) == 100)
        #expect(StarterYieldAdjustment.waterDelta(grams: 100, from: 200, to: 200) == 0)
        #expect(StarterYieldAdjustment.hints(from: 200, to: 200, yieldSource: .name).isEmpty)
    }

    // MARK: Naming

    @Test("The TA is written into the line", arguments: [
        ("Anstellgut TA 150",        "Anstellgut TA 210"),
        ("Anstellgut (TA150)",       "Anstellgut (TA 210)"),
        ("Anstellgut TA: 150, aktiv", "Anstellgut TA 210, aktiv"),
        ("Starter 50 % Hydration",   "Starter 110 % Hydration"),
        ("Anstellgut",               "Anstellgut (TA 210)")
    ])
    func renamed(name: String, expected: String) {
        #expect(StarterYieldAdjustment.renamed(name, toYield: 210) == expected)
    }

    // MARK: Recognition

    private func recognize(_ name: String, grams: Double = 100, componentNames: [String] = ["Hauptteig"]) -> StarterYieldAdjustment.Source? {
        StarterYieldAdjustment.recognize(name: name, grams: grams, weight: grams, numerator: 0, denominator: 0,
                                         componentNames: componentNames, yields: yields)
    }

    @Test("A starter with its TA in the name is read from the name")
    func recognizesStatedYield() throws {
        let source = try #require(recognize("Anstellgut TA 150"))
        #expect(source.kind == .sourdough)
        #expect(source.doughYield == 150)
        #expect(source.yieldSource == .name)
        #expect(abs(source.flour - 66.667) < 0.01)
    }

    @Test("A starter without a TA takes the one from the settings")
    func recognizesSettingYield() throws {
        let source = try #require(recognize("Anstellgut"))
        #expect(source.doughYield == 200)
        #expect(source.yieldSource == .setting)

        let madre = try #require(recognize("Lievito Madre"))
        #expect(madre.kind == .lievitoMadre)
        #expect(madre.doughYield == 150)
    }

    @Test("Lines that are not a starter one keeps are not offered", arguments: [
        "Wasser", "Weizenmehl 550", "Poolish", "Biga", "Sauerteigpulver"
    ])
    func rejectsOthers(name: String) {
        #expect(recognize(name) == nil)
    }

    @Test("A line standing for a component of the recipe is that component's dough, not a starter")
    func rejectsComponentReference() {
        #expect(recognize("Sauerteig", componentNames: ["Sauerteig", "Hauptteig"]) == nil)
        #expect(recognize("gesamter Sauerteig", grams: 0, componentNames: ["Sauerteig", "Hauptteig"]) == nil)
        // Without such a component the same line is the starter from the jar.
        #expect(recognize("Sauerteig", componentNames: ["Hauptteig"]) != nil)
    }

    // MARK: Hints

    @Test("Softer, firmer and big steps bring their advice; an assumed TA is pointed out")
    func hints() {
        #expect(StarterYieldAdjustment.hints(from: 150, to: 210, yieldSource: .name) == [.softer, .bigStep])
        #expect(StarterYieldAdjustment.hints(from: 210, to: 200, yieldSource: .name) == [.firmer])
        #expect(StarterYieldAdjustment.hints(from: 200, to: 220, yieldSource: .setting) == [.assumedYield, .softer])
    }

    // MARK: Applying to a recipe

    private func recipe(water: Double = 340) -> RecipeExportData {
        RecipeExportData(
            name: "Landbrot", summary: "", urlLink: nil, prepTime: 0, totalWeight: 950,
            tags: [], rating: 0, recurrenceIntervalDays: 0, image: nil,
            components: [
                RecipeExportComponent(name: "Hauptteig", number: 0, ingredients: [
                    RecipeExportIngredient(name: "Anstellgut TA 150", number: 0, unit: "g", weight: 100,   normWeight: 100,   num: 0, denom: 0),
                    RecipeExportIngredient(name: "Weizenmehl 550",    number: 1, unit: "g", weight: 500,   normWeight: 500,   num: 0, denom: 0),
                    RecipeExportIngredient(name: "Wasser",            number: 2, unit: "g", weight: water, normWeight: water, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Salz",              number: 3, unit: "g", weight: 10,    normWeight: 10,    num: 0, denom: 0)
                ])
            ],
            instructions: []
        )
    }

    @Test("The starter line is rescaled and renamed, the component's water moved the other way")
    func applyRescalesStarterAndWater() throws {
        let applied = try #require(StarterYieldAdjustment.apply(to: recipe(), componentIndex: 0, ingredientIndex: 0, targetYield: 210, yields: yields))

        #expect(applied.starterGrams == 140)
        #expect(applied.waterDelta == -40)
        #expect(applied.waterAdjusted)
        #expect(applied.adjustedLiquidName == "Wasser")
        #expect(applied.waterShortfall == 0)

        let ingredients = applied.recipe.components[0].ingredients
        #expect(ingredients[0].name == "Anstellgut TA 210")
        #expect(ingredients[0].weight == 140)
        #expect(ingredients[0].normWeight == 140)
        #expect(ingredients[2].weight == 300)
        #expect(ingredients[2].normWeight == 300)
        #expect(ingredients[1].weight == 500)
        // Starter and water trade places, the dough weighs the same.
        #expect(applied.recipe.totalWeight == 950)
        #expect(applied.recipe.name == "Landbrot – TA 210")
    }

    @Test("Flour and water of the whole dough stay where the recipe put them")
    func doughYieldIsUnchanged() throws {
        let before = try #require(DoughComposition.compute(DoughComposition.components(of: recipe()), starterYields: yields))
        let applied = try #require(StarterYieldAdjustment.apply(to: recipe(), componentIndex: 0, ingredientIndex: 0, targetYield: 210, yields: yields))
        let after = try #require(DoughComposition.compute(DoughComposition.components(of: applied.recipe), starterYields: yields))

        #expect(abs(before.flour - after.flour) < 0.01)
        #expect(abs(before.water - after.water) < 0.01)
        #expect(abs(before.doughYield - after.doughYield) < 0.01)
    }

    @Test("A firmer starter puts water back into the dough")
    func applyFirmer() throws {
        let applied = try #require(StarterYieldAdjustment.apply(to: recipe(), componentIndex: 0, ingredientIndex: 0, targetYield: 120, yields: yields))

        #expect(applied.starterGrams == 80)
        #expect(applied.waterDelta == 20)
        #expect(applied.recipe.components[0].ingredients[2].weight == 360)
        #expect(applied.recipe.totalWeight == 950)
    }

    @Test("Water never drops below zero; what does not fit is reported")
    func applyWithTooLittleWater() throws {
        let applied = try #require(StarterYieldAdjustment.apply(to: recipe(water: 25), componentIndex: 0, ingredientIndex: 0, targetYield: 210, yields: yields))

        #expect(applied.waterDelta == -40)
        #expect(applied.waterShortfall == 15)
        #expect(applied.recipe.components[0].ingredients[2].weight == 0)
        // 40 g more starter, only 25 g less water.
        #expect(applied.recipe.totalWeight == 965)
    }

    @Test("Without a liquid line the starter is rescaled and the rest is left to the baker")
    func applyWithoutWater() throws {
        var dry = recipe()
        dry.components[0].ingredients.remove(at: 2)

        let applied = try #require(StarterYieldAdjustment.apply(to: dry, componentIndex: 0, ingredientIndex: 0, targetYield: 210, yields: yields))

        #expect(!applied.waterAdjusted)
        #expect(applied.waterDelta == -40)
        #expect(applied.recipe.totalWeight == 990)
    }

    @Test("A line that is not a starter cannot be adjusted")
    func applyRejectsNonStarter() {
        #expect(StarterYieldAdjustment.apply(to: recipe(), componentIndex: 0, ingredientIndex: 1, targetYield: 210, yields: yields) == nil)
    }
}

@Suite("Starter TA presets")
struct StarterYieldPresetTests {

    @Test("Presets are read from a comma-separated list, cleaned, and sorted")
    func parsing() {
        #expect(AppSettings.starterDoughYieldPresets(from: "190, 210,220") == [190, 210, 220])
        #expect(AppSettings.starterDoughYieldPresets(from: "220; 190 abc 50 210 210") == [190, 210, 220])
        #expect(AppSettings.starterDoughYieldPresets(from: "TA 190 / TA 210") == [190, 210])
    }

    @Test("An empty or useless list falls back to the defaults")
    func fallback() {
        #expect(AppSettings.starterDoughYieldPresets(from: "") == AppSettings.starterDoughYieldPresets(from: AppSettings.defaultStarterDoughYieldPresets))
        #expect(AppSettings.starterDoughYieldPresets(from: "50, 999").isEmpty == false)
    }
}
