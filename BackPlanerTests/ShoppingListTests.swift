//
//  ShoppingListTests.swift
//  BackPlanerTests
//

import BakePlannerCore
import CoreData
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

    @Test("Water, salt and starters stay off the list in any language", arguments: [
        "Wasser", "Schüttwasser", "Wasser (lauwarm)", "water", "Mixing water", "eau", "eau tiède",
        "Salz", "Meersalz", "salt", "sea salt", "sel", "Anstellgut", "Anstellgut TA 150", "Sauerteig",
        "Roggensauerteig", "Sourdough starter", "levain", "Lievito Madre", "Poolish", "ASG"
    ])
    func notBought(name: String) {
        #expect(!ShoppingListAmount.belongsOnList(name: name), "\(name)")
    }

    @Test("Everything else is bought — including what merely sounds like water or salt", arguments: [
        "Weizenmehl 550", "Rosenwasser", "Kokosmilch", "salted butter", "Sellerie", "Sauerteigpulver",
        "Sauerteigextrakt", "Hefe", "Eier", "Milch", "Bier"
    ])
    func bought(name: String) {
        #expect(ShoppingListAmount.belongsOnList(name: name), "\(name)")
    }

    @Test("Eggs are counted by the piece in every language", arguments: ["Eier", "eggs", "œufs", "oeufs"])
    func eggsInAnyLanguage(name: String) {
        let amount = ShoppingListAmount.forShoppingList(name: name, unit: "g", weight: 120, num: 0, denom: 0)
        #expect(amount.unit == ShoppingListAmount.pieceUnit)
        #expect(amount.weight == 2)
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

/// A bread whose main dough takes over two of its components whole, as
/// "Sauerteigbrot mit Kartoffeln und Saaten" does.
private func potatoBread() -> RecipeExportData {
    func row(_ name: String, _ weight: Double, whole: Bool = false, number: Int) -> RecipeExportIngredient {
        RecipeExportIngredient(name: name, number: number, unit: whole ? nil : "g", weight: weight, normWeight: weight,
                               num: whole ? 1 : 0, denom: whole ? 1 : 0)
    }
    return RecipeExportData(
        name: "Sauerteigbrot mit Kartoffeln und Saaten", summary: "", urlLink: nil, prepTime: 0, totalWeight: 0,
        tags: [], rating: 0, recurrenceIntervalDays: 0, image: nil,
        components: [
            RecipeExportComponent(name: "Brühstück", number: 1, ingredients: [
                row("Saatenmischung", 125, number: 1),
            ]),
            RecipeExportComponent(name: "Kartoffeln (gekocht)", number: 2, ingredients: [
                row("Kartoffeln", 104, number: 1),
            ]),
            RecipeExportComponent(name: "Hauptteig", number: 3, ingredients: [
                row("Gesamte Kartoffeln (gekocht)", 0, whole: true, number: 1),
                row("Butter", 12, number: 2),
                row("Gesamtes Brühstück", 0, whole: true, number: 3),
            ]),
        ],
        instructions: [])
}

@Suite("Shopping list: rows that stand for another component")
struct ShoppingListComponentProductTests {

    @Test("A row taking over another component is not bought, the component's own ingredient is")
    func componentProduct() {
        let names = ["Brühstück", "Kartoffeln (gekocht)", "Hauptteig"]
        #expect(ShoppingListAmount.standsForAnotherComponent(name: "Gesamte Kartoffeln (gekocht)", weight: 0, num: 1, denom: 1,
                                                             componentIndex: 2, componentNames: names))
        #expect(!ShoppingListAmount.standsForAnotherComponent(name: "Kartoffeln", weight: 104, num: 0, denom: 0,
                                                              componentIndex: 1, componentNames: names))
        #expect(!ShoppingListAmount.standsForAnotherComponent(name: "Butter", weight: 12, num: 0, denom: 0,
                                                              componentIndex: 2, componentNames: names))
    }

    @Test("A public recipe puts each potato on the list once")
    func publicRecipe() {
        let recipe = RecipeFB()
        recipe.name = potatoBread().name
        recipe.components = potatoBread().components.map { component in
            let componentFB = ComponentFB()
            componentFB.name = component.name
            componentFB.number = component.number
            componentFB.ingredients = component.ingredients.map { ingredient in
                let ingredientFB = IngredientFB()
                ingredientFB.name = ingredient.name
                ingredientFB.number = ingredient.number
                ingredientFB.unit = ingredient.unit ?? ""
                ingredientFB.weight = ingredient.weight
                ingredientFB.num = ingredient.num
                ingredientFB.denom = ingredient.denom
                return ingredientFB
            }
            return componentFB
        }

        let entries = ShoppingCartSource.cloudRecipe(recipe).entries(in: "de").entries
        #expect(entries.map(\.name) == ["Saatenmischung", "Kartoffeln", "Butter"])
    }

    @Test("An own recipe puts each potato on the list once")
    @MainActor
    func ownRecipe() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let recipe = potatoBread().makeRecipe(in: context)
        try context.save()

        let entries = ShoppingCartSource.localRecipe(recipe).entries(in: "de").entries
        #expect(entries.map(\.name) == ["Saatenmischung", "Kartoffeln", "Butter"])
    }
}
