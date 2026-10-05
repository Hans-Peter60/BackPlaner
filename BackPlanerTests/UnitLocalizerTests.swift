//
//  UnitLocalizerTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Units in the app's language and from imports")
@MainActor
struct UnitLocalizerTests {

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func ingredient(_ amount: Double, _ unit: String) -> IngredientFB {
        let ingredient = IngredientFB()
        ingredient.weight = amount
        ingredient.unit = unit
        return ingredient
    }

    // MARK: Recognition

    @Test("Spellings from all three languages map to the bundled abbreviation",
          arguments: [
            ("tsp", "TL"), ("Teaspoons", "TL"), ("c. à c.", "TL"), ("cuillère à café", "TL"), ("TL", "TL"),
            ("tbsp", "EL"), ("C. à s.", "EL"), ("Esslöffel", "EL"),
            ("cups", "Tas"), ("tasse", "Tas"),
            ("pinch", "Pr"), ("pincées", "Pr"), ("Prise", "Pr"),
            ("grams", "g"), ("gr.", "g"), ("Gramm", "g"),
            ("pcs", "St"), ("Stk.", "St"), ("pièces", "St"),
            ("eggs", "ei"), ("litres", "l"), ("sachet", "Pck"),
          ])
    func recognisesSpellings(spelling: String, abbreviation: String) {
        #expect(UnitLocalizer.canonicalAbbreviation(for: spelling) == abbreviation)
    }

    @Test("Unknown and empty units are not guessed")
    func leavesUnknownUnits() {
        #expect(UnitLocalizer.canonicalAbbreviation(for: "Würfel") == nil)
        #expect(UnitLocalizer.canonicalAbbreviation(for: "") == nil)
        #expect(UnitLocalizer.canonicalAbbreviation(for: "cc") == nil)
    }

    // MARK: Imports

    @Test("An import gets the bundled unit, so its weight can be worked out")
    func normalisesImportedUnits() {
        let salt = ingredient(2, "tsp")
        UnitLocalizer.normalize(salt)
        #expect(salt.unit == "TL")

        let weightBefore = CalcIngredientWeight().calcIngredientWeight(weight: 2, unit: "tsp", name: "Salz", num: 0, denom: 0)
        #expect(weightBefore == 10, "2 tsp should count as 2 × 5 ml, not as 2 g")
    }

    @Test("Pounds and ounces become grams, fractions included")
    func convertsImperialWeights() {
        let flour = ingredient(1, "lb")
        UnitLocalizer.normalize(flour)
        #expect(flour.unit == "g")
        #expect(flour.weight == 454)

        let butter = IngredientFB()
        butter.unit = "oz"
        butter.num = 1
        butter.denom = 2
        UnitLocalizer.normalize(butter)
        #expect(butter.unit == "g")
        #expect(butter.weight == 14)
        #expect(butter.num == 0 && butter.denom == 0)
    }

    @Test("Units the app does not know stay as they came")
    func keepsUnknownImportedUnits() {
        let yeast = ingredient(1, "Würfel")
        UnitLocalizer.normalize(yeast)
        #expect(yeast.unit == "Würfel")
    }

    // MARK: Display

    @Test("German shows the stored unit unchanged")
    func germanIsUnchanged() throws {
        let german = try bundle("de")
        #expect(UnitLocalizer.display("TL", amount: 3, language: "de", bundle: german) == "TL")
        #expect(UnitLocalizer.display("Tasse", amount: 2, language: "de", bundle: german) == "Tasse")
        #expect(UnitLocalizer.display("TL", style: .name, language: "de", bundle: german) == "Teelöffel")
    }

    @Test("English and French show their own abbreviations, with plurals")
    func translatesAbbreviations() throws {
        let english = try bundle("en")
        let french = try bundle("fr")

        #expect(UnitLocalizer.display("TL", amount: 2, language: "en", bundle: english) == "tsp")
        #expect(UnitLocalizer.display("Tas", amount: 1, language: "en", bundle: english) == "cup")
        #expect(UnitLocalizer.display("Tas", amount: 2, language: "en", bundle: english) == "cups")
        #expect(UnitLocalizer.display("Pr", amount: 1.5, language: "fr", bundle: french) == "pincée")
        #expect(UnitLocalizer.display("Pr", amount: 2, language: "fr", bundle: french) == "pincées")
        #expect(UnitLocalizer.display("EL", amount: 3, language: "fr", bundle: french) == "c. à s.")
        // Older recipes that store the German name are translated as well.
        #expect(UnitLocalizer.display("Gramm", amount: 500, language: "en", bundle: english) == "g")
    }

    @Test("Spelled-out names for reading aloud and for the picker")
    func translatesNames() throws {
        let english = try bundle("en")
        #expect(UnitLocalizer.display("TL", amount: 2, style: .name, language: "en", bundle: english) == "teaspoons")

        let teaspoon = try #require(GlobalVariables.bundledUnitSets.first { $0.abbreviation == "TL" })
        #expect(UnitLocalizer.menuTitle(for: teaspoon, language: "en", bundle: english) == "tsp - teaspoon")
    }

    @Test("Custom and free-text units are shown as written")
    func keepsUnknownUnitsOnScreen() throws {
        let english = try bundle("en")
        #expect(UnitLocalizer.display("Würfel", amount: 2, language: "en", bundle: english) == "Würfel")
    }
}
