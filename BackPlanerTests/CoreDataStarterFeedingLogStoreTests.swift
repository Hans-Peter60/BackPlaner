//
//  CoreDataStarterFeedingLogStoreTests.swift
//  BackPlanerTests
//
//  The starter feeding diary contract, checked against Core Data in memory:
//  the same checks the in-memory store passes in the package, and the
//  SQLite store will pass on Android.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

// On the main actor: the context is the view context, a main-queue context.
@Suite("Starter feeding diary contract: Core Data")
@MainActor
struct CoreDataStarterFeedingLogStoreTests {

    private func newStores() -> (CoreDataStarterFeedingLogStore, CoreDataRecipeStore) {
        let context = PersistenceController(inMemory: true).container.viewContext
        return (CoreDataStarterFeedingLogStore(context: context), CoreDataRecipeStore(context: context))
    }

    @Test("Every check of the contract", arguments: StarterFeedingLogStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(StarterFeedingLogStoreContract.checks.first { $0.name == name })
        let (store, recipes) = newStores()
        try check.run(store, recipes)
    }

    @Test("A feeding written through the store reads the same in the diary and for Siri")
    func sameAsCoreData() throws {
        let (store, recipes) = newStores()
        let starter = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil,
                                      bakeHistoryFlag: false)
        let facts = StarterFeedingFacts(peakMinutes: 240, floatTestPassed: false, note: "träge")
        _ = try store.add(toRecipe: starter.id, date: Date(timeIntervalSince1970: 1_800_000_000), facts: facts)

        let recipe = try #require(try store.context.fetch(Recipe.fetchRequest()).first)
        let feeding = try #require(StarterFeedingStore.lastFeeding(of: recipe))
        #expect(feeding.id != nil)
        #expect(feeding.date == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(feeding.facts == facts)
        #expect(feeding.peakMinutes?.intValue == 240)
        #expect(feeding.floatTestPassed?.boolValue == false)
    }
}
