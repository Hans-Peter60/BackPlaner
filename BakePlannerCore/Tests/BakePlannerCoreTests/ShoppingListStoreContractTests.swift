//
//  ShoppingListStoreContractTests.swift
//  BakePlannerCoreTests
//
//  The shopping list store contract, checked against the in-memory store.
//  The Core Data and SQLite stores run the same checks.
//

import BakePlannerCore
import Testing

@Suite("Shopping list store contract: in memory")
struct InMemoryShoppingListStoreTests {

    @Test("Every check of the contract", arguments: ShoppingListStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(ShoppingListStoreContract.checks.first { $0.name == name })
        let recipes = InMemoryRecipeStore()
        try check.run(InMemoryShoppingListStore(recipes: recipes), recipes)
    }
}
