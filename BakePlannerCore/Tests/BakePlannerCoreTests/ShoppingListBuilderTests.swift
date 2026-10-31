//
//  ShoppingListBuilderTests.swift
//  BakePlannerCoreTests
//
//  Putting a recipe on a shopping list: what is bought, at which amount,
//  and how it joins the lines already there. No unit conversions: on
//  Apple platforms the unit table comes from the app bundle, which the
//  package's test runner does not have.
//

import Testing
@testable import BakePlannerCore

private func entry(_ name: String, _ weight: Double, unit: String = "g", num: Int = 0, denom: Int = 0) -> ShoppingListEntry {
    ShoppingListEntry(name: name, unit: unit, weight: weight, num: num, denom: denom)
}

private func line(_ key: String?, _ name: String, _ weight: Double, unit: String? = "g",
                  num: Int = 0, denom: Int = 0) -> ShoppingListLine {
    ShoppingListLine(key: key, name: name, unit: unit, weight: weight, normWeight: weight, num: num, denom: denom)
}

@Suite("Shopping list: building the list")
struct ShoppingListBuilderTests {

    @Test("Water, salt, starters and rows without amount or unit stay off the list")
    func sifting() {
        let entries = [entry("Weizenmehl 550", 500), entry("Wasser", 350), entry("Salz", 10),
                       entry("Anstellgut", 100), entry("Butter", 0), entry("Hefe", 5, unit: " ")]
        let bought = ShoppingListBuilder.entriesToBuy(entries, scale: 1)
        #expect(bought.map(\.name) == ["Weizenmehl 550"])
    }

    @Test("Amounts are scaled before they are sifted")
    func scaling() {
        let bought = ShoppingListBuilder.entriesToBuy([entry("Roggenmehl", 250)], scale: 2)
        #expect(bought == [entry("Roggenmehl", 500)])
    }

    // Eggs by weight become pieces only where the unit table says "g" is a
    // weight; that case is tested in the app (ShoppingListTests).
    @Test("Eggs go on the list by the piece, at the chosen scale")
    func eggsAsPieces() {
        let bought = ShoppingListBuilder.entriesToBuy([entry("Eier", 2, unit: "St")], scale: 2)
        let lines = ShoppingListBuilder.adding(bought, to: [])
        #expect(lines.count == 1)
        #expect(lines[0].unit == ShoppingListAmount.pieceUnit)
        #expect(lines[0].weight == 4)
        #expect(lines[0].key == nil)
    }

    @Test("An ingredient already on the list is added to, under its shown name")
    func mergesIntoExistingLine() {
        let lines = ShoppingListBuilder.adding([entry("Butter, zimmerwarm", 12)],
                                               to: [line("a", "Butter", 100), line("b", "Mehl", 500)])
        #expect(lines.count == 2)
        let butter = lines.first { $0.key == "a" }
        #expect(butter?.name == "Butter")
        #expect(butter?.weight == 112)
        #expect(butter?.normWeight == 112)
    }

    @Test("A new ingredient gets a line of its own at the end")
    func newLine() {
        let lines = ShoppingListBuilder.adding([entry("Zucker", 50)], to: [line("a", "Mehl", 500)])
        #expect(lines.map(\.key) == ["a", nil])
        #expect(lines[1].name == "Zucker")
        #expect(lines[1].normWeight == 50)
    }

    @Test("Fractions are added and reduced")
    func fractions() {
        let lines = ShoppingListBuilder.adding([entry("Hefe", 0, unit: "Würfel", num: 1, denom: 4)],
                                               to: [line("a", "Hefe", 0, unit: "Würfel", num: 1, denom: 2)])
        #expect(lines.count == 1)
        #expect(lines[0].num == 3)
        #expect(lines[0].denom == 4)
    }

    @Test("Lines of the same ingredient and unit are brought together first")
    func harmonizing() {
        let lines = ShoppingListBuilder.adding([], to: [line("a", "Butter", 100), line("b", "butter", 50),
                                                         line("c", "Butter", 2, unit: "EL")])
        #expect(lines.count == 2)
        let grams = lines.first { $0.unit == "g" }
        #expect(grams?.key == "a")
        #expect(grams?.weight == 150)
        #expect(lines.contains { $0.key == "c" && $0.weight == 2 })
    }

    @Test("Lines are taken in name order, whatever order the store hands them over")
    func nameOrder() {
        let lines = ShoppingListBuilder.adding([], to: [line("z", "Zucker", 1), line("m", "Mehl", 1)])
        #expect(lines.map(\.key) == ["m", "z"])
    }

    @Test("A recipe's rows that stand for another component are not bought")
    func recipeEntries() {
        func row(_ name: String, _ weight: Double, whole: Bool = false, number: Int) -> RecipeExportIngredient {
            RecipeExportIngredient(name: name, number: number, unit: whole ? nil : "g", weight: weight,
                                   normWeight: weight, num: whole ? 1 : 0, denom: whole ? 1 : 0)
        }
        let recipe = RecipeExportData(
            name: "Kartoffelbrot", summary: "", urlLink: nil, prepTime: 0, totalWeight: 0,
            tags: [], rating: 0, recurrenceIntervalDays: 0, image: nil,
            components: [
                RecipeExportComponent(name: "Kartoffeln (gekocht)", number: 1, ingredients: [
                    row("Kartoffeln", 104, number: 1),
                ]),
                RecipeExportComponent(name: "Hauptteig", number: 2, ingredients: [
                    row("Gesamte Kartoffeln (gekocht)", 0, whole: true, number: 1),
                    row("Butter", 12, number: 2),
                ]),
            ],
            instructions: [])
        let entries = ShoppingListBuilder.entries(of: recipe)
        #expect(entries.map(\.name) == ["Kartoffeln", "Butter"])
        #expect(entries[0].unit == "g")
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
