//
//  CoreDataRecipeStoreTests.swift
//  BackPlanerTests
//
//  The recipe store contract, checked against Core Data in memory: the
//  same checks the in-memory store passes in the package, and the SQLite
//  store will pass on Android.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

// On the main actor: the context is the view context, a main-queue context.
@Suite("Recipe store contract: Core Data")
@MainActor
struct CoreDataRecipeStoreTests {

    private func newStore() -> CoreDataRecipeStore {
        CoreDataRecipeStore(context: PersistenceController(inMemory: true).container.viewContext)
    }

    @Test("Every check of the contract", arguments: RecipeStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(RecipeStoreContract.checks.first { $0.name == name })
        try check.run(newStore())
    }

    @Test("A recipe written through the store reads the same through Core Data")
    func sameAsCoreData() throws {
        let store = newStore()
        let added = try store.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let recipes = try store.context.fetch(Recipe.fetchRequest())
        let recipe = try #require(recipes.first)
        #expect(recipes.count == 1)
        #expect(RecipeExportData(recipe: recipe) == added.content)
        #expect(recipe.id != nil)
    }

    @Test("Changing only the name leaves components and steps as they were")
    func untouchedParts() throws {
        let store = newStore()
        var added = try store.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let recipe = try #require(try store.context.fetch(Recipe.fetchRequest()).first)
        let componentIDs = Set(recipe.componentsArray.map(\.objectID))
        let instructionIDs = Set(recipe.instructionsArray.map(\.objectID))

        added.content.name = "Bauernbrot"
        try store.update(added)

        #expect(recipe.name == "Bauernbrot")
        #expect(Set(recipe.componentsArray.map(\.objectID)) == componentIDs)
        #expect(Set(recipe.instructionsArray.map(\.objectID)) == instructionIDs)
    }
}
