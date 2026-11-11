//
//  BakersFormulaTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A recipe from baker's percentages")
struct BakersFormulaTests {

    private func formula() -> BakersFormula {
        BakersFormula(components: [
            .init(name: "Vorteig", lines: [
                .init(name: "Weizenmehl 550", percent: 20),
                .init(name: "Wasser", percent: 20),
                .init(name: "Frischhefe", percent: 0.2),
            ]),
            .init(name: "Hauptteig", lines: [
                .init(name: "Weizenmehl 550", percent: 60),
                .init(name: "Roggenmehl 1150", percent: 20),
                .init(name: "Wasser", percent: 48),
                .init(name: "Salz", percent: 2),
                .init(name: "", percent: 99),
            ]),
        ])
    }

    @Test("The template is a complete main dough of flour, water, salt and yeast")
    func template() {
        let template = BakersFormula.template(bundle: .main)
        #expect(template.isComplete)
        #expect(template.components.count == 1)
        #expect(template.flourPercent == 100)
        #expect(template.totalPercent == 171)
    }

    @Test("Flours add up over every component; blank lines do not count")
    func sums() {
        let formula = formula()
        #expect(formula.flourPercent == 100)
        #expect(abs(formula.totalPercent - 170.2) < 0.001)
        #expect(formula.lines.count == 7)
        #expect(formula.isComplete)
    }

    @Test("Dough weight and flour weight convert both ways")
    func conversions() {
        let formula = formula()
        #expect(abs(formula.totalFlour(forDoughWeight: 851) - 500) < 0.001)
        #expect(abs(formula.doughWeight(forTotalFlour: 500) - 851) < 0.001)
    }

    @Test("Grams read like a kitchen scale: whole grams from 10 g, tenths below")
    func rounding() {
        #expect(BakersFormula.grams(percent: 68, totalFlour: 500) == 340)
        #expect(BakersFormula.grams(percent: 2, totalFlour: 500) == 10)
        #expect(BakersFormula.grams(percent: 0.7, totalFlour: 500) == 3.5)
        #expect(BakersFormula.grams(percent: 1.8, totalFlour: 512) == 9.2)
        #expect(BakersFormula.grams(percent: 68.3, totalFlour: 512) == 350)
    }

    @Test("What stops the formula: no flour, flour not 100, a share of zero, no lines")
    func issues() {
        var formula = formula()
        formula.components[1].lines[1].percent = 15
        #expect(formula.issues == [.flourNot100(95)])

        formula.components[1].lines[3].percent = 0
        #expect(formula.issues == [.flourNot100(95), .nonPositive("Salz")])

        let noFlour = BakersFormula(components: [.init(name: "Teig", lines: [.init(name: "Wasser", percent: 70)])])
        #expect(noFlour.issues == [.noFlour])

        #expect(BakersFormula(components: [.init(name: "Teig", lines: [.init(name: " ", percent: 100)])]).issues == [.noLines])
    }

    @MainActor
    @Test("The recipe carries every named line in grams and one mixing step per component")
    func recipe() {
        let recipe = formula().makeRecipe(name: " Landbrot ", totalFlour: 500, bundle: .main)
        #expect(recipe.name == "Landbrot")
        #expect(recipe.components.map(\.name) == ["Vorteig", "Hauptteig"])
        #expect(recipe.components[0].ingredients.map(\.weight) == [100, 100, 1])
        #expect(recipe.components[1].ingredients.map(\.name) == ["Weizenmehl 550", "Roggenmehl 1150", "Wasser", "Salz"])
        #expect(recipe.components[1].ingredients.map(\.weight) == [300, 100, 240, 10])
        #expect(recipe.components[1].ingredients.allSatisfy { $0.unit == "g" && $0.normWeight == $0.weight })
        #expect(recipe.totalWeight == 851)
        #expect(recipe.instructions.map(\.instruction) == ["Vorteig herstellen", "Hauptteig herstellen"])
        #expect(recipe.instructions.map(\.componentName) == ["Vorteig", "Hauptteig"])
        #expect(recipe.instructions.map(\.step) == [1, 2])
    }

    @MainActor
    @Test("A component without named lines is left out, a nameless one becomes the main dough")
    func emptyComponents() {
        let formula = BakersFormula(components: [
            .init(name: "Leer", lines: [.init(name: "", percent: 10)]),
            .init(name: "", lines: [.init(name: "Dinkelmehl 630", percent: 100), .init(name: "Wasser", percent: 60)]),
        ])
        let recipe = formula.makeRecipe(name: "Brot", totalFlour: 1000, bundle: .main)
        #expect(recipe.components.map(\.name) == ["Hauptteig"])
        #expect(recipe.instructions.count == 1)
    }
}
