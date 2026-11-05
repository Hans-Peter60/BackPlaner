//
//  DoughTypeGuessTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The dough type of a recipe, from its flours and seeds")
struct DoughTypeGuessTests {

    private typealias Ingredient = DoughComposition.Ingredient
    private typealias Component = DoughComposition.Component

    private func recipe(_ ingredients: [(String, Double)]) -> [Component] {
        [Component(name: "Hauptteig", ingredients: ingredients.map { Ingredient(name: $0.0, grams: $0.1) })]
    }

    @Test("White wheat and spelt breads are light wheat doughs")
    func lightWheat() {
        #expect(DoughWeightFromTin.doughType(for: recipe([("Weizenmehl 550", 500), ("Wasser", 330), ("Salz", 10), ("Hefe", 5)])) == .lightWheat)
        #expect(DoughWeightFromTin.doughType(for: recipe([("Dinkelmehl 630", 450), ("Weizenmehl 405", 50), ("Milch", 300), ("Butter", 40)])) == .lightWheat)
        // A spoon of rye for flavour does not make a Mischbrot.
        #expect(DoughWeightFromTin.doughType(for: recipe([("Weizenmehl 550", 470), ("Roggenmehl 1150", 30), ("Wasser", 330)])) == .lightWheat)
        // Flour names in the other languages count the same.
        #expect(DoughWeightFromTin.doughType(for: recipe([("Bread flour", 500), ("Water", 350)])) == .lightWheat)
        #expect(DoughWeightFromTin.doughType(for: recipe([("Farine T65", 500), ("Eau", 350)])) == .lightWheat)
    }

    @Test("Wheat and rye in between make a mixed bread")
    func mixed() {
        #expect(DoughWeightFromTin.doughType(for: recipe([("Weizenmehl 1050", 300), ("Roggenmehl 1150", 200), ("Wasser", 350)])) == .mixed)
        #expect(DoughWeightFromTin.doughType(for: recipe([("Weizenmehl 550", 400), ("Roggenmehl 997", 100), ("Wasser", 350)])) == .mixed)
        // Dark wheat alone is no longer a light dough, but not a rye one either.
        #expect(DoughWeightFromTin.doughType(for: recipe([("Weizenmehl 1050", 500), ("Wasser", 350)])) == .mixed)
        // A handful of seeds moves a white bread to the middle.
        #expect(DoughWeightFromTin.doughType(for: recipe([("Weizenmehl 550", 500), ("Sonnenblumenkerne", 40), ("Wasser", 350)])) == .mixed)
    }

    @Test("Rye, wholegrain, coarse meal and seed breads are the dense doughs")
    func ryeWholeGrain() {
        #expect(DoughWeightFromTin.doughType(for: recipe([("Roggenmehl 1150", 350), ("Weizenmehl 1050", 150), ("Wasser", 400)])) == .ryeWholeGrain)
        #expect(DoughWeightFromTin.doughType(for: recipe([("Dinkelvollkornmehl", 500), ("Wasser", 400)])) == .ryeWholeGrain)
        #expect(DoughWeightFromTin.doughType(for: recipe([("Weizenschrot", 300), ("Weizenmehl 550", 200), ("Wasser", 380)])) == .ryeWholeGrain)
        #expect(DoughWeightFromTin.doughType(for: recipe([("Weizenmehl 550", 500), ("Leinsamen", 50), ("Sonnenblumenkerne", 50), ("Wasser", 400)])) == .ryeWholeGrain)
        #expect(DoughWeightFromTin.doughType(for: recipe([("Whole wheat flour", 500), ("Water", 400)])) == .ryeWholeGrain)
        #expect(DoughWeightFromTin.doughType(for: recipe([("Farine de seigle T130", 400), ("Farine T80", 100), ("Eau", 400)])) == .ryeWholeGrain)
    }

    @Test("Flour is counted across components; reference rows and starters are not")
    func acrossComponents() {
        let components = [
            Component(name: "Sauerteig", ingredients: [Ingredient(name: "Roggenmehl 1150", grams: 200), Ingredient(name: "Wasser", grams: 200), Ingredient(name: "Anstellgut", grams: 20)]),
            Component(name: "Hauptteig", ingredients: [Ingredient(name: "gesamter Sauerteig", grams: 420, weight: 0), Ingredient(name: "Weizenmehl 1050", grams: 300), Ingredient(name: "Wasser", grams: 150), Ingredient(name: "Salz", grams: 10)])
        ]
        // 200 g rye of 500 g flour: a Weizenmischbrot, neither light nor rye.
        #expect(DoughWeightFromTin.doughType(for: components) == .mixed)

        // The same with 300 g rye in the sourdough tips over.
        let ryeHeavy = [
            Component(name: "Sauerteig", ingredients: [Ingredient(name: "Roggenmehl 1150", grams: 300), Ingredient(name: "Wasser", grams: 300)]),
            Component(name: "Hauptteig", ingredients: [Ingredient(name: "Weizenmehl 1050", grams: 200), Ingredient(name: "Wasser", grams: 100)])
        ]
        #expect(DoughWeightFromTin.doughType(for: ryeHeavy) == .ryeWholeGrain)
    }

    @Test("Without flour there is nothing to say")
    func noFlour() {
        #expect(DoughWeightFromTin.doughType(for: recipe([("Wasser", 300), ("Salz", 10)])) == nil)
        #expect(DoughWeightFromTin.doughType(for: []) == nil)
        // Nuts and flakes alone are no flour either.
        #expect(DoughWeightFromTin.doughType(for: recipe([("Haferflocken", 300), ("Mandeln", 100)])) == nil)
    }
}
