//
//  SQLiteBakeHistoryStoreTests.swift
//  BakePlannerStorageTests
//
//  The bake history store contract, checked against SQLite: the same checks
//  the in-memory store passes in BakePlannerCore and the Core Data store in
//  the iOS app. Runs on the Mac (swift test) and on Android
//  (skip android test).
//

import BakePlannerCore
import BakePlannerStorage
import Foundation
import Testing

@Suite("Bake history store contract: SQLite")
struct SQLiteBakeHistoryStoreTests {

    @Test("Every check of the contract", arguments: BakeHistoryStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(BakeHistoryStoreContract.checks.first { $0.name == name })
        let recipes = try SQLiteRecipeStore(path: nil)
        defer { try? recipes.close() }
        try check.run(SQLiteBakeHistoryStore(file: recipes.file), recipes)
    }

    @Test("Entries stay in the database file when it is closed and opened again")
    func persistence() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let firstRecipes = try SQLiteRecipeStore(path: path)
        let bread = try firstRecipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil,
                                         bakeHistoryFlag: false)
        let facts = BakeHistoryFacts(roomTemperature: 21.5, doughTemperature: 0, finalProofMinutes: 50,
                                     outcome: "offen")
        let added = try SQLiteBakeHistoryStore(file: firstRecipes.file)
            .add(toRecipe: bread.id, date: Date(timeIntervalSinceReferenceDate: 815_000_000.5), comment: "Gut",
                 images: [Data([1, 2, 3]), Data([4])], facts: facts)
        try firstRecipes.close()

        let secondRecipes = try SQLiteRecipeStore(path: path)
        defer { try? secondRecipes.close() }
        #expect(try SQLiteBakeHistoryStore(file: secondRecipes.file).entry(id: added.id) == added)
        #expect(try secondRecipes.recipe(id: bread.id)?.bakeHistoryFlag == true)
    }
}
