//
//  TotalIngredientsTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Total ingredients over all components")
struct TotalIngredientsTests {

    private func ingredient(_ name: String, _ weight: Double, unit: String = "g") -> TotalIngredientData {
        TotalIngredientData(name: name, unit: unit, weight: weight, numerator: 0, denominator: 0)
    }

    /// A whole-product row as the import writes it: no weight, 1/1.
    private func wholeProduct(_ name: String) -> TotalIngredientData {
        TotalIngredientData(name: name, unit: "", weight: 0, numerator: 1, denominator: 1)
    }

    private func column(_ name: String, _ ingredients: [TotalIngredientData]) -> ComponentColumn {
        ComponentColumn(id: name, name: name, ingredients: ingredients)
    }

    private func lines(_ components: [ComponentColumn]) -> [String] {
        TotalIngredientsView.totalIngredients(of: components).map { "\($0.weight) \($0.unit) \($0.name)" }
    }

    @Test("An ingredient named like its own component is counted once, its reference in the main dough not at all")
    func ownComponentIngredientIsRaw() {
        // The sourdough bread with potatoes: the component "Kartoffeln
        // (gekocht)" cooks 104 g potatoes, the main dough takes them over
        // under the same name. The potatoes were missing from the list.
        let total = lines([
            column("Kartoffeln (gekocht)", [ingredient("Kartoffeln", 104)]),
            column("Hauptteig", [ingredient("Kartoffeln", 104),
                                 ingredient("Weizenmehl 1050", 213),
                                 ingredient("Salz", 12)])
        ])
        #expect(total.contains("104.0 g Kartoffeln"))
        #expect(total.contains("213.0 g Weizenmehl 1050"))
    }

    @Test("A whole component used in the main dough is not counted twice, water and salt never")
    func wholeComponentWaterAndSaltAreLeftOut() {
        let total = lines([
            column("Weizensauerteig", [ingredient("Weizenmehl 1050", 55),
                                       ingredient("Wasser", 27)]),
            column("Hauptteig", [wholeProduct("Gesamter Weizensauerteig"),
                                 ingredient("Weizenmehl 1050", 213),
                                 ingredient("Wasser", 280),
                                 ingredient("Salz", 12)])
        ])
        #expect(total == ["268.0 g Weizenmehl 1050"])
    }

    @Test("The same recipe read in English: total/whole components, water and salt stay out")
    func englishTranslation() {
        let total = lines([
            column("Scald", [ingredient("Seed mixture", 125), ingredient("Water 100 C", 125)]),
            column("Potatoes (cooked)", [ingredient("Potatoes", 104)]),
            column("Wheat sourdough", [ingredient("Wheat flour 1050", 55), ingredient("Water", 27)]),
            column("Main dough", [wholeProduct("Total scald"),
                                  wholeProduct("Whole potatoes (cooked)"),
                                  wholeProduct("Total wheat sourdough"),
                                  ingredient("Wheat flour 1050", 213),
                                  ingredient("Water", 280),
                                  ingredient("Salt", 12)])
        ])
        #expect(total == ["104.0 g Potatoes", "125.0 g Seed mixture", "268.0 g Wheat flour 1050"])
    }

    @Test("The same recipe read in French: tout/toutes les components, eau and sel stay out")
    func frenchTranslation() {
        let total = lines([
            column("Échaudage", [ingredient("Mélange de semences", 125), ingredient("Eau 100 C", 125)]),
            column("Pommes de terre (cuites)", [ingredient("Pommes de terre", 104)]),
            column("Levain de blé", [ingredient("Farine de blé 1050", 55), ingredient("Eau", 27)]),
            column("Pâte principale", [wholeProduct("Tout échaudage"),
                                       wholeProduct("Toutes les pommes de terre (cuites)"),
                                       wholeProduct("Total levain de blé"),
                                       ingredient("Farine de blé 1050", 213),
                                       ingredient("Eau", 280),
                                       ingredient("Sel", 12)])
        ])
        #expect(total == ["268.0 g Farine de blé 1050", "125.0 g Mélange de semences", "104.0 g Pommes de terre"])
    }
}
