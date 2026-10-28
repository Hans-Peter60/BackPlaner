//
//  StarterRecipeTests.swift
//  BackPlanerTests
//
//  What makes a recipe a starter being fed rather than a bread: its
//  ingredients give a feeding ratio and its steps never use an oven — or a
//  tag says so. A rhythm plays no part; a bread planned every five days
//  must not be asked for a feeding.
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Telling a starter feeding from a bread")
struct StarterRecipeTests {

    private func component(_ ingredients: [(String, Double)]) -> DoughComposition.Component {
        DoughComposition.Component(name: "Teig", ingredients: ingredients.map {
            DoughComposition.Ingredient(name: $0.0, grams: $0.1)
        })
    }

    private let feedingIngredients = [("Anstellgut", 10.0), ("Roggenmehl", 50.0), ("Wasser", 50.0)]
    private let breadIngredients = [("Anstellgut", 20.0), ("Weizenmehl", 500.0), ("Wasser", 350.0), ("Salz", 10.0)]

    private func isStarter(steps: [String], ingredients: [(String, Double)], tags: [String] = []) -> Bool {
        StarterRecipe.isStarterFeeding(instructions: steps, components: [component(ingredients)], tags: tags)
    }

    @Test("Mix and let ripen, with starter, flour and water: a feeding")
    func feedingIsAStarter() {
        #expect(isStarter(steps: ["Anstellgut, Mehl und Wasser mischen", "Bei 26 °C 12 Stunden reifen lassen"],
                          ingredients: feedingIngredients))
    }

    @Test("The same in English and French")
    func feedingInOtherLanguages() {
        #expect(isStarter(steps: ["Mix starter, flour and water", "Let ripen 12 hours at 26 °C"],
                          ingredients: [("Sourdough starter", 10), ("Rye flour", 50), ("Water", 50)]))
        #expect(isStarter(steps: ["Mélanger le levain, la farine et l’eau", "Laisser pousser 12 heures à 26 °C"],
                          ingredients: [("Levain chef", 10), ("Farine de seigle", 50), ("Eau", 50)]))
    }

    @Test("A sourdough bread bakes, so it is no starter — with or without a rhythm")
    func breadIsNoStarter() {
        #expect(!isStarter(steps: ["Sauerteig ansetzen und reifen lassen", "Hauptteig kneten", "Bei 250 °C backen"],
                           ingredients: breadIngredients))
        // A preheating step or an oven temperature alone gives the oven away too.
        #expect(!isStarter(steps: ["Zutaten mischen", "Backofen auf 250 °C vorheizen", "50 Minuten"],
                           ingredients: breadIngredients))
        #expect(!isStarter(steps: ["Zutaten mischen", "Bei 250 °C 50 Minuten"],
                           ingredients: breadIngredients))
    }

    @Test("Without a feeding ratio nothing is a starter, however it ripens")
    func noRatioNoStarter() {
        // Yeast water: no flour.
        #expect(!isStarter(steps: ["Ansetzen und 5 Tage reifen lassen"],
                           ingredients: [("Wasser", 500), ("Rosinen", 50), ("Honig", 20)]))
        // A soaker: no starter.
        #expect(!isStarter(steps: ["Mischen und über Nacht quellen lassen"],
                           ingredients: [("Roggenschrot", 100), ("Wasser", 100)]))
        #expect(!isStarter(steps: [], ingredients: []))
    }

    /// "Sauerteig" and "Anstellgut" name the same thing. A recipe of
    /// nothing but sourdough, flour and water is a feeding even when a
    /// step mentions the oven or the bake the starter is kept for; it used
    /// to be taken for a bread and read "Nächster Backtermin".
    @Test("Sourdough, flour and water alone are a feeding, whatever the steps mention")
    func sourdoughFlourAndWaterAreAFeeding() {
        let sourdough = [("Sauerteig", 50.0), ("Roggenmehl", 100.0), ("Wasser", 100.0)]
        #expect(isStarter(steps: ["Sauerteig, Mehl und Wasser verrühren", "12 Stunden bei Raumtemperatur reifen lassen"],
                          ingredients: sourdough))
        #expect(isStarter(steps: ["Verrühren", "Bis zum nächsten Backen im Kühlschrank lagern"],
                          ingredients: sourdough))
        #expect(isStarter(steps: ["Zutaten mischen", "Im ausgeschalteten Backofen mit Licht reifen lassen"],
                          ingredients: feedingIngredients))
        // Oven heat does bake something; salt makes it a bread.
        #expect(!isStarter(steps: ["Verrühren", "Bei 230 °C backen"], ingredients: sourdough))
        #expect(!isStarter(steps: ["Verrühren", "Bis zum nächsten Backen im Kühlschrank lagern"],
                           ingredients: sourdough + [("Salz", 4.0)]))
    }

    @Test("A tag settles it when a step heats the oven")
    func tagOverridesTheOvenCheck() {
        let steps = ["Zutaten mischen", "Backofen auf 50 °C vorheizen, ausschalten und den Teig hineinstellen"]
        #expect(!isStarter(steps: steps, ingredients: feedingIngredients))
        #expect(isStarter(steps: steps, ingredients: feedingIngredients, tags: ["Anstellgut"]))
        #expect(isStarter(steps: steps, ingredients: feedingIngredients, tags: ["Fütterung"]))
        #expect(isStarter(steps: steps, ingredients: feedingIngredients, tags: ["ASG "]))
    }

    @Test("\"Sauerteig\" on a bread is a category, not an override; a tag never invents a ratio")
    func tagLimits() {
        #expect(!isStarter(steps: ["Bei 250 °C backen"], ingredients: breadIngredients, tags: ["Sauerteig"]))
        #expect(!isStarter(steps: ["Ansetzen"], ingredients: [("Wasser", 500)], tags: ["Anstellgut"]))
    }
}
