//
//  SQLiteRecipeStoreTests.swift
//  BakePlannerStorageTests
//
//  The recipe store contract, checked against SQLite: the same checks the
//  in-memory store passes in BakePlannerCore and the Core Data store in the
//  iOS app. Runs on the Mac (swift test) and on Android (skip android test).
//

import BakePlannerCore
import BakePlannerStorage
import Foundation
import Testing

@Suite("Recipe store contract: SQLite")
struct SQLiteRecipeStoreTests {

    @Test("Every check of the contract", arguments: RecipeStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(RecipeStoreContract.checks.first { $0.name == name })
        let store = try SQLiteRecipeStore(path: nil)
        defer { try? store.close() }
        try check.run(store)
    }

    @Test("Recipes stay in the database file when it is closed and opened again")
    func persistence() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("recipes-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = try SQLiteRecipeStore(path: path)
        let added = try first.add(RecipeStoreContract.bread(), firestoreId: "public-1",
                                  adjustedOn: Date(timeIntervalSinceReferenceDate: 812_345_678.25), bakeHistoryFlag: true)
        try first.close()

        let second = try SQLiteRecipeStore(path: path)
        defer { try? second.close() }
        #expect(try second.recipe(id: added.id) == added)
        #expect(try second.recipes(includingImages: false).count == 1)
    }

    @Test("A backup file reads into SQLite as into any other store")
    func backup() throws {
        let store = try SQLiteRecipeStore(path: nil)
        defer { try? store.close() }
        let data = try RecipeExportFile(recipes: [RecipeStoreContract.bread()]).encoded()
        #expect(try RecipeImport.importFile(data, into: store, bakeHistory: SQLiteBakeHistoryStore(file: store.file)) == 1)
        let file = try RecipeExportFile(recipeIDs: store.recipes(includingImages: false).map(\.id), from: store)
        #expect(file.recipes == [RecipeStoreContract.bread()])
    }
}
