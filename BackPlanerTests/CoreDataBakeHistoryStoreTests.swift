//
//  CoreDataBakeHistoryStoreTests.swift
//  BackPlanerTests
//
//  The bake history store contract, checked against Core Data in memory:
//  the same checks the in-memory store passes in the package, and the
//  SQLite store will pass on Android.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

// On the main actor: the context is the view context, a main-queue context.
@Suite("Bake history store contract: Core Data")
@MainActor
struct CoreDataBakeHistoryStoreTests {

    private func newStores() -> (CoreDataBakeHistoryStore, CoreDataRecipeStore) {
        let context = PersistenceController(inMemory: true).container.viewContext
        return (CoreDataBakeHistoryStore(context: context), CoreDataRecipeStore(context: context))
    }

    @Test("Every check of the contract", arguments: BakeHistoryStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(BakeHistoryStoreContract.checks.first { $0.name == name })
        let (store, recipes) = newStores()
        try check.run(store, recipes)
    }

    @Test("Replacing or deleting a plan takes its untouched history entry, through the Core Data store")
    func plannedEntryGoesWithThePlan() throws {
        let (store, recipes) = newStores()
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let tomorrow = Date().addingTimeInterval(86_400)
        let placeholder = AppSettings.generatedRecipeTexts().missingComment
        _ = try store.add(toRecipe: bread.id, date: tomorrow, comment: placeholder, images: [], facts: BakeHistoryFacts())
        let kept = try store.add(toRecipe: bread.id, date: tomorrow, comment: "Mit Saaten probiert", images: [],
                                 facts: BakeHistoryFacts())

        let recipe = try #require(try store.context.fetch(Recipe.fetchRequest()).first)
        BakePlanScheduler.removePlannedBakeEntries(of: recipe, in: store.context)

        #expect(try store.entries(ofRecipe: bread.id, includingImages: false).map(\.id) == [kept.id])
    }

    @Test("An entry written through the store reads the same in the history screens")
    func sameAsCoreData() throws {
        let (store, recipes) = newStores()
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let facts = BakeHistoryFacts(roomTemperature: 22, bulkProofMinutes: 180, flour: "Roggen 1150")
        _ = try store.add(toRecipe: bread.id, date: Date(timeIntervalSince1970: 1_800_000_000), comment: "Gut",
                          images: [Data([1, 2])], facts: facts)

        let recipe = try #require(try store.context.fetch(Recipe.fetchRequest()).first)
        let history = try #require(recipe.bakeHistoriesArray.first)
        #expect(recipe.bakeHistoryFlag)
        #expect(history.id != nil)
        #expect(history.date == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(history.comment == "Gut")
        #expect(history.images == [Data([1, 2])])
        #expect(history.facts == facts)
        #expect(recipe.lastCompletedBakeHistory(now: Date(timeIntervalSince1970: 1_900_000_000)) == history)
    }

    @Test("An entry written when a bake is planned, without a UUID, is found by its key")
    func plannedEntry() throws {
        let (store, recipes) = newStores()
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let recipe = try #require(try store.context.fetch(Recipe.fetchRequest()).first)
        let history = BakeHistory(context: store.context)
        history.date = Date(timeIntervalSince1970: 1_800_000_000)
        history.comment = "—"
        recipe.addToBakeHistories(history)
        try store.context.save()

        let entries = try store.entries(ofRecipe: bread.id, includingImages: false)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(try store.entry(id: entry.id) == entry)
        try store.delete(id: entry.id)
        #expect(try store.entries(includingImages: false).isEmpty)
    }
}
