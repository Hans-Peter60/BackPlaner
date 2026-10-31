//
//  InMemoryBakeHistoryStore.swift
//  BakePlannerCore
//
//  A BakeHistoryStore that keeps everything in memory, next to a
//  RecipeStore: the reference the contract is checked against first, and a
//  stand-in for tests.
//

import Foundation

public final class InMemoryBakeHistoryStore: BakeHistoryStore {

    private let recipes: RecipeStore
    private var stored: [String: StoredBakeHistory] = [:]
    private var nextID = 1

    /// `recipes` is the store the entries' recipes are kept in.
    public init(recipes: RecipeStore) {
        self.recipes = recipes
    }

    public func entries(includingImages: Bool) throws -> [StoredBakeHistory] {
        try live().map { includingImages ? $0 : withoutImages($0) }
    }

    public func entries(ofRecipe recipeID: String, includingImages: Bool) throws -> [StoredBakeHistory] {
        try entries(includingImages: includingImages).filter { $0.recipeID == recipeID }
    }

    public func entry(id: String) throws -> StoredBakeHistory? {
        try live().first { $0.id == id }
    }

    public func add(toRecipe recipeID: String, date: Date, comment: String, images: [Data],
                    facts: BakeHistoryFacts) throws -> StoredBakeHistory {
        guard var recipe = try recipes.recipe(id: recipeID) else {
            throw BakeHistoryStoreError.unknownRecipe(recipeID)
        }
        let entry = StoredBakeHistory(id: "memory-bake-\(nextID)", recipeID: recipeID, date: date, comment: comment,
                                      images: images, facts: facts.normalized)
        nextID += 1
        stored[entry.id] = entry
        if !recipe.bakeHistoryFlag {
            recipe.bakeHistoryFlag = true
            try recipes.update(recipe)
        }
        return entry
    }

    public func update(_ entry: StoredBakeHistory) throws {
        guard let existing = try self.entry(id: entry.id) else {
            throw BakeHistoryStoreError.unknownEntry(entry.id)
        }
        var updated = entry
        updated.recipeID = existing.recipeID
        updated.facts = entry.facts.normalized
        stored[entry.id] = updated
    }

    public func delete(id: String) throws {
        stored[id] = nil
    }

    // MARK: Helpers

    /// The entries whose recipe still exists — removing a recipe removes
    /// its history, as Core Data's cascade rule has it — newest first.
    private func live() throws -> [StoredBakeHistory] {
        try stored.values
            .filter { try recipes.recipe(id: $0.recipeID) != nil }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
    }

    private func withoutImages(_ entry: StoredBakeHistory) -> StoredBakeHistory {
        var entry = entry
        entry.images = []
        return entry
    }
}
