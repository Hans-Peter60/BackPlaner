//
//  DoughPlausibilityTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Pre-fermented flour, salt and yeast in baker's percentages")
struct DoughPlausibilityTests {

    private typealias Component = DoughComposition.Component
    private typealias Ingredient = DoughComposition.Ingredient

    private let yields = DoughComposition.StarterYields.standard
    private let german = Locale(identifier: "de_DE")

    private func wholeProduct(_ name: String) -> Ingredient {
        Ingredient(name: name, grams: 1, weight: 0, numerator: 1, denominator: 1)
    }

    @Test("A sourdough taken over whole: its flour and its starter's flour are pre-fermented")
    func sourdoughTakenOver() throws {
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
                Ingredient(name: "Salz", grams: 10),
                Ingredient(name: "Frischhefe", grams: 5)
            ])
        ], starterYields: yields))

        // 200 g flour plus 10 g in the 20 g of Anstellgut (TA 200), of 510 g.
        #expect(result.prefermentedFlour == 210)
        #expect(abs(result.prefermentedShare - 41.18) < 0.01)
        #expect(result.salt == 10 && abs(result.saltShare - 1.96) < 0.01)
        #expect(result.freshYeast == 5 && result.dryYeast == 0)
        #expect(DoughPlausibility.hints(for: result, locale: german).isEmpty)
    }

    @Test("A soaker taken over ferments nothing; a Vorteig nobody names does")
    func soakerAndLooseVorteig() throws {
        let soaked = try #require(DoughComposition.compute([
            Component(name: "Brühstück", ingredients: [
                Ingredient(name: "Altbrot", grams: 50),
                Ingredient(name: "Wasser", grams: 150)
            ]),
            Component(name: "Hauptteig", ingredients: [
                wholeProduct("gesamtes Brühstück"),
                Ingredient(name: "Weizenmehl 550", grams: 450),
                Ingredient(name: "Wasser", grams: 200)
            ])
        ], starterYields: yields))
        #expect(soaked.prefermentedFlour == 0)

        let loose = try #require(DoughComposition.compute([
            Component(name: "Vorteig", ingredients: [
                Ingredient(name: "Weizenmehl 550", grams: 100),
                Ingredient(name: "Wasser", grams: 100),
                Ingredient(name: "Hefe", grams: 1)
            ]),
            Component(name: "Hauptteig", ingredients: [
                Ingredient(name: "Weizenmehl 550", grams: 400),
                Ingredient(name: "Wasser", grams: 250),
                Ingredient(name: "Salz", grams: 10)
            ])
        ], starterYields: yields))
        #expect(loose.prefermentedFlour == 100)
        #expect(loose.prefermentedShare == 20)
    }

    @Test("A recipe that is nothing but a starter is not pre-fermented against itself")
    func starterAlone() throws {
        let result = try #require(DoughComposition.compute([
            Component(name: "Roggensauer", ingredients: [
                Ingredient(name: "Roggenmehl 1150", grams: 100),
                Ingredient(name: "Wasser", grams: 100),
                Ingredient(name: "Anstellgut", grams: 10)
            ])
        ], starterYields: yields))
        // Only the Anstellgut's own flour.
        #expect(result.prefermentedFlour == 5)
    }

    @Test("Salt and yeast are told apart from their look-alikes")
    func detection() {
        #expect(DoughComposition.isSalt("Meersalz"))
        #expect(DoughComposition.isSalt("Salt"))
        #expect(DoughComposition.isSalt("Sel de Guérande"))
        #expect(!DoughComposition.isSalt("Sellerie"))
        #expect(!DoughComposition.isSalt("Gesalzene Butter"))

        #expect(DoughComposition.yeastKind("Frischhefe") == .fresh)
        #expect(DoughComposition.yeastKind("Hefe") == .fresh)
        #expect(DoughComposition.yeastKind("Trockenhefe") == .dry)
        #expect(DoughComposition.yeastKind("Instant dry yeast") == .dry)
        #expect(DoughComposition.yeastKind("Levure sèche") == .dry)
        #expect(DoughComposition.yeastKind("Levure fraîche") == .fresh)
        #expect(DoughComposition.yeastKind("Levure chimique") == nil)
        #expect(DoughComposition.yeastKind("Hefeflocken") == nil)
        #expect(DoughComposition.yeastKind("Backpulver") == nil)
    }

    @Test("Hints: little salt, much salt, much fresh or dry yeast; nothing for the usual amounts")
    func hints() throws {
        func result(salt: Double, yeast: Ingredient? = nil) throws -> DoughComposition.Result {
            var ingredients = [Ingredient(name: "Weizenmehl 550", grams: 500),
                               Ingredient(name: "Wasser", grams: 350),
                               Ingredient(name: "Salz", grams: salt)]
            if let yeast { ingredients.append(yeast) }
            return try #require(DoughComposition.compute([Component(name: "Teig", ingredients: ingredients)], starterYields: yields))
        }

        let low = DoughPlausibility.hints(for: try result(salt: 6), locale: german)
        #expect(low.map(\.kind) == [.lowSalt])
        // The percent sign hangs on its number with a no-break space.
        #expect(low[0].text == "Wenig Salz: 1,2\u{00A0}% des Mehls, üblich sind 1,8–2,2\u{00A0}%.")

        let high = DoughPlausibility.hints(for: try result(salt: 14), locale: german)
        #expect(high.map(\.kind) == [.highSalt])

        let fresh = DoughPlausibility.hints(for: try result(salt: 10, yeast: Ingredient(name: "Hefe", grams: 20)), locale: german)
        #expect(fresh.map(\.kind) == [.muchFreshYeast])
        #expect(fresh[0].text.hasPrefix("Viel Frischhefe: 4\u{00A0}% des Mehls"))

        let dry = DoughPlausibility.hints(for: try result(salt: 10, yeast: Ingredient(name: "Trockenhefe", grams: 7)), locale: german)
        #expect(dry.map(\.kind) == [.muchDryYeast])

        #expect(DoughPlausibility.hints(for: try result(salt: 10, yeast: Ingredient(name: "Hefe", grams: 5)), locale: german).isEmpty)
        // No salt at all is no hint: some breads are meant that way.
        #expect(DoughPlausibility.hints(for: try result(salt: 0), locale: german).isEmpty)
    }
}
