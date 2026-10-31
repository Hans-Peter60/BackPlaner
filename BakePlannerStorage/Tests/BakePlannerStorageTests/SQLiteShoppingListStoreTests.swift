//
//  SQLiteShoppingListStoreTests.swift
//  BakePlannerStorageTests
//
//  The shopping list store contract, checked against SQLite: the same
//  checks the in-memory store passes in BakePlannerCore and the Core Data
//  store in the iOS app. Runs on the Mac (swift test) and on Android
//  (skip android test).
//

import BakePlannerCore
import BakePlannerStorage
import Foundation
import Testing

@Suite("Shopping list store contract: SQLite")
struct SQLiteShoppingListStoreTests {

    @Test("Every check of the contract", arguments: ShoppingListStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(ShoppingListStoreContract.checks.first { $0.name == name })
        let recipes = try SQLiteRecipeStore(path: nil)
        defer { try? recipes.close() }
        try check.run(SQLiteShoppingListStore(file: recipes.file), recipes)
    }

    @Test("Lists stay in the database file when it is closed and opened again")
    func persistence() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("lists-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let firstRecipes = try SQLiteRecipeStore(path: path)
        let firstLists = SQLiteShoppingListStore(file: firstRecipes.file)
        let bread = try firstRecipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil,
                                         bakeHistoryFlag: false)
        let list = try firstLists.addList(on: Date(timeIntervalSinceReferenceDate: 815_000_000.5))
        try firstLists.add([ShoppingListEntry(name: "Weizenmehl 550", unit: "g", weight: 400, num: 0, denom: 0)],
                           from: .own(id: bread.id), toList: list.id)
        try firstLists.add([], from: .publicRecipe(name: "Zopf"), toList: list.id)
        let written = try firstLists.list(id: list.id)
        try firstRecipes.close()

        let secondRecipes = try SQLiteRecipeStore(path: path)
        defer { try? secondRecipes.close() }
        let read = try SQLiteShoppingListStore(file: secondRecipes.file).list(id: list.id)
        #expect(read == written)
        #expect(read?.recipeNames == ["Landbrot", "Zopf"])
        #expect(read?.items.count == 1)
    }
}
