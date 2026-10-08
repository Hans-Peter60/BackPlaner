//
//  DoughCompositionTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Dough yield and hydration over all components")
struct DoughCompositionTests {

    private typealias Component = DoughComposition.Component
    private typealias Ingredient = DoughComposition.Ingredient

    private let yields = DoughComposition.StarterYields.standard

    /// A whole-product row as the import writes it: no weight, 1/1.
    private func wholeProduct(_ name: String) -> Ingredient {
        Ingredient(name: name, grams: 1, weight: 0, numerator: 1, denominator: 1)
    }

    // MARK: Plain doughs

    @Test("Flour and water of one component give the dough yield")
    func singleComponent() throws {
        let result = try #require(DoughComposition.compute([
            Component(name: "Hauptteig", ingredients: [
                Ingredient(name: "Weizenmehl 550", grams: 500),
                Ingredient(name: "Wasser", grams: 340),
                Ingredient(name: "Salz", grams: 10),
                Ingredient(name: "Hefe", grams: 5)
            ])
        ], starterYields: yields))

        #expect(result.flour == 500)
        #expect(result.water == 340)
        #expect(result.doughYield == 168)
        #expect(result.hydration == 68)
        #expect(result.uncounted.isEmpty)
    }

    @Test("A recipe without flour has no dough yield")
    func noFlour() {
        #expect(DoughComposition.compute([
            Component(name: "Brühstück", ingredients: [
                Ingredient(name: "Leinsamen", grams: 50),
                Ingredient(name: "Wasser", grams: 100)
            ])
        ], starterYields: yields) == nil)
    }

    @Test("Milk, beer and wine count as liquid in full, their powders do not")
    func liquids() {
        #expect(DoughComposition.classify("Milch 3,5 %") == .water)
        #expect(DoughComposition.classify("Buttermilch") == .water)
        #expect(DoughComposition.classify("Bier") == .water)
        #expect(DoughComposition.classify("Weißwein") == .water)
        #expect(DoughComposition.classify("Vin blanc") == .water)
        #expect(DoughComposition.classify("Hefewasser") == .water)
        #expect(DoughComposition.classify("Milchpulver") == .other)
        #expect(DoughComposition.classify("Weinstein") == .other)
        #expect(DoughComposition.classify("Weinsteinbackpulver") == .other)
    }

    @Test("Flours, meals and semolina count as flour; seeds and flakes do not")
    func flours() {
        #expect(DoughComposition.classify("Roggenvollkornmehl") == .flour)
        #expect(DoughComposition.classify("Roggenschrot grob") == .flour)
        #expect(DoughComposition.classify("Hartweizengrieß") == .flour)
        #expect(DoughComposition.classify("Dunst") == .flour)
        #expect(DoughComposition.classify("farine T65") == .flour)
        // Old bread in a scald is flour that was baked once already.
        #expect(DoughComposition.classify("Altbrot (geröstet, gemahlen)") == .flour)
        #expect(DoughComposition.classify("Semmelbrösel") == .flour)
        #expect(DoughComposition.classify("Haferflocken") == .other)
        #expect(DoughComposition.classify("Sonnenblumenkerne") == .other)
        #expect(DoughComposition.classify("Leinsamenschrot") == .other)
        #expect(DoughComposition.classify("Mandelmehl") == .other)
        #expect(DoughComposition.classify("Sauerteigpulver") == .other)
    }

    // MARK: Starters

    @Test("Anstellgut is split by the TA in its name")
    func starterYieldFromName() throws {
        let result = try #require(DoughComposition.compute([
            Component(name: "Sauerteig", ingredients: [
                Ingredient(name: "Roggenmehl 1150", grams: 100),
                Ingredient(name: "Wasser", grams: 100),
                Ingredient(name: "Anstellgut (TA 200, weich)", grams: 20)
            ])
        ], starterYields: yields))

        #expect(result.flour == 110)
        #expect(result.water == 110)
        #expect(result.doughYield == 200)

        let starter = try #require(result.starters.first)
        #expect(starter.doughYield == 200)
        #expect(starter.source == .name)
        #expect(starter.flour == 10)
        #expect(starter.water == 10)
    }

    @Test("A hydration percentage in the name is read as a TA as well")
    func starterYieldFromHydration() {
        #expect(DoughComposition.doughYield(in: "Starter (100 % Hydration)") == 200)
        #expect(DoughComposition.doughYield(in: "Levain 80% hydratation") == 180)
        #expect(DoughComposition.doughYield(in: "Anstellgut TA150") == 150)
        #expect(DoughComposition.doughYield(in: "Anstellgut") == nil)
        // A type number is not a TA.
        #expect(DoughComposition.doughYield(in: "Weizenmehl Type 550") == nil)
    }

    @Test("Without a TA in the name the setting for the starter's kind applies")
    func starterYieldFromSetting() throws {
        let custom = DoughComposition.StarterYields(sourdough: 180, lievitoMadre: 150)
        let result = try #require(DoughComposition.compute([
            Component(name: "Teig", ingredients: [
                Ingredient(name: "Weizenmehl", grams: 400),
                Ingredient(name: "Wasser", grams: 260),
                Ingredient(name: "Anstellgut", grams: 90),
                Ingredient(name: "Lievito Madre", grams: 150)
            ])
        ], starterYields: custom))

        let starters = result.starters
        #expect(starters.count == 2)
        #expect(starters[0].kind == .sourdough)
        #expect(starters[0].doughYield == 180)
        #expect(starters[0].source == .setting)
        #expect(starters[0].flour == 50)
        #expect(starters[0].water == 40)
        #expect(starters[1].kind == .lievitoMadre)
        #expect(starters[1].doughYield == 150)
        #expect(starters[1].flour == 100)
        #expect(starters[1].water == 50)

        #expect(result.flour == 550)
        #expect(result.water == 350)
    }

    @Test("Biga, poolish and pâte fermentée have a TA by definition")
    func definedStarters() {
        #expect(DoughComposition.classify("Biga") == .starter(.biga))
        #expect(DoughComposition.classify("Poolish") == .starter(.poolish))
        #expect(DoughComposition.classify("Pâte fermentée") == .starter(.pateFermentee))
        #expect(DoughComposition.classify("ASG") == .starter(.sourdough))
        #expect(DoughComposition.doughYield(of: .biga, in: "Biga", yields: yields) == (150, .definition))
        #expect(DoughComposition.doughYield(of: .poolish, in: "Poolish", yields: yields) == (200, .definition))
        #expect(DoughComposition.doughYield(of: .pateFermentee, in: "Pâte fermentée", yields: yields) == (165, .definition))
    }

    // MARK: Components that use other components

    @Test("A sourdough used whole in the main dough is counted once")
    func wholeComponentUse() throws {
        let result = try #require(DoughComposition.compute([
            Component(name: "Sauerteig", ingredients: [
                Ingredient(name: "Roggenmehl 1150", grams: 200),
                Ingredient(name: "Wasser", grams: 200),
                Ingredient(name: "Anstellgut", grams: 20)
            ]),
            Component(name: "Hauptteig", ingredients: [
                wholeProduct("gesamter Sauerteig"),
                Ingredient(name: "Roggenmehl 1150", grams: 300),
                Ingredient(name: "Wasser", grams: 150),
                Ingredient(name: "Salz", grams: 10)
            ])
        ], starterYields: yields))

        #expect(result.flour == 510)
        #expect(result.water == 360)
        #expect(result.components.count == 2)
        #expect(result.components[0].doughYield == 200)
        #expect(result.components[1].doughYield == 150)
    }

    @Test("Components that never name each other are summed as well")
    func independentComponents() throws {
        let result = try #require(DoughComposition.compute([
            Component(name: "Vorteig", ingredients: [
                Ingredient(name: "Weizenmehl", grams: 100),
                Ingredient(name: "Wasser", grams: 100)
            ]),
            Component(name: "Hauptteig", ingredients: [
                Ingredient(name: "Weizenmehl", grams: 400),
                Ingredient(name: "Wasser", grams: 220)
            ])
        ], starterYields: yields))

        #expect(result.flour == 500)
        #expect(result.water == 320)
    }

    @Test("A partial use of a component is scaled to the amount taken")
    func partialComponentUse() throws {
        let result = try #require(DoughComposition.compute([
            Component(name: "Sauerteig", ingredients: [
                Ingredient(name: "Roggenmehl", grams: 150),
                Ingredient(name: "Wasser", grams: 150)
            ]),
            Component(name: "Hauptteig", ingredients: [
                Ingredient(name: "Sauerteig", grams: 200),
                Ingredient(name: "Roggenmehl", grams: 300),
                Ingredient(name: "Wasser", grams: 200)
            ])
        ], starterYields: yields))

        // Two thirds of the sourdough: 100 g flour and 100 g water.
        #expect(abs(result.flour - 400) < 0.001)
        #expect(abs(result.water - 300) < 0.001)
        // Sourdough named without a component of that name would be a
        // starter; with one it is that component.
        #expect(result.starters.isEmpty)
    }

    @Test("A chain of stages is followed to the main dough")
    func stagedSourdough() throws {
        let result = try #require(DoughComposition.compute([
            Component(name: "Sauerteig Stufe 1", ingredients: [
                Ingredient(name: "Roggenmehl", grams: 50),
                Ingredient(name: "Wasser", grams: 50),
                Ingredient(name: "Anstellgut", grams: 10)
            ]),
            Component(name: "Sauerteig Stufe 2", ingredients: [
                wholeProduct("gesamte Sauerteigstufe 1"),
                Ingredient(name: "Roggenmehl", grams: 150),
                Ingredient(name: "Wasser", grams: 150)
            ]),
            Component(name: "Hauptteig", ingredients: [
                wholeProduct("gesamte Sauerteigstufe 2"),
                Ingredient(name: "Roggenmehl", grams: 300),
                Ingredient(name: "Wasser", grams: 200)
            ])
        ], starterYields: yields))

        #expect(result.flour == 505)
        #expect(result.water == 405)
    }

    // MARK: What is left out

    @Test("Heavier uncounted ingredients are listed, salt and yeast are not")
    func uncountedIngredients() throws {
        let result = try #require(DoughComposition.compute([
            Component(name: "Teig", ingredients: [
                Ingredient(name: "Weizenmehl", grams: 500),
                Ingredient(name: "Wasser", grams: 300),
                Ingredient(name: "Sonnenblumenkerne", grams: 120),
                Ingredient(name: "Butter", grams: 40),
                Ingredient(name: "Salz", grams: 12),
                Ingredient(name: "Hefe", grams: 20),
                Ingredient(name: "Kümmel", grams: 3)
            ])
        ], starterYields: yields))

        #expect(result.uncounted.map(\.name) == ["Sonnenblumenkerne", "Butter"])
    }
}
