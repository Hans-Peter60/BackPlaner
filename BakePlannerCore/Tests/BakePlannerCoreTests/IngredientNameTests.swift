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

    @Test("A temperature in brackets leaves no empty brackets behind")
    func bracketsAreTidied() {
        #expect(IngredientNameNormalizer.displayName("Hefe (zimmerwarm)") == "Hefe")
        #expect(IngredientNameNormalizer.displayName("Milch (lauwarm)") == "Milch")
        #expect(IngredientNameNormalizer.displayName("Ei (Größe M, zimmerwarm)") == "Ei (Größe M)")
        #expect(IngredientNameNormalizer.displayName("Butter (zimmerwarm, weich)") == "Butter (weich)")
    }

    @Test("Brackets without a temperature stay as they are")
    func otherBracketsStay() {
        #expect(IngredientNameNormalizer.displayName("Weizenmehl (Type 550)") == "Weizenmehl (Type 550)")
        #expect(IngredientNameNormalizer.displayName("Kartoffeln (gekocht)") == "Kartoffeln (gekocht)")
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

    @Test("A remark such as (optional) is no part of the name")
    func optionalRemark() {
        #expect(IngredientNameNormalizer.displayName("Hefe (optional)") == "Hefe")
        #expect(IngredientNameNormalizer.displayName("Sesam (nach Belieben)") == "Sesam")
        #expect(IngredientNameNormalizer.displayName("Levure (facultatif)") == "Levure")
        #expect(IngredientNameNormalizer.displayName("Salz (to taste)") == "Salz")
        #expect(IngredientNameNormalizer.comparisonKey("Frischhefe (optional)") == IngredientNameNormalizer.comparisonKey("Hefe"))
        // A bracket that says something else stays.
        #expect(IngredientNameNormalizer.displayName("Ei (Größe M)") == "Ei (Größe M)")
    }

    @Test("Fresh yeast is yeast and eggs are egg, in every language; dry yeast stays apart")
    func synonyms() {
        let key = IngredientNameNormalizer.comparisonKey
        #expect(key("Frischhefe") == key("Hefe"))
        #expect(key("frische Hefe (zimmerwarm)") == key("hefe"))
        #expect(key("Trockenhefe") != key("Hefe"))
        #expect(key("Eier") == key("Ei"))
        #expect(key("Eigelb") != key("Ei"))
        #expect(key("fresh yeast") == key("Yeast"))
        #expect(key("Eggs") == key("egg"))
        #expect(key("Œufs") == key("oeuf"))
        #expect(key("levure fraîche") == key("levure"))
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
