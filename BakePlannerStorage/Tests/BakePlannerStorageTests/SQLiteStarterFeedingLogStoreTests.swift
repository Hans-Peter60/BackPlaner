//
//  SQLiteStarterFeedingLogStoreTests.swift
//  BakePlannerStorageTests
//
//  The starter feeding diary contract, checked against SQLite: the same
//  checks the in-memory store passes in BakePlannerCore and the Core Data
//  store in the iOS app. Runs on the Mac (swift test) and on Android
//  (skip android test).
//

import BakePlannerCore
import BakePlannerStorage
import Foundation
import Testing

@Suite("Starter feeding diary contract: SQLite")
struct SQLiteStarterFeedingLogStoreTests {

    @Test("Every check of the contract", arguments: StarterFeedingLogStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(StarterFeedingLogStoreContract.checks.first { $0.name == name })
        let recipes = try SQLiteRecipeStore(path: nil)
        defer { try? recipes.close() }
        try check.run(SQLiteStarterFeedingLogStore(file: recipes.file), recipes)
    }

    @Test("Feedings stay in the database file when it is closed and opened again")
    func persistence() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedings-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let firstRecipes = try SQLiteRecipeStore(path: path)
        let starter = try firstRecipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil,
                                           bakeHistoryFlag: false)
        let store = SQLiteStarterFeedingLogStore(file: firstRecipes.file)
        let failed = try store.add(toRecipe: starter.id, date: Date(timeIntervalSinceReferenceDate: 815_000_000.5),
                                   facts: StarterFeedingFacts(peakMinutes: 240, floatTestPassed: false, note: "träge"))
        let untested = try store.add(toRecipe: starter.id, date: Date(timeIntervalSinceReferenceDate: 815_100_000),
                                     facts: StarterFeedingFacts())
        try firstRecipes.close()

        let secondRecipes = try SQLiteRecipeStore(path: path)
        defer { try? secondRecipes.close() }
        #expect(try SQLiteStarterFeedingLogStore(file: secondRecipes.file).feedings(ofRecipe: starter.id)
                == [untested, failed])
    }
}
