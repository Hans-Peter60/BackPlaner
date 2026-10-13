//
//  ShoppingListTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Shopping list: amounts at the chosen serving scale")
struct ShoppingListScalingTests {

    @Test("A weight is multiplied by the factor")
    func weightScales() {
        let scaled = ShoppingListAmount.scaled(weight: 500, num: 0, denom: 0, by: 2)
        #expect(scaled.weight == 1000)
        #expect(scaled.num == 0)
        #expect(scaled.denom == 0)
    }

    @Test("Factor 1 leaves everything untouched")
    func factorOneIsIdentity() {
        let scaled = ShoppingListAmount.scaled(weight: 0, num: 1, denom: 2, by: 1)
        #expect(scaled.weight == 0)
        #expect(scaled.num == 1)
        #expect(scaled.denom == 2)
    }

    @Test("A fraction stays a fraction at a half step", arguments: [
        // 1/2 Würfel ×2 = 1 Würfel; ×1.5 = 3/4; ×0.5 = 1/4
        (1, 2, 2.0, 1, 1),
        (1, 2, 1.5, 3, 4),
        (1, 2, 0.5, 1, 4),
        (3, 4, 2.0, 3, 2)
    ])
    func fractionAtHalfStep(num: Int, denom: Int, scale: Double, expectedNum: Int, expectedDenom: Int) {
        let scaled = ShoppingListAmount.scaled(weight: 0, num: num, denom: denom, by: scale)
        #expect(scaled.weight == 0)
        #expect(scaled.num == expectedNum)
        #expect(scaled.denom == expectedDenom)
    }

    @Test("At a free scale a fraction becomes a decimal amount")
    func fractionAtFreeScale() {
        let scaled = ShoppingListAmount.scaled(weight: 0, num: 1, denom: 2, by: 1.37)
        #expect(abs(scaled.weight - 0.685) < 0.0001)
        #expect(scaled.num == 0)
        #expect(scaled.denom == 0)
    }

    @Test("Eggs by weight are doubled before they become pieces")
    func eggsScaleThenCount() {
        // 120 g of eggs is two; at ×2 the list has to ask for four.
        let scaled = ShoppingListAmount.scaled(weight: 120, num: 0, denom: 0, by: 2)
        let amount = ShoppingListAmount.forShoppingList(name: "Eier", unit: "g", weight: scaled.weight, num: 0, denom: 0)
        #expect(amount.unit == ShoppingListAmount.pieceUnit)
        #expect(amount.weight == 4)
    }
}

@Suite("Shopping list: shelves")
struct ShoppingListCategoryTests {

    typealias Category = ShoppingListCategory

    @Test("Ingredients land on their shelf", arguments: [
        ("Weizenmehl 550",        Category.flourAndGrain),
        ("Roggenvollkornschrot",  Category.flourAndGrain),
        ("Haferflocken",          Category.flourAndGrain),
        ("Kartoffelstärke",       Category.flourAndGrain),
        ("Reis",                  Category.flourAndGrain),
        ("Semmelbrösel",          Category.flourAndGrain),
        ("Butter",                Category.dairyAndEggs),
        ("Eier",                  Category.dairyAndEggs),
        ("Ei(M)",                 Category.dairyAndEggs),
        ("Eigelb",                Category.dairyAndEggs),
        ("Buttermilch",           Category.dairyAndEggs),
        ("Magerquark",            Category.dairyAndEggs),
        ("Frische Hefe",          Category.bakingSupplies),
        ("Trockenhefe",           Category.bakingSupplies),
        ("Zucker",                Category.bakingSupplies),
        ("Vanillezucker",         Category.bakingSupplies),
        ("Honig",                 Category.bakingSupplies),
        ("Backmalz",              Category.bakingSupplies),
        ("Weinsteinbackpulver",   Category.bakingSupplies),
        ("Haselnüsse",            Category.nutsSeedsDriedFruit),
        ("Mandelmehl",            Category.nutsSeedsDriedFruit),
        ("Erdnussbutter",         Category.nutsSeedsDriedFruit),
        ("Sonnenblumenkerne",     Category.nutsSeedsDriedFruit),
        ("Leinsamen",             Category.nutsSeedsDriedFruit),
        ("Rosinen",               Category.nutsSeedsDriedFruit),
        ("Äpfel",                 Category.fruitAndVegetables),
        ("Zwiebeln",              Category.fruitAndVegetables),
        ("Kartoffeln",            Category.fruitAndVegetables),
        ("Zitronenschale",        Category.fruitAndVegetables),
        ("Preiselbeeren",         Category.fruitAndVegetables),
        ("Brotgewürz",            Category.spicesAndHerbs),
        ("Kümmel",                Category.spicesAndHerbs),
        ("Rosmarin",              Category.spicesAndHerbs),
        ("Olivenöl",              Category.fatsAndLiquids),
        ("Butterschmalz",         Category.fatsAndLiquids),
        ("Apfelessig",            Category.fatsAndLiquids),
        ("Bier",                  Category.fatsAndLiquids),
        ("Zitronensaft",          Category.fatsAndLiquids),
        ("Speck",                 Category.other),
        ("",                      Category.other)
    ])
    func classifies(name: String, expected: Category) {
        #expect(Category.category(for: name) == expected, "\(name)")
    }

    @Test("Shelves come in shop order, each sorted by name, empty ones left out")
    func shelvesAreOrdered() {
        let names = ["Zucker", "Butter", "Weizenmehl 550", "Hefe", "Äpfel", "Roggenmehl 1150"]
        let shelves = Category.shelves(names, name: { $0 })

        #expect(shelves.map(\.category) == [.flourAndGrain, .dairyAndEggs, .bakingSupplies, .fruitAndVegetables])
        #expect(shelves[0].items == ["Roggenmehl 1150", "Weizenmehl 550"])
        #expect(shelves[2].items == ["Hefe", "Zucker"])
    }
}
