//
//  InMemoryStarterFeedingLogStore.swift
//  BakePlannerCore
//
//  A StarterFeedingLogStore that keeps everything in memory, next to a
//  RecipeStore: the reference the contract is checked against first, and a
//  stand-in for tests.
//

import Foundation

public final class InMemoryStarterFeedingLogStore: StarterFeedingLogStore {

    private let recipes: RecipeStore
    private var stored: [String: StoredStarterFeeding] = [:]
    private var nextID = 1

    /// `recipes` is the store the feedings' recipes are kept in.
    public init(recipes: RecipeStore) {
        self.recipes = recipes
    }

    public func feedings(ofRecipe recipeID: String) throws -> [StoredStarterFeeding] {
        // A recipe removed takes its feedings along, as Core Data's cascade
        // rule has it.
        guard try recipes.recipe(id: recipeID) != nil else { return [] }
        return stored.values
            .filter { $0.recipeID == recipeID }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
    }

    public func add(toRecipe recipeID: String, date: Date, facts: StarterFeedingFacts) throws -> StoredStarterFeeding {
        guard try recipes.recipe(id: recipeID) != nil else {
            throw StarterFeedingLogStoreError.unknownRecipe(recipeID)
        }
        let feeding = StoredStarterFeeding(id: "memory-feeding-\(nextID)", recipeID: recipeID, date: date,
                                           facts: facts.normalized)
        nextID += 1
        stored[feeding.id] = feeding
        return feeding
    }

    public func delete(id: String) throws {
        stored[id] = nil
    }
}
