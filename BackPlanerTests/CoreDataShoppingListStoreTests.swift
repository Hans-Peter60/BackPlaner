//
//  CoreDataShoppingListStoreTests.swift
//  BackPlanerTests
//
//  The shopping list store contract, checked against Core Data in memory:
//  the same checks the in-memory store passes in the package, and the
//  SQLite store will pass on Android.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

// On the main actor: the context is the view context, a main-queue context.
@Suite("Shopping list store contract: Core Data")
@MainActor
struct CoreDataShoppingListStoreTests {

    private func newStores() -> (CoreDataShoppingListStore, CoreDataRecipeStore) {
        let context = PersistenceController(inMemory: true).container.viewContext
        return (CoreDataShoppingListStore(context: context), CoreDataRecipeStore(context: context))
    }

    @Test("Every check of the contract", arguments: ShoppingListStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(ShoppingListStoreContract.checks.first { $0.name == name })
        let (store, recipes) = newStores()
        try check.run(store, recipes)
    }

    @Test("An ingredient of a recipe is no line of a shopping list")
    func recipeIngredientsAreNotLines() throws {
        let (store, recipes) = newStores()
        _ = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let ingredient = try #require(try store.context.fetch(Ingredient.fetchRequest()).first)
        let key = ingredient.storeKey

        try store.deleteItem(id: key)
        #expect(!ingredient.isDeleted)
        #expect(throws: ShoppingListStoreError.unknownItem(key)) {
            try store.update(StoredShoppingListItem(id: key, name: "Hefe", unit: "g", weight: 1, normWeight: 1,
                                                    num: 0, denom: 0))
        }
    }

    @Test("A list written through the store reads the same in the shopping list screens")
    func sameAsCoreData() throws {
        let (store, recipes) = newStores()
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let list = try store.addList(on: Date(timeIntervalSince1970: 1_800_000_000))
        try store.add([ShoppingListEntry(name: "Weizenmehl 550", unit: "g", weight: 400, num: 0, denom: 0)],
                      from: .own(id: bread.id), toList: list.id)
        try store.add([], from: .publicRecipe(name: "Zopf"), toList: list.id)

        let cart = try #require(try store.context.fetch(ShoppingCart.fetchRequest()).first)
        #expect(cart.id != nil)
        #expect(cart.date == Date(timeIntervalSince1970: 1_800_000_000))
        #expect((cart.recipes as? Set<Recipe>)?.map(\.name) == ["Landbrot"])
        #expect(cart.cloudRecipeNamesArray == ["Zopf"])
        let line = try #require(cart.ingredientsArray.first)
        #expect(cart.ingredientsArray.count == 1)
        #expect(line.name == "Weizenmehl 550" && line.weight == 400 && line.unit == "g")
        #expect(line.id != nil && line.number == 0 && line.component == nil)
    }
}
