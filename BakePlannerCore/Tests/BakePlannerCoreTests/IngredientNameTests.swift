//
//  IngredientNameTests.swift
//  BakePlannerCoreTests
//
//  Ingredient names without their temperatures, compared regardless of
//  case and accents, and the rows that stand for another component.
//

import Testing
@testable import BakePlannerCore

@Suite("Ingredient names")
struct IngredientNameNormalizerTests {

    @Test("Temperatures are left out of the shown name")
    func temperaturesAreRemoved() {
        #expect(IngredientNameNormalizer.displayName("Wasser (lauwarm, 30 °C)") == "Wasser")
        #expect(IngredientNameNormalizer.displayName("Hefe, zimmerwarm") == "Hefe")
        #expect(IngredientNameNormalizer.displayName("Milch, lauwarm") == "Milch")
        #expect(IngredientNameNormalizer.displayName("Weizenmehl 550") == "Weizenmehl 550")
    }

    @Test("A name that is nothing but a temperature stays as it was")
    func onlyATemperature() {
        #expect(IngredientNameNormalizer.displayName(" lauwarm ") == "lauwarm")
    }

    @Test("Names compare regardless of case, accents and temperature")
    func comparisonKey() {
        #expect(IngredientNameNormalizer.comparisonKey("Crème fraîche")
                == IngredientNameNormalizer.comparisonKey("creme FRAICHE"))
        #expect(IngredientNameNormalizer.comparisonKey("Wasser, kalt")
                == IngredientNameNormalizer.comparisonKey("wasser"))
    }
}

@Suite("Rows that stand for another component")
struct ComponentProductMatcherTests {

    private func match(_ name: String, weight: Double = 0, whole: Bool = true, in components: [String]) -> Int? {
        ComponentProductMatcher.referencedComponent(name: name, weight: weight,
                                                    numerator: whole ? 1 : 0, denominator: whole ? 1 : 0,
                                                    componentNames: components)
    }

    @Test("The whole component, by its name")
    func wholeComponent() {
        #expect(match("gesamter Sauerteig", in: ["Sauerteig", "Hauptteig"]) == 0)
        #expect(match("Total wheat sourdough", in: ["Wheat sourdough", "Main dough"]) == 0)
    }

    @Test("Part of a component, by its exact name and a weight")
    func partOfAComponent() {
        #expect(match("Sauerteig", weight: 200, whole: false, in: ["Sauerteig", "Hauptteig"]) == 0)
    }

    @Test("The stage tells two stages of one sourdough apart")
    func stages() {
        let components = ["Sauerteig Stufe 1", "Sauerteig Stufe 2", "Hauptteig"]
        #expect(match("gesamte Sauerteigstufe 1", in: components) == 0)
        #expect(match("gesamte Sauerteigstufe 2", in: components) == 1)
    }

    @Test("A loose name counts only for the whole product")
    func looseName() {
        #expect(match("gesamter Roggensauerteig", in: ["Sauerteig"]) == 0)
        #expect(match("Roggensauerteig", weight: 100, whole: false, in: ["Sauerteig"]) == nil)
    }

    @Test("A raw ingredient refers to no component")
    func rawIngredient() {
        #expect(match("Weizenmehl 550", weight: 400, whole: false, in: ["Sauerteig", "Hauptteig"]) == nil)
    }
}
