//
//  RecipeFacetsTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("What a recipe is like, for the list's filters")
struct RecipeFacetsTests {

    private func step(_ text: String, _ step: Double, _ duration: Int, start: Int = 0, bake: Bool = false) -> RecipeExportInstruction {
        RecipeExportInstruction(instruction: text, step: step, duration: duration, startTime: start, bakeFlag: bake)
    }

    private func recipe(ingredients: [(String, Double)] = [("Weizenmehl 550", 500), ("Wasser", 340), ("Salz", 10), ("Frischhefe", 5)],
                        components: [(String, [(String, Double)])]? = nil,
                        steps: [RecipeExportInstruction]) -> RecipeExportData {
        let groups = components ?? [("Hauptteig", ingredients)]
        return RecipeExportData(
            name: "Brot", summary: "", urlLink: nil, prepTime: 0, totalWeight: 0, tags: [], rating: 0,
            recurrenceIntervalDays: 0, image: nil,
            components: groups.enumerated().map { index, group in
                RecipeExportComponent(name: group.0, number: index + 1, ingredients: group.1.enumerated().map { i, item in
                    RecipeExportIngredient(name: item.0, number: i + 1, unit: "g", weight: item.1, normWeight: item.1, num: 0, denom: 0)
                })
            },
            instructions: steps)
    }

    @Test("A cold-retard loaf: set up in the evening, only shape and bake in the morning")
    func eveningToMorning() {
        let facets = RecipeFacets.compute(recipe(steps: [
            step("Teig kneten", 1, 15, start: 0),
            step("Teig 2 Stunden gehen lassen", 2, 120, start: 15),
            step("Teig formen und in den Gärkorb legen", 3, 15, start: 135),
            step("Über Nacht im Kühlschrank reifen lassen", 4, 720, start: 150),
            step("Backofen mit Backstein auf 250 °C vorheizen", 5, 45, start: 825),
            step("Brot backen", 6, 45, start: 870, bake: true),
        ]), starterYields: .standard)
        #expect(facets.totalMinutes == 915)
        #expect(facets.duration == .overnight)
        #expect(facets.dayFlows == [.eveningToMorning])
        #expect(facets.activeMinutes == 30)
        #expect(facets.longestRestMinutes == 720)
        #expect(facets.equipment == [.bakingStone, .proofingBasket])
        #expect(facets.leavening == .yeast)
        #expect(facets.isLowWork)

        // One more minute of kneading and it is no longer little work.
        var busier = RecipeFacets.compute(recipe(steps: [
            step("Teig kneten", 1, 16, start: 0),
            step("Teig 2 Stunden gehen lassen", 2, 120, start: 16),
            step("Teig formen und in den Gärkorb legen", 3, 15, start: 136),
            step("Brot backen", 4, 45, start: 151, bake: true),
        ]), starterYields: .standard)
        #expect(busier.activeMinutes == 31)
        #expect(!busier.isLowWork)
        busier = RecipeFacets.compute(recipe(steps: []), starterYields: .standard)
        #expect(!busier.isLowWork)
    }

    @Test("A long final proof after the fridge is not a morning bake")
    func fridgeThenLongProof() {
        let facets = RecipeFacets.compute(recipe(steps: [
            step("Teig kneten", 1, 15, start: 0),
            step("Über Nacht im Kühlschrank reifen lassen", 2, 720, start: 15),
            step("Teig formen", 3, 15, start: 735),
            step("2 Stunden Stückgare", 4, 120, start: 750),
            step("Brot backen", 5, 45, start: 870, bake: true),
        ]), starterYields: .standard)
        #expect(!facets.dayFlows.contains(.eveningToMorning))
        #expect(facets.dayFlows.isEmpty)
    }

    @Test("A same-day bread has no six-hour rest; a two-hour one is quick as well")
    func sameDayAndQuick() {
        let sameDay = RecipeFacets.compute(recipe(steps: [
            step("Teig kneten", 1, 15, start: 0),
            step("Teig 3 Stunden gehen lassen", 2, 180, start: 15),
            step("Teig formen", 3, 10, start: 195),
            step("1 Stunde Stückgare", 4, 60, start: 205),
            step("Brot backen", 5, 50, start: 265, bake: true),
        ]), starterYields: .standard)
        #expect(sameDay.dayFlows == [.sameDay])
        #expect(sameDay.duration == .halfDay)

        let quick = RecipeFacets.compute(recipe(steps: [
            step("Teig kneten", 1, 10, start: 0),
            step("30 Minuten ruhen lassen", 2, 30, start: 10),
            step("Fladen backen", 3, 20, start: 40, bake: true),
        ]), starterYields: .standard)
        #expect(quick.dayFlows == [.quick, .sameDay])
        #expect(quick.duration == .short)
    }

    @Test("Steps without start times run one after the other")
    func sequentialFallback() {
        let facets = RecipeFacets.compute(recipe(steps: [
            step("Teig kneten", 1, 10),
            step("Teig 8 Stunden ruhen lassen", 2, 480),
            step("Brot backen", 3, 40, bake: true),
        ]), starterYields: .standard)
        #expect(facets.totalMinutes == 530)
        #expect(facets.longestRestMinutes == 480)
        #expect(facets.dayFlows == [.eveningToMorning])
    }

    @Test("What raises the dough: sourdough, lievito madre, yeast, both, or nothing")
    func leavening() {
        func facets(_ ingredients: [(String, Double)]) -> RecipeFacets.Leavening {
            RecipeFacets.compute(recipe(ingredients: ingredients, steps: [step("Kneten", 1, 10)]), starterYields: .standard).leavening
        }
        #expect(facets([("Roggenmehl 1150", 500), ("Wasser", 400), ("Anstellgut", 50), ("Salz", 10)]) == .sourdough)
        #expect(facets([("Weizenmehl 550", 500), ("Wasser", 300), ("Lievito Madre", 100)]) == .lievitoMadre)
        #expect(facets([("Weizenmehl 550", 500), ("Wasser", 300), ("Trockenhefe", 3)]) == .yeast)
        #expect(facets([("Weizenmehl 550", 500), ("Wasser", 300), ("Poolish", 200)]) == .yeast)
        #expect(facets([("Roggenmehl 1150", 300), ("Weizenmehl 550", 200), ("Sauerteig", 200), ("Frischhefe", 5)]) == .mixed)
        #expect(facets([("Weizenmehl 550", 500), ("Wasser", 300), ("Backpulver", 10)]) == .none)

        // The component's name counts when the starter line is named loosely.
        let named = RecipeFacets.compute(recipe(components: [
            ("Sauerteig", [("Roggenmehl 1150", 200), ("Wasser", 200), ("ASG", 20)]),
            ("Hauptteig", [("Roggenmehl 1150", 300), ("Wasser", 200), ("Salz", 10)]),
        ], steps: [step("Kneten", 1, 10)]), starterYields: .standard)
        #expect(named.leavening == .sourdough)
    }

    @Test("Grain shares and the whole-grain share come from the flours")
    func grains() {
        let facets = RecipeFacets.compute(recipe(ingredients: [
            ("Roggenmehl 1150", 300), ("Roggenvollkornmehl", 100), ("Weizenmehl 550", 100), ("Wasser", 400), ("Salz", 10),
        ], steps: [step("Kneten", 1, 10)]), starterYields: .standard)
        #expect(abs(facets.share(of: .rye) - 0.8) < 0.001)
        #expect(abs(facets.share(of: .wheat) - 0.2) < 0.001)
        #expect(abs(facets.wholeGrainShare - 0.2) < 0.001)
        #expect(facets.mainGrain == .rye)
    }

    @Test("The dough yield bands the hydration; a recipe without flour has none")
    func doughYield() {
        let soft = RecipeFacets.compute(recipe(ingredients: [("Weizenmehl 550", 500), ("Wasser", 400), ("Salz", 10)],
                                               steps: [step("Kneten", 1, 10)]), starterYields: .standard)
        #expect(soft.doughYield == 180)
        #expect(soft.doughYieldBand == .soft)
        let firm = RecipeFacets.compute(recipe(ingredients: [("Weizenmehl 550", 500), ("Wasser", 300), ("Salz", 10)],
                                               steps: [step("Kneten", 1, 10)]), starterYields: .standard)
        #expect(firm.doughYieldBand == .firm)
        let none = RecipeFacets.compute(recipe(ingredients: [("Wasser", 300)], steps: [step("Kneten", 1, 10)]), starterYields: .standard)
        #expect(none.doughYieldBand == nil)
    }

    @Test("Tins, baskets, pots and stones are read from the steps")
    func equipment() {
        let facets = RecipeFacets.compute(recipe(steps: [
            step("Teig in die Kastenform geben", 1, 5),
            step("Im gusseisernen Topf bei 250 °C backen", 2, 45, bake: true),
        ]), starterYields: .standard)
        #expect(facets.equipment == [.loafTin, .dutchOven])
        let english = RecipeFacets.compute(recipe(steps: [step("Proof in a banneton, then bake on the baking steel", 1, 60)]), starterYields: .standard)
        #expect(english.equipment == [.proofingBasket, .bakingStone])
    }
}
