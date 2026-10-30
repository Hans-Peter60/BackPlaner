//
//  StarterFeedingRatioTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Starter feeding ratio derived from a recipe's ingredients")
struct StarterFeedingRatioTests {

    private typealias Component = DoughComposition.Component
    private typealias Ingredient = DoughComposition.Ingredient

    @Test("A 1:1:1 starter recipe reduces to the smallest whole-number ratio")
    func oneOneOne() throws {
        let ratio = try #require(StarterFeedingRatio.ratio(components: [
            Component(name: "Anstellgut", ingredients: [
                Ingredient(name: "Anstellgut", grams: 20),
                Ingredient(name: "Weizenmehl 550", grams: 20),
                Ingredient(name: "Wasser", grams: 20)
            ])
        ]))

        #expect(ratio == StarterFeedingRatio.Ratio(starter: 1, flour: 1, water: 1))
    }

    @Test("A 1:5:5 feeding reduces correctly")
    func oneFiveFive() throws {
        let ratio = try #require(StarterFeedingRatio.ratio(components: [
            Component(name: "Anstellgut", ingredients: [
                Ingredient(name: "Anstellgut", grams: 20),
                Ingredient(name: "Roggenmehl 1150", grams: 100),
                Ingredient(name: "Wasser", grams: 100)
            ])
        ]))

        #expect(ratio == StarterFeedingRatio.Ratio(starter: 1, flour: 5, water: 5))
    }

    @Test("Ingredients across several components still contribute to the ratio")
    func acrossComponents() throws {
        let ratio = try #require(StarterFeedingRatio.ratio(components: [
            Component(name: "Anstellgut", ingredients: [
                Ingredient(name: "Anstellgut", grams: 10)
            ]),
            Component(name: "Fütterung", ingredients: [
                Ingredient(name: "Weizenmehl 1050", grams: 40),
                Ingredient(name: "Wasser", grams: 40)
            ])
        ]))

        #expect(ratio == StarterFeedingRatio.Ratio(starter: 1, flour: 4, water: 4))
    }

    @Test("Missing starter, flour or water gives no ratio")
    func missingPart() {
        #expect(StarterFeedingRatio.ratio(components: [
            Component(name: "Hauptteig", ingredients: [
                Ingredient(name: "Weizenmehl 550", grams: 500),
                Ingredient(name: "Wasser", grams: 340)
            ])
        ]) == nil)
    }

    @Test("An empty recipe gives no ratio")
    func empty() {
        #expect(StarterFeedingRatio.ratio(components: []) == nil)
    }
}
